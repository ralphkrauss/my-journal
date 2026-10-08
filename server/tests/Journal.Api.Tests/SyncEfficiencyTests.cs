using System.Diagnostics;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Journal.Api.Data;
using Journal.Api.Features;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace Journal.Api.Tests;

// Short push receipts and waiting for changes (docs/design/sync-protocol-efficiency.md §7.1).
public sealed class SyncEfficiencyTests
{
    private static readonly JsonSerializerOptions Web = new(JsonSerializerDefaults.Web);

    private static string Payload(byte value) => Convert.ToBase64String(Enumerable.Repeat(value, 60).ToArray());

    private static string Digest(string payload) => Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(payload)));

    // A library without encryption (format 4), so further devices can join with a recovery code.
    private static async Task<(HttpClient Client, DeviceGrant Grant)> SetUp(JournalFactory factory)
    {
        var client = factory.CreateClient();
        var code = await File.ReadAllTextAsync(Path.Combine(factory.Root, "setup-code"));
        var response = await client.PostAsJsonAsync("/v1/setup", new SetupRequest(code, "", "", 0, new string('a', 64), "Mac", 4));
        response.EnsureSuccessStatusCode();
        var grant = (await response.Content.ReadFromJsonAsync<DeviceGrant>())!;
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", grant.Token);
        return (client, grant);
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

    private static async Task<JsonElement> Put(HttpClient client, Guid id, PutRecord request)
    {
        var response = await client.PutAsJsonAsync($"/v1/sync/{id}", request);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<JsonElement>();
    }

    private static async Task<(HttpStatusCode Status, JsonElement Body)> Wait(HttpClient client, string query, CancellationToken ct = default)
    {
        var response = await client.GetAsync("/v1/sync/wait?" + query, ct);
        var text = await response.Content.ReadAsStringAsync(ct);
        return (response.StatusCode, text.Length == 0 ? default : JsonDocument.Parse(text).RootElement.Clone());
    }

    private static bool Changed(JsonElement body) => body.GetProperty("changed").GetBoolean();

    private static bool Early(JsonElement body) => body.TryGetProperty("early", out var early) && early.GetBoolean();

    private static async Task<string> ServerId(HttpClient client) =>
        (await client.GetFromJsonAsync<JsonElement>("/v1/status")).GetProperty("serverId").GetString()!;

    // protocol/conformance/sync/sync-receipts-v1.json: the server writes a short receipt exactly as the public vector shows.
    [Fact]
    public void ShortReceiptMatchesTheProtocolVector()
    {
        using var corpus = ConformanceFiles.Json("sync/sync-receipts-v1.json");
        var full = corpus.RootElement.GetProperty("fullReceipt");
        var expected = corpus.RootElement.GetProperty("shortReceipt");
        var receipt = new ShortReceipt(
            full.GetProperty("cursor").GetInt64(), full.GetProperty("recordId").GetGuid(), full.GetProperty("revision").GetInt64(),
            full.GetProperty("kind").GetString()!, full.GetProperty("deviceId").GetGuid(), full.GetProperty("modifiedAt").GetDateTimeOffset(),
            Digest(full.GetProperty("payload").GetString()!));
        var written = JsonDocument.Parse(JsonSerializer.Serialize(receipt, Web)).RootElement;
        Assert.Equal(
            expected.EnumerateObject().Select(member => (member.Name, member.Value.ToString())).OrderBy(member => member.Name),
            written.EnumerateObject().Select(member => (member.Name, member.Value.ToString())).OrderBy(member => member.Name));
    }

    [Fact]
    public async Task ShortReceiptOmitsThePayloadAndCarriesItsDigest()
    {
        using var factory = new JournalFactory();
        var (client, grant) = await SetUp(factory);
        var id = Guid.NewGuid();
        var receipt = await Put(client, id, new PutRecord(Guid.NewGuid(), 0, "entry", Payload(1), ShortReceipt: true));

        Assert.False(receipt.TryGetProperty("payload", out _));
        Assert.Equal(Digest(Payload(1)), receipt.GetProperty("payloadDigest").GetString());
        Assert.Equal(id, receipt.GetProperty("recordId").GetGuid());
        Assert.Equal(1, receipt.GetProperty("revision").GetInt64());
        Assert.Equal("entry", receipt.GetProperty("kind").GetString());
        Assert.Equal(grant.DeviceId, receipt.GetProperty("deviceId").GetGuid());
        Assert.True(receipt.GetProperty("cursor").GetInt64() > 0);
        Assert.True(receipt.TryGetProperty("modifiedAt", out _));
    }

    [Fact]
    public async Task RetriesChooseTheReceiptFormWithoutChangingTheOperation()
    {
        using var factory = new JournalFactory();
        var (client, _) = await SetUp(factory);
        var id = Guid.NewGuid();
        var full = new PutRecord(Guid.NewGuid(), 0, "entry", Payload(2));
        var first = await Put(client, id, full);
        var shortRetry = await Put(client, id, full with
        {
            ShortReceipt = true
        });
        var fullRetry = await Put(client, id, full with
        {
            ShortReceipt = false
        });

        Assert.Equal(Payload(2), first.GetProperty("payload").GetString());
        Assert.Equal(first.GetProperty("cursor").GetInt64(), shortRetry.GetProperty("cursor").GetInt64());
        Assert.Equal(Digest(Payload(2)), shortRetry.GetProperty("payloadDigest").GetString());
        Assert.Equal(first.GetRawText(), fullRetry.GetRawText());
        var page = await client.GetFromJsonAsync<JsonElement>("/v1/sync/?after=0");
        Assert.Equal(1, page.GetProperty("changes").GetArrayLength());
    }

    // An operation applied before receipts referred to their change keeps its whole receipt as text. A retry gets
    // exactly that text, also when it asks for a short receipt; clients accept a full receipt either way.
    [Fact]
    public async Task ReceiptsKeptWholeByOlderServersStayWhole()
    {
        using var factory = new JournalFactory();
        var (client, _) = await SetUp(factory);
        var id = Guid.NewGuid();
        var request = new PutRecord(Guid.NewGuid(), 0, "entry", Payload(3));
        var receipt = await Put(client, id, request);
        // Distinguishable from a receipt rebuilt from the change log: another modifiedAt.
        var kept = receipt.GetRawText().Replace(receipt.GetProperty("modifiedAt").GetString()!, "2026-01-01T00:00:00+00:00", StringComparison.Ordinal);
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<JournalDb>();
            var applied = db.Operations.Single(operation => operation.Id == request.OperationId);
            applied.ChangeCursor = null;
            applied.ResponseJson = kept;
            Assert.Equal(1, await db.SaveChangesAsync());
        }

        foreach (var form in new bool?[] { null, false, true })
        {
            var response = await client.PutAsJsonAsync($"/v1/sync/{id}", request with
            {
                ShortReceipt = form
            });
            response.EnsureSuccessStatusCode();
            Assert.Equal(kept, await response.Content.ReadAsStringAsync());
        }
    }

    [Fact]
    public async Task ConflictsStillCarryTheServersWholeVersion()
    {
        using var factory = new JournalFactory();
        var (client, _) = await SetUp(factory);
        var id = Guid.NewGuid();
        await Put(client, id, new PutRecord(Guid.NewGuid(), 0, "entry", Payload(4)));
        var response = await client.PutAsJsonAsync($"/v1/sync/{id}", new PutRecord(Guid.NewGuid(), 0, "entry", Payload(5), ShortReceipt: true));

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        var problem = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(Payload(4), problem.GetProperty("current").GetProperty("payload").GetString());
    }

    [Fact]
    public async Task WaitAnswersAtOnceWhenAnOrdinarySyncWouldFindSomething()
    {
        using var factory = new JournalFactory();
        var (client, _) = await SetUp(factory);
        var id = Guid.NewGuid();
        var receipt = await Put(client, id, new PutRecord(Guid.NewGuid(), 0, "entry", Payload(6)));
        var cursor = receipt.GetProperty("cursor").GetInt64();
        var serverId = await ServerId(client);
        var applied = $"afterRecord={id}&afterRevision=1&afterDigest={Digest(Payload(6))}&serverId={serverId}";

        var cases = new[]
        {
            $"after={cursor - 1}&serverId={serverId}",
            $"after={cursor}&afterRecord={Guid.NewGuid()}&afterRevision=1&serverId={serverId}",
            $"after={cursor}&afterRecord={id}&afterRevision=2&serverId={serverId}",
            $"after={cursor}&afterRecord={id}&afterRevision=1&afterDigest={Digest(Payload(7))}&serverId={serverId}",
            $"after={cursor + 5}&afterRecord={id}&afterRevision=1&serverId={serverId}",
            $"after={cursor}&{applied.Replace(serverId, Guid.NewGuid().ToString(), StringComparison.Ordinal)}",
        };
        foreach (var query in cases)
        {
            var stopwatch = Stopwatch.StartNew();
            var (status, body) = await Wait(client, query + "&timeout=10");
            Assert.Equal(HttpStatusCode.OK, status);
            Assert.True(Changed(body), query);
            Assert.True(stopwatch.Elapsed < TimeSpan.FromSeconds(5), query);
        }

        // An identity differing only in letter case is the same, and a position past the end that names no change is
        // what an empty page would report: both are held and confirmed.
        foreach (var query in new[] { $"after={cursor}&{applied.Replace(serverId, serverId.ToUpperInvariant(), StringComparison.Ordinal)}", $"after={cursor + 5}&serverId={serverId}" })
        {
            var stopwatch = Stopwatch.StartNew();
            var (status, body) = await Wait(client, query + "&timeout=1");
            Assert.Equal(HttpStatusCode.OK, status);
            Assert.False(Changed(body), query);
            Assert.False(Early(body), query);
            Assert.True(stopwatch.Elapsed >= TimeSpan.FromSeconds(0.9), query);
        }
    }

    [Fact]
    public async Task HeldWaitWakesWhenAnotherDeviceWrites()
    {
        using var factory = new JournalFactory();
        var (mac, _) = await SetUp(factory);
        using var phone = await AddDevice(factory);
        var serverId = await ServerId(mac);

        var waiting = Wait(phone, $"after=0&serverId={serverId}&timeout=20");
        await Task.Delay(300);
        Assert.False(waiting.IsCompleted);
        var stopwatch = Stopwatch.StartNew();
        await Put(mac, Guid.NewGuid(), new PutRecord(Guid.NewGuid(), 0, "entry", Payload(8)));
        var (status, body) = await waiting;

        Assert.Equal(HttpStatusCode.OK, status);
        Assert.True(Changed(body));
        Assert.True(stopwatch.Elapsed < TimeSpan.FromSeconds(1));
    }

    [Fact]
    public void SignalTakenBeforeANotificationCompletesAndOneTakenAfterDoesNot()
    {
        var signal = new SyncSignal();
        var before = signal.Current;
        signal.Notify();
        var after = signal.Current;

        Assert.True(before.IsCompleted);
        Assert.False(after.IsCompleted);
    }

    [Fact]
    public async Task ConfirmingAnswerComesAtTheTimeoutAndChecksTheCredentialAgain()
    {
        using var factory = new JournalFactory();
        var (mac, _) = await SetUp(factory);
        var serverId = await ServerId(mac);
        var stopwatch = Stopwatch.StartNew();
        var (status, body) = await Wait(mac, $"after=0&serverId={serverId}&timeout=1");
        Assert.Equal(HttpStatusCode.OK, status);
        Assert.False(Changed(body));
        Assert.False(Early(body));
        Assert.True(stopwatch.Elapsed >= TimeSpan.FromSeconds(0.9));

        // Revoked outside any request, so nothing notifies: the check at the deadline refuses it.
        using var phone = await AddDevice(factory);
        var waiting = Wait(phone, $"after=0&serverId={serverId}&timeout=2");
        await Task.Delay(300);
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<JournalDb>();
            foreach (var device in db.Devices.Where(device => device.Name == "iPhone"))
            {
                device.Revoked = true;
            }
            await db.SaveChangesAsync();
        }
        Assert.Equal(HttpStatusCode.Unauthorized, (await waiting).Status);
    }

    [Fact]
    public async Task RevokedDevicesAreRefusedBeforeAndWhileWaiting()
    {
        using var factory = new JournalFactory();
        var (mac, _) = await SetUp(factory);
        var serverId = await ServerId(mac);
        using var phone = await AddDevice(factory);
        var devices = await mac.GetFromJsonAsync<JsonElement>("/v1/devices/");
        var phoneId = devices.EnumerateArray().Single(device => device.GetProperty("name").GetString() == "iPhone").GetProperty("id").GetGuid();

        var waiting = Wait(phone, $"after=0&serverId={serverId}&timeout=20");
        await Task.Delay(300);
        var stopwatch = Stopwatch.StartNew();
        (await mac.DeleteAsync($"/v1/devices/{phoneId}")).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Unauthorized, (await waiting).Status);
        Assert.True(stopwatch.Elapsed < TimeSpan.FromSeconds(1));
        Assert.Equal(HttpStatusCode.Unauthorized, (await Wait(phone, $"after=0&timeout=1")).Status);
    }

    [Fact]
    public async Task CancellingAnApprovedPairingRefusesTheNewDevicesWait()
    {
        using var factory = new JournalFactory();
        var (owner, _) = await SetUp(factory);
        using var phone = factory.CreateClient();
        var pair = await PairingFlow.Begin(phone);
        await PairingFlow.Challenge(owner, phone, pair);
        var token = new string('c', 64);
        (await owner.PostAsJsonAsync($"/v1/pairing/{pair.Id}/approve", PairingFlow.Approval(token))).EnsureSuccessStatusCode();
        using var paired = factory.CreateClient();
        paired.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        var waiting = Wait(paired, "after=0&timeout=20");
        await Task.Delay(300);
        var stopwatch = Stopwatch.StartNew();
        (await phone.PostAsJsonAsync($"/v1/pairing/{pair.Id}/cancel", new PollPairing(pair.PollToken))).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Unauthorized, (await waiting).Status);
        Assert.True(stopwatch.Elapsed < TimeSpan.FromSeconds(1));
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task TurningOnEncryptionWakesTheRequesterAndRefusesOthers(bool withContinuity)
    {
        using var factory = new JournalFactory();
        var (mac, _) = await SetUp(factory);
        using var phone = await AddDevice(factory);
        var id = Guid.NewGuid();
        var receipt = await Put(mac, id, new PutRecord(Guid.NewGuid(), 0, "entry", Payload(9)));
        var cursor = receipt.GetProperty("cursor").GetInt64();
        var serverId = await ServerId(mac);
        var position = $"after={cursor}&serverId={serverId}&timeout=20" + (withContinuity ? $"&afterRecord={id}&afterRevision=1" : "");

        var macWait = Wait(mac, position);
        var phoneWait = Wait(phone, position);
        await Task.Delay(300);
        var turnOn = new TurnOnEncryptionRequest(Convert.ToBase64String(new byte[16]), Convert.ToBase64String(new byte[60]), 600_000, new string('c', 64), 2, cursor, id, 1);
        (await mac.PostAsJsonAsync("/v1/recovery/encrypt", turnOn)).EnsureSuccessStatusCode();

        var (macStatus, macBody) = await macWait;
        Assert.Equal(HttpStatusCode.OK, macStatus);
        Assert.True(Changed(macBody));
        Assert.Equal(HttpStatusCode.Unauthorized, (await phoneWait).Status);
    }

    [Fact]
    public async Task ANewerWaitReplacesTheOlderAndTheRegistryEmpties()
    {
        using var factory = new JournalFactory();
        var (mac, _) = await SetUp(factory);
        var signal = factory.Services.GetRequiredService<SyncSignal>();
        var serverId = await ServerId(mac);
        var query = $"after=0&serverId={serverId}&timeout=20";

        var first = Wait(mac, query);
        await Task.Delay(300);
        var second = Wait(mac, query);
        var (status, body) = await first;
        Assert.Equal(HttpStatusCode.OK, status);
        Assert.False(Changed(body));
        Assert.True(Early(body));
        Assert.Equal(1, signal.WaiterCount);

        // A cancelled wait and one that timed out both leave the registry.
        using (var cancel = new CancellationTokenSource(TimeSpan.FromMilliseconds(300)))
        {
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() => Wait(mac, query, cancel.Token));
        }
        Assert.True(Early((await second).Body));
        await Wait(mac, $"after=0&serverId={serverId}&timeout=1");
        await WaitUntil(() => signal.WaiterCount == 0);
    }

    private static async Task WaitUntil(Func<bool> condition)
    {
        var stopwatch = Stopwatch.StartNew();
        while (!condition())
        {
            Assert.True(stopwatch.Elapsed < TimeSpan.FromSeconds(5));
            await Task.Delay(20);
        }
    }

    [Fact]
    public async Task WaitsBeyondTheServerWideCapacityAreAnsweredEarly()
    {
        using var factory = new JournalFactory();
        factory.Settings["Journal:SyncWaitCapacity"] = "1";
        var (mac, _) = await SetUp(factory);
        using var phone = await AddDevice(factory);
        var serverId = await ServerId(mac);
        var query = $"after=0&serverId={serverId}&timeout=20";
        var held = Wait(mac, query);
        await Task.Delay(300);

        var stopwatch = Stopwatch.StartNew();
        var (status, body) = await Wait(phone, query);
        Assert.Equal(HttpStatusCode.OK, status);
        Assert.True(Early(body));
        Assert.True(stopwatch.Elapsed < TimeSpan.FromSeconds(2));
        Assert.False(held.IsCompleted, "The wait already held is kept");

        // Replacing a device's own wait is never refused at capacity.
        var replacement = Wait(mac, query);
        Assert.True(Early((await held).Body));
        Assert.False(replacement.IsCompleted);
        Assert.Equal(1, factory.Services.GetRequiredService<SyncSignal>().WaiterCount);
    }

    [Fact]
    public async Task WaitsAreRateLimitedPerDeviceAndPerAddress()
    {
        using var factory = new JournalFactory();
        var (mac, _) = await SetUp(factory);
        var statuses = new List<HttpStatusCode>();
        for (var attempt = 0; attempt < 61; attempt++)
        {
            // Refused requests count too, so none of these needs to be held.
            statuses.Add((await mac.GetAsync("/v1/sync/wait?after=-1")).StatusCode);
        }
        Assert.Equal(HttpStatusCode.TooManyRequests, statuses[^1]);

        using var anonymous = factory.CreateClient();
        HttpStatusCode last = default;
        for (var attempt = 0; attempt < 61; attempt++)
        {
            last = (await anonymous.GetAsync("/v1/sync/wait?after=0")).StatusCode;
        }
        Assert.Equal(HttpStatusCode.TooManyRequests, last);
    }

    [Fact]
    public async Task StoppingAnswersEveryWaitEarlyWithoutHoldingShutdown()
    {
        using var factory = new JournalFactory();
        var (mac, _) = await SetUp(factory);
        using var phone = await AddDevice(factory);
        var serverId = await ServerId(mac);
        var query = $"after=0&serverId={serverId}&timeout=20";
        var waits = new[] { Wait(mac, query), Wait(phone, query) };
        await Task.Delay(300);

        var stopwatch = Stopwatch.StartNew();
        factory.Services.GetRequiredService<IHostApplicationLifetime>().StopApplication();
        foreach (var (status, body) in await Task.WhenAll(waits))
        {
            Assert.Equal(HttpStatusCode.OK, status);
            Assert.True(Early(body));
        }
        Assert.True(stopwatch.Elapsed < TimeSpan.FromSeconds(2));
    }

    [Theory]
    [InlineData("")]
    [InlineData("after=-1")]
    [InlineData("after=1&afterRecord=3f2504e0-4f89-41d3-9a0c-0305e82c3301")]
    [InlineData("after=1&afterDigest=0000000000000000000000000000000000000000000000000000000000000000")]
    [InlineData("after=1&afterRecord=3f2504e0-4f89-41d3-9a0c-0305e82c3301&afterRevision=1&afterDigest=XYZ")]
    public async Task InvalidPositionsAreRefused(string query)
    {
        ArgumentNullException.ThrowIfNull(query);
        using var factory = new JournalFactory();
        var (mac, _) = await SetUp(factory);
        var (status, body) = await Wait(mac, query + "&serverId=" + (query.Length == 0 ? new string('x', 65) : "x"));
        Assert.Equal(HttpStatusCode.BadRequest, status);
        Assert.Equal("invalid_cursor", body.GetProperty("code").GetString());
    }
}

// Measures memory, so it runs alone: other tests allocating in parallel would make the numbers meaningless.
[CollectionDefinition(nameof(SignalMemoryTests), DisableParallelization = true)]
public sealed class SignalMemoryGroup
{
}

[Collection(nameof(SignalMemoryTests))]
public sealed class SignalMemoryTests
{
    // A wait that ends without a write, by timeout, disconnect or replacement, leaves nothing attached to the shared
    // signal; otherwise an idle server would collect a continuation for every wait cycle. Whatever stayed attached
    // keeps that wait's replacement task reachable, so those are counted after a full collection.
    [Fact]
    public async Task FinishedWaitsLeaveNothingAttachedToTheSignal()
    {
        var notified = new SyncSignal().Current;
        var waits = new List<WeakReference>();
        for (var index = 0; index < 1_000; index++)
        {
            waits.Add(await OneWait(notified, replace: index % 2 == 0));
        }
        GC.Collect();
        GC.WaitForPendingFinalizers();
        GC.Collect();
        Assert.False(notified.IsCompleted);
        Assert.True(waits.Count(wait => wait.IsAlive) < 10, $"{waits.Count(wait => wait.IsAlive)} of 1,000 finished waits are still attached");
    }

    private static async Task<WeakReference> OneWait(Task notified, bool replace)
    {
        var replaced = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var stop = new CancellationTokenSource();
        var waiting = SyncSignal.WaitForSignal(notified, replaced.Task, stop.Token);
        if (replace)
        {
            replaced.SetResult();
        }
        else
        {
            await stop.CancelAsync();
        }
        await waiting;
        return new WeakReference(replaced.Task);
    }
}
