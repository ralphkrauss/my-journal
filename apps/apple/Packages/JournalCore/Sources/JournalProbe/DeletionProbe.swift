import Foundation
import JournalCore

extension Probe {
    static func verifyDeletionReceiving(
        clean: JournalStore, offline: JournalStore, client: ServerClient, offlineClient: ServerClient,
        key: Data, entryID: UUID
    ) async throws {
        guard var edit = try await offline.item(entryID) else {
            throw ProbeFailure("the entry to delete is missing on the offline device")
        }
        edit.document = .plain("An offline edit awaiting deletion review")
        try await offline.save(edit)
        guard let pending = try await offline.pending().first(where: { $0.recordID == entryID }) else {
            throw ProbeFailure("the offline edit was not queued")
        }
        // Publish protocol bytes directly: the local destructive mutation is intentionally not exposed yet.
        let date = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        var marker = JournalItem(id: entryID, kind: "entry", date: date)
        marker.deletedAt = date
        marker.permanentlyDeletedAt = date
        marker.permanentDeletionID = UUID()
        var deletion = pending
        deletion.operationId = UUID()
        let bytes = try PortableRecord.encode(marker)
        deletion.payload =
            try await clean.protection == .plaintext
            ? bytes.base64EncodedString()
            : VaultCrypto.seal(bytes, key: key, context: VaultCrypto.recordContext(id: entryID, kind: "entry"))
                .base64EncodedString()
        guard case .accepted(let receipt) = try await client.push(deletion),
            case .accepted(let retry) = try await client.push(deletion),
            receipt.revision == retry.revision, receipt.payload == retry.payload
        else { throw ProbeFailure("retrying the deletion marker did not return the same receipt") }
        let cleanSync = SyncEngine(store: clean, client: client)
        let offlineSync = SyncEngine(store: offline, client: offlineClient)
        try await cleanSync.synchronize()
        try await offlineSync.synchronize()
        try await cleanSync.synchronize()
        try await offlineSync.synchronize()
        let received = try await clean.item(entryID)
        let history = try await clean.history(for: entryID)
        let visible = try await clean.viewSnapshot()
        let conflicts = try await offline.conflicts()
        guard received == marker, history.isEmpty, !visible.items.contains(where: { $0.id == entryID }),
            conflicts.count == 1, conflicts[0].remote == marker,
            conflicts[0].local.document == edit.document
        else { throw ProbeFailure("the deletion marker did not arrive, or the offline edit is not kept for review") }
        print("PASS: deletion marker retries converge while a concurrent offline edit remains available for review")
        guard let journalID = edit.journalID else { throw ProbeFailure("the offline edit has no journal") }
        let review = try await offline.prepareDeletionConflict(entryID)
        let kept = try await offline.resolveDeletionConflict(review, choice: .keepEntry(journalID: journalID))
        try await offlineSync.synchronize()
        try await cleanSync.synchronize()
        let restored = try await clean.item(entryID)
        let unresolved = try await clean.conflicts()
        guard restored == kept, unresolved.isEmpty, kept.document == edit.document,
            kept.restoredFromDeletionID == marker.permanentDeletionID
        else {
            throw ProbeFailure(
                "keeping the edited entry did not revive it on the other device without a second conflict")
        }
        print("PASS: explicitly keeping the edited entry revives it on another device without a second conflict")
    }
}

extension Probe {
    static func verifyLocalJournalDeletion(
        sender: JournalStore, observer: JournalStore, client: ServerClient, observerClient: ServerClient,
        journalID: UUID
    ) async throws {
        let recoverable = try await sender.prepareJournalDeletion(journalID)
        _ = try await sender.deleteJournal(recoverable)
        let confirmed = try await sender.preparePermanentDeletion(journalID)
        _ = try await sender.permanentlyDelete(confirmed)
        let senderSync = SyncEngine(store: sender, client: client)
        let observerSync = SyncEngine(store: observer, client: observerClient)
        // First send settles immutable earlier operations; the next delivers the resulting markers.
        try await senderSync.synchronize()
        try await senderSync.synchronize()
        try await observerSync.synchronize()
        let sent = try await sender.items()
        let received = try await observer.items()
        let pending = try await sender.pending()
        let conflicts = try await observer.conflicts()
        guard sent.count == 3, received.count == 3, sent.allSatisfy(\.isPermanentlyDeleted),
            received.allSatisfy(\.isPermanentlyDeleted), pending.isEmpty, conflicts.isEmpty
        else {
            throw ProbeFailure("the confirmed journal deletion did not converge, or left queued changes or conflicts")
        }
        print("PASS: confirmed local journal deletion converges after immutable prior retries settle")
    }
}
