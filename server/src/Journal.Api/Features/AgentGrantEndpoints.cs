using System.Text.RegularExpressions;
using Journal.Api.Data;
using Journal.Api.Security;
using Microsoft.EntityFrameworkCore;

namespace Journal.Api.Features;

// The owner's devices approve agent requests, list and revoke grants, and keep each grant's encrypted copy current
// (protocol/agent-access-server.md, Approval in the app and The per-grant copy).
public static partial class AgentGrantEndpoints
{
    public const int MaximumGrants = 20;
    public const int MaximumItemsPerGrant = 20_000;
    public const long MaximumBytesPerGrant = 128L * 1024 * 1024;
    public const int MaximumItemsPerUpload = 200;
    public const int MaximumMetadataLength = 16 * 1024;
    public const int MaximumEvents = 50;
    private const int MaximumPayloadBytes = 4 * 1024 * 1024;
    private static readonly TimeSpan LongestExpiry = TimeSpan.FromDays(3660);

    [GeneratedRegex("^[0-9a-f]{32}$", RegexOptions.CultureInvariant)]
    private static partial Regex HexPattern();

    public static void MapAgentGrants(this WebApplication app)
    {
        var requests = app.MapGroup("/v1/agent-requests").RequireAuthorization();
        // The Agent Access pane polls the list while it's visible.
        requests.MapGet("/", Requests).RequireRateLimiting(RateLimits.Device);
        requests.MapGet("/{id:guid}", Request).RequireRateLimiting(RateLimits.Device);
        requests.MapPost("/{id:guid}/approve", Approve).RequireRateLimiting(RateLimits.DeviceLookup);
        requests.MapPost("/{id:guid}/ready", Ready).RequireRateLimiting(RateLimits.DeviceLookup);
        requests.MapPost("/{id:guid}/decline", Decline).RequireRateLimiting(RateLimits.DeviceLookup);

        var grants = app.MapGroup("/v1/agents").RequireAuthorization();
        grants.MapGet("/", List).RequireRateLimiting(RateLimits.Device);
        grants.MapPut("/{id:guid}", Change).RequireRateLimiting(RateLimits.Device).WithBodyLimit(BodyLimits.SyncRecord);
        grants.MapDelete("/{id:guid}", Revoke).RequireRateLimiting(RateLimits.Device);
        grants.MapGet("/{id:guid}/items", Manifest).RequireRateLimiting(RateLimits.Device);
        grants.MapPost("/{id:guid}/items", Upload).RequireRateLimiting(RateLimits.Sync).WithBodyLimit(BodyLimits.SyncRecord);
        grants.MapGet("/{id:guid}/activity", Activity).RequireRateLimiting(RateLimits.Device);
    }

    // Requests waiting for the owner, newest first, with where each returns to and whether it would reconnect an
    // agent that signed out. Never the number: the owner reads it from the page.
    private static async Task<IResult> Requests(AgentAuthorizations authorizations, JournalDb db, WriteGate gate, TimeProvider clock, AuditLog audit, CancellationToken ct)
    {
        await RemoveUnfinished(db, authorizations, gate, audit, ct);
        var waiting = authorizations.Waiting();
        var signedOut = await SignedOut(db, clock, ct);
        return Results.Ok(waiting.Select(x => Summary(x, signedOut)));
    }

    // One request, opened by the owner: it's kept from now on until it expires or is decided.
    private static async Task<IResult> Request(Guid id, AgentAuthorizations authorizations, JournalDb db, TimeProvider clock, CancellationToken ct)
    {
        var pending = authorizations.Open(id);
        if (pending is null)
        {
            return Problems.Of(StatusCodes.Status404NotFound, "agent_request_not_found");
        }
        return Results.Ok(Summary(pending, await SignedOut(db, clock, ct)));
    }

    // Active grants without a live refresh token, most recently used first, by client ID. Only these are reconnected:
    // a client ID isn't unique per installation, so a request never takes over an agent that's still connected.
    private static async Task<ILookup<string, Guid>> SignedOut(JournalDb db, TimeProvider clock, CancellationToken ct)
    {
        var connected = await AgentTokens.Connected(db, clock.GetUtcNow(), ct);
        var grants = await db.AgentGrants.AsNoTracking().Where(x => x.State == AgentGrantState.Active).Select(x => new { x.Id, x.ClientId, x.LastUsedAt, x.CreatedAt }).ToListAsync(ct);
        return grants.Where(x => !connected.Contains(x.Id)).OrderByDescending(x => x.LastUsedAt ?? x.CreatedAt).ToLookup(x => x.ClientId, x => x.Id, StringComparer.Ordinal);
    }

    private static AgentRequestSummary Summary(PendingAuthorization pending, ILookup<string, Guid> signedOut)
    {
        var client = pending.Details.Client;
        return new AgentRequestSummary(pending.Id, client.Name, client.ClientId, client.IdentifiedAs,
            OAuthRedirects.Describe(pending.Details.RedirectUri), (OAuthRedirects.Classify(pending.Details.RedirectUri) ?? OAuthRedirects.Kind.Https).ToString().ToLowerInvariant(),
            pending.RequestedAt, pending.ExpiresAt, signedOut[client.ClientId].Cast<Guid?>().FirstOrDefault());
    }

    private static async Task<IResult> Approve(Guid id, AgentApproval request, AgentAuthorizations authorizations, JournalDb db, WriteGate gate, TimeProvider clock, AuditLog audit, HttpContext http)
    {
        var ct = http.RequestAborted;
        var now = clock.GetUtcNow();
        if (request.GrantId == Guid.Empty || !Secrets.IsBase64(request.WrappedKey, AgentKeys.WrappedLength, AgentKeys.WrappedLength) ||
            !Secrets.IsBase64(request.GrantSecret, AgentKeys.KeyLength, AgentKeys.KeyLength) ||
            request.ExpiresAt is { } expires && (expires <= now || expires > now + LongestExpiry))
        {
            return Problems.Of(StatusCodes.Status400BadRequest, "invalid_agent");
        }
        var pending = authorizations.ById(id);
        if (pending is null || pending.Status != PendingStatus.Waiting)
        {
            return Problems.Of(StatusCodes.Status404NotFound, "agent_request_not_found");
        }
        var device = DeviceAuthentication.Current(http);
        // The number is checked before anything is stored: a wrong one declines the request and sends its page back.
        if (pending.Number != request.Number)
        {
            if (authorizations.Approve(id, request.Number, request.GrantId, [], [], false) == AgentAuthorizations.ApproveResult.Mismatch)
            {
                audit.AgentRequestDeclined(device.Id);
                return Problems.Of(StatusCodes.Status409Conflict, "agent_request_mismatch");
            }
            return Problems.Of(StatusCodes.Status404NotFound, "agent_request_not_found");
        }
        var wrapped = Convert.FromBase64String(request.WrappedKey);
        var secret = Convert.FromBase64String(request.GrantSecret);
        using (await gate.Enter(ct))
        {
            if (!await DeviceAuthentication.IsStillAuthorized(http, db))
            {
                return Problems.Of(StatusCodes.Status401Unauthorized, "unauthorized");
            }
            var existing = await db.AgentGrants.SingleOrDefaultAsync(x => x.Id == request.GrantId, ct);
            var reconnect = existing is not null;
            if (reconnect)
            {
                // Only an agent of the same client that signed out (no live refresh token) is reconnected; a client ID
                // isn't unique per installation, so a connected agent is never taken over.
                if (existing!.State != AgentGrantState.Active || !string.Equals(existing.ClientId, pending.Details.Client.ClientId, StringComparison.Ordinal) ||
                    (await AgentTokens.Connected(db, now, ct)).Contains(existing.Id))
                {
                    return Problems.Of(StatusCodes.Status409Conflict, "agent_not_reconnectable");
                }
                existing.ClientName = pending.Details.Client.Name;
                existing.RedirectHost = OAuthRedirects.Describe(pending.Details.RedirectUri);
            }
            else
            {
                if (request.Metadata is null || request.Metadata.Length > MaximumMetadataLength || !Secrets.IsBase64(request.Metadata, 1, MaximumMetadataLength))
                {
                    return Problems.Of(StatusCodes.Status400BadRequest, "invalid_agent");
                }
                if (await db.AgentGrants.CountAsync(ct) >= MaximumGrants)
                {
                    return Problems.Of(StatusCodes.Status409Conflict, "agent_limit");
                }
                db.AgentGrants.Add(new AgentGrant
                {
                    Id = request.GrantId,
                    Metadata = request.Metadata,
                    State = AgentGrantState.Pending,
                    ClientId = pending.Details.Client.ClientId,
                    ClientName = pending.Details.Client.Name,
                    RedirectHost = OAuthRedirects.Describe(pending.Details.RedirectUri),
                    ApprovedByDeviceId = device.Id,
                    CreatedAt = now,
                    ExpiresAt = request.ExpiresAt,
                    Revision = 1,
                });
                await db.SaveChangesAsync(ct);
            }
            if (authorizations.Approve(id, request.Number, request.GrantId, secret, wrapped, reconnect) != AgentAuthorizations.ApproveResult.Approved)
            {
                if (!reconnect)
                {
                    await Delete(db, request.GrantId, ct);
                }
                return Problems.Of(StatusCodes.Status404NotFound, "agent_request_not_found");
            }
            if (reconnect)
            {
                // The request's client name and return address replace the ones the agent had.
                await db.SaveChangesAsync(ct);
            }
        }
        audit.AgentRequestApproved(request.GrantId, device.Id);
        return Results.NoContent();
    }

    // The device uploaded the first copy (or gave up waiting): the browser can return to the client.
    private static async Task<IResult> Ready(Guid id, AgentReady request, AgentAuthorizations authorizations, JournalDb db, WriteGate gate, CancellationToken ct)
    {
        var pending = authorizations.ById(id);
        if (pending?.GrantId is not { } grantId || pending.Status is not (PendingStatus.Approved or PendingStatus.Released or PendingStatus.Redeemed))
        {
            return Problems.Of(StatusCodes.Status404NotFound, "agent_request_not_found");
        }
        using (await gate.Enter(ct))
        {
            await db.AgentGrants.Where(x => x.Id == grantId).ExecuteUpdateAsync(x => x.SetProperty(g => g.CopyComplete, request.Complete), ct);
        }
        authorizations.Release(id);
        return Results.NoContent();
    }

    private static IResult Decline(Guid id, AgentAuthorizations authorizations, AuditLog audit, HttpContext http)
    {
        if (!authorizations.Decline(id))
        {
            return Problems.Of(StatusCodes.Status404NotFound, "agent_request_not_found");
        }
        var device = DeviceAuthentication.Current(http);
        audit.AgentRequestDeclined(device.Id);
        return Results.NoContent();
    }

    private static async Task<IResult> List(JournalDb db, AgentAuthorizations authorizations, WriteGate gate, TimeProvider clock, AuditLog audit, CancellationToken ct)
    {
        await RemoveUnfinished(db, authorizations, gate, audit, ct);
        await PurgeExpired(db, gate, clock, audit, ct);
        var now = clock.GetUtcNow();
        var connected = await AgentTokens.Connected(db, now, ct);
        // SQLite can't order by DateTimeOffset; there are at most MaximumGrants.
        var grants = (await db.AgentGrants.AsNoTracking().ToListAsync(ct)).OrderBy(x => x.CreatedAt);
        return Results.Ok(grants.Select(x => new AgentGrantSummary(x.Id,
            x.State == AgentGrantState.Pending ? "pending" : connected.Contains(x.Id) ? "active" : "needsReconnect",
            x.ClientName, x.ClientId, x.RedirectHost, x.CreatedAt, x.ExpiresAt, x.LastUsedAt, x.UpdatedAt, x.CopyComplete, x.Metadata, x.Revision)));
    }

    // Changes an agent's settings (name, journals, end) as the owner's device sealed them, only from the revision the
    // device read. Items of journals no longer shared are emptied in the same transaction, so narrowing takes effect
    // before the next upload; devices that planned with an older revision are refused (agent_settings_changed).
    private static async Task<IResult> Change(Guid id, AgentChange request, JournalDb db, WriteGate gate, TimeProvider clock, AuditLog audit, HttpContext http)
    {
        var ct = http.RequestAborted;
        var now = clock.GetUtcNow();
        if (request.Revision is not { } revision || request.Metadata is null || request.Metadata.Length > MaximumMetadataLength ||
            !Secrets.IsBase64(request.Metadata, 1, MaximumMetadataLength) || request.ExpiresAt is { } ends && (ends <= now || ends > now + LongestExpiry) ||
            request.RemovedItems is { } removed && (removed.Count > MaximumItemsPerGrant || !removed.All(x => HexPattern().IsMatch(x))))
        {
            return Problems.Of(StatusCodes.Status400BadRequest, "invalid_agent");
        }
        using var lease = await gate.Enter(ct);
        if (!await DeviceAuthentication.IsStillAuthorized(http, db))
        {
            return Problems.Of(StatusCodes.Status401Unauthorized, "unauthorized");
        }
        var grant = await db.AgentGrants.SingleOrDefaultAsync(x => x.Id == id, ct);
        if (grant is null)
        {
            return Problems.Of(StatusCodes.Status404NotFound, "agent_not_found");
        }
        if (grant.ExpiresAt <= now)
        {
            return Problems.Of(StatusCodes.Status409Conflict, "agent_expired");
        }
        if (grant.Revision != revision)
        {
            return Problems.Of(StatusCodes.Status409Conflict, "agent_settings_changed");
        }
        await using var transaction = await db.Database.BeginTransactionAsync(ct);
        grant.Metadata = request.Metadata;
        grant.ExpiresAt = request.ExpiresAt;
        grant.Revision = revision + 1;
        if (request.RemovedItems is { Count: > 0 } items)
        {
            var ids = items.Distinct(StringComparer.Ordinal).ToList();
            // Emptied at version 0, so sharing the journal again later publishes it whatever the device's cursor; devices
            // still planning with the earlier revision can't upload over it.
            foreach (var item in await db.AgentItems.Where(x => x.GrantId == id && ids.Contains(x.ItemId) && x.Payload != null).ToListAsync(ct))
            {
                item.Payload = null;
                item.Version = 0;
                item.Sequence = ++grant.NextSequence;
            }
        }
        // A sooner end applies to the tokens already issued too.
        if (request.ExpiresAt is { } end)
        {
            await db.OAuthTokens.Where(x => x.GrantId == id && x.ExpiresAt > end).ExecuteUpdateAsync(x => x.SetProperty(t => t.ExpiresAt, end), ct);
        }
        grant.UpdatedAt = now;
        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);
        return Results.Ok(new
        {
            revision = grant.Revision
        });
    }

    private static async Task<IResult> Revoke(Guid id, JournalDb db, WriteGate gate, AuditLog audit, AgentAuthorizations authorizations, HttpContext http)
    {
        // Stopping a pending agent declines its request, so its browser page says so.
        authorizations.DeclineGrant(id);
        var ct = http.RequestAborted;
        var device = DeviceAuthentication.Current(http);
        using (await gate.Enter(ct))
        {
            if (!await DeviceAuthentication.IsStillAuthorized(http, db))
            {
                return Problems.Of(StatusCodes.Status401Unauthorized, "unauthorized");
            }
            if (!await Delete(db, id, ct))
            {
                return Problems.Of(StatusCodes.Status404NotFound, "agent_not_found");
            }
            // The deleted key wraps shouldn't stay in the write-ahead log either.
            await db.Database.ExecuteSqlRawAsync("PRAGMA wal_checkpoint(TRUNCATE)", ct);
        }
        audit.AgentRevoked(id, device.Id);
        return Results.NoContent();
    }

    private static async Task<IResult> Manifest(Guid id, long? after, int? limit, JournalDb db, CancellationToken ct)
    {
        if (after is < 0)
        {
            return Problems.Of(StatusCodes.Status400BadRequest, "invalid_cursor");
        }
        if (!await db.AgentGrants.AnyAsync(x => x.Id == id, ct))
        {
            return Problems.Of(StatusCodes.Status404NotFound, "agent_not_found");
        }
        var cursor = after ?? 0;
        var size = Math.Clamp(limit ?? 1000, 1, 5000);
        var items = await db.AgentItems.AsNoTracking().Where(x => x.GrantId == id && x.Sequence > cursor).OrderBy(x => x.Sequence).Take(size + 1)
            .Select(x => new ManifestItem(x.ItemId, x.Version, x.Digest, x.Payload == null, x.Sequence)).ToListAsync(ct);
        var hasMore = items.Count > size;
        if (hasMore)
        {
            items.RemoveAt(items.Count - 1);
        }
        return Results.Ok(new
        {
            items,
            cursor = items.Count > 0 ? items[^1].Sequence : cursor,
            hasMore
        });
    }

    private static async Task<IResult> Upload(Guid id, UploadItemsRequest request, JournalDb db, WriteGate gate, TimeProvider clock, AuditLog audit, HttpContext http)
    {
        var ct = http.RequestAborted;
        if (!ValidUpload(request) || request.Revision is null)
        {
            return Problems.Of(StatusCodes.Status400BadRequest, "invalid_agent_item");
        }
        using var lease = await gate.Enter(ct);
        if (!await DeviceAuthentication.IsStillAuthorized(http, db))
        {
            return Problems.Of(StatusCodes.Status401Unauthorized, "unauthorized");
        }
        var grant = await db.AgentGrants.SingleOrDefaultAsync(x => x.Id == id, ct);
        if (grant is null)
        {
            return Problems.Of(StatusCodes.Status404NotFound, "agent_not_found");
        }
        var now = clock.GetUtcNow();
        if (grant.ExpiresAt <= now)
        {
            await Delete(db, id, ct);
            audit.AgentExpired(id);
            return Problems.Of(StatusCodes.Status409Conflict, "agent_expired");
        }
        // The device planned with other settings (another device changed the journals): it reads them again.
        if (grant.Revision != request.Revision)
        {
            return Problems.Of(StatusCodes.Status409Conflict, "agent_settings_changed");
        }
        await using var transaction = await db.Database.BeginTransactionAsync(ct);
        var ids = request.Items.Select(x => x.Id).ToList();
        var existing = await db.AgentItems.Where(x => x.GrantId == id && ids.Contains(x.ItemId)).ToDictionaryAsync(x => x.ItemId, ct);
        var stale = new List<ManifestItem>();
        var added = 0;
        long bytes = 0;
        foreach (var item in request.Items)
        {
            existing.TryGetValue(item.Id, out var current);
            // The highest version wins; an equal one keeps what the server has, whatever order devices upload in.
            if (current is not null && current.Version >= item.Version)
            {
                stale.Add(new ManifestItem(current.ItemId, current.Version, current.Digest, current.Payload is null, current.Sequence));
                continue;
            }
            if (current is null && item.Payload is null)
            {
                continue;
            }
            if (current is null)
            {
                current = new AgentItem { GrantId = id, ItemId = item.Id };
                db.AgentItems.Add(current);
                added++;
            }
            bytes += (item.Payload?.Length ?? 0) - (current.Payload?.Length ?? 0);
            current.Version = item.Version;
            current.Digest = item.Digest;
            current.Payload = item.Payload;
            current.Sequence = ++grant.NextSequence;
        }
        if (added > 0 || bytes > 0)
        {
            var count = await db.AgentItems.CountAsync(x => x.GrantId == id, ct);
            var stored = await db.AgentItems.Where(x => x.GrantId == id && x.Payload != null).SumAsync(x => (long)x.Payload!.Length, ct);
            if (count + added > MaximumItemsPerGrant || stored + bytes > MaximumBytesPerGrant)
            {
                return Problems.Of(StatusCodes.Status409Conflict, "agent_quota");
            }
        }
        grant.UpdatedAt = now;
        if (request.Complete is { } complete)
        {
            grant.CopyComplete = complete;
        }
        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);
        return Results.Ok(new
        {
            stale
        });
    }

    private static async Task<IResult> Activity(Guid id, JournalDb db, CancellationToken ct)
    {
        if (!await db.AgentGrants.AnyAsync(x => x.Id == id, ct))
        {
            return Problems.Of(StatusCodes.Status404NotFound, "agent_not_found");
        }
        var events = await db.AgentEvents.AsNoTracking().Where(x => x.GrantId == id).OrderByDescending(x => x.Id).Take(MaximumEvents)
            .Select(x => new { x.At, x.Tool }).ToListAsync(ct);
        return Results.Ok(events);
    }

    // Approved requests whose code was never redeemed leave a pending grant and its copy; they're deleted, and so are
    // pending grants a restart orphaned (the requests lived only in memory).
    public static async Task RemoveUnfinished(JournalDb db, AgentAuthorizations authorizations, WriteGate gate, AuditLog audit, CancellationToken ct, bool all = false)
    {
        ArgumentNullException.ThrowIfNull(db);
        ArgumentNullException.ThrowIfNull(authorizations);
        ArgumentNullException.ThrowIfNull(gate);
        ArgumentNullException.ThrowIfNull(audit);
        // Including redeemed codes whose exchange failed (a wrong verifier or client): their grant is still pending.
        // Only grants still pending are deleted; an exchange that succeeded made its grant active.
        var expired = authorizations.TakeExpired().Where(x => x.GrantId is not null && !x.Reconnect).Select(x => x.GrantId!.Value).ToList();
        if (expired.Count == 0 && !all)
        {
            return;
        }
        using (await gate.Enter(ct))
        {
            var orphaned = all ? await db.AgentGrants.Where(x => x.State == AgentGrantState.Pending).Select(x => x.Id).ToListAsync(ct) : [];
            foreach (var id in expired.Concat(orphaned).Distinct())
            {
                if (await db.AgentGrants.AnyAsync(x => x.Id == id && x.State == AgentGrantState.Pending, ct))
                {
                    await Delete(db, id, ct);
                }
            }
        }
    }

    // When a grant's access ends, its tokens, key wraps and copy go at once; the grant and its activity stay 30 days so
    // the owner can see why the agent stopped. Also removes key wraps of refresh tokens replaced more than the grace
    // ago, expired tokens and registrations unused for 30 days, then checkpoints the log so deleted key material
    // doesn't stay in it (every connection uses secure_delete).
    public static async Task PurgeExpired(JournalDb db, WriteGate gate, TimeProvider clock, AuditLog audit, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(db);
        ArgumentNullException.ThrowIfNull(gate);
        ArgumentNullException.ThrowIfNull(clock);
        ArgumentNullException.ThrowIfNull(audit);
        var now = clock.GetUtcNow();
        using var lease = await gate.Enter(ct);
        var removedKeys = false;
        // SQLite can't compare DateTimeOffset values; these tables are small.
        foreach (var grant in (await db.AgentGrants.AsNoTracking().Select(x => new { x.Id, x.ExpiresAt }).ToListAsync(ct)).Where(x => x.ExpiresAt <= now))
        {
            if (grant.ExpiresAt!.Value + TimeSpan.FromDays(30) <= now)
            {
                await Delete(db, grant.Id, ct);
                removedKeys = true;
            }
            else if (await db.OAuthTokens.AnyAsync(x => x.GrantId == grant.Id, ct) || await db.AgentItems.AnyAsync(x => x.GrantId == grant.Id, ct))
            {
                await db.OAuthTokens.Where(x => x.GrantId == grant.Id).ExecuteDeleteAsync(ct);
                await db.AgentItems.Where(x => x.GrantId == grant.Id).ExecuteDeleteAsync(ct);
                removedKeys = true;
                audit.AgentExpired(grant.Id);
            }
        }
        foreach (var token in await db.OAuthTokens.ToListAsync(ct))
        {
            if (token.ExpiresAt <= now)
            {
                db.OAuthTokens.Remove(token);
                removedKeys = true;
            }
            else if (token.ReplacedAt is { } replaced && now - replaced > AgentTokens.RefreshGrace && token.WrappedKey.Length > 0)
            {
                token.WrappedKey = [];
                removedKeys = true;
            }
        }
        foreach (var client in (await db.OAuthClients.Where(x => !x.Used).ToListAsync(ct)).Where(x => now - x.CreatedAt > TimeSpan.FromDays(30)))
        {
            db.OAuthClients.Remove(client);
        }
        await db.SaveChangesAsync(ct);
        if (removedKeys)
        {
            await db.Database.ExecuteSqlRawAsync("PRAGMA wal_checkpoint(TRUNCATE)", ct);
        }
    }

    // Removes a grant and everything that belongs to it. Returns false when there was none.
    public static async Task<bool> Delete(JournalDb db, Guid id, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(db);
        await db.OAuthTokens.Where(x => x.GrantId == id).ExecuteDeleteAsync(ct);
        await db.AgentItems.Where(x => x.GrantId == id).ExecuteDeleteAsync(ct);
        await db.AgentEvents.Where(x => x.GrantId == id).ExecuteDeleteAsync(ct);
        return await db.AgentGrants.Where(x => x.Id == id).ExecuteDeleteAsync(ct) > 0;
    }

    // Everything of agent access, for restoring a backup and turning on encryption.
    public static async Task RemoveAll(JournalDb db, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(db);
        await db.OAuthTokens.ExecuteDeleteAsync(ct);
        await db.AgentItems.ExecuteDeleteAsync(ct);
        await db.AgentEvents.ExecuteDeleteAsync(ct);
        await db.AgentGrants.ExecuteDeleteAsync(ct);
        await db.OAuthClients.ExecuteDeleteAsync(ct);
    }

    private static bool ValidUpload(UploadItemsRequest request)
    {
        if (request.Items.Count > MaximumItemsPerUpload || request.Items.Select(x => x.Id).Distinct(StringComparer.Ordinal).Count() != request.Items.Count)
        {
            return false;
        }
        return request.Items.All(item => HexPattern().IsMatch(item.Id) && HexPattern().IsMatch(item.Digest) && item.Version >= 0 &&
            (item.Payload is null || Secrets.IsBase64(item.Payload, 29, MaximumPayloadBytes)));
    }
}

public sealed record AgentRequestSummary(Guid Id, string ClientName, string ClientId, string? IdentifiedAs, string RedirectHost, string RedirectKind, DateTimeOffset RequestedAt, DateTimeOffset ExpiresAt, Guid? ReconnectCandidate);
// Reconnecting an agent sends no metadata (its settings don't change), so the field may be left out.
public sealed record AgentApproval(int Number, Guid GrantId, string WrappedKey, string GrantSecret, string? Metadata = null, DateTimeOffset? ExpiresAt = null);
public sealed record AgentChange(long? Revision, string? Metadata, DateTimeOffset? ExpiresAt = null, IReadOnlyList<string>? RemovedItems = null);
public sealed record AgentReady(bool Complete);
public sealed record AgentGrantSummary(Guid Id, string State, string ClientName, string ClientId, string RedirectHost, DateTimeOffset CreatedAt, DateTimeOffset? ExpiresAt, DateTimeOffset? LastUsedAt, DateTimeOffset? UpdatedAt, bool CopyComplete, string Metadata, long Revision);
// A deletion has no payload; clients may send null or leave the field out.
public sealed record UploadItem(string Id, long Version, string Digest, string? Payload = null);
public sealed record UploadItemsRequest(IReadOnlyList<UploadItem> Items, bool? Complete = null, long? Revision = null);
public sealed record ManifestItem(string Id, long Version, string Digest, bool Deleted, long Sequence);
