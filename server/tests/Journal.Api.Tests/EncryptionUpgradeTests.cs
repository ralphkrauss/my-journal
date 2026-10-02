using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Journal.Api.Data;
using Journal.Api.Features;
using Microsoft.Extensions.DependencyInjection;

namespace Journal.Api.Tests;

// Turning on encryption for a vault created without it (POST /v1/recovery/encrypt).
public sealed class EncryptionUpgradeTests
{
    private const string Canary = "Canary sentence only this journal contains";
    private static readonly string CanaryPayload = Convert.ToBase64String(Encoding.UTF8.GetBytes($"{{\"title\":\"{Canary}\"}}"));

    private static TurnOnEncryptionRequest Encrypt(long after, Guid? record = null, long? revision = null, string? current = null, byte marker = 7) => new(
        Convert.ToBase64String(Enumerable.Repeat(marker, 16).ToArray()), Convert.ToBase64String(Enumerable.Repeat(marker, 60).ToArray()),
        600_000, new string('c', 64), 2, after, record, revision, current);

    // A vault without encryption or password (format 4), as new libraries without encryption create.
    private static async Task<HttpClient> SetUpWithoutEncryption(JournalFactory factory)
    {
        var client = factory.CreateClient();
        var code = await File.ReadAllTextAsync(Path.Combine(factory.Root, "setup-code"));
        var response = await client.PostAsJsonAsync("/v1/setup", new SetupRequest(code, "", "", 0, new string('a', 64), "Mac", 4));
        response.EnsureSuccessStatusCode();
        var grant = (await response.Content.ReadFromJsonAsync<DeviceGrant>())!;
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", grant.Token);
        return client;
    }

    private static async Task<HttpClient> AddDevice(JournalFactory factory)
    {
        var code = await RecoveryCode.Create(factory.Root);
        var client = factory.CreateClient();
        var response = await client.PostAsJsonAsync("/v1/recovery", new RecoveryRequest(code, "iPhone"));
        response.EnsureSuccessStatusCode();
        var grant = (await response.Content.ReadFromJsonAsync<DeviceGrant>())!;
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", grant.Token);
        return client;
    }

    // Writes a readable record and image; returns the newest change's cursor, record and revision.
    private static async Task<(long cursor, Guid record, long revision)> WriteReadableContent(HttpClient client)
    {
        var record = Guid.NewGuid();
        (await client.PutAsJsonAsync($"/v1/sync/{record}", new PutRecord(Guid.NewGuid(), 0, "entry", CanaryPayload))).EnsureSuccessStatusCode();
        (await client.PutAsJsonAsync($"/v1/sync/{record}", new PutRecord(Guid.NewGuid(), 1, "entry", CanaryPayload))).EnsureSuccessStatusCode();
        (await client.PutAsync($"/v1/attachments/{Guid.NewGuid()}", new ByteArrayContent(Encoding.UTF8.GetBytes(Canary)))).EnsureSuccessStatusCode();
        using var page = JsonDocument.Parse(await client.GetStringAsync("/v1/sync/?after=0"));
        return (page.RootElement.GetProperty("cursor").GetInt64(), record, 2);
    }

    private static async Task<JsonElement> Error(HttpResponseMessage response) =>
        (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("code");

    private static byte[] ReadShared(string path)
    {
        if (!File.Exists(path))
        {
            return [];
        }
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        using var copy = new MemoryStream();
        stream.CopyTo(copy);
        return copy.ToArray();
    }

    private static bool Contains(byte[] haystack, string text)
    {
        var needle = Encoding.UTF8.GetBytes(text);
        return haystack.AsSpan().IndexOf(needle) >= 0;
    }

    [Fact]
    public async Task TurningOnEncryptionRemovesEveryReadableCopyAndSignsOutOtherDevices()
    {
        using var factory = new JournalFactory();
        using var owner = await SetUpWithoutEncryption(factory);
        using var phone = await AddDevice(factory);
        var (cursor, record, revision) = await WriteReadableContent(owner);
        await File.WriteAllTextAsync(Path.Combine(factory.Root, DatabaseStartup.PreMigrationCopy), Canary);
        using var before = JsonDocument.Parse(await owner.GetStringAsync("/v1/status"));
        var oldServerId = before.RootElement.GetProperty("serverId").GetString();

        var response = await owner.PostAsJsonAsync("/v1/recovery/encrypt", Encrypt(cursor, record, revision));
        response.EnsureSuccessStatusCode();
        var serverId = (await response.Content.ReadFromJsonAsync<EncryptionResult>())!.ServerId;
        Assert.NotEqual(oldServerId, serverId);

        // Every other device is signed out; the requesting device keeps its access to upload its encrypted copy.
        Assert.Equal(HttpStatusCode.Unauthorized, (await phone.GetAsync("/v1/sync/")).StatusCode);
        using var page = JsonDocument.Parse(await owner.GetStringAsync("/v1/sync/?after=0"));
        Assert.Equal(0, page.RootElement.GetProperty("changes").GetArrayLength());
        Assert.Equal(serverId, page.RootElement.GetProperty("serverId").GetString());
        using var recovery = JsonDocument.Parse(await owner.GetStringAsync("/v1/recovery"));
        Assert.Equal(2, recovery.RootElement.GetProperty("formatVersion").GetInt32());

        // Nothing readable is left: no records, revisions, images, pre-migration copy or free database pages.
        Assert.Empty(Directory.EnumerateFiles(Path.Combine(factory.Root, "attachments")));
        Assert.False(File.Exists(Path.Combine(factory.Root, DatabaseStartup.PreMigrationCopy)));
        Assert.False(File.Exists(Path.Combine(factory.Root, EncryptionPurge.MarkerName)));
        foreach (var file in new[] { "journal.db", "journal.db-wal" })
        {
            var bytes = ReadShared(Path.Combine(factory.Root, file));
            Assert.False(Contains(bytes, Canary) || Contains(bytes, CanaryPayload[..24]), $"{file} still holds readable content");
        }

        // Sending the same request again, as after a lost answer, succeeds without changing anything.
        var retry = await owner.PostAsJsonAsync("/v1/recovery/encrypt", Encrypt(cursor, record, revision));
        Assert.Equal(serverId, (await retry.Content.ReadFromJsonAsync<EncryptionResult>())!.ServerId);
        // The encrypted copy is uploaded as new records.
        (await owner.PutAsJsonAsync($"/v1/sync/{record}", new PutRecord(Guid.NewGuid(), 0, "entry", Convert.ToBase64String(new byte[40]), serverId))).EnsureSuccessStatusCode();
    }

    [Fact]
    public async Task AnEncryptedVaultRefusesReadableRecords()
    {
        using var factory = new JournalFactory();
        using var owner = await SetUpWithoutEncryption(factory);
        var (cursor, record, revision) = await WriteReadableContent(owner);
        (await owner.PostAsJsonAsync("/v1/recovery/encrypt", Encrypt(cursor, record, revision))).EnsureSuccessStatusCode();

        // A sync of the unencrypted library that continues after the switch can't add readable journals to it.
        var readable = await owner.PutAsJsonAsync($"/v1/sync/{record}", new PutRecord(Guid.NewGuid(), 0, "entry", CanaryPayload));
        Assert.Equal(HttpStatusCode.BadRequest, readable.StatusCode);
        Assert.Equal("unencrypted_record", (await Error(readable)).GetString());
        using var page = JsonDocument.Parse(await owner.GetStringAsync("/v1/sync/?after=0"));
        Assert.Equal(0, page.RootElement.GetProperty("changes").GetArrayLength());
    }

    [Fact]
    public async Task RefusesWhenTheDeviceHasNotReadEveryChange()
    {
        using var factory = new JournalFactory();
        using var owner = await SetUpWithoutEncryption(factory);
        var (cursor, record, revision) = await WriteReadableContent(owner);

        var stale = await owner.PostAsJsonAsync("/v1/recovery/encrypt", Encrypt(cursor - 1));
        Assert.Equal(HttpStatusCode.Conflict, stale.StatusCode);
        Assert.Equal("server_changed", (await Error(stale)).GetString());
        var otherChange = await owner.PostAsJsonAsync("/v1/recovery/encrypt", Encrypt(cursor, record, revision + 1));
        Assert.Equal("server_changed", (await Error(otherChange)).GetString());

        using var recovery = JsonDocument.Parse(await owner.GetStringAsync("/v1/recovery"));
        Assert.Equal(4, recovery.RootElement.GetProperty("formatVersion").GetInt32());
        using var page = JsonDocument.Parse(await owner.GetStringAsync("/v1/sync/?after=0"));
        Assert.Equal(2, page.RootElement.GetProperty("changes").GetArrayLength());
    }

    [Fact]
    public async Task AnAccessPasswordLibraryNeedsItsCurrentPassword()
    {
        using var factory = new JournalFactory();
        var (owner, _) = await factory.SetUp(3);
        using (owner)
        {
            var missing = await owner.PostAsJsonAsync("/v1/recovery/encrypt", Encrypt(0));
            Assert.Equal(HttpStatusCode.Forbidden, missing.StatusCode);
            Assert.Equal("wrong_password", (await Error(missing)).GetString());
            Assert.Equal(HttpStatusCode.Forbidden, (await owner.PostAsJsonAsync("/v1/recovery/encrypt", Encrypt(0, current: new string('z', 64)))).StatusCode);
            (await owner.PostAsJsonAsync("/v1/recovery/encrypt", Encrypt(0, current: new string('a', 64)))).EnsureSuccessStatusCode();
        }
    }

    [Fact]
    public async Task RefusesAVaultThatIsAlreadyEncrypted()
    {
        using var factory = new JournalFactory();
        var (owner, _) = await factory.SetUp(2);
        using (owner)
        {
            var response = await owner.PostAsJsonAsync("/v1/recovery/encrypt", Encrypt(0));
            Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
            Assert.Equal("unsupported_format", (await Error(response)).GetString());
        }
        using var second = new JournalFactory();
        using var device = await SetUpWithoutEncryption(second);
        (await device.PostAsJsonAsync("/v1/recovery/encrypt", Encrypt(0))).EnsureSuccessStatusCode();
        // Another device's attempt, with its own envelope, finds the vault already encrypted.
        var other = await device.PostAsJsonAsync("/v1/recovery/encrypt", Encrypt(0, marker: 9));
        Assert.Equal("unsupported_format", (await Error(other)).GetString());
    }

    [Fact]
    public async Task AttemptsAreRateLimitedPerDevice()
    {
        using var factory = new JournalFactory();
        var (owner, _) = await factory.SetUp(3);
        using (owner)
        {
            var statuses = new List<HttpStatusCode>();
            for (var attempt = 0; attempt < 11; attempt++)
            {
                statuses.Add((await owner.PostAsJsonAsync("/v1/recovery/encrypt", Encrypt(0, current: new string('z', 64)))).StatusCode);
            }
            Assert.All(statuses.Take(10), status => Assert.Equal(HttpStatusCode.Forbidden, status));
            Assert.Equal(HttpStatusCode.TooManyRequests, statuses[^1]);
        }
    }

    [Fact]
    public async Task APurgeInterruptedByAStopFinishesAtTheNextStart()
    {
        var parent = Path.Combine(Path.GetTempPath(), "journal-purge-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(parent);
        try
        {
            string serverId;
            using (var factory = new JournalFactory())
            {
                using var owner = await SetUpWithoutEncryption(factory);
                await WriteReadableContent(owner);
                using var status = JsonDocument.Parse(await owner.GetStringAsync("/v1/status"));
                serverId = status.RootElement.GetProperty("serverId").GetString()!;
                await BackupArchive.Create(factory.Root, Path.Combine(parent, "backup"));
            }
            // The vault switched, but the server stopped before its files were removed.
            var root = Path.Combine(parent, "data");
            var images = Path.Combine(root, "attachments");
            Directory.CreateDirectory(images);
            File.Copy(Path.Combine(parent, "backup", "journal.db"), Path.Combine(root, "journal.db"));
            var kept = Directory.EnumerateFiles(Path.Combine(parent, "backup", "attachments")).Single();
            File.Copy(kept, Path.Combine(images, Path.GetFileName(kept)));
            var orphan = Path.Combine(images, Guid.NewGuid().ToString("D"));
            await File.WriteAllTextAsync(orphan, Canary);
            await File.WriteAllTextAsync(Path.Combine(root, DatabaseStartup.PreMigrationCopy), Canary);
            await File.WriteAllTextAsync(Path.Combine(root, EncryptionPurge.MarkerName), serverId);

            using (var restarted = new JournalFactory(root))
            {
                using var client = restarted.CreateClient();
                (await client.GetAsync("/health")).EnsureSuccessStatusCode();
                Assert.False(File.Exists(orphan));
                Assert.True(File.Exists(Path.Combine(images, Path.GetFileName(kept))), "Images the vault refers to stay");
                Assert.False(File.Exists(Path.Combine(root, DatabaseStartup.PreMigrationCopy)));
                Assert.False(File.Exists(Path.Combine(root, EncryptionPurge.MarkerName)));
            }
        }
        finally
        {
            if (Directory.Exists(parent))
            {
                Directory.Delete(parent, true);
            }
        }
    }

    [Fact]
    public async Task AMarkerFromARequestThatNeverCommittedRemovesNothing()
    {
        using var factory = new JournalFactory();
        using var owner = await SetUpWithoutEncryption(factory);
        await WriteReadableContent(owner);
        var marker = Path.Combine(factory.Root, EncryptionPurge.MarkerName);
        await File.WriteAllTextAsync(marker, Guid.NewGuid().ToString("D"));
        using (var scope = factory.Services.CreateScope())
        {
            var services = scope.ServiceProvider;
            await EncryptionPurge.Finish(
                services.GetRequiredService<JournalDb>(), services.GetRequiredService<Journal.Api.Security.StoragePaths>(),
                services.GetRequiredService<Journal.Api.Security.AuditLog>(), CancellationToken.None);
        }
        Assert.Single(Directory.EnumerateFiles(Path.Combine(factory.Root, "attachments")));
        Assert.False(File.Exists(marker));
    }

    // Operators filter and alert on audit events by ID: removing every record must not share an ID with an agent approval.
    [Fact]
    public void EveryAuditEventHasItsOwnId()
    {
        var ids = typeof(Journal.Api.Security.AuditLog).GetMethods()
            .SelectMany(x => x.GetCustomAttributes(typeof(Microsoft.Extensions.Logging.LoggerMessageAttribute), false).Cast<Microsoft.Extensions.Logging.LoggerMessageAttribute>(), (method, attribute) => (method.Name, attribute.EventId))
            .ToList();
        Assert.Contains(ids, x => x.Name == "EncryptionTurnedOn");
        Assert.Empty(ids.GroupBy(x => x.EventId).Where(x => x.Count() > 1).Select(x => string.Join(", ", x.Select(e => e.Name))));
    }
}
