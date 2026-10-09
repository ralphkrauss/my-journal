using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Journal.Api.Security;
using Microsoft.Data.Sqlite;

namespace Journal.Api.Tests;

// The database of an archive as another client reads it with SQLite (conformance/archive/v1/expected.json lists the
// rows), shared by the readers of the directory archive and of the file archive, which hold the same library.
internal static class ArchiveDatabaseAssertions
{
    // The decrypted text of a stored payload: base64 of the sealed record, or of the plain record without a key.
    private static string Plaintext(string payload, byte[]? vaultKey, string kind, string id)
    {
        Assert.True(Secrets.IsBase64(payload, 0, 1 << 24), "payloads are canonical base64");
        var bytes = Convert.FromBase64String(payload);
        return Encoding.UTF8.GetString(vaultKey is null ? bytes : ConformanceCrypto.Open(vaultKey, bytes, $"journal:v1:record:{kind}:{id}"));
    }

    private static string Text(object value) => value is byte[] bytes ? Encoding.UTF8.GetString(bytes) : (string)value;

    public static List<string> Rows(SqliteConnection connection, string query, Func<SqliteDataReader, string> row)
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

    // Opens a copy of the database read-only and compares every table with the rows listed in expected. readImage gives
    // the stored (still encrypted) bytes of the image with an ID.
    public static void AssertDatabase(string databaseFile, Func<string, byte[]> readImage, JsonElement expected, byte[]? vaultKey)
    {
        var header = File.ReadAllBytes(databaseFile).AsSpan(0, 20);
        Assert.True(header[18] == 1 && header[19] == 1, "the database is in rollback-journal mode");

        var copy = Path.Combine(Path.GetTempPath(), "archive-conformance-" + Guid.NewGuid().ToString("N") + ".sqlite");
        File.Copy(databaseFile, copy);
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
                Rows(connection, "SELECT id, uploaded FROM attachments ORDER BY id", reader => $"{reader.GetString(0)}|{reader.GetInt64(1)}|{Image(readImage(reader.GetString(0)), reader.GetString(0), vaultKey)}"));
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
    private static string Image(byte[] stored, string id, byte[]? vaultKey)
    {
        var image = vaultKey is null ? stored : ConformanceCrypto.Open(vaultKey, stored, $"journal:v1:attachment:{id}");
        return $"{image.Length}|{Convert.ToHexStringLower(SHA256.HashData(image))}";
    }
}
