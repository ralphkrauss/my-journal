import JournalCore
import SwiftUI
import XCTest

@testable import Journal

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Writing next to images, tables, rules and hidden list markers must save exactly what the person sees.
@MainActor final class EditorContentSafetyTests: XCTestCase {
    private var table: DocumentBlock {
        var block = DocumentBlock(kind: "table")
        block.table = DocumentTable(
            rows: [[[TextRun("Name")], [TextRun("Value")]], [[TextRun("A")], [TextRun("B")]]], alignments: [nil, nil])
        return block
    }

    func testTypingAfterAnInsertedImageKeepsTheTextAndASingleImage() throws {
        let harness = EditorHarness(markdown: "Hello")
        defer { harness.close() }
        harness.caret(at: harness.text.length)
        let attachment = UUID()
        harness.coordinator.perform(
            .image(DocumentBlock(kind: "image", attachmentID: attachment, imageDescription: "", mediaType: "image/png"))
        )
        harness.type("World")
        XCTAssertTrue(harness.document.markdown.contains("World"), harness.document.markdown)
        XCTAssertEqual(harness.document.references(to: attachment), 1, harness.document.markdown)
    }

    func testTypingOnTheEmptyLineAfterAnImageTableOrRuleKeepsTheText() throws {
        let attachment = UUID()
        let image = DocumentBlock(kind: "image", attachmentID: attachment, imageDescription: "", mediaType: "image/png")
        for block in [image, table, DocumentBlock(kind: "rule")] {
            let harness = EditorHarness(
                JournalDocument(blocks: [DocumentBlock(runs: [TextRun("Hello")]), block, DocumentBlock()]))
            defer { harness.close() }
            // As a click below the block puts the caret there.
            harness.caret(at: harness.text.length)
            harness.type("World")
            let saved = harness.document
            XCTAssertEqual(saved.blocks.last?.kind, "paragraph", "\(block.kind): \(saved.markdown)")
            XCTAssertEqual(saved.blocks.last?.runs.map(\.text).joined(), "World", "\(block.kind): \(saved.markdown)")
            XCTAssertEqual(saved.blocks.filter { $0.kind == block.kind }.count, 1, "\(block.kind): \(saved.markdown)")
            XCTAssertEqual(saved.references(to: attachment), block.kind == "image" ? 1 : 0, saved.markdown)
        }
    }

    func testTypingBesideAnImageOnItsOwnLineKeepsTheTextAndASingleImage() throws {
        let attachment = UUID()
        let harness = EditorHarness(
            JournalDocument(blocks: [
                DocumentBlock(runs: [TextRun("Hello")]),
                DocumentBlock(kind: "image", attachmentID: attachment, imageDescription: "", mediaType: "image/png"),
                DocumentBlock(runs: [TextRun("After")]),
            ]))
        defer { harness.close() }
        let image = (harness.text.string as NSString).range(of: "\u{FFFC}")
        harness.caret(at: NSMaxRange(image))
        harness.type("Beside")
        // Images arriving afterwards must not turn the typed text into more pictures.
        harness.update { $0.images = [attachment: Data([1, 2, 3])] }
        let saved = harness.document
        XCTAssertTrue(saved.text.contains("Beside"), saved.markdown)
        XCTAssertTrue(saved.text.contains("After"), saved.markdown)
        XCTAssertEqual(saved.references(to: attachment), 1, saved.markdown)
        harness.type("!")
        XCTAssertEqual(harness.document.references(to: attachment), 1, harness.document.markdown)
        XCTAssertTrue(harness.document.text.contains("Beside!"), harness.document.markdown)
    }

    func testTypingInsideACodeBlockKeepsOneCodeBlock() throws {
        let harness = EditorHarness(markdown: "Before\n\n```\nlet x = 1\nlet y = 2\n```\n\nAfter")
        defer { harness.close() }
        harness.caret(at: NSMaxRange((harness.text.string as NSString).range(of: "= 1")))
        harness.type("0")
        harness.caret(at: (harness.text.string as NSString).range(of: "let y").location)
        harness.type("Z")
        XCTAssertEqual(harness.document.markdown, "Before\n\n```\nlet x = 10\nZlet y = 2\n```\n\nAfter")
    }

    func testTypingAtTheStartOfAnItemIsVisibleAndSavedWithoutMarkers() throws {
        for (markdown, expected) in [
            ("- [ ] Buy milk", "- [ ] XBuy milk"), ("> Quoted", "> XQuoted"), ("- Point", "- XPoint"),
            ("3. Third", "3. XThird"), ("# Heading", "# XHeading"),
        ] {
            let harness = EditorHarness(markdown: markdown)
            defer { harness.close() }
            // Home, a click at the start of the line, or ⌘A: the caret never lands inside the hidden marker.
            harness.caret(at: 0)
            harness.type("X")
            XCTAssertEqual(
                harness.document.markdown.trimmingCharacters(in: .newlines), expected, harness.document.markdown)
            let typed = (harness.text.string as NSString).range(of: "X")
            let attributes = harness.text.attributes(at: typed.location, effectiveRange: nil)
            XCTAssertFalse(HiddenMarkers.isInvisible(attributes), markdown)
        }
    }

    func testBackspaceAtTheStartOfAnItemNeverSavesItsHiddenMarker() throws {
        // The first Backspace removes the item's formatting (as in Notes); the text stays, without marker glyphs.
        for (markdown, expected) in [
            ("- [ ] Buy milk", "XBuy milk"), ("> Buy milk", "XBuy milk"), ("- Buy milk", "XBuy milk"),
        ] {
            let harness = EditorHarness(markdown: markdown)
            defer { harness.close() }
            harness.caret(at: (harness.text.string as NSString).range(of: "Buy").location)
            harness.deleteBackward()
            harness.type("X")
            XCTAssertEqual(harness.document.markdown.trimmingCharacters(in: .newlines), expected, markdown)
            let typed = (harness.text.string as NSString).range(of: "X")
            XCTAssertFalse(HiddenMarkers.isInvisible(harness.text.attributes(at: typed.location, effectiveRange: nil)))
        }
    }

    func testJoiningLinesAcrossAHiddenMarkerSavesOnlyTheText() throws {
        let harness = EditorHarness(markdown: "Previous\n\n- [ ] Buy milk")
        defer { harness.close() }
        // Forward delete at the end of the line above, as a selected line break shows it.
        harness.select(NSRange(location: (harness.text.string as NSString).range(of: "Previous").length, length: 1))
        harness.deleteBackward()
        XCTAssertEqual(harness.document.markdown.trimmingCharacters(in: .newlines), "PreviousBuy milk")
        XCTAssertEqual(harness.text.string, "PreviousBuy milk")
    }

    func testMarkersAreReadByTheirAttributeNotTheirShape() {
        let item = RichText.render(
            .init(blocks: [DocumentBlock(kind: "numbered", runs: [TextRun("Buy")])]), size: 17, images: [:])
        let text = NSMutableAttributedString(
            string: "Note: ", attributes: item.attributes(at: item.length - 1, effectiveRange: nil))
        text.append(item)
        // Text that only looks like a marker is content.
        text.append(
            NSAttributedString(string: " •\t☐", attributes: item.attributes(at: item.length - 1, effectiveRange: nil)))
        let read = RichText.document(text)
        XCTAssertEqual(read.blocks.map(\.kind), ["numbered"])
        XCTAssertEqual(read.blocks.first?.runs.map(\.text).joined(), "Note: Buy •\t☐")
    }

    func testPastingRichTextInSourceViewKeepsTheMarkdown() throws {
        let source = "# Heading\n\n**Bold** and ![](attachments/\(UUID().uuidString.lowercased()))"
        let harness = EditorHarness(markdown: source)
        defer { harness.close() }
        harness.coordinator.perform(.source)
        XCTAssertTrue(harness.actions.sourceMode)
        let markdown = harness.document.markdown
        harness.caret(at: 0)
        harness.pasteRichText(
            NSAttributedString(
                string: "Pasted ",
                attributes: [
                    .font: PlatformFont(name: "Times New Roman", size: 12) ?? PlatformFont.systemFont(ofSize: 12)
                ]))
        XCTAssertEqual(harness.document.markdown, "Pasted " + markdown)
        XCTAssertEqual(harness.text.attribute(.journalSource, at: 0, effectiveRange: nil) as? Bool, true)
        harness.type("x")
        XCTAssertEqual(harness.document.markdown, "Pasted x" + markdown)
        // Emptying the source and typing again stays in the source.
        harness.select(NSRange(location: 0, length: harness.text.length))
        harness.deleteBackward()
        harness.type("# New")
        XCTAssertTrue(harness.actions.sourceMode)
        XCTAssertEqual(harness.document.blocks.first?.kind, "heading", harness.document.markdown)
    }

    func testPastedTextTakesTheEditorsFontsAndColoursAndKeepsItsEmphasis() throws {
        let harness = EditorHarness(markdown: "# Heading\n\nBody text")
        defer { harness.close() }
        let foreignFont =
            PlatformFont(name: "Times New Roman Bold", size: 12) ?? PlatformFont.boldSystemFont(ofSize: 12)
        let foreign: [NSAttributedString.Key: Any] = [
            .font: foreignFont, .foregroundColor: PlatformColor(red: 0, green: 0, blue: 0, alpha: 1),
            .backgroundColor: PlatformColor.yellow,
        ]
        for (target, kind) in [("text", "paragraph"), ("Heading", "heading")] {
            let range = (harness.text.string as NSString).range(of: target)
            harness.caret(at: NSMaxRange(range))
            harness.pasteRichText(NSAttributedString(string: " pasted", attributes: foreign))
            let pasted = (harness.text.string as NSString).range(of: " pasted")
            let attributes = harness.text.attributes(at: pasted.location + 1, effectiveRange: nil)
            let own = RichText.attributes(kind: kind, size: 17, run: TextRun("", bold: true))
            XCTAssertEqual((attributes[.font] as? PlatformFont)?.pointSize, (own[.font] as? PlatformFont)?.pointSize)
            XCTAssertEqual(attributes[.foregroundColor] as? PlatformColor, PlatformColor.labelColorCompat)
            XCTAssertNil(attributes[.backgroundColor])
            XCTAssertEqual(attributes[.journalKind] as? String, kind)
        }
        XCTAssertEqual(harness.document.blocks.map(\.kind), ["heading", "paragraph"])
        XCTAssertEqual(
            harness.document.blocks.map { $0.runs.map(\.text).joined() }, ["Heading pasted", "Body text pasted"])
        XCTAssertTrue(harness.document.blocks[1].runs.contains { $0.bold && $0.text.contains("pasted") })
    }
}
