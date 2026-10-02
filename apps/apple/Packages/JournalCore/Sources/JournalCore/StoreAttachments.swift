import CryptoKit
import Foundation
import GRDB

// Images: which to upload, and checking them before an archive is made or restored.
extension JournalStore {
    /// Images waiting for upload that something uses: a record, an earlier version, a version awaiting review or a
    /// change taken for sending (`takeForSending`). An image removed again before it synced waits until something uses
    /// it again.
    public func attachmentsToUpload() throws -> [UUID] {
        let waiting = try pendingAttachments()
        guard !waiting.isEmpty else { return [] }
        var used = try referencedAttachmentIDs()
        for queued in try pending() where unsentOperations[queued.operationId] == nil {
            used.formUnion(try decode(queued.payload, id: queued.recordID, kind: queued.kind).document.attachmentIDs)
        }
        return waiting.filter(used.contains)
    }
    /// Validates restored content before a caller makes the staged vault active. Images are authenticated a few at a
    /// time outside the store, so saving and syncing continue meanwhile.
    public func validateSnapshot() async throws {
        try checkIntegrity()
        let images = Array(try referencedAttachmentIDs())
        let key = key
        let protection = protection
        let folder = directory.appendingPathComponent("attachments", isDirectory: true)
        try await Self.authenticateAttachments(images, in: folder, key: key, protection: protection)
    }
    private func checkIntegrity() throws {
        let integrity = try db.read { try String.fetchOne($0, sql: "PRAGMA integrity_check") }
        guard integrity == "ok" else { throw JournalError.invalidData }
    }
    /// Runs outside the store, so its work doesn't hold up saving and syncing.
    private static func authenticateAttachments(
        _ images: [UUID], in folder: URL, key: Data, protection: ContentProtection
    ) async throws {
        _ = try Parallel.map(images, width: 4, cancellableEvery: 16) { identifier in
            try authenticateAttachment(identifier, in: folder, key: key, protection: protection)
        }
    }
    static func encryptedAttachment(at url: URL) throws -> Data {
        // Only files no larger than the app writes are read, including from a restored archive.
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Self.maximumAttachmentBytes else { throw JournalError.invalidData }
        return try Data(contentsOf: url)
    }
    static func authenticateAttachment(
        _ uuid: UUID, in folder: URL, key: Data, protection: ContentProtection
    ) throws {
        let encrypted = try encryptedAttachment(at: folder.appendingPathComponent(uuid.uuidString.lowercased()))
        _ = try protection.decode(encrypted, key: key, context: VaultCrypto.attachmentContext(id: uuid))
    }
}
