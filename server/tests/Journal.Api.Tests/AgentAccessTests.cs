using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Journal.Api.Data;
using Journal.Api.Features;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace Journal.Api.Tests;

// Agent access through MCP (protocol/agent-access-server.md): what an authorized agent can read, how tokens are bound
// and rotated, and that revocation, expiry and restores leave no usable access or key material behind.
public sealed class AgentAccessTests
{
    [Fact]
    public async Task AnApprovedAgentReadsOnlyTheGrantedJournals()
    {
        using var factory = new JournalFactory();
        var (device, _) = await factory.SetUp();
        using var ownedDevice = device;
        var flow = new AgentFlow(factory, device);
        await flow.Connect();

        var journals = (await flow.CallTool("list_journals"))["structuredContent"]!["journals"]!.AsArray();
        Assert.Equal(["Work"], journals.Select(x => (string)x!["name"]!));
        var found = (await flow.CallTool("search_entries", new JsonObject { ["query"] = "CAFE" }))["structuredContent"]!;
        Assert.Equal([flow.SharedEntry.ToString("D").ToUpperInvariant()], found["entries"]!.AsArray().Select(x => (string)x!["id"]!));
        Assert.True((bool)found["copy"]!["complete"]!);
        // An entry the copy holds but whose journal isn't shared stays invisible, by search and by ID.
        Assert.Empty((await flow.CallTool("search_entries", new JsonObject { ["query"] = "Never" }))["structuredContent"]!["entries"]!.AsArray());
        var hidden = await flow.CallTool("read_entry", new JsonObject { ["entry_id"] = flow.PrivateEntry.ToString("D") });
        Assert.True((bool)hidden["isError"]!);
        Assert.Null(hidden["structuredContent"]);
        var read = await flow.CallTool("read_entry", new JsonObject { ["entry_id"] = flow.SharedEntry.ToString("D"), ["max_characters"] = 12 });
        Assert.Equal("The plan for", (string)read["structuredContent"]!["entry"]!["text"]!);
        Assert.Equal(12, (int)read["structuredContent"]!["entry"]!["nextOffset"]!);

        // The token is bound to this resource: presented at another host name of the same server, it's refused.
        var elsewhere = await flow.Mcp("tools/list", adjust: request => request.Headers.Host = "127.0.0.1");
        Assert.Equal(HttpStatusCode.Unauthorized, elsewhere.StatusCode);
        // Device and agent tokens never stand in for each other.
        Assert.Equal(HttpStatusCode.Unauthorized, (await flow.Mcp("tools/list", token: device.DefaultRequestHeaders.Authorization!.Parameter)).StatusCode);
        using var agentAsDevice = factory.CreateClient();
        agentAsDevice.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", flow.AccessToken);
        Assert.Equal(HttpStatusCode.Unauthorized, (await agentAsDevice.GetAsync("/v1/sync/")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await agentAsDevice.GetAsync("/v1/agents/")).StatusCode);
        // The owner's devices see the agent, its client and its activity.
        var grants = await device.GetFromJsonAsync<JsonElement>("/v1/agents/");
        Assert.Equal("active", grants[0].GetProperty("state").GetString());
        Assert.Equal("Test Agent", grants[0].GetProperty("clientName").GetString());
        var activity = await device.GetFromJsonAsync<JsonElement>($"/v1/agents/{flow.GrantId}/activity");
        Assert.Contains(activity.EnumerateArray(), x => x.GetProperty("tool").GetString() == "search_entries");
    }

    [Fact]
    public async Task AuthorizationRequiresPkceTheRightResourceAndARegisteredRedirect()
    {
        using var factory = new JournalFactory();
        var (device, _) = await factory.SetUp();
        using var ownedDevice = device;
        var flow = new AgentFlow(factory, device);
        var registered = await flow.Register();
        using var browser = factory.CreateClient(new()
        {
            AllowAutoRedirect = false
        });
        // An unregistered redirect is never followed.
        var foreign = await browser.GetAsync($"/oauth/authorize?response_type=code&client_id={registered}&redirect_uri={Uri.EscapeDataString("https://attacker.example/cb")}&code_challenge={AgentFlow.Challenge}&code_challenge_method=S256");
        Assert.Equal(HttpStatusCode.BadRequest, foreign.StatusCode);
        // Another resource is refused back to the client, with the issuer.
        var wrongResource = await browser.GetAsync($"/oauth/authorize?response_type=code&client_id={registered}&redirect_uri={Uri.EscapeDataString(AgentFlow.Redirect)}&code_challenge={AgentFlow.Challenge}&code_challenge_method=S256&state=s&resource={Uri.EscapeDataString("https://other.example/mcp")}");
        var refused = QueryHelpers.ParseQuery(wrongResource.Headers.Location!.Query);
        Assert.Equal("invalid_target", refused["error"]);
        Assert.Equal("http://localhost", refused["iss"]);
        // Without PKCE there's no request.
        var plain = await browser.GetAsync($"/oauth/authorize?response_type=code&client_id={registered}&redirect_uri={Uri.EscapeDataString(AgentFlow.Redirect)}&code_challenge=abc&code_challenge_method=plain");
        Assert.Equal("invalid_request", QueryHelpers.ParseQuery(plain.Headers.Location!.Query)["error"]);

        // The resource may be omitted (RFC 8707: the one this server has); a wrong verifier gets nothing.
        var (number, handle) = await flow.OpenAuthorizationPage(resource: null);
        await flow.Approve(number);
        var callback = QueryHelpers.ParseQuery((await flow.Callback(handle)).Query);
        Assert.Equal("xyz", callback["state"]);
        Assert.Equal("http://localhost", callback["iss"]);
        var authorizationCode = callback["code"].ToString();
        Assert.Equal("invalid_grant", (await (await flow.Exchange(authorizationCode, AgentFlow.Verifier + "x")).Content.ReadFromJsonAsync<JsonElement>()).GetProperty("error").GetString());
        // The code was consumed by that attempt; presenting it again gets nothing either.
        Assert.Equal(HttpStatusCode.BadRequest, (await flow.Exchange(authorizationCode, AgentFlow.Verifier)).StatusCode);
    }

    [Fact]
    public async Task ARedeemedCodeUsedAgainRevokesTheTokensItIssued()
    {
        using var factory = new JournalFactory();
        var (device, _) = await factory.SetUp();
        using var ownedDevice = device;
        var flow = new AgentFlow(factory, device);
        await flow.Register();
        var (number, handle) = await flow.OpenAuthorizationPage();
        await flow.Approve(number);
        var authorizationCode = QueryHelpers.ParseQuery((await flow.Callback(handle)).Query)["code"].ToString();
        var first = await flow.Exchange(authorizationCode, AgentFlow.Verifier);
        Assert.Equal("no-store", first.Headers.CacheControl?.ToString());
        flow.Keep(await first.Content.ReadFromJsonAsync<JsonElement>());
        Assert.Equal(HttpStatusCode.OK, (await flow.Mcp("tools/list")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await flow.Exchange(authorizationCode, AgentFlow.Verifier)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await flow.Mcp("tools/list")).StatusCode);
    }

    [Fact]
    public async Task RefreshTokensRotateWithAShortGraceAndReuseAfterItSignsTheAgentOut()
    {
        var clock = new ManualClock(DateTimeOffset.UtcNow);
        using var factory = new JournalFactory { Clock = clock };
        var (device, _) = await factory.SetUp();
        using var ownedDevice = device;
        var flow = new AgentFlow(factory, device);
        await flow.Connect();
        var original = flow.RefreshToken;
        var rotated = await flow.RefreshWith(original);
        rotated.EnsureSuccessStatusCode();
        flow.Keep(await rotated.Content.ReadFromJsonAsync<JsonElement>());
        Assert.Equal(HttpStatusCode.OK, (await flow.Mcp("tools/list")).StatusCode);
        // A concurrent client retrying within the grace still gets tokens.
        clock.Now += TimeSpan.FromSeconds(30);
        (await flow.RefreshWith(original)).EnsureSuccessStatusCode();
        // Afterwards the replaced token signals theft: every token of the family goes.
        clock.Now += TimeSpan.FromSeconds(60);
        Assert.Equal(HttpStatusCode.BadRequest, (await flow.RefreshWith(original)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await flow.Mcp("tools/list")).StatusCode);
        var grants = await device.GetFromJsonAsync<JsonElement>("/v1/agents/");
        Assert.Equal("needsReconnect", grants[0].GetProperty("state").GetString());
    }

    [Fact]
    public async Task ARevokedSiblingRefreshTokenPresentedAgainSignsTheAgentOut()
    {
        using var factory = new JournalFactory();
        var (device, _) = await factory.SetUp();
        using var ownedDevice = device;
        var flow = new AgentFlow(factory, device);
        await flow.Connect();
        var original = flow.RefreshToken;
        // Two refreshes with the same token within the grace, as concurrent clients do, create siblings.
        var first = (await (await flow.RefreshWith(original)).Content.ReadFromJsonAsync<JsonElement>()).GetProperty("refresh_token").GetString()!;
        var second = (await (await flow.RefreshWith(original)).Content.ReadFromJsonAsync<JsonElement>()).GetProperty("refresh_token").GetString()!;
        var rotated = await flow.RefreshWith(first);
        rotated.EnsureSuccessStatusCode();
        flow.Keep(await rotated.Content.ReadFromJsonAsync<JsonElement>());
        Assert.Equal(HttpStatusCode.OK, (await flow.Mcp("tools/list")).StatusCode);
        // The sibling was revoked when the first was used; presenting it is reuse.
        Assert.Equal(HttpStatusCode.BadRequest, (await flow.RefreshWith(second)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await flow.Mcp("tools/list")).StatusCode);
        Assert.Equal("needsReconnect", (await device.GetFromJsonAsync<JsonElement>("/v1/agents/"))[0].GetProperty("state").GetString());
    }

    [Theory]
    [InlineData("http://nas.local:8080/", "http://localhost/mcp")]
    [InlineData("not an address", "http://localhost/mcp")]
    [InlineData("https://Journal.Example.ts.net/", "https://journal.example.ts.net/mcp")]
    public async Task ExistingJournalUrlsKeepTheServerSyncing(string journalUrl, string mcpUrl)
    {
        using var factory = new JournalFactory();
        factory.Settings["JOURNAL_URL"] = journalUrl;
        var (device, _) = await factory.SetUp();
        using var ownedDevice = device;
        (await device.PutAsJsonAsync($"/v1/sync/{Guid.NewGuid()}", new PutRecord(Guid.NewGuid(), 0, "entry", Convert.ToBase64String(new byte[40])))).EnsureSuccessStatusCode();
        Assert.Equal(mcpUrl, (await device.GetFromJsonAsync<JsonElement>("/v1/server")).GetProperty("mcpUrl").GetString());
    }

    [Fact]
    public async Task RevokingRemovesTheGrantItsTokensAndTheirKeyWrapsFromTheDatabaseFiles()
    {
        using var factory = new JournalFactory();
        var (device, _) = await factory.SetUp();
        using var ownedDevice = device;
        var flow = new AgentFlow(factory, device);
        await flow.Connect();
        byte[][] wraps;
        await using (var scope = factory.Services.CreateAsyncScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<JournalDb>();
            wraps = await db.OAuthTokens.Select(x => x.WrappedKey).ToArrayAsync();
        }
        Assert.NotEmpty(wraps);
        Assert.Equal(HttpStatusCode.NoContent, (await device.DeleteAsync($"/v1/agents/{flow.GrantId}")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await flow.Mcp("tools/list")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await flow.RefreshWith(flow.RefreshToken)).StatusCode);
        foreach (var file in Directory.EnumerateFiles(factory.Root, "journal.db*"))
        {
            var bytes = await ReadShared(file);
            Assert.All(wraps, wrap => Assert.Equal(-1, bytes.AsSpan().IndexOf(wrap)));
            Assert.Equal(-1, bytes.AsSpan().IndexOf(flow.CopyKey));
        }
    }

    [Fact]
    public async Task WhenAccessEndsTheAgentIsRefusedAndItsCopyIsDeleted()
    {
        var clock = new ManualClock(DateTimeOffset.UtcNow);
        using var factory = new JournalFactory { Clock = clock };
        var (device, _) = await factory.SetUp();
        using var ownedDevice = device;
        var flow = new AgentFlow(factory, device);
        await flow.Connect(clock.Now.AddDays(30));
        clock.Now = clock.Now.AddDays(31);
        Assert.Equal(HttpStatusCode.Unauthorized, (await flow.Mcp("tools/list")).StatusCode);
        var grants = await device.GetFromJsonAsync<JsonElement>("/v1/agents/");
        // Kept for the owner to see that access ended, without tokens or copy.
        Assert.Single(grants.EnumerateArray());
        await using var scope = factory.Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<JournalDb>();
        Assert.False(await db.OAuthTokens.AnyAsync());
        Assert.False(await db.AgentItems.AnyAsync());
    }

    [Fact]
    public async Task AnApprovalWhoseCodeIsNeverRedeemedLeavesNoGrant()
    {
        var clock = new ManualClock(DateTimeOffset.UtcNow);
        using var factory = new JournalFactory { Clock = clock };
        var (device, _) = await factory.SetUp();
        using var ownedDevice = device;
        var flow = new AgentFlow(factory, device);
        await flow.Register();
        var (number, handle) = await flow.OpenAuthorizationPage();
        var request = (await flow.WaitingRequests()).Single();
        var approval = new AgentApproval(number, Guid.NewGuid(), Convert.ToBase64String(new byte[60]), Convert.ToBase64String(new byte[32]), Convert.ToBase64String(new byte[48]));
        (await device.PostAsJsonAsync($"/v1/agent-requests/{request.Id}/approve", approval)).EnsureSuccessStatusCode();
        // The device never says the copy is ready (it went to the background): the page says access is allowed at
        // once, and the server releases the code on its own after 15 seconds.
        using var browser = factory.CreateClient();
        var approved = await browser.GetFromJsonAsync<JsonElement>("/oauth/authorize/status?handle=" + handle);
        Assert.Equal("approved", approved.GetProperty("status").GetString());
        Assert.Equal(JsonValueKind.Null, approved.GetProperty("redirect").ValueKind);
        clock.Now += TimeSpan.FromSeconds(16);
        Assert.Equal("allowed", (await browser.GetFromJsonAsync<JsonElement>("/oauth/authorize/status?handle=" + handle)).GetProperty("status").GetString());
        // Nobody redeems the code: once the request expires, the pending grant goes.
        clock.Now += TimeSpan.FromMinutes(20);
        Assert.Empty((await device.GetFromJsonAsync<JsonElement>("/v1/agents/")).EnumerateArray());
    }

    [Fact]
    public async Task StoppingAPendingAgentTellsItsPageThatAccessWasDeclined()
    {
        using var factory = new JournalFactory();
        var (device, _) = await factory.SetUp();
        using var ownedDevice = device;
        var flow = new AgentFlow(factory, device);
        await flow.Register();
        var (number, handle) = await flow.OpenAuthorizationPage();
        await flow.Approve(number);
        Assert.Equal(HttpStatusCode.NoContent, (await device.DeleteAsync($"/v1/agents/{flow.GrantId}")).StatusCode);
        using var browser = factory.CreateClient();
        var status = await browser.GetFromJsonAsync<JsonElement>("/oauth/authorize/status?handle=" + handle);
        Assert.Equal("declined", status.GetProperty("status").GetString());
        Assert.Equal("access_denied", QueryHelpers.ParseQuery(new Uri(status.GetProperty("redirect").GetString()!).Query)["error"]);
    }

    [Fact]
    public async Task RestoringABackupAndTurningOnEncryptionRemoveEveryAgent()
    {
        var root = Path.Combine(Path.GetTempPath(), "journal-agent-restore-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            string token;
            using (var factory = new JournalFactory())
            {
                var (device, _) = await factory.SetUp();
                using var ownedDevice = device;
                var flow = new AgentFlow(factory, device);
                await flow.Connect();
                token = flow.AccessToken;
                await BackupArchive.Create(factory.Root, Path.Combine(root, "backup"));
            }
            await BackupArchive.Restore(Path.Combine(root, "backup"), Path.Combine(root, "restored"));
            using var restored = new JournalFactory(Path.Combine(root, "restored"));
            await using var scope = restored.Services.CreateAsyncScope();
            var db = scope.ServiceProvider.GetRequiredService<JournalDb>();
            Assert.False(await db.AgentGrants.AnyAsync());
            Assert.False(await db.OAuthTokens.AnyAsync());
            Assert.False(await db.OAuthClients.AnyAsync());
            Assert.NotEmpty(token);
        }
        finally { Directory.Delete(root, true); }

        using var unencrypted = new JournalFactory();
        using var owner = unencrypted.CreateClient();
        var setupCode = await File.ReadAllTextAsync(Path.Combine(unencrypted.Root, "setup-code"));
        var setUp = await owner.PostAsJsonAsync("/v1/setup", new SetupRequest(setupCode, "", "", 0, new string('a', 64), "Mac", 4));
        owner.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", (await setUp.Content.ReadFromJsonAsync<DeviceGrant>())!.Token);
        var agent = new AgentFlow(unencrypted, owner);
        await agent.Connect();
        var id = Guid.NewGuid();
        var receipt = await (await owner.PutAsJsonAsync($"/v1/sync/{id}", new PutRecord(Guid.NewGuid(), 0, "entry", Convert.ToBase64String(new byte[40])))).Content.ReadFromJsonAsync<JsonElement>();
        var encrypt = new TurnOnEncryptionRequest(Convert.ToBase64String(new byte[16]), Convert.ToBase64String(new byte[60]), 600_000, new string('c', 64), 2,
            receipt.GetProperty("cursor").GetInt64(), id, receipt.GetProperty("revision").GetInt64(), null);
        (await owner.PostAsJsonAsync("/v1/recovery/encrypt", encrypt)).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Unauthorized, (await agent.Mcp("tools/list")).StatusCode);
        Assert.Empty((await owner.GetFromJsonAsync<JsonElement>("/v1/agents/")).EnumerateArray());
    }

    [Fact]
    public async Task OnlyPresentedTokensThatFailCountTowardTheFailureLimit()
    {
        using var factory = new JournalFactory();
        var (device, _) = await factory.SetUp();
        using var ownedDevice = device;
        var flow = new AgentFlow(factory, device);
        await flow.Connect();
        for (var index = 0; index < 30; index++)
        {
            Assert.Equal(HttpStatusCode.Unauthorized, (await flow.Mcp("tools/list", token: "mjat_" + new string('A', 107))).StatusCode);
        }
        Assert.Equal(HttpStatusCode.TooManyRequests, (await flow.Mcp("tools/list", token: "mjat_" + new string('A', 107))).StatusCode);
        // Discovery without a token and a valid token are never refused by it.
        Assert.Equal(HttpStatusCode.Unauthorized, (await flow.Mcp("tools/list", adjust: request => request.Headers.Authorization = null)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await flow.Mcp("tools/list")).StatusCode);
    }

    // SQLite keeps the files open; read them the way another process would.
    private static async Task<byte[]> ReadShared(string path)
    {
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        var bytes = new byte[stream.Length];
        await stream.ReadExactlyAsync(bytes);
        return bytes;
    }

    // protocol/conformance/agent-copy/agent-copy-v1.json: .NET reproduces the key derivation, item ID, digest, sealed item and key
    // wrap independently; opening at another position fails.
    [Fact]
    public void AgentCopyFixtureMatchesIndependentDotNetCryptography()
    {
        using var corpus = ConformanceFiles.Json("agent-copy/agent-copy-v1.json");
        var fixture = corpus.RootElement;
        var copyKey = fixture.GetProperty("copyKey").GetBytesFromBase64();
        var grantId = Guid.Parse(fixture.GetProperty("grantId").GetString()!);
        using var keys = Journal.Api.Security.AgentCopyKeys.FromCopyKey(copyKey);
        var item = fixture.GetProperty("item");
        var itemId = keys.ItemId(Guid.Parse(item.GetProperty("recordId").GetString()!));
        Assert.Equal(item.GetProperty("itemId").GetString(), itemId);
        var opened = keys.Open(grantId, itemId, item.GetProperty("combined").GetString()!);
        Assert.Equal("Fixture entry", opened?.Title);
        Assert.Null(keys.Open(Guid.NewGuid(), itemId, item.GetProperty("combined").GetString()!));
        var wrap = fixture.GetProperty("wrap");
        var unwrapped = Journal.Api.Security.AgentKeys.Unwrap(wrap.GetProperty("wrappedKey").GetBytesFromBase64(), wrap.GetProperty("secret").GetBytesFromBase64(), grantId);
        Assert.Equal(copyKey, unwrapped);
        Assert.Null(Journal.Api.Security.AgentKeys.Unwrap(wrap.GetProperty("wrappedKey").GetBytesFromBase64(), new byte[32], grantId));
        var digest = Convert.ToHexStringLower(System.Security.Cryptography.HMACSHA256.HashData(
            System.Security.Cryptography.HKDF.DeriveKey(System.Security.Cryptography.HashAlgorithmName.SHA256, copyKey, 32, [], "journal:v1:agent-copy:item-id"u8.ToArray()),
            (byte[])[.. "journal:v1:agent-digest:"u8, .. item.GetProperty("plaintext").GetBytesFromBase64()])[..16]);
        Assert.Equal(item.GetProperty("digest").GetString(), digest);
    }
}
