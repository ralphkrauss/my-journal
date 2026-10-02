import JournalCore
import XCTest

@testable import Journal

/// Backspace at the start of a list item, task or quote removes one level of its formatting before it joins lines,
/// as in Notes. A wrong range here would lose or duplicate writing, or save a hidden marker.
@MainActor
final class ItemFormattingRemovalTests: XCTestCase {
    func testBackspaceRemovesOneLevelAndKeepsTheText() throws {
        for (markdown, kind, prefix) in [
            ("- [ ] Buy milk", "paragraph", nil), ("- [x] Buy milk", "paragraph", nil),
            ("- Buy milk", "paragraph", nil),
            ("3. Buy milk", "paragraph", nil), ("> Buy milk", "paragraph", nil),
            // Innermost first: a list in a quote keeps the quote, and a nested quote keeps the outer one.
            ("> - Buy milk", "quote", nil), ("> > Buy milk", "quote", nil),
        ] as [(String, String, String?)] {
            let harness = EditorHarness(markdown: markdown)
            defer { harness.close() }
            harness.caret(at: (harness.text.string as NSString).range(of: "Buy").location)
            harness.deleteBackward()
            let block = try XCTUnwrap(harness.document.blocks.last, markdown)
            XCTAssertEqual(block.kind, kind, markdown)
            XCTAssertEqual(block.markdownPrefix, prefix, markdown)
            XCTAssertEqual(block.runs.map(\.text).joined(), "Buy milk", markdown)
            XCTAssertEqual(
                harness.selection.location, (harness.text.string as NSString).range(of: "Buy").location, markdown)
            let saved = harness.document.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(saved, kind == "quote" ? "> Buy milk" : "Buy milk", markdown)
        }
    }

    func testNestedItemMovesOutOneLevelAtATimeThenJoinsTheLineAbove() throws {
        let harness = EditorHarness(markdown: "Previous\n\n- Parent\n  - Buy milk")
        defer { harness.close() }
        func item() -> DocumentBlock? { harness.document.blocks.last }
        func caretAtText() { harness.caret(at: (harness.text.string as NSString).range(of: "Buy").location) }
        caretAtText()
        harness.deleteBackward()
        XCTAssertEqual(item()?.kind, "bullet")
        XCTAssertEqual(item()?.listIndents ?? [], [])
        harness.deleteBackward()
        XCTAssertEqual(item()?.kind, "paragraph")
        XCTAssertEqual(item()?.runs.map(\.text).joined(), "Buy milk")
        // Now at the start of a paragraph: Backspace joins it with the item above, as usual.
        harness.deleteBackward()
        XCTAssertEqual(harness.document.blocks.last?.runs.map(\.text).joined(), "ParentBuy milk")
        XCTAssertFalse(harness.document.markdown.contains("•"))
    }

    func testUndoBringsTheItemBackExactly() throws {
        let harness = EditorHarness(markdown: "- [x] Buy milk")
        defer { harness.close() }
        let before = harness.document
        let undo = try XCTUnwrap(harness.undoManager)
        harness.settle()
        undo.groupsByEvent = false
        while undo.groupingLevel > 0 { undo.endUndoGrouping() }
        undo.removeAllActions()
        harness.caret(at: (harness.text.string as NSString).range(of: "Buy").location)
        undo.beginUndoGrouping()
        harness.deleteBackward()
        undo.endUndoGrouping()
        XCTAssertEqual(harness.document.blocks.first?.kind, "paragraph")
        XCTAssertEqual(undo.undoActionName, "Paragraph")
        undo.undo()
        XCTAssertEqual(harness.document.markdown, before.markdown)
        XCTAssertEqual(harness.document.blocks.first?.kind, "checked")
    }

    func testBackspaceElsewhereInAnItemStillDeletesText() throws {
        let harness = EditorHarness(markdown: "- Buy milk")
        defer { harness.close() }
        harness.caret(at: (harness.text.string as NSString).range(of: "milk").location)
        harness.deleteBackward()
        XCTAssertEqual(harness.document.blocks.first?.kind, "bullet")
        XCTAssertEqual(harness.document.blocks.first?.runs.map(\.text).joined(), "Buymilk")
    }
}
