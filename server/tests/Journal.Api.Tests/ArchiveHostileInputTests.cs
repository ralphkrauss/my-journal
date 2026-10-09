using System.Text;
using Microsoft.Data.Sqlite;

namespace Journal.Api.Tests;

// What an archive built to be expensive does to the independent reader (protocol/archive.md, Limits): the databases and
// documents that cost something to look at are built here, because they are too large to commit.
public sealed class ArchiveHostileInputTests
{
    private const string SmallPages = "archive/v2/database/foreign-small-pages.sqlite";

    private static string CopyOf(TemporaryFolder folder, string fixture)
    {
        var file = folder.Combine(Guid.NewGuid().ToString("N") + ".sqlite");
        File.Copy(ConformanceFiles.Path(fixture), file);
        return file;
    }

    private static void Change(string file, params string[] statements)
    {
        using var connection = new SqliteConnection($"Data Source={file};Pooling=False");
        connection.Open();
        foreach (var sql in statements)
        {
            using var command = connection.CreateCommand();
            command.CommandText = sql;
            command.ExecuteNonQuery();
        }
    }

    [Fact]
    public void ALargeSchemaIsRefusedFromItsPagesBeforeSqliteParsesIt()
    {
        using var folder = new TemporaryFolder();
        var file = CopyOf(folder, SmallPages);
        Change(
            file,
            "PRAGMA writable_schema = ON",
            """
            WITH RECURSIVE counter(number) AS (SELECT 1 UNION ALL SELECT number + 1 FROM counter WHERE number < 20000)
            INSERT INTO sqlite_master(type, name, tbl_name, rootpage, sql)
            SELECT 'view', 'v' || number, 'v' || number, 0, 'CREATE VIEW v' || number || ' AS SELECT 1' FROM counter
            """);

        var (outcome, reason) = ArchiveRefusal.Classify(() => ArchiveSchemaScan.Check(file));

        Assert.Equal(ArchiveOutcome.Damaged, outcome);
        Assert.Contains("objects", reason, StringComparison.Ordinal);
        Assert.Equal(ArchiveOutcome.Damaged, ArchiveRefusal.Classify(() => ArchiveDatabaseInspector.Inspect(file)).Outcome);
    }

    [Fact]
    public void AHugeSchemaStatementIsOverTheByteLimit()
    {
        using var folder = new TemporaryFolder();
        var file = CopyOf(folder, SmallPages);
        Change(
            file,
            "PRAGMA writable_schema = ON",
            $"INSERT INTO sqlite_master(type, name, tbl_name, rootpage, sql) VALUES ('view', 'big', 'big', 0, 'CREATE VIEW big AS SELECT ''{new string('x', 1_000_000)}''')");

        Assert.Equal(ArchiveOutcome.Damaged, ArchiveRefusal.Classify(() => ArchiveSchemaScan.Check(file)).Outcome);
    }

    [Theory]
    [InlineData("archive/v2/database/foreign.sqlite")]
    [InlineData(SmallPages)]
    [InlineData("archive/v2/database/foreign-virtual-table.sqlite")]
    [InlineData("archive/v1/encrypted/journal.sqlite")]
    public void TheScanCountsWhatSqliteLists(string fixture)
    {
        using var folder = new TemporaryFolder();
        var file = CopyOf(folder, fixture);
        var scanned = ArchiveSchemaScan.Check(file);
        using var connection = new SqliteConnection($"Data Source={file};Mode=ReadOnly;Pooling=False");
        connection.Open();
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT COUNT(*) FROM sqlite_master";
        Assert.Equal(Convert.ToInt32(command.ExecuteScalar(), System.Globalization.CultureInfo.InvariantCulture), scanned);
    }

    [Fact]
    public void AHugeMigrationTableIsReadWithALimitAndIsNewer()
    {
        using var folder = new TemporaryFolder();
        var file = CopyOf(folder, SmallPages);
        Change(
            file,
            """
            WITH RECURSIVE counter(number) AS (SELECT 1 UNION ALL SELECT number + 1 FROM counter WHERE number < 200000)
            INSERT INTO grdb_migrations(identifier) SELECT 'later-' || number FROM counter
            """);

        Assert.Equal(ArchiveOutcome.Newer, ArchiveRefusal.Classify(() => ArchiveDatabaseInspector.Inspect(file)).Outcome);
    }

    // A virtual table has no pages of its own (rootpage 0), and SQLite loads such a row without connecting it. The
    // reader refuses it from the schema table, so the library table it impersonates is never asked about.
    [Fact]
    public void AVirtualTableInTheNameOfALibraryTableIsRefusedForWhatItIs()
    {
        using var folder = new TemporaryFolder();
        var file = CopyOf(folder, SmallPages);
        Change(
            file,
            "PRAGMA writable_schema = ON",
            "UPDATE sqlite_master SET rootpage = 0, sql = 'CREATE  /* x */ VIRTUAL TABLE attachments USING fts5(id)' WHERE type = 'table' AND name = 'attachments'",
            "DELETE FROM sqlite_master WHERE name = 'sqlite_autoindex_attachments_1'");

        var (outcome, reason) = ArchiveRefusal.Classify(() => ArchiveDatabaseInspector.Inspect(file));

        Assert.Equal(ArchiveOutcome.Damaged, outcome);
        Assert.StartsWith("table attachments", reason, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("CREATE TABLE t (a CHECK (a > 0))", "CHECK")]
    [InlineData("create table t (a text collate nocase)", "COLLATE")]
    [InlineData("CREATE TABLE t (a UNIQUE ON CONFLICT REPLACE)", "CONFLICT")]
    [InlineData("CREATE TABLE t (a, b AS (a + 1))", "AS")]
    [InlineData("CREATE TABLE t (a, FOREIGN KEY (a) REFERENCES p DEFERRABLE INITIALLY DEFERRED)", "DEFERRABLE")]
    public void TheWordsNoPragmaReportsAreFound(string sql, string word) =>
        Assert.Contains(word, ArchiveSchemaWords.RefusedWordsIn(sql));

    [Theory]
    [InlineData("CREATE TABLE t (\"check\" TEXT, [collate] TEXT, `as` TEXT, 'virtual')")]
    [InlineData("CREATE TABLE t (a TEXT /* CHECK */) -- COLLATE")]
    [InlineData("CREATE TABLE t (a TEXT DEFAULT 'GENERATED ALWAYS AS')")]
    [InlineData("CREATE TABLE t (checked TEXT, collated TEXT, as_of TEXT, CHECKé TEXT)")]
    public void TheseAreNotTheWords(string sql) => Assert.Empty(ArchiveSchemaWords.RefusedWordsIn(sql));

    [Fact]
    public void AManifestMayHoldAsManyValuesAsTheLimitAndNoMore()
    {
        var database = "\"database\":{\"bytes\":1,\"sha256\":\"" + new string('0', 64) + "\"}";
        string Text(int padding) => "{" + database + ",\"attachments\":{},\"x\":[" + string.Join(",", Enumerable.Repeat("0", padding)) + "]}";
        // The root, database, its two members, attachments and the padding array are six values.
        _ = ArchiveManifest.Parse(Encoding.UTF8.GetBytes(Text(ArchiveStrictJson.MaxManifestValues - 6)));
        var (outcome, _) = ArchiveRefusal.Classify(() => ArchiveManifest.Parse(Encoding.UTF8.GetBytes(Text(ArchiveStrictJson.MaxManifestValues - 5))));
        Assert.Equal(ArchiveOutcome.Damaged, outcome);
    }
}
