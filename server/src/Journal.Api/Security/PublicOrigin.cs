using System.Globalization;
using System.Net;

namespace Journal.Api.Security;

// The origin clients reach this server at, which names its MCP resource and OAuth issuer
// (protocol/agent-access-server.md, Endpoints and identifiers): the configured public URL, or the request's host with
// HTTPS when TLS ended here, at a trusted proxy or at Tailscale Serve, and HTTP only for loopback hosts. A request's
// Host header is trusted only when the server listens on loopback or its host names are configured.
public static class PublicOrigin
{
    public const string SettingKey = "Journal:PublicUrl";
    public const string McpPath = "/mcp";
    public const string HttpsRequired = "https-required";
    public const string PublicUrlRequired = "public-url-required";

    public readonly record struct Result(string? Origin, string? Unavailable)
    {
        public string? McpResource => Origin is null ? null : Origin + McpPath;
    }

    public static Result Of(HttpContext http)
    {
        ArgumentNullException.ThrowIfNull(http);
        var configuration = http.RequestServices.GetRequiredService<IConfiguration>();
        if (ConfiguredOrigin(configuration) is { } origin)
        {
            return new Result(origin, null);
        }
        var host = http.Request.Host;
        if (!host.HasValue)
        {
            return new Result(null, PublicUrlRequired);
        }
        var name = host.Host.ToLowerInvariant();
        var loopbackHost = name is "localhost" or "127.0.0.1" or "[::1]";
        var local = http.Connection.LocalIpAddress;
        var loopbackListener = local is null || IPAddress.IsLoopback(local);
        var hostsConfigured = configuration["AllowedHosts"] is { Length: > 0 } hosts && hosts.Trim() != "*";
        if (!loopbackListener && !hostsConfigured)
        {
            return new Result(null, PublicUrlRequired);
        }
        var loopbackConnection = OriginalRemoteAddress(http) is { } remote && IPAddress.IsLoopback(remote);
        var https = http.Request.IsHttps || (loopbackConnection && name.EndsWith(".ts.net", StringComparison.Ordinal));
        if (!https && !loopbackHost)
        {
            return new Result(null, HttpsRequired);
        }
        var scheme = https ? "https" : "http";
        var port = host.Port is { } value && value != (https ? 443 : 80) ? ":" + value.ToString(CultureInfo.InvariantCulture) : "";
        return new Result(scheme + "://" + name + port, null);
    }

    // The configured public address: Journal:PublicUrl, else JOURNAL_URL (which the deployments pass for the setup
    // code) when it is a usable origin. Journal:PublicUrl is validated at startup by Validate.
    public static string? ConfiguredOrigin(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        if (configuration[SettingKey] is { Length: > 0 } explicitValue)
        {
            return Origin(explicitValue);
        }
        return configuration["JOURNAL_URL"] is { Length: > 0 } devices ? Origin(devices) : null;
    }

    // An existing deployment's JOURNAL_URL that agents can't use (for example an http:// LAN address), so startup can
    // say why agents get an address derived per request instead.
    public static bool UnusableJournalUrl(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        return configuration[SettingKey] is not { Length: > 0 } && configuration["JOURNAL_URL"] is { Length: > 0 } value && Origin(value) is null;
    }

    // Throws when Journal:PublicUrl isn't an origin: https://host[:port], or http:// with a loopback host. A path would
    // move the well-known metadata documents (RFC 8414, RFC 9728). JOURNAL_URL, which older deployments may have set
    // to anything for the setup code's display, is used only when it is such an origin.
    public static void Validate(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        var value = configuration[SettingKey];
        if (!string.IsNullOrWhiteSpace(value) && Origin(value) is null)
        {
            throw new FormatException($"{SettingKey} must be the server's address without a path, such as https://journal.example.ts.net.");
        }
    }

    private static string? Origin(string value)
    {
        if (!Uri.TryCreate(value.Trim().TrimEnd('/'), UriKind.Absolute, out var uri) || uri.Host.Length == 0 ||
            uri.AbsolutePath != "/" || uri.Query.Length > 0 || uri.Fragment.Length > 0 || uri.UserInfo.Length > 0 ||
            !(uri.Scheme == "https" || (uri.Scheme == "http" && (uri.IsLoopback || uri.Host == "localhost"))))
        {
            return null;
        }
        return uri.GetLeftPart(UriPartial.Authority).ToLowerInvariant();
    }

    // With a configured public address, MCP and OAuth requests must come for its host.
    public static bool RequestHostMatches(HttpContext http)
    {
        ArgumentNullException.ThrowIfNull(http);
        var configured = ConfiguredOrigin(http.RequestServices.GetRequiredService<IConfiguration>());
        if (configured is null)
        {
            return true;
        }
        var expected = new Uri(configured);
        var port = http.Request.Host.Port ?? (http.Request.IsHttps || expected.Scheme == "https" ? 443 : 80);
        return string.Equals(http.Request.Host.Host, expected.Host, StringComparison.OrdinalIgnoreCase) && port == expected.Port;
    }

    // The address the connection came from, before a trusted proxy's X-Forwarded-For replaced it (the forwarded
    // headers middleware keeps the original in X-Original-For): Tailscale Serve connects over loopback.
    private static IPAddress? OriginalRemoteAddress(HttpContext http)
    {
        var original = http.Request.Headers["X-Original-For"].ToString();
        if (original.Length > 0)
        {
            var value = original.Split(',')[0].Trim();
            if (IPEndPoint.TryParse(value, out var endpoint))
            {
                return endpoint.Address;
            }
            return IPAddress.TryParse(value.Trim('[', ']'), out var address) ? address : null;
        }
        return http.Connection.RemoteIpAddress;
    }

    // Compares a client-supplied resource with this server's, ignoring the case of scheme and host (RFC 3986 §6.2.2.1)
    // and a trailing slash.
    public static bool SameResource(string? candidate, string resource)
    {
        if (!Uri.TryCreate(candidate, UriKind.Absolute, out var uri) || uri.Fragment.Length > 0 || uri.Query.Length > 0)
        {
            return false;
        }
        var normalized = uri.GetLeftPart(UriPartial.Authority).ToLowerInvariant() + uri.AbsolutePath.TrimEnd('/');
        return string.Equals(normalized, resource, StringComparison.Ordinal);
    }
}
