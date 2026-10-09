namespace Journal.Api.Tests;

// The structure check of protocol/archive.md (Database), run by an independent reader (ArchiveDatabaseInspector) with
// Microsoft.Data.Sqlite on the databases of conformance/archive/v2/database, which Python's sqlite3 module wrote in its
// own style, not GRDB.
public sealed class ArchiveDatabaseConformanceTests
{
    [Fact]
    public void EveryForeignDatabaseIsAcceptedOrRefusedInItsClass()
    {
        using var corpus = ConformanceFiles.Json("archive/v2/database-v2.json");
        var failures = new List<string>();
        foreach (var database in corpus.RootElement.GetProperty("cases").EnumerateArray())
        {
            var name = database.GetProperty("name").GetString()!;
            var expected = ArchiveOutcomes.Parse(database.GetProperty("expect").GetString()!);
            var file = ConformanceFiles.Path($"archive/v2/{database.GetProperty("file").GetString()}");
            var (outcome, reason) = ArchiveRefusal.Classify(() => ArchiveDatabaseInspector.Inspect(file));
            if (outcome != expected)
            {
                failures.Add($"{name}: {outcome} ({reason}), expected {expected}");
            }
        }
        Assert.True(failures.Count == 0, string.Join(Environment.NewLine, failures));
    }

    [Fact]
    public void TheLibraryOfTheDirectoryArchiveHasTheDocumentedStructure()
    {
        ArchiveDatabaseInspector.Inspect(ConformanceFiles.Path("archive/v1/encrypted/journal.sqlite"));
        ArchiveDatabaseInspector.Inspect(ConformanceFiles.Path("archive/v1/plaintext/journal.sqlite"));
    }
}
