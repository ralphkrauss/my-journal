using System.Diagnostics;
using System.Net.Http.Json;
using System.Security.Cryptography;
using Journal.Api.Data;
using Journal.Api.Features;
using Microsoft.Data.Sqlite;

namespace Journal.Api.Tests;

public sealed class BackupTests
{
    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task InterruptedRestoreOrMissingRestoreArgumentCannotStartServer(bool interrupted)
    {
        var root = Path.Combine(Path.GetTempPath(), "journal-restore-guard-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        var start = new ProcessStartInfo("dotnet") { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false };
        start.ArgumentList.Add(typeof(Program).Assembly.Location);
        start.Environment["Journal__DataDirectory"] = root;
        start.Environment["ASPNETCORE_URLS"] = "http://127.0.0.1:0";
        if (interrupted)
        {
            await File.WriteAllTextAsync(Path.Combine(root, BackupArchive.RestoreMarker), "1");
        }
        else
        {
            start.ArgumentList.Add("--restore");
        }
        using var child = new Process { StartInfo = start };
        var started = false;
        try
        {
            if (interrupted)
            {
                var backup = Path.Combine(root, "incomplete-backup");
                await Assert.ThrowsAsync<IOException>(() => BackupArchive.Create(root, backup));
                Assert.False(Directory.Exists(backup));
            }
            started = child.Start();
            Assert.True(started);
            var output = child.StandardOutput.ReadToEndAsync();
            var errors = child.StandardError.ReadToEndAsync();
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
            await child.WaitForExitAsync(timeout.Token);
            Assert.Equal(interrupted ? 1 : 2, child.ExitCode);
            Assert.DoesNotContain("Now listening", await output, StringComparison.Ordinal);
            Assert.NotEmpty(await errors);
            Assert.False(File.Exists(Path.Combine(root, "journal.db")));
        }
        finally
        {
            if (started && !child.HasExited)
            {
                child.Kill(entireProcessTree: true);
                await child.WaitForExitAsync();
            }
            Directory.Delete(root, true);
        }
    }

    [Fact]
    public async Task LiveSnapshotRestoresExactRevisionAndImageWithoutOverwritingExistingData()
    {
        using var factory = new JournalFactory();
        var (client, _) = await factory.SetUp();
        var root = Path.Combine(Path.GetTempPath(), "journal-backup-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var id = Guid.NewGuid();
            var image = Enumerable.Repeat((byte)42, 100).ToArray();
            (await client.PutAsync($"/v1/attachments/{id}", new ByteArrayContent(image))).EnsureSuccessStatusCode();
            var record = Guid.NewGuid();
            var payload = Convert.ToBase64String(new byte[60]);
            (await client.PutAsJsonAsync($"/v1/sync/{record}", new PutRecord(Guid.NewGuid(), 0, "entry", payload))).EnsureSuccessStatusCode();
            var backup = Path.Combine(root, "backup");
            await BackupArchive.Create(factory.Root, backup);
            (await client.PutAsJsonAsync($"/v1/sync/{record}", new PutRecord(Guid.NewGuid(), 1, "entry", Convert.ToBase64String(image)))).EnsureSuccessStatusCode();
            var restored = Path.Combine(root, "restored");
            Directory.CreateDirectory(restored); // Existing empty directories include container mount points.
            await BackupArchive.Restore(backup, restored);
            Assert.False(File.Exists(Path.Combine(restored, BackupArchive.RestoreMarker)));
            Assert.Equal(image, await File.ReadAllBytesAsync(Path.Combine(restored, "attachments", id.ToString("D"))));
            using var database = new SqliteConnection($"Data Source={Path.Combine(restored, "journal.db")};Pooling=False");
            database.Open();
            using var command = database.CreateCommand();
            command.CommandText = "SELECT Revision FROM Records";
            Assert.Equal(1L, command.ExecuteScalar());
            await Assert.ThrowsAsync<IOException>(() => BackupArchive.Restore(backup, restored));
            Assert.Equal(1L, command.ExecuteScalar());
        }
        finally { Directory.Delete(root, true); }
    }

    [Fact]
    public async Task DamagedImageOrDatabaseIsRejectedBeforeCreatingTarget()
    {
        using var factory = new JournalFactory();
        var (client, _) = await factory.SetUp();
        var root = Path.Combine(Path.GetTempPath(), "journal-backup-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var id = Guid.NewGuid();
            var image = Enumerable.Repeat((byte)17, 100).ToArray();
            (await client.PutAsync($"/v1/attachments/{id}", new ByteArrayContent(image))).EnsureSuccessStatusCode();
            var backup = Path.Combine(root, "backup");
            await BackupArchive.Create(factory.Root, backup);
            var file = Path.Combine(backup, "attachments", id.ToString("D"));
            await File.WriteAllBytesAsync(file, new byte[100]);
            var target = Path.Combine(root, "rejected");
            await Assert.ThrowsAsync<IOException>(() => BackupArchive.Restore(backup, target));
            Assert.False(Directory.Exists(target));
            await File.WriteAllBytesAsync(file, image);
            using (var database = new SqliteConnection($"Data Source={Path.Combine(backup, "journal.db")};Pooling=False"))
            {
                database.Open();
                using var command = database.CreateCommand();
                command.CommandText = "UPDATE Devices SET Name='Changed backup'";
                command.ExecuteNonQuery();
            }
            await Assert.ThrowsAsync<IOException>(() => BackupArchive.Restore(backup, target));
            Assert.False(Directory.Exists(target));
        }
        finally { Directory.Delete(root, true); }
    }

    [Fact]
    public async Task LegacyBackupValidatesSchemaAndRejectsLinkedImages()
    {
        using var factory = new JournalFactory();
        var (client, _) = await factory.SetUp();
        var root = Path.Combine(Path.GetTempPath(), "journal-backup-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var id = Guid.NewGuid();
            var image = new byte[100];
            (await client.PutAsync($"/v1/attachments/{id}", new ByteArrayContent(image))).EnsureSuccessStatusCode();
            var backup = Path.Combine(root, "backup");
            await BackupArchive.Create(factory.Root, backup);
            using (var legacy = new SqliteConnection($"Data Source={Path.Combine(backup, "journal.db")};Pooling=False"))
            {
                legacy.Open();
                using var mode = legacy.CreateCommand();
                mode.CommandText = "PRAGMA journal_mode=WAL";
                mode.ExecuteScalar();
            }
            await File.WriteAllTextAsync(Path.Combine(backup, "backup-version"), "1");
            File.Delete(Path.Combine(backup, "database-sha256"));
            await BackupArchive.Restore(backup, Path.Combine(root, "legacy"));
            var file = Path.Combine(backup, "attachments", id.ToString("D"));
            File.Delete(file);
            var external = Path.Combine(root, "external");
            await File.WriteAllBytesAsync(external, image);
            File.CreateSymbolicLink(file, external);
            await Assert.ThrowsAsync<IOException>(() => BackupArchive.Restore(backup, Path.Combine(root, "linked")));
            Assert.False(Directory.Exists(Path.Combine(root, "linked")));
            Assert.Equal(image, await File.ReadAllBytesAsync(external));
            File.Delete(file);
            await File.WriteAllBytesAsync(file, image);
            using (var damaged = new SqliteConnection($"Data Source={Path.Combine(backup, "journal.db")};Pooling=False"))
            {
                damaged.Open();
                using var removeColumn = damaged.CreateCommand();
                removeColumn.CommandText = "ALTER TABLE Records DROP COLUMN Payload";
                removeColumn.ExecuteNonQuery();
            }
            await Assert.ThrowsAsync<SqliteException>(() => BackupArchive.Restore(backup, Path.Combine(root, "missing-column")));
            Assert.False(Directory.Exists(Path.Combine(root, "missing-column")));
        }
        finally { Directory.Delete(root, true); }
    }

    // Someone who can change stored backups can also replace their digest. Restore must still refuse
    // schema objects that would run or change writes, such as re-enabling revoked devices.
    [Theory]
    [InlineData("CREATE TRIGGER KeepAccess AFTER UPDATE OF Revoked ON Devices BEGIN UPDATE Devices SET Revoked = 0 WHERE Id = NEW.Id; END")]
    [InlineData("CREATE VIEW Everything AS SELECT * FROM Devices")]
    [InlineData("CREATE TABLE Extra (Id INTEGER)")]
    [InlineData("CREATE INDEX IX_Devices_Revoked ON Devices (Revoked)")]
    [InlineData("PRAGMA writable_schema=ON; UPDATE sqlite_master SET sql = replace(sql, '\"Revoked\" INTEGER NOT NULL', '\"Revoked\" INTEGER NOT NULL CHECK (\"Revoked\" = 0 OR \"Name\" <> ''Kept'')') WHERE name = 'Devices'")]
    public async Task BackupWithSchemaObjectsJournalDoesNotCreateIsRejected(string statement)
    {
        using var factory = new JournalFactory();
        await factory.SetUp();
        var root = Path.Combine(Path.GetTempPath(), "journal-backup-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var backup = Path.Combine(root, "backup");
            await BackupArchive.Create(factory.Root, backup);
            var database = Path.Combine(backup, "journal.db");
            using (var connection = new SqliteConnection($"Data Source={database};Pooling=False"))
            {
                connection.Open();
                using var command = connection.CreateCommand();
                command.CommandText = statement;
                command.ExecuteNonQuery();
            }
            await File.WriteAllTextAsync(Path.Combine(backup, "database-sha256"), Convert.ToHexString(SHA256.HashData(await File.ReadAllBytesAsync(database))));
            var target = Path.Combine(root, "restored");
            var error = await Assert.ThrowsAsync<IOException>(() => BackupArchive.Restore(backup, target));
            Assert.Contains("schema", error.Message, StringComparison.Ordinal);
            Assert.False(Directory.Exists(target));
        }
        finally { Directory.Delete(root, true); }
    }
}
