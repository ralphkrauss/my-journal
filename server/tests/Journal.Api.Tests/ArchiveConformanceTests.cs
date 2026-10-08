using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Journal.Api.Security;
using Microsoft.Data.Sqlite;

namespace Journal.Api.Tests;

// An independent reader of the .journalarchive package (protocol/archive.md) checked against
// protocol/conformance/archive/v1: header, password, authenticated manifest, file hashes, the database as SQLite
// reads it, and the damage a reader must refuse or ignore.
public sealed class ArchiveConformanceTests
{
    private const string Root = "archive/v1";

    private sealed record Opened(string? Refusal, byte[]? VaultKey = null);

    private static JsonDocument Expected() => ConformanceFiles.Json($"{Root}/expected.json");

    private static string Directory(string name) => ConformanceFiles.Path($"{Root}/{name}");

    private static Opened Refused(string reason) => new(reason);

    private static string Sha256(string file) => Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(file)));

    // The credentials a password opens an envelope with: formats 2 and 3 use its NFC form first and, when that differs
    // from what was typed, the exact text; format 1 trims. Nothing else is tried.
    private static IEnumerable<string> PasswordCandidates(int formatVersion, string typed)
    {
        if (formatVersion == 1)
        {
            yield return typed.Trim();
            yield break;
        }
        var normalized = typed.Normalize(NormalizationForm.FormC);
        yield return normalized;
        if (!string.Equals(normalized, typed, StringComparison.Ordinal))
        {
            yield return typed;
        }
    }

    private static byte[]? UnwrapVaultKey(JsonElement recovery, string password)
    {
        var format = recovery.GetProperty("formatVersion").GetInt32();
        var salt = Convert.FromBase64String(recovery.GetProperty("salt").GetString()!);
        var iterations = recovery.GetProperty("iterations").GetInt32();
        var wrapped = Convert.FromBase64String(recovery.GetProperty("wrappedKey").GetString()!);
        foreach (var candidate in PasswordCandidates(format, password))
        {
            var wrappingKey = Rfc2898DeriveBytes.Pbkdf2(Encoding.UTF8.GetBytes(candidate), salt, iterations, HashAlgorithmName.SHA256, 32);
            try
            {
                return ConformanceCrypto.Open(wrappingKey, wrapped, $"journal:v{format}:recovery");
            }
            catch (CryptographicException)
            {
            }
        }
        return null;
    }

    // Opens the header, recovers the vault key, authenticates or decodes the manifest and checks every file
    // against it. Names in attachments/ that start with a dot and other top-level files are ignored.
    private static Opened Open(string directory, string? password)
    {
        var headerFile = Path.Combine(directory, "archive.json");
        if (!File.Exists(headerFile) || new FileInfo(headerFile).Length > 16 << 20)
        {
            return Refused("no usable header");
        }
        using var header = JsonDocument.Parse(File.ReadAllBytes(headerFile));
        var recovery = header.RootElement.GetProperty("recovery");
        var format = recovery.GetProperty("formatVersion").GetInt32();
        var expectedVersion = format switch
        {
            >= 1 and <= 3 => 1,
            4 => 2,
            _ => 0,
        };
        if (header.RootElement.GetProperty("version").GetInt32() != expectedVersion || expectedVersion == 0)
        {
            return Refused("the header version doesn't match the envelope");
        }
        var manifestBytes = Convert.FromBase64String(header.RootElement.GetProperty("manifest").GetString()!);
        byte[]? vaultKey = null;
        if (expectedVersion == 1)
        {
            vaultKey = UnwrapVaultKey(recovery, password ?? "");
            if (vaultKey is null)
            {
                return Refused("the password doesn't open the envelope");
            }
            try
            {
                manifestBytes = ConformanceCrypto.Open(vaultKey, manifestBytes, "journal:v1:archive");
            }
            catch (CryptographicException)
            {
                return Refused("the manifest doesn't authenticate");
            }
        }
        using var manifest = JsonDocument.Parse(manifestBytes);
        var mismatch = FilesDiffer(directory, manifest.RootElement);
        return mismatch is null ? new Opened(null, vaultKey) : Refused(mismatch);
    }

    private static string? FilesDiffer(string directory, JsonElement manifest)
    {
        var database = Path.Combine(directory, "journal.sqlite");
        if (!File.Exists(database) || Sha256(database) != manifest.GetProperty("database").GetString())
        {
            return "the database doesn't match the manifest";
        }
        var listed = manifest.GetProperty("attachments").EnumerateObject().ToDictionary(member => member.Name, member => member.Value.GetString());
        var folder = Path.Combine(directory, "attachments");
        var found = new Dictionary<string, string>();
        foreach (var entry in System.IO.Directory.Exists(folder) ? new DirectoryInfo(folder).GetFileSystemInfos().Where(info => !info.Name.StartsWith('.')) : [])
        {
            if (entry is not FileInfo { LinkTarget: null } || entry.Name.Any(char.IsAsciiLetterUpper) || !ConformanceFormats.IsUuid(entry.Name))
            {
                return $"attachments/{entry.Name} isn't a regular file named by a lower-case UUID";
            }
            found[entry.Name] = Sha256(entry.FullName);
        }
        return listed.Count == found.Count && listed.All(item => found.TryGetValue(item.Key, out var hash) && hash == item.Value)
            ? null
            : "the images don't match the manifest";
    }

    // The decrypted text of a stored payload: base64 of the sealed record, or of the plain record without a key.
    private static string Plaintext(string payload, byte[]? vaultKey, string kind, string id)
    {
        Assert.True(Secrets.IsBase64(payload, 0, 1 << 24), "payloads are canonical base64");
        var bytes = Convert.FromBase64String(payload);
        return Encoding.UTF8.GetString(vaultKey is null ? bytes : ConformanceCrypto.Open(vaultKey, bytes, $"journal:v1:record:{kind}:{id}"));
    }

    private static string Text(object value) => value is byte[] bytes ? Encoding.UTF8.GetString(bytes) : (string)value;

    private static List<string> Rows(SqliteConnection connection, string query, Func<SqliteDataReader, string> row)
    {
        using var command = connection.CreateCommand();
        command.CommandText = query;
        using var reader = command.ExecuteReader();
        var rows = new List<string>();
        while (reader.Read())
        {
            rows.Add(row(reader));
        }
        return rows;
    }

    private static List<string> Strings(JsonElement array, Func<JsonElement, string> row) => array.EnumerateArray().Select(row).ToList();

    private static void AssertDatabase(string directory, JsonElement expected, byte[]? vaultKey)
    {
        var original = Path.Combine(directory, "journal.sqlite");
        var header = File.ReadAllBytes(original).AsSpan(0, 20);
        Assert.True(header[18] == 1 && header[19] == 1, "the database is in rollback-journal mode");

        var copy = Path.Combine(Path.GetTempPath(), "archive-conformance-" + Guid.NewGuid().ToString("N") + ".sqlite");
        File.Copy(original, copy);
        try
        {
            using var connection = new SqliteConnection($"Data Source={copy};Mode=ReadOnly;Pooling=False");
            connection.Open();
            Assert.Equal(
                Strings(expected.GetProperty("records"), item => $"{item.GetProperty("id").GetString()}|{item.GetProperty("kind").GetString()}|{item.GetProperty("revision").GetInt64()}|{item.GetProperty("dirty").GetInt64()}|{item.GetProperty("plaintext").GetString()}"),
                Rows(connection, "SELECT id, kind, payload, revision, dirty FROM records ORDER BY id", reader => $"{reader.GetString(0)}|{reader.GetString(1)}|{reader.GetInt64(3)}|{reader.GetInt64(4)}|{Plaintext(reader.GetString(2), vaultKey, reader.GetString(1), reader.GetString(0))}"));
            Assert.Equal(
                Strings(expected.GetProperty("outbox"), item => $"{item.GetProperty("operation").GetString()}|{item.GetProperty("record").GetString()}|{item.GetProperty("kind").GetString()}|{item.GetProperty("base").GetInt64()}|{item.GetProperty("plaintext").GetString()}"),
                Rows(connection, "SELECT operation, record, kind, payload, base FROM outbox ORDER BY operation", reader => $"{reader.GetString(0)}|{reader.GetString(1)}|{reader.GetString(2)}|{reader.GetInt64(4)}|{Plaintext(reader.GetString(3), vaultKey, reader.GetString(2), reader.GetString(1))}"));
            Assert.Equal(
                Strings(expected.GetProperty("history"), item => $"{item.GetProperty("record").GetString()}|{item.GetProperty("kind").GetString()}|{item.GetProperty("checkpoint").GetInt64()}|{item.GetProperty("plaintext").GetString()}"),
                Rows(connection, "SELECT record, kind, payload, checkpoint FROM history ORDER BY id", reader => $"{reader.GetString(0)}|{reader.GetString(1)}|{reader.GetInt64(3)}|{Plaintext(reader.GetString(2), vaultKey, reader.GetString(1), reader.GetString(0))}"));
            AssertSettings(Rows(connection, "SELECT key, value FROM settings ORDER BY key", reader => $"{reader.GetString(0)}={Text(reader.GetValue(1))}"), expected.GetProperty("settings"), vaultKey);
            Assert.Equal(
                Strings(expected.GetProperty("migrations"), item => item.GetString()!),
                Rows(connection, "SELECT identifier FROM grdb_migrations ORDER BY rowid", reader => reader.GetString(0)));
            Assert.Equal(
                Strings(expected.GetProperty("attachments"), item => $"{item.GetProperty("id").GetString()}|{item.GetProperty("uploaded").GetInt64()}|{item.GetProperty("bytes").GetInt64()}|{item.GetProperty("sha256").GetString()}"),
                Rows(connection, "SELECT id, uploaded FROM attachments ORDER BY id", reader => $"{reader.GetString(0)}|{reader.GetInt64(1)}|{Image(directory, reader.GetString(0), vaultKey)}"));
        }
        finally
        {
            File.Delete(copy);
        }
    }

    // Every listed setting is present as listed. The database also holds the unsent library changes (the dirty library
    // record has an outbox row), which expected.json doesn't list: they must read as the documented JSON.
    private static void AssertSettings(List<string> stored, JsonElement expected, byte[]? vaultKey)
    {
        var listed = Strings(expected, item => $"{item.GetProperty("key").GetString()}={item.GetProperty("value").GetString()}");
        Assert.All(listed, setting => Assert.Contains(setting, stored));
        const string key = "library-changes=";
        var changes = stored.SingleOrDefault(setting => setting.StartsWith(key, StringComparison.Ordinal));
        if (changes is null)
        {
            return;
        }
        var bytes = Convert.FromBase64String(changes[key.Length..]);
        var json = vaultKey is null ? bytes : ConformanceCrypto.Open(vaultKey, bytes, "journal:v1:local:library-changes");
        using var document = JsonDocument.Parse(json);
        Assert.Equal(1, document.RootElement.GetProperty("version").GetInt32());
        Assert.Equal(JsonValueKind.Object, document.RootElement.GetProperty("changes").ValueKind);
    }

    // The decrypted image: its size and SHA-256.
    private static string Image(string directory, string id, byte[]? vaultKey)
    {
        var stored = File.ReadAllBytes(Path.Combine(directory, "attachments", id));
        var image = vaultKey is null ? stored : ConformanceCrypto.Open(vaultKey, stored, $"journal:v1:attachment:{id}");
        return $"{image.Length}|{Convert.ToHexStringLower(SHA256.HashData(image))}";
    }

    private static void AssertArchive(string name, string? password)
    {
        using var corpus = Expected();
        var expected = corpus.RootElement.GetProperty("archives").GetProperty(name);
        var directory = Directory(name);
        var opened = Open(directory, password);
        Assert.True(opened.Refusal is null, opened.Refusal);
        using var header = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(directory, "archive.json")));
        Assert.Equal(expected.GetProperty("headerVersion").GetInt32(), header.RootElement.GetProperty("version").GetInt32());
        Assert.Equal(expected.GetProperty("formatVersion").GetInt32(), header.RootElement.GetProperty("recovery").GetProperty("formatVersion").GetInt32());
        AssertManifest(directory, expected.GetProperty("manifest"));
        AssertDatabase(directory, expected, opened.VaultKey);
    }

    // What the header's manifest holds once opened is what the corpus lists.
    private static void AssertManifest(string directory, JsonElement expected)
    {
        Assert.Equal(expected.GetProperty("database").GetString(), Sha256(Path.Combine(directory, "journal.sqlite")));
        foreach (var image in expected.GetProperty("attachments").EnumerateObject())
        {
            Assert.Equal(image.Value.GetString(), Sha256(Path.Combine(directory, "attachments", image.Name)));
        }
    }

    [Fact]
    public void EncryptedArchiveOpensWithThePasswordAndEveryRowDecryptsAsListed()
    {
        using var corpus = Expected();
        var password = corpus.RootElement.GetProperty("archives").GetProperty("encrypted").GetProperty("password").GetString();
        using var vectors = ConformanceFiles.Json("crypto/encryption-v2.json");
        var recovery = vectors.RootElement.GetProperty("recovery");
        Assert.Equal(recovery.GetProperty("password").GetString(), password);
        var opened = Open(Directory("encrypted"), password);
        Assert.True(opened.Refusal is null, opened.Refusal);
        Assert.Equal(recovery.GetProperty("vaultKey").GetBytesFromBase64(), opened.VaultKey);
        AssertArchive("encrypted", password);
        Assert.NotNull(Open(Directory("encrypted"), password!.Trim()).Refusal);
    }

    [Fact]
    public void PlaintextArchiveReadsWithoutAPasswordAndItsPayloadsAreTheRecords()
    {
        AssertArchive("plaintext", null);
    }

    [Fact]
    public void DamagedArchivesAreRefusedAndSystemFilesAreIgnored()
    {
        using var corpus = Expected();
        var password = corpus.RootElement.GetProperty("archives").GetProperty("encrypted").GetProperty("password").GetString();
        var failures = new List<string>();
        foreach (var mutation in corpus.RootElement.GetProperty("mutations").EnumerateArray())
        {
            var copy = Path.Combine(Path.GetTempPath(), "archive-conformance-" + Guid.NewGuid().ToString("N"));
            try
            {
                CopyDirectory(Directory("encrypted"), copy);
                foreach (var operation in mutation.GetProperty("ops").EnumerateArray())
                {
                    Apply(copy, operation);
                }
                var refused = Open(copy, password).Refusal is not null;
                var result = mutation.GetProperty("result").GetString();
                if (refused != (result == "refused"))
                {
                    failures.Add($"{mutation.GetProperty("name").GetString()}: {(refused ? "refused" : "restored")}, expected {result}");
                }
            }
            finally
            {
                System.IO.Directory.Delete(copy, true);
            }
        }
        Assert.True(failures.Count == 0, string.Join(Environment.NewLine, failures));
    }

    private static void CopyDirectory(string source, string destination)
    {
        System.IO.Directory.CreateDirectory(destination);
        foreach (var file in System.IO.Directory.GetFiles(source))
        {
            File.Copy(file, Path.Combine(destination, Path.GetFileName(file)));
        }
        foreach (var folder in System.IO.Directory.GetDirectories(source))
        {
            CopyDirectory(folder, Path.Combine(destination, Path.GetFileName(folder)));
        }
    }

    private static void Apply(string directory, JsonElement operation)
    {
        var file = operation.TryGetProperty("file", out var name) ? Path.Combine(directory, name.GetString()!) : null;
        switch (operation.GetProperty("op").GetString())
        {
            case "flipByte":
                var bytes = File.ReadAllBytes(file!);
                bytes[operation.GetProperty("offset").GetInt32()] ^= 1;
                File.WriteAllBytes(file!, bytes);
                break;
            case "delete":
                File.Delete(file!);
                break;
            case "add":
                File.WriteAllText(file!, operation.GetProperty("text").GetString());
                break;
            case "setHeaderVersion":
                var headerFile = Path.Combine(directory, "archive.json");
                var header = JsonNode.Parse(File.ReadAllText(headerFile))!;
                header["version"] = operation.GetProperty("version").GetInt32();
                File.WriteAllText(headerFile, header.ToJsonString());
                break;
            default:
                throw new InvalidDataException($"Unknown mutation {operation}.");
        }
    }
}
