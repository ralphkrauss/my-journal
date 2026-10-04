import JournalCore
import XCTest

@testable import Journal

/// Increase and Decrease Indent in lists (docs/design/list-indentation-2026-10-04.md), through the real editor on
/// each platform. Every result is read back from its Markdown: what the editor shows must be what the entry is when
/// it opens again, or on another device.
@MainActor final class ListIndentationTests: XCTestCase {
    /// The owner's journey: an item, Return, then Increase Indent on the new empty item, at the end of the entry and
    /// between two items. The empty item isn't mistaken for the plain line after a list.
    func testANewItemAfterReturnIndentsUnderTheItemAbove() throws {
        for (markdown, caretAfter, expected) in [
            ("- Milk", "Milk", "- Milk\n  - Eggs"),
            ("- Milk\n- Bread", "Milk", "- Milk\n  - Eggs\n- Bread"),
            ("1. Milk", "Milk", "1. Milk\n   1. Eggs"),
            ("- [ ] Milk", "Milk", "- [ ] Milk\n  - [ ] Eggs"),
        ] {
            let harness = EditorHarness(markdown: markdown)
            defer { harness.close() }
            harness.caret(at: NSMaxRange((harness.text.string as NSString).range(of: caretAfter)))
            harness.pressReturn()
            XCTAssertEqual(availability(harness), .init(increase: true, decrease: false), markdown)
            XCTAssertTrue(harness.coordinator.performStructuralKey(.indent), markdown)
            XCTAssertEqual(availability(harness), .init(increase: false, decrease: true), markdown)
            harness.type("Eggs")
            // The empty item couldn't follow its parent's line in Markdown without a blank line; the list keeps it.
            XCTAssertEqual(
                harness.document.markdown.replacingOccurrences(of: "\n\n", with: "\n").trimmingCharacters(
                    in: .newlines), expected, markdown)
            assertReadsBack(harness.document, markdown)
        }
    }

    func testEachKindOfItemIndentsAndOutdents() throws {
        for markdown in ["- One\n- Two", "1. One\n2. Two", "- [ ] One\n- [ ] Two", "- [x] One\n- [x] Two"] {
            let harness = EditorHarness(markdown: markdown)
            defer { harness.close() }
            harness.select("Two")
            harness.actions.captureFormatting()
            harness.actions.performFormatting(.indent)
            XCTAssertEqual(depths(harness.document), [0, 1], markdown)
            XCTAssertEqual(harness.document.blocks.map(\.kind), JournalDocument(markdown: markdown).blocks.map(\.kind))
            assertReadsBack(harness.document, markdown)
            harness.actions.performFormatting(.outdent)
            XCTAssertEqual(harness.document.markdown, markdown)
        }
    }

    /// A list's first item has nothing to nest under, and an item can go only one level below the item above it,
    /// and no deeper than the editor can draw. Tab there changes nothing; it doesn't type a tab into the item.
    func testItemsIndentOnlyWhereMarkdownKeepsIt() throws {
        let harness = EditorHarness(markdown: "- One\n- Two\n  - Three")
        defer { harness.close() }
        for target in ["One", "Three"] {
            harness.select(target)
            harness.caret(at: harness.selection.location)
            XCTAssertFalse(availability(harness).increase, target)
            XCTAssertTrue(harness.coordinator.performStructuralKey(.indent), target)
            XCTAssertEqual(harness.document.markdown, "- One\n- Two\n  - Three", target)
        }
        harness.select("One")
        XCTAssertFalse(availability(harness).decrease)
        XCTAssertTrue(harness.coordinator.performStructuralKey(.outdent))
        XCTAssertEqual(harness.document.markdown, "- One\n- Two\n  - Three")

        // At most as deep as the editor draws: 6 levels at this size. "Five b" could go to 6, but its nested items
        // would go to 7.
        let deepest = RichText.visibleNestingLevels(size: 17)
        XCTAssertEqual(deepest, 6)
        let lines =
            (0...5).map { String(repeating: "  ", count: $0) + "- Level \($0)" }
            + ["          - Five b", "            - Six b", "            - Six c"]
        let deep = EditorHarness(markdown: lines.joined(separator: "\n"))
        defer { deep.close() }
        deep.select("Six c")
        XCTAssertEqual(availability(deep), .init(increase: false, decrease: true))
        deep.select("Five b")
        XCTAssertEqual(availability(deep), .init(increase: false, decrease: true))
    }

    func testNestedItemsMoveWithTheirParent() throws {
        try checkIndent(.indent, "- a\n- b\n  - c\n    - d\n- e", at: "b", gives: "- a\n  - b\n    - c\n      - d\n- e")
        try checkIndent(
            .outdent, "- a\n  - b\n    - c\n      - d\n- e", at: "b", gives: "- a\n- b\n  - c\n    - d\n- e")
        // The item after an outdented one keeps its level, so it is now nested under it.
        try checkIndent(.outdent, "- a\n  - b\n  - c", at: "b", gives: "- a\n- b\n  - c")
        // Several items move together, with what is nested under the last of them.
        let harness = EditorHarness(markdown: "- a\n- b\n- c\n  - d\n- e")
        defer { harness.close() }
        let source = harness.text.string as NSString
        harness.select(NSRange(location: source.range(of: "b").location, length: 3))
        XCTAssertTrue(harness.coordinator.performStructuralKey(.indent))
        XCTAssertEqual(harness.document.markdown, "- a\n  - b\n  - c\n    - d\n- e")
        assertReadsBack(harness.document, "several")
    }

    /// Numbers follow the structure, as Markdown reads it: a new nested list starts at 1 and is written without a
    /// blank line, an item joining a nested list continues it, and the items after a moved one follow.
    func testNumberedListsAreNumberedAsTheyReadBack() throws {
        try checkIndent(.indent, "1. one\n2. two\n3. three", at: "two", gives: "1. one\n   1. two\n2. three")
        try checkIndent(.indent, "1. a\n   1. x\n2. b\n3. c", at: "b", gives: "1. a\n   1. x\n   2. b\n2. c")
        try checkIndent(.outdent, "1. a\n   1. x\n   2. b\n2. c", at: "x", gives: "1. a\n2. x\n   1. b\n3. c")
        // Under an item numbered 10 and up, nesting needs its wider marker.
        let ten = (1...10).map { "\($0). item \($0)" }.joined(separator: "\n") + "\n11. last"
        try checkIndent(
            .indent, ten, at: "last",
            gives: (1...10).map { "\($0). item \($0)" }.joined(separator: "\n") + "\n    1. last")
        // A numbered item can nest under a bullet, and a list's own first number is kept.
        try checkIndent(.indent, "- a\n1. b", at: "b", gives: "- a\n  1. b")
        try checkIndent(.indent, "5. five\n6. six", at: "six", gives: "5. five\n   1. six")
    }

    func testAListInAQuoteStaysInTheQuote() throws {
        try checkIndent(.indent, "> - a\n> - b", at: "b", gives: "> - a\n>   - b")
        let harness = EditorHarness(markdown: "> - a\n>   - b")
        defer { harness.close() }
        harness.select("a")
        XCTAssertEqual(availability(harness), .init(increase: false, decrease: false))
        harness.select("b")
        XCTAssertEqual(availability(harness), .init(increase: false, decrease: true))
    }

    /// Lists whose items hold other content, and selections across two lists, can't change safely: both commands are
    /// unavailable and Tab leaves the text as it is.
    func testListsThatCantChangeSafelyAreLeftAlone() throws {
        for (markdown, first, last) in [
            ("- a\n- b\n\n  More about b.\n- c", "c", "c"),
            ("- a\n- b\n\nBetween\n\n- c\n- d", "b", "c"),
        ] {
            let harness = EditorHarness(markdown: markdown)
            defer { harness.close() }
            let original = harness.document.markdown
            let source = harness.text.string as NSString
            let start = source.range(of: first).location
            harness.select(NSRange(location: start, length: NSMaxRange(source.range(of: last)) - start))
            XCTAssertEqual(availability(harness), .init(), markdown)
            _ = harness.coordinator.performStructuralKey(.indent)
            _ = harness.coordinator.performStructuralKey(.outdent)
            XCTAssertEqual(harness.document.markdown, original, markdown)
        }
    }

    /// The owner saw the indent buttons on the empty line after a list, where they did nothing: that line is a plain
    /// line, so the Format panel says Paragraph and both buttons are dimmed.
    func testTheLineAfterAListIsAPlainLine() throws {
        let harness = EditorHarness(markdown: "- one\n- two")
        defer { harness.close() }
        harness.caret(at: harness.text.length)
        harness.pressReturn()
        harness.pressReturn()
        harness.actions.captureFormatting()
        XCTAssertEqual(harness.actions.formattingState.paragraph, "paragraph")
        XCTAssertEqual(harness.actions.formattingState.indent, .init())
        XCTAssertEqual(availability(harness), .init())
    }

    func testUndoAndRedoRestoreTheListAndTheSelection() throws {
        for (key, markdown, target) in [
            (StructuredKeyboard.Key.indent, "1. a\n2. b\n   1. c\n3. d", "b"),
            (.outdent, "- a\n  - b\n    - c\n  - d", "b"),
        ] {
            let harness = EditorHarness(markdown: markdown)
            defer { harness.close() }
            let undo = try XCTUnwrap(harness.undoManager)
            harness.settle()
            undo.groupsByEvent = false
            while undo.groupingLevel > 0 { undo.endUndoGrouping() }
            undo.removeAllActions()
            harness.select(target)
            let selection = harness.selection
            undo.beginUndoGrouping()
            XCTAssertTrue(harness.coordinator.performStructuralKey(key))
            undo.endUndoGrouping()
            let changed = harness.document.markdown
            XCTAssertNotEqual(changed, markdown)
            undo.undo()
            harness.settle()
            XCTAssertEqual(harness.document.markdown, markdown)
            XCTAssertEqual(harness.selection, selection)
            undo.redo()
            harness.settle()
            XCTAssertEqual(harness.document.markdown, changed)
        }
    }

    /// Backspace at the start of a nested item moves it out a level with the items nested under it.
    func testBackspaceAtANestedItemsStartMovesItsNestedItemsToo() throws {
        let harness = EditorHarness(markdown: "- a\n  - b\n    - c")
        defer { harness.close() }
        harness.select("b")
        harness.caret(at: harness.selection.location)
        harness.deleteBackward()
        XCTAssertEqual(harness.document.markdown, "- a\n- b\n  - c")
    }

    // MARK: Helpers

    private func availability(_ harness: EditorHarness) -> ListIndentation.Availability {
        FormattingState.indentation(
            harness.text, range: harness.selection, typing: harness.view.typingAttributes, size: 17)
    }

    private func checkIndent(
        _ key: StructuredKeyboard.Key, _ markdown: String, at target: String, gives expected: String,
        line: UInt = #line
    ) throws {
        let harness = EditorHarness(markdown: markdown)
        defer { harness.close() }
        let source = harness.text.string as NSString
        let range = source.range(of: target)
        XCTAssertNotEqual(range.location, NSNotFound, line: line)
        harness.caret(at: range.location)
        XCTAssertTrue(harness.coordinator.performStructuralKey(key), line: line)
        XCTAssertEqual(harness.document.markdown, expected, line: line)
        assertReadsBack(harness.document, markdown, line: line)
    }

    /// Each item's kind, depth, number and text, as the editor holds them.
    private func structure(_ document: JournalDocument) -> [String] {
        document.blocks.filter { !$0.runs.isEmpty || ListIndentation.kinds.contains($0.kind) }.map { block in
            let number = block.kind == "numbered" ? "\(block.listNumber ?? 0)." : ""
            return "\(block.listIndents?.count ?? 0) \(block.kind)\(number) \(block.runs.map(\.text).joined())"
        }
    }

    private func depths(_ document: JournalDocument) -> [Int] {
        document.blocks.map { $0.listIndents?.count ?? 0 }
    }

    /// The Markdown the editor saved reads back as the structure the editor shows.
    private func assertReadsBack(_ document: JournalDocument, _ label: String, line: UInt = #line) {
        XCTAssertEqual(
            structure(JournalDocument(markdown: document.markdown)), structure(document), label, line: line)
    }
}
