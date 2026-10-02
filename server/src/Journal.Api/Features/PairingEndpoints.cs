using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Journal.Api.Data;
using Journal.Api.Security;
using Microsoft.EntityFrameworkCore;

namespace Journal.Api.Features;

// Check-code pairing (protocol/README.md): the new device commits to its key, the approving device
// contributes a one-time key, and only then is the new device's key revealed. Both devices show a
// check code derived from the pairing ID and both keys; the server cannot choose keys that match it.
// With invite pairing, the new device instead proves that it read a code shown by the approving device.
public static class PairingEndpoints
{
    // Pending requests are small. The cap bounds storage; per-address rate limits keep one caller
    // from filling it within the five-minute lifetime.
    public const int MaximumPending = 200;
    public static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(5);
    // The new device stops polling at the expiry it was given. An approval must leave it time to
    // collect the grant, and an approved grant stays readable a little longer for devices whose
    // clocks run behind. Grants never collected are revoked when the request is removed.
    public static readonly TimeSpan ApprovalMargin = TimeSpan.FromSeconds(30);
    public static readonly TimeSpan GrantGrace = TimeSpan.FromMinutes(2);

    public static void MapPairing(this WebApplication app)
    {
        app.MapPost("/v1/pairing", Begin).RequireRateLimiting(RateLimits.PairingStart);
        app.MapPost("/v1/pairing/{id:guid}/poll", Poll).RequireRateLimiting(RateLimits.PairingRequest);
        app.MapPost("/v1/pairing/{id:guid}/reveal", Reveal).RequireRateLimiting(RateLimits.PairingRequest);
        app.MapPost("/v1/pairing/{id:guid}/cancel", Cancel).RequireRateLimiting(RateLimits.PairingRequest);
        var secured = app.MapGroup("/v1/pairing").RequireAuthorization();
        secured.MapPost("/lookup", async (LookupPairing request, JournalDb db, TimeProvider clock, CancellationToken ct) =>
        {
            var hash = Secrets.Hash(request.Code);
            var pair = await db.PairRequests.AsNoTracking().SingleOrDefaultAsync(x => x.CodeHash == hash, ct);
            return Pending(pair, clock.GetUtcNow()) ? Results.Ok(Candidate(pair)) : NotFound();
        }).RequireRateLimiting(RateLimits.DeviceLookup);
        secured.MapGet("/{id:guid}", async (Guid id, JournalDb db, TimeProvider clock, CancellationToken ct) =>
        {
            var pair = await db.PairRequests.AsNoTracking().SingleOrDefaultAsync(x => x.Id == id, ct);
            return Pending(pair, clock.GetUtcNow()) ? Results.Ok(Candidate(pair)) : NotFound();
        }).RequireRateLimiting(RateLimits.Device);
        secured.MapPost("/{id:guid}/challenge", Challenge).RequireRateLimiting(RateLimits.Device);
        secured.MapPost("/{id:guid}/decline", Decline).RequireRateLimiting(RateLimits.Device);
        secured.MapPost("/{id:guid}/approve", Approve).RequireRateLimiting(RateLimits.Device);
    }

    public static string Commitment(byte[] publicKey) =>
        Convert.ToBase64String(SHA256.HashData([.. Encoding.UTF8.GetBytes("journal:v2:pairing-commitment"), .. publicKey]));

    // Removes requests whose lifetime and grant grace period have ended. A device whose grant was
    // never collected keeps no working credential: it is revoked.
    internal static async Task RemoveExpired(JournalDb db, DateTimeOffset now, AuditLog audit, CancellationToken ct)
    {
        // SQLite cannot compare DateTimeOffset server-side; the table is bounded by MaximumPending.
        var expired = (await db.PairRequests.ToListAsync(ct)).Where(x => x.ExpiresAt + GrantGrace < now).ToList();
        var uncollected = expired.Where(x => !x.GrantDelivered).Select(x => x.DeviceId).OfType<Guid>().ToList();
        var devices = await db.Devices.Where(x => uncollected.Contains(x.Id) && !x.Revoked).ToListAsync(ct);
        foreach (var device in devices)
        {
            device.Revoked = true;
            audit.PairingGrantUncollected(device.Id);
        }
        db.PairRequests.RemoveRange(expired);
        await db.SaveChangesAsync(ct);
    }

    private static async Task<IResult> Begin(BeginPairing request, JournalDb db, WriteGate gate, TimeProvider clock, AuditLog audit, HttpContext http)
    {
        var ct = http.RequestAborted;
        // Only check-code requests are accepted: a commitment, never the key itself.
        if (!AccountEndpoints.ValidName(request.DeviceName) || !Secrets.IsBase64(request.KeyCommitment, 32, 32) || !ValidInvite(request))
        {
            return Problems.Of(StatusCodes.Status400BadRequest, "invalid_pairing_request");
        }
        if (!await db.Vaults.AsNoTracking().AnyAsync(ct))
        {
            return Problems.Of(StatusCodes.Status409Conflict, "not_initialized");
        }

        using var lease = await gate.Enter(ct);
        var now = clock.GetUtcNow();
        await RemoveExpired(db, now, audit, ct);
        var pending = await db.PairRequests.AsNoTracking().Select(x => x.ExpiresAt).ToListAsync(ct);
        var active = pending.Where(expires => expires >= now).ToList();
        if (active.Count >= MaximumPending)
        {
            var wait = Math.Max(1, Math.Ceiling((active.Min() - now).TotalSeconds));
            http.Response.Headers.RetryAfter = wait.ToString(CultureInfo.InvariantCulture);
            return Problems.Of(StatusCodes.Status429TooManyRequests, "pairing_capacity");
        }

        // An invite names the connected device's code: the approver looks the request up with it, so it may
        // belong to one request only, including one already approved or declined.
        var code = request.Invite ?? RandomNumberGenerator.GetInt32(100_000_000, 1_000_000_000).ToString(CultureInfo.InvariantCulture);
        var codeHash = Secrets.Hash(code);
        if (request.Invite is not null && await db.PairRequests.AsNoTracking().AnyAsync(x => x.CodeHash == codeHash, ct))
        {
            return Problems.Of(StatusCodes.Status409Conflict, "invite_used");
        }
        var token = Secrets.NewToken();
        var pair = new PairRequest { Id = Guid.NewGuid(), CodeHash = codeHash, PollTokenHash = Secrets.Hash(token), DeviceName = request.DeviceName, KeyCommitment = request.KeyCommitment, InviteProof = request.InviteProof, ExpiresAt = now + Lifetime };
        db.PairRequests.Add(pair);
        await db.SaveChangesAsync(ct);
        return Results.Ok(new
        {
            pair.Id,
            code,
            pollToken = token,
            pair.ExpiresAt
        });
    }

    private static async Task<IResult> Poll(Guid id, PollPairing request, JournalDb db, WriteGate gate, TimeProvider clock, HttpContext http)
    {
        var ct = http.RequestAborted;
        var pair = await db.PairRequests.AsNoTracking().SingleOrDefaultAsync(x => x.Id == id, ct);
        if (!Readable(pair, request.PollToken, clock.GetUtcNow()))
        {
            return NotFound();
        }
        if (pair.EncryptedGrant is not null && !pair.GrantDelivered)
        {
            using var lease = await gate.Enter(ct);
            var current = await db.PairRequests.SingleOrDefaultAsync(x => x.Id == id, ct);
            // Cancelled while waiting for the gate.
            if (current is null)
            {
                return NotFound();
            }
            current.GrantDelivered = true;
            await db.SaveChangesAsync(ct);
        }

        return Results.Ok(new
        {
            approved = pair.EncryptedGrant is not null,
            pair.EncryptedGrant,
            pair.DeviceId,
            pair.ApproverKey,
            pair.Declined
        });
    }

    private static async Task<IResult> Reveal(Guid id, RevealPairing request, JournalDb db, WriteGate gate, TimeProvider clock, HttpContext http)
    {
        var ct = http.RequestAborted;
        if (!Secrets.IsBase64(request.PublicKey, 32, 32))
        {
            return Problems.Of(StatusCodes.Status400BadRequest, "invalid_pairing_request");
        }
        var pair = await db.PairRequests.AsNoTracking().SingleOrDefaultAsync(x => x.Id == id, ct);
        if (pair is null || pair.ExpiresAt < clock.GetUtcNow() || !Secrets.Matches(request.PollToken, pair.PollTokenHash))
        {
            return NotFound();
        }
        // Revealing before the approver's key is fixed would let the server choose that key afterwards.
        if (pair.ApproverKey is null)
        {
            return Problems.Of(StatusCodes.Status409Conflict, "pairing_not_challenged");
        }
        if (pair.Declined)
        {
            return Problems.Of(StatusCodes.Status409Conflict, "pairing_declined");
        }
        if (Commitment(Convert.FromBase64String(request.PublicKey)) != pair.KeyCommitment)
        {
            return Problems.Of(StatusCodes.Status400BadRequest, "commitment_mismatch");
        }
        if (pair.PublicKey.Length > 0)
        {
            return Results.NoContent();
        }

        using var lease = await gate.Enter(ct);
        var current = await db.PairRequests.SingleOrDefaultAsync(x => x.Id == id, ct);
        if (current is null)
        {
            return NotFound();
        }
        if (current.PublicKey.Length == 0)
        {
            current.PublicKey = request.PublicKey;
            await db.SaveChangesAsync(ct);
        }
        return Results.NoContent();
    }

    private static async Task<IResult> Cancel(Guid id, PollPairing request, JournalDb db, WriteGate gate, AuditLog audit, HttpContext http)
    {
        var ct = http.RequestAborted;
        var tokenHash = await db.PairRequests.AsNoTracking().Where(x => x.Id == id).Select(x => x.PollTokenHash).SingleOrDefaultAsync(ct);
        if (tokenHash is null || !Secrets.Matches(request.PollToken, tokenHash))
        {
            return NotFound();
        }

        using var lease = await gate.Enter(ct);
        var pair = await db.PairRequests.SingleOrDefaultAsync(x => x.Id == id, ct);
        if (pair is null)
        {
            return NotFound();
        }
        if (pair.DeviceId is { } deviceId && await db.Devices.SingleOrDefaultAsync(x => x.Id == deviceId && !x.Revoked, ct) is { } device)
        {
            device.Revoked = true;
            audit.PairingCancelled(device.Id);
        }
        db.PairRequests.Remove(pair);
        await db.SaveChangesAsync(ct);
        return Results.NoContent();
    }

    private static async Task<IResult> Challenge(Guid id, ChallengePairing request, JournalDb db, WriteGate gate, TimeProvider clock, HttpContext http)
    {
        var ct = http.RequestAborted;
        if (!Secrets.IsBase64(request.ApproverKey, 32, 32))
        {
            return Problems.Of(StatusCodes.Status400BadRequest, "invalid_pairing_request");
        }
        using var lease = await gate.Enter(ct);
        if (!await DeviceAuthentication.IsStillAuthorized(http, db))
        {
            return Problems.Of(StatusCodes.Status401Unauthorized, "unauthorized");
        }
        var pair = await db.PairRequests.SingleOrDefaultAsync(x => x.Id == id, ct);
        if (!Pending(pair, clock.GetUtcNow()))
        {
            return NotFound();
        }
        // The approver's key is fixed once; only an identical retry is accepted.
        if (pair.ApproverKey is not null && pair.ApproverKey != request.ApproverKey)
        {
            return Problems.Of(StatusCodes.Status409Conflict, "approver_key_fixed");
        }
        pair.ApproverKey = request.ApproverKey;
        await db.SaveChangesAsync(ct);
        return Results.NoContent();
    }

    private static async Task<IResult> Decline(Guid id, JournalDb db, WriteGate gate, TimeProvider clock, HttpContext http)
    {
        var ct = http.RequestAborted;
        using var lease = await gate.Enter(ct);
        if (!await DeviceAuthentication.IsStillAuthorized(http, db))
        {
            return Problems.Of(StatusCodes.Status401Unauthorized, "unauthorized");
        }
        var pair = await db.PairRequests.SingleOrDefaultAsync(x => x.Id == id, ct);
        if (pair is null || pair.ExpiresAt < clock.GetUtcNow())
        {
            return NotFound();
        }
        if (pair.EncryptedGrant is not null)
        {
            return Problems.Of(StatusCodes.Status409Conflict, "pairing_already_approved");
        }
        pair.Declined = true;
        await db.SaveChangesAsync(ct);
        return Results.NoContent();
    }

    private static async Task<IResult> Approve(Guid id, ApprovePairing request, JournalDb db, WriteGate gate, TimeProvider clock, AuditLog audit, HttpContext http)
    {
        var ct = http.RequestAborted;
        if (!Secrets.IsBase64(request.EncryptedGrant, 60, 4096) || request.DeviceToken.Length != 64)
        {
            return Problems.Of(StatusCodes.Status400BadRequest, "invalid_pairing_request");
        }

        using var lease = await gate.Enter(ct);
        if (!await DeviceAuthentication.IsStillAuthorized(http, db))
        {
            return Problems.Of(StatusCodes.Status401Unauthorized, "unauthorized");
        }

        var pair = await db.PairRequests.SingleOrDefaultAsync(x => x.Id == id, ct);
        var now = clock.GetUtcNow();
        if (pair is null || pair.ExpiresAt < now || pair.Declined)
        {
            return NotFound();
        }
        if (pair.EncryptedGrant is not null)
        {
            return Problems.Of(StatusCodes.Status409Conflict, "pairing_already_approved");
        }
        // Too late for the new device to collect the grant before it gives up: refuse instead.
        if (pair.ExpiresAt - now < ApprovalMargin)
        {
            return Problems.Of(StatusCodes.Status404NotFound, "pairing_expired");
        }
        // The grant must be sealed with the approver key both devices used for the check code.
        if (pair.KeyCommitment is null || pair.ApproverKey is null || pair.PublicKey.Length == 0 ||
            !Convert.FromBase64String(request.EncryptedGrant).AsSpan(0, 32).SequenceEqual(Convert.FromBase64String(pair.ApproverKey)))
        {
            return Problems.Of(StatusCodes.Status409Conflict, "grant_key_mismatch");
        }
        // The approving client chooses the credential and includes it only inside the sealed grant to the new device.
        var approvedBy = DeviceAuthentication.Current(http).Id;
        var device = AccountEndpoints.NewDevice(pair.DeviceName, request.DeviceToken, clock, DeviceOrigin.Pairing, approvedBy);
        pair.EncryptedGrant = request.EncryptedGrant;
        pair.DeviceId = device.Id;
        db.Devices.Add(device);
        await db.SaveChangesAsync(ct);
        audit.DevicePaired(device.Id, approvedBy);
        return Results.Ok(new
        {
            device.Id
        });
    }

    // Invite pairing (capability pairing-invite): the invite handle as 32 lower-case hexadecimal characters and
    // a 32-byte HMAC proof, both or neither. Only the connected device that made the invite can check the proof.
    private static bool ValidInvite(BeginPairing request) => (request.Invite, request.InviteProof) switch
    {
        (null, null) => true,
        ({ Length: 32 } invite, { } proof) => invite.All(char.IsAsciiHexDigitLower) && Secrets.IsBase64(proof, 32, 32),
        _ => false,
    };

    private static IResult NotFound() => Problems.Of(StatusCodes.Status404NotFound, "pairing_not_found");

    // Waiting for approval: approvers can look it up, challenge and approve it.
    private static bool Pending([NotNullWhen(true)] PairRequest? pair, DateTimeOffset now) =>
        pair is not null && pair.ExpiresAt >= now && pair.EncryptedGrant is null && !pair.Declined;

    // The new device may poll until expiry; an approved grant remains readable during the grace period.
    private static bool Readable([NotNullWhen(true)] PairRequest? pair, string pollToken, DateTimeOffset now) =>
        pair is not null && Secrets.Matches(pollToken, pair.PollTokenHash) &&
        (pair.ExpiresAt >= now || (pair.EncryptedGrant is not null && pair.ExpiresAt + GrantGrace >= now));

    private static object Candidate(PairRequest pair) => new
    {
        pair.Id,
        pair.DeviceName,
        PublicKey = pair.PublicKey.Length == 0 ? null : pair.PublicKey,
        pair.KeyCommitment,
        pair.ApproverKey,
        pair.InviteProof,
        pair.ExpiresAt
    };
}
public sealed record BeginPairing(string DeviceName, string KeyCommitment, string? Invite = null, string? InviteProof = null);
public sealed record PollPairing(string PollToken);
public sealed record RevealPairing(string PollToken, string PublicKey);
public sealed record LookupPairing(string Code);
public sealed record ChallengePairing(string ApproverKey);
public sealed record ApprovePairing(string DeviceToken, string EncryptedGrant);
