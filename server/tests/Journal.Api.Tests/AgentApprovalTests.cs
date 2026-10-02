using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using Journal.Api.Data;
using Journal.Api.Features;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace Journal.Api.Tests;

// How the owner approves an agent (protocol/agent-access-server.md, Approval in the app): the request appears on the
// owner's devices, the number the page shows decides which request is approved, declining sends the page back, and
// changed settings take effect at once without a device overwriting another's change.
public sealed class AgentApprovalTests
{
    [Fact]
    public async Task OnlyThePagesNumberApprovesAndAWrongNumberOrDontAllowSendsThePageBack()
    {
        using var factory = new JournalFactory();
        var (device, _) = await factory.SetUp();
        using var ownedDevice = device;
        var flow = new AgentFlow(factory, device);
        await flow.Register();
        var (number, handle) = await flow.OpenAuthorizationPage();

        // Devices see the request and where it returns to, never the number: the owner reads it from the page.
        var listed = await device.GetStringAsync("/v1/agent-requests/");
        Assert.DoesNotContain("number", listed, StringComparison.OrdinalIgnoreCase);
        var request = (await flow.WaitingRequests()).Single();
        Assert.Equal("127.0.0.1", request.RedirectHost);

        var wrong = number == 99 ? 10 : number + 1;
        var refused = await flow.SendApproval(request.Id, wrong);
        Assert.Equal(HttpStatusCode.Conflict, refused.StatusCode);
        Assert.Equal("agent_request_mismatch", (await refused.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("code").GetString());
        // The request is over: the right number can't be tried next, nothing was granted, and the page returns to
        // the client with access_denied, its state and the issuer.
        Assert.Equal(HttpStatusCode.NotFound, (await flow.SendApproval(request.Id, number)).StatusCode);
        Assert.Empty((await device.GetFromJsonAsync<JsonElement>("/v1/agents/")).EnumerateArray());
        await AssertDeclined(factory, handle);

        // Don't Allow does the same.
        var (_, second) = await flow.OpenAuthorizationPage();
        var next = (await flow.WaitingRequests()).Single();
        Assert.Equal(HttpStatusCode.NoContent, (await device.PostAsync($"/v1/agent-requests/{next.Id}/decline", null)).StatusCode);
        await AssertDeclined(factory, second);
    }

    [Fact]
    public async Task ARetryReplacesOnlyTheSameClientsRequestFromTheSameAddressAndNeverTakesOverAConnectedAgent()
    {
        using var factory = new JournalFactory();
        var (device, _) = await factory.SetUp();
        using var ownedDevice = device;
        var flow = new AgentFlow(factory, device);
        await flow.Connect();

        // The owner's client asks again from the owner's computer, twice: the newer request replaces the older.
        var (_, first) = await flow.OpenAuthorizationPage(address: "10.0.0.2");
        var (_, retry) = await flow.OpenAuthorizationPage(address: "10.0.0.2");
        using var browser = factory.CreateClient();
        Assert.Equal("replaced", (await browser.GetFromJsonAsync<JsonElement>("/oauth/authorize/status?handle=" + first)).GetProperty("status").GetString());
        // A stranger presenting the same client ID (as every copy of an app with a metadata document does) from
        // another address replaces nothing.
        var (_, stranger) = await flow.OpenAuthorizationPage(address: "203.0.113.9");
        Assert.Equal("waiting", (await browser.GetFromJsonAsync<JsonElement>("/oauth/authorize/status?handle=" + retry)).GetProperty("status").GetString());
        Assert.Equal("waiting", (await browser.GetFromJsonAsync<JsonElement>("/oauth/authorize/status?handle=" + stranger)).GetProperty("status").GetString());
        // Neither would reconnect the connected agent of that client, whose access keeps working.
        var waiting = await flow.WaitingRequests();
        Assert.Equal(2, waiting.Count);
        Assert.All(waiting, x => Assert.Null(x.ReconnectCandidate));
        Assert.Equal(HttpStatusCode.OK, (await flow.Mcp("tools/list")).StatusCode);
    }

    [Fact]
    public async Task NarrowedJournalsAreHiddenAtOnceAndOnlyTheCurrentRevisionCanChangeTheAgent()
    {
        using var factory = new JournalFactory();
        var (device, _) = await factory.SetUp();
        using var ownedDevice = device;
        var flow = new AgentFlow(factory, device);
        await flow.Connect();
        var metadata = Convert.ToBase64String(new byte[48]);

        // Uploads name the revision their plan used; without one they're refused.
        var unversioned = await device.PostAsJsonAsync($"/v1/agents/{flow.GrantId}/items", new UploadItemsRequest([], true));
        Assert.Equal(HttpStatusCode.BadRequest, unversioned.StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await device.PutAsJsonAsync($"/v1/agents/{flow.GrantId}", new AgentChange(null, metadata, null, []))).StatusCode);

        // The owner stops sharing Work: its journal item is emptied with the change, so its entries are hidden at
        // once, while their items are still stored until a device removes them.
        // As the app sends it: no end date means access never ends, so the field is left out.
        var body = "{\"metadata\":\"" + metadata + "\",\"removedItems\":[\"" + flow.ItemId(flow.SharedJournal) + "\"],\"revision\":1}";
        var changed = await device.PutAsync($"/v1/agents/{flow.GrantId}", new StringContent(body, System.Text.Encoding.UTF8, "application/json"));
        Assert.Equal(HttpStatusCode.OK, changed.StatusCode);
        Assert.Equal(2, (await changed.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("revision").GetInt64());
        Assert.Empty((await flow.CallTool("list_journals"))["structuredContent"]!["journals"]!.AsArray());
        Assert.Empty((await flow.CallTool("search_entries", new JsonObject { ["query"] = "café" }))["structuredContent"]!["entries"]!.AsArray());
        Assert.True((bool)(await flow.CallTool("read_entry", new JsonObject { ["entry_id"] = flow.SharedEntry.ToString("D") }))["isError"]!);
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<JournalDb>();
            Assert.NotNull((await db.AgentItems.SingleAsync(x => x.GrantId == flow.GrantId && x.ItemId == flow.ItemId(flow.SharedEntry))).Payload);
        }

        // A device that still plans with revision 1 can neither upload nor change the settings back.
        var stale = await device.PostAsJsonAsync($"/v1/agents/{flow.GrantId}/items", new UploadItemsRequest([], true, 1));
        Assert.Equal(HttpStatusCode.Conflict, stale.StatusCode);
        Assert.Equal("agent_settings_changed", (await stale.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("code").GetString());
        Assert.Equal(HttpStatusCode.Conflict, (await device.PutAsJsonAsync($"/v1/agents/{flow.GrantId}", new AgentChange(1, metadata, null, []))).StatusCode);
        var listed = await device.GetFromJsonAsync<JsonElement>("/v1/agents/");
        Assert.Equal(2, listed[0].GetProperty("revision").GetInt64());
    }

    [Fact]
    public async Task AnAgentThatSignedOutReconnectsToTheSameGrantAsTheAppApprovesIt()
    {
        using var factory = new JournalFactory();
        var (device, _) = await factory.SetUp();
        using var ownedDevice = device;
        var flow = new AgentFlow(factory, device);
        await flow.Connect();
        using (var client = factory.CreateClient())
        {
            (await client.PostAsync("/oauth/revoke", new FormUrlEncodedContent(new Dictionary<string, string> { ["token"] = flow.RefreshToken, ["client_id"] = flow.ClientId }))).EnsureSuccessStatusCode();
        }
        Assert.Equal("needsReconnect", (await device.GetFromJsonAsync<JsonElement>("/v1/agents/"))[0].GetProperty("state").GetString());

        // The same client asks again; the request is offered as a reconnect of that agent.
        var (number, handle) = await flow.OpenAuthorizationPage();
        var request = (await flow.WaitingRequests()).Single();
        Assert.Equal(flow.GrantId, request.ReconnectCandidate);
        // As the app approves a reconnect: a new wrap of the same copy key, and no metadata field.
        var secret = System.Security.Cryptography.RandomNumberGenerator.GetBytes(32);
        var wrapped = Journal.Api.Security.AgentKeys.Wrap(flow.CopyKey, secret, flow.GrantId);
        var body = "{\"grantId\":\"" + flow.GrantId + "\",\"grantSecret\":\"" + Convert.ToBase64String(secret) + "\",\"number\":" + number +
            ",\"wrappedKey\":\"" + Convert.ToBase64String(wrapped) + "\"}";
        var approved = await device.PostAsync($"/v1/agent-requests/{request.Id}/approve", new StringContent(body, System.Text.Encoding.UTF8, "application/json"));
        Assert.Equal(HttpStatusCode.NoContent, approved.StatusCode);
        (await device.PostAsJsonAsync($"/v1/agent-requests/{request.Id}/ready", new AgentReady(true))).EnsureSuccessStatusCode();
        var callback = QueryHelpers.ParseQuery((await flow.Callback(handle)).Query);
        var tokens = await flow.Exchange(callback["code"].ToString(), AgentFlow.Verifier);
        tokens.EnsureSuccessStatusCode();
        flow.Keep(await tokens.Content.ReadFromJsonAsync<JsonElement>());
        // One agent, connected again, reading the copy it had.
        var grants = await device.GetFromJsonAsync<JsonElement>("/v1/agents/");
        Assert.Equal(1, grants.GetArrayLength());
        Assert.Equal("active", grants[0].GetProperty("state").GetString());
        Assert.Equal(["Work"], (await flow.CallTool("list_journals"))["structuredContent"]!["journals"]!.AsArray().Select(x => (string)x!["name"]!));
    }

    [Fact]
    public async Task AJournalDeletedAsTheAppSendsItLeavesWhatTheAgentListsAndFinds()
    {
        using var factory = new JournalFactory();
        var (device, _) = await factory.SetUp();
        using var ownedDevice = device;
        var flow = new AgentFlow(factory, device);
        await flow.Connect();
        Assert.Single((await flow.CallTool("list_journals"))["structuredContent"]!["journals"]!.AsArray());

        // The journal went to Recently Deleted: a device empties its item and its entry's, leaving the payload out
        // as the app's encoder did before it sent an explicit null.
        var items = new[] { flow.ItemId(flow.SharedJournal), flow.ItemId(flow.SharedEntry) }
            .Select(id => "{\"digest\":\"" + new string('0', 32) + "\",\"id\":\"" + id + "\",\"version\":9}");
        var body = "{\"items\":[" + string.Join(',', items) + "],\"revision\":1}";
        var deleted = await device.PostAsync($"/v1/agents/{flow.GrantId}/items", new StringContent(body, System.Text.Encoding.UTF8, "application/json"));
        Assert.Equal(HttpStatusCode.OK, deleted.StatusCode);
        Assert.Empty((await flow.CallTool("list_journals"))["structuredContent"]!["journals"]!.AsArray());
        Assert.Empty((await flow.CallTool("search_entries", new JsonObject { ["query"] = "café" }))["structuredContent"]!["entries"]!.AsArray());
    }

    private static async Task AssertDeclined(JournalFactory factory, string handle)
    {
        using var browser = factory.CreateClient();
        var status = await browser.GetFromJsonAsync<JsonElement>("/oauth/authorize/status?handle=" + handle);
        Assert.Equal("declined", status.GetProperty("status").GetString());
        var query = QueryHelpers.ParseQuery(new Uri(status.GetProperty("redirect").GetString()!).Query);
        Assert.Equal("access_denied", query["error"]);
        Assert.Equal("xyz", query["state"]);
        Assert.Equal("http://localhost", query["iss"]);
    }
}
