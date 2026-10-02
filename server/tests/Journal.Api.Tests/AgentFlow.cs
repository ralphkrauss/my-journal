using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Journal.Api.Features;
using Journal.Api.Security;

namespace Journal.Api.Tests;

// Drives agent access the way a real MCP client and an owner's device do: registration, the authorization page,
// approval with the page's number, the copy's upload and the token exchange (protocol/agent-access-server.md).
public sealed partial class AgentFlow(JournalFactory factory, HttpClient device)
{
    public const string Resource = "http://localhost/mcp";
    public const string Redirect = "http://127.0.0.1:43210/callback";
    public Guid SharedJournal { get; } = Guid.NewGuid();
    public Guid PrivateJournal { get; } = Guid.NewGuid();
    public Guid SharedEntry { get; } = Guid.NewGuid();
    public Guid PrivateEntry { get; } = Guid.NewGuid();
    public Guid GrantId
    {
        get; private set;
    }
    public byte[] CopyKey { get; } = RandomNumberGenerator.GetBytes(32);
    public string ClientId { get; private set; } = "";
    public string AccessToken { get; private set; } = "";
    public string RefreshToken { get; private set; } = "";

    [GeneratedRegex("class=\"number\">([0-9]{2})<", RegexOptions.CultureInvariant)]
    private static partial Regex NumberPattern();

    [GeneratedRegex("data-handle=\"([0-9a-f]{64})\"", RegexOptions.CultureInvariant)]
    private static partial Regex HandlePattern();

    public static string Verifier => "verifier-" + new string('v', 50);

    public static string Challenge => System.Buffers.Text.Base64Url.EncodeToString(SHA256.HashData(Encoding.ASCII.GetBytes(Verifier)));

    public async Task<string> Register(string redirect = Redirect)
    {
        using var anonymous = factory.CreateClient();
        var response = await anonymous.PostAsJsonAsync("/oauth/register", new
        {
            client_name = "Test Agent",
            redirect_uris = new[] { redirect, "cursor://anysphere.cursor-mcp/oauth/callback" },
            token_endpoint_auth_method = "none"
        });
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        ClientId = body.GetProperty("client_id").GetString()!;
        return ClientId;
    }

    // Opens the authorization page as the client's browser would; returns the number shown and the page's handle.
    public async Task<(int Number, string Handle)> OpenAuthorizationPage(string? resource = Resource, string? address = null)
    {
        using var browser = factory.CreateClient(new()
        {
            AllowAutoRedirect = false
        });
        if (address is not null)
        {
            browser.DefaultRequestHeaders.Add(JournalFactory.ClientAddressHeader, address);
        }
        var url = "/oauth/authorize?response_type=code&client_id=" + ClientId + "&redirect_uri=" + Uri.EscapeDataString(Redirect) +
            "&code_challenge=" + Challenge + "&code_challenge_method=S256&state=xyz" + (resource is null ? "" : "&resource=" + Uri.EscapeDataString(resource));
        var page = await browser.GetStringAsync(url);
        return (int.Parse(NumberPattern().Match(page).Groups[1].Value, System.Globalization.CultureInfo.InvariantCulture), HandlePattern().Match(page).Groups[1].Value);
    }

    // The owner's device: finds the waiting request (the newest), opens it, approves it with the number the page
    // shows and a new copy key, uploads the copy and releases the code. Returns the request's ID.
    public async Task<Guid> Approve(int number, DateTimeOffset? expiresAt = null)
    {
        var id = (await WaitingRequests())[0].Id;
        (await device.GetAsync($"/v1/agent-requests/{id}")).EnsureSuccessStatusCode();
        GrantId = Guid.NewGuid();
        (await SendApproval(id, number, expiresAt)).EnsureSuccessStatusCode();
        var items = new[]
        {
            Seal(new { kind = "journal", id = SharedJournal, name = "Work" }, SharedJournal, 5),
            Seal(new { kind = "entry", id = SharedEntry, journalId = SharedJournal, title = "Planning", date = "2026-09-20T12:00:00Z", text = "The plan for the café launch." }, SharedEntry, 5),
            // An entry whose journal isn't in the copy is never shown.
            Seal(new { kind = "entry", id = PrivateEntry, journalId = PrivateJournal, title = "Secret", date = "2026-09-21T12:00:00Z", text = "Never shared" }, PrivateEntry, 5),
        };
        (await device.PostAsJsonAsync($"/v1/agents/{GrantId}/items", new UploadItemsRequest(items, true, 1))).EnsureSuccessStatusCode();
        (await device.PostAsJsonAsync($"/v1/agent-requests/{id}/ready", new AgentReady(true))).EnsureSuccessStatusCode();
        return id;
    }

    public async Task<IReadOnlyList<AgentRequestSummary>> WaitingRequests() =>
        (await device.GetFromJsonAsync<List<AgentRequestSummary>>("/v1/agent-requests/"))!;

    // An approval with a fresh copy key wrap for GrantId.
    public async Task<HttpResponseMessage> SendApproval(Guid requestId, int number, DateTimeOffset? expiresAt = null)
    {
        if (GrantId == Guid.Empty)
        {
            GrantId = Guid.NewGuid();
        }
        var secret = RandomNumberGenerator.GetBytes(32);
        var wrapped = AgentKeys.Wrap(CopyKey, secret, GrantId);
        var approval = new AgentApproval(number, GrantId, Convert.ToBase64String(wrapped), Convert.ToBase64String(secret), Convert.ToBase64String(new byte[48]), expiresAt);
        return await device.PostAsJsonAsync($"/v1/agent-requests/{requestId}/approve", approval);
    }

    // The item ID of a record in this flow's copy.
    public string ItemId(Guid recordId)
    {
        var identity = HKDF.DeriveKey(HashAlgorithmName.SHA256, CopyKey, 32, [], "journal:v1:agent-copy:item-id"u8.ToArray());
        return Convert.ToHexStringLower(HMACSHA256.HashData(identity, Encoding.UTF8.GetBytes("journal:v1:agent-item:" + recordId.ToString("D")))[..16]);
    }

    // The page's poller: where the browser is sent once the owner answered.
    public async Task<Uri> Callback(string handle)
    {
        using var browser = factory.CreateClient();
        var status = await browser.GetFromJsonAsync<JsonElement>("/oauth/authorize/status?handle=" + handle);
        return new Uri(status.GetProperty("redirect").GetString()!);
    }

    public async Task<HttpResponseMessage> Exchange(string code, string verifier, string? resource = Resource)
    {
        using var client = factory.CreateClient();
        var form = new Dictionary<string, string> { ["grant_type"] = "authorization_code", ["code"] = code, ["redirect_uri"] = Redirect, ["client_id"] = ClientId, ["code_verifier"] = verifier };
        if (resource is not null)
        {
            form["resource"] = resource;
        }
        return await client.PostAsync("/oauth/token", new FormUrlEncodedContent(form));
    }

    public async Task<HttpResponseMessage> RefreshWith(string refreshToken)
    {
        using var client = factory.CreateClient();
        return await client.PostAsync("/oauth/token", new FormUrlEncodedContent(new Dictionary<string, string> { ["grant_type"] = "refresh_token", ["refresh_token"] = refreshToken, ["client_id"] = ClientId }));
    }

    public void Keep(JsonElement tokens)
    {
        AccessToken = tokens.GetProperty("access_token").GetString()!;
        RefreshToken = tokens.GetProperty("refresh_token").GetString()!;
    }

    // Everything from registration to tokens.
    public async Task Connect(DateTimeOffset? expiresAt = null)
    {
        await Register();
        var (number, handle) = await OpenAuthorizationPage();
        await Approve(number, expiresAt);
        var callback = await Callback(handle);
        var query = Microsoft.AspNetCore.WebUtilities.QueryHelpers.ParseQuery(callback.Query);
        var response = await Exchange(query["code"].ToString(), Verifier);
        response.EnsureSuccessStatusCode();
        Keep(await response.Content.ReadFromJsonAsync<JsonElement>());
    }

    // A modern (2026-07-28) MCP request with the headers the transport requires.
    public async Task<HttpResponseMessage> Mcp(string method, JsonObject? parameters = null, string? token = null, int id = 1, Action<HttpRequestMessage>? adjust = null)
    {
        parameters ??= [];
        parameters["_meta"] = new JsonObject { ["io.modelcontextprotocol/protocolVersion"] = "2026-07-28", ["io.modelcontextprotocol/clientCapabilities"] = new JsonObject() };
        var body = new JsonObject { ["jsonrpc"] = "2.0", ["id"] = id, ["method"] = method, ["params"] = parameters };
        using var request = new HttpRequestMessage(HttpMethod.Post, "/mcp") { Content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json") };
        request.Headers.Accept.ParseAdd("application/json, text/event-stream");
        request.Headers.Add("MCP-Protocol-Version", "2026-07-28");
        request.Headers.Add("Mcp-Method", method);
        if (method == "tools/call")
        {
            request.Headers.Add("Mcp-Name", (string)parameters["name"]!);
        }
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token ?? AccessToken);
        adjust?.Invoke(request);
        using var client = factory.CreateClient();
        return await client.SendAsync(request);
    }

    public async Task<JsonObject> CallTool(string name, JsonObject? arguments = null)
    {
        var response = await Mcp("tools/call", new JsonObject { ["name"] = name, ["arguments"] = arguments ?? [] });
        response.EnsureSuccessStatusCode();
        return (JsonNode.Parse(await response.Content.ReadAsStringAsync())!["result"] as JsonObject)!;
    }

    // Adds an item to the copy, as a device would publish it.
    public async Task Upload(object item, Guid recordId, long version, long revision = 1) =>
        (await device.PostAsJsonAsync($"/v1/agents/{GrantId}/items", new UploadItemsRequest([Seal(item, recordId, version)], null, revision))).EnsureSuccessStatusCode();

    private UploadItem Seal(object item, Guid recordId, long version)
    {
        var encryption = HKDF.DeriveKey(HashAlgorithmName.SHA256, CopyKey, 32, [], "journal:v1:agent-copy:encryption"u8.ToArray());
        var identity = HKDF.DeriveKey(HashAlgorithmName.SHA256, CopyKey, 32, [], "journal:v1:agent-copy:item-id"u8.ToArray());
        var itemId = ItemId(recordId);
        var plaintext = JsonSerializer.SerializeToUtf8Bytes(item);
        var combined = new byte[12 + plaintext.Length + 16];
        RandomNumberGenerator.Fill(combined.AsSpan(0, 12));
        using var aes = new AesGcm(encryption, 16);
        aes.Encrypt(combined.AsSpan(0, 12), plaintext, combined.AsSpan(12, plaintext.Length), combined.AsSpan(12 + plaintext.Length), Encoding.UTF8.GetBytes("journal:v1:agent-copy:" + GrantId.ToString("D") + ":" + itemId));
        var digest = Convert.ToHexStringLower(HMACSHA256.HashData(identity, (byte[])[.. "journal:v1:agent-digest:"u8, .. plaintext])[..16]);
        return new UploadItem(itemId, version, digest, Convert.ToBase64String(combined));
    }
}
