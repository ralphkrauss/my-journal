using System.Text.Json;
using Microsoft.Data.Sqlite;

namespace Journal.Api.Tests;

// The structure check of protocol/archive.md (Database), run before a database is opened as a library. It compares
// structure, not CREATE text, with the tables the recorded migrations create, which conformance/archive/v2/database-v2.json
// lists. It reads a copy of the file, read-only, and never writes to it.
internal static class ArchiveDatabaseInspector
{
    private static readonly Lazy<Expected> Reference = new(Load);

    private sealed record Expected(string[] Migrations, Dictionary<int, Dictionary<string, TableShape>> StructureAfter);

    // Columns and indexes as sorted signature texts, so that two tables are equal when their signatures are.
    private sealed record TableShape(List<string> Columns, List<string> Indexes);

    // Returns normally when the database is acceptable. Throws damaged, or newer for a migration this reader does not know.
    public static void Inspect(string databaseFile)
    {
        RequireRollbackJournalHeader(databaseFile);
        var copy = Path.Combine(Path.GetTempPath(), "archive-database-" + Guid.NewGuid().ToString("N") + ".sqlite");
        File.Copy(databaseFile, copy);
        try
        {
            using var connection = new SqliteConnection($"Data Source={copy};Mode=ReadOnly;Pooling=False");
            connection.Open();
            InspectConnection(connection);
        }
        catch (SqliteException exception)
        {
            throw ArchiveRefusal.Damaged($"SQLite cannot read the database: {exception.Message}");
        }
        finally
        {
            File.Delete(copy);
        }
    }

    // Bytes 18 and 19 are the file format versions: 1 and 1 for a database in rollback-journal mode, 2 and 2 for
    // write-ahead logging.
    private static void RequireRollbackJournalHeader(string databaseFile)
    {
        using var stream = File.OpenRead(databaseFile);
        var header = new byte[100];
        if (stream.Read(header, 0, header.Length) < header.Length || !header.AsSpan(0, 16).SequenceEqual("SQLite format 3\0"u8))
        {
            throw ArchiveRefusal.Damaged("the file is not a SQLite database");
        }
        if (header[18] != 1 || header[19] != 1)
        {
            throw ArchiveRefusal.Damaged($"the file format versions are {header[18]} and {header[19]}, not 1 and 1");
        }
    }

    private static void InspectConnection(SqliteConnection connection)
    {
        Execute(connection, "PRAGMA trusted_schema = OFF");
        var quickCheck = Strings(connection, "PRAGMA quick_check");
        if (quickCheck.Count != 1 || quickCheck[0] != "ok")
        {
            throw ArchiveRefusal.Damaged("PRAGMA quick_check does not report ok");
        }
        var recorded = Strings(connection, "SELECT identifier FROM grdb_migrations ORDER BY rowid");
        var known = Reference.Value.Migrations;
        for (var index = 0; index < recorded.Count; index++)
        {
            if (!known.Contains(recorded[index]))
            {
                throw ArchiveRefusal.Newer($"migration {recorded[index]} is not known");
            }
            if (index >= known.Length || recorded[index] != known[index])
            {
                throw ArchiveRefusal.Damaged($"migration {recorded[index]} is recorded out of order");
            }
        }
        if (!Reference.Value.StructureAfter.TryGetValue(recorded.Count, out var expected))
        {
            throw ArchiveRefusal.Damaged($"{recorded.Count} migrations are recorded and none has a structure to compare");
        }
        RequireNoTriggersOrViews(connection);
        var actualTables = Strings(connection, "SELECT name FROM sqlite_schema WHERE type = 'table' AND name <> 'sqlite_sequence' ORDER BY name");
        if (!actualTables.SequenceEqual(expected.Keys.Order(StringComparer.Ordinal)))
        {
            throw ArchiveRefusal.Damaged($"the tables are {string.Join(", ", actualTables)}, not the ones the recorded migrations create");
        }
        foreach (var (table, shape) in expected)
        {
            var actual = ReadShape(connection, table);
            if (!actual.Columns.SequenceEqual(shape.Columns))
            {
                throw ArchiveRefusal.Damaged($"the columns of {table} differ: {string.Join("; ", actual.Columns)}");
            }
            if (!actual.Indexes.SequenceEqual(shape.Indexes))
            {
                throw ArchiveRefusal.Damaged($"the indexes of {table} differ: {string.Join("; ", actual.Indexes)}");
            }
        }
    }

    private static void RequireNoTriggersOrViews(SqliteConnection connection)
    {
        var others = Strings(connection, "SELECT type || ' ' || name FROM sqlite_schema WHERE type NOT IN ('table', 'index')");
        if (others.Count > 0)
        {
            throw ArchiveRefusal.Damaged($"the database has {string.Join(", ", others)}");
        }
    }

    private static TableShape ReadShape(SqliteConnection connection, string table)
    {
        var columns = new List<string>();
        using (var command = connection.CreateCommand())
        {
            command.CommandText = "SELECT name, type, \"notnull\", dflt_value, pk FROM pragma_table_info($table)";
            command.Parameters.AddWithValue("$table", table);
            using var reader = command.ExecuteReader();
            while (reader.Read())
            {
                var primaryKey = reader.GetInt32(4);
                var notNull = reader.GetInt32(2) != 0 || primaryKey > 0;
                var defaultValue = reader.IsDBNull(3) ? null : reader.GetString(3);
                columns.Add(ColumnSignature(reader.GetString(0), reader.GetString(1), notNull, defaultValue, primaryKey));
            }
        }
        var indexes = new List<string>();
        using (var command = connection.CreateCommand())
        {
            command.CommandText = "SELECT name, \"unique\", origin, partial FROM pragma_index_list($table)";
            command.Parameters.AddWithValue("$table", table);
            using var reader = command.ExecuteReader();
            var found = new List<(string Name, bool Unique, string Origin, bool Partial)>();
            while (reader.Read())
            {
                found.Add((reader.GetString(0), reader.GetInt32(1) != 0, reader.GetString(2), reader.GetInt32(3) != 0));
            }
            reader.Close();
            foreach (var index in found)
            {
                indexes.Add(IndexSignature(index.Origin == "c" ? index.Name : null, index.Unique, index.Partial, KeyColumns(connection, index.Name)));
            }
        }
        columns.Sort(StringComparer.Ordinal);
        indexes.Sort(StringComparer.Ordinal);
        return new TableShape(columns, indexes);
    }

    private static List<string> KeyColumns(SqliteConnection connection, string index)
    {
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT name FROM pragma_index_xinfo($index) WHERE key = 1 ORDER BY seqno";
        command.Parameters.AddWithValue("$index", index);
        using var reader = command.ExecuteReader();
        var columns = new List<string>();
        while (reader.Read())
        {
            columns.Add(reader.IsDBNull(0) ? "<expression>" : reader.GetString(0));
        }
        return columns;
    }

    private static string ColumnSignature(string name, string type, bool notNull, string? defaultValue, int primaryKey) =>
        $"{name}|{type.ToUpperInvariant()}|{(notNull ? "NOT NULL" : "NULL")}|{(defaultValue is null ? "no default" : "default " + WithoutOuterParentheses(defaultValue))}|pk {primaryKey}";

    private static string IndexSignature(string? name, bool unique, bool partial, List<string> columns) =>
        $"{name ?? "unnamed"}|{(unique ? "unique" : "not unique")}|{(partial ? "partial" : "full")}|{string.Join(",", columns)}";

    // Outer parentheses are ignored: (0) and 0 are the same default, but (1) + (2) is not wrapped by one pair.
    private static string WithoutOuterParentheses(string text)
    {
        text = text.Trim();
        while (text.Length >= 2 && text[0] == '(' && text[^1] == ')' && WrapsWhole(text))
        {
            text = text[1..^1].Trim();
        }
        return text;
    }

    private static bool WrapsWhole(string text)
    {
        var depth = 0;
        for (var index = 0; index < text.Length; index++)
        {
            depth += text[index] == '(' ? 1 : text[index] == ')' ? -1 : 0;
            if (depth == 0 && index < text.Length - 1)
            {
                return false;
            }
        }
        return depth == 0;
    }

    private static void Execute(SqliteConnection connection, string sql)
    {
        using var command = connection.CreateCommand();
        command.CommandText = sql;
        command.ExecuteNonQuery();
    }

    private static List<string> Strings(SqliteConnection connection, string sql)
    {
        using var command = connection.CreateCommand();
        command.CommandText = sql;
        using var reader = command.ExecuteReader();
        var values = new List<string>();
        while (reader.Read())
        {
            values.Add(reader.GetString(0));
        }
        return values;
    }

    private static Expected Load()
    {
        using var document = ConformanceFiles.Json("archive/v2/database-v2.json");
        var root = document.RootElement;
        var migrations = root.GetProperty("migrations").EnumerateArray().Select(item => item.GetString()!).ToArray();
        var structure = new Dictionary<int, Dictionary<string, TableShape>>();
        foreach (var level in root.GetProperty("structureAfter").EnumerateObject())
        {
            var tables = new Dictionary<string, TableShape>(StringComparer.Ordinal);
            foreach (var table in level.Value.EnumerateObject())
            {
                var columns = table.Value.GetProperty("columns").EnumerateArray()
                    .Select(column => ColumnSignature(
                        column.GetProperty("name").GetString()!,
                        column.GetProperty("type").GetString()!,
                        column.GetProperty("notNull").GetBoolean() || column.GetProperty("primaryKey").GetInt32() > 0,
                        column.GetProperty("default").ValueKind == JsonValueKind.Null ? null : column.GetProperty("default").GetString(),
                        column.GetProperty("primaryKey").GetInt32()))
                    .Order(StringComparer.Ordinal).ToList();
                var indexes = table.Value.GetProperty("indexes").EnumerateArray()
                    .Select(index => IndexSignature(
                        index.GetProperty("name").ValueKind == JsonValueKind.Null ? null : index.GetProperty("name").GetString(),
                        index.GetProperty("unique").GetBoolean(),
                        index.GetProperty("partial").GetBoolean(),
                        index.GetProperty("columns").EnumerateArray().Select(column => column.GetString()!).ToList()))
                    .Order(StringComparer.Ordinal).ToList();
                tables[table.Name] = new TableShape(columns, indexes);
            }
            structure[int.Parse(level.Name, System.Globalization.CultureInfo.InvariantCulture)] = tables;
        }
        return new Expected(migrations, structure);
    }
}
