import JournalCore
import SwiftUI
import XCTest

@testable import Journal

@MainActor
final class SourceFormattingTests: XCTestCase {
    func testEmptySourceFormattingKeepsMarkdownAndInsertionPoint() throws {
        var document = JournalDocument.plain("")
        let actions = EditorActions()
        let editor = NativeEditor(
            document: Binding(get: { document }, set: { document = $0 }), itemID: UUID(), images: [:],
            fontSize: 17, editable: true, actions: actions
        ) { _ in nil }
        let coordinator = editor.makeCoordinator()
        let view = JournalTextView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        #if os(macOS)
            let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
            view.isRichText = true
            view.allowsUndo = true
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
        coordinator.perform(.source)
        XCTAssertTrue(actions.sourceMode)
        let session = try XCTUnwrap(coordinator.formattingSession())
        session(.paragraph("heading"))
        XCTAssertEqual(document.markdown, "# ")
        session(.paragraph("paragraph"))
        XCTAssertEqual(document.markdown, "")
        XCTAssertTrue(actions.sourceMode)
        session(.bold)
        XCTAssertEqual(document.markdown, "****")
        XCTAssertTrue(actions.sourceMode)
        session(.insert("word"))
        XCTAssertEqual(document.markdown, "**word**")
        session(.source)
        XCTAssertFalse(actions.sourceMode)
        XCTAssertEqual(document.text, "word")
        XCTAssertTrue(document.blocks[0].runs[0].bold)
    }

    /// Applies a source-mode command at the `‸` caret or between `«` `»` selection markers and returns the result
    /// with the new caret or selection marked the same way.
    private func apply(_ command: EditorCommand, to marked: String) throws -> String {
        let start = try XCTUnwrap(marked.firstIndex { $0 == "‸" || $0 == "«" })
        let isCaret = marked[start] == "‸"
        var text = marked
        let location = text.utf16.distance(from: text.startIndex, to: start)
        text.remove(at: start)
        var length = 0
        if !isCaret {
            let end = try XCTUnwrap(text.firstIndex(of: "»"))
            length = text.utf16.distance(from: text.startIndex, to: end) - location
            text.remove(at: end)
        }
        let change = try XCTUnwrap(
            SourceFormatting.change(command, in: text, selection: NSRange(location: location, length: length)))
        let result = NSMutableString(string: text)
        result.replaceCharacters(in: change.range, with: change.replacement)
        if change.selection.length == 0 {
            result.insert("‸", at: change.selection.location)
        } else {
            result.insert("»", at: NSMaxRange(change.selection))
            result.insert("«", at: change.selection.location)
        }
        return result as String
    }

    func testSourceInlineStylesWrapToggleAndKeepNeighbors() throws {
        let body = "Before.\n\n«Target» words\n\nAfter."
        XCTAssertEqual(try apply(.bold, to: body), "Before.\n\n**«Target»** words\n\nAfter.")
        XCTAssertEqual(try apply(.italic, to: body), "Before.\n\n*«Target»* words\n\nAfter.")
        XCTAssertEqual(try apply(.strikethrough, to: body), "Before.\n\n~~«Target»~~ words\n\nAfter.")
        XCTAssertEqual(try apply(.code, to: body), "Before.\n\n`«Target»` words\n\nAfter.")
        XCTAssertEqual(try apply(.underline, to: body), "Before.\n\n<u>«Target»</u> words\n\nAfter.")
        // Applying again, with or without the syntax selected, or with the caret inside, removes it.
        XCTAssertEqual(try apply(.bold, to: "A **«Target»** b"), "A «Target» b")
        XCTAssertEqual(try apply(.bold, to: "A «**Target**» b"), "A «Target» b")
        XCTAssertEqual(try apply(.bold, to: "A **Tar‸get** b"), "A Tar‸get b")
        XCTAssertEqual(try apply(.italic, to: "A *«Target»* b"), "A «Target» b")
        // Italic inside bold adds emphasis instead of removing half of the bold delimiter.
        XCTAssertEqual(try apply(.italic, to: "A **«Target»** b"), "A ***«Target»*** b")
        // Surrounding spaces stay outside, and each line is wrapped on its own.
        XCTAssertEqual(try apply(.bold, to: "A« word »b"), "A **«word»** b")
        XCTAssertEqual(
            try apply(.italic, to: "«- one\n\n# Two»"), "«- *one*\n\n# *Two*»")
        // With nothing selected, an empty pair is inserted around the caret; pressing again removes it.
        XCTAssertEqual(try apply(.bold, to: "A ‸ b"), "A **‸** b")
        XCTAssertEqual(try apply(.bold, to: "A **‸** b"), "A ‸ b")
    }

    func testSourceParagraphStylesChangeOnlyTouchedLines() throws {
        let body = "Before.\n\nTarget ‸words\n\nAfter."
        let prefixes = [
            "heading": "# ", "subheading": "## ", "heading3": "### ", "heading4": "#### ", "heading5": "##### ",
            "heading6": "###### ", "bullet": "- ", "numbered": "1. ", "task": "- [ ] ", "quote": "> ",
        ]
        for (kind, prefix) in prefixes {
            XCTAssertEqual(try apply(.paragraph(kind), to: body), "Before.\n\n\(prefix)Target ‸words\n\nAfter.", kind)
            // Changing style replaces the existing marker rather than stacking markers.
            XCTAssertEqual(
                try apply(.paragraph(kind), to: "Before.\n\n- [ ] Target ‸words\n\nAfter."),
                "Before.\n\n\(prefix)Target ‸words\n\nAfter.", kind)
        }
        XCTAssertEqual(try apply(.paragraph("paragraph"), to: "## Tar‸get"), "Tar‸get")
        XCTAssertEqual(try apply(.paragraph("numbered"), to: "«a\nb\nc»"), "«1. a\n2. b\n3. c»")
        // A paragraph after a quote or list item would continue it, so it is separated.
        XCTAssertEqual(try apply(.paragraph("paragraph"), to: "> a\n> b‸"), "> a\n\nb‸")
        // On an empty line between paragraphs the style starts its own block; neighbors don't merge.
        XCTAssertEqual(try apply(.paragraph("bullet"), to: "Before\n‸\nAfter"), "Before\n\n- ‸\n\nAfter")
        XCTAssertEqual(try apply(.paragraph("heading"), to: "Before\n\n‸\n\nAfter"), "Before\n\n# ‸\n\nAfter")
        XCTAssertEqual(try apply(.toggleTask, to: "- [ ] a‸\n- [x] b"), "- [x] a‸\n- [x] b")
        XCTAssertEqual(try apply(.toggleTask, to: "«- [x] a\n- [x] b»"), "«- [ ] a\n- [ ] b»")
    }

    func testSourceBlockInsertionsNeverReplaceOrSplitText() throws {
        XCTAssertEqual(
            try apply(.insert("```\n\n```\n"), to: "Before.\n\nTarget ‸words\n\nAfter."),
            "Before.\n\nTarget words\n\n```\n‸\n```\n\nAfter.")
        XCTAssertEqual(
            try apply(.insert("```\n\n```\n"), to: "Before.\n\n«Target words»\n\nAfter."),
            "Before.\n\n```\n‸Target words\n```\n\nAfter.")
        XCTAssertEqual(
            try apply(.insert("---\n"), to: "Before.\n\nTarget ‸words\n\nAfter."),
            "Before.\n\nTarget words\n\n---\n\n‸After.")
        XCTAssertEqual(
            try apply(.insert("|  |  |\n| --- | --- |\n|  |  |\n"), to: "Target ‸words"),
            "Target words\n\n| ‸ |  |\n| --- | --- |\n|  |  |\n")
        XCTAssertEqual(
            try apply(.link("https://example.com"), to: "A «Target» b"), "A [Target](https://example.com)‸ b")
        XCTAssertEqual(
            try apply(.link("https://example.com"), to: "A ‸ b"), "A [https://example.com](https://example.com)‸ b")
        XCTAssertEqual(try apply(.insert("word"), to: "A «x» b"), "A word‸ b")
        XCTAssertNil(SourceFormatting.change(.insert(""), in: "A b", selection: NSRange(location: 1, length: 1)))
    }
}
