using Journal.Api.Data;
using Journal.Api.Security;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;

namespace Journal.Api.Features;

// Turns on encryption for a vault created without it (capability encryption-upgrade; protocol/README.md,
// "Turning on encryption"). The server can't encrypt anything itself. The requesting device has synchronized
// everything and staged an encrypted copy with the same record and image identities, so the server replaces the
// whole vault: every readable record, revision, receipt, image and pairing request is removed, every other device
// is signed out, and the server gets a new identity. The device then uploads its encrypted copy.
public static class EncryptionEndpoints
{
    public const string Feature = "encryption-upgrade";

    public static void MapEncryption(this WebApplication app) =>
        app.MapPost("/v1/recovery/encrypt", TurnOn).RequireAuthorization().RequireRateLimiting(RateLimits.Password);

    private static async Task<IResult> TurnOn(TurnOnEncryptionRequest request, JournalDb db, StoragePaths paths, WriteGate gate, SyncSignal signal, AuditLog audit, HttpContext http)
    {
        var ct = http.RequestAborted;
        if (!ValidRequest(request))
        {
            return Problems.Of(StatusCodes.Status400BadRequest, "invalid_encryption_request");
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
        // A retry of the request that already succeeded: its random salt and wrapped key identify it.
        if (vault.FormatVersion == 2 && vault.Salt == request.Salt && vault.WrappedKey == request.WrappedKey &&
            Secrets.Matches(request.RecoverySecret, vault.RecoveryHash))
        {
            return Results.Ok(new EncryptionResult(vault.SyncId));
        }
        if (vault.FormatVersion is not (3 or 4))
        {
            return Problems.Of(StatusCodes.Status409Conflict, "unsupported_format");
        }
        // A library with an access password needs it; without one, the device credential is the authorization.
        if (vault.FormatVersion == 3 &&
            (request.CurrentRecoverySecret is not { Length: 64 } current || !Secrets.Matches(current, vault.RecoveryHash)))
        {
            return Problems.Of(StatusCodes.Status403Forbidden, "wrong_password");
        }
        // The device's copy must hold every change: anything written since it last read would be lost.
        if (!await HasReadEverything(request, db, ct))
        {
            return Problems.Of(StatusCodes.Status409Conflict, "server_changed");
        }

        var serverId = SyncIdentity.NewId();
        var requester = DeviceAuthentication.Current(http).Id;
        // Written first, so a server stopped before the files are removed finishes at its next start.
        EncryptionPurge.Begin(paths, serverId);
        int signedOut;
        await using (var transaction = await db.Database.BeginTransactionAsync(ct))
        {
            vault.Salt = request.Salt;
            vault.WrappedKey = request.WrappedKey;
            vault.Iterations = request.Iterations;
            vault.RecoveryHash = Secrets.Hash(request.RecoverySecret);
            vault.FormatVersion = 2;
            vault.SyncId = serverId;
            vault.SyncIdCursor = 0;
            await db.SaveChangesAsync(ct);
            // Everything the vault held before, readable or tied to it, is removed here, in this one transaction.
            await db.Operations.ExecuteDeleteAsync(ct);
            await db.Changes.ExecuteDeleteAsync(ct);
            await db.Records.ExecuteDeleteAsync(ct);
            await db.Attachments.ExecuteDeleteAsync(ct);
            await db.PairRequests.ExecuteDeleteAsync(ct);
            await AgentGrantEndpoints.RemoveAll(db, ct);
            signedOut = await db.Devices.Where(device => device.Id != requester && !device.Revoked)
                .ExecuteUpdateAsync(update => update.SetProperty(device => device.Revoked, true), ct);
            try
            {
                await transaction.CommitAsync(ct);
            }
            finally
            {
                // Before the slow purge: waits of revoked devices are refused, and the requester's sees the new identity.
                signal.Notify();
            }
        }
        audit.EncryptionTurnedOn(requester, signedOut);
        // The vault has changed; removing what it no longer refers to finishes even if the device disconnects. If it
        // can't finish now, the marker stays and the next start finishes it.
        try
        {
            await EncryptionPurge.Finish(db, paths, audit, CancellationToken.None);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or SqliteException)
        {
            audit.EncryptionPurgeDeferred();
        }
        return Results.Ok(new EncryptionResult(serverId));
    }

    private static async Task<bool> HasReadEverything(TurnOnEncryptionRequest request, JournalDb db, CancellationToken ct)
    {
        var latest = await db.Changes.MaxAsync(change => (long?)change.Cursor, ct) ?? 0;
        if (latest != request.AfterCursor)
        {
            return false;
        }
        return latest == 0 || request.AfterRecord is not { } record || request.AfterRevision is not { } revision ||
            await db.Changes.AnyAsync(change => change.Cursor == latest && change.RecordId == record && change.Revision == revision, ct);
    }

    private static bool ValidRequest(TurnOnEncryptionRequest request) =>
        request.FormatVersion == 2 && request.Iterations == 600_000 && request.RecoverySecret.Length == 64 &&
        Secrets.IsBase64(request.Salt, 16, 16) && Secrets.IsBase64(request.WrappedKey, 60, 60) &&
        request.AfterCursor >= 0 && request.AfterRecord.HasValue == request.AfterRevision.HasValue;
}

public sealed record TurnOnEncryptionRequest(
    string Salt, string WrappedKey, int Iterations, string RecoverySecret, int FormatVersion, long AfterCursor,
    Guid? AfterRecord = null, long? AfterRevision = null, string? CurrentRecoverySecret = null);
public sealed record EncryptionResult(string ServerId);
