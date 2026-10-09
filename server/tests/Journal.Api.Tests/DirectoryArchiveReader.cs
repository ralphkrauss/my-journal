using System.Security.Cryptography;
using System.Text.Json;
using Journal.Api.Security;

namespace Journal.Api.Tests;

// An independent reader of the directory archive (protocol/archive.md, Directory archive): header, password,
// authenticated manifest, and exactly the files the manifest lists. It never creates, writes or deletes anything.
internal static class DirectoryArchiveReader
{
    private sealed record Manifest(string Database, Dictionary<string, string> Attachments);

    public sealed record Opened(ArchiveOutcome Outcome, string? Refusal, byte[]? VaultKey = null);

    public static Opened Open(string directory, string? password)
    {
        try
        {
            return Read(directory, password);
        }
        catch (ArchiveRefusal refusal)
        {
            return new Opened(refusal.Outcome, refusal.Message);
        }
    }

    private static Opened Read(string directory, string? password)
    {
        var headerFile = new FileInfo(Path.Combine(directory, "archive.json"));
        if (headerFile.LinkTarget is not null || !headerFile.Exists || headerFile.Length > ZipContainerReader.MaximumHeaderBytes)
        {
            throw ArchiveRefusal.Damaged("there is no usable archive.json");
        }
        using var header = ArchiveStrictJson.Parse(File.ReadAllBytes(headerFile.FullName), "archive.json");
        var root = header.RootElement;
        if (root.ValueKind != JsonValueKind.Object || root.TryGetProperty("archiveVersion", out _))
        {
            throw ArchiveRefusal.Damaged("archive.json is not the header of a directory archive");
        }
        var version = ReadInteger(root, "version");
        if (!root.TryGetProperty("recovery", out var recovery) || recovery.ValueKind != JsonValueKind.Object)
        {
            throw ArchiveRefusal.Damaged("archive.json has no recovery envelope");
        }
        var format = ReadInteger(recovery, "formatVersion");
        var expectedVersion = format switch
        {
            >= 1 and <= 3 => 1,
            4 => 2,
            _ => 0,
        };
        if (expectedVersion == 0 || version != expectedVersion)
        {
            throw ArchiveRefusal.Damaged("the header version doesn't match the envelope");
        }
        var manifestBytes = ReadBase64(root, "manifest", 0, 1 << 24);
        byte[]? vaultKey = null;
        if (expectedVersion == 1)
        {
            vaultKey = UnwrapVaultKey(recovery, format, password ?? "");
            try
            {
                manifestBytes = ConformanceCrypto.Open(vaultKey, manifestBytes, "journal:v1:archive");
            }
            catch (Exception exception) when (exception is CryptographicException or ArgumentException)
            {
                throw ArchiveRefusal.Damaged("the manifest doesn't authenticate");
            }
        }
        var manifest = ParseManifest(manifestBytes);
        CheckListedFiles(directory, manifest);
        return new Opened(ArchiveOutcome.Accept, null, vaultKey);
    }

    private static int ReadInteger(JsonElement parent, string name)
    {
        if (!parent.TryGetProperty(name, out var element) || !ArchiveStrictJson.TryReadPlainInteger(element, out var value) || value > int.MaxValue)
        {
            throw ArchiveRefusal.Damaged($"{name} is missing or not an integer");
        }
        return (int)value;
    }

    private static byte[] ReadBase64(JsonElement parent, string name, int minimumBytes, int maximumBytes)
    {
        if (!parent.TryGetProperty(name, out var element) || element.ValueKind != JsonValueKind.String || !Secrets.IsBase64(element.GetString(), minimumBytes, maximumBytes))
        {
            throw ArchiveRefusal.Damaged($"{name} is missing or not base64");
        }
        return Convert.FromBase64String(element.GetString()!);
    }

    // The envelope's bounds are the CPU limit before a password is tried.
    private static byte[] UnwrapVaultKey(JsonElement recovery, int format, string password)
    {
        var iterations = ReadInteger(recovery, "iterations");
        if (iterations is < 100_000 or > 2_000_000)
        {
            throw ArchiveRefusal.Damaged("the envelope's iterations are outside the bounds");
        }
        var salt = ReadBase64(recovery, "salt", 16, 16);
        var wrapped = ReadBase64(recovery, "wrappedKey", 1, 1024);
        return ArchiveCrypto.UnwrapVaultKey(format, salt, iterations, wrapped, password)
            ?? throw ArchiveRefusal.WrongPassword("the password doesn't open the envelope");
    }

    // {"database": "<sha256>", "attachments": {"<UUID>": "<sha256>"}}. Every key is checked before any is used as a name.
    private static Manifest ParseManifest(byte[] json)
    {
        using var document = ArchiveStrictJson.Parse(json, "the manifest");
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object
            || !root.TryGetProperty("database", out var database)
            || database.ValueKind != JsonValueKind.String
            || !root.TryGetProperty("attachments", out var attachments)
            || attachments.ValueKind != JsonValueKind.Object)
        {
            throw ArchiveRefusal.Damaged("the manifest lacks database or attachments");
        }
        var listed = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var member in attachments.EnumerateObject())
        {
            if (!ArchiveNames.IsUuid(member.Name))
            {
                throw ArchiveRefusal.Damaged("a manifest key is not a lower-case UUID");
            }
            if (member.Value.ValueKind != JsonValueKind.String || !ArchiveNames.IsSha256(member.Value.GetString()!))
            {
                throw ArchiveRefusal.Damaged("a manifest hash is not 64 lower-case hexadecimal characters");
            }
            listed.Add(member.Name, member.Value.GetString()!);
        }
        if (!ArchiveNames.IsSha256(database.GetString()!))
        {
            throw ArchiveRefusal.Damaged("the database hash is not 64 lower-case hexadecimal characters");
        }
        return new Manifest(database.GetString()!, listed);
    }

    // Reads exactly the files the manifest lists, as regular files within the limits, and ignores everything else.
    private static void CheckListedFiles(string directory, Manifest manifest)
    {
        var folder = new DirectoryInfo(Path.Combine(directory, "attachments"));
        if (folder.LinkTarget is not null)
        {
            throw ArchiveRefusal.Damaged("attachments/ is a link");
        }
        long total = 0;
        total += CheckFile(Path.Combine(directory, "journal.sqlite"), manifest.Database, ArchiveManifest.MaximumDatabaseBytes, "journal.sqlite");
        foreach (var (name, hash) in manifest.Attachments)
        {
            total += CheckFile(Path.Combine(folder.FullName, name), hash, ArchiveManifest.MaximumImageBytes, $"attachments/{name}");
        }
        if (total > ArchiveManifest.MaximumTotalBytes)
        {
            throw ArchiveRefusal.Damaged("the listed files add up to more than 1 TiB");
        }
    }

    private static long CheckFile(string path, string expectedHash, long maximumBytes, string name)
    {
        var file = new FileInfo(path);
        if (file.LinkTarget is not null || !file.Exists)
        {
            throw ArchiveRefusal.Damaged($"{name} is missing, a link or not a regular file");
        }
        if (file.Length > maximumBytes)
        {
            throw ArchiveRefusal.Damaged($"{name} is over the size limit");
        }
        using var stream = file.OpenRead();
        if (!string.Equals(Convert.ToHexStringLower(SHA256.HashData(stream)), expectedHash, StringComparison.Ordinal))
        {
            throw ArchiveRefusal.Damaged($"{name} doesn't match the manifest");
        }
        return file.Length;
    }
}
