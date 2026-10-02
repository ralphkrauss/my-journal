using System.Globalization;
using System.Net;
using System.Net.Sockets;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.RateLimiting;

namespace Journal.Api.Security;

// Authenticated requests are partitioned by device, so anonymous traffic can never exhaust the limits
// used by the owner's devices. Anonymous requests (and requests with an invalid credential) are
// partitioned by client address. Behind a reverse proxy that address is the proxy's own unless the
// proxy is listed in Journal:TrustedProxies (see NetworkPolicy); only then is X-Forwarded-For used.
public static class RateLimits
{
    public const string Anonymous = "anonymous";
    public const string RecoveryEnvelope = "recovery-envelope";
    public const string PairingStart = "pairing-start";
    public const string PairingRequest = "pairing-request";
    public const string Device = "device";
    public const string DeviceLookup = "device-lookup";
    public const string Password = "password";
    public const string Sync = "sync";
    public const string SyncWait = "sync-wait";
    public const string OAuthMetadata = "oauth-metadata";
    public const string OAuthRegister = "oauth-register";
    public const string OAuthAuthorize = "oauth-authorize";
    public const string OAuthStatus = "oauth-status";
    public const string OAuthToken = "oauth-token";

    public static void Configure(RateLimiterOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);
        options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
        options.OnRejected = (context, _) =>
        {
            if (context.Lease.TryGetMetadata(MetadataName.RetryAfter, out var retryAfter))
            {
                context.HttpContext.Response.Headers.RetryAfter = Math.Ceiling(retryAfter.TotalSeconds).ToString(CultureInfo.InvariantCulture);
            }
            return ValueTask.CompletedTask;
        };
        // Setup and recovery accept guessable credentials.
        options.AddPolicy(Anonymous, context => Window(ClientAddress(context), 30));
        // Separate from recovery attempts, so guessing cannot block a device fetching the envelope.
        options.AddPolicy(RecoveryEnvelope, context => DeviceOrAddress(context, 60));
        options.AddPolicy(PairingStart, context => Window(ClientAddress(context), 10));
        // Poll, reveal and cancel require the request's secret poll token. The route ID is chosen by the
        // caller, so the limit follows the client address; it covers a few concurrent pairings.
        options.AddPolicy(PairingRequest, context => Window(ClientAddress(context), 240));
        options.AddPolicy(Device, context => DeviceOrAddress(context, 300));
        options.AddPolicy(DeviceLookup, context => DeviceOrAddress(context, 30));
        options.AddPolicy(Password, context => DeviceOrAddress(context, 10));
        // A client syncs sequentially, however fast, so it never waits here. Concurrent requests beyond
        // this bound (a runaway or stolen credential) queue briefly and are then refused.
        // Agent access (protocol/agent-access-server.md, Limits): the MCP endpoint limits per grant itself.
        options.AddPolicy(OAuthMetadata, context => Window("oauth-metadata:" + ClientAddress(context), 120));
        options.AddPolicy(OAuthRegister, context => RateLimitPartition.GetFixedWindowLimiter("oauth-register:" + ClientAddress(context), _ => new FixedWindowRateLimiterOptions { PermitLimit = 10, Window = TimeSpan.FromHours(1), QueueLimit = 0 }));
        options.AddPolicy(OAuthAuthorize, context => Window("oauth-authorize:" + ClientAddress(context), 30));
        // The waiting page polls with its own handle, so its polling never uses up the authorization limit. A handle the
        // server doesn't know counts against the caller's address, so made-up handles can't open unlimited partitions.
        options.AddPolicy(OAuthStatus, context =>
        {
            var handle = context.Request.Query["handle"].ToString();
            return context.RequestServices.GetRequiredService<AgentAuthorizations>().ByHandle(handle) is not null
                ? Window("oauth-status:" + handle, 60)
                : Window("oauth-status-unknown:" + ClientAddress(context), 60);
        });
        options.AddPolicy(OAuthToken, context => Window("oauth-token:" + ClientAddress(context), 60));
        // A client waits for changes at most once every 3 s. The limiter runs before authorization, so requests
        // without a valid credential count against their address.
        options.AddPolicy(SyncWait, context => Window(DeviceAuthentication.DeviceId(context) is { } device ? "sync-wait:" + device : "sync-wait-address:" + ClientAddress(context), 60));
        options.AddPolicy(Sync, context => DeviceAuthentication.DeviceId(context) is { } device
            ? RateLimitPartition.GetConcurrencyLimiter("device:" + device, _ => new ConcurrencyLimiterOptions { PermitLimit = 8, QueueLimit = 32, QueueProcessingOrder = QueueProcessingOrder.OldestFirst })
            : Window(ClientAddress(context), 60));
    }

    private static RateLimitPartition<string> Window(string key, int permits) =>
        RateLimitPartition.GetFixedWindowLimiter(key, _ => new FixedWindowRateLimiterOptions { PermitLimit = permits, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 });

    private static RateLimitPartition<string> DeviceOrAddress(HttpContext context, int permits) =>
        Window(DeviceAuthentication.DeviceId(context) is { } device ? "device:" + device : ClientAddress(context), permits);

    // IPv6 clients commonly control a whole /64, so it forms one partition.
    internal static string ClientAddress(HttpContext context)
    {
        var address = context.Connection.RemoteIpAddress;
        if (address is null)
        {
            return "address:unknown";
        }
        if (address.IsIPv4MappedToIPv6)
        {
            address = address.MapToIPv4();
        }
        if (address.AddressFamily != AddressFamily.InterNetworkV6)
        {
            return "address:" + address;
        }
        var bytes = address.GetAddressBytes();
        Array.Clear(bytes, 8, 8);
        return "address:" + new IPAddress(bytes) + "/64";
    }
}
