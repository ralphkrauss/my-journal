using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Journal.Api.Data;
using Journal.Api.Features;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace Journal.Api.Tests;

// Invite pairing (capability pairing-invite): the new device read a code shown by the connected device, which
// looks the request up with its own invite handle and checks the proof itself.
public sealed class InvitePairingTests
{
    private const string Invite = "0123456789abcdef0123456789abcdef";
    // 32 bytes, as HMAC-SHA256 produces.
    private const string Proof = "BQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQU=";

    private static Task<HttpResponseMessage> Begin(HttpClient client, string? invite, string? proof) =>
        client.PostAsJsonAsync("/v1/pairing", new BeginPairing("Phone", PairingEndpoints.Commitment(PairingFlow.NewDeviceKey), invite, proof));

    private static async Task<(Guid Id, string Code, string PollToken)> BeginInvite(HttpClient client)
    {
        var response = await Begin(client, Invite, Proof);
        response.EnsureSuccessStatusCode();
        var pair = await response.Content.ReadFromJsonAsync<JsonElement>();
        return (pair.GetProperty("id").GetGuid(), pair.GetProperty("code").GetString() ?? "", pair.GetProperty("pollToken").GetString() ?? "");
    }

    private static async Task<string> ErrorCode(HttpResponseMessage response) =>
        (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("code").GetString() ?? "";

    [Fact]
    public async Task ApproverFindsTheRequestWithItsInviteAndEachInviteIsUsedOnce()
    {
        using var factory = new JournalFactory();
        var (owner, _) = await factory.SetUp();
        using var phone = factory.CreateClient();
        var pair = await BeginInvite(phone);
        Assert.Equal(Invite, pair.Code);

        var candidate = await (await owner.PostAsJsonAsync("/v1/pairing/lookup", new LookupPairing(Invite))).Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal((pair.Id, "Phone", Proof), (candidate.GetProperty("id").GetGuid(), candidate.GetProperty("deviceName").GetString(), candidate.GetProperty("inviteProof").GetString()));
        Assert.Equal(Proof, (await owner.GetFromJsonAsync<JsonElement>($"/v1/pairing/{pair.Id}")).GetProperty("inviteProof").GetString());

        // Someone who saw the code can't add a second request for the approver to find.
        using var stranger = factory.CreateClient();
        var second = await Begin(stranger, Invite, Proof);
        Assert.Equal(HttpStatusCode.Conflict, second.StatusCode);
        Assert.Equal("invite_used", await ErrorCode(second));

        // An approver that declines a request with a bad proof ends the code: it can't be used again either.
        (await owner.PostAsJsonAsync($"/v1/pairing/{pair.Id}/decline", new
        {
        })).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Conflict, (await Begin(stranger, Invite, Proof)).StatusCode);

        // Requests with a typed code carry no proof.
        var typed = await PairingFlow.Begin(phone);
        var typedCandidate = await (await owner.PostAsJsonAsync("/v1/pairing/lookup", new LookupPairing(typed.Code))).Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(JsonValueKind.Null, typedCandidate.GetProperty("inviteProof").ValueKind);
    }

    [Theory]
    [InlineData(Invite, null)]
    [InlineData(null, Proof)]
    [InlineData("0123456789ABCDEF0123456789ABCDEF", Proof)]
    [InlineData("0123456789abcdef0123456789abcde", Proof)]
    // A 31-byte proof.
    [InlineData(Invite, "BQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQ==")]
    public async Task IncompleteOrMalformedInviteIsRefusedWithoutCreatingARequest(string? invite, string? proof)
    {
        using var factory = new JournalFactory();
        await factory.SetUp();
        using var phone = factory.CreateClient();
        var response = await Begin(phone, invite, proof);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("invalid_pairing_request", await ErrorCode(response));
        using var scope = factory.Services.CreateScope();
        Assert.Equal(0, await scope.ServiceProvider.GetRequiredService<JournalDb>().PairRequests.CountAsync());
    }

    [Fact]
    public async Task InviteRequestIsChallengedRevealedAndApprovedLikeATypedCode()
    {
        using var factory = new JournalFactory();
        var (owner, _) = await factory.SetUp();
        using var phone = factory.CreateClient();
        var pair = await BeginInvite(phone);
        await PairingFlow.Challenge(owner, phone, pair);
        var token = new string('d', 64);
        (await owner.PostAsJsonAsync($"/v1/pairing/{pair.Id}/approve", PairingFlow.Approval(token))).EnsureSuccessStatusCode();

        var poll = await (await phone.PostAsJsonAsync($"/v1/pairing/{pair.Id}/poll", new PollPairing(pair.PollToken))).Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(poll.GetProperty("approved").GetBoolean());
        Assert.Equal(PairingFlow.Grant(PairingFlow.ApproverKey), poll.GetProperty("encryptedGrant").GetString());
        phone.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        (await phone.GetAsync("/v1/sync/")).EnsureSuccessStatusCode();
    }
}
