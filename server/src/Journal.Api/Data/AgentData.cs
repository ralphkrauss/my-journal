namespace Journal.Api.Data;

// Agent access through the server (protocol/agent-access-server.md). A grant is what the owner approved in the app for
// one MCP client: which journals (in the sealed metadata) and until when. It is a separate principal from devices.
public sealed class AgentGrant
{
    public Guid Id
    {
        get; set;
    }
    // Name, client name, journals, end date and the copy's key, sealed by the approving device like a record.
    public string Metadata { get; set; } = "";
    // AgentGrantState: pending until its authorization code is redeemed.
    public string State { get; set; } = AgentGrantState.Pending;
    public string ClientId { get; set; } = "";
    public string ClientName { get; set; } = "";
    public string RedirectHost { get; set; } = "";
    public Guid ApprovedByDeviceId
    {
        get; set;
    }
    public DateTimeOffset CreatedAt
    {
        get; set;
    }
    public DateTimeOffset? ExpiresAt
    {
        get; set;
    }
    public DateTimeOffset? LastUsedAt
    {
        get; set;
    }
    // When a device last changed the copy, and whether that pass covered every shared entry.
    public DateTimeOffset? UpdatedAt
    {
        get; set;
    }
    public bool CopyComplete
    {
        get; set;
    }
    // The sequence number the next changed item receives.
    public long NextSequence
    {
        get; set;
    }
    // Increases with every change of the settings; devices upload and change settings only from the current one.
    public long Revision
    {
        get; set;
    } = 1;
}

public static class AgentGrantState
{
    public const string Pending = "pending";
    public const string Active = "active";
}

// One encrypted item of a grant's copy. A deleted item keeps its row without a payload.
public sealed class AgentItem
{
    public Guid GrantId
    {
        get; set;
    }
    public string ItemId { get; set; } = "";
    // The sync cursor the publishing device had applied; the server keeps the highest.
    public long Version
    {
        get; set;
    }
    // A keyed digest of the plaintext, so devices can compare without downloading payloads.
    public string Digest { get; set; } = "";
    public long Sequence
    {
        get; set;
    }
    public string? Payload
    {
        get; set;
    }
}

// A tool an agent used, and when; never its arguments or results.
public sealed class AgentEvent
{
    public long Id
    {
        get; set;
    }
    public Guid GrantId
    {
        get; set;
    }
    public DateTimeOffset At
    {
        get; set;
    }
    public string Tool { get; set; } = "";
}

// A client registered with dynamic client registration (RFC 7591). Clients identified by a metadata document URL
// aren't stored.
public sealed class OAuthClient
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    // JSON array of the registered redirect URIs.
    public string RedirectUris { get; set; } = "[]";
    // "none", "client_secret_basic" or "client_secret_post"; confidential clients have a secret, stored as its hash.
    public string AuthMethod { get; set; } = "none";
    public string? SecretHash
    {
        get; set;
    }
    public DateTimeOffset CreatedAt
    {
        get; set;
    }
    // Set once an authorization with this client was approved; unused registrations are removed after a day.
    public bool Used
    {
        get; set;
    }
}

// An access or refresh token. The token itself carries a secret that unwraps the grant's copy key; the server keeps
// only the verifier's hash and the key wrapped under that secret.
public sealed class OAuthToken
{
    public Guid Id
    {
        get; set;
    }
    public Guid GrantId
    {
        get; set;
    }
    // OAuthTokenKind.
    public string Kind { get; set; } = "";
    public string VerifierHash { get; set; } = "";
    public byte[] WrappedKey { get; set; } = [];
    public string Resource { get; set; } = "";
    public string Scope { get; set; } = "";
    public DateTimeOffset ExpiresAt
    {
        get; set;
    }
    // The refresh token this one was issued from; siblings (issued from it during its grace) are revoked once one of
    // them is used.
    public Guid? Parent
    {
        get; set;
    }
    // Refresh tokens of one authorization form a family: reuse of a replaced one revokes the family.
    public Guid Family
    {
        get; set;
    }
    // Revoked with its family or as a superseded sibling: the row stays, without a wrap, until it would have expired, so
    // presenting it again is recognized as reuse.
    public bool Revoked
    {
        get; set;
    }
    // For a replaced refresh token: when it was replaced. It stays usable for a short grace, for clients that retry or
    // refresh concurrently; later use revokes the family.
    public DateTimeOffset? ReplacedAt
    {
        get; set;
    }
}

public static class OAuthTokenKind
{
    public const string Access = "access";
    public const string Refresh = "refresh";
}
