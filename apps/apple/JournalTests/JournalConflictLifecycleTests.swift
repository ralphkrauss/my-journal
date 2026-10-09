import CryptoKit
import JournalCore
import SwiftUI
import XCTest

@testable import Journal

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

@MainActor
final class JournalConflictLifecycleTests: XCTestCase {
    /// Deleting a journal saves the open entry first, and locking while the deletion commits cannot undo it.
    func testDeletingAJournalFlushesTheEntryAndLockCannotUndoTheCommittedDeletion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(directory: root)
        defer {
            let account =
                "master-" + SHA256.hash(data: Data(root.path.utf8)).map { String(format: "%02x", $0) }.joined()
            try? Keychain.remove(account)
            try? FileManager.default.removeItem(at: root)
        }
        await model.start()
        model.confirmRecovery()
        await model.newEntry()
        let store = try XCTUnwrap(model.store)
        let journal = try XCTUnwrap(model.selectedJournal)
        var draft = try XCTUnwrap(model.draft)
        draft.title = "Final unsaved edit"
        model.updateDraft(draft)
        let plan = try await model.prepareJournalDeletion(journal.id)
        let saved = try await store.item(draft.id)
        XCTAssertEqual(saved?.title, draft.title, "The open entry is saved before the journal is deleted")
        await model.turnOnAppLockForTesting()
        let committed = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let deleting = Task {
            try await model.commitJournalResolution {
                let deleted = try await store.deleteJournal(plan)
                committed.continuation.yield(())
                committed.continuation.finish()
                for await _ in release.stream { break }
                return deleted
            }
        }
        for await _ in committed.stream { break }
        let locking = Task { await model.lock() }
        while !model.locked { await Task.yield() }
        release.continuation.yield(())
        release.continuation.finish()
        _ = try await deleting.value
        await locking.value
        XCTAssertTrue(model.items.isEmpty)
        await model.unlockForTesting()
        XCTAssertNil(model.selectedJournal)
        XCTAssertNil(model.draft)
        XCTAssertFalse(model.canEdit)
        XCTAssertTrue(model.deletedJournals.contains { $0.id == journal.id })
        try await store.close()
        let reopened = AppModel(directory: root)
        await reopened.load()
        await reopened.unlockForTesting()
        XCTAssertNil(reopened.selectedJournal)
        XCTAssertNil(reopened.draft)
        let retained = try await reopened.store?.item(draft.id)
        XCTAssertEqual(retained?.title, draft.title)
        XCTAssertEqual(retained?.journalID, journal.id)
        try await reopened.store?.close()
    }
    /// Each version stays where it is when the other device moved or deleted the entry: this device's in its journal,
    /// the other in Recently Deleted, with a title that says it is the other version.
    func testKeepingBothLeavesEachVersionWhereItIs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root, key: key)
        let work = JournalItem(kind: "journal", title: "Work")
        let home = JournalItem(kind: "journal", title: "Home")
        try await store.save(work)
        try await store.save(home)
        let local = JournalItem(
            kind: "entry", journalID: work.id, title: "Plans",
            document: JournalDocument(blocks: [DocumentBlock(runs: [TextRun("Edited here")])]))
        try await store.save(local)
        var remote = local
        remote.journalID = home.id
        remote.deletedAt = Date()
        remote.document = JournalDocument(blocks: [DocumentBlock(runs: [TextRun("Older text")])])
        _ = try await installConflict(remote, revision: 1, store: store, key: key)
        let report = try await store.resolveConflicts(at: .local)
        XCTAssertEqual(report.resolved.count, 1)
        let entries = try await store.items().filter { $0.kind == "entry" }
        XCTAssertEqual(entries.count, 2)
        let kept = try XCTUnwrap(entries.first { $0.id == local.id })
        XCTAssertEqual(kept.journalID, work.id)
        XCTAssertNil(kept.deletedAt)
        XCTAssertEqual(kept.document.text, "Edited here")
        let copy = try XCTUnwrap(entries.first { $0.id != local.id })
        XCTAssertEqual(copy.journalID, home.id)
        XCTAssertNotNil(copy.deletedAt)
        XCTAssertEqual(copy.document, remote.document)
        XCTAssertEqual(copy.title, "Plans (other version)")
        try await store.close()
    }

    private func installConflict(_ item: JournalItem, revision: Int64, store: JournalStore, key: Data) async throws
        -> ConflictVersion
    {
        let payload = try VaultCrypto.seal(
            JournalCoding.encoder().encode(item), key: key,
            context: VaultCrypto.recordContext(id: item.id, kind: item.kind))
        try await store.recordConflict(
            RemoteChange(
                cursor: revision, recordId: item.id, revision: revision, kind: item.kind,
                payload: payload.base64EncodedString(), deviceId: UUID(), modifiedAt: Date()))
        let conflicts = try await store.conflicts()
        return try XCTUnwrap(conflicts.first { $0.id == item.id })
    }
}
