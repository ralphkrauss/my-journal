using System.Net;
using Microsoft.AspNetCore.HostFiltering;
using Microsoft.AspNetCore.HttpOverrides;

namespace Journal.Api.Security;

// Host-name filtering and trusted reverse proxies. Both default to the safe choice and are changed only
// through configuration (appsettings, environment variables or command-line options).
public static class NetworkPolicy
{
    public const string TrustedProxiesKey = "Journal:TrustedProxies";
    // Tailscale Serve forwards its *.ts.net name, which only Tailscale can point at an address.
    private static readonly string[] LoopbackHosts = ["localhost", "127.0.0.1", "[::1]", "*.ts.net"];
    private static readonly string[] AnyHost = ["*"];

    // Unless AllowedHosts is configured, a server that listens only on loopback accepts only loopback
    // host names (and Tailscale Serve's): another name reaching it most likely comes from a local
    // browser page using DNS rebinding. A reverse proxy that forwards its own host name needs that name
    // in AllowedHosts. A server listening on other interfaces (containers) accepts any host name.
    public static void ConfigureHostFiltering(WebApplicationBuilder builder)
    {
        ArgumentNullException.ThrowIfNull(builder);
        if (!string.IsNullOrWhiteSpace(builder.Configuration["AllowedHosts"]))
        {
            return;
        }
        var hosts = DefaultAllowedHosts(builder.Configuration);
        builder.Services.Configure<HostFilteringOptions>(options => options.AllowedHosts = [.. hosts]);
    }

    internal static string[] DefaultAllowedHosts(IConfiguration configuration)
    {
        var endpoints = configuration.GetSection("Kestrel:Endpoints").GetChildren().Select(endpoint => endpoint["Url"] ?? "").ToArray();
        var urls = endpoints.Length > 0 ? endpoints : (configuration["urls"] ?? "").Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (urls.Length == 0)
        {
            // Without addresses Kestrel listens on http://localhost:5000, unless ports are configured.
            var ports = !string.IsNullOrWhiteSpace(configuration["http_ports"]) || !string.IsNullOrWhiteSpace(configuration["https_ports"]);
            return ports ? AnyHost : LoopbackHosts;
        }
        return urls.All(IsLoopback) ? LoopbackHosts : AnyHost;
    }

    private static bool IsLoopback(string url)
    {
        BindingAddress address;
        try
        {
            address = BindingAddress.Parse(url);
        }
        catch (FormatException)
        {
            return false;
        }
        if (address.IsNamedPipe || address.IsUnixPipe)
        {
            return false;
        }
        return address.Host == "localhost" || (IPAddress.TryParse(address.Host.Trim('[', ']'), out var ip) && IPAddress.IsLoopback(ip));
    }

    // X-Forwarded-For is honored only from the proxy addresses or CIDR networks listed (separated by ';'
    // or ',') in Journal:TrustedProxies, and only its last entry: the address that proxy saw. Returns
    // false when none are configured, which is the default. Throws FormatException for invalid entries.
    public static bool ConfigureForwardedHeaders(WebApplicationBuilder builder)
    {
        ArgumentNullException.ThrowIfNull(builder);
        var entries = (builder.Configuration[TrustedProxiesKey] ?? "").Split([';', ','], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (entries.Length == 0)
        {
            return false;
        }
        var proxies = new List<IPAddress>();
        var networks = new List<System.Net.IPNetwork>();
        foreach (var entry in entries)
        {
            if (entry.Contains('/', StringComparison.Ordinal) && System.Net.IPNetwork.TryParse(entry, out var network))
            {
                networks.Add(network);
            }
            else if (IPAddress.TryParse(entry, out var proxy))
            {
                proxies.Add(proxy);
            }
            else
            {
                throw new FormatException($"{TrustedProxiesKey} contains an entry that is not an IP address or CIDR network: {entry}");
            }
        }
        builder.Services.Configure<ForwardedHeadersOptions>(options =>
        {
            // The scheme too, so a trusted proxy that ends TLS makes the MCP and OAuth addresses https.
            options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
            options.ForwardLimit = 1;
            // Replace the framework's implicit loopback trust with exactly the configured entries.
            options.KnownProxies.Clear();
            options.KnownIPNetworks.Clear();
            proxies.ForEach(options.KnownProxies.Add);
            networks.ForEach(options.KnownIPNetworks.Add);
        });
        return true;
    }
}
