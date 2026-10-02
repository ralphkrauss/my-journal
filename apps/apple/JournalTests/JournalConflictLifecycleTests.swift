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
    func testResolutionFlushesEntryAndLockCannotUndoCommittedMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(directory: root)
        defer {
            let account =
                "master-" + SHA256.hash(data: Data(root.path.utf8)).map { String(format: "%02x", $0) }.joined()
            try? Keychain.remove(account)
            try? FileManager.default.removeItem(at: root)
        }
        await model.start()
        let phrase = try XCTUnwrap(model.recoveryKey)
        model.confirmRecovery()
        await model.newEntry()
        let store = try XCTUnwrap(model.store)
        let journal = try XCTUnwrap(model.selectedJournal)
        let recovery = try XCTUnwrap(model.configuration?.recovery)
        let key = try VaultCrypto.recover(recovery, phrase: phrase).0
        var other = journal
        other.title = "Work Notes"
        other.defaultTemplateID = UUID()
        var draft = try XCTUnwrap(model.draft)
        draft.title = "Final unsaved edit"
        model.updateDraft(draft)
        let conflict = try await installConflict(other, revision: 1, store: store, key: key)
        try await model.refresh()
        if let preview = await NativeTestPreview.capture(
            JournalConflictView(conflict: conflict).environmentObject(model),
            name: "Journal metadata conflict native preview")
        {
            add(preview)
        }
        let refreshed = try await model.resolveJournalConflict(conflict, choice: .remote)
        XCTAssertTrue(refreshed)
        XCTAssertFalse(model.showingUnavailable)
        XCTAssertEqual(model.selectedJournal?.title, other.title)
        let saved = try await store.item(draft.id)
        XCTAssertEqual(saved?.title, draft.title)
        XCTAssertEqual(saved?.journalID, journal.id)
        await model.turnOnAppLockForTesting()
        other.title = "Shared Work"
        other.deletedAt = Date()
        let next = try await installConflict(other, revision: 2, store: store, key: key)
        let committed = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let resolving = Task {
            try await model.commitJournalResolution {
                let resolved = try await store.resolve(next, choice: .remote)
                committed.continuation.yield(())
                committed.continuation.finish()
                for await _ in release.stream { break }
                return resolved
            }
        }
        for await _ in committed.stream { break }
        let locking = Task { await model.lock() }
        while !model.locked { await Task.yield() }
        release.continuation.yield(())
        release.continuation.finish()
        _ = try await resolving.value
        await locking.value
        XCTAssertTrue(model.items.isEmpty)
        await model.unlockForTesting()
        XCTAssertNil(model.selectedJournal)
        XCTAssertNil(model.draft)
        XCTAssertFalse(model.canEdit)
        let history = try await store.history(for: journal.id)
        XCTAssertEqual(history.count, 4)
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
    /// Review Changes says where each version is when the other device moved or deleted the entry, and the choices
    /// keep each version there, as the review says.
    func testEntryReviewSaysWhereEachVersionIsAndKeepBothKeepsThemThere() async throws {
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
        let conflict = try await installConflict(remote, revision: 1, store: store, key: key)
        let journals = [work, home]
        XCTAssertEqual(
            ConflictPlacement.line(for: conflict.local, other: conflict.remote, journals: journals), "In Work")
        XCTAssertEqual(
            ConflictPlacement.line(for: conflict.remote, other: conflict.local, journals: journals),
            "In Recently Deleted")
        XCTAssertEqual(
            ConflictPlacement.outcome(keepingRemote: conflict.remote, local: conflict.local, journals: journals),
            "The entry will move to Recently Deleted.")
        XCTAssertEqual(
            ConflictPlacement.keepBothOutcome(conflict.local, conflict.remote), "Each version stays where it is.")
        var archived = remote
        archived.deletedAt = nil
        archived.archivedAt = Date()
        archived.date = Date(timeIntervalSince1970: 1_790_000_000)
        let archivedLine = try XCTUnwrap(ConflictPlacement.line(for: archived, other: local, journals: journals))
        XCTAssertTrue(archivedLine.hasPrefix("Archived in Home, dated "), archivedLine)
        let archivedOutcome = try XCTUnwrap(
            ConflictPlacement.outcome(keepingRemote: archived, local: local, journals: journals))
        XCTAssertTrue(archivedOutcome.hasPrefix("The entry will be archived in Home, and its date will change to "))
        var edited = local
        edited.document = remote.document
        XCTAssertNil(ConflictPlacement.line(for: edited, other: local, journals: journals))
        XCTAssertNil(ConflictPlacement.keepBothOutcome(edited, local))
        try await store.resolve(conflict, choice: .keepBoth)
        let entries = try await store.items().filter { $0.kind == "entry" }
        XCTAssertEqual(entries.count, 2)
        let kept = try XCTUnwrap(entries.first { $0.id == local.id })
        XCTAssertEqual(kept.journalID, work.id)
        XCTAssertNil(kept.deletedAt)
        let copy = try XCTUnwrap(entries.first { $0.id != local.id })
        XCTAssertEqual(copy.journalID, home.id)
        XCTAssertNotNil(copy.deletedAt)
        XCTAssertEqual(copy.document, remote.document)
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
