using Journal.Api.Security;
using Microsoft.EntityFrameworkCore;

namespace Journal.Api.Data;

// Removes what a vault kept before encryption was turned on (EncryptionEndpoints): image files it no longer
// refers to, the copy made before the last database migration, and the database's free pages and write-ahead log,
// which can still hold readable content. A marker file names the new server identity, so a server stopped part way
// finishes at its next start, and a marker left by a request that never committed removes nothing.
public static class EncryptionPurge
{
    public const string MarkerName = "encryption-purge";

    public static void Begin(StoragePaths paths, string serverId)
    {
        ArgumentNullException.ThrowIfNull(paths);
        var marker = Path.Combine(paths.Root, MarkerName);
        var temporary = marker + ".tmp";
        using (var file = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None))
        using (var writer = new StreamWriter(file))
        {
            writer.Write(serverId);
            writer.Flush();
            file.Flush(true);
        }
        File.Move(temporary, marker, overwrite: true);
    }

    public static async Task Finish(JournalDb db, StoragePaths paths, AuditLog audit, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(db);
        ArgumentNullException.ThrowIfNull(paths);
        ArgumentNullException.ThrowIfNull(audit);
        var marker = Path.Combine(paths.Root, MarkerName);
        if (!File.Exists(marker))
        {
            return;
        }
        var expected = (await File.ReadAllTextAsync(marker, ct)).Trim();
        var current = await db.Vaults.AsNoTracking().Select(vault => vault.SyncId).SingleOrDefaultAsync(ct);
        if (expected.Length > 0 && string.Equals(expected, current, StringComparison.Ordinal))
        {
            var kept = (await db.Attachments.AsNoTracking().Select(attachment => attachment.Id).ToListAsync(ct)).ToHashSet();
            foreach (var file in Directory.EnumerateFiles(paths.AttachmentDirectory))
            {
                var name = Path.GetFileName(file);
                // Uploads in progress use hidden temporary names and remove themselves.
                if (!name.StartsWith('.') && !(Guid.TryParse(name, out var id) && kept.Contains(id)))
                {
                    File.Delete(file);
                }
            }
            File.Delete(Path.Combine(paths.Root, DatabaseStartup.PreMigrationCopy));
            await db.Database.ExecuteSqlRawAsync("VACUUM", ct);
            await db.Database.ExecuteSqlRawAsync("PRAGMA wal_checkpoint(TRUNCATE)", ct);
            audit.EncryptionPurged();
        }
        File.Delete(marker);
    }
}
