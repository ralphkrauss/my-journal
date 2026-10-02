import Foundation
import XCTest

@testable import JournalCore

final class ImageDescriptionTests: XCTestCase {
    func testInlineImageDescriptionsPreserveTitlesAndConcurrentTextAcrossReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root, key: key)
        let journal = JournalItem(kind: "journal", title: "Default")
        try await store.save(journal)
        let attachment = try await store.addAttachment(Data("Synthetic image".utf8))
        let source =
            "Before [![Diagram](attachments/" + attachment.uuidString.lowercased()
            + " \"Image title\")](https://example.com \"Link title\") after."
        var entry = JournalItem(kind: "entry", journalID: journal.id, document: JournalDocument(markdown: source))
        try await store.save(entry)
        let baseline = entry.document.imageBlocks
        let image = try XCTUnwrap(baseline.first)
        entry.title = "Later title"
        try await store.save(entry)
        let updated = try await store.updateImageDescriptions(
            entry.id, expectedImages: baseline, descriptions: [image.id: "New description"])
        XCTAssertEqual(updated.title, "Later title")
        XCTAssertEqual(updated.document.attachmentIDs, [attachment])
        XCTAssertTrue(updated.document.markdown.contains("New description"))
        let parsed = JournalDocument(markdown: updated.document.markdown)
        let run = try XCTUnwrap(parsed.blocks.flatMap(\.runs).first { $0.imageSource != nil })
        XCTAssertEqual(run.imageTitle, "Image title")
        XCTAssertEqual(run.linkTitle, "Link title")
        XCTAssertEqual(run.link, "https://example.com")
        do {
            _ = try await store.updateImageDescriptions(
                entry.id, expectedImages: baseline, descriptions: [image.id: "Stale"])
            XCTFail("A stale inline image form must not overwrite a newer description")
        } catch ImageDescriptionError.changed {}
        try await store.close()
        let reopened = try JournalStore(directory: root, key: key)
        let saved = try await reopened.item(entry.id)
        XCTAssertEqual(saved?.document, updated.document)
        try await reopened.close()
    }

    func testDescriptionPatchPreservesLatestTextAndRepeatedAttachmentsAndRejectsStaleImages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root, key: key)
        let parent = JournalItem(kind: "journal", title: "Reflections")
        try await store.save(parent)
        let imageBytes = Data("Synthetic attachment".utf8)
        let attachment = try await store.addAttachment(imageBytes)
        let first = DocumentBlock(
            kind: "image", attachmentID: attachment, imageDescription: "Before", mediaType: "image/png")
        let second = DocumentBlock(kind: "image", attachmentID: attachment, mediaType: "image/png")
        var entry = JournalItem(
            kind: "entry", journalID: parent.id, title: "Original title",
            document: .init(blocks: [first, DocumentBlock(runs: [TextRun("Original body")]), second]))
        try await store.save(entry)
        let baseline = [first, second]
        entry.title = "Later title"
        entry.document.blocks[1].runs = [TextRun("Later body", bold: true)]
        try await store.save(entry)
        let pending = try await store.pending()
        let updated = try await store.updateImageDescriptions(
            entry.id, expectedImages: baseline,
            descriptions: [first.id: "Morning", second.id: "Evening"])
        XCTAssertEqual(updated.title, entry.title)
        XCTAssertEqual(updated.document.blocks[1], entry.document.blocks[1])
        XCTAssertEqual(updated.document.blocks.map(\.id), entry.document.blocks.map(\.id))
        XCTAssertEqual(updated.document.blocks[0].imageDescription, "Morning")
        XCTAssertEqual(updated.document.blocks[2].imageDescription, "Evening")
        XCTAssertEqual(updated.document.blocks[0].attachmentID, attachment)
        XCTAssertEqual(updated.document.blocks[2].attachmentID, attachment)
        XCTAssertEqual(updated.document.blocks[0].mediaType, first.mediaType)
        let retried = try await store.pending()
        XCTAssertEqual(retried.map(\.operationId), pending.map(\.operationId))
        XCTAssertEqual(retried.map(\.payload), pending.map(\.payload))
        do {
            _ = try await store.updateImageDescriptions(
                entry.id, expectedImages: baseline,
                descriptions: [first.id: "Stale", second.id: "Stale"])
            XCTFail("Changed descriptions require explicit review.")
        } catch ImageDescriptionError.changed {}
        let currentImages = updated.document.blocks.filter { $0.kind == "image" }
        var reordered = updated
        reordered.document.blocks.swapAt(0, 2)
        try await store.save(reordered)
        do {
            _ = try await store.updateImageDescriptions(
                entry.id, expectedImages: currentImages,
                descriptions: [first.id: "Wrong order", second.id: "Wrong order"])
            XCTFail("A changed image roster cannot reuse an older form.")
        } catch ImageDescriptionError.changed {}
        let plan = try await store.prepareJournalDeletion(parent.id)
        _ = try await store.deleteJournal(plan)
        do {
            _ = try await store.updateImageDescriptions(
                entry.id,
                expectedImages: reordered.document.blocks.filter { $0.kind == "image" },
                descriptions: [first.id: "Hidden", second.id: "Hidden"])
            XCTFail("Descriptions cannot modify an entry under a deleted journal.")
        } catch ImageDescriptionError.unavailable {}
        try await store.close()
        let reopened = try JournalStore(directory: root, key: key)
        let saved = try await reopened.item(entry.id)
        XCTAssertEqual(saved?.document, reordered.document)
        XCTAssertEqual(saved?.title, "Later title")
        let image = try await reopened.attachment(attachment)
        XCTAssertEqual(image, imageBytes)
        try await reopened.close()
    }
}
