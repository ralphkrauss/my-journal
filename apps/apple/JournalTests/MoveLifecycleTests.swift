import CryptoKit
import JournalCore
import XCTest

@testable import Journal

#if os(macOS)
    import AppKit
    import SwiftUI
#endif

@MainActor
final class MoveLifecycleTests: XCTestCase {
    func testMovingFlushesFinalEditAndRetainsSelectionWithoutChangingAnotherEntry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { @MainActor in try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root, key: key)
        addTeardownBlock { try await store.close() }
        let source = JournalItem(kind: "journal", title: "Personal")
        let destination = JournalItem(kind: "journal", title: "Work")
        let entry = JournalItem(kind: "entry", journalID: source.id, title: "Before")
        for item in [source, destination, entry] { try await store.save(item) }
        let model = AppModel(directory: root)
        model.store = store
        model.items = [source, destination, entry]
        model.selectedID = entry.id
        model.selectedJournalID = source.id
        model.draft = entry
        #if os(macOS)
            await attachPreview(MoveEntryView(entryID: entry.id).environmentObject(model))
        #endif
        var edited = entry
        edited.title = "Saved immediately before moving"
        model.updateDraft(edited)
        try await model.moveEntry(entry.id, to: destination.id)
        XCTAssertEqual(model.selectedJournalID, destination.id)
        XCTAssertEqual(model.draft?.id, entry.id)
        XCTAssertEqual(model.draft?.title, edited.title)
        XCTAssertTrue(model.pendingSync)
        let reopened = try JournalStore(directory: root, key: key)
        addTeardownBlock { try await reopened.close() }
        let stored = try await reopened.item(entry.id)
        XCTAssertEqual(stored?.title, edited.title)
        XCTAssertEqual(stored?.journalID, destination.id)
        model.draft = JournalItem(kind: "entry", journalID: source.id, title: "Another selection")
        do {
            try await model.moveEntry(entry.id, to: source.id)
            XCTFail("A changed selection must not move another entry.")
        } catch JournalError.locked {}
        let unchanged = try await reopened.item(entry.id)
        XCTAssertEqual(unchanged, stored)
    }
    func testLockedRelaunchRestoresHistoricalEntryAndFallsBackFromDeletedJournal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(directory: root)
        addTeardownBlock { @MainActor in
            let account =
                "master-" + SHA256.hash(data: Data(root.path.utf8)).map { String(format: "%02x", $0) }.joined()
            try? Keychain.remove(account)
            try? FileManager.default.removeItem(at: root)
        }
        addTeardownBlock { @MainActor in
            _ = await model.finishPendingSave()
            try await model.store?.close()
        }
        await model.start()
        model.confirmRecovery()
        let personal = try XCTUnwrap(model.selectedJournalID)
        await model.createJournal("Work")
        let work = try XCTUnwrap(model.selectedJournal)
        await model.newEntry()
        var entry = try XCTUnwrap(model.draft)
        entry.title = "Last week’s notes"
        entry.date = Date(timeIntervalSinceNow: -7 * 24 * 60 * 60)
        model.updateDraft(entry)
        let saved = await model.finishPendingSave()
        XCTAssertTrue(saved)
        await model.turnOnAppLockForTesting()
        let reopened = AppModel(directory: root)
        addTeardownBlock { @MainActor in
            _ = await reopened.finishPendingSave()
            try await reopened.store?.close()
        }
        await reopened.load()
        XCTAssertTrue(reopened.locked)
        XCTAssertNil(reopened.draft)
        await reopened.unlockForTesting()
        XCTAssertEqual(reopened.selectedJournalID, work.id)
        XCTAssertEqual(reopened.draft?.id, entry.id)
        XCTAssertEqual(reopened.draft?.title, entry.title)
        var removed = work
        removed.deletedAt = Date()
        let store = try XCTUnwrap(model.store)
        try await store.save(removed)
        let fallback = AppModel(directory: root)
        addTeardownBlock { @MainActor in
            _ = await fallback.finishPendingSave()
            try await fallback.store?.close()
        }
        await fallback.load()
        await fallback.unlockForTesting()
        XCTAssertEqual(fallback.selectedJournalID, personal)
        XCTAssertNil(fallback.draft)
        let retained = try await store.item(entry.id)
        XCTAssertEqual(retained?.title, entry.title)
    }
    func testLockAfterMoveCommitCannotSaveOldJournalMembership() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(directory: root)
        addTeardownBlock { @MainActor in
            let account =
                "master-" + SHA256.hash(data: Data(root.path.utf8)).map { String(format: "%02x", $0) }.joined()
            try? Keychain.remove(account)
            try? FileManager.default.removeItem(at: root)
        }
        addTeardownBlock { @MainActor in
            _ = await model.finishPendingSave()
            try await model.store?.close()
        }
        await model.start()
        model.confirmRecovery()
        await model.newEntry()
        let entry = try XCTUnwrap(model.draft)
        await model.createJournal("Work")
        let destination = try XCTUnwrap(model.selectedJournalID)
        let source = try XCTUnwrap(entry.journalID)
        await model.switchJournal(source)
        await model.select(entry.id)
        await model.turnOnAppLockForTesting()
        let store = try XCTUnwrap(model.store)
        let committed = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let moving = Task {
            try await model.commitEntryMove {
                let moved = try await store.moveEntry(entry.id, to: destination)
                committed.continuation.yield(())
                committed.continuation.finish()
                // Deliberately hold reconciliation after the real transaction has committed.
                for await _ in release.stream { break }
                return moved
            }
        }
        for await _ in committed.stream { break }
        let locking = Task { await model.lock() }
        while !model.locked { await Task.yield() }
        release.continuation.yield(())
        release.continuation.finish()
        try await moving.value
        await locking.value
        XCTAssertTrue(model.locked)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(model.draft?.journalID, destination)
        let saved = try await store.item(entry.id)
        XCTAssertEqual(saved?.journalID, destination)
        await model.unlockForTesting()
        XCTAssertEqual(model.selectedJournalID, destination)
        XCTAssertEqual(model.draft?.journalID, destination)
        let flushed = await model.finishPendingSave()
        XCTAssertTrue(flushed)
        let reopened = AppModel(directory: root)
        addTeardownBlock { @MainActor in
            _ = await reopened.finishPendingSave()
            try await reopened.store?.close()
        }
        await reopened.load()
        await reopened.unlockForTesting()
        XCTAssertEqual(reopened.draft?.id, entry.id)
        XCTAssertEqual(reopened.draft?.journalID, destination)
    }
    #if os(macOS)
        private func attachPreview<V: View>(_ view: V) async {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 360), styleMask: [.titled], backing: .buffered,
                defer: true)
            let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
            host.frame = NSRect(x: 0, y: 0, width: 420, height: 360)
            window.contentView = host
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = NSImage(size: host.bounds.size)
            image.addRepresentation(bitmap)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Move entry (offscreen native render)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    #endif
}
