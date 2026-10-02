import JournalCore
import SwiftUI
import XCTest

@testable import Journal

@MainActor
final class StructuredSelectionTests: XCTestCase {
    func testMixedSelectionRetainsEveryBlockAndCompletesAllTasks() throws {
        let id = UUID()
        let original = JournalDocument(
            markdown:
                "- [ ] First\n- [x] Second\n\nParagraph ![Image](attachments/\(id.uuidString.lowercased()))\n\n| A | B |\n| --- | --- |\n| C | D |\n\n```\ncode\n```\n\nLast"
        )
        let text = RichText.render(original, size: 17, images: [:])
        let selection = NSRange(location: 0, length: text.length)
        let edit = try XCTUnwrap(StructuredKeyboard.edit(.toggleTask, text: text, selection: selection, size: 17))
        let updated = applying(edit, to: text)
        let read = MarkdownEditing.read(updated, previous: original)
        XCTAssertEqual(read.blocks.map(\.kind), original.blocks.map { $0.kind == "task" ? "checked" : $0.kind })
        XCTAssertEqual(read.blocks.map(\.runs), original.blocks.map(\.runs))
        XCTAssertEqual(read.blocks.first { $0.table != nil }?.table, original.blocks.first { $0.table != nil }?.table)
        XCTAssertEqual(read.attachmentIDs, [id])
        let uncheck = try XCTUnwrap(
            StructuredKeyboard.edit(
                .toggleTask, text: updated, selection: NSRange(location: 0, length: updated.length), size: 17))
        let unchecked = MarkdownEditing.read(applying(uncheck, to: updated), previous: read)
        XCTAssertEqual(unchecked.blocks.filter { $0.kind == "task" }.count, 2)
        XCTAssertTrue(unchecked.markdown.contains("Last"))
    }

    func testIndentAndOutdentMultipleItemsPreserveContent() throws {
        let original = JournalDocument(markdown: "- First\n- Second\n- Third\n\nAfter")
        let text = RichText.render(original, size: 17, images: [:])
        let selection = NSRange(location: 0, length: text.length)
        let indent = try XCTUnwrap(StructuredKeyboard.edit(.indent, text: text, selection: selection, size: 17))
        let indented = applying(indent, to: text)
        let outdent = try XCTUnwrap(
            StructuredKeyboard.edit(
                .outdent, text: indented, selection: NSRange(location: 0, length: indented.length), size: 17))
        let read = MarkdownEditing.read(applying(outdent, to: indented), previous: original)
        XCTAssertEqual(read.blocks.map(\.runs), original.blocks.map(\.runs))
        XCTAssertEqual(read.blocks.map(\.kind), original.blocks.map(\.kind))
    }

    func testMultilineCodeIndentPreservesTextAndRejectsCrossBlockSelection() throws {
        let original = JournalDocument(markdown: "```swift\nfirst()\nsecond()\n```\n\nAfter")
        let text = RichText.render(original, size: 17, images: [:])
        let source = text.string as NSString
        let range = source.range(of: "first()\nsecond()")
        let indent = try XCTUnwrap(StructuredKeyboard.edit(.indent, text: text, selection: range, size: 17))
        let indented = applying(indent, to: text)
        XCTAssertTrue(indented.string.contains("\tfirst()\n\tsecond()"))
        let outdent = try XCTUnwrap(
            StructuredKeyboard.edit(.outdent, text: indented, selection: try XCTUnwrap(indent.selection), size: 17))
        let restored = MarkdownEditing.read(applying(outdent, to: indented), previous: original)
        XCTAssertEqual(restored.markdown, original.markdown)
        XCTAssertNil(
            StructuredKeyboard.edit(.indent, text: text, selection: NSRange(location: 0, length: text.length), size: 17)
        )
        XCTAssertNil(
            StructuredKeyboard.edit(
                .outdent, text: text, selection: NSRange(location: 0, length: text.length), size: 17))
    }

    private func applying(_ edit: MarkdownEditing.Edit, to text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        result.replaceCharacters(in: edit.range, with: edit.text)
        return result
    }
}
