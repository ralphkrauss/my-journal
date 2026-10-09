using System.Text.Json;
using Journal.Api.Data;
using Journal.Api.Security;
using Microsoft.EntityFrameworkCore;

namespace Journal.Api.Features;

public static class SyncEndpoints
{
    // A page stops before its payloads exceed this many bytes, but always holds at least one change,
    // so a single large record still makes progress.
    public const long PageBytes = 8 * 1024 * 1024;
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    // The longest a wait is held. Below the response and idle timeouts of common reverse proxies (30 s and more).
    public const int MaximumWaitSeconds = 25;

    // 1 to 32 characters from a-z, 0-9 and '-'. The server never interprets a payload; the kind is bound into the
    // record's encryption context by clients.
    internal static bool IsRecordKind(string? kind) =>
        kind is { Length: >= 1 and <= 32 } && kind.All(c => c is (>= 'a' and <= 'z') or (>= '0' and <= '9') or '-');

    private static bool IsDigest(string value) =>
        value.Length == 64 && value.All(c => char.IsAsciiDigit(c) || c is >= 'a' and <= 'f');

    private static string Digest(string payload) =>
        Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(payload)));

    public static void MapSync(this WebApplication app)
    {
        var group = app.MapGroup("/v1/sync").RequireAuthorization().RequireRateLimiting(RateLimits.Sync);
        group.MapGet("/", ReadPage);
        group.MapPut("/{id:guid}", Write).WithBodyLimit(BodyLimits.SyncRecord);
        // Outside the group: a held wait must not use one of the device's concurrent sync slots.
        app.MapGet("/v1/sync/wait", Wait).RequireAuthorization().RequireRateLimiting(RateLimits.SyncWait);
    }

    private static bool ValidPosition(long cursor, Guid? afterRecord, long? afterRevision, string? afterDigest) =>
        cursor >= 0 && afterRecord.HasValue == afterRevision.HasValue &&
        (afterDigest is null || (afterRecord.HasValue && IsDigest(afterDigest)));

    // Whether this database still has, at `cursor`, the change the client applied there (and, with a digest, the same
    // payload). A rolled-back server can give the same record and revision to another device's version.
    private static async Task<bool> HasAppliedChange(JournalDb db, long cursor, Guid? afterRecord, long? afterRevision, string? afterDigest, CancellationToken ct)
    {
        if (cursor <= 0 || afterRecord is not { } record || afterRevision is not { } revision)
        {
            return true;
        }
        var changes = db.Changes.AsNoTracking().Where(x => x.Cursor == cursor && x.RecordId == record && x.Revision == revision);
        if (afterDigest is null)
        {
            return await changes.AnyAsync(ct);
        }
        var payload = await changes.Select(x => x.Payload).FirstOrDefaultAsync(ct);
        return payload is not null && Digest(payload) == afterDigest;
    }

    // afterRecord/afterRevision (optional, together): the change the client last applied at `after`.
    // afterDigest (optional, with them; capability sync-continuity-digest): the lower-case hex SHA-256 of
    // that change's payload text. If this database has a different change there, it is not the log the
    // client read (for example a data directory restored by copying), and the client must reconcile.
    private static async Task<IResult> ReadPage(long? after, int? limit, Guid? afterRecord, long? afterRevision, string? afterDigest, JournalDb db, CancellationToken ct)
    {
        var cursor = after ?? 0;
        if (!ValidPosition(cursor, afterRecord, afterRevision, afterDigest))
        {
            return Problems.Of(StatusCodes.Status400BadRequest, "invalid_cursor");
        }
        if (!await HasAppliedChange(db, cursor, afterRecord, afterRevision, afterDigest, ct))
        {
            return Problems.Of(StatusCodes.Status409Conflict, "server_changed");
        }

        var pageSize = Math.Clamp(limit ?? 100, 1, 200);
        var changes = new List<Change>();
        var hasMore = false;
        long bytes = 0;
        await foreach (var change in db.Changes.AsNoTracking().Where(x => x.Cursor > cursor).OrderBy(x => x.Cursor).Take(pageSize + 1).AsAsyncEnumerable().WithCancellation(ct))
        {
            if (changes.Count == pageSize || (changes.Count > 0 && bytes + change.Payload.Length > PageBytes))
            {
                hasMore = true;
                break;
            }
            bytes += change.Payload.Length;
            changes.Add(change);
        }

        var identity = await db.Vaults.AsNoTracking().Select(vault => new { vault.SyncId, vault.SyncIdCursor }).SingleOrDefaultAsync(ct);
        return Results.Ok(new
        {
            changes,
            cursor = changes.Count > 0 ? changes[^1].Cursor : cursor,
            hasMore,
            serverId = identity?.SyncId,
            serverIdCursor = identity?.SyncIdCursor ?? 0
        });
    }

    // GET /v1/sync/wait (capability sync-wait): holds the request until the log has a change after `after`, the
    // change the client applied there is gone, or the identity differs (changed: true), or the timeout passes with
    // none of that (changed: false). Every check reads the database, so it can't miss a change; it sends no content.
    private static async Task<IResult> Wait(long? after, Guid? afterRecord, long? afterRevision, string? afterDigest, string? serverId, int? timeout,
        JournalDb db, SyncSignal signal, TimeProvider clock, IHostApplicationLifetime lifetime, HttpContext http)
    {
        if (after is not { } cursor || !ValidPosition(cursor, afterRecord, afterRevision, afterDigest) || serverId is { Length: > 64 })
        {
            return Problems.Of(StatusCodes.Status400BadRequest, "invalid_cursor");
        }
        var ct = http.RequestAborted;
        var stopping = lifetime.ApplicationStopping;
        // At capacity, an early answer: it proves nothing, so the client counts it toward polling instead.
        if (signal.Register(DeviceAuthentication.Current(http).Id) is not { } registration)
        {
            return Results.Ok(new
            {
                changed = false,
                early = true
            });
        }
        try
        {
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(Math.Clamp(timeout ?? MaximumWaitSeconds, 1, MaximumWaitSeconds)), clock);
            using var wake = CancellationTokenSource.CreateLinkedTokenSource(deadline.Token, ct, stopping);
            // The payload digest can only change with a restart (which ends every wait), so it is compared once.
            if (!await HasAppliedChange(db, cursor, afterRecord, afterRevision, afterDigest, ct))
            {
                return Changed(true);
            }
            while (true)
            {
                var notified = signal.Current;
                if (!await DeviceAuthentication.IsStillAuthorized(http, db))
                {
                    return Problems.Of(StatusCodes.Status401Unauthorized, "unauthorized");
                }
                if (await HasNews(db, cursor, afterRecord, afterRevision, serverId, ct))
                {
                    return Changed(true);
                }
                if (deadline.IsCancellationRequested)
                {
                    return Changed(false);
                }
                if (registration.Superseded.IsCompleted || stopping.IsCancellationRequested)
                {
                    return Results.Ok(new
                    {
                        changed = false,
                        early = true
                    });
                }
                // After the deadline or shutdown, the next pass checks once more and answers; after an abort, its
                // reads throw and end the request.
                await SyncSignal.WaitForSignal(notified, registration.Superseded, wake.Token);
            }
        }
        finally
        {
            signal.Release(registration);
        }
    }

    private static IResult Changed(bool changed) => Results.Ok(new { changed });

    // What an ordinary sync from this position would find: another identity, a change after `after`, or the change
    // the client applied at `after` gone (turning on encryption removes every change without a restart).
    private static async Task<bool> HasNews(JournalDb db, long cursor, Guid? afterRecord, long? afterRevision, string? serverId, CancellationToken ct)
    {
        var identity = await db.Vaults.AsNoTracking().Select(vault => vault.SyncId).SingleOrDefaultAsync(ct);
        if (identity is null || (serverId is not null && !string.Equals(serverId, identity, StringComparison.OrdinalIgnoreCase)))
        {
            return true;
        }
        return !await HasAppliedChange(db, cursor, afterRecord, afterRevision, null, ct) ||
            await db.Changes.AsNoTracking().AnyAsync(change => change.Cursor > cursor, ct);
    }

    private static async Task<IResult> Write(Guid id, PutRecord request, JournalDb db, WriteGate gate, SyncSignal signal, TimeProvider clock, HttpContext http)
    {
        var ct = http.RequestAborted;
        if (id == Guid.Empty || request.OperationId == Guid.Empty || request.BaseRevision < 0 ||
            !IsRecordKind(request.Kind) || !Secrets.IsBase64(request.Payload, 29, 4 * 1024 * 1024))
        {
            return Problems.Of(StatusCodes.Status400BadRequest, "invalid_record");
        }

        // The identity guard is not part of the operation, so earlier receipts stay retryable.
        var hash = Secrets.Hash(JsonSerializer.Serialize(new
        {
            id,
            request = new
            {
                request.OperationId,
                request.BaseRevision,
                request.Kind,
                request.Payload
            }
        }, Json));
        using var lease = await gate.Enter(ct);
        if (!await DeviceAuthentication.IsStillAuthorized(http, db))
        {
            return Problems.Of(StatusCodes.Status401Unauthorized, "unauthorized");
        }

        var applied = await db.Operations.AsNoTracking().SingleOrDefaultAsync(x => x.Id == request.OperationId, ct);
        var shortReceipt = request.ShortReceipt == true;
        if (applied is not null)
        {
            return applied.RequestHash == hash ? Results.Content(await Receipt(applied, shortReceipt, db, ct), "application/json") : Problems.Of(StatusCodes.Status409Conflict, "operation_reused");
        }

        await using var transaction = await db.Database.BeginTransactionAsync(ct);
        var vault = await db.Vaults.AsNoTracking().SingleAsync(ct);
        if (request.ServerId is { } expected && !string.Equals(expected, vault.SyncId, StringComparison.OrdinalIgnoreCase))
        {
            // The client last synchronized with a different database, such as before a restore.
            return Problems.Of(StatusCodes.Status409Conflict, "server_changed");
        }
        // An encrypted vault holds only ciphertext. A device whose library isn't encrypted, such as one still
        // synchronizing when another device turned encryption on, never adds readable journals to it.
        if (vault.FormatVersion is 1 or 2 && IsReadable(request.Payload))
        {
            return Problems.Of(StatusCodes.Status400BadRequest, "unencrypted_record");
        }
        var record = await db.Records.SingleOrDefaultAsync(x => x.Id == id, ct);
        var currentRevision = record?.Revision ?? 0;
        if (currentRevision != request.BaseRevision)
        {
            // A base ahead of the server means the server lost revisions the client has seen.
            return Problems.RevisionConflict(request.BaseRevision > currentRevision ? "revision_ahead" : "revision_conflict", record);
        }

        if (record is not null && record.Kind != request.Kind)
        {
            return Problems.Of(StatusCodes.Status400BadRequest, "kind_is_immutable");
        }

        var device = DeviceAuthentication.Current(http);
        if (record is null)
        {
            record = new EncryptedRecord { Id = id, Kind = request.Kind };
            db.Records.Add(record);
        }
        record.Revision++;
        record.Payload = request.Payload;
        record.DeviceId = device.Id;
        record.ModifiedAt = clock.GetUtcNow();
        var change = new Change { RecordId = id, Kind = record.Kind, Payload = record.Payload, Revision = record.Revision, DeviceId = device.Id, ModifiedAt = record.ModifiedAt };
        db.Changes.Add(change);
        await db.SaveChangesAsync(ct);
        db.Operations.Add(new AppliedOperation { Id = request.OperationId, RecordId = id, RequestHash = hash, ChangeCursor = change.Cursor });
        await db.SaveChangesAsync(ct);
        try
        {
            await transaction.CommitAsync(ct);
        }
        finally
        {
            // Wakes waiting devices; it must follow the commit attempt, so an aborted request can't skip it.
            signal.Notify();
        }
        return Results.Content(ReceiptJson(change, shortReceipt), "application/json");
    }

    // A record stored without encryption is a JSON document. Ciphertext begins with a random nonce, so it rarely
    // starts like one and never is one in practice.
    private static bool IsReadable(string payload)
    {
        ReadOnlySpan<byte> bytes = Convert.FromBase64String(payload);
        if (bytes.StartsWith("\uFEFF"u8))
        {
            bytes = bytes[3..];
        }
        if (bytes.IsEmpty || bytes[0] is not ((byte)'{' or (byte)' ' or (byte)'\t' or (byte)'\n' or (byte)'\r'))
        {
            return false;
        }
        var reader = new Utf8JsonReader(bytes, new JsonReaderOptions { MaxDepth = 4096 });
        try
        {
            while (reader.Read())
            {
            }
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    // The same receipt the operation first returned: the change it wrote, in the form this request asks for. Receipts
    // kept whole by older servers are returned whole; clients that ask for a short receipt accept those too.
    private static async Task<string> Receipt(AppliedOperation applied, bool shortReceipt, JournalDb db, CancellationToken ct)
    {
        if (applied.ChangeCursor is not { } cursor)
        {
            return applied.ResponseJson;
        }
        var change = await db.Changes.AsNoTracking().SingleAsync(x => x.Cursor == cursor, ct);
        return ReceiptJson(change, shortReceipt);
    }

    // A short receipt (capability sync-short-receipt) is the change without its payload, which the client sent and
    // already has, and with the payload's digest instead.
    private static string ReceiptJson(Change change, bool shortReceipt) => shortReceipt
        ? JsonSerializer.Serialize(new ShortReceipt(change.Cursor, change.RecordId, change.Revision, change.Kind, change.DeviceId, change.ModifiedAt, Digest(change.Payload)), Json)
        : JsonSerializer.Serialize(change, Json);
}
// The short receipt and the operation's request hash never include ShortReceipt: it only chooses the receipt's form.
public sealed record PutRecord(Guid OperationId, long BaseRevision, string Kind, string Payload, string? ServerId = null, bool? ShortReceipt = null);
public sealed record ShortReceipt(long Cursor, Guid RecordId, long Revision, string Kind, Guid DeviceId, DateTimeOffset ModifiedAt, string PayloadDigest);
