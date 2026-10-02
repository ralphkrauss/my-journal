import JournalCore
import XCTest

@testable import Journal

@MainActor
final class ImageLoadingLifecycleTests: XCTestCase {
    func testPreviewVersionsAndVaultReplacementDoNotRetainOtherImages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ImagePreview-" + UUID().uuidString)
        let firstStore = try JournalStore(
            directory: root.appendingPathComponent("first"), key: VaultCrypto.generateKey())
        let secondStore = try JournalStore(
            directory: root.appendingPathComponent("second"), key: VaultCrypto.generateKey())
        addTeardownBlock {
            try await firstStore.close()
            try await secondStore.close()
            try FileManager.default.removeItem(at: root)
        }
        let localID = try await firstStore.addAttachment(Data([1]))
        let remoteID = try await firstStore.addAttachment(Data([2]))
        _ = try await secondStore.addAttachment(Data([3]), id: remoteID)
        let local = JournalItem(
            kind: "entry",
            document: .init(blocks: [
                DocumentBlock(kind: "image", attachmentID: localID, mediaType: "image/png")
            ]))
        var remote = local
        remote.document.blocks[0].attachmentID = remoteID
        let preview = DocumentImageLoader()
        preview.update(local, store: firstStore, enabled: true)
        let stale = preview.task
        preview.update(remote, store: firstStore, enabled: true)
        await stale?.value
        await preview.task?.value
        XCTAssertEqual(preview.images, [remoteID: Data([2])])
        preview.update(remote, store: secondStore, enabled: true)
        XCTAssertTrue(preview.images.isEmpty)
        await preview.task?.value
        XCTAssertEqual(preview.images, [remoteID: Data([3])])
        preview.clear()
        XCTAssertTrue(preview.images.isEmpty)
        XCTAssertTrue(preview.loading.isEmpty)
    }

    func testRefreshingAnUnselectedVaultDoesNotLoadEveryAttachment() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Images-" + UUID().uuidString)
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        addTeardownBlock {
            try await store.close()
            try FileManager.default.removeItem(at: root)
        }
        let journal = JournalItem(kind: "journal", title: "Images")
        try await store.save(journal)
        for index in 0..<3 {
            let imageID = try await store.addAttachment(Data(repeating: UInt8(index), count: 1024 * 1024))
            try await store.save(
                JournalItem(
                    kind: "entry", journalID: journal.id, title: "Entry \(index)",
                    document: .init(blocks: [
                        DocumentBlock(kind: "image", attachmentID: imageID, mediaType: "image/png")
                    ])
                ))
        }
        let model = AppModel(directory: root)
        model.store = store
        try await model.refresh()
        XCTAssertNil(model.draft)
        XCTAssertTrue(model.imageData.isEmpty, "Opening the entry list must not retain every image in the vault.")
    }
    func testSelectionPrunesImagesAndRefreshRetriesMissingReferencesWithoutCrossingLock() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ImageSelection-" + UUID().uuidString)
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        addTeardownBlock {
            try await store.close()
            try FileManager.default.removeItem(at: root)
        }
        let journal = JournalItem(kind: "journal", title: "Images")
        let firstID = try await store.addAttachment(Data([1, 2, 3]))
        let secondID = UUID()
        let first = JournalItem(
            kind: "entry", journalID: journal.id,
            document: .init(blocks: [
                DocumentBlock(kind: "image", attachmentID: firstID, mediaType: "image/png")
            ]))
        let second = JournalItem(
            kind: "entry", journalID: journal.id,
            document: .init(blocks: [
                DocumentBlock(kind: "image", attachmentID: secondID, mediaType: "image/png")
            ]))
        for item in [journal, first, second] { try await store.save(item) }
        let model = AppModel(directory: root)
        model.store = store
        try await model.refresh()
        await model.select(first.id)
        await model.imageLoader.task?.value
        XCTAssertEqual(model.imageData, [firstID: Data([1, 2, 3])])
        await model.select(second.id)
        await model.imageLoader.task?.value
        XCTAssertTrue(model.imageData.isEmpty)
        XCTAssertTrue(model.imageLoader.loading.isEmpty)
        XCTAssertEqual(model.draft?.document, second.document)
        _ = try await store.addAttachment(Data([4, 5, 6]), id: secondID)
        try await model.refresh()
        XCTAssertEqual(model.imageData, [secondID: Data([4, 5, 6])])
        model.draft = first
        let pending = model.imageLoader.task
        model.locked = true
        await pending?.value
        XCTAssertTrue(model.imageData.isEmpty)
        XCTAssertTrue(model.imageLoader.loading.isEmpty)
        model.locked = false
        await model.imageLoader.task?.value
        XCTAssertEqual(model.imageData, [firstID: Data([1, 2, 3])])
        model.draft = nil
        XCTAssertTrue(model.imageData.isEmpty)
    }

}
