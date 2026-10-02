using System.Security.Claims;
using System.Text.Encodings.Web;
using Journal.Api.Data;
using Microsoft.AspNetCore.Authentication;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Journal.Api.Security;

// Device bearer credentials. Authentication runs as middleware before rate limiting, and authorization
// rejects a missing or invalid credential before an endpoint binds (reads) its request body.
public sealed class DeviceAuthentication(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, JournalDb db)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, UrlEncoder.Default)
{
    public const string SchemeName = "Device";
    private const string DeviceClaim = "device";
    private static readonly object DeviceKey = new();

    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var header = Request.Headers.Authorization.ToString();
        if (header.Length == 0)
        {
            return AuthenticateResult.NoResult();
        }
        if (!header.StartsWith("Bearer ", StringComparison.Ordinal) || header.Length > 200)
        {
            return AuthenticateResult.Fail("Unsupported credential.");
        }

        var hash = Secrets.Hash(header[7..]);
        var device = await db.Devices.AsNoTracking().SingleOrDefaultAsync(x => x.TokenHash == hash && !x.Revoked, Context.RequestAborted);
        if (device is null)
        {
            return AuthenticateResult.Fail("Unknown or revoked device credential.");
        }

        Context.Items[DeviceKey] = device;
        var identity = new ClaimsIdentity([new Claim(DeviceClaim, device.Id.ToString("D"))], SchemeName);
        return AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(identity), SchemeName));
    }

    // The status-code-pages middleware adds the problem details body.
    protected override Task HandleChallengeAsync(AuthenticationProperties properties)
    {
        Response.Headers.WWWAuthenticate = "Bearer";
        return base.HandleChallengeAsync(properties);
    }

    // The authenticated device's ID, for rate-limit partitions; null for anonymous requests.
    public static string? DeviceId(HttpContext http)
    {
        ArgumentNullException.ThrowIfNull(http);
        return http.User.FindFirst(DeviceClaim)?.Value;
    }

    public static Device Current(HttpContext http)
    {
        ArgumentNullException.ThrowIfNull(http);
        return http.Items[DeviceKey] as Device ?? throw new InvalidOperationException("The endpoint requires device authorization.");
    }

    // Call while holding WriteGate: initial authentication may predate a queued write or upload.
    internal static Task<bool> IsStillAuthorized(HttpContext http, JournalDb db)
    {
        if (http.Items[DeviceKey] is not Device device)
        {
            return Task.FromResult(false);
        }
        return db.Devices.AsNoTracking().AnyAsync(
            current => current.Id == device.Id && current.TokenHash == device.TokenHash && !current.Revoked,
            http.RequestAborted);
    }
}
