using Microsoft.EntityFrameworkCore;

namespace Journal.Api.Data;

public sealed class JournalDb(DbContextOptions<JournalDb> options) : DbContext(options)
{
    public DbSet<Vault> Vaults => Set<Vault>();
    public DbSet<Device> Devices => Set<Device>();
    public DbSet<EncryptedRecord> Records => Set<EncryptedRecord>();
    public DbSet<Change> Changes => Set<Change>();
    public DbSet<AppliedOperation> Operations => Set<AppliedOperation>();
    public DbSet<Attachment> Attachments => Set<Attachment>();
    public DbSet<PairRequest> PairRequests => Set<PairRequest>();
    public DbSet<AgentGrant> AgentGrants => Set<AgentGrant>();
    public DbSet<AgentItem> AgentItems => Set<AgentItem>();
    public DbSet<AgentEvent> AgentEvents => Set<AgentEvent>();
    public DbSet<OAuthClient> OAuthClients => Set<OAuthClient>();
    public DbSet<OAuthToken> OAuthTokens => Set<OAuthToken>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        ArgumentNullException.ThrowIfNull(modelBuilder);
        modelBuilder.Entity<Vault>().HasKey(x => x.Id);
        modelBuilder.Entity<Device>().HasIndex(x => x.TokenHash).IsUnique();
        modelBuilder.Entity<EncryptedRecord>().Property(x => x.Revision).IsConcurrencyToken();
        modelBuilder.Entity<Change>().HasKey(x => x.Cursor);
        modelBuilder.Entity<Change>().Property(x => x.Cursor).ValueGeneratedOnAdd();
        modelBuilder.Entity<AppliedOperation>().HasKey(x => x.Id);
        modelBuilder.Entity<Attachment>().HasKey(x => x.Id);
        modelBuilder.Entity<PairRequest>().HasIndex(x => x.CodeHash).IsUnique();
        modelBuilder.Entity<AgentGrant>().HasKey(x => x.Id);
        modelBuilder.Entity<AgentItem>().HasKey(x => new { x.GrantId, x.ItemId });
        modelBuilder.Entity<AgentItem>().HasIndex(x => new { x.GrantId, x.Sequence });
        modelBuilder.Entity<AgentEvent>().HasKey(x => x.Id);
        modelBuilder.Entity<AgentEvent>().Property(x => x.Id).ValueGeneratedOnAdd();
        modelBuilder.Entity<AgentEvent>().HasIndex(x => x.GrantId);
        modelBuilder.Entity<OAuthClient>().HasKey(x => x.Id);
        modelBuilder.Entity<OAuthToken>().HasKey(x => x.Id);
        modelBuilder.Entity<OAuthToken>().HasIndex(x => x.GrantId);
        modelBuilder.Entity<OAuthToken>().HasIndex(x => x.Family);
    }
}

public sealed class Vault
{
    public int Id { get; set; } = 1;
    public string Salt { get; set; } = "";
    public string WrappedKey { get; set; } = "";
    public string RecoveryHash { get; set; } = "";
    public int Iterations
    {
        get; set;
    }
    public int FormatVersion { get; set; } = 1;
    // Random database identity. Replaced when a backup is restored so clients can detect lost changes.
    public string SyncId { get; set; } = "";
    // Changes at or below this cursor existed when SyncId was assigned; later changes were written afterwards.
    public long SyncIdCursor
    {
        get; set;
    }
}
public sealed class Device
{
    public Guid Id
    {
        get; set;
    }
    public string Name { get; set; } = "";
    public string TokenHash { get; set; } = "";
    public DateTimeOffset CreatedAt
    {
        get; set;
    }
    public bool Revoked
    {
        get; set;
    }
    // How the device was added (DeviceOrigin); null for devices added before this was recorded.
    public string? CreatedVia
    {
        get; set;
    }
    // For pairing: the device that approved it.
    public Guid? ApprovedByDeviceId
    {
        get; set;
    }
}
// Values of Device.CreatedVia, returned by GET /v1/devices.
public static class DeviceOrigin
{
    public const string Setup = "setup";
    public const string Recovery = "recovery";
    public const string Pairing = "pairing";
}
public sealed class EncryptedRecord
{
    public Guid Id
    {
        get; set;
    }
    public string Kind { get; set; } = "";
    public long Revision
    {
        get; set;
    }
    public string Payload { get; set; } = "";
    public Guid DeviceId
    {
        get; set;
    }
    public DateTimeOffset ModifiedAt
    {
        get; set;
    }
}
// Each change includes its immutable encrypted revision, so pagination is a stable log.
public sealed class Change
{
    public long Cursor
    {
        get; set;
    }
    public Guid RecordId
    {
        get; set;
    }
    public long Revision
    {
        get; set;
    }
    public string Kind { get; set; } = "";
    public string Payload { get; set; } = "";
    public Guid DeviceId
    {
        get; set;
    }
    public DateTimeOffset ModifiedAt
    {
        get; set;
    }
}
public sealed class AppliedOperation
{
    public Guid Id
    {
        get; set;
    }
    public Guid RecordId
    {
        get; set;
    }
    public string RequestHash { get; set; } = "";
    // The change the operation wrote. A retry receives that change again as its receipt, read from the log, so the
    // receipt doesn't keep a second copy of the payload. Changes are never removed.
    public long? ChangeCursor
    {
        get; set;
    }
    // The whole receipt, as kept for operations applied before ChangeCursor existed; empty for later ones.
    public string ResponseJson { get; set; } = "";
}
public sealed class Attachment
{
    public Guid Id
    {
        get; set;
    }
    public string Sha256 { get; set; } = "";
    public long Length
    {
        get; set;
    }
}
public sealed class PairRequest
{
    public Guid Id
    {
        get; set;
    }
    public string CodeHash { get; set; } = "";
    public string PollTokenHash { get; set; } = "";
    public string DeviceName { get; set; } = "";
    public string PublicKey { get; set; } = "";
    public DateTimeOffset ExpiresAt
    {
        get; set;
    }
    public string? EncryptedGrant
    {
        get; set;
    }
    public Guid? DeviceId
    {
        get; set;
    }
    // Check-code pairing: SHA-256 commitment to the new device's key, published before the approver's key.
    public string? KeyCommitment
    {
        get; set;
    }
    public string? ApproverKey
    {
        get; set;
    }
    public bool Declined
    {
        get; set;
    }
    // The new device has read the approved grant. Uncollected grants are revoked once the request expires.
    public bool GrantDelivered
    {
        get; set;
    }
    // Invite pairing: the new device's proof that it read the connected device's code, which only that device
    // can check. CodeHash is then the hash of the invite handle.
    public string? InviteProof
    {
        get; set;
    }
}
