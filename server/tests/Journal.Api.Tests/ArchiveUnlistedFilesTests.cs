using System.Text.Json;

namespace Journal.Api.Tests;

// What the directory archive reader does with files the manifest does not list, with links and over-limit files in the
// places it does read, and with the hostile folders it must refuse (conformance/archive/v1/unlisted-files-v1.json,
// protocol/archive.md, Rules for both kinds).
public sealed class ArchiveUnlistedFilesTests
{
    private const string Root = "archive/v1";

    [Fact]
    public void UnlistedFilesAreIgnoredAndLinksAndOversizedFilesInListedPlacesAreRefused()
    {
        using var corpus = ConformanceFiles.Json($"{Root}/unlisted-files-v1.json");
        using var expected = ConformanceFiles.Json($"{Root}/expected.json");
        var password = expected.RootElement.GetProperty("archives").GetProperty("encrypted").GetProperty("password").GetString();
        var failures = new List<string>();
        foreach (var mutation in corpus.RootElement.GetProperty("mutations").EnumerateArray())
        {
            using var folder = new TemporaryFolder();
            var package = folder.Combine("package");
            ArchiveConformanceTests.CopyDirectory(ConformanceFiles.Path($"{Root}/encrypted"), package);
            foreach (var operation in mutation.GetProperty("ops").EnumerateArray())
            {
                Apply(package, operation);
            }
            var wanted = mutation.GetProperty("result").GetString() == "restores" ? ArchiveOutcome.Accept : ArchiveOutcome.Damaged;
            var opened = DirectoryArchiveReader.Open(package, password);
            var name = mutation.GetProperty("name").GetString()!;
            if (opened.Outcome != wanted)
            {
                failures.Add($"{name}: {opened.Outcome} ({opened.Refusal}), expected {wanted}");
            }
            else if (name.StartsWith("sparse-", StringComparison.Ordinal) && opened.Refusal?.Contains("size limit", StringComparison.Ordinal) != true)
            {
                // Hashing 33 GiB of zeros would also end in a mismatch; only the limit refuses without reading the file.
                failures.Add($"{name}: refused for another reason than the size limit ({opened.Refusal})");
            }
        }
        Assert.True(failures.Count == 0, string.Join(Environment.NewLine, failures));
    }

    [Fact]
    public void HostilePackagesAreRefusedBeforeAnyFileIsCreated()
    {
        using var corpus = ConformanceFiles.Json($"{Root}/unlisted-files-v1.json");
        foreach (var package in corpus.RootElement.GetProperty("packages").EnumerateArray())
        {
            using var folder = new TemporaryFolder();
            var directory = folder.Combine("package");
            ArchiveConformanceTests.CopyDirectory(ConformanceFiles.Path($"{Root}/{package.GetProperty("directory").GetString()}"), directory);
            var before = Snapshot(folder.FullName);

            var opened = DirectoryArchiveReader.Open(directory, null);

            var name = package.GetProperty("name").GetString();
            Assert.True(opened.Outcome == ArchiveOutcome.Damaged, $"{name}: {opened.Outcome}");
            Assert.Equal(before, Snapshot(folder.FullName));
            Assert.False(System.IO.Directory.Exists(folder.Combine("restored")), $"{name} created the would-be destination");
            var rule = name == "manifest-names-a-file-outside" ? "lower-case UUID" : "not the header of a directory archive";
            Assert.True(opened.Refusal?.Contains(rule, StringComparison.Ordinal) == true, $"{name}: refused for another reason ({opened.Refusal})");
        }
    }

    [Fact]
    public void LinksAreRefusedEvenWhenTheyLeadToTheListedBytes()
    {
        using var expected = ConformanceFiles.Json($"{Root}/expected.json");
        var password = expected.RootElement.GetProperty("archives").GetProperty("encrypted").GetProperty("password").GetString();
        var moves = new (string Name, string Listed, string Elsewhere)[]
        {
            ("database", "journal.sqlite", "elsewhere.sqlite"),
            ("image", "attachments/01234567-89ab-4cde-8fab-0123456789ab", "elsewhere-image"),
            ("attachments folder", "attachments", "attachments-elsewhere"),
        };
        foreach (var (name, listed, elsewhere) in moves)
        {
            using var folder = new TemporaryFolder();
            var package = folder.Combine("package");
            ArchiveConformanceTests.CopyDirectory(ConformanceFiles.Path($"{Root}/encrypted"), package);
            Assert.Equal(ArchiveOutcome.Accept, DirectoryArchiveReader.Open(package, password).Outcome);

            var path = Path.Combine(package, listed);
            var moved = Path.Combine(package, elsewhere);
            if (listed == "attachments")
            {
                System.IO.Directory.Move(path, moved);
                System.IO.Directory.CreateSymbolicLink(path, Path.GetRelativePath(package, moved));
            }
            else
            {
                File.Move(path, moved);
                File.CreateSymbolicLink(path, Path.GetRelativePath(Path.GetDirectoryName(path)!, moved));
            }

            var opened = DirectoryArchiveReader.Open(package, password);
            Assert.True(opened.Outcome == ArchiveOutcome.Damaged, $"a link in place of the {name} was followed");
        }
    }

    // Every file and folder below the root with its size, so a created, changed or removed file shows.
    private static List<string> Snapshot(string root) =>
        new DirectoryInfo(root).EnumerateFileSystemInfos("*", SearchOption.AllDirectories)
            .Select(info => $"{Path.GetRelativePath(root, info.FullName)}|{(info is FileInfo file ? file.Length : -1)}")
            .Order(StringComparer.Ordinal)
            .ToList();

    // Operations as unlisted-files-v1.json describes them. Targets of links are relative to the package.
    private static void Apply(string package, JsonElement operation)
    {
        var path = Path.Combine(package, operation.GetProperty("file").GetString()!);
        switch (operation.GetProperty("op").GetString())
        {
            case "add":
                System.IO.Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                File.WriteAllText(path, operation.GetProperty("text").GetString());
                break;
            case "delete":
                File.Delete(path);
                break;
            case "symlink":
                File.Delete(path);
                File.CreateSymbolicLink(path, RelativeTarget(package, path, operation));
                break;
            case "symlinkFolder":
                System.IO.Directory.Delete(path, true);
                System.IO.Directory.CreateDirectory(Path.Combine(package, operation.GetProperty("target").GetString()!));
                System.IO.Directory.CreateSymbolicLink(path, RelativeTarget(package, path, operation));
                break;
            case "sparse":
                File.Delete(path);
                using (var sparse = new FileStream(path, FileMode.CreateNew, FileAccess.Write))
                {
                    sparse.SetLength(operation.GetProperty("bytes").GetInt64());
                }
                break;
            default:
                throw new InvalidDataException($"Unknown operation {operation}.");
        }
    }

    private static string RelativeTarget(string package, string link, JsonElement operation) =>
        Path.GetRelativePath(Path.GetDirectoryName(link)!, Path.Combine(package, operation.GetProperty("target").GetString()!));
}
