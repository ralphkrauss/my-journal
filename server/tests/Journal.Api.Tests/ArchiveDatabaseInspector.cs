using System.Text.Json;
using Microsoft.Data.Sqlite;

namespace Journal.Api.Tests;

// The structure check of protocol/archive.md (Database), run before a database is opened as a library. It compares
// structure, not CREATE text, with the tables the recorded migrations create, which conformance/archive/v2/database-v2.json
// lists. It reads a copy of the file, read-only, and never writes to it.
//
// The order is the one the document gives, because each step must be safe given the ones before it: the file header,
// the size of the schema table from the file's pages (no SQL), the objects the schema lists (a virtual table connects the
// first time a statement or a pragma touches it, and quick_check touches every table), PRAGMA quick_check, and only then
// the recorded migrations and the pragmas. (Microsoft.Data.Sqlite cannot switch on SQLite's defensive mode, which the
// document also asks for; this reader only reads a copy.)
internal static class ArchiveDatabaseInspector
{
    private static readonly Lazy<Expected> Reference = new(Load);

    private sealed record Expected(string[] Migrations, Dictionary<int, Dictionary<string, TableShape>> StructureAfter, string[] IndexNamesOfLatest);

    // Columns, indexes and foreign keys as sorted signature texts, so that two tables are equal when their signatures are.
    private sealed record TableShape(List<string> Columns, List<string> Indexes, List<string> ForeignKeys, bool Autoincrement);

    private sealed record SchemaObject(string Type, string Name, string Table, long RootPage, string? Sql);

    // Returns normally when the database is acceptable. Throws damaged, or newer for a migration this reader does not know.
    public static void Inspect(string databaseFile)
    {
        RequireRollbackJournalHeader(databaseFile);
        ArchiveSchemaScan.Check(databaseFile);
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
        var objects = RequireLibraryObjects(ReadObjects(connection));
        var quickCheck = Strings(connection, "PRAGMA quick_check");
        if (quickCheck.Count != 1 || quickCheck[0] != "ok")
        {
            throw ArchiveRefusal.Damaged("PRAGMA quick_check does not report ok");
        }
        var known = Reference.Value.Migrations;
        // One more than there are migrations: more is a repeated identifier or an unknown one.
        var recorded = Strings(connection, $"SELECT identifier FROM grdb_migrations ORDER BY rowid LIMIT {known.Length + 1}");
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
        var actualTables = objects.Where(item => item.Type == "table" && item.Name != "sqlite_sequence").Select(item => item.Name).Order(StringComparer.Ordinal).ToList();
        if (!actualTables.SequenceEqual(expected.Keys.Order(StringComparer.Ordinal)))
        {
            throw ArchiveRefusal.Damaged($"the tables are {string.Join(", ", actualTables)}, not the ones the recorded migrations create");
        }
        var actual = ReadShapes(connection, objects.Where(item => item.Type == "table" && item.Name != "sqlite_sequence").ToList());
        foreach (var (table, shape) in expected)
        {
            RequireSame(table, actual[table], shape);
        }
    }

    private static void RequireSame(string table, TableShape actual, TableShape shape)
    {
        if (!actual.Columns.SequenceEqual(shape.Columns))
        {
            throw ArchiveRefusal.Damaged($"the columns of {table} differ: {string.Join("; ", actual.Columns)}");
        }
        if (!actual.Indexes.SequenceEqual(shape.Indexes))
        {
            throw ArchiveRefusal.Damaged($"the indexes of {table} differ: {string.Join("; ", actual.Indexes)}");
        }
        if (!actual.ForeignKeys.SequenceEqual(shape.ForeignKeys))
        {
            throw ArchiveRefusal.Damaged($"the foreign keys of {table} differ: {string.Join("; ", actual.ForeignKeys)}");
        }
        if (actual.Autoincrement != shape.Autoincrement)
        {
            throw ArchiveRefusal.Damaged($"{table} differs in AUTOINCREMENT");
        }
    }

    // At most MaxObjects rows: more is not a library (the file's pages were checked first, so this is cheap).
    private static List<SchemaObject> ReadObjects(SqliteConnection connection)
    {
        var objects = new List<SchemaObject>();
        using var command = connection.CreateCommand();
        command.CommandText = $"SELECT type, name, tbl_name, rootpage, sql FROM sqlite_master LIMIT {ArchiveSchemaScan.MaxObjects + 1}";
        using var reader = command.ExecuteReader();
        while (reader.Read())
        {
            objects.Add(new SchemaObject(reader.GetString(0), reader.GetString(1), reader.GetString(2), reader.GetInt64(3), reader.IsDBNull(4) ? null : reader.GetString(4)));
        }
        if (objects.Count > ArchiveSchemaScan.MaxObjects)
        {
            throw ArchiveRefusal.Damaged($"the schema has more than {ArchiveSchemaScan.MaxObjects} objects");
        }
        return objects;
    }

    // Only the library's own tables and indexes, written without the clauses no pragma reports. A table the pragmas
    // would connect (a virtual table) is refused here, before any of them runs.
    private static List<SchemaObject> RequireLibraryObjects(List<SchemaObject> objects)
    {
        var latest = Reference.Value.StructureAfter[Reference.Value.Migrations.Length];
        var tables = latest.Keys.Append("sqlite_sequence").ToHashSet(StringComparer.Ordinal);
        var indexes = Reference.Value.IndexNamesOfLatest.ToHashSet(StringComparer.Ordinal);
        foreach (var item in objects)
        {
            if (item.Type is not ("table" or "index"))
            {
                throw ArchiveRefusal.Damaged($"the database has {item.Type} {item.Name}");
            }
            if (item.RootPage <= 0)
            {
                throw ArchiveRefusal.Damaged($"{item.Type} {item.Name} has no pages");
            }
            if (item.Sql is null)
            {
                // The index SQLite makes for a primary key or a UNIQUE constraint has no statement of its own.
                if (item.Type != "index" || !item.Name.StartsWith("sqlite_autoindex_", StringComparison.Ordinal))
                {
                    throw ArchiveRefusal.Damaged($"{item.Type} {item.Name} has no statement");
                }
                continue;
            }
            var words = ArchiveSchemaWords.RefusedWordsIn(item.Sql).ToList();
            if (words.Count > 0)
            {
                throw ArchiveRefusal.Damaged($"{item.Type} {item.Name} uses {string.Join(", ", words)}");
            }
            if (!(item.Type == "table" ? tables : indexes).Contains(item.Name))
            {
                throw ArchiveRefusal.Damaged($"the database has {item.Type} {item.Name}, which the migrations do not create");
            }
        }
        return objects;
    }

    private static Dictionary<string, TableShape> ReadShapes(SqliteConnection connection, List<SchemaObject> tables)
    {
        var shapes = new Dictionary<string, TableShape>(StringComparer.Ordinal);
        var primaryKeys = new Dictionary<string, List<string>>(StringComparer.Ordinal);
        foreach (var table in tables)
        {
            RequireOrdinaryTable(connection, table.Name);
            var (columns, keys) = ReadColumns(connection, table.Name);
            primaryKeys[table.Name] = keys;
            shapes[table.Name] = new TableShape(columns, ReadIndexes(connection, table.Name), [], ArchiveSchemaWords.Words(table.Sql ?? "").Contains("AUTOINCREMENT"));
        }
        foreach (var table in tables)
        {
            shapes[table.Name] = shapes[table.Name] with
            {
                ForeignKeys = ReadForeignKeys(connection, table.Name, primaryKeys)
            };
        }
        return shapes;
    }

    // Not virtual (its module's code would run), not WITHOUT ROWID and not STRICT.
    private static void RequireOrdinaryTable(SqliteConnection connection, string table)
    {
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT type, wr, strict FROM pragma_table_list($table) WHERE schema = 'main' AND name = $table";
        command.Parameters.AddWithValue("$table", table);
        using var reader = command.ExecuteReader();
        if (!reader.Read() || reader.GetString(0) != "table")
        {
            throw ArchiveRefusal.Damaged($"table {table} is not an ordinary table");
        }
        if (reader.GetInt32(1) != 0 || reader.GetInt32(2) != 0)
        {
            throw ArchiveRefusal.Damaged($"table {table} is WITHOUT ROWID or STRICT");
        }
    }

    private static (List<string> Columns, List<string> PrimaryKey) ReadColumns(SqliteConnection connection, string table)
    {
        var columns = new List<string>();
        var primary = new List<(int Position, string Name)>();
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT name, type, \"notnull\", dflt_value, pk, hidden FROM pragma_table_xinfo($table)";
        command.Parameters.AddWithValue("$table", table);
        using var reader = command.ExecuteReader();
        while (reader.Read())
        {
            if (reader.GetInt32(5) != 0)
            {
                throw ArchiveRefusal.Damaged($"column {reader.GetString(0)} of {table} is hidden or generated");
            }
            var primaryKey = reader.GetInt32(4);
            var notNull = reader.GetInt32(2) != 0 || primaryKey > 0;
            var defaultValue = reader.IsDBNull(3) ? null : reader.GetString(3);
            columns.Add(ColumnSignature(reader.GetString(0), reader.GetString(1), notNull, defaultValue, primaryKey));
            if (primaryKey > 0)
            {
                primary.Add((primaryKey, reader.GetString(0)));
            }
        }
        columns.Sort(StringComparer.Ordinal);
        return (columns, primary.OrderBy(item => item.Position).Select(item => item.Name).ToList());
    }

    private static List<string> ReadIndexes(SqliteConnection connection, string table)
    {
        var indexes = new List<string>();
        var found = new List<(string Name, bool Unique, string Origin, bool Partial)>();
        using (var command = connection.CreateCommand())
        {
            command.CommandText = "SELECT name, \"unique\", origin, partial FROM pragma_index_list($table)";
            command.Parameters.AddWithValue("$table", table);
            using var reader = command.ExecuteReader();
            while (reader.Read())
            {
                found.Add((reader.GetString(0), reader.GetInt32(1) != 0, reader.GetString(2), reader.GetInt32(3) != 0));
            }
        }
        foreach (var index in found)
        {
            indexes.Add(IndexSignature(index.Origin == "c" ? index.Name : null, index.Unique, index.Partial, KeyColumns(connection, index.Name)));
        }
        indexes.Sort(StringComparer.Ordinal);
        return indexes;
    }

    // A key that names no parent column refers to the parent's primary key, and is read as that column.
    private static List<string> ReadForeignKeys(SqliteConnection connection, string table, Dictionary<string, List<string>> primaryKeys)
    {
        var keys = new List<string>();
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT \"table\", \"from\", \"to\", on_update, on_delete, \"match\" FROM pragma_foreign_key_list($table)";
        command.Parameters.AddWithValue("$table", table);
        using var reader = command.ExecuteReader();
        while (reader.Read())
        {
            var parent = reader.GetString(0);
            string? to = reader.IsDBNull(2) ? null : reader.GetString(2);
            if (to is null && primaryKeys.TryGetValue(parent, out var parentKey) && parentKey.Count == 1)
            {
                to = parentKey[0];
            }
            keys.Add(ForeignKeySignature(parent, reader.GetString(1), to, reader.GetString(3), reader.GetString(4), reader.GetString(5)));
        }
        keys.Sort(StringComparer.Ordinal);
        return keys;
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

    private static string ForeignKeySignature(string table, string from, string? to, string onUpdate, string onDelete, string match) =>
        $"{from}|{table}|{to ?? "no column"}|{onUpdate.ToUpperInvariant()}|{onDelete.ToUpperInvariant()}|{match.ToUpperInvariant()}";

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
                var foreignKeys = table.Value.GetProperty("foreignKeys").EnumerateArray()
                    .Select(key => ForeignKeySignature(
                        key.GetProperty("table").GetString()!,
                        key.GetProperty("from").GetString()!,
                        key.GetProperty("to").ValueKind == JsonValueKind.Null ? null : key.GetProperty("to").GetString(),
                        key.GetProperty("onUpdate").GetString()!,
                        key.GetProperty("onDelete").GetString()!,
                        key.GetProperty("match").GetString()!))
                    .Order(StringComparer.Ordinal).ToList();
                tables[table.Name] = new TableShape(columns, indexes, foreignKeys, table.Value.GetProperty("autoincrement").GetBoolean());
            }
            structure[int.Parse(level.Name, System.Globalization.CultureInfo.InvariantCulture)] = tables;
        }
        return new Expected(migrations, structure, IndexNamesIn(root.GetProperty("structureAfter").GetProperty(migrations.Length.ToString(System.Globalization.CultureInfo.InvariantCulture))));
    }

    // The names of the indexes made with CREATE INDEX in one structure of the document.
    private static string[] IndexNamesIn(JsonElement structure) =>
        structure.EnumerateObject()
            .SelectMany(table => table.Value.GetProperty("indexes").EnumerateArray())
            .Where(index => index.GetProperty("name").ValueKind != JsonValueKind.Null)
            .Select(index => index.GetProperty("name").GetString()!)
            .ToArray();
}
