using System.Security.Cryptography;
using System.Text.RegularExpressions;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Metadata;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.EntityFrameworkCore.Migrations.Operations;

namespace Journal.Api.Data;

public static partial class BackupArchive
{
    public const string RestoreMarker = "restore-in-progress";
    // Words that appear in the tables and indexes Journal's migrations create. Anything else in a
    // backup's schema (CHECK, ON CONFLICT, REFERENCES, generated columns, partial or expression
    // indexes) could change what restore and later revocations actually write.
    private static readonly HashSet<string> SchemaWords = new(StringComparer.OrdinalIgnoreCase)
    {
        "CREATE", "TABLE", "UNIQUE", "INDEX", "ON", "INTEGER", "TEXT", "BLOB", "REAL", "NUMERIC",
        "NOT", "NULL", "CONSTRAINT", "PRIMARY", "KEY", "AUTOINCREMENT", "DEFAULT",
    };
    // Tables SQLite itself maintains, with the definitions it always gives them.
    private static readonly Dictionary<string, string> InternalTables = new(StringComparer.Ordinal)
    {
        ["sqlite_sequence"] = "CREATE TABLE sqlite_sequence(name,seq)",
        ["sqlite_stat1"] = "CREATE TABLE sqlite_stat1(tbl,idx,stat)",
        ["sqlite_stat4"] = "CREATE TABLE sqlite_stat4(tbl,idx,neq,nlt,ndlt,sample)",
    };

    public static async Task Create(string root, string archive)
    {
        if (Path.Exists(Path.Combine(root, RestoreMarker)))
        {
            throw new IOException("Finish restoration before creating a backup.");
        }
        if (Path.Exists(archive))
        {
            throw new IOException("Choose a new backup destination.");
        }
        RequireRegular(root, directory: true);
        RequireRegular(Path.Combine(root, "journal.db"), directory: false);
        PrivateDirectory(archive);
        using (var source = Open(Path.Combine(root, "journal.db")))
        using (var destination = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = Path.Combine(archive, "journal.db"), Pooling = false }.ToString()))
        {
            destination.Open();
            source.BackupDatabase(destination);
            // Agent access stays out of backups: tokens, key wraps and copies are useless without live tokens anyway.
            using (var secure = destination.CreateCommand())
            {
                secure.CommandText = "PRAGMA secure_delete=ON";
                secure.ExecuteNonQuery();
            }
            using (var transaction = destination.BeginTransaction())
            {
                RemoveAgents(destination, transaction);
                transaction.Commit();
            }
            using (var vacuum = destination.CreateCommand())
            {
                vacuum.CommandText = "VACUUM";
                vacuum.ExecuteNonQuery();
            }
            using var checkpoint = destination.CreateCommand();
            checkpoint.CommandText = "PRAGMA journal_mode=DELETE";
            checkpoint.ExecuteScalar();
        }
        PrivateDirectory(Path.Combine(archive, "attachments"));
        using (var snapshot = Open(Path.Combine(archive, "journal.db"), snapshot: true))
        {
            foreach (var attachment in Attachments(snapshot))
            {
                var source = Path.Combine(root, "attachments", attachment.Name);
                RequireRegular(Path.Combine(root, "attachments"), directory: true);
                RequireRegular(source, directory: false);
                File.Copy(source, Path.Combine(archive, "attachments", attachment.Name));
            }
        }
        await ValidateContents(archive);
        await File.WriteAllTextAsync(Path.Combine(archive, "database-sha256"), await Digest(Path.Combine(archive, "journal.db")));
        // Written last: a partial backup is never advertised as complete.
        await File.WriteAllTextAsync(Path.Combine(archive, "backup-version"), "2");
    }

    // Returns how many devices were signed out. A backup can predate later revocations, so every
    // restored device credential is revoked and devices reconnect with the journal's credentials.
    public static async Task<int> Restore(string archive, string root)
    {
        await Validate(archive);
        if (Path.Exists(root))
        {
            RequireRegular(root, directory: true);
            if (Directory.EnumerateFileSystemEntries(root).Any())
            {
                throw new IOException("Restore requires an empty data directory and a stopped server.");
            }
        }
        PrivateDirectory(root);
        // A directory rename cannot replace a mounted container volume. This marker blocks startup
        // until validated files have been published within the same volume.
        await File.WriteAllTextAsync(Path.Combine(root, RestoreMarker), "1");
        var staged = Path.Combine(root, "restore-" + Guid.NewGuid().ToString("N"));
        PrivateDirectory(staged);
        File.Copy(Path.Combine(archive, "journal.db"), Path.Combine(staged, "journal.db"));
        PrivateDirectory(Path.Combine(staged, "attachments"));
        using (var database = Open(Path.Combine(staged, "journal.db"), snapshot: true))
        {
            foreach (var attachment in Attachments(database))
            {
                var source = Path.Combine(archive, "attachments", attachment.Name);
                RequireRegular(source, directory: false);
                File.Copy(source, Path.Combine(staged, "attachments", attachment.Name));
            }
        }
        await ValidateContents(staged);
        // Recheck the copied database against the source manifest, not just the source before copying.
        await ValidateDigest(archive, Path.Combine(staged, "journal.db"));
        var signedOut = PrepareRestoredDatabase(Path.Combine(staged, "journal.db"));
        File.Move(Path.Combine(staged, "journal.db"), Path.Combine(root, "journal.db"));
        Directory.Move(Path.Combine(staged, "attachments"), Path.Combine(root, "attachments"));
        Directory.Delete(staged);
        File.Delete(Path.Combine(root, RestoreMarker));
        return signedOut;
    }

    private static int PrepareRestoredDatabase(string path)
    {
        using var database = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Mode = SqliteOpenMode.ReadWrite, Pooling = false }.ToString());
        database.Open();
        DistrustSchema(database);
        using var transaction = database.BeginTransaction();
        using var revoke = database.CreateCommand();
        revoke.Transaction = transaction;
        revoke.CommandText = "UPDATE Devices SET Revoked = 1 WHERE Revoked = 0";
        var signedOut = revoke.ExecuteNonQuery();
        using var pairing = database.CreateCommand();
        pairing.Transaction = transaction;
        pairing.CommandText = "DELETE FROM PairRequests";
        pairing.ExecuteNonQuery();
        RemoveAgents(database, transaction);
        SyncIdentity.Replace(database, transaction);
        transaction.Commit();
        return signedOut;
    }

    // A restored backup may hold agents revoked since, so every agent grant, token, registered client and copy is
    // removed, as devices are signed out. Backups from before agent access have no such tables.
    private static void RemoveAgents(SqliteConnection database, SqliteTransaction transaction)
    {
        foreach (var table in new[] { "OAuthTokens", "AgentEvents", "AgentItems", "AgentGrants", "OAuthClients" })
        {
            using var exists = database.CreateCommand();
            exists.Transaction = transaction;
            exists.CommandText = "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = $name";
            exists.Parameters.AddWithValue("$name", table);
            if (Convert.ToInt64(exists.ExecuteScalar(), System.Globalization.CultureInfo.InvariantCulture) == 0)
            {
                continue;
            }
            using var delete = database.CreateCommand();
            delete.Transaction = transaction;
            delete.CommandText = "DELETE FROM \"" + table + "\"";
            delete.ExecuteNonQuery();
        }
    }

    public static async Task Validate(string archive)
    {
        RequireRegular(archive, directory: true);
        RequireRegular(Path.Combine(archive, "backup-version"), directory: false);
        var version = (await File.ReadAllTextAsync(Path.Combine(archive, "backup-version"))).Trim();
        if (version is not ("1" or "2"))
        {
            throw new IOException("Unsupported or incomplete backup.");
        }
        await ValidateContents(archive);
        await ValidateDigest(archive, Path.Combine(archive, "journal.db"));
    }

    private static async Task ValidateDigest(string archive, string database)
    {
        var version = (await File.ReadAllTextAsync(Path.Combine(archive, "backup-version"))).Trim();
        if (version == "1")
        {
            return;
        }
        RequireRegular(Path.Combine(archive, "database-sha256"), directory: false);
        var expected = (await File.ReadAllTextAsync(Path.Combine(archive, "database-sha256"))).Trim();
        if (!StringComparer.OrdinalIgnoreCase.Equals(expected, await Digest(database)))
        {
            throw new IOException("The backup database is damaged or has changed.");
        }
    }

    private static async Task ValidateContents(string archive)
    {
        var database = Path.Combine(archive, "journal.db");
        RequireRegular(database, directory: false);
        RequireRegular(Path.Combine(archive, "attachments"), directory: true);
        if (Path.Exists(database + "-wal") || Path.Exists(database + "-journal"))
        {
            throw new IOException("Use a completed Journal backup, not a copied live database.");
        }
        using var connection = Open(database, snapshot: true);
        using var integrity = connection.CreateCommand();
        integrity.CommandText = "PRAGMA integrity_check";
        if (!Equals(integrity.ExecuteScalar(), "ok"))
        {
            throw new IOException("The backup database is damaged.");
        }
        using var context = new JournalDb(new DbContextOptionsBuilder<JournalDb>().UseSqlite(connection).Options);
        ValidateSchemaObjects(connection, context);
        var applied = (await context.Database.GetAppliedMigrationsAsync()).ToArray();
        var known = context.Database.GetMigrations().ToArray();
        if (applied.Length == 0 || !applied.SequenceEqual(known.Take(applied.Length), StringComparer.Ordinal))
        {
            throw new IOException("This backup uses an unsupported database version.");
        }
        // An older backup lacks columns and tables added by later migrations; startup adds them.
        var added = AddedLater(context, known.Skip(applied.Length));
        foreach (var entity in context.Model.GetEntityTypes())
        {
            var table = entity.GetTableName() ?? throw new IOException("Unsupported backup table.");
            if (added.Contains((table, null)))
            {
                continue;
            }
            var identifier = StoreObjectIdentifier.Table(table, entity.GetSchema());
            var columns = entity.GetProperties()
                .Select(property => property.GetColumnName(identifier) ?? property.Name)
                .Where(column => !added.Contains((table, column)))
                .Select(column => Quote(table) + "." + Quote(column));
            using var schema = connection.CreateCommand();
            schema.CommandText = "SELECT " + string.Join(",", columns) + " FROM " + Quote(table) + " LIMIT 0";
            using var rows = schema.ExecuteReader();
        }
        foreach (var attachment in Attachments(connection))
        {
            var path = Path.Combine(archive, "attachments", attachment.Name);
            RequireRegular(path, directory: false);
            if (new FileInfo(path).Length != attachment.Length || !StringComparer.OrdinalIgnoreCase.Equals(await Digest(path), attachment.Hash))
            {
                throw new IOException("A backup image is missing, damaged, or has changed.");
            }
        }
    }

    // Restore writes to the restored database (revoking every device) and then publishes its schema.
    // Only the tables and indexes Journal creates are accepted: a trigger, for example, could undo
    // those revocations and every later one.
    private static void ValidateSchemaObjects(SqliteConnection connection, JournalDb context)
    {
        // Every name a known migration creates, so older backups remain valid after later migrations
        // rename or drop tables and indexes.
        var tables = new HashSet<string>(StringComparer.Ordinal) { HistoryRepository.DefaultTableName, "__EFMigrationsLock" };
        var indexes = new HashSet<string>(StringComparer.Ordinal);
        var assembly = context.GetService<IMigrationsAssembly>();
        foreach (var migration in assembly.Migrations.Values.Select(type => assembly.CreateMigration(type, context.Database.ProviderName ?? "")))
        {
            foreach (var operation in migration.UpOperations)
            {
                switch (operation)
                {
                    case CreateTableOperation table:
                        tables.Add(table.Name);
                        break;
                    case RenameTableOperation { NewName: { } renamed }:
                        tables.Add(renamed);
                        break;
                    case CreateIndexOperation index:
                        indexes.Add(index.Name);
                        break;
                    case RenameIndexOperation index:
                        indexes.Add(index.NewName);
                        break;
                    default:
                        break;
                }
            }
        }
        using var query = connection.CreateCommand();
        query.CommandText = "SELECT type, name, sql FROM sqlite_master";
        using var reader = query.ExecuteReader();
        while (reader.Read())
        {
            var type = reader.GetString(0);
            var name = reader.GetString(1);
            var sql = reader.IsDBNull(2) ? null : reader.GetString(2);
            var expected = type switch
            {
                "table" when InternalTables.TryGetValue(name, out var definition) => sql == definition,
                "table" => tables.Contains(name) && sql is not null && OnlySchemaWords(sql),
                "index" when sql is null => name.StartsWith("sqlite_autoindex_", StringComparison.Ordinal),
                "index" => indexes.Contains(name) && OnlySchemaWords(sql),
                _ => false,
            };
            if (!expected)
            {
                throw new IOException("The backup database contains schema objects that Journal does not create.");
            }
        }
    }

    private static bool OnlySchemaWords(string sql) => SchemaToken().Matches(sql).All(token =>
        token.Groups["word"].Success ? SchemaWords.Contains(token.Value) : !token.Groups["other"].Success);

    // Quoted identifiers, string literals, numbers, words, punctuation, whitespace, or anything else.
    [GeneratedRegex("""("(?:[^"]|"")*"|'(?:[^']|'')*'|-?[0-9]+(?:\.[0-9]+)?|(?<word>[A-Za-z_][A-Za-z0-9_]*)|[(),]|\s+|(?<other>.))""", RegexOptions.CultureInvariant | RegexOptions.Singleline)]
    private static partial Regex SchemaToken();

    private static HashSet<(string Table, string? Column)> AddedLater(JournalDb context, IEnumerable<string> migrations)
    {
        var assembly = context.GetService<IMigrationsAssembly>();
        var added = new HashSet<(string, string?)>();
        foreach (var id in migrations)
        {
            var migration = assembly.CreateMigration(assembly.Migrations[id], context.Database.ProviderName ?? "");
            foreach (var operation in migration.UpOperations)
            {
                switch (operation)
                {
                    case AddColumnOperation column:
                        added.Add((column.Table, column.Name));
                        break;
                    case CreateTableOperation table:
                        added.Add((table.Name, null));
                        break;
                    default:
                        break;
                }
            }
        }
        return added;
    }

    private static IEnumerable<(string Name, long Length, string Hash)> Attachments(SqliteConnection database)
    {
        using var query = database.CreateCommand();
        query.CommandText = "SELECT Id, Length, Sha256 FROM Attachments";
        using var reader = query.ExecuteReader();
        while (reader.Read())
        {
            if (!Guid.TryParse(reader.GetString(0), out var id))
            {
                throw new IOException("Invalid backup image identifier.");
            }
            yield return (id.ToString("D"), reader.GetInt64(1), reader.GetString(2));
        }
    }

    private static string Quote(string identifier) => "\"" + identifier.Replace("\"", "\"\"", StringComparison.Ordinal) + "\"";

    private static SqliteConnection Open(string path, bool snapshot = false)
    {
        var connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = snapshot ? new Uri(Path.GetFullPath(path)).AbsoluteUri + "?immutable=1" : path, Mode = SqliteOpenMode.ReadOnly, Pooling = false }.ToString());
        connection.Open();
        DistrustSchema(connection);
        return connection;
    }
    // Backup databases are untrusted: functions with side effects are refused inside their schema.
    private static void DistrustSchema(SqliteConnection connection)
    {
        using var pragma = connection.CreateCommand();
        pragma.CommandText = "PRAGMA trusted_schema=OFF";
        pragma.ExecuteNonQuery();
    }
    private static async Task<string> Digest(string path)
    {
        await using var stream = File.OpenRead(path);
        return Convert.ToHexString(await SHA256.HashDataAsync(stream));
    }
    private static void RequireRegular(string path, bool directory)
    {
        var attributes = File.GetAttributes(path);
        if ((attributes & FileAttributes.ReparsePoint) != 0 || ((attributes & FileAttributes.Directory) != 0) != directory)
        {
            throw new IOException("Backup files must be regular files and directories, not symbolic links.");
        }
    }
    private static void PrivateDirectory(string path)
    {
        Directory.CreateDirectory(path);
        if (!OperatingSystem.IsWindows())
        {
            File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        }
    }
}
