namespace Journal.Api.Security;

// Structured events for server operators: access changes, integrity faults and maintenance. Never log
// tokens, codes, secrets, envelopes, device names or journal content.
public sealed partial class AuditLog(ILogger<AuditLog> logger)
{
    private readonly ILogger logger = logger;

    [LoggerMessage(EventId = 1, Level = LogLevel.Information, Message = "Device {DeviceId} was enrolled through {Route}.")]
    public partial void DeviceEnrolled(Guid deviceId, string route);

    [LoggerMessage(EventId = 2, Level = LogLevel.Information, Message = "Device {DeviceId} was revoked by device {RevokedBy}.")]
    public partial void DeviceRevoked(Guid deviceId, Guid revokedBy);

    [LoggerMessage(EventId = 13, Level = LogLevel.Information, Message = "Device {DeviceId} was enrolled through pairing approved by device {ApprovedBy}.")]
    public partial void DevicePaired(Guid deviceId, Guid approvedBy);

    [LoggerMessage(EventId = 14, Level = LogLevel.Information, Message = "Device {DeviceId} was revoked because its pairing request was cancelled.")]
    public partial void PairingCancelled(Guid deviceId);

    [LoggerMessage(EventId = 15, Level = LogLevel.Information, Message = "Device {DeviceId} was revoked because its pairing grant was never collected.")]
    public partial void PairingGrantUncollected(Guid deviceId);

    [LoggerMessage(EventId = 30, Level = LogLevel.Information, Message = "Agent {GrantId} was approved by device {DeviceId}.")]
    public partial void AgentRequestApproved(Guid grantId, Guid deviceId);

    [LoggerMessage(EventId = 31, Level = LogLevel.Information, Message = "An agent request was declined by device {DeviceId}.")]
    public partial void AgentRequestDeclined(Guid deviceId);

    [LoggerMessage(EventId = 32, Level = LogLevel.Information, Message = "Agent {GrantId} was revoked by device {DeviceId}.")]
    public partial void AgentRevoked(Guid grantId, Guid deviceId);

    [LoggerMessage(EventId = 33, Level = LogLevel.Information, Message = "Agent {GrantId}'s access ended; its tokens and copy were deleted.")]
    public partial void AgentExpired(Guid grantId);

    [LoggerMessage(EventId = 34, Level = LogLevel.Warning, Message = "An authorization code of agent {GrantId} was used twice; its tokens were revoked.")]
    public partial void AuthorizationCodeReused(Guid grantId);

    [LoggerMessage(EventId = 35, Level = LogLevel.Warning, Message = "A replaced refresh token of agent {GrantId} was used; its tokens were revoked.")]
    public partial void RefreshTokenReused(Guid grantId);

    [LoggerMessage(EventId = 36, Level = LogLevel.Information, Message = "OAuth client {ClientId} was registered.")]
    public partial void OAuthClientRegistered(string clientId);

    [LoggerMessage(EventId = 38, Level = LogLevel.Warning, Message = "Client metadata documents couldn’t be fetched. If this server can’t reach the internet, set Journal__ClientMetadataDocuments=false so agents register instead.")]
    public partial void ClientMetadataUnreachable();

    [LoggerMessage(EventId = 37, Level = LogLevel.Warning, Message = "JOURNAL_URL isn't an HTTPS address without a path, so agents get an address derived from each request. Set Journal__PublicUrl to the HTTPS address agents should use.")]
    public partial void JournalUrlNotUsedForAgents();

    [LoggerMessage(EventId = 3, Level = LogLevel.Information, Message = "The recovery envelope and password verifier were replaced by device {DeviceId}.")]
    public partial void PasswordChanged(Guid deviceId);

    [LoggerMessage(EventId = 4, Level = LogLevel.Warning, Message = "A recovery request from {ClientAddress} used an invalid recovery secret.")]
    public partial void RecoveryRejected(string clientAddress);

    [LoggerMessage(EventId = 16, Level = LogLevel.Warning, Message = "Recovery is paused for {Seconds} seconds after {Failures} failed or pending recovery attempts within an hour.")]
    public partial void RecoveryPaused(int failures, int seconds);

    [LoggerMessage(EventId = 5, Level = LogLevel.Warning, Message = "A setup request from {ClientAddress} used an invalid setup code.")]
    public partial void SetupCodeRejected(string clientAddress);

    [LoggerMessage(EventId = 6, Level = LogLevel.Information, Message = "A new setup code was written to the data directory ({Reason}).")]
    public partial void SetupCodeWritten(string reason);

    [LoggerMessage(EventId = 17, Level = LogLevel.Warning, Message = "Setup is paused for {Seconds} seconds after {Failures} failed or pending setup attempts within an hour.")]
    public partial void SetupPaused(int failures, int seconds);

    [LoggerMessage(EventId = 18, Level = LogLevel.Information, Message = "This server isn't set up yet. To see its setup code, run setup-code.")]
    public partial void SetupPending();

    [LoggerMessage(EventId = 7, Level = LogLevel.Warning, Message = "Image {AttachmentId} is recorded in the database but its file is missing.")]
    public partial void AttachmentFileMissing(Guid attachmentId);

    [LoggerMessage(EventId = 8, Level = LogLevel.Information, Message = "The missing file of image {AttachmentId} was restored from an identical upload.")]
    public partial void AttachmentFileRestored(Guid attachmentId);

    [LoggerMessage(EventId = 9, Level = LogLevel.Critical, Message = "The database was updated by a newer version of Journal (migration {Migration}). This version cannot use it. Install that version or later, or restore a backup made by this version into an empty data directory.")]
    public partial void NewerDatabase(string migration);

    [LoggerMessage(EventId = 10, Level = LogLevel.Information, Message = "Copied the database to {CopyName} before applying {Pending} database migration(s).")]
    public partial void CopiedBeforeMigration(string copyName, int pending);

    [LoggerMessage(EventId = 11, Level = LogLevel.Information, Message = "Backup created.")]
    public partial void BackupCreated();

    [LoggerMessage(EventId = 12, Level = LogLevel.Warning, Message = "Backup restored: {SignedOut} device credential(s) were revoked and the server identity was replaced.")]
    public partial void BackupRestored(int signedOut);

    [LoggerMessage(EventId = 40, Level = LogLevel.Warning, Message = "Encryption was turned on by device {DeviceId}: every record, revision and image was removed, and {SignedOut} other device credential(s) were revoked.")]
    public partial void EncryptionTurnedOn(Guid deviceId, int signedOut);

    [LoggerMessage(EventId = 41, Level = LogLevel.Information, Message = "Files left from before encryption was turned on were removed.")]
    public partial void EncryptionPurged();

    [LoggerMessage(EventId = 42, Level = LogLevel.Warning, Message = "Files left from before encryption was turned on couldn't be removed yet. The server removes them when it next starts.")]
    public partial void EncryptionPurgeDeferred();
}
