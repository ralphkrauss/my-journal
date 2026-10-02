using System.Diagnostics;
using System.Security.Cryptography;
using Journal.Api.Data;
using Microsoft.Data.Sqlite;

namespace Journal.Api.Tests;

public sealed class DatabaseStartupTests
{
    // A self-contained copy of a current server database, in a new data directory.
    private static async Task<string> CurrentDatabase(string parent)
    {
        using (var factory = new JournalFactory())
        {
            await factory.SetUp();
            await BackupArchive.Create(factory.Root, Path.Combine(parent, "backup"));
        }
        var root = Path.Combine(parent, "data");
        Directory.CreateDirectory(Path.Combine(root, "attachments"));
        File.Copy(Path.Combine(parent, "backup", "journal.db"), Path.Combine(root, "journal.db"));
        return root;
    }

    private static void Execute(string database, string sql)
    {
        using var connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = database, Pooling = false }.ToString());
        connection.Open();
        using var command = connection.CreateCommand();
        command.CommandText = sql;
        command.ExecuteNonQuery();
    }

    private static long Count(string database, string sql)
    {
        using var connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = database, Pooling = false }.ToString());
        connection.Open();
        using var command = connection.CreateCommand();
        command.CommandText = sql;
        return Convert.ToInt64(command.ExecuteScalar(), System.Globalization.CultureInfo.InvariantCulture);
    }

    [Fact]
    public async Task StartupRefusesADatabaseMigratedByANewerVersionWithoutChangingIt()
    {
        var parent = Path.Combine(Path.GetTempPath(), "journal-downgrade-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(parent);
        try
        {
            var root = await CurrentDatabase(parent);
            var database = Path.Combine(root, "journal.db");
            Execute(database, "INSERT INTO __EFMigrationsHistory (MigrationId, ProductVersion) VALUES ('29991231000000_FromANewerVersion', '99.0.0')");
            var before = Convert.ToHexString(SHA256.HashData(await File.ReadAllBytesAsync(database)));

            var start = new ProcessStartInfo("dotnet") { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false };
            start.ArgumentList.Add(typeof(Program).Assembly.Location);
            start.Environment["Journal__DataDirectory"] = root;
            start.Environment["ASPNETCORE_URLS"] = "http://127.0.0.1:0";
            using var child = new Process { StartInfo = start };
            Assert.True(child.Start());
            try
            {
                var output = child.StandardOutput.ReadToEndAsync();
                var errors = child.StandardError.ReadToEndAsync();
                using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(30));
                await child.WaitForExitAsync(timeout.Token);
                Assert.Equal(1, child.ExitCode);
                var log = await output + await errors;
                Assert.Contains("newer version of Journal", log, StringComparison.Ordinal);
                Assert.DoesNotContain("Now listening", log, StringComparison.Ordinal);
            }
            finally
            {
                if (!child.HasExited)
                {
                    child.Kill(entireProcessTree: true);
                    await child.WaitForExitAsync();
                }
            }
            var after = Convert.ToHexString(SHA256.HashData(await File.ReadAllBytesAsync(database)));
            Assert.Equal(before, after);
        }
        finally { Directory.Delete(parent, true); }
    }

    [Fact]
    public async Task PendingMigrationsFirstCopyTheExistingDatabase()
    {
        var parent = Path.Combine(Path.GetTempPath(), "journal-migration-copy-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(parent);
        try
        {
            var root = await CurrentDatabase(parent);
            // The database as the previous version left it.
            Execute(Path.Combine(root, "journal.db"), """
                ALTER TABLE PairRequests DROP COLUMN GrantDelivered;
                DELETE FROM __EFMigrationsHistory WHERE MigrationId LIKE '%_PairingGrantDelivery';
                """);
            using var factory = new JournalFactory(root);
            using var client = factory.CreateClient();
            (await client.GetAsync("/v1/status")).EnsureSuccessStatusCode();

            var copy = Path.Combine(root, DatabaseStartup.PreMigrationCopy);
            const string Delivered = "SELECT COUNT(*) FROM pragma_table_info('PairRequests') WHERE name = 'GrantDelivered'";
            Assert.Equal(0, Count(copy, Delivered));
            Assert.Equal(0, Count(copy, "SELECT COUNT(*) FROM __EFMigrationsHistory WHERE MigrationId LIKE '%_PairingGrantDelivery'"));
            Assert.Equal(1, Count(copy, "SELECT COUNT(*) FROM Devices"));
            Assert.Equal(1, Count(Path.Combine(root, "journal.db"), Delivered));
        }
        finally
        {
            if (Directory.Exists(parent))
            {
                Directory.Delete(parent, true);
            }
        }
    }
}
