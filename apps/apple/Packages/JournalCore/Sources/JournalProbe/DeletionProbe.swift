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
        deletion.payload = try VaultCrypto.seal(
            bytes, key: key, context: VaultCrypto.recordContext(id: entryID, kind: "entry")
        ).base64EncodedString()
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
        guard received == marker, history.isEmpty, !visible.items.contains(where: { $0.id == entryID }) else {
            throw ProbeFailure("the deletion marker did not arrive on the clean device")
        }
        // The offline edit meets the marker: the deletion stays final and the edit is parked in Recently Deleted.
        let unresolved = try await offline.conflicts()
        let offlineMarker = try await offline.item(entryID)
        let parkedOffline = try await parkedEntries(in: offline, edit: edit, marker: marker)
        let parkedClean = try await parkedEntries(in: clean, edit: edit, marker: marker)
        guard unresolved.isEmpty, offlineMarker == marker, parkedOffline.count == 1, parkedClean.count == 1,
            parkedOffline.map(\.id) == parkedClean.map(\.id)
        else { throw ProbeFailure("the deletion did not stay final with the offline edit parked on both devices") }
        let queued = try await offline.pending()
        guard queued.isEmpty else { throw ProbeFailure("the parked edit was not sent") }
        print("PASS: a permanent deletion stays final while a concurrent offline edit is parked in Recently Deleted")
    }
    /// Entries other than `marker`'s record that hold the edited document, deleted at the marker's time.
    private static func parkedEntries(in store: JournalStore, edit: JournalItem, marker: JournalItem) async throws
        -> [JournalItem]
    {
        try await store.items().filter {
            $0.kind == "entry" && $0.id != marker.id && !$0.isPermanentlyDeleted && $0.document == edit.document
                && $0.deletedAt == marker.permanentlyDeletedAt && $0.title == edit.title
        }
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
