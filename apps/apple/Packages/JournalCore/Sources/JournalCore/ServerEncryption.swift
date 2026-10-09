import Foundation

/// Why a server didn't turn on encryption (POST /v1/recovery/encrypt).
public enum EncryptionUpgradeRefusal: Error, Equatable, Sendable {
    /// Another device wrote to the server after this one last read it; nothing changed.
    case serverChanged
    /// The server's journals are already encrypted, with another envelope.
    case alreadyEncrypted
    /// The current access password is wrong.
    case incorrectPassword
    /// Anything else; whether the server changed is unknown.
    case failed
}

extension ServerClient {
    /// Asks the server to replace its unencrypted vault with `envelope`, a master-password envelope for a new vault
    /// key. The server removes every record, revision and image, signs out every other device and takes a new identity;
    /// this device then uploads its encrypted copy. `position` is the last change this device read, which must still
    /// be the server's newest. `currentRecoverySecret` proves the access password of a library that has one.
    /// Returns the server's new identity. Sending the same request again after it succeeded returns the same identity.
    public func turnOnEncryption(
        _ envelope: RecoveryEnvelope, recoverySecret: String, currentRecoverySecret: String?,
        after position: (cursor: Int64, change: LoggedChange?)
    ) async throws -> String {
        struct Body: Encodable {
            let salt: String
            let wrappedKey: String
            let iterations: Int
            let recoverySecret: String
            let formatVersion: Int
            let afterCursor: Int64
            let afterRecord: UUID?
            let afterRevision: Int64?
            let currentRecoverySecret: String?
        }
        struct Result: Decodable { let serverId: String }
        let body = Body(
            salt: envelope.salt, wrappedKey: envelope.wrappedKey, iterations: envelope.iterations,
            recoverySecret: recoverySecret, formatVersion: envelope.formatVersion, afterCursor: position.cursor,
            afterRecord: position.change?.recordId, afterRevision: position.change?.revision,
            currentRecoverySecret: currentRecoverySecret)
        let (data, status) = try await request("/v1/recovery/encrypt", method: "POST", body: json(body))
        switch status {
        case 200: return try JournalCoding.decoder().decode(Result.self, from: data).serverId
        case 403: throw EncryptionUpgradeRefusal.incorrectPassword
        case 409:
            throw Self.problemCode(data) == "server_changed"
                ? EncryptionUpgradeRefusal.serverChanged : EncryptionUpgradeRefusal.alreadyEncrypted
        default: throw EncryptionUpgradeRefusal.failed
        }
    }
}
