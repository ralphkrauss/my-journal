using Journal.Api.Security;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;

namespace Journal.Api.Data;

public static class DatabaseStartup
{
    public const string DatabaseName = "journal.db";
    // The newest copy taken before migrations changed an existing database; each new copy replaces it.
    public const string PreMigrationCopy = "journal.pre-migration.db";

    public static string ConnectionString(string root) => new SqliteConnectionStringBuilder
    {
        DataSource = Path.Combine(root, DatabaseName),
        ForeignKeys = true,
        DefaultTimeout = 30,
    }.ToString();

    // Returns false, without changing anything, when a newer build has migrated the database: running
    // older code against a newer schema could lose or corrupt data it does not know about.
    public static async Task<bool> Migrate(JournalDb db, string root, AuditLog audit, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(db);
        ArgumentNullException.ThrowIfNull(audit);
        var database = Path.Combine(root, DatabaseName);
        if (File.Exists(database))
        {
            var known = db.Database.GetMigrations().ToHashSet(StringComparer.Ordinal);
            var applied = (await db.Database.GetAppliedMigrationsAsync(ct)).ToArray();
            if (applied.FirstOrDefault(migration => !known.Contains(migration)) is { } unknown)
            {
                audit.NewerDatabase(unknown);
                return false;
            }
            var pending = known.Count(migration => !applied.Contains(migration, StringComparer.Ordinal));
            if (applied.Length > 0 && pending > 0)
            {
                Copy(database, Path.Combine(root, PreMigrationCopy));
                audit.CopiedBeforeMigration(PreMigrationCopy, pending);
            }
        }
        await db.Database.MigrateAsync(ct);
        return true;
    }

    // A consistent SQLite online-backup copy, self-contained (no WAL), published by rename.
    private static void Copy(string database, string target)
    {
        var temporary = target + ".tmp";
        File.Delete(temporary);
        using (var source = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = database, Mode = SqliteOpenMode.ReadWrite, Pooling = false }.ToString()))
        using (var copy = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = temporary, Pooling = false }.ToString()))
        {
            source.Open();
            copy.Open();
            source.BackupDatabase(copy);
            using var mode = copy.CreateCommand();
            mode.CommandText = "PRAGMA journal_mode=DELETE";
            mode.ExecuteScalar();
        }
        if (!OperatingSystem.IsWindows())
        {
            File.SetUnixFileMode(temporary, UnixFileMode.UserRead | UnixFileMode.UserWrite);
        }
        File.Move(temporary, target, overwrite: true);
    }
}
