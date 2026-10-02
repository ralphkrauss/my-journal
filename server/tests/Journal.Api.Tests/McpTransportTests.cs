using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Journal.Api.Tests;

// The MCP endpoint's transport rules (protocol/agent-access-server.md, Streamable HTTP transport): the 2026-07-28
// stateless binding, the handshake revisions clients still use, discovery, Origin and CORS.
public sealed class McpTransportTests
{
    private static async Task<(JournalFactory Factory, AgentFlow Flow, HttpClient Device)> Connected()
    {
        var factory = new JournalFactory();
        var (device, _) = await factory.SetUp();
        var flow = new AgentFlow(factory, device);
        await flow.Connect();
        return (factory, flow, device);
    }

    private static async Task<JsonObject> Body(HttpResponseMessage response) => (JsonNode.Parse(await response.Content.ReadAsStringAsync()) as JsonObject)!;

    [Fact]
    public async Task UnauthenticatedRequestsLeadClientsToTheAuthorizationServer()
    {
        using var factory = new JournalFactory();
        using var client = factory.CreateClient();
        using var request = new HttpRequestMessage(HttpMethod.Post, "/mcp") { Content = new StringContent("{}", Encoding.UTF8, "application/json") };
        var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        var challenge = response.Headers.WwwAuthenticate.ToString();
        Assert.Contains("resource_metadata=\"http://localhost/.well-known/oauth-protected-resource/mcp\"", challenge, StringComparison.Ordinal);
        Assert.Contains("scope=\"journals:read\"", challenge, StringComparison.Ordinal);
        var resource = await client.GetFromJsonAsync<JsonElement>("/.well-known/oauth-protected-resource/mcp");
        Assert.Equal("http://localhost/mcp", resource.GetProperty("resource").GetString());
        var issuer = resource.GetProperty("authorization_servers")[0].GetString();
        var server = await client.GetFromJsonAsync<JsonElement>("/.well-known/oauth-authorization-server");
        Assert.Equal(issuer, server.GetProperty("issuer").GetString());
        Assert.Equal(["S256"], server.GetProperty("code_challenge_methods_supported").EnumerateArray().Select(x => x.GetString()));
        Assert.True(server.GetProperty("authorization_response_iss_parameter_supported").GetBoolean());
        Assert.Equal("http://localhost/mcp", (await client.GetFromJsonAsync<JsonElement>("/v1/server")).GetProperty("mcpUrl").GetString());
    }

    [Fact]
    public async Task ModernRequestsFollowTheHeaderAndVersionRules()
    {
        var (factory, flow, device) = await Connected();
        using var ownedFactory = factory;
        using var ownedDevice = device;
        var discover = await Body(await flow.Mcp("server/discover"));
        var supported = discover["result"]!["supportedVersions"]!.AsArray().Select(x => (string)x!).ToList();
        Assert.Equal(["2026-07-28", "2025-11-25", "2025-06-18"], supported);
        var tools = await Body(await flow.Mcp("tools/list"));
        Assert.Equal("private", (string)tools["result"]!["cacheScope"]!);
        Assert.Equal("complete", (string)tools["result"]!["resultType"]!);
        Assert.All(tools["result"]!["tools"]!.AsArray(), tool => Assert.True((bool)tool!["annotations"]!["readOnlyHint"]!));

        var mismatch = await flow.Mcp("tools/list", adjust: request => request.Headers.Remove("Mcp-Method"));
        Assert.Equal(HttpStatusCode.BadRequest, mismatch.StatusCode);
        Assert.Equal(-32020, (int)(await Body(mismatch))["error"]!["code"]!);
        var name = await flow.Mcp("tools/call", new JsonObject { ["name"] = "list_journals" }, adjust: request =>
        {
            request.Headers.Remove("Mcp-Name");
            request.Headers.Add("Mcp-Name", "read_entry");
        });
        Assert.Equal(-32020, (int)(await Body(name))["error"]!["code"]!);
        var future = await flow.Mcp("tools/list", adjust: request =>
        {
            request.Headers.Remove("MCP-Protocol-Version");
            request.Headers.Add("MCP-Protocol-Version", "2099-01-01");
        });
        Assert.Equal(-32020, (int)(await Body(future))["error"]!["code"]!);
        // Methods 2026-07-28 doesn't have, including the handshake and ping, are unknown there.
        foreach (var method in new[] { "resources/list", "initialize", "ping" })
        {
            var unknown = await flow.Mcp(method);
            Assert.Equal(HttpStatusCode.NotFound, unknown.StatusCode);
            Assert.Equal(-32601, (int)(await Body(unknown))["error"]!["code"]!);
        }
        // A header that disagrees with _meta is a mismatch before any version question.
        var disagreeing = await flow.Mcp("tools/list", adjust: request =>
        {
            request.Headers.Remove("MCP-Protocol-Version");
            request.Headers.Add("MCP-Protocol-Version", "2025-11-25");
        });
        Assert.Equal(-32020, (int)(await Body(disagreeing))["error"]!["code"]!);
        // Tool problems are results the model can act on, and unknown tools application errors with HTTP 200.
        var badTool = await flow.Mcp("tools/call", new JsonObject { ["name"] = "delete_everything" });
        Assert.Equal(HttpStatusCode.OK, badTool.StatusCode);
        Assert.Equal(-32602, (int)(await Body(badTool))["error"]!["code"]!);
    }

    [Fact]
    public async Task HandshakeClientsAreServedWithErrorsInHttp200()
    {
        var (factory, flow, device) = await Connected();
        using var ownedFactory = factory;
        using var ownedDevice = device;
        async Task<HttpResponseMessage> Legacy(string json, string? version)
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, "/mcp") { Content = new StringContent(json, Encoding.UTF8, "application/json") };
            request.Headers.Accept.ParseAdd("application/json, text/event-stream");
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", flow.AccessToken);
            if (version is not null)
            {
                request.Headers.Add("MCP-Protocol-Version", version);
            }
            using var client = factory.CreateClient();
            return await client.SendAsync(request);
        }
        var initialize = await Body(await Legacy("""{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}""", null));
        Assert.Equal("2025-06-18", (string)initialize["result"]!["protocolVersion"]!);
        Assert.Equal(HttpStatusCode.Accepted, (await Legacy("""{"jsonrpc":"2.0","method":"notifications/initialized"}""", "2025-06-18")).StatusCode);
        var list = await Legacy("""{"jsonrpc":"2.0","id":2,"method":"tools/list"}""", "2025-11-25");
        Assert.Equal(3, (await Body(list))["result"]!["tools"]!.AsArray().Count);
        var unknown = await Legacy("""{"jsonrpc":"2.0","id":3,"method":"prompts/list"}""", "2025-11-25");
        Assert.Equal(HttpStatusCode.OK, unknown.StatusCode);
        Assert.Equal(-32601, (int)(await Body(unknown))["error"]!["code"]!);
        var call = await Body(await Legacy("""{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"list_journals","arguments":{}}}""", "2025-11-25"));
        Assert.False((bool)call["result"]!["isError"]!);
        // A request with neither a version header nor _meta is refused by header validation.
        var none = await Legacy("""{"jsonrpc":"2.0","id":5,"method":"tools/list"}""", null);
        Assert.Equal(HttpStatusCode.BadRequest, none.StatusCode);
        Assert.Equal(-32020, (int)(await Body(none))["error"]!["code"]!);
        // A version this server doesn't implement, even a later one, names the supported versions so the client can retry.
        var later = await Body(await Legacy("""{"jsonrpc":"2.0","id":7,"method":"tools/list"}""", "2099-01-01"));
        Assert.Equal(-32022, (int)later["error"]!["code"]!);
        Assert.Equal(3, later["error"]!["data"]!["supported"]!.AsArray().Count);
        Assert.Equal(HttpStatusCode.BadRequest, (await Legacy("""[{"jsonrpc":"2.0","id":6,"method":"ping"}]""", "2025-11-25")).StatusCode);
    }

    [Fact]
    public async Task OriginsMethodsAndMediaTypesAreChecked()
    {
        var (factory, flow, device) = await Connected();
        using var ownedFactory = factory;
        using var ownedDevice = device;
        using var client = factory.CreateClient();
        Assert.Equal(HttpStatusCode.MethodNotAllowed, (await client.GetAsync("/mcp")).StatusCode);
        Assert.Equal(HttpStatusCode.MethodNotAllowed, (await client.DeleteAsync("/mcp")).StatusCode);
        // A browser client on any https origin gets the authorization challenge, readable through CORS, so it can start
        // OAuth; it reveals nothing, and without a token nothing is served.
        var browserStart = await flow.Mcp("tools/list", adjust: request =>
        {
            request.Headers.Authorization = null;
            request.Headers.Add("Origin", "https://inspector.example");
        });
        Assert.Equal(HttpStatusCode.Unauthorized, browserStart.StatusCode);
        Assert.Contains("resource_metadata=", browserStart.Headers.WwwAuthenticate.ToString(), StringComparison.Ordinal);
        Assert.Equal("https://inspector.example", browserStart.Headers.GetValues("Access-Control-Allow-Origin").Single());
        Assert.Contains("WWW-Authenticate", browserStart.Headers.GetValues("Access-Control-Expose-Headers").Single(), StringComparison.Ordinal);
        // Sandboxed or file pages (the "null" origin) and plain-http pages elsewhere are refused, without CORS.
        foreach (var refused in new[] { "null", "http://attacker.example" })
        {
            var response = await flow.Mcp("tools/list", adjust: request =>
            {
                request.Headers.Authorization = null;
                request.Headers.Add("Origin", refused);
            });
            Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
            Assert.False(response.Headers.Contains("Access-Control-Allow-Origin"));
            Assert.Empty(response.Headers.WwwAuthenticate);
        }
        var browserClient = await flow.Mcp("tools/list", adjust: request => request.Headers.Add("Origin", "https://inspector.example"));
        Assert.Equal(HttpStatusCode.OK, browserClient.StatusCode);
        Assert.Equal("https://inspector.example", browserClient.Headers.GetValues("Access-Control-Allow-Origin").Single());
        var html = await flow.Mcp("tools/list", adjust: request =>
        {
            request.Headers.Accept.Clear();
            request.Headers.Accept.ParseAdd("text/html");
        });
        Assert.Equal(HttpStatusCode.NotAcceptable, html.StatusCode);
    }

    [Fact]
    public async Task AConfiguredPublicAddressAloneNamesTheResourceAndIssuer()
    {
        using var factory = new JournalFactory();
        factory.Settings["Journal:PublicUrl"] = "https://journal.example.ts.net/";
        using var client = factory.CreateClient();
        // Requests for another host name get no metadata that would name it.
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync("/.well-known/oauth-authorization-server")).StatusCode);
        client.DefaultRequestHeaders.Host = "journal.example.ts.net";
        var server = await client.GetFromJsonAsync<JsonElement>("/.well-known/oauth-authorization-server");
        Assert.Equal("https://journal.example.ts.net", server.GetProperty("issuer").GetString());
        var resource = await client.GetFromJsonAsync<JsonElement>("/.well-known/oauth-protected-resource/mcp");
        Assert.Equal("https://journal.example.ts.net/mcp", resource.GetProperty("resource").GetString());
        Assert.Equal("https://journal.example.ts.net/mcp", (await client.GetFromJsonAsync<JsonElement>("/v1/server")).GetProperty("mcpUrl").GetString());
    }

    // Client metadata documents need outbound HTTPS. A Compose profile whose server has no route out (only an internal
    // network) must not advertise them, or clients that prefer them reach a dead end.
    [Fact]
    public void ComposeProfilesAdvertiseClientMetadataDocumentsOnlyWithInternetAccess()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null && !File.Exists(Path.Combine(directory.FullName, "deploy", "compose.yaml")))
        {
            directory = directory.Parent;
        }
        Assert.NotNull(directory);
        foreach (var file in Directory.EnumerateFiles(Path.Combine(directory.FullName, "deploy"), "compose*.yaml"))
        {
            var text = File.ReadAllText(file);
            var offline = text.Contains("internal: true", StringComparison.Ordinal);
            var disabled = text.Contains("Journal__ClientMetadataDocuments: \"false\"", StringComparison.Ordinal);
            Assert.True(offline == disabled, Path.GetFileName(file) + " must disable client metadata documents exactly when its server has no internet access.");
        }
    }
}

