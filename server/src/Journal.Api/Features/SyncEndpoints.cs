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
    public const string ContinuityDigestFeature = "sync-continuity-digest";

    private static bool IsDigest(string value) =>
        value.Length == 64 && value.All(c => char.IsAsciiDigit(c) || c is >= 'a' and <= 'f');

    private static string Digest(string payload) =>
        Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(payload)));

    public static void MapSync(this WebApplication app)
    {
        var group = app.MapGroup("/v1/sync").RequireAuthorization().RequireRateLimiting(RateLimits.Sync);
        group.MapGet("/", ReadPage);
        group.MapPut("/{id:guid}", Write).WithBodyLimit(BodyLimits.SyncRecord);
    }

    // afterRecord/afterRevision (optional, together): the change the client last applied at `after`.
    // afterDigest (optional, with them; capability sync-continuity-digest): the lower-case hex SHA-256 of
    // that change's payload text. If this database has a different change there, it is not the log the
    // client read (for example a data directory restored by copying), and the client must reconcile.
    private static async Task<IResult> ReadPage(long? after, int? limit, Guid? afterRecord, long? afterRevision, string? afterDigest, JournalDb db, CancellationToken ct)
    {
        var cursor = after ?? 0;
        if (cursor < 0 || afterRecord.HasValue != afterRevision.HasValue ||
            (afterDigest is not null && (!afterRecord.HasValue || !IsDigest(afterDigest))))
        {
            return Problems.Of(StatusCodes.Status400BadRequest, "invalid_cursor");
        }
        if (cursor > 0 && afterRecord is { } record && afterRevision is { } revision)
        {
            var payload = await db.Changes.AsNoTracking()
                .Where(x => x.Cursor == cursor && x.RecordId == record && x.Revision == revision)
                .Select(x => x.Payload).FirstOrDefaultAsync(ct);
            // A rolled-back server can give the same record and revision to another device's version.
            if (payload is null || (afterDigest is not null && Digest(payload) != afterDigest))
            {
                return Problems.Of(StatusCodes.Status409Conflict, "server_changed");
            }
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

    private static async Task<IResult> Write(Guid id, PutRecord request, JournalDb db, WriteGate gate, TimeProvider clock, HttpContext http)
    {
        var ct = http.RequestAborted;
        if (id == Guid.Empty || request.OperationId == Guid.Empty || request.BaseRevision < 0 ||
            request.Kind is not ("journal" or "entry" or "template") || !Secrets.IsBase64(request.Payload, 29, 4 * 1024 * 1024))
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
        if (applied is not null)
        {
            return applied.RequestHash == hash ? Results.Content(await Receipt(applied, db, ct), "application/json") : Problems.Of(StatusCodes.Status409Conflict, "operation_reused");
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
        await transaction.CommitAsync(ct);
        return Results.Content(JsonSerializer.Serialize(change, Json), "application/json");
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

    // The same receipt the operation first returned: the change it wrote, serialized the same way.
    private static async Task<string> Receipt(AppliedOperation applied, JournalDb db, CancellationToken ct)
    {
        if (applied.ChangeCursor is not { } cursor)
        {
            return applied.ResponseJson;
        }
        var change = await db.Changes.AsNoTracking().SingleAsync(x => x.Cursor == cursor, ct);
        return JsonSerializer.Serialize(change, Json);
    }
}
public sealed record PutRecord(Guid OperationId, long BaseRevision, string Kind, string Payload, string? ServerId = null);
