using System.Globalization;
using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Journal.Api.Features;
using Journal.Api.Security;
using Microsoft.AspNetCore.WebUtilities;

namespace Journal.Api.Tests;

// Agent access against misuse (protocol/agent-access-server.md): failed code exchanges, look-alike hosts, flooding the
// waiting requests, reconnecting someone else's agent, unknown page handles, large entries and hostile client names.
public sealed class AgentHardeningTests
{
    [Fact]
    public async Task ACodeRedeemedByAFailedExchangeLeavesNoConnectingAgentBehind()
    {
        var clock = new ManualClock(DateTimeOffset.UtcNow);
        using var factory = new JournalFactory { Clock = clock };
        var (device, _) = await factory.SetUp();
        using var ownedDevice = device;
        var flow = new AgentFlow(factory, device);
        await flow.Register();
        var (number, handle) = await flow.OpenAuthorizationPage();
        await flow.Approve(number);
        var code = QueryHelpers.ParseQuery((await flow.Callback(handle)).Query)["code"].ToString();
        // The wrong verifier uses the code up; the right one can't follow.
        Assert.Equal(HttpStatusCode.BadRequest, (await flow.Exchange(code, AgentFlow.Verifier + "x")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await flow.Exchange(code, AgentFlow.Verifier)).StatusCode);
        Assert.Equal("pending", (await device.GetFromJsonAsync<JsonElement>("/v1/agents/"))[0].GetProperty("state").GetString());
        // Once the request is over, the agent that never connected goes.
        clock.Now += TimeSpan.FromMinutes(20);
        Assert.Empty((await device.GetFromJsonAsync<JsonElement>("/v1/agents/")).EnumerateArray());
    }

    [Fact]
    public async Task InternationalizedHostsAreShownInTheirAsciiForm()
    {
        using var factory = new JournalFactory();
        var (device, _) = await factory.SetUp();
        using var ownedDevice = device;
        var flow = new AgentFlow(factory, device);
        const string lookAlike = "https://аpple.com/callback";
        await flow.Register(lookAlike);
        using var browser = factory.CreateClient();
        await browser.GetStringAsync("/oauth/authorize?response_type=code&client_id=" + flow.ClientId + "&redirect_uri=" + Uri.EscapeDataString(lookAlike) +
            "&code_challenge=" + AgentFlow.Challenge + "&code_challenge_method=S256&state=s");
        var ascii = new IdnMapping().GetAscii("аpple.com");
        Assert.StartsWith("xn--", ascii, StringComparison.Ordinal);
        Assert.Equal(ascii, (await flow.WaitingRequests()).Single().RedirectHost);
        var document = new OAuthClientInfo("https://аpple.com/client.json", "Apple", [lookAlike], FromMetadataDocument: true);
        Assert.Equal(ascii, document.IdentifiedAs);
        Assert.Equal("claude.ai", new OAuthClientInfo("https://claude.ai/oauth/client", "Claude", [], FromMetadataDocument: true).IdentifiedAs);
    }

    [Fact]
    public void FloodingEvictsTheBusiestSourceFirstNeverAnOpenedRequestAndNumbersAreNotReusedSoon()
    {
        var clock = new ManualClock(DateTimeOffset.UtcNow);
        var numbers = new Queue<int>(Enumerable.Range(10, 90));
        var scripted = new Queue<int>();
        var authorizations = new AgentAuthorizations(clock, () => scripted.Count > 0 ? scripted.Dequeue() : numbers.Dequeue());
        PendingAuthorization Start(string address, string clientId = "client")
        {
            var (result, request) = authorizations.Start(Details(clientId), address);
            Assert.Equal(AgentAuthorizations.StartResult.Started, result);
            return request!;
        }
        // At most 3 waiting requests per address.
        var quiet = new[] { Start("address:quiet", "q1"), Start("address:quiet", "q2") };
        var flood = Enumerable.Range(0, 3).Select(i => Start("address:flood", "f" + i)).ToList();
        Assert.Equal(AgentAuthorizations.StartResult.Busy, authorizations.Start(Details("f4"), "address:flood").Result);
        // Fill up to 20 with requests the owner opened.
        var opened = Enumerable.Range(0, 15).Select(i => Start("address:owner" + (i / 3), "o" + i)).ToList();
        foreach (var request in opened)
        {
            Assert.NotNull(authorizations.Open(request.Id));
        }
        // A new request evicts the flooding address's oldest one, not the quiet address's older ones or opened ones.
        var evicted = flood[0];
        scripted.Enqueue(evicted.Number);
        var next = Start("address:new", "n1");
        Assert.Null(authorizations.ById(evicted.Id));
        Assert.All(quiet.Concat(opened), x => Assert.NotNull(authorizations.ById(x.Id)));
        // The evicted request's number isn't handed out again while its page may still show it.
        Assert.NotEqual(evicted.Number, next.Number);
        // Neither is a replaced request's number.
        var replaced = quiet[1];
        scripted.Enqueue(replaced.Number);
        var retry = Start("address:quiet", "q2");
        Assert.Equal(PendingStatus.Replaced, authorizations.ById(replaced.Id)!.Status);
        Assert.NotEqual(replaced.Number, retry.Number);
        // After the evicted request's own expiry, its number is free again.
        clock.Now += AgentAuthorizations.Lifetime + TimeSpan.FromSeconds(1);
        scripted.Enqueue(evicted.Number);
        Assert.Equal(evicted.Number, Start("address:later", "l1").Number);
    }

    [Fact]
    public async Task OnlyASignedOutAgentOfTheSameClientCanBeReconnected()
    {
        using var factory = new JournalFactory();
        var (device, _) = await factory.SetUp();
        using var ownedDevice = device;
        var flow = new AgentFlow(factory, device);
        await flow.Connect();
        // The same client can't take over the agent while it's connected.
        var (number, _) = await flow.OpenAuthorizationPage();
        var request = (await flow.WaitingRequests()).Single();
        var connected = await Reconnect(device, request.Id, number, flow);
        Assert.Equal(HttpStatusCode.Conflict, connected.StatusCode);
        Assert.Equal("agent_not_reconnectable", (await connected.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("code").GetString());

        // Signed out, it still can't be taken over by another client.
        using (var client = factory.CreateClient())
        {
            (await client.PostAsync("/oauth/revoke", new FormUrlEncodedContent(new Dictionary<string, string> { ["token"] = flow.RefreshToken, ["client_id"] = flow.ClientId }))).EnsureSuccessStatusCode();
        }
        var other = new AgentFlow(factory, device);
        await other.Register();
        var (otherNumber, _) = await other.OpenAuthorizationPage(address: "10.0.0.9");
        var otherRequest = (await other.WaitingRequests()).Single(x => x.ClientId == other.ClientId);
        Assert.Null(otherRequest.ReconnectCandidate);
        var foreign = await Reconnect(device, otherRequest.Id, otherNumber, flow);
        Assert.Equal(HttpStatusCode.Conflict, foreign.StatusCode);
        Assert.Equal("agent_not_reconnectable", (await foreign.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("code").GetString());
    }

    [Fact]
    public async Task MadeUpPageHandlesShareTheCallersLimit()
    {
        using var factory = new JournalFactory();
        using var browser = factory.CreateClient();
        HttpStatusCode last = HttpStatusCode.OK;
        for (var i = 0; i < 61; i++)
        {
            last = (await browser.GetAsync("/oauth/authorize/status?handle=" + Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(32)))).StatusCode;
        }
        Assert.Equal(HttpStatusCode.TooManyRequests, last);
    }

    [Fact]
    public async Task LongEntriesAreExcerptedBySearchAndReadInFull()
    {
        using var factory = new JournalFactory();
        var (device, _) = await factory.SetUp();
        using var ownedDevice = device;
        var flow = new AgentFlow(factory, device);
        await flow.Connect();
        var id = Guid.NewGuid();
        var text = "Long day. " + new string('x', 40_000);
        await flow.Upload(new
        {
            kind = "entry",
            id,
            journalId = flow.SharedJournal,
            title = "Long",
            date = "2026-09-22T12:00:00Z",
            text
        }, id, 6);
        var found = (await flow.CallTool("search_entries", new JsonObject { ["query"] = "Long day" }))["structuredContent"]!["entries"]!.AsArray().Single()!;
        Assert.True((bool)found["truncated"]!);
        Assert.Equal(1000, ((string)found["text"]!).Length);
        var read = (await flow.CallTool("read_entry", new JsonObject { ["entry_id"] = id.ToString("D"), ["offset"] = 39_000, ["max_characters"] = 50_000 }))["structuredContent"]!["entry"]!;
        Assert.Equal(text.Length - 39_000, ((string)read["text"]!).Length);
        Assert.False((bool)read["truncated"]!);
    }

    // A broad search of a large copy must not hold every match to return one page.
    [Fact]
    public void SearchKeepsOnlyTheMatchesItsPageCanReach()
    {
        var random = new Random(7);
        var start = new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);
        // Few distinct dates, so many matches tie and are ordered by ID.
        var matches = Enumerable.Range(0, 5_000).Select(_ => (Id: Guid.NewGuid(), Date: start.AddDays(random.Next(40)))).ToList();
        var ranking = new SearchRanking(offset: 30, limit: 10);
        foreach (var (id, date) in matches)
        {
            ranking.Add(id, date);
            Assert.True(ranking.Retained <= 40);
        }
        var expected = matches.OrderByDescending(x => x.Date).ThenBy(x => x.Id.ToString("D").ToUpperInvariant(), StringComparer.Ordinal)
            .Skip(30).Take(10).Select(x => x.Id);
        Assert.Equal(expected, ranking.Page());
        Assert.True(ranking.MoreFollow);

        var last = new SearchRanking(offset: 3, limit: 2);
        foreach (var (id, date) in matches.Take(5))
        {
            last.Add(id, date);
        }
        Assert.Equal(2, last.Page().Count);
        Assert.False(last.MoreFollow);
    }

    [Fact]
    public async Task SearchPagesNewestFirstIncludingEntriesStoredBeforeTheirJournal()
    {
        using var factory = new JournalFactory();
        var (device, _) = await factory.SetUp();
        using var ownedDevice = device;
        var flow = new AgentFlow(factory, device);
        await flow.Connect();
        // A journal shared later: its entries reach the copy before the journal does.
        var journal = Guid.NewGuid();
        var entries = Enumerable.Range(1, 5).Select(day => (Id: Guid.NewGuid(), Day: day)).ToList();
        foreach (var (id, day) in entries)
        {
            await flow.Upload(new
            {
                kind = "entry",
                id,
                journalId = journal,
                title = "Notes",
                date = $"2026-08-0{day}T12:00:00Z",
                text = "Garden notes"
            }, id, 6);
        }
        await flow.Upload(new
        {
            kind = "journal",
            id = journal,
            name = "Garden"
        }, journal, 6);

        var first = (await flow.CallTool("search_entries", new JsonObject { ["query"] = "garden", ["limit"] = 2 }))["structuredContent"]!;
        var second = (await flow.CallTool("search_entries", new JsonObject { ["query"] = "garden", ["offset"] = 2, ["limit"] = 3 }))["structuredContent"]!;
        string[] Ids(JsonNode page) => page["entries"]!.AsArray().Select(x => (string)x!["id"]!).ToArray();
        Assert.Equal(entries.OrderByDescending(x => x.Day).Select(x => x.Id.ToString("D").ToUpperInvariant()), [.. Ids(first), .. Ids(second)]);
        Assert.Equal(2, (int)first["nextOffset"]!);
        Assert.Null(second["nextOffset"]);
        Assert.True((bool)(await flow.CallTool("search_entries", new JsonObject { ["journal_id"] = flow.PrivateJournal.ToString("D") }))["isError"]!);
    }

    // User information makes a redirect look as if it led to another site (https://trusted.example@other.example/).
    [Theory]
    [InlineData("https://legit.example@evil.example/cb")]
    [InlineData("https://user:pass@evil.example/cb")]
    [InlineData("https://legit.example%40x@evil.example/cb")]
    [InlineData("http://legit.example@127.0.0.1:8080/cb")]
    public async Task RedirectUrisWithUserInformationAreRefused(string redirect)
    {
        Assert.Null(OAuthRedirects.Classify(redirect));
        using var factory = new JournalFactory();
        using var anonymous = factory.CreateClient();
        var response = await anonymous.PostAsJsonAsync("/oauth/register", new
        {
            client_name = "U",
            redirect_uris = new[] { redirect },
            token_endpoint_auth_method = "none"
        });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("invalid_redirect_uri", (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("error").GetString());
    }

    [Theory]
    [InlineData("Claude‮Code", "ClaudeCode")]
    [InlineData("Claude​ Code⁦", "Claude Code")]
    [InlineData("Claude\nCode\r\n\tAgent", "Claude Code Agent")]
    [InlineData("‮\n ", "An agent")]
    [InlineData("An agent with a remarkably long self-chosen name, longer than forty", "An agent with a remarkably long self-cho…")]
    public void ClientNamesAreShownWithoutControlOrFormattingCharactersOnOneShortLine(string name, string shown) =>
        Assert.Equal(shown, AuthorizationPage.DisplayName(name));

    private static AuthorizationRequestDetails Details(string clientId) =>
        new(new OAuthClientInfo(clientId, "Client", ["http://127.0.0.1/callback"], false), "http://127.0.0.1:5000/callback", true, "s", new string('a', 43), "http://localhost/mcp", "journals:read", "http://localhost");

    private static async Task<HttpResponseMessage> Reconnect(HttpClient device, Guid requestId, int number, AgentFlow flow)
    {
        var secret = RandomNumberGenerator.GetBytes(32);
        var body = new JsonObject
        {
            ["number"] = number,
            ["grantId"] = flow.GrantId.ToString("D"),
            ["wrappedKey"] = Convert.ToBase64String(AgentKeys.Wrap(flow.CopyKey, secret, flow.GrantId)),
            ["grantSecret"] = Convert.ToBase64String(secret),
        };
        return await device.PostAsync($"/v1/agent-requests/{requestId}/approve", new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json"));
    }
}
