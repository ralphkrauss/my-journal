using System.Security.Cryptography;
using Journal.Api.Data;
using Microsoft.EntityFrameworkCore;

namespace Journal.Api.Security;

// Issues, checks, rotates and revokes agent tokens (protocol/agent-access-server.md, Keys and tokens).
public sealed class AgentTokens(TimeProvider clock, AuditLog audit)
{
    public const string Scope = "journals:read";
    public static readonly TimeSpan AccessLifetime = TimeSpan.FromHours(1);
    public static readonly TimeSpan RefreshIdleLifetime = TimeSpan.FromDays(30);
    public static readonly TimeSpan RefreshGrace = TimeSpan.FromSeconds(60);

    public sealed record Issued(string AccessToken, string RefreshToken, int ExpiresIn);

    // An access token that passed every check, with the grant's copy key for this request only.
    public sealed class Access(AgentGrant grant, byte[] copyKey) : IDisposable
    {
        public AgentGrant Grant { get; } = grant;
        public byte[] CopyKey { get; } = copyKey;
        public void Dispose() => CryptographicOperations.ZeroMemory(CopyKey);
    }

    public enum Refusal
    {
        Invalid,
        InsufficientScope,
    }

    // Issues a new access and refresh token for a grant. Each gets its own secret; the copy key is stored wrapped
    // under it and nowhere else. Call under the write gate.
    public async Task<Issued> Issue(JournalDb db, AgentGrant grant, byte[] copyKey, string resource, Guid family, CancellationToken ct, Guid? parent = null)
    {
        ArgumentNullException.ThrowIfNull(db);
        ArgumentNullException.ThrowIfNull(grant);
        var now = clock.GetUtcNow();
        var accessExpiry = Earlier(now + AccessLifetime, grant.ExpiresAt);
        var refreshExpiry = Earlier(now + RefreshIdleLifetime, grant.ExpiresAt);
        var access = AgentToken.New(OAuthTokenKind.Access);
        var refresh = AgentToken.New(OAuthTokenKind.Refresh);
        db.OAuthTokens.Add(Row(access, grant.Id, copyKey, resource, accessExpiry, family));
        var refreshRow = Row(refresh, grant.Id, copyKey, resource, refreshExpiry, family);
        refreshRow.Parent = parent;
        db.OAuthTokens.Add(refreshRow);
        await db.SaveChangesAsync(ct);
        var seconds = (int)Math.Max(1, Math.Floor((accessExpiry - now).TotalSeconds));
        return new Issued(access.Encoded, refresh.Encoded, seconds);
    }

    private static OAuthToken Row(AgentToken token, Guid grantId, byte[] copyKey, string resource, DateTimeOffset expiresAt, Guid family) => new()
    {
        Id = token.Id,
        GrantId = grantId,
        Kind = token.Kind,
        VerifierHash = token.VerifierHash,
        WrappedKey = AgentKeys.WrapForToken(copyKey, token.Secret, grantId, token.Id),
        Resource = resource,
        Scope = Scope,
        ExpiresAt = expiresAt,
        Family = family,
    };

    private static DateTimeOffset Earlier(DateTimeOffset value, DateTimeOffset? limit) => limit is { } end && end < value ? end : value;

    // Checks an access token for this resource and unwraps the copy key. Null with a refusal when it isn't valid.
    public async Task<(Access? Access, Refusal Refusal)> Check(JournalDb db, string? authorization, string resource, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(db);
        if (authorization is null || !authorization.StartsWith("Bearer ", StringComparison.Ordinal) ||
            AgentToken.Parse(authorization[7..].Trim(), OAuthTokenKind.Access) is not { } token)
        {
            return (null, Refusal.Invalid);
        }
        var now = clock.GetUtcNow();
        var row = await db.OAuthTokens.AsNoTracking().SingleOrDefaultAsync(x => x.Id == token.Id, ct);
        if (row is null || row.Kind != OAuthTokenKind.Access || row.Revoked || !token.Matches(row.VerifierHash) || row.ExpiresAt <= now ||
            !string.Equals(row.Resource, resource, StringComparison.Ordinal))
        {
            return (null, Refusal.Invalid);
        }
        var grant = await db.AgentGrants.AsNoTracking().SingleOrDefaultAsync(x => x.Id == row.GrantId, ct);
        if (grant is null || grant.State != AgentGrantState.Active || grant.ExpiresAt <= now)
        {
            return (null, Refusal.Invalid);
        }
        if (!row.Scope.Split(' ').Contains(Scope))
        {
            return (null, Refusal.InsufficientScope);
        }
        var key = AgentKeys.UnwrapForToken(row.WrappedKey, token.Secret, grant.Id, row.Id);
        return key is null ? (null, Refusal.Invalid) : (new Access(grant, key), Refusal.Invalid);
    }

    public enum RefreshFailure
    {
        None,
        InvalidGrant,
        InvalidTarget,
    }

    // Rotates a refresh token. A replaced token still works within the grace; later reuse revokes the family, and the
    // grant then needs to reconnect. Call under the write gate.
    public async Task<(Issued? Issued, RefreshFailure Failure)> Refresh(JournalDb db, string? presented, string? requestedResource, string resource, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(db);
        if (requestedResource is not null && !PublicOrigin.SameResource(requestedResource, resource))
        {
            return (null, RefreshFailure.InvalidTarget);
        }
        if (AgentToken.Parse(presented, OAuthTokenKind.Refresh) is not { } token)
        {
            return (null, RefreshFailure.InvalidGrant);
        }
        var now = clock.GetUtcNow();
        var row = await db.OAuthTokens.SingleOrDefaultAsync(x => x.Id == token.Id, ct);
        if (row is null || row.Kind != OAuthTokenKind.Refresh || !token.Matches(row.VerifierHash))
        {
            return (null, RefreshFailure.InvalidGrant);
        }
        // A token that is no longer usable — revoked, or replaced longer ago than the grace — presented again: someone else
        // may hold the family (RFC 9700 §4.14.2).
        if (row.Revoked || (row.ReplacedAt is { } replaced && now - replaced > RefreshGrace))
        {
            await RevokeFamily(db, row.Family, ct);
            audit.RefreshTokenReused(row.GrantId);
            return (null, RefreshFailure.InvalidGrant);
        }
        if (row.ExpiresAt <= now || !string.Equals(row.Resource, resource, StringComparison.Ordinal))
        {
            return (null, RefreshFailure.InvalidGrant);
        }
        var grant = await db.AgentGrants.AsNoTracking().SingleOrDefaultAsync(x => x.Id == row.GrantId, ct);
        if (grant is null || grant.State != AgentGrantState.Active || grant.ExpiresAt <= now)
        {
            return (null, RefreshFailure.InvalidGrant);
        }
        var key = AgentKeys.UnwrapForToken(row.WrappedKey, token.Secret, grant.Id, row.Id);
        if (key is null)
        {
            return (null, RefreshFailure.InvalidGrant);
        }
        try
        {
            // The replaced token keeps its wrap only for the grace period; the sweep then removes the wrap and keeps the
            // row, so later reuse is still recognized.
            row.ReplacedAt ??= now;
            // Tokens issued from the same parent during its grace: once one is used, the others go.
            if (row.Parent is { } parent)
            {
                await db.OAuthTokens.Where(x => x.Parent == parent && x.Id != row.Id && x.Kind == OAuthTokenKind.Refresh)
                    .ExecuteUpdateAsync(x => x.SetProperty(t => t.Revoked, true).SetProperty(t => t.WrappedKey, Array.Empty<byte>()), ct);
            }
            var issued = await Issue(db, grant, key, resource, row.Family, ct, row.Id);
            return (issued, RefreshFailure.None);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(key);
        }
    }

    // Revokes every token of a family: their wraps go at once; the rows stay until they would have expired, so a
    // revoked refresh token presented later is still recognized as reuse.
    public static async Task RevokeFamily(JournalDb db, Guid family, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(db);
        await db.OAuthTokens.Where(x => x.Family == family)
            .ExecuteUpdateAsync(x => x.SetProperty(t => t.Revoked, true).SetProperty(t => t.WrappedKey, Array.Empty<byte>()), ct);
    }

    // RFC 7009: revokes the presented token; a refresh token takes its family with it. Unknown tokens are ignored.
    public async Task Revoke(JournalDb db, string? presented, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(db);
        foreach (var kind in new[] { OAuthTokenKind.Refresh, OAuthTokenKind.Access })
        {
            if (AgentToken.Parse(presented, kind) is not { } token)
            {
                continue;
            }
            var row = await db.OAuthTokens.AsNoTracking().SingleOrDefaultAsync(x => x.Id == token.Id && x.Kind == kind, ct);
            if (row is null || !token.Matches(row.VerifierHash))
            {
                return;
            }
            if (kind == OAuthTokenKind.Refresh)
            {
                await RevokeFamily(db, row.Family, ct);
            }
            else
            {
                await db.OAuthTokens.Where(x => x.Id == row.Id)
                    .ExecuteUpdateAsync(x => x.SetProperty(t => t.Revoked, true).SetProperty(t => t.WrappedKey, Array.Empty<byte>()), ct);
            }
            return;
        }
    }

    // A grant needs to reconnect when no refresh token of it is left.
    public static async Task<HashSet<Guid>> Connected(JournalDb db, DateTimeOffset now, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(db);
        var rows = await db.OAuthTokens.AsNoTracking().Where(x => x.Kind == OAuthTokenKind.Refresh && x.ReplacedAt == null && !x.Revoked)
            .Select(x => new { x.GrantId, x.ExpiresAt }).ToListAsync(ct);
        // SQLite can't compare DateTimeOffset values; there are few tokens.
        return rows.Where(x => x.ExpiresAt > now).Select(x => x.GrantId).ToHashSet();
    }
}
