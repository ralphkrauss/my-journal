import CryptoKit
import JournalCore
import SwiftUI
import XCTest

@testable import Journal

@MainActor
final class HistoryLifecycleTests: XCTestCase {
    /// Resolving a conflict records the other device's older version after this device's newer one; the picker
    /// still lists versions newest first, and numbers only versions whose times read the same.
    func testVersionPickerListsVersionsNewestFirstAndNumbersOnlyMatchingTimes() {
        func version(_ title: String, _ seconds: TimeInterval) -> JournalItem {
            var item = JournalItem(kind: "entry", title: title)
            item.modifiedAt = Date(timeIntervalSince1970: 1_790_000_000 + seconds)
            return item
        }
        // As the store returns them: most recently recorded first.
        let recorded = [
            version("Other device", 0), version("This device", 73), version("Older", -282), version("Same A", -900),
            version("Same B", -900),
        ]
        let listed = HistoryVersions.newestFirst(recorded)
        XCTAssertEqual(listed.map(\.title), ["This device", "Other device", "Older", "Same A", "Same B"])
        let titles = HistoryVersions.titles(listed)
        XCTAssertEqual(titles.filter { $0.contains(" · ") }.count, 2)
        XCTAssertFalse(titles[0].contains(" · "))
        XCTAssertTrue(titles[3].hasSuffix(" · 1"))
        XCTAssertTrue(titles[4].hasSuffix(" · 2"))
    }
    func testHistoryRecoverySavesCurrentDraftAndRetainsItOnSaveFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root, key: key)
        let journal = JournalItem(kind: "journal", title: "Work")
        try await store.save(journal)
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Current")
        let version = try await history(store, entry: entry, key: key)
        let model = AppModel(directory: root)
        model.store = store
        try await model.refresh()
        model.draft = try await store.item(entry.id)
        model.selectedID = entry.id
        if let preview = await NativeTestPreview.capture(
            VersionHistoryView(sourceID: entry.id, sourceKind: entry.kind).environmentObject(model),
            name: "Entry history native preview")
        {
            add(preview)
        }
        var unsaved = try XCTUnwrap(model.draft)
        unsaved.title = "Final current edit"
        model.updateDraft(unsaved)
        let refreshed = try await model.restoreHistoricalVersion(version, to: journal.id)
        XCTAssertTrue(refreshed)
        let copy = try XCTUnwrap(model.draft)
        XCTAssertNotEqual(copy.id, entry.id)
        XCTAssertEqual(copy.title, version.title)
        XCTAssertEqual(model.selectedID, copy.id)
        XCTAssertEqual(model.selectedJournalID, journal.id)
        let savedSource = try await store.item(entry.id)
        XCTAssertEqual(savedSource?.title, unsaved.title)
        model.draft = nil
        model.selectedID = nil
        let created = try await model.createRecoveryJournal("Recovered", entryID: nil)
        XCTAssertTrue(created)
        XCTAssertNil(model.selectedID)
        XCTAssertNil(model.draft)
        model.draft = copy
        model.selectedID = copy.id
        try await store.close()
        var failedDraft = copy
        failedDraft.title = "Keep this unsaved work"
        model.updateDraft(failedDraft)
        do {
            _ = try await model.restoreHistoricalVersion(version, to: journal.id)
            XCTFail("A failed current draft must not be discarded by history recovery.")
        } catch JournalError.saveRequired {}
        XCTAssertTrue(model.saveFailure)
        XCTAssertEqual(model.draft?.title, failedDraft.title)
        let reopened = try JournalStore(directory: root, key: key)
        let copies = try await reopened.items().filter { $0.kind == "entry" && $0.id != entry.id }
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(copies.first, copy)
        try await reopened.close()
    }

    func testCommittedHistoryCopySurvivesLockAndReportsRefreshFailure() async throws {
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
        let envelope = try XCTUnwrap(model.configuration?.recovery)
        let key = try VaultCrypto.recover(envelope, phrase: phrase).0
        let store = try XCTUnwrap(model.store)
        let entry = try XCTUnwrap(model.draft)
        let version = try await history(store, entry: entry, key: key)
        try await model.refresh()
        model.draft = try await store.item(entry.id)
        await model.turnOnAppLockForTesting()
        let committed = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let restoring = Task {
            try await model.commitHistoricalCopy {
                let copy = try await store.restoreHistoryCopy(version, to: entry.journalID)
                committed.continuation.yield(())
                committed.continuation.finish()
                for await _ in release.stream { break }
                return copy
            }
        }
        for await _ in committed.stream { break }
        let locking = Task { await model.lock() }
        while !model.locked { await Task.yield() }
        release.continuation.yield(())
        release.continuation.finish()
        _ = try await restoring.value
        await locking.value
        XCTAssertTrue(model.locked)
        XCTAssertTrue(model.items.isEmpty)
        let committedID = try XCTUnwrap(model.draft?.id)
        XCTAssertNotEqual(committedID, entry.id)
        let savedCopy = try await store.item(committedID)
        XCTAssertEqual(savedCopy?.document, version.document)
        await model.unlockForTesting()
        XCTAssertEqual(model.draft?.id, committedID)
        let refreshed = try await model.commitHistoricalCopy {
            let another = try await store.restoreHistoryCopy(version, to: entry.journalID)
            try await store.close()  // Actual durable commit followed by an unreadable store.
            return another
        }
        XCTAssertFalse(refreshed)
        let lastCopy = try XCTUnwrap(model.draft)
        XCTAssertNotEqual(lastCopy.id, committedID)
        let reopened = try JournalStore(directory: await store.directory, key: key)
        let recovered = try await reopened.item(lastCopy.id)
        XCTAssertEqual(recovered, lastCopy)
        let all = try await reopened.items()
        XCTAssertEqual(all.filter { $0.kind == "entry" }.count, 3)
        try await reopened.close()
    }

    private func history(_ store: JournalStore, entry: JournalItem, key: Data) async throws -> JournalItem {
        try await store.save(entry)
        var earlier = entry
        earlier.title = "Earlier reflection"
        earlier.document = .plain("Preserved earlier words")
        let payload = try VaultCrypto.seal(
            JournalCoding.encoder().encode(earlier), key: key,
            context: VaultCrypto.recordContext(id: earlier.id, kind: earlier.kind))
        try await store.recordConflict(
            RemoteChange(
                cursor: 1, recordId: entry.id, revision: 1, kind: entry.kind,
                payload: payload.base64EncodedString(), deviceId: UUID(), modifiedAt: Date()))
        let conflicts = try await store.conflicts()
        try await store.resolve(try XCTUnwrap(conflicts.first), choice: .local)
        let versions = try await store.history(for: entry.id)
        return try XCTUnwrap(versions.first { $0.title == earlier.title })
    }
}
