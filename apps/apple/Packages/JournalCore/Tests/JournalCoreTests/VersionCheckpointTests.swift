import XCTest
import os

@testable import JournalCore

/// Version History keeps earlier versions of ordinary changes, not every autosave.
final class VersionCheckpointTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let key = Data(repeating: 7, count: 32)
    private let time = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_800_000_000))

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }
    private func openStore() async throws -> JournalStore {
        let store = try JournalStore(directory: root, key: key)
        let time = time
        await store.useClock { time.withLock { $0 } }
        return store
    }
    private func advance(minutes: Double) {
        time.withLock { $0 += minutes * 60 }
    }
    private func edit(_ store: JournalStore, _ item: inout JournalItem, _ text: String, after minutes: Double)
        async throws
    {
        advance(minutes: minutes)
        item.document = .plain(text)
        item = try await store.save(item)
    }
    private func texts(_ store: JournalStore, _ item: JournalItem) async throws -> [String] {
        try await store.history(for: item.id).map(\.document.text)
    }

    func testEditingAfterReopeningKeepsTheVersionFromBefore() async throws {
        var entry = JournalItem(kind: "entry", journalID: UUID(), title: "Day", document: .plain("First body"))
        entry = try await openStore().save(entry)
        advance(minutes: 1)
        let reopened = try await openStore()
        try await edit(reopened, &entry, "Second body", after: 0)
        let history = try await texts(reopened, entry)
        XCTAssertEqual(history, ["First body"])
    }

    func testRapidAutosavesKeepOneVersionPerIntervalAndAfterAPause() async throws {
        let store = try await openStore()
        var entry = try await store.save(JournalItem(kind: "entry", journalID: UUID(), title: "Notes"))
        for (index, minutes) in [0.1, 0.2, 3, 5].enumerated() {
            try await edit(store, &entry, "Draft \(index)", after: minutes)
        }
        var history = try await texts(store, entry)
        XCTAssertEqual(history, [], "Autosaves within the first interval keep nothing")
        try await edit(store, &entry, "Draft 4", after: 2)
        try await edit(store, &entry, "Draft 5", after: 1)
        history = try await texts(store, entry)
        XCTAssertEqual(history, ["Draft 3"], "Ten minutes of editing keeps the version it replaced once")
        try await edit(store, &entry, "Evening", after: 45)
        history = try await texts(store, entry)
        XCTAssertEqual(history, ["Draft 5", "Draft 3"], "Returning after a pause keeps the version from before")
    }

    func testBlankEntriesAndDateChangesDontUseUpTheNextVersion() async throws {
        let store = try await openStore()
        var entry = try await store.save(JournalItem(kind: "entry", journalID: UUID()))
        try await edit(store, &entry, "Written later", after: 30)
        var history = try await texts(store, entry)
        XCTAssertEqual(history, [], "An untouched blank entry isn't a version worth keeping")
        advance(minutes: 30)
        entry.date = entry.date.addingTimeInterval(-86_400)
        entry = try await store.save(entry)
        try await edit(store, &entry, "Rewritten", after: 1)
        history = try await texts(store, entry)
        XCTAssertEqual(history, ["Written later"], "The text from before this session is still kept")
    }

    func testOnlyTheOldestCheckpointsAreRemovedAndReviewedVersionsStay() async throws {
        let store = try await openStore()
        let original = try await store.save(
            JournalItem(kind: "template", title: "Weekly", document: .plain("Original")))
        var entry = original
        try await edit(store, &entry, "Edited here", after: 0)
        var stale = original
        stale.document = .plain("Edited from a stale copy")
        try await store.save(stale)
        let conflicts = try await store.conflicts()
        entry = try await store.resolve(try XCTUnwrap(conflicts.first), choice: .local)
        let reviewed = try await texts(store, entry)
        XCTAssertEqual(reviewed.count, 2)
        try await edit(store, &entry, "Oldest kept", after: 0)
        for index in 0...JournalStore.checkpointLimit {
            try await edit(store, &entry, "Week \(index)", after: 11)
        }
        let history = try await texts(store, entry)
        XCTAssertEqual(history.count, JournalStore.checkpointLimit + reviewed.count)
        XCTAssertEqual(history.first, "Week \(JournalStore.checkpointLimit - 1)")
        XCTAssertFalse(history.contains("Oldest kept"), "The oldest checkpoint is the one removed")
        XCTAssertTrue(history.contains("Week 0"))
        XCTAssertEqual(Set(history.suffix(reviewed.count)), Set(reviewed), "Versions kept for review are never removed")
    }

    func testACheckpointKeepsItsImageAndCanBeRestored() async throws {
        let store = try await openStore()
        let journal = try await store.save(JournalItem(kind: "journal", title: "Travel"))
        let bytes = Data("Harbour photo".utf8)
        let image = try await store.addAttachment(bytes)
        var entry = JournalItem(kind: "entry", journalID: journal.id, title: "Harbour")
        entry.document = JournalDocument(blocks: [
            DocumentBlock(runs: [TextRun("Boats at dawn")]),
            DocumentBlock(kind: "image", attachmentID: image, imageDescription: "Boats", mediaType: "image/png"),
        ])
        entry = try await store.save(entry)
        try await edit(store, &entry, "Rewritten without the photo", after: 20)
        let history = try await store.history(for: entry.id)
        let version = try XCTUnwrap(history.first)
        let referenced = try await store.referencedAttachmentIDs()
        XCTAssertTrue(referenced.contains(image), "An image only a kept version uses isn't treated as unused")
        let copy = try await store.restoreHistoryCopy(version, to: journal.id)
        XCTAssertEqual(copy.document.attachmentIDs, [image])
        let restoredImage = try await store.attachment(image)
        XCTAssertEqual(restoredImage, bytes)
        let current = try await store.item(entry.id)
        XCTAssertEqual(current?.document.text, "Rewritten without the photo")
    }

    func testDeletePermanentlyRemovesCheckpoints() async throws {
        let store = try await openStore()
        let journal = try await store.save(JournalItem(kind: "journal", title: "Work"))
        var entry = try await store.save(
            JournalItem(kind: "entry", journalID: journal.id, title: "Plan", document: .plain("Draft")))
        try await edit(store, &entry, "Final", after: 20)
        let kept = try await texts(store, entry)
        XCTAssertEqual(kept, ["Draft"])
        advance(minutes: 20)
        entry.deletedAt = time.withLock { $0 }
        entry = try await store.save(entry)
        let unchanged = try await texts(store, entry)
        XCTAssertEqual(unchanged, ["Draft"], "Moving to Recently Deleted keeps no extra version")
        try await store.permanentlyDelete(try await store.preparePermanentDeletion(entry.id))
        let history = try await store.history(for: entry.id)
        XCTAssertEqual(history, [])
    }

    func testAChangeFromAnotherDeviceKeepsTheVersionItReplaces() async throws {
        let store = try await openStore()
        var entry = try await store.save(
            JournalItem(kind: "entry", journalID: UUID(), title: "Shared", document: .plain("Written here")))
        let queued = try await store.pending()
        let sent = try XCTUnwrap(queued.first)
        try await store.acknowledge(sent, receipt: receipt(sent.payload, for: entry, revision: 1))
        let other = try JournalStore(directory: root.appendingPathComponent("other"), key: key)
        entry.document = .plain("Changed on the other device")
        try await other.save(entry)
        let changed = try await other.pending()
        let incoming = try XCTUnwrap(changed.first)
        advance(minutes: 1)
        try await store.apply([receipt(incoming.payload, for: entry, revision: 2)], cursor: 2)
        let history = try await texts(store, entry)
        XCTAssertEqual(history, ["Written here"])
    }
    private func receipt(_ payload: String, for item: JournalItem, revision: Int64) -> RemoteChange {
        RemoteChange(
            cursor: revision, recordId: item.id, revision: revision, kind: item.kind, payload: payload,
            deviceId: UUID(), modifiedAt: Date())
    }
}
