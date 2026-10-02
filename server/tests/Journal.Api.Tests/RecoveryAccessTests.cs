using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Journal.Api.Data;
using Journal.Api.Features;
using Journal.Api.Security;
using Microsoft.Extensions.DependencyInjection;

namespace Journal.Api.Tests;

// The password-wrapped vault key is what offline guessing needs, so only a verified recovery secret or a
// connected device can read it, and wrong secrets from anywhere together slow recovery down.
public sealed class RecoveryAccessTests
{
    private static readonly RecoveryEnvelope SetUpEnvelope = new(Convert.ToBase64String(new byte[16]), Convert.ToBase64String(new byte[60]), 600_000, 2);

    [Fact]
    public async Task TheWrappedKeyIsReadableOnlyWithTheRightSecretOrADeviceCredential()
    {
        using var factory = new JournalFactory();
        var (owner, _) = await factory.SetUp(2);
        using var anonymous = factory.CreateClient();
        var published = await anonymous.GetFromJsonAsync<JsonElement>("/v1/recovery");
        Assert.False(published.TryGetProperty("wrappedKey", out _));
        Assert.Equal((SetUpEnvelope.Salt, 600_000, 2), (published.GetProperty("salt").GetString(), published.GetProperty("iterations").GetInt32(), published.GetProperty("formatVersion").GetInt32()));
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync("/v1/recovery/envelope")).StatusCode);

        var wrong = await anonymous.PostAsJsonAsync("/v1/recovery", new RecoveryRequest(new string('b', 64), "Phone"));
        Assert.Equal(HttpStatusCode.Unauthorized, wrong.StatusCode);
        Assert.DoesNotContain(SetUpEnvelope.WrappedKey, await wrong.Content.ReadAsStringAsync(), StringComparison.Ordinal);
        var recovered = await anonymous.PostAsJsonAsync("/v1/recovery", new RecoveryRequest(new string('a', 64), "Phone"));
        recovered.EnsureSuccessStatusCode();
        Assert.Equal(SetUpEnvelope, (await recovered.Content.ReadFromJsonAsync<RecoveryGrant>())?.Envelope);
        Assert.Equal(SetUpEnvelope, await owner.GetFromJsonAsync<RecoveryEnvelope>("/v1/recovery/envelope"));
        foreach (var path in new[] { "/v1/status", "/v1/server" })
        {
            var features = (await anonymous.GetFromJsonAsync<JsonElement>(path)).GetProperty("features").EnumerateArray().Select(feature => feature.GetString()).ToList();
            // Clients offer invite pairing (Scan Code) only when the server lists it.
            Assert.Contains("private-envelope", features);
            Assert.Contains("pairing-invite", features);
        }
    }

    [Fact]
    public async Task WrongSecretsFromManyAddressesPauseRecoveryButNotConnectedDevices()
    {
        var clock = new ManualClock(DateTimeOffset.UtcNow);
        using var factory = new JournalFactory { Clock = clock };
        var (owner, _) = await factory.SetUp(2);
        using var anonymous = factory.CreateClient();
        async Task<HttpResponseMessage> Recover(string secret, int address)
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/recovery") { Content = JsonContent.Create(new RecoveryRequest(secret, "Phone")) };
            request.Headers.Add(JournalFactory.ClientAddressHeader, $"198.51.100.{address}");
            return await anonymous.SendAsync(request);
        }
        // Each address stays far below its own limit.
        for (var address = 0; address < RecoveryAttempts.Budget; address++)
        {
            Assert.Equal(HttpStatusCode.Unauthorized, (await Recover(new string('b', 64), address)).StatusCode);
        }
        var paused = await Recover(new string('a', 64), 200);
        Assert.Equal(HttpStatusCode.TooManyRequests, paused.StatusCode);
        Assert.Equal(RecoveryAttempts.FirstWait, paused.Headers.RetryAfter?.Delta);
        Assert.Equal("rate_limited", (await paused.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("code").GetString());

        // Connected devices keep working: the envelope, the device list, pairing and a password change.
        (await owner.GetAsync("/v1/recovery/envelope")).EnsureSuccessStatusCode();
        (await owner.GetAsync("/v1/devices/")).EnsureSuccessStatusCode();
        (await anonymous.GetAsync("/v1/recovery")).EnsureSuccessStatusCode();
        using var phone = factory.CreateClient();
        var pair = await PairingFlow.Begin(phone);
        await PairingFlow.Challenge(owner, phone, pair);
        (await owner.PostAsJsonAsync($"/v1/pairing/{pair.Id}/approve", PairingFlow.Approval(new string('c', 64)))).EnsureSuccessStatusCode();
        var change = new ChangePasswordRequest(new string('a', 64), SetUpEnvelope.Salt, SetUpEnvelope.WrappedKey, 600_000, new string('d', 64), 2);
        Assert.Equal(HttpStatusCode.NoContent, (await owner.PostAsJsonAsync("/v1/recovery/password", change)).StatusCode);

        // Each further wrong secret doubles the wait; the right one works once it has passed.
        clock.Now += RecoveryAttempts.FirstWait;
        Assert.Equal(HttpStatusCode.Unauthorized, (await Recover(new string('b', 64), 201)).StatusCode);
        var longer = await Recover(new string('d', 64), 202);
        Assert.Equal(HttpStatusCode.TooManyRequests, longer.StatusCode);
        Assert.Equal(2 * RecoveryAttempts.FirstWait, longer.Headers.RetryAfter?.Delta);
        clock.Now += 2 * RecoveryAttempts.FirstWait;
        (await Recover(new string('d', 64), 203)).EnsureSuccessStatusCode();
    }

    [Fact]
    public async Task DevicesShowHowEachWasAddedAndWhichDeviceApprovedAPairing()
    {
        using var factory = new JournalFactory();
        var (owner, setUp) = await factory.SetUp(2);
        using var anonymous = factory.CreateClient();
        var recovered = await (await anonymous.PostAsJsonAsync("/v1/recovery", new RecoveryRequest(new string('a', 64), "Laptop"))).Content.ReadFromJsonAsync<RecoveryGrant>();
        using var phone = factory.CreateClient();
        var pair = await PairingFlow.Begin(phone);
        await PairingFlow.Challenge(owner, phone, pair);
        var approval = await owner.PostAsJsonAsync($"/v1/pairing/{pair.Id}/approve", PairingFlow.Approval(new string('c', 64)));
        var paired = (await approval.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
        var legacy = Guid.NewGuid();
        await using (var scope = factory.Services.CreateAsyncScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<JournalDb>();
            db.Devices.Add(new Device { Id = legacy, Name = "Old iPad", TokenHash = Secrets.Hash(new string('e', 64)), CreatedAt = DateTimeOffset.UtcNow });
            await db.SaveChangesAsync();
        }

        var devices = (await owner.GetFromJsonAsync<JsonElement[]>("/v1/devices/") ?? []).ToDictionary(device => device.GetProperty("id").GetGuid());
        string? Origin(Guid id) => devices[id].TryGetProperty("createdVia", out var value) ? value.GetString() : null;
        Guid? Approver(Guid id) => devices[id].GetProperty("approvedByDeviceId") is { ValueKind: JsonValueKind.String } value ? value.GetGuid() : null;
        Assert.Equal(("setup", (Guid?)null), (Origin(setUp.DeviceId), Approver(setUp.DeviceId)));
        Assert.Equal(("recovery", (Guid?)null), (Origin(recovered?.DeviceId ?? Guid.Empty), Approver(recovered?.DeviceId ?? Guid.Empty)));
        Assert.Equal(("pairing", (Guid?)setUp.DeviceId), (Origin(paired), Approver(paired)));
        // Devices added before this was recorded have no origin rather than a guessed one.
        Assert.False(devices[legacy].TryGetProperty("createdVia", out _));
        Assert.Equal(JsonValueKind.Null, devices[legacy].GetProperty("approvedByDeviceId").ValueKind);
    }
}
