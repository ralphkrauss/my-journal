using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Sockets;
using System.Text.Json;
using Journal.Api.Data;
using Microsoft.EntityFrameworkCore;

namespace Journal.Api.Security;

// An MCP client as the authorization server knows it: from dynamic client registration, or from its client ID
// metadata document (protocol/agent-access-server.md, Clients).
public sealed record OAuthClientInfo(string ClientId, string Name, IReadOnlyList<string> RedirectUris, bool FromMetadataDocument, string AuthMethod = "none", string? SecretHash = null)
{
    // The host a metadata-document client proved control of, shown during approval.
    public string? IdentifiedAs => FromMetadataDocument && Uri.TryCreate(ClientId, UriKind.Absolute, out var uri) ? OAuthRedirects.ShownHost(uri) : null;

    // RFC 8252: loopback redirects match ignoring the port; everything else matches exactly.
    public bool Allows(string redirectUri) => RedirectUris.Any(registered =>
        string.Equals(registered, redirectUri, StringComparison.Ordinal) || SameLoopbackRedirect(registered, redirectUri));

    private static bool SameLoopbackRedirect(string registered, string requested) =>
        OAuthRedirects.IsLoopback(registered) && OAuthRedirects.IsLoopback(requested) &&
        Uri.TryCreate(registered, UriKind.Absolute, out var a) && Uri.TryCreate(requested, UriKind.Absolute, out var b) &&
        string.Equals(a.Host, b.Host, StringComparison.OrdinalIgnoreCase) && a.PathAndQuery == b.PathAndQuery;
}

public static class OAuthRedirects
{
    public enum Kind
    {
        Https,
        Loopback,
    }

    // MCP allows only https and loopback http redirect URIs; never a fragment, and never user information, which
    // makes an address such as https://trusted.example@other.example/ look as if it led somewhere it doesn't.
    public static Kind? Classify(string? value)
    {
        if (value is null || value.Length > 2000 || !Uri.TryCreate(value, UriKind.Absolute, out var uri) || uri.Fragment.Length > 0 ||
            value.Contains('#', StringComparison.Ordinal) || uri.UserInfo.Length > 0)
        {
            return null;
        }
        if (uri.Scheme == "https" && uri.Host.Length > 0)
        {
            return Kind.Https;
        }
        return IsLoopback(value) ? Kind.Loopback : null;
    }

    public static bool IsLoopback(string value) =>
        Uri.TryCreate(value, UriKind.Absolute, out var uri) && uri.Scheme == "http" &&
        (uri.Host is "127.0.0.1" or "[::1]" or "::1" || string.Equals(uri.Host, "localhost", StringComparison.OrdinalIgnoreCase));

    // What the approval shows as the redirect's destination.
    public static string Describe(string value) => Uri.TryCreate(value, UriKind.Absolute, out var uri) ? ShownHost(uri) : "";

    // A host as the owner sees it: an internationalized name in its ASCII (punycode) form, so a look-alike such as
    // "аpple.com" with a Cyrillic "а" reads "xn--pple-43d.com" instead of passing for another site.
    public static string ShownHost(Uri uri)
    {
        ArgumentNullException.ThrowIfNull(uri);
        return uri.Host.All(char.IsAscii) ? uri.Host : uri.IdnHost;
    }
}

// Finds clients: registered ones in the database, metadata-document ones fetched over HTTPS with SSRF protections.
public sealed class OAuthClients(IHttpClientFactory http, TimeProvider clock, IConfiguration configuration, AuditLog audit)
{
    // Why a metadata-document client couldn't be used.
    public enum Problem
    {
        None,
        Unreachable,
        Invalid,
        UnsupportedAuthentication,
    }
    private int warnedUnreachable;
    public const string HttpClientName = "client-metadata";
    public const int MaximumDocumentBytes = 16 * 1024;
    private static readonly TimeSpan LongestCache = TimeSpan.FromHours(24);
    private static readonly TimeSpan FailureCache = TimeSpan.FromMinutes(5);
    // A connection failure may be the network, which recovers; trying again soon should work.
    private static readonly TimeSpan UnreachableCache = TimeSpan.FromSeconds(30);
    private readonly ConcurrentDictionary<string, (OAuthClientInfo? Client, DateTimeOffset Until, Problem Problem)> documents = new(StringComparer.Ordinal);

    public bool MetadataDocumentsEnabled => configuration.GetValue("Journal:ClientMetadataDocuments", true);

    // Why a metadata-document client couldn't be used, for the authorization page.
    public Problem ProblemWith(string clientId) =>
        documents.TryGetValue(clientId, out var cached) ? cached.Problem : Problem.Invalid;

    public async Task<OAuthClientInfo?> Find(string? clientId, JournalDb db, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(db);
        if (clientId is null || clientId.Length is 0 or > 2000)
        {
            return null;
        }
        if (clientId.StartsWith("https://", StringComparison.Ordinal))
        {
            return MetadataDocumentsEnabled ? await Document(clientId, ct) : null;
        }
        var registered = await db.OAuthClients.AsNoTracking().SingleOrDefaultAsync(x => x.Id == clientId, ct);
        return registered is null ? null : new OAuthClientInfo(registered.Id, registered.Name, JsonSerializer.Deserialize<string[]>(registered.RedirectUris) ?? [], false, registered.AuthMethod, registered.SecretHash);
    }

    private async Task<OAuthClientInfo?> Document(string clientId, CancellationToken ct)
    {
        var now = clock.GetUtcNow();
        if (documents.TryGetValue(clientId, out var cached) && cached.Until > now)
        {
            return cached.Client;
        }
        var (client, lifetime, problem) = await Fetch(clientId, ct);
        if (documents.Count > 1000)
        {
            documents.Clear();
        }
        documents[clientId] = (client, now + (client is not null ? lifetime : problem == Problem.Unreachable ? UnreachableCache : FailureCache), problem);
        return client;
    }

    private sealed class UnsupportedClientAuthentication : Exception;

    // The metadata document's host resolves only to addresses this server doesn't fetch from.
    private sealed class BlockedAddress : IOException;

    private async Task<(OAuthClientInfo? Client, TimeSpan Lifetime, Problem Problem)> Fetch(string clientId, CancellationToken ct)
    {
        if (!Uri.TryCreate(clientId, UriKind.Absolute, out var uri) || uri.Scheme != "https" || !uri.IsDefaultPort ||
            uri.AbsolutePath.Length <= 1 || uri.Fragment.Length > 0 || uri.UserInfo.Length > 0)
        {
            return (null, FailureCache, Problem.Invalid);
        }
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeout.CancelAfter(TimeSpan.FromSeconds(5));
            using var request = new HttpRequestMessage(HttpMethod.Get, uri);
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            using var response = await http.CreateClient(HttpClientName).SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token);
            if (response.StatusCode != HttpStatusCode.OK || response.Content.Headers.ContentLength > MaximumDocumentBytes)
            {
                return (null, FailureCache, Problem.Invalid);
            }
            var body = await ReadLimited(response, timeout.Token);
            var client = Parse(clientId, body);
            var age = response.Headers.CacheControl?.MaxAge ?? TimeSpan.FromHours(1);
            return (client, age < LongestCache ? age : LongestCache, client is null ? Problem.Invalid : Problem.None);
        }
        catch (UnsupportedClientAuthentication)
        {
            return (null, FailureCache, Problem.UnsupportedAuthentication);
        }
        catch (HttpRequestException error) when (error.InnerException is BlockedAddress || error.GetBaseException() is BlockedAddress)
        {
            return (null, FailureCache, Problem.Invalid);
        }
        catch (HttpRequestException error) when (error.HttpRequestError is HttpRequestError.NameResolutionError or HttpRequestError.ConnectionError && !ct.IsCancellationRequested)
        {
            // Said once: a server without internet access should stop advertising metadata documents.
            if (Interlocked.Exchange(ref warnedUnreachable, 1) == 0)
            {
                audit.ClientMetadataUnreachable();
            }
            return (null, FailureCache, Problem.Unreachable);
        }
        catch (Exception error) when (error is HttpRequestException or OperationCanceledException or IOException or JsonException or InvalidDataException)
        {
            if (ct.IsCancellationRequested)
            {
                throw;
            }
            // A connect timeout counts as unreachable.
            return (null, FailureCache, error is OperationCanceledException ? Problem.Unreachable : Problem.Invalid);
        }
    }

    private static async Task<byte[]> ReadLimited(HttpResponseMessage response, CancellationToken ct)
    {
        await using var stream = await response.Content.ReadAsStreamAsync(ct);
        var buffer = new byte[MaximumDocumentBytes + 1];
        var total = 0;
        int read;
        while ((read = await stream.ReadAsync(buffer.AsMemory(total), ct)) > 0)
        {
            total += read;
            if (total > MaximumDocumentBytes)
            {
                throw new InvalidDataException("The client metadata document is too large.");
            }
        }
        return buffer[..total];
    }

    // Validates a metadata document: its client_id is exactly the URL it came from; it names the client and its
    // redirect URIs; it's a public client.
    internal static OAuthClientInfo? Parse(string clientId, byte[] body)
    {
        using var document = JsonDocument.Parse(body);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object ||
            !root.TryGetProperty("client_id", out var id) || id.ValueKind != JsonValueKind.String || id.GetString() != clientId ||
            !root.TryGetProperty("client_name", out var name) || name.ValueKind != JsonValueKind.String || name.GetString() is not { Length: > 0 and <= 100 } clientName ||
            !root.TryGetProperty("redirect_uris", out var redirects) || redirects.ValueKind != JsonValueKind.Array)
        {
            return null;
        }
        if (root.TryGetProperty("token_endpoint_auth_method", out var method) && method.GetString() != "none")
        {
            throw new UnsupportedClientAuthentication();
        }
        var uris = redirects.EnumerateArray().Select(x => x.ValueKind == JsonValueKind.String ? x.GetString() : null).ToList();
        if (uris.Count is 0 or > 10 || uris.Any(x => OAuthRedirects.Classify(x) is null))
        {
            return null;
        }
        return new OAuthClientInfo(clientId, clientName, uris!, true);
    }

    // Connects only to public addresses, checking the address actually connected to, so a name that resolves
    // differently at connection time (DNS rebinding) can't reach this network. No redirects are followed.
    public static SocketsHttpHandler Handler() => new()
    {
        AllowAutoRedirect = false,
        UseProxy = false,
        UseCookies = false,
        ConnectTimeout = TimeSpan.FromSeconds(5),
        ConnectCallback = async (context, ct) =>
        {
            var addresses = await Dns.GetHostAddressesAsync(context.DnsEndPoint.Host, ct);
            var address = addresses.FirstOrDefault(IsPublic) ?? throw new BlockedAddress();
            var socket = new Socket(address.AddressFamily, SocketType.Stream, ProtocolType.Tcp) { NoDelay = true };
            try
            {
                await socket.ConnectAsync(new IPEndPoint(address, context.DnsEndPoint.Port), ct);
                if (socket.RemoteEndPoint is not IPEndPoint connected || !IsPublic(connected.Address))
                {
                    throw new BlockedAddress();
                }
                return new NetworkStream(socket, ownsSocket: true);
            }
            catch
            {
                socket.Dispose();
                throw;
            }
        },
    };

    // Excludes loopback, private, link-local, shared (CGNAT, including Tailscale), multicast, reserved and unspecified
    // addresses, also in IPv4-mapped form.
    internal static bool IsPublic(IPAddress address)
    {
        if (address.IsIPv4MappedToIPv6)
        {
            address = address.MapToIPv4();
        }
        if (IPAddress.IsLoopback(address) || address.Equals(IPAddress.Any) || address.Equals(IPAddress.IPv6Any) || address.Equals(IPAddress.IPv6None))
        {
            return false;
        }
        if (address.AddressFamily == AddressFamily.InterNetwork)
        {
            var b = address.GetAddressBytes();
            return !(b[0] == 0 || b[0] == 10 || b[0] == 127 || b[0] >= 224 ||
                (b[0] == 100 && b[1] >= 64 && b[1] <= 127) || (b[0] == 169 && b[1] == 254) ||
                (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168) ||
                (b[0] == 192 && b[1] == 0 && b[2] is 0 or 2) || (b[0] == 198 && b[1] is 18 or 19) ||
                (b[0] == 198 && b[1] == 51 && b[2] == 100) || (b[0] == 203 && b[1] == 0 && b[2] == 113));
        }
        if (address.AddressFamily != AddressFamily.InterNetworkV6)
        {
            return false;
        }
        var v6 = address.GetAddressBytes();
        return !(address.IsIPv6LinkLocal || address.IsIPv6SiteLocal || address.IsIPv6Multicast || address.IsIPv6UniqueLocal ||
            (v6[0] == 0x20 && v6[1] == 0x01 && v6[2] == 0x0d && v6[3] == 0xb8) || (v6[0] == 0x00 && v6[1] == 0x64 && v6[2] == 0xff && v6[3] == 0x9b));
    }
}
