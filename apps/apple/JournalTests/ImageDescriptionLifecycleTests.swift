import CryptoKit
import JournalCore
import SwiftUI
import XCTest

@testable import Journal

@MainActor
final class ImageDescriptionLifecycleTests: XCTestCase {
    func testDescriptionsPreserveNewerStoredBodyAndNativeRoundTripAfterReopen() async throws {
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
        var entry = try XCTUnwrap(model.draft)
        let picture = DocumentBlock(kind: "image", attachmentID: UUID(), mediaType: "image/png")
        entry.document = .init(blocks: [DocumentBlock(runs: [TextRun("Before")]), picture])
        model.updateDraft(entry)
        let saved = await model.finishPendingSave()
        XCTAssertTrue(saved)
        if let preview = await NativeTestPreview.capture(
            ImageDescriptionsView(entry: entry).environmentObject(model),
            name: "Image descriptions with unavailable preview")
        {
            add(preview)
        }
        if let preview = await NativeTestPreview.capture(
            ImageDescriptionsView(entry: entry).environmentObject(model).preferredColorScheme(.dark)
                .environment(\.dynamicTypeSize, .accessibility5), name: "Image descriptions dark largest text")
        {
            add(preview)
        }
        var newer = try XCTUnwrap(model.draft)
        newer.document.blocks[0].runs = [TextRun("Newer body from storage", bold: true)]
        newer.title = "More recent title"
        try await store.save(newer)
        // Do not refresh the old displayed snapshot before the patch.
        let patched = try await model.saveImageDescriptions(
            entryID: entry.id, expectedImages: [picture],
            descriptions: [picture.id: "A path through the forest"])
        XCTAssertTrue(patched)
        let current = try XCTUnwrap(model.draft)
        XCTAssertEqual(current.title, newer.title)
        XCTAssertEqual(current.document.blocks[0], newer.document.blocks[0])
        XCTAssertEqual(current.document.blocks[1].imageDescription, "A path through the forest")
        XCTAssertEqual(current.document.blocks[1].attachmentID, picture.attachmentID)
        let roundTrip = RichText.document(RichText.render(current.document, size: 17, images: [:]))
        XCTAssertEqual(roundTrip, current.document)
        do {
            _ = try await model.saveImageDescriptions(
                entryID: entry.id, expectedImages: [picture],
                descriptions: [picture.id: "Stale change"])
            XCTFail("An older form cannot replace a changed description.")
        } catch ImageDescriptionError.changed {}
        let unchanged = try await store.item(entry.id)
        XCTAssertEqual(unchanged?.document, current.document)
        let refreshed = try await model.reloadImageDescriptionEntry(entry.id)
        XCTAssertEqual(refreshed.document, current.document)
        try await store.close()
        var unsaved = current
        unsaved.title = "Retain this unsaved entry"
        model.updateDraft(unsaved)
        do {
            _ = try await model.saveImageDescriptions(
                entryID: entry.id,
                expectedImages: current.document.blocks.filter { $0.kind == "image" },
                descriptions: [picture.id: "Keep these local descriptions"])
            XCTFail("A failed entry save needs an explicit recovery route, not a repeating description retry.")
        } catch ImageDescriptionError.entrySaveRequired {}
        XCTAssertTrue(model.saveFailure)
        XCTAssertEqual(model.draft?.title, unsaved.title)
        let reopened = AppModel(directory: root)
        await reopened.load()
        XCTAssertEqual(reopened.draft?.document, current.document)
        XCTAssertEqual(reopened.draft?.title, newer.title)
        try await reopened.store?.close()
    }
    /// A right-click on a Mac list row leaves the open entry as it is, so the row's own content decides.
    func testRowOffersImageDescriptionsWithoutBeingTheOpenEntry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try JournalStore(directory: root, key: try VaultCrypto.generateKey())
        let journal = JournalItem(kind: "journal", title: "Personal")
        let picture = DocumentBlock(kind: "image", attachmentID: UUID(), mediaType: "image/png")
        let pictured = JournalItem(
            kind: "entry", journalID: journal.id, title: "Walk",
            document: JournalDocument(blocks: [DocumentBlock(runs: [TextRun("Before")]), picture]))
        let open = JournalItem(kind: "entry", journalID: journal.id, title: "Open")
        var deleted = pictured
        deleted.id = UUID()
        deleted.deletedAt = Date()
        for item in [journal, pictured, open, deleted] { try await store.save(item) }
        let model = AppModel(directory: root)
        model.store = store
        model.loaded = true
        try await model.refresh()
        model.selectedJournalID = journal.id
        model.selectedID = open.id
        model.draft = model.items.first { $0.id == open.id }
        XCTAssertTrue(model.offersImageDescriptions(for: pictured))
        XCTAssertFalse(model.offersImageDescriptions(for: deleted), "Recently Deleted can't be edited")
        XCTAssertFalse(model.offersImageDescriptions(for: open), "No images to describe")
        try await store.close()
    }

    func testLockAfterDescriptionCommitCannotRestoreOldDescription() async throws {
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
        var entry = try XCTUnwrap(model.draft)
        let block = DocumentBlock(kind: "image", attachmentID: UUID(), imageDescription: "Before lock")
        entry.document = .init(blocks: [block])
        model.updateDraft(entry)
        let flushed = await model.finishPendingSave()
        XCTAssertTrue(flushed)
        await model.turnOnAppLockForTesting()
        let committed = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let entryID = entry.id
        let saving = Task {
            try await model.commitImageDescriptionUpdate {
                let saved = try await store.updateImageDescriptions(
                    entryID, expectedImages: [block],
                    descriptions: [block.id: "Committed description"])
                committed.continuation.yield(())
                committed.continuation.finish()
                for await _ in release.stream { break }
                return saved
            }
        }
        for await _ in committed.stream { break }
        let locking = Task { await model.lock() }
        while !model.locked { await Task.yield() }
        release.continuation.yield(())
        release.continuation.finish()
        _ = try await saving.value
        await locking.value
        XCTAssertTrue(model.locked)
        let saved = try await store.item(entryID)
        XCTAssertEqual(saved?.document.blocks.first?.imageDescription, "Committed description")
        await model.unlockForTesting()
        XCTAssertEqual(model.draft?.document.blocks.first?.imageDescription, "Committed description")
        try await store.close()
    }

}
