using System.Diagnostics;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Journal.Api.Data;
using Journal.Api.Features;
using Microsoft.Data.Sqlite;

namespace Journal.Api.Tests;

public sealed class RestoreIdentityTests
{
    private static string Payload(byte value) => Convert.ToBase64String(Enumerable.Repeat(value, 60).ToArray());

    private static async Task<string?> ServerId(HttpClient client) =>
        (await client.GetFromJsonAsync<JsonElement>("/v1/status")).GetProperty("serverId").GetString();

    [Fact]
    public async Task RestoredServerHasNewIdentityMarksOlderChangesAndSignsOutEveryDevice()
    {
        var root = Path.Combine(Path.GetTempPath(), "journal-identity-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            string original;
            string token;
            using (var factory = new JournalFactory())
            {
                var (client, grant) = await factory.SetUp();
                token = grant.Token;
                original = (await ServerId(client))!;
                Assert.Equal(36, original.Length);
                (await client.PutAsJsonAsync($"/v1/sync/{Guid.NewGuid()}", new PutRecord(Guid.NewGuid(), 0, "entry", Payload(1)))).EnsureSuccessStatusCode();
                (await client.PostAsJsonAsync("/v1/pairing", new BeginPairing("Pending", PairingEndpoints.Commitment(new byte[32])))).EnsureSuccessStatusCode();
                await BackupArchive.Create(factory.Root, Path.Combine(root, "backup"));
                // A later change the backup doesn't contain.
                (await client.PutAsJsonAsync($"/v1/sync/{Guid.NewGuid()}", new PutRecord(Guid.NewGuid(), 0, "entry", Payload(2)))).EnsureSuccessStatusCode();
            }

            var restoredRoot = Path.Combine(root, "restored");
            Assert.Equal(1, await BackupArchive.Restore(Path.Combine(root, "backup"), restoredRoot));
            using var restored = new JournalFactory(restoredRoot);
            using var anonymous = restored.CreateClient();
            var replaced = await ServerId(anonymous);
            Assert.NotNull(replaced);
            Assert.NotEqual(original, replaced);
            using var owner = restored.CreateClient();
            owner.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
            Assert.Equal(HttpStatusCode.Unauthorized, (await owner.GetAsync("/v1/sync/")).StatusCode);

            // Reconnecting uses the recovery credential; the page reports which changes predate the new identity.
            var recovered = await anonymous.PostAsJsonAsync("/v1/recovery", new RecoveryRequest(new string('a', 64), "Reconnected"));
            var reconnected = (await recovered.Content.ReadFromJsonAsync<DeviceGrant>())!;
            owner.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", reconnected.Token);
            var page = await owner.GetFromJsonAsync<JsonElement>("/v1/sync/?after=0");
            Assert.Equal(replaced, page.GetProperty("serverId").GetString());
            Assert.Equal(1, page.GetProperty("serverIdCursor").GetInt64());
            Assert.Equal(1, page.GetProperty("changes").GetArrayLength());
            using var database = new SqliteConnection($"Data Source={Path.Combine(restoredRoot, "journal.db")};Pooling=False");
            database.Open();
            using var pending = database.CreateCommand();
            pending.CommandText = "SELECT COUNT(*) FROM PairRequests";
            Assert.Equal(0L, pending.ExecuteScalar());
        }
        finally { Directory.Delete(root, true); }
    }

    [Fact]
    public async Task BackupFromBeforeIdentitiesRestoresAndReceivesAnIdentityAtStartup()
    {
        var root = Path.Combine(Path.GetTempPath(), "journal-identity-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var backup = Path.Combine(root, "backup");
            using (var factory = new JournalFactory())
            {
                var (client, _) = await factory.SetUp();
                (await client.PutAsJsonAsync($"/v1/sync/{Guid.NewGuid()}", new PutRecord(Guid.NewGuid(), 0, "entry", Payload(1)))).EnsureSuccessStatusCode();
                await BackupArchive.Create(factory.Root, backup);
            }
            // Recreate the older schema: no identity or check-code columns, only the first migration applied.
            using (var legacy = new SqliteConnection($"Data Source={Path.Combine(backup, "journal.db")};Pooling=False"))
            {
                legacy.Open();
                using var downgrade = legacy.CreateCommand();
                downgrade.CommandText = """
                    ALTER TABLE Vaults DROP COLUMN SyncId; ALTER TABLE Vaults DROP COLUMN SyncIdCursor;
                    ALTER TABLE PairRequests DROP COLUMN KeyCommitment; ALTER TABLE PairRequests DROP COLUMN ApproverKey;
                    ALTER TABLE PairRequests DROP COLUMN Declined; ALTER TABLE PairRequests DROP COLUMN GrantDelivered;
                    ALTER TABLE PairRequests DROP COLUMN InviteProof;
                    ALTER TABLE Devices DROP COLUMN CreatedVia; ALTER TABLE Devices DROP COLUMN ApprovedByDeviceId;
                    ALTER TABLE Operations DROP COLUMN ChangeCursor;
                    DROP TABLE OAuthTokens; DROP TABLE OAuthClients; DROP TABLE AgentEvents; DROP TABLE AgentItems; DROP TABLE AgentGrants;
                    DELETE FROM __EFMigrationsHistory WHERE MigrationId NOT LIKE '%_Initial';
                    """;
                downgrade.ExecuteNonQuery();
            }
            await File.WriteAllTextAsync(Path.Combine(backup, "backup-version"), "1");
            File.Delete(Path.Combine(backup, "database-sha256"));
            var restoredRoot = Path.Combine(root, "restored");
            await BackupArchive.Restore(backup, restoredRoot);
            using var restored = new JournalFactory(restoredRoot);
            using var restoredClient = restored.CreateClient();
            Assert.NotNull(await ServerId(restoredClient));
        }
        finally { Directory.Delete(root, true); }
    }

    [Fact]
    public async Task WritesFromAnotherDatabaseOrAheadOfTheServerAreRejectedDistinctly()
    {
        using var factory = new JournalFactory();
        var (client, _) = await factory.SetUp();
        var serverId = await ServerId(client);
        var id = Guid.NewGuid();
        var ahead = await client.PutAsJsonAsync($"/v1/sync/{id}", new PutRecord(Guid.NewGuid(), 3, "entry", Payload(1), serverId));
        Assert.Equal(HttpStatusCode.Conflict, ahead.StatusCode);
        var aheadBody = await ahead.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("revision_ahead", aheadBody.GetProperty("error").GetString());
        Assert.Equal(JsonValueKind.Null, aheadBody.GetProperty("current").ValueKind);

        var first = new PutRecord(Guid.NewGuid(), 0, "entry", Payload(1), serverId);
        var receipt = await (await client.PutAsJsonAsync($"/v1/sync/{id}", first)).Content.ReadAsStringAsync();
        var stale = await client.PutAsJsonAsync($"/v1/sync/{id}", new PutRecord(Guid.NewGuid(), 0, "entry", Payload(2), serverId));
        Assert.Equal("revision_conflict", (await stale.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("error").GetString());

        var elsewhere = await client.PutAsJsonAsync($"/v1/sync/{id}", new PutRecord(Guid.NewGuid(), 1, "entry", Payload(3), Guid.NewGuid().ToString()));
        Assert.Equal("server_changed", (await elsewhere.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("error").GetString());
        // A retried operation still returns its original receipt whatever identity accompanies it.
        Assert.Equal(receipt, await (await client.PutAsJsonAsync($"/v1/sync/{id}", first with
        {
            ServerId = null
        })).Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task MaintenanceCommandsUseTheSameConfigurationOptionsAsTheServer()
    {
        using var factory = new JournalFactory();
        using var client = factory.CreateClient();
        var setup = await File.ReadAllTextAsync(Path.Combine(factory.Root, "setup-code"));
        (await client.PostAsJsonAsync("/v1/setup", new SetupRequest(setup, "", "", 0, new string('a', 64), "Mac", 4))).EnsureSuccessStatusCode();
        var backup = Path.Combine(Path.GetTempPath(), "journal-config-backup-" + Guid.NewGuid().ToString("N"));
        try
        {
            // No Journal__DataDirectory: the data directory comes only from a configuration option.
            var created = await RunServer("--backup", backup, "--Journal:DataDirectory=" + factory.Root);
            Assert.Equal(0, created.ExitCode);
            Assert.True(File.Exists(Path.Combine(backup, "backup-version")));
            var code = await RunServer("--Journal:DataDirectory", factory.Root, "--recovery-code");
            Assert.Equal(0, code.ExitCode);
            var recovered = await client.PostAsJsonAsync("/v1/recovery", new RecoveryRequest(code.Output.Trim(), "Phone"));
            Assert.Equal(HttpStatusCode.OK, recovered.StatusCode);
        }
        finally
        {
            if (Directory.Exists(backup))
            {
                Directory.Delete(backup, true);
            }
        }
    }

    private static async Task<(int ExitCode, string Output)> RunServer(params string[] arguments)
    {
        var start = new ProcessStartInfo("dotnet") { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false };
        start.ArgumentList.Add(typeof(Program).Assembly.Location);
        foreach (var argument in arguments)
        {
            start.ArgumentList.Add(argument);
        }
        start.Environment.Remove("Journal__DataDirectory");
        using var process = new Process { StartInfo = start };
        Assert.True(process.Start());
        try
        {
            var output = process.StandardOutput.ReadToEndAsync();
            var errors = process.StandardError.ReadToEndAsync();
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(30));
            await process.WaitForExitAsync(timeout.Token);
            Assert.True(process.ExitCode == 0, await errors);
            return (process.ExitCode, await output);
        }
        finally
        {
            // A command that hangs or a failed assertion must not leave the process running.
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
                await process.WaitForExitAsync();
            }
        }
    }
}
