using System.Security.Cryptography;
using System.Text;

namespace Journal.Api.Security;

// Authorization requests waiting for the owner to approve them in My Journal (protocol/agent-access-server.md,
// Authorization page and Approval in the app). They are kept only in memory: the one-time secret an approving device
// sends lives here until its code is redeemed, and a restart forgets every pending request.
public sealed class AgentAuthorizations
{
    public const int MaximumPending = 20;
    public const int MaximumPendingPerAddress = 3;
    public static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(10);
    public static readonly TimeSpan CodeLifetime = TimeSpan.FromSeconds(60);
    // After approval: how long the device has to upload the first copy before the server releases the code itself,
    // and how much longer an approved request lives.
    public static readonly TimeSpan ReleaseDelay = TimeSpan.FromSeconds(15);
    public static readonly TimeSpan ApprovedExtension = TimeSpan.FromMinutes(5);
    private readonly Lock gate = new();
    private readonly List<PendingAuthorization> pending = [];
    // Numbers of requests evicted to make room, kept out of use until those requests would have expired, so a page
    // the owner is still looking at never shows a number that now belongs to someone else's request.
    private readonly Dictionary<int, DateTimeOffset> quarantined = [];
    private readonly TimeProvider clock;
    private readonly Func<int> nextNumber;

    public AgentAuthorizations(TimeProvider clock)
        : this(clock, () => RandomNumberGenerator.GetInt32(10, 100))
    {
    }

    // Tests choose the numbers.
    public AgentAuthorizations(TimeProvider clock, Func<int> nextNumber)
    {
        this.clock = clock;
        this.nextNumber = nextNumber;
    }

    public enum StartResult
    {
        Started,
        Busy,
    }

    public enum ApproveResult
    {
        Approved,
        NotFound,
        // The number the owner entered isn't the one the page shows: the request is declined.
        Mismatch,
    }

    public (StartResult Result, PendingAuthorization? Request) Start(AuthorizationRequestDetails details, string clientAddress)
    {
        ArgumentNullException.ThrowIfNull(details);
        lock (gate)
        {
            RemoveExpired();
            // A client asking again from the same address replaces its waiting request, so retries don't pile up.
            foreach (var earlier in pending.Where(x => x.Status == PendingStatus.Waiting && x.ClientAddress == clientAddress &&
                string.Equals(x.Details.Client.ClientId, details.Client.ClientId, StringComparison.Ordinal)))
            {
                earlier.Status = PendingStatus.Replaced;
                earlier.Forget();
            }
            if (pending.Count(x => x.ClientAddress == clientAddress && x.Status == PendingStatus.Waiting) >= MaximumPendingPerAddress)
            {
                return (StartResult.Busy, null);
            }
            // When full, a request nobody opened makes room: the oldest from the address (or IPv6 /64) with the most
            // waiting requests, so one flooding source evicts its own requests first.
            if (pending.Count >= MaximumPending)
            {
                var evictable = pending.Where(x => x.Status is PendingStatus.Waiting or PendingStatus.Replaced && !x.LookedUp).ToList();
                var oldest = evictable.GroupBy(x => x.ClientAddress, StringComparer.Ordinal)
                    .OrderByDescending(g => pending.Count(x => x.ClientAddress == g.Key && x.Status == PendingStatus.Waiting)).ThenByDescending(g => g.Count())
                    .FirstOrDefault()?.MinBy(x => x.ExpiresAt);
                if (oldest is null)
                {
                    return (StartResult.Busy, null);
                }
                pending.Remove(oldest);
                oldest.Forget();
                quarantined[oldest.Number] = oldest.ExpiresAt;
            }
            // Numbers of every request still kept (waiting, replaced or decided) and of evicted ones stay out of use.
            var now = clock.GetUtcNow();
            foreach (var released in quarantined.Where(x => x.Value <= now).Select(x => x.Key).ToList())
            {
                quarantined.Remove(released);
            }
            var used = pending.Select(x => x.Number).Concat(quarantined.Keys).ToHashSet();
            if (used.Count >= 90)
            {
                return (StartResult.Busy, null);
            }
            int number;
            do
            {
                number = nextNumber();
            }
            while (number is < 10 or > 99 || used.Contains(number));
            var request = new PendingAuthorization(Guid.NewGuid(), number, Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(32)), details, clientAddress, now + Lifetime);
            pending.Add(request);
            return (StartResult.Started, request);
        }
    }

    // Requests waiting for the owner, newest first. Listing them doesn't keep them from being evicted.
    public IReadOnlyList<PendingAuthorization> Waiting()
    {
        lock (gate)
        {
            RemoveExpired();
            return pending.Where(x => x.Status == PendingStatus.Waiting).OrderByDescending(x => x.RequestedAt).ToList();
        }
    }

    // A waiting request the owner opened; from now on it's never evicted to make room.
    public PendingAuthorization? Open(Guid id)
    {
        lock (gate)
        {
            RemoveExpired();
            var request = pending.SingleOrDefault(x => x.Id == id && x.Status == PendingStatus.Waiting);
            request?.LookedUp = true;
            return request;
        }
    }

    public PendingAuthorization? ById(Guid id)
    {
        lock (gate)
        {
            RemoveExpired();
            return pending.SingleOrDefault(x => x.Id == id);
        }
    }

    public PendingAuthorization? ByHandle(string? handle)
    {
        lock (gate)
        {
            return handle is { Length: 64 } ? pending.SingleOrDefault(x => CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(x.BrowserHandle), Encoding.ASCII.GetBytes(handle))) : null;
        }
    }

    // Records the device's approval if the owner entered the number the page shows; a wrong number declines the
    // request, so it can't be guessed.
    public ApproveResult Approve(Guid id, int number, Guid grantId, byte[] secret, byte[] wrappedKey, bool reconnect)
    {
        lock (gate)
        {
            var now = clock.GetUtcNow();
            var request = pending.SingleOrDefault(x => x.Id == id && x.Status == PendingStatus.Waiting && x.ExpiresAt > now);
            if (request is null)
            {
                return ApproveResult.NotFound;
            }
            if (request.Number != number)
            {
                request.Status = PendingStatus.Declined;
                return ApproveResult.Mismatch;
            }
            request.Status = PendingStatus.Approved;
            request.GrantId = grantId;
            request.Secret = secret;
            request.WrappedKey = wrappedKey;
            request.Reconnect = reconnect;
            request.ApprovedAt = now;
            request.ExpiresAt += ApprovedExtension;
            return ApproveResult.Approved;
        }
    }

    // Releases the code of an approved request once its device said the copy is ready, or once the device had
    // enough time (it may have locked or gone to the background).
    public void ReleaseIfDue(PendingAuthorization request)
    {
        ArgumentNullException.ThrowIfNull(request);
        if (request.Status == PendingStatus.Approved && request.ApprovedAt + ReleaseDelay <= clock.GetUtcNow())
        {
            Release(request.Id);
        }
    }

    // Issues the authorization code once the first copy is on the server; the browser is then sent back to the client.
    public string? Release(Guid id)
    {
        lock (gate)
        {
            var request = pending.SingleOrDefault(x => x.Id == id && x.Status == PendingStatus.Approved);
            if (request is null)
            {
                return null;
            }
            var code = Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(32));
            request.CodeHash = Secrets.Hash(code);
            request.Status = PendingStatus.Released;
            request.Code = code;
            return code;
        }
    }

    // The code's short lifetime starts when the browser first receives it: a browser suspended while the owner
    // approves on the same iPhone collects it later. It never outlives the request.
    public void Delivered(PendingAuthorization request)
    {
        ArgumentNullException.ThrowIfNull(request);
        lock (gate)
        {
            if (request.Status == PendingStatus.Released && request.DeliveredAt is null)
            {
                var now = clock.GetUtcNow();
                request.DeliveredAt = now;
                request.ExpiresAt = now + CodeLifetime < request.ExpiresAt ? now + CodeLifetime : request.ExpiresAt;
            }
        }
    }

    // A pending agent the owner stopped in the app: its browser page shows that access was declined.
    public void DeclineGrant(Guid grantId)
    {
        lock (gate)
        {
            foreach (var request in pending.Where(x => x.GrantId == grantId && x.Status is PendingStatus.Approved or PendingStatus.Released))
            {
                request.Status = PendingStatus.Declined;
                request.Forget();
            }
        }
    }

    public bool Decline(Guid id)
    {
        lock (gate)
        {
            var request = pending.SingleOrDefault(x => x.Id == id && x.Status == PendingStatus.Waiting);
            if (request is null)
            {
                return false;
            }
            request.Status = PendingStatus.Declined;
            return true;
        }
    }

    // Takes a released code for redemption; it can be taken once. A second attempt returns the request marked reused.
    public (PendingAuthorization? Request, bool Reused) Redeem(string? code)
    {
        if (code is null || code.Length != 64)
        {
            return (null, false);
        }
        var hash = Secrets.Hash(code);
        lock (gate)
        {
            var request = pending.SingleOrDefault(x => x.CodeHash is { } stored && CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(stored), Encoding.ASCII.GetBytes(hash)));
            if (request is null)
            {
                return (null, false);
            }
            if (request.Status == PendingStatus.Redeemed)
            {
                return (request, true);
            }
            if (request.Status != PendingStatus.Released || request.ExpiresAt <= clock.GetUtcNow())
            {
                return (null, false);
            }
            request.Status = PendingStatus.Redeemed;
            // Kept briefly so a replayed code is recognized, without its secret.
            request.ExpiresAt = clock.GetUtcNow() + Lifetime;
            return (request, false);
        }
    }

    // Removes and returns requests whose time ran out; approved ones that were never redeemed leave a pending grant for
    // the caller to delete.
    public IReadOnlyList<PendingAuthorization> TakeExpired()
    {
        lock (gate)
        {
            var now = clock.GetUtcNow();
            var expired = pending.Where(x => x.ExpiresAt <= now).ToList();
            foreach (var request in expired)
            {
                request.Forget();
                pending.Remove(request);
            }
            return expired;
        }
    }

    private void RemoveExpired()
    {
        var now = clock.GetUtcNow();
        // Approved requests stay until the sweep deletes their pending grants.
        foreach (var request in pending.Where(x => x.ExpiresAt <= now && x.GrantId is null).ToList())
        {
            request.Forget();
            pending.Remove(request);
        }
    }
}

public enum PendingStatus
{
    Waiting,
    Approved,
    Released,
    Declined,
    Redeemed,
    // A newer request from the same client and address took its place.
    Replaced,
}

// What the client asked for, validated.
// RedirectUriGiven: the request named its redirect URI, so the token request must repeat it.
public sealed record AuthorizationRequestDetails(OAuthClientInfo Client, string RedirectUri, bool RedirectUriGiven, string? State, string CodeChallenge, string Resource, string Scope, string Issuer);

public sealed class PendingAuthorization(Guid id, int number, string browserHandle, AuthorizationRequestDetails details, string clientAddress, DateTimeOffset expiresAt)
{
    public Guid Id { get; } = id;
    // The number the page shows; the owner enters it in My Journal to approve.
    public int Number { get; } = number;
    // Once released, the authorization code (only its hash is compared).
    public string Code { get; set; } = "";
    public string BrowserHandle { get; } = browserHandle;
    public DateTimeOffset RequestedAt { get; } = expiresAt - AgentAuthorizations.Lifetime;
    public AuthorizationRequestDetails Details { get; } = details;
    public string ClientAddress { get; } = clientAddress;
    public DateTimeOffset ExpiresAt { get; set; } = expiresAt;
    public PendingStatus Status { get; set; } = PendingStatus.Waiting;
    public bool LookedUp
    {
        get; set;
    }
    public Guid? GrantId
    {
        get; set;
    }
    public bool Reconnect
    {
        get; set;
    }
    public byte[]? Secret
    {
        get; set;
    }
    public byte[]? WrappedKey
    {
        get; set;
    }
    public DateTimeOffset? ApprovedAt
    {
        get; set;
    }
    public DateTimeOffset? DeliveredAt
    {
        get; set;
    }
    // The token family issued when the code was redeemed; revoked if the code is presented again.
    public Guid? Family
    {
        get; set;
    }
    public string? CodeHash
    {
        get; set;
    }

    public void Forget()
    {
        if (Secret is not null)
        {
            CryptographicOperations.ZeroMemory(Secret);
        }
        Secret = null;
        WrappedKey = null;
    }
}
