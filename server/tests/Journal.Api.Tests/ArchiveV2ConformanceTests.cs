using System.Buffers.Binary;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Data.Sqlite;

namespace Journal.Api.Tests;

// An independent reader of the file archive (protocol/archive.md, File archive) checked against
// protocol/conformance/archive/v2. The ZIP container is parsed by ZipContainerReader, not by ZipArchive, which hides
// duplicate names, overlapping data and wrong CRC-32 values; ZipArchive only cross-checks what is accepted.
public sealed class ArchiveV2ConformanceTests
{
    private const string Root = "archive/v2";

    [Fact]
    public void EveryContainerCaseIsAcceptedOrRefusedInItsClass()
    {
        using var corpus = ConformanceFiles.Json($"{Root}/container-v2.json");
        var cases = corpus.RootElement.GetProperty("cases").EnumerateArray().ToList();
        Assert.True(cases.Count >= 100, "the corpus lists about a hundred cases");
        var failures = new List<string>();
        foreach (var container in cases)
        {
            var name = container.GetProperty("name").GetString()!;
            var file = ConformanceFiles.Path($"{Root}/{container.GetProperty("file").GetString()}");
            var manifestJson = container.TryGetProperty("manifestText", out var text) ? text.GetString()! : container.GetProperty("manifest").GetRawText();
            var parseHeader = container.TryGetProperty("parseHeader", out var parse) && parse.GetBoolean();
            var expected = ArchiveOutcomes.Parse(container.GetProperty("expect").GetString()!);
            FileArchiveContents? contents = null;
            var (outcome, reason) = ArchiveRefusal.Classify(() => contents = FileArchiveReader.ReadWithManifest(file, manifestJson, parseHeader));
            if (outcome != expected)
            {
                failures.Add($"{name}: {outcome} ({reason}), expected {expected}");
            }
            else if (outcome == ArchiveOutcome.Accept)
            {
                failures.AddRange(ExtractionDifferences(name, container, contents!, crossCheckWith: parseHeader ? null : file));
            }
        }
        Assert.True(failures.Count == 0, string.Join(Environment.NewLine, failures));
    }

    // An accepted archive yields exactly the listed files with the listed sizes and hashes; unless its header is a
    // stand-in, System.IO.Compression reads the same bytes.
    private static List<string> ExtractionDifferences(string name, JsonElement container, FileArchiveContents contents, string? crossCheckWith)
    {
        var differences = new List<string>();
        // A case whose manifest is given as text (where the text is the point) carries no manifest object: read the text.
        using var parsedText = container.TryGetProperty("manifestText", out var text) ? JsonDocument.Parse(text.GetString()!) : null;
        var manifest = parsedText?.RootElement ?? container.GetProperty("manifest");
        var listed = new List<(string Key, string EntryName, JsonElement Entry)> { ("journal.sqlite", "journal.sqlite", manifest.GetProperty("database")) };
        listed.AddRange(manifest.GetProperty("attachments").EnumerateObject().Select(image => (image.Name, "attachments/" + image.Name, image.Value)));
        if (contents.Files.Count != listed.Count)
        {
            differences.Add($"{name}: {contents.Files.Count} files extracted, {listed.Count} listed");
        }
        using var zip = crossCheckWith is null ? null : ZipFile.OpenRead(crossCheckWith);
        foreach (var (key, entryName, entry) in listed)
        {
            if (!contents.Files.TryGetValue(key, out var bytes))
            {
                differences.Add($"{name}: {entryName} was not extracted");
                continue;
            }
            if (bytes.Length != entry.GetProperty("bytes").GetInt64() || Convert.ToHexStringLower(SHA256.HashData(bytes)) != entry.GetProperty("sha256").GetString())
            {
                differences.Add($"{name}: {entryName} differs from the manifest");
            }
            if (zip is not null)
            {
                using var stream = zip.Entries.Single(candidate => candidate.FullName == entryName).Open();
                using var copy = new MemoryStream();
                stream.CopyTo(copy);
                if (!copy.ToArray().AsSpan().SequenceEqual(bytes))
                {
                    differences.Add($"{name}: System.IO.Compression reads other bytes for {entryName}");
                }
            }
        }
        return differences;
    }

    [Fact]
    public void EncryptedArchiveOpensWithThePasswordAndHoldsTheLibraryOfTheDirectoryArchive()
    {
        using var corpus = ConformanceFiles.Json($"{Root}/expected.json");
        var archive = corpus.RootElement.GetProperty("archives").GetProperty("encrypted");
        using var vectors = ConformanceFiles.Json("crypto/encryption-v2.json");
        var recovery = vectors.RootElement.GetProperty("recovery");
        var password = archive.GetProperty("password").GetString()!;
        Assert.Equal(recovery.GetProperty("password").GetString(), password);

        var contents = FileArchiveReader.ReadEncrypted(ConformanceFiles.Path($"{Root}/{archive.GetProperty("file").GetString()}"), password);

        Assert.Equal(recovery.GetProperty("vaultKey").GetBytesFromBase64(), contents.VaultKey);
        Assert.Equal(archive.GetProperty("recoveryFormat").GetInt32(), contents.Header!.FormatVersion);
        AssertEntries(archive, contents);
        var directory = ConformanceFiles.Path("archive/v1/encrypted");
        Assert.Equal(File.ReadAllBytes(Path.Combine(directory, "journal.sqlite")), contents.Files["journal.sqlite"]);
        var image = contents.Manifest.Attachments.Keys.Single();
        Assert.Equal(File.ReadAllBytes(Path.Combine(directory, "attachments", image)), contents.Files[image]);

        using var rows = ConformanceFiles.Json("archive/v1/expected.json");
        using var folder = new TemporaryFolder();
        var database = folder.Combine("journal.sqlite");
        File.WriteAllBytes(database, contents.Files["journal.sqlite"]);
        ArchiveDatabaseInspector.Inspect(database);
        ArchiveDatabaseAssertions.AssertDatabase(database, id => contents.Files[id], rows.RootElement.GetProperty("archives").GetProperty("encrypted"), contents.VaultKey);
    }

    [Fact]
    public void RecoveryKeyArchiveOpensWithTheTrimmedKeyAndHoldsAnEmptyLibrary()
    {
        using var corpus = ConformanceFiles.Json($"{Root}/expected.json");
        var archive = corpus.RootElement.GetProperty("archives").GetProperty("encryptedRecoveryKey");
        using var vectors = ConformanceFiles.Json("crypto/encryption-v1.json");
        var phrase = archive.GetProperty("password").GetString()!;
        Assert.Equal(vectors.RootElement.GetProperty("recovery").GetProperty("phrase").GetString(), phrase);

        var contents = FileArchiveReader.ReadEncrypted(ConformanceFiles.Path($"{Root}/{archive.GetProperty("file").GetString()}"), phrase);

        var wrapped = vectors.RootElement.GetProperty("envelopes").EnumerateArray().Single(item => item.GetProperty("name").GetString() == "recovery");
        Assert.Equal(Convert.FromBase64String(wrapped.GetProperty("plaintext").GetString()!), contents.VaultKey);
        Assert.Equal(archive.GetProperty("recoveryFormat").GetInt32(), contents.Header!.FormatVersion);
        AssertEntries(archive, contents);
        Assert.Empty(contents.Manifest.Attachments);

        using var folder = new TemporaryFolder();
        var database = folder.Combine("journal.sqlite");
        File.WriteAllBytes(database, contents.Files["journal.sqlite"]);
        ArchiveDatabaseInspector.Inspect(database);
        using var connection = new SqliteConnection($"Data Source={database};Mode=ReadOnly;Pooling=False");
        connection.Open();
        var rows = ArchiveDatabaseAssertions.Rows(connection, "SELECT (SELECT count(*) FROM records) + (SELECT count(*) FROM outbox) + (SELECT count(*) FROM history) + (SELECT count(*) FROM attachments) + (SELECT count(*) FROM conflicts)", reader => reader.GetInt64(0).ToString(System.Globalization.CultureInfo.InvariantCulture));
        Assert.Equal(["0"], rows);
    }

    // The ZIP entries as expected.json lists them, in central directory order: where each local header and its data
    // start, the size, the method, the CRC-32 as its four bytes appear in the file, and the SHA-256.
    private static void AssertEntries(JsonElement archive, FileArchiveContents contents)
    {
        var expected = archive.GetProperty("entries").EnumerateArray().ToList();
        Assert.Equal(expected.Select(item => item.GetProperty("name").GetString()), contents.Entries.Select(item => item.Entry.Name));
        for (var index = 0; index < expected.Count; index++)
        {
            var item = expected[index];
            var located = contents.Entries[index];
            var name = located.Entry.Name;
            Assert.Equal(item.GetProperty("localHeaderOffset").GetInt64(), (long)located.Entry.LocalHeaderOffset);
            Assert.Equal(item.GetProperty("dataOffset").GetInt64(), (long)located.DataOffset);
            Assert.Equal(item.GetProperty("bytes").GetInt64(), (long)located.Entry.Size);
            Assert.Equal(item.GetProperty("method").GetInt32(), located.Entry.Method);
            var crc = new byte[4];
            BinaryPrimitives.WriteUInt32LittleEndian(crc, located.Entry.Crc32);
            Assert.Equal(item.GetProperty("crc32").GetString(), Convert.ToHexStringLower(crc));
            var data = name switch
            {
                "archive.json" => contents.HeaderJson,
                "journal.sqlite" => contents.Files[name],
                _ => contents.Files[name["attachments/".Length..]],
            };
            Assert.Equal(item.GetProperty("sha256").GetString(), Convert.ToHexStringLower(SHA256.HashData(data)));
        }
    }

    [Fact]
    public void ChangedEncryptedArchivesAreRefusedInTheirClass()
    {
        using var corpus = ConformanceFiles.Json($"{Root}/expected.json");
        var archives = corpus.RootElement.GetProperty("archives");
        var failures = new List<string>();
        foreach (var mutation in corpus.RootElement.GetProperty("mutations").EnumerateArray())
        {
            var archive = archives.GetProperty(mutation.GetProperty("archive").GetString()!);
            var password = mutation.TryGetProperty("password", out var override_) ? override_.GetString()! : archive.GetProperty("password").GetString()!;
            using var folder = new TemporaryFolder();
            var copy = folder.Combine("changed.zip");
            File.Copy(ConformanceFiles.Path($"{Root}/{archive.GetProperty("file").GetString()}"), copy);
            using (var stream = new FileStream(copy, FileMode.Open, FileAccess.Write))
            {
                foreach (var operation in mutation.GetProperty("operations").EnumerateArray())
                {
                    Assert.Equal("set", operation.GetProperty("op").GetString());
                    stream.Position = operation.GetProperty("offset").GetInt64();
                    stream.Write(Convert.FromHexString(operation.GetProperty("bytes").GetString()!));
                }
            }
            var expected = ArchiveOutcomes.Parse(mutation.GetProperty("expect").GetString()!);
            var (outcome, reason) = ArchiveRefusal.Classify(() => FileArchiveReader.ReadEncrypted(copy, password));
            if (outcome != expected)
            {
                failures.Add($"{mutation.GetProperty("name").GetString()}: {outcome} ({reason}), expected {expected}");
            }
        }
        Assert.True(failures.Count == 0, string.Join(Environment.NewLine, failures));
    }
}
