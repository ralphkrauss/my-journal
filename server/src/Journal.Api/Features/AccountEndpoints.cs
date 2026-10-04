using System.Globalization;
using System.Reflection;
using System.Text.Json.Serialization;
using Journal.Api.Data;
using Journal.Api.Security;
using Microsoft.EntityFrameworkCore;

namespace Journal.Api.Features;

public static class AccountEndpoints
{
    // Wire major versions this server implements; see protocol/README.md, Versioning.
    private static readonly int[] ProtocolVersions = [1];
    private static readonly int[] RecoveryVersions = [1, 2, 3, 4];
    // Additive protocol v1 capabilities; see protocol/README.md.
    private static readonly string[] Features = ["sync-identity", "pairing-check-code", "password-change", "sync-continuity", SyncEndpoints.ContinuityDigestFeature, "private-envelope", "pairing-invite", "setup-check", EncryptionEndpoints.Feature, "agent-access-2", SyncEndpoints.ShortReceiptFeature, SyncEndpoints.WaitFeature, SyncEndpoints.RecordKindsFeature];
    private static readonly string ServerVersion = (typeof(AccountEndpoints).Assembly
        .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "0.0.0").Split('+')[0];

    public static void MapAccounts(this WebApplication app)
    {
        // Static and database-free, so clients can check compatibility before anything else.
        app.MapGet("/v1/server", (HttpContext http) => Results.Ok(new
        {
            protocolVersions = ProtocolVersions,
            serverVersion = ServerVersion,
            features = Features,
            recoveryVersions = RecoveryVersions,
            mcpUrl = PublicOrigin.Of(http).McpResource,
            mcpUnavailable = PublicOrigin.Of(http).Unavailable
        }));
        app.MapGet("/v1/status", async (JournalDb db, HttpContext http, CancellationToken ct) =>
        {
            var vault = await db.Vaults.AsNoTracking().Select(vault => new { vault.SyncId }).SingleOrDefaultAsync(ct);
            var serverId = vault is { SyncId.Length: > 0 } ? vault.SyncId : null;
            return Results.Ok(new
            {
                protocolVersion = 1,
                recoveryVersions = RecoveryVersions,
                features = Features,
                initialized = vault is not null,
                serverId,
                mcpUrl = PublicOrigin.Of(http).McpResource,
                mcpUnavailable = PublicOrigin.Of(http).Unavailable
            });
        });
        app.MapPost("/v1/setup", Setup).RequireRateLimiting(RateLimits.Anonymous);
        app.MapPost("/v1/setup/check", CheckSetup).RequireRateLimiting(RateLimits.Anonymous);
        // Anyone may read what deriving the recovery secret needs, but not the wrapped vault key: guessing the
        // password offline would otherwise need nothing more (capability private-envelope).
        app.MapGet("/v1/recovery", async (JournalDb db, CancellationToken ct) =>
        {
            var vault = await db.Vaults.AsNoTracking().SingleOrDefaultAsync(ct);
            return vault is null ? Problems.Of(StatusCodes.Status404NotFound, "not_initialized") : Results.Ok(new
            {
                vault.Salt,
                vault.Iterations,
                vault.FormatVersion
            });
        }).RequireRateLimiting(RateLimits.RecoveryEnvelope);
        app.MapGet("/v1/recovery/envelope", async (JournalDb db, CancellationToken ct) =>
        {
            var vault = await db.Vaults.AsNoTracking().SingleOrDefaultAsync(ct);
            return vault is null ? Problems.Of(StatusCodes.Status404NotFound, "not_initialized") : Results.Ok(Envelope(vault));
        }).RequireAuthorization().RequireRateLimiting(RateLimits.RecoveryEnvelope);
        app.MapPost("/v1/recovery", Recover).RequireRateLimiting(RateLimits.Anonymous);
        app.MapPost("/v1/recovery/password", ChangePassword).RequireAuthorization().RequireRateLimiting(RateLimits.Password);
        var secured = app.MapGroup("/v1/devices").RequireAuthorization().RequireRateLimiting(RateLimits.Device);
        secured.MapGet("/", async (JournalDb db, CancellationToken ct) =>
            await db.Devices.AsNoTracking()
                .Select(x => new DeviceSummary(x.Id, x.Name, x.CreatedAt, x.Revoked, x.CreatedVia, x.ApprovedByDeviceId))
                .ToListAsync(ct));
        secured.MapDelete("/{id:guid}", Revoke);
    }

    // Lets a client report a wrong code before the person chooses a password. It checks exactly what setup
    // checks first, sharing its attempt budget, and changes nothing: the code stays valid for setup (capability setup-check).
    private static async Task<IResult> CheckSetup(SetupCheckRequest request, JournalDb db, StoragePaths paths, AuditLog audit, SetupAttempts attempts, HttpContext http) =>
        await VerifySetupCode(request.SetupCode, db, paths, audit, attempts, http) ?? Results.NoContent();

    // Everything that needs no lock is checked before the write gate; the gate then rechecks state.
    private static async Task<IResult> Setup(SetupRequest request, JournalDb db, StoragePaths paths, WriteGate gate, TimeProvider clock, AuditLog audit, SetupAttempts attempts, HttpContext http)
    {
        var ct = http.RequestAborted;
        if (await VerifySetupCode(request.SetupCode, db, paths, audit, attempts, http) is { } refusal)
        {
            return refusal;
        }
        if (!ValidVault(request) || !ValidName(request.DeviceName))
        {
            return Problems.Of(StatusCodes.Status400BadRequest, "invalid_setup");
        }

        using var lease = await gate.Enter(ct);
        if (await db.Vaults.AnyAsync(ct))
        {
            return Problems.Of(StatusCodes.Status409Conflict, "already_initialized");
        }
        var token = Secrets.NewToken();
        var device = NewDevice(request.DeviceName, token, clock, DeviceOrigin.Setup);
        db.Vaults.Add(new Vault { Salt = request.Salt, WrappedKey = request.WrappedKey, RecoveryHash = Secrets.Hash(request.RecoverySecret), Iterations = request.Iterations, FormatVersion = request.FormatVersion, SyncId = SyncIdentity.NewId() });
        db.Devices.Add(device);
        await db.SaveChangesAsync(ct);
        File.Delete(paths.BootstrapFile);
        audit.DeviceEnrolled(device.Id, "setup");
        return Results.Ok(new DeviceGrant(device.Id, token));
    }

    // Returns the refusal, or null when the code matches (the attempt then doesn't count as a failure).
    private static async Task<IResult?> VerifySetupCode(string setupCode, JournalDb db, StoragePaths paths, AuditLog audit, SetupAttempts attempts, HttpContext http)
    {
        var ct = http.RequestAborted;
        if (await db.Vaults.AsNoTracking().AnyAsync(ct))
        {
            return Problems.Of(StatusCodes.Status409Conflict, "already_initialized");
        }
        // Only well-formed codes count as attempts: typing mistakes such as a missing character don't.
        var code = SetupCode.Normalize(setupCode);
        if (!SetupCode.IsValid(code))
        {
            return Problems.Of(StatusCodes.Status400BadRequest, "invalid_setup_code");
        }
        // The server writes a new setup code when it starts without a vault.
        var expected = await SetupCode.Read(paths.BootstrapFile, ct);
        if (expected is null)
        {
            return Problems.Of(StatusCodes.Status503ServiceUnavailable, "setup_code_missing");
        }
        if (attempts.Reserve() is { } wait)
        {
            http.Response.Headers.RetryAfter = Math.Ceiling(wait.TotalSeconds).ToString(CultureInfo.InvariantCulture);
            return Problems.Of(StatusCodes.Status429TooManyRequests, "rate_limited");
        }
        if (!Secrets.Matches(code, Secrets.Hash(expected)))
        {
            audit.SetupCodeRejected(RateLimits.ClientAddress(http));
            return Problems.Of(StatusCodes.Status401Unauthorized, "invalid_setup_code");
        }
        attempts.Succeeded();
        return null;
    }

    // The wrapped vault key is returned only with a new device credential, after the recovery secret is verified.
    private static async Task<IResult> Recover(RecoveryRequest request, JournalDb db, WriteGate gate, TimeProvider clock, AuditLog audit, RecoveryAttempts attempts, HttpContext http)
    {
        var ct = http.RequestAborted;
        if (!ValidName(request.DeviceName))
        {
            return Problems.Of(StatusCodes.Status400BadRequest, "invalid_device_name");
        }
        if (attempts.Reserve() is { } wait)
        {
            http.Response.Headers.RetryAfter = Math.Ceiling(wait.TotalSeconds).ToString(CultureInfo.InvariantCulture);
            return Problems.Of(StatusCodes.Status429TooManyRequests, "rate_limited");
        }
        var verifier = await db.Vaults.AsNoTracking().Select(vault => vault.RecoveryHash).SingleOrDefaultAsync(ct);
        if (verifier is null || !Secrets.Matches(request.RecoverySecret, verifier))
        {
            audit.RecoveryRejected(RateLimits.ClientAddress(http));
            return Problems.Of(StatusCodes.Status401Unauthorized, "invalid_recovery_secret");
        }

        using var lease = await gate.Enter(ct);
        // A concurrent recovery may have consumed a one-use administrator code.
        var vault = await db.Vaults.SingleOrDefaultAsync(ct);
        if (vault is null || !Secrets.Matches(request.RecoverySecret, vault.RecoveryHash))
        {
            return Problems.Of(StatusCodes.Status401Unauthorized, "invalid_recovery_secret");
        }
        var token = Secrets.NewToken();
        var device = NewDevice(request.DeviceName, token, clock, DeviceOrigin.Recovery);
        if (vault.FormatVersion == 4)
        {
            vault.RecoveryHash = Secrets.Hash(Secrets.NewToken());
        }
        db.Devices.Add(device);
        await db.SaveChangesAsync(ct);
        attempts.Succeeded();
        audit.DeviceEnrolled(device.Id, "recovery");
        return Results.Ok(new RecoveryGrant(device.Id, token, Envelope(vault)));
    }

    private static async Task<IResult> Revoke(Guid id, JournalDb db, WriteGate gate, SyncSignal signal, AuditLog audit, HttpContext http)
    {
        var ct = http.RequestAborted;
        using var lease = await gate.Enter(ct);
        if (!await DeviceAuthentication.IsStillAuthorized(http, db))
        {
            return Problems.Of(StatusCodes.Status401Unauthorized, "unauthorized");
        }

        var device = await db.Devices.FindAsync([id], ct);
        if (device is null)
        {
            return Problems.Of(StatusCodes.Status404NotFound, "device_not_found");
        }

        device.Revoked = true;
        try
        {
            await db.SaveChangesAsync(ct);
        }
        finally
        {
            // A wait held by the revoked device re-checks its credential now and is refused.
            signal.Notify();
        }
        var revokedBy = DeviceAuthentication.Current(http).Id;
        audit.DeviceRevoked(id, revokedBy);
        return Results.NoContent();
    }

    // Replaces the password envelope atomically. The key it wraps is unchanged, so encrypted content,
    // device keys and connected devices are unaffected. The current password's verifier is required.
    private static async Task<IResult> ChangePassword(ChangePasswordRequest request, JournalDb db, WriteGate gate, AuditLog audit, HttpContext http)
    {
        var ct = http.RequestAborted;
        if (request.CurrentRecoverySecret.Length != 64 ||
            !ValidVault(new SetupRequest("", request.Salt, request.WrappedKey, request.Iterations, request.RecoverySecret, "", request.FormatVersion)))
        {
            return Problems.Of(StatusCodes.Status400BadRequest, "invalid_password_change");
        }
        using var lease = await gate.Enter(ct);
        if (!await DeviceAuthentication.IsStillAuthorized(http, db))
        {
            return Problems.Of(StatusCodes.Status401Unauthorized, "unauthorized");
        }
        var vault = await db.Vaults.SingleOrDefaultAsync(ct);
        if (vault is null)
        {
            return Problems.Of(StatusCodes.Status404NotFound, "not_initialized");
        }
        if (vault.FormatVersion != 2)
        {
            return Problems.Of(StatusCodes.Status409Conflict, "unsupported_format");
        }
        if (request.FormatVersion != vault.FormatVersion)
        {
            return Problems.Of(StatusCodes.Status400BadRequest, "invalid_password_change");
        }
        if (!Secrets.Matches(request.CurrentRecoverySecret, vault.RecoveryHash))
        {
            return Problems.Of(StatusCodes.Status403Forbidden, "wrong_password");
        }
        vault.Salt = request.Salt;
        vault.WrappedKey = request.WrappedKey;
        vault.Iterations = request.Iterations;
        vault.RecoveryHash = Secrets.Hash(request.RecoverySecret);
        await db.SaveChangesAsync(ct);
        var changedBy = DeviceAuthentication.Current(http).Id;
        audit.PasswordChanged(changedBy);
        return Results.NoContent();
    }
    internal static bool ValidName(string value) => !string.IsNullOrWhiteSpace(value) && value.Length <= 100;
    private static bool ValidVault(SetupRequest r) => r.RecoverySecret.Length == 64 &&
        (r.FormatVersion == 4
            ? r.Iterations == 0 && r.Salt.Length == 0 && r.WrappedKey.Length == 0
            : r.FormatVersion is >= 1 and <= 3 && r.Iterations == 600_000 && Secrets.IsBase64(r.Salt, 16, 16) && Secrets.IsBase64(r.WrappedKey, 60, 60));
    internal static Device NewDevice(string name, string token, TimeProvider clock, string createdVia, Guid? approvedBy = null) =>
        new()
        {
            Id = Guid.NewGuid(),
            Name = name,
            TokenHash = Secrets.Hash(token),
            CreatedAt = clock.GetUtcNow(),
            CreatedVia = createdVia,
            ApprovedByDeviceId = approvedBy
        };
    private static RecoveryEnvelope Envelope(Vault vault) => new(vault.Salt, vault.WrappedKey, vault.Iterations, vault.FormatVersion);
}
public sealed record SetupRequest(string SetupCode, string Salt, string WrappedKey, int Iterations, string RecoverySecret, string DeviceName, int FormatVersion = 1);
public sealed record SetupCheckRequest(string SetupCode);
public sealed record ChangePasswordRequest(string CurrentRecoverySecret, string Salt, string WrappedKey, int Iterations, string RecoverySecret, int FormatVersion);
public sealed record RecoveryRequest(string RecoverySecret, string DeviceName);
public sealed record DeviceGrant(Guid DeviceId, string Token);
public sealed record RecoveryEnvelope(string Salt, string WrappedKey, int Iterations, int FormatVersion);
public sealed record RecoveryGrant(Guid DeviceId, string Token, RecoveryEnvelope Envelope);
// CreatedVia is omitted for devices added before it was recorded.
public sealed record DeviceSummary(
    Guid Id, string Name, DateTimeOffset CreatedAt, bool Revoked,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? CreatedVia, Guid? ApprovedByDeviceId);
