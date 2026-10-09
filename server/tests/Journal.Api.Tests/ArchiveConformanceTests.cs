using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Journal.Api.Tests;

// The independent reader of the directory archive (DirectoryArchiveReader, protocol/archive.md) checked against
// protocol/conformance/archive/v1: header, password, authenticated manifest, file hashes, the database as SQLite
// reads it, and the damage a reader must refuse or ignore.
public sealed class ArchiveConformanceTests
{
    private const string Root = "archive/v1";

    private static JsonDocument Expected() => ConformanceFiles.Json($"{Root}/expected.json");

    private static string Directory(string name) => ConformanceFiles.Path($"{Root}/{name}");

    private static string Sha256(string file) => Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(file)));

    private static void AssertArchive(string name, string? password)
    {
        using var corpus = Expected();
        var expected = corpus.RootElement.GetProperty("archives").GetProperty(name);
        var directory = Directory(name);
        var opened = DirectoryArchiveReader.Open(directory, password);
        Assert.True(opened.Refusal is null, opened.Refusal);
        using var header = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(directory, "archive.json")));
        Assert.Equal(expected.GetProperty("headerVersion").GetInt32(), header.RootElement.GetProperty("version").GetInt32());
        Assert.Equal(expected.GetProperty("formatVersion").GetInt32(), header.RootElement.GetProperty("recovery").GetProperty("formatVersion").GetInt32());
        AssertManifest(directory, expected.GetProperty("manifest"));
        ArchiveDatabaseAssertions.AssertDatabase(
            Path.Combine(directory, "journal.sqlite"),
            id => File.ReadAllBytes(Path.Combine(directory, "attachments", id)),
            expected,
            opened.VaultKey);
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
        var opened = DirectoryArchiveReader.Open(Directory("encrypted"), password);
        Assert.True(opened.Refusal is null, opened.Refusal);
        Assert.Equal(recovery.GetProperty("vaultKey").GetBytesFromBase64(), opened.VaultKey);
        AssertArchive("encrypted", password);
        Assert.Equal(ArchiveOutcome.WrongPassword, DirectoryArchiveReader.Open(Directory("encrypted"), password!.Trim()).Outcome);
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
                var refused = DirectoryArchiveReader.Open(copy, password).Refusal is not null;
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

    internal static void CopyDirectory(string source, string destination)
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
