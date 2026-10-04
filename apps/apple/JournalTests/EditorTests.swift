import JournalCore
import XCTest

@testable import Journal

@MainActor
final class EditorTests: XCTestCase {
    func testNativeTextRoundTripPreservesInlineStylesLinksAndParagraphs() throws {
        let document = JournalDocument(blocks: [
            DocumentBlock(kind: "heading", runs: [TextRun("Reflection")]),
            DocumentBlock(runs: [
                TextRun("Plain "), TextRun("bold", bold: true), TextRun(" and "), TextRun("italic", italic: true),
                TextRun(" underlined", underline: true), TextRun(" link", link: "https://example.com"),
            ]),
            DocumentBlock(kind: "bullet", runs: [TextRun("First point")]),
            DocumentBlock(kind: "numbered", runs: [TextRun("Next action")]),
        ])
        let restored = RichText.document(RichText.render(document, size: 17, images: [:]))
        XCTAssertEqual(restored.blocks.map(\.kind), document.blocks.map(\.kind))
        XCTAssertEqual(restored.blocks.map(\.runs), document.blocks.map(\.runs))
        XCTAssertEqual(restored.blocks.map(\.id), document.blocks.map(\.id))
    }
    func testCodeBlocksRoundTripWithoutAnExtraBlankLine() {
        let document = JournalDocument(blocks: [
            DocumentBlock(kind: "codeBlock", runs: [TextRun("let x = 1\n")]),
            DocumentBlock(kind: "codeBlock", runs: [TextRun("typed")]),
            DocumentBlock(kind: "codeBlock", runs: [TextRun("")]),
            DocumentBlock(kind: "codeBlock", runs: [TextRun("blank below\n\n")]),
            DocumentBlock(runs: [TextRun("After")]),
        ])
        let rendered = RichText.render(document, size: 17, images: [:])
        XCTAssertEqual(rendered.string, "let x = 1\ntyped\n\nblank below\n\nAfter")
        let restored = RichText.document(rendered)
        XCTAssertEqual(restored.blocks.map(\.kind), document.blocks.map(\.kind))
        XCTAssertEqual(restored.blocks.map(\.runs), document.blocks.map(\.runs))
    }
    func testUnavailableImageRetainsReferenceAndDescriptionWhenEditingSurroundingText() throws {
        let attachment = UUID()
        let document = JournalDocument(blocks: [
            DocumentBlock(runs: [TextRun("Before")]),
            DocumentBlock(
                kind: "image", attachmentID: attachment, imageDescription: "A forest path", mediaType: "image/jpeg"),
            DocumentBlock(runs: [TextRun("After")]),
        ])
        let restored = RichText.document(RichText.render(document, size: 17, images: [:]))
        XCTAssertEqual(restored.blocks[1], document.blocks[1])
        XCTAssertEqual(restored.blocks[1].attachmentID, attachment)
        XCTAssertEqual(restored.blocks.last?.runs, document.blocks.last?.runs)
    }
    func testTextBesideAnAttachmentSurvivesConversion() {
        let image = DocumentBlock(kind: "image", attachmentID: UUID(), imageDescription: "A picture")
        let text = NSMutableAttributedString(
            string: "Before ", attributes: RichText.attributes(kind: "paragraph", size: 17))
        text.append(RichText.render(.init(blocks: [image]), size: 17, images: [:]))
        text.append(NSAttributedString(string: " after", attributes: RichText.attributes(kind: "paragraph", size: 17)))
        let restored = RichText.document(text)
        XCTAssertEqual(restored.blocks.map(\.kind), ["paragraph", "image", "paragraph"])
        XCTAssertEqual(restored.blocks[0].runs.map(\.text).joined(), "Before ")
        XCTAssertEqual(restored.blocks[1].attachmentID, image.attachmentID)
        XCTAssertEqual(restored.blocks[2].runs.map(\.text).joined(), " after")
        XCTAssertNotEqual(restored.blocks[0].id, image.id)
        XCTAssertNotEqual(restored.blocks[2].id, image.id)
    }
    func testListReturnContinuesAndEmptyListReturnsToBody() throws {
        let text = RichText.render(
            .init(blocks: [DocumentBlock(kind: "bullet", runs: [TextRun("A point")])]), size: 17, images: [:])
        let action = try XCTUnwrap(
            RichText.newlineAction(
                text, selection: NSRange(location: ("A point" as NSString).length, length: 0), size: 17))
        let continued = NSMutableAttributedString(attributedString: text)
        continued.replaceCharacters(in: action.range, with: action.replacement)
        // Only the line breaks are added: the new item has no marker characters, only its own line break.
        XCTAssertEqual(continued.string, "A point\n\n")
        XCTAssertEqual(action.nextKind, "bullet")
        XCTAssertEqual(RichText.document(continued).blocks.map(\.kind), ["bullet", "bullet"])
        let empty = RichText.render(.init(blocks: [DocumentBlock(kind: "bullet")]), size: 17, images: [:])
        let exit = try XCTUnwrap(RichText.newlineAction(empty, selection: NSRange(location: 0, length: 0), size: 17))
        XCTAssertEqual(exit.range, NSRange(location: 0, length: 1))
        XCTAssertEqual(exit.replacement.string, "")
        XCTAssertEqual(exit.nextKind, "paragraph")
    }
    func testReturnAfterLeavingAListStartsNewLinesAgain() throws {
        for trailing in [false, true] {
            var blocks = [
                DocumentBlock(kind: "numbered", runs: [TextRun("One")]),
                DocumentBlock(kind: "numbered", runs: [TextRun("Two")]),
            ]
            if trailing { blocks.append(DocumentBlock(runs: [TextRun("After")])) }
            let text = NSMutableAttributedString(
                attributedString: RichText.render(.init(blocks: blocks), size: 17, images: [:]))
            var caret = (text.string as NSString).range(of: "Two").upperBound
            func pressReturn() -> Bool {
                guard
                    let action = RichText.newlineAction(
                        text, selection: NSRange(location: caret, length: 0), size: 17)
                else { return false }
                text.replaceCharacters(in: action.range, with: action.replacement)
                caret = action.caret ?? action.range.location + action.replacement.length
                return true
            }
            XCTAssertTrue(pressReturn(), "Return continues the list")
            XCTAssertTrue(pressReturn(), "Return on the empty item leaves the list")
            let line = (text.string as NSString).paragraphRange(for: NSRange(location: caret, length: 0))
            XCTAssertEqual(
                (text.string as NSString).substring(with: line).trimmingCharacters(in: .newlines), "",
                "The caret stays on the emptied line")
            // The line is a plain paragraph now, so Return is the system's ordinary new line.
            XCTAssertFalse(pressReturn())
            XCTAssertEqual(RichText.document(text).blocks.map(\.kind).prefix(3), ["numbered", "numbered", "paragraph"])
        }
    }
    func testNewParagraphsGetDistinctIDsAndEmptyParagraphSurvives() {
        let original = JournalDocument.plain("First\n\nThird\n")
        let restored = RichText.document(RichText.render(original, size: 17, images: [:]))
        XCTAssertEqual(restored.text, original.text)
        XCTAssertEqual(Set(restored.blocks.map(\.id)).count, restored.blocks.count)
    }

    func testPrefixReplacementRecoversOnlyItsOwnParagraphIdentity() {
        let original = JournalDocument(blocks: [
            DocumentBlock(runs: [TextRun("First paragraph")]),
            DocumentBlock(runs: [TextRun("Second paragraph")]),
        ])
        let text = NSMutableAttributedString(attributedString: RichText.render(original, size: 17, images: [:]))
        text.replaceCharacters(
            in: NSRange(location: 0, length: 5),
            with: NSAttributedString(string: "Edited", attributes: RichText.attributes(kind: "paragraph", size: 17)))
        var expected = original
        expected.blocks[0].runs = [TextRun("Edited paragraph")]
        XCTAssertEqual(RichText.document(text), expected)
        text.addAttribute(.journalBlockID, value: "invalid", range: NSRange(location: 0, length: 6))
        XCTAssertEqual(RichText.document(text), expected)
        let leadingID = UUID()
        text.addAttribute(.journalBlockID, value: leadingID.uuidString, range: NSRange(location: 0, length: 6))
        XCTAssertEqual(RichText.document(text).blocks[0].id, leadingID)
        let firstParagraph = (text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
        text.removeAttribute(.journalBlockID, range: firstParagraph)
        let withoutIdentity = RichText.document(text)
        XCTAssertNotEqual(withoutIdentity.blocks[0].id, original.blocks[0].id)
        XCTAssertNotEqual(withoutIdentity.blocks[0].id, original.blocks[1].id)
        XCTAssertEqual(withoutIdentity.blocks[1], original.blocks[1])
        XCTAssertEqual(withoutIdentity.blocks[0].runs, expected.blocks[0].runs)
    }
}
