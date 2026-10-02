using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;

namespace Journal.Api.Data;

// Each database copy that clients synchronize with has a random identity. A restored backup gets a
// new one, so clients notice that change cursors and revisions restarted from an older state.
public static class SyncIdentity
{
    public static string NewId() => Guid.NewGuid().ToString("D");

    // Covers servers upgraded from a version without identities and backups restored from one.
    public static async Task EnsureAssigned(JournalDb db)
    {
        ArgumentNullException.ThrowIfNull(db);
        var vault = await db.Vaults.SingleOrDefaultAsync();
        if (vault is null || vault.SyncId.Length > 0)
        {
            return;
        }
        vault.SyncId = NewId();
        vault.SyncIdCursor = await db.Changes.MaxAsync(change => (long?)change.Cursor) ?? 0;
        await db.SaveChangesAsync();
    }

    // Restore replaces the identity in the staged copy before it is published. Older backups without
    // the column receive an identity when the server first starts and migrates them.
    internal static void Replace(SqliteConnection database, SqliteTransaction transaction)
    {
        using var columns = database.CreateCommand();
        columns.Transaction = transaction;
        columns.CommandText = "SELECT COUNT(*) FROM pragma_table_info('Vaults') WHERE name = 'SyncId'";
        if (Convert.ToInt64(columns.ExecuteScalar(), System.Globalization.CultureInfo.InvariantCulture) == 0)
        {
            return;
        }
        using var update = database.CreateCommand();
        update.Transaction = transaction;
        update.CommandText = "UPDATE Vaults SET SyncId = $id, SyncIdCursor = (SELECT COALESCE(MAX(Cursor), 0) FROM Changes)";
        update.Parameters.AddWithValue("$id", NewId());
        update.ExecuteNonQuery();
    }
}
