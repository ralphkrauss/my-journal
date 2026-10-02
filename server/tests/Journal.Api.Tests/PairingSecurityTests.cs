using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Journal.Api.Features;

namespace Journal.Api.Tests;

// The check-code pairing steps up to the point where the approving device may approve.
internal static class PairingFlow
{
    public static readonly byte[] NewDeviceKey = Enumerable.Repeat((byte)7, 32).ToArray();
    public static readonly byte[] ApproverKey = Enumerable.Repeat((byte)9, 32).ToArray();

    public static async Task<(Guid Id, string Code, string PollToken)> Begin(HttpClient client)
    {
        var response = await client.PostAsJsonAsync("/v1/pairing", new BeginPairing("Phone", PairingEndpoints.Commitment(NewDeviceKey)));
        response.EnsureSuccessStatusCode();
        var pair = await response.Content.ReadFromJsonAsync<JsonElement>();
        return (pair.GetProperty("id").GetGuid(), pair.GetProperty("code").GetString() ?? "", pair.GetProperty("pollToken").GetString() ?? "");
    }

    public static async Task Challenge(HttpClient owner, HttpClient phone, (Guid Id, string Code, string PollToken) pair)
    {
        (await owner.PostAsJsonAsync("/v1/pairing/lookup", new LookupPairing(pair.Code))).EnsureSuccessStatusCode();
        (await owner.PostAsJsonAsync($"/v1/pairing/{pair.Id}/challenge", new ChallengePairing(Convert.ToBase64String(ApproverKey)))).EnsureSuccessStatusCode();
        (await phone.PostAsJsonAsync($"/v1/pairing/{pair.Id}/reveal", new RevealPairing(pair.PollToken, Convert.ToBase64String(NewDeviceKey)))).EnsureSuccessStatusCode();
    }

    public static string Grant(byte[] prefix) => Convert.ToBase64String([.. prefix, .. new byte[60]]);

    public static ApprovePairing Approval(string token) => new(token, Grant(ApproverKey));
}

public sealed class PairingSecurityTests
{
    // Shared with protocol/README.md and the Swift client.
    [Fact]
    public void CommitmentMatchesTheProtocolVector() =>
        Assert.Equal("2kHrWMfI9jssNr6LMzi1CnMfO8j59ftEu0NEGULOHFY=", PairingEndpoints.Commitment(PairingFlow.NewDeviceKey));

    [Fact]
    public async Task NewDeviceKeyIsRevealedOnlyAfterTheApproverKeyIsFixedAndGrantMustUseThatKey()
    {
        using var factory = new JournalFactory();
        var (owner, _) = await factory.SetUp();
        using var phone = factory.CreateClient();
        var (id, code, pollToken) = await PairingFlow.Begin(phone);
        var reveal = new RevealPairing(pollToken, Convert.ToBase64String(PairingFlow.NewDeviceKey));
        Assert.Equal(HttpStatusCode.Conflict, (await phone.PostAsJsonAsync($"/v1/pairing/{id}/reveal", reveal)).StatusCode);

        var candidate = await (await owner.PostAsJsonAsync("/v1/pairing/lookup", new LookupPairing(code))).Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(JsonValueKind.Null, candidate.GetProperty("publicKey").ValueKind);
        var challenge = new ChallengePairing(Convert.ToBase64String(PairingFlow.ApproverKey));
        (await owner.PostAsJsonAsync($"/v1/pairing/{id}/challenge", challenge)).EnsureSuccessStatusCode();
        // The approver key cannot be replaced once the new device may have seen it.
        Assert.Equal(HttpStatusCode.Conflict, (await owner.PostAsJsonAsync($"/v1/pairing/{id}/challenge", new ChallengePairing(Convert.ToBase64String(new byte[32])))).StatusCode);
        var poll = await (await phone.PostAsJsonAsync($"/v1/pairing/{id}/poll", new PollPairing(pollToken))).Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(challenge.ApproverKey, poll.GetProperty("approverKey").GetString());

        var wrongKey = new RevealPairing(pollToken, Convert.ToBase64String(new byte[32]));
        Assert.Equal(HttpStatusCode.BadRequest, (await phone.PostAsJsonAsync($"/v1/pairing/{id}/reveal", wrongKey)).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await owner.PostAsJsonAsync($"/v1/pairing/{id}/approve", PairingFlow.Approval(new string('c', 64)))).StatusCode);
        (await phone.PostAsJsonAsync($"/v1/pairing/{id}/reveal", reveal)).EnsureSuccessStatusCode();
        var revealed = await owner.GetFromJsonAsync<JsonElement>($"/v1/pairing/{id}");
        Assert.Equal(reveal.PublicKey, revealed.GetProperty("publicKey").GetString());

        Assert.Equal(HttpStatusCode.Conflict, (await owner.PostAsJsonAsync($"/v1/pairing/{id}/approve", new ApprovePairing(new string('c', 64), PairingFlow.Grant(new byte[32])))).StatusCode);
        (await owner.PostAsJsonAsync($"/v1/pairing/{id}/approve", PairingFlow.Approval(new string('c', 64)))).EnsureSuccessStatusCode();
    }

    [Fact]
    public async Task DeclinedRequestTellsTheNewDeviceAndCannotBeApproved()
    {
        using var factory = new JournalFactory();
        var (owner, _) = await factory.SetUp();
        using var phone = factory.CreateClient();
        var (id, code, pollToken) = await PairingFlow.Begin(phone);
        (await owner.PostAsJsonAsync($"/v1/pairing/{id}/decline", new
        {
        })).EnsureSuccessStatusCode();
        var poll = await (await phone.PostAsJsonAsync($"/v1/pairing/{id}/poll", new PollPairing(pollToken))).Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(poll.GetProperty("declined").GetBoolean());
        Assert.Equal(HttpStatusCode.NotFound, (await owner.PostAsJsonAsync("/v1/pairing/lookup", new LookupPairing(code))).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await owner.PostAsJsonAsync($"/v1/pairing/{id}/approve", PairingFlow.Approval(new string('c', 64)))).StatusCode);
    }

    [Fact]
    public async Task AnonymousFloodingCannotBlockTheOwnersDevicesOrAnotherClientsPairing()
    {
        using var factory = new JournalFactory();
        var (owner, _) = await factory.SetUp();
        using var stranger = factory.CreateClient();
        stranger.DefaultRequestHeaders.Add(JournalFactory.ClientAddressHeader, "192.0.2.1");
        using var phone = factory.CreateClient();
        phone.DefaultRequestHeaders.Add(JournalFactory.ClientAddressHeader, "192.0.2.2");
        var (id, code, pollToken) = await PairingFlow.Begin(phone);
        HttpResponseMessage? limited = null;
        for (var attempt = 0; attempt < 20 && limited is null; attempt++)
        {
            var response = await stranger.PostAsJsonAsync("/v1/pairing", new BeginPairing("Stranger", PairingEndpoints.Commitment(new byte[32])));
            if (response.StatusCode == HttpStatusCode.TooManyRequests)
            {
                limited = response;
            }
        }
        Assert.NotNull(limited);
        Assert.True(limited.Headers.RetryAfter?.Delta > TimeSpan.Zero);
        Assert.Equal("rate_limited", (await limited.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("code").GetString());
        // Random request IDs do not give a caller fresh limits.
        var polls = new List<HttpStatusCode>();
        for (var attempt = 0; attempt < 260; attempt++)
        {
            polls.Add((await stranger.PostAsJsonAsync($"/v1/pairing/{Guid.NewGuid()}/poll", new PollPairing("guess"))).StatusCode);
        }
        Assert.Contains(HttpStatusCode.TooManyRequests, polls);
        // The owner's devices and other clients keep their own limits.
        (await owner.PostAsJsonAsync("/v1/pairing/lookup", new LookupPairing(code))).EnsureSuccessStatusCode();
        (await owner.GetAsync("/v1/devices/")).EnsureSuccessStatusCode();
        (await phone.PostAsJsonAsync($"/v1/pairing/{id}/poll", new PollPairing(pollToken))).EnsureSuccessStatusCode();
    }

    [Fact]
    public async Task ApprovalTooCloseToExpiryIsRefusedWithoutCreatingADevice()
    {
        var clock = new ManualClock(DateTimeOffset.UtcNow);
        using var factory = new JournalFactory { Clock = clock };
        var (owner, _) = await factory.SetUp();
        using var phone = factory.CreateClient();
        var pair = await PairingFlow.Begin(phone);
        await PairingFlow.Challenge(owner, phone, pair);
        clock.Now += PairingEndpoints.Lifetime - PairingEndpoints.ApprovalMargin + TimeSpan.FromSeconds(1);

        var late = await owner.PostAsJsonAsync($"/v1/pairing/{pair.Id}/approve", PairingFlow.Approval(new string('e', 64)));
        Assert.Equal(HttpStatusCode.NotFound, late.StatusCode);
        Assert.Equal("pairing_expired", (await late.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("code").GetString());
        Assert.Single(await owner.GetFromJsonAsync<JsonElement[]>("/v1/devices/") ?? []);
    }

    [Fact]
    public async Task ApprovedGrantStaysReadableAfterExpiryAndAnUncollectedGrantIsRevoked()
    {
        var clock = new ManualClock(DateTimeOffset.UtcNow);
        using var factory = new JournalFactory { Clock = clock };
        var (owner, _) = await factory.SetUp();
        using var phone = factory.CreateClient();
        using var laptop = factory.CreateClient();
        var collected = await PairingFlow.Begin(phone);
        await PairingFlow.Challenge(owner, phone, collected);
        var uncollected = await PairingFlow.Begin(laptop);
        await PairingFlow.Challenge(owner, laptop, uncollected);
        clock.Now += PairingEndpoints.Lifetime - PairingEndpoints.ApprovalMargin - TimeSpan.FromSeconds(1);
        (await owner.PostAsJsonAsync($"/v1/pairing/{collected.Id}/approve", PairingFlow.Approval(new string('f', 64)))).EnsureSuccessStatusCode();
        (await owner.PostAsJsonAsync($"/v1/pairing/{uncollected.Id}/approve", PairingFlow.Approval(new string('9', 64)))).EnsureSuccessStatusCode();

        // A new device whose clock runs behind polls just after the server's expiry.
        clock.Now += PairingEndpoints.ApprovalMargin + TimeSpan.FromSeconds(5);
        var poll = await phone.PostAsJsonAsync($"/v1/pairing/{collected.Id}/poll", new PollPairing(collected.PollToken));
        poll.EnsureSuccessStatusCode();
        Assert.True((await poll.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("approved").GetBoolean());

        // Once the grace period ends, the next pairing request removes both expired requests.
        clock.Now += PairingEndpoints.GrantGrace;
        using var tablet = factory.CreateClient();
        await PairingFlow.Begin(tablet);
        Assert.Equal(HttpStatusCode.NotFound, (await phone.PostAsJsonAsync($"/v1/pairing/{collected.Id}/poll", new PollPairing(collected.PollToken))).StatusCode);
        phone.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", new string('f', 64));
        (await phone.GetAsync("/v1/sync/")).EnsureSuccessStatusCode();
        laptop.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", new string('9', 64));
        Assert.Equal(HttpStatusCode.Unauthorized, (await laptop.GetAsync("/v1/sync/")).StatusCode);
    }
}
