import JournalCore
import SwiftUI
import XCTest

@testable import Journal

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

@MainActor
final class MarkdownEditorTests: XCTestCase {
    func testSwitchingMarkdownViewsRetainsNativeUndoAcrossEdits() throws {
        var document = JournalDocument.plain("Original")
        let actions = EditorActions()
        let editor = NativeEditor(
            document: Binding(get: { document }, set: { document = $0 }), itemID: UUID(), images: [:], fontSize: 17,
            editable: true, actions: actions
        ) { _ in nil }
        let coordinator = editor.makeCoordinator()
        let view = JournalTextView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        #if os(macOS)
            let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
            view.allowsUndo = true
            view.isRichText = true
            defer { window.orderOut(nil) }
        #else
            let window = UIWindow(frame: view.frame)
            let controller = UIViewController()
            controller.view = view
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
        #endif
        coordinator.view = view
        view.delegate = coordinator
        coordinator.update(editor)
        #if os(macOS)
            XCTAssertTrue(window.makeFirstResponder(view))
        #else
            XCTAssertTrue(view.becomeFirstResponder())
        #endif
        let undo = try XCTUnwrap(view.undoManager)
        undo.groupsByEvent = false
        while undo.groupingLevel > 0 { undo.endUndoGrouping() }
        undo.beginUndoGrouping()
        coordinator.replace(
            NSAttributedString(string: "Changed", attributes: RichText.attributes(kind: "paragraph", size: 17)),
            range: NSRange(location: 0, length: 8))
        undo.endUndoGrouping()
        undo.beginUndoGrouping()
        coordinator.perform(.source)
        undo.endUndoGrouping()
        XCTAssertTrue(actions.sourceMode)
        XCTAssertTrue(document.markdown.contains("Changed"))
        undo.beginUndoGrouping()
        coordinator.replace(MarkdownEditing.render("**Changed**", size: 17), range: NSRange(location: 0, length: 7))
        undo.endUndoGrouping()
        undo.beginUndoGrouping()
        coordinator.perform(.source)
        undo.endUndoGrouping()
        XCTAssertFalse(actions.sourceMode)
        XCTAssertTrue(document.blocks[0].runs.contains { $0.bold })
        undo.undo()
        XCTAssertTrue(actions.sourceMode)
        undo.undo()
        XCTAssertFalse(document.blocks[0].runs.contains { $0.bold })
        undo.undo()
        XCTAssertFalse(actions.sourceMode)
        undo.undo()
        XCTAssertEqual(document.text, "Original")
        undo.redo()
        XCTAssertEqual(document.text, "Changed")
    }
    func testCodeBlockRemainsFormattedAndKeepsMultilineContentsOnRichEdit() throws {
        let source = "Before.\n\n```swift\nlet value = 1\nprint(value)\n```\n\nAfter."
        let original = JournalDocument(markdown: source)
        let text = RichText.render(original, size: 17, images: [:])
        XCTAssertFalse(MarkdownEditing.isSource(text))
        let read = MarkdownEditing.read(text, previous: original)
        XCTAssertEqual(read.markdown, source)
        let code = try XCTUnwrap(read.blocks.first { $0.kind == "codeBlock" })
        XCTAssertEqual(code.codeLanguage, "swift")
        XCTAssertEqual(code.runs.map(\.text).joined(), "let value = 1\nprint(value)\n")
        let inserted = try XCTUnwrap(
            MarkdownEditing.edit(
                .insert("```\n\n```\n"), text: text,
                selection: NSRange(location: 1, length: 0), document: original, size: 17, images: [:]))
        XCTAssertFalse(MarkdownEditing.isSource(inserted.text))
        let updated = MarkdownEditing.read(inserted.text, previous: original)
        XCTAssertEqual(updated.blocks.filter { $0.kind == "codeBlock" }.count, 2)
        XCTAssertTrue(updated.text.contains("After."))
        XCTAssertTrue(updated.text.contains("print(value)"))
    }
    func testNestedListAndLineBreakRichRoundTripPreservesOriginalMarkdown() {
        let source =
            "7. First\n   - Nested **item**\n\n> A quote\n> with a soft break.  \n> And a hard break.\n\n[Link](https://example.com \"Title\")."
        let original = JournalDocument(markdown: source)
        XCTAssertFalse(original.requiresMarkdownSource)
        let text = RichText.render(original, size: 17, images: [:])
        XCTAssertFalse(MarkdownEditing.isSource(text))
        let read = MarkdownEditing.read(text, previous: original)
        XCTAssertEqual(read.markdown, source)
        XCTAssertEqual(read.blocks[1].listIndents, [3])
    }
    func testStructuralKeysPreserveNestedContentAndCodeBoundary() throws {
        let original = JournalDocument(
            markdown: "- Parent\n  - Child\n\n```swift\n  let value = 1\nprint(value)\n```\n\nAfter")
        let text = RichText.render(original, size: 17, images: [:])
        let child = (text.string as NSString).range(of: "Child")
        let outdent = try XCTUnwrap(StructuredKeyboard.edit(.outdent, text: text, selection: child, size: 17))
        let edited = NSMutableAttributedString(attributedString: text)
        edited.replaceCharacters(in: outdent.range, with: outdent.text)
        let result = MarkdownEditing.read(edited, previous: original)
        XCTAssertTrue(result.markdown.contains("- Child"))
        XCTAssertFalse(result.markdown.contains("  - Child"))
        XCTAssertTrue(result.markdown.contains("print(value)"))
        let code = (text.string as NSString).range(of: "let value")
        XCTAssertNil(
            StructuredKeyboard.edit(.down, text: text, selection: NSRange(location: code.location, length: 0), size: 17)
        )
        let indent = try XCTUnwrap(
            StructuredKeyboard.edit(
                .indent, text: text, selection: NSRange(location: code.location, length: 0), size: 17))
        let literal = NSMutableAttributedString(attributedString: text)
        literal.replaceCharacters(in: indent.range, with: indent.text)
        let updated = MarkdownEditing.read(literal, previous: original)
        XCTAssertTrue(updated.markdown.contains("  \tlet value = 1"))
        XCTAssertTrue(updated.markdown.contains("After"))
    }

    func testInlineImagesAndTaskControlsPreserveMarkdownAndAttachments() throws {
        let id = UUID()
        let source =
            "Before ![Diagram](attachments/" + id.uuidString.lowercased()
            + " \"Title\") after.\n\n- [ ] Check this\n\n![Remote](https://example.com/image.png)"
        let original = JournalDocument(markdown: source)
        let text = RichText.render(original, size: 17, images: [:])
        XCTAssertFalse(MarkdownEditing.isSource(text))
        let read = MarkdownEditing.read(text, previous: original)
        XCTAssertEqual(read.markdown, source)
        XCTAssertEqual(read.attachmentIDs, [id])
        let item = (text.string as NSString).range(of: "Check this")
        XCTAssertNotEqual(item.location, NSNotFound)
        let checked = try XCTUnwrap(
            StructuredKeyboard.edit(
                .toggleTask, text: text, selection: NSRange(location: item.location, length: 0), size: 17))
        let updated = NSMutableAttributedString(attributedString: text)
        updated.replaceCharacters(in: checked.range, with: checked.text)
        let document = MarkdownEditing.read(updated, previous: original)
        XCTAssertEqual(document.attachmentIDs, [id])
        XCTAssertTrue(document.markdown.contains("- [x] Check this"))
        XCTAssertTrue(document.markdown.contains("https://example.com/image.png"))
    }

    func testSourceDeletionAndComplexFormattingDoNotFlattenContent() throws {
        let source = "| A | B |\n| --- | --- |\n| X | Y |\n"
        let original = JournalDocument(markdown: source)
        let text = RichText.render(original, size: 17, images: [:])
        XCTAssertFalse(MarkdownEditing.isSource(text))
        XCTAssertNotNil(
            MarkdownEditing.edit(
                .source, text: text, selection: NSRange(location: 0, length: 0), document: original, size: 17,
                images: [:]))
        let deleted = MarkdownEditing.read(NSAttributedString(string: ""), previous: original, source: true)
        XCTAssertEqual(deleted.markdown, "")
        XCTAssertEqual(original.markdown, source)
    }

    func testSwitchingViewsKeepsTheCaretOnTheSameCharacterInEveryKindOfBlock() throws {
        let markdown = """
            # Plan

            Notes about the plan, and the plan again.

            ### Heading 3

            - First plan item
            - Second item

            1. One plan
            2. Two

            > Quoted plan

            | Name | Plan |
            | --- | --- |
            | A | plan |

            ```
            let plan = 1
            ```

            Last plan line with **bold** and `code`.

            """
        let document = JournalDocument(markdown: markdown)
        let preview = RichText.render(document, size: 17, images: [:])
        let text = preview.string as NSString
        var checked = 0
        for location in 0..<text.length {
            let character = text.substring(with: NSRange(location: location, length: 1))
            guard character.rangeOfCharacter(from: .alphanumerics) != nil else { continue }
            let source = try XCTUnwrap(
                MarkdownEditing.edit(
                    .source, text: preview, selection: NSRange(location: location, length: 0), document: document,
                    size: 17, images: [:]))
            let caret = try XCTUnwrap(source.selection)
            let sourceText = source.text.string as NSString
            XCTAssertEqual(
                sourceText.substring(with: NSRange(location: caret.location, length: 1)), character,
                "Preview offset \(location) landed on the wrong character in source")
            let back = try XCTUnwrap(
                MarkdownEditing.edit(
                    .source, text: source.text, selection: caret, document: document, size: 17, images: [:],
                    source: true))
            XCTAssertEqual(back.selection?.location, location, "Round trip moved the caret from \(location)")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 100)
    }
}
