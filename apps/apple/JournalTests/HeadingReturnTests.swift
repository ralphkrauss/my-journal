import JournalCore
import SwiftUI
import XCTest

@testable import Journal

/// Return in a heading: two headings in the middle, a paragraph at the end, an empty paragraph above at the start,
/// and an empty heading becomes a paragraph (docs/design/1-1-settings-messages-editor.md §5).
@MainActor
final class HeadingReturnTests: XCTestCase {
    private static let levels = ["heading", "subheading", "heading3", "heading4", "heading5", "heading6"]

    private func render(_ kind: String, text: String = "Hello world") -> (NSMutableAttributedString, UUID) {
        let heading = DocumentBlock(kind: kind, runs: text.isEmpty ? [] : [TextRun(text)])
        let document = JournalDocument(blocks: [
            DocumentBlock(runs: [TextRun("Intro")]), heading, DocumentBlock(runs: [TextRun("After")]),
        ])
        return (
            NSMutableAttributedString(attributedString: RichText.render(document, size: 17, images: [:])), heading.id
        )
    }
    private func pressReturn(_ text: NSMutableAttributedString, at caret: Int, selecting length: Int = 0) throws
        -> RichText.NewlineAction
    {
        let action = try XCTUnwrap(
            RichText.newlineAction(text, selection: NSRange(location: caret, length: length), size: 17))
        text.replaceCharacters(in: action.range, with: action.replacement)
        return action
    }
    private func texts(_ document: JournalDocument) -> [String] { document.blocks.map { $0.runs.map(\.text).joined() } }

    func testReturnInTheMiddleMakesTwoHeadingsOfTheSameLevelWithTheSecondOneNew() throws {
        for kind in Self.levels {
            let (text, original) = render(kind)
            let caret = (text.string as NSString).range(of: "Hello").upperBound
            let action = try pressReturn(text, at: caret)
            XCTAssertEqual(action.caret, caret + 1, kind)
            let document = RichText.document(text)
            XCTAssertEqual(document.blocks.map(\.kind), ["paragraph", kind, kind, "paragraph"], kind)
            XCTAssertEqual(texts(document), ["Intro", "Hello", " world", "After"], "The tail is not trimmed: \(kind)")
            XCTAssertEqual(document.blocks[1].id, original, "The first half keeps the block: \(kind)")
            XCTAssertNotEqual(document.blocks[2].id, original, kind)
            // The identity is part of the text: reading it again gives the same two, not a new random one.
            XCTAssertEqual(RichText.document(text).blocks.map(\.id), document.blocks.map(\.id), kind)
            let typing = RichText.typing(after: action, in: text, size: 17)
            XCTAssertEqual(typing[.journalKind] as? String, kind, "Typing continues the heading: \(kind)")
            XCTAssertNil(typing[.link], kind)
            // Two headings, so the Markdown writes two (a leading space is dropped, as for any heading).
            XCTAssertEqual(document.markdown.components(separatedBy: "\n").filter { $0.hasSuffix("world") }.count, 1)
        }
    }
    func testReturnAtTheEndStartsAParagraphAndAtTheStartAddsOneAbove() throws {
        for kind in Self.levels {
            let (atEnd, original) = render(kind)
            let end = (atEnd.string as NSString).range(of: "world").upperBound
            let action = try pressReturn(atEnd, at: end)
            XCTAssertEqual(action.nextKind, "paragraph", kind)
            XCTAssertEqual(
                RichText.document(atEnd).blocks.map(\.kind), ["paragraph", kind, "paragraph", "paragraph"], kind)

            let (atStart, startOriginal) = render(kind)
            let start = (atStart.string as NSString).range(of: "Hello").location
            let above = try pressReturn(atStart, at: start)
            XCTAssertEqual(above.caret, start + 1, "The caret stays at the start of the heading text: \(kind)")
            let document = RichText.document(atStart)
            XCTAssertEqual(document.blocks.map(\.kind), ["paragraph", "paragraph", kind, "paragraph"], kind)
            XCTAssertEqual(texts(document), ["Intro", "", "Hello world", "After"], kind)
            XCTAssertEqual(document.blocks[2].id, startOriginal, "The heading keeps its identity: \(kind)")
            XCTAssertNotEqual(original, startOriginal)
        }
    }
    func testReturnInAnEmptyHeadingMakesItAParagraph() throws {
        for kind in Self.levels {
            let (text, _) = render(kind, text: "")
            let caret = (text.string as NSString).range(of: "Intro\n").upperBound
            let action = try pressReturn(text, at: caret)
            XCTAssertEqual(action.caret, caret, "The caret stays on the line: \(kind)")
            let document = RichText.document(text)
            XCTAssertEqual(document.blocks.map(\.kind), ["paragraph", "paragraph", "paragraph"], kind)
            XCTAssertEqual(texts(document), ["Intro", "", "After"], "No line is added: \(kind)")
        }
    }
    func testReturnReplacesASelectionFirstAndClassifiesWhereTheCaretLands() throws {
        let (middle, original) = render("subheading")
        let range = (middle.string as NSString).range(of: "lo wo")
        _ = try pressReturn(middle, at: range.location, selecting: range.length)
        let split = RichText.document(middle)
        XCTAssertEqual(texts(split), ["Intro", "Hel", "rld", "After"])
        XCTAssertEqual(split.blocks.map(\.kind), ["paragraph", "subheading", "subheading", "paragraph"])
        XCTAssertEqual(split.blocks[1].id, original)

        let (whole, _) = render("subheading")
        let all = (whole.string as NSString).range(of: "Hello world")
        _ = try pressReturn(whole, at: all.location, selecting: all.length)
        XCTAssertEqual(texts(RichText.document(whole)), ["Intro", "", "After"])
        XCTAssertEqual(RichText.document(whole).blocks[1].kind, "paragraph", "The emptied heading becomes a paragraph.")
    }

    /// The journey in the editor: one Return splits, undo restores the single heading with its identity, redo the two.
    func testSplittingIsOneUndoStepThatRestoresTheOriginalIdentity() throws {
        let harness = EditorHarness(markdown: "## Hello world\n\nAfter")
        defer { harness.close() }
        let original = try XCTUnwrap(harness.document.blocks.first).id
        let undo = try XCTUnwrap(harness.undoManager)
        undo.groupsByEvent = false
        while undo.groupingLevel > 0 { undo.endUndoGrouping() }
        undo.removeAllActions()
        harness.caret(at: 5)
        undo.beginUndoGrouping()
        harness.pressReturn()
        undo.endUndoGrouping()
        let split = harness.document
        XCTAssertEqual(split.blocks.map(\.kind), ["subheading", "subheading", "paragraph"])
        XCTAssertEqual(texts(split), ["Hello", " world", "After"])
        XCTAssertEqual(split.blocks[0].id, original)
        XCTAssertEqual(
            harness.selection, NSRange(location: 6, length: 0), "The caret is at the start of the second heading.")
        undo.beginUndoGrouping()
        harness.type("big")
        undo.endUndoGrouping()
        XCTAssertEqual(harness.document.blocks.map(\.kind), ["subheading", "subheading", "paragraph"])
        XCTAssertEqual(texts(harness.document)[1], "big world", "Typing at the start keeps it a heading.")
        undo.undo()
        undo.undo()
        XCTAssertEqual(
            harness.document.blocks.map(\.kind), ["subheading", "paragraph"], "One undo step undid the split.")
        XCTAssertEqual(harness.document.blocks[0].id, original)
        XCTAssertEqual(texts(harness.document), ["Hello world", "After"])
        undo.redo()
        XCTAssertEqual(harness.document.blocks.map(\.kind), ["subheading", "subheading", "paragraph"])
        XCTAssertEqual(harness.document.blocks[0].id, original)
        XCTAssertNotEqual(harness.document.blocks[1].id, original)
    }
    /// Return that commits an input method's composition is the input method's; the heading is not split.
    func testReturnDuringCompositionOnlyCommitsIt() throws {
        let harness = EditorHarness(markdown: "## Hello world")
        defer { harness.close() }
        harness.caret(at: 5)
        harness.compose("x")
        XCTAssertTrue(harness.isComposing)
        let before = harness.text.string
        #if os(macOS)
            XCTAssertFalse(
                harness.coordinator.textView(harness.view, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #else
            XCTAssertTrue(
                harness.coordinator.textView(harness.view, shouldChangeTextIn: harness.selection, replacementText: "\n")
            )
        #endif
        XCTAssertEqual(harness.text.string, before)
        XCTAssertEqual(harness.document.blocks.count, 1)
    }
    /// "# Title", Return, then text: the Return is at the end, so the text is a paragraph, as before.
    func testATypedKeyBurstStillEndsInAParagraph() {
        let harness = EditorHarness(markdown: "")
        defer { harness.close() }
        harness.type("# Title")
        harness.wait { harness.document.blocks.first?.kind == "heading" }
        harness.pressReturn()
        harness.type("Text")
        XCTAssertEqual(harness.document.blocks.map(\.kind), ["heading", "paragraph"])
        XCTAssertEqual(texts(harness.document), ["Title", "Text"])
    }
}
