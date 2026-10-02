import JournalCore
import SwiftUI
import XCTest

@testable import Journal

@MainActor final class FormattingRuntimeTests: XCTestCase {
    /// A heading is drawn bold by its style; Bold is shown on only for text formatted bold.
    func testBoldIsNotShownOnForHeadings() {
        let harness = EditorHarness(markdown: "## A heading\n\nPlain and **strong** words")
        defer { harness.close() }
        func bold() -> FormattingToggle {
            harness.actions.captureFormatting()
            return harness.actions.formattingState.bold
        }
        harness.select("A heading")
        XCTAssertEqual(bold(), .off)
        harness.caret(at: 3)
        XCTAssertEqual(bold(), .off)
        harness.select("strong")
        XCTAssertEqual(bold(), .on)
        harness.select("Plain and strong")
        XCTAssertEqual(bold(), .mixed)
    }
    func testEveryParagraphStylePreservesAdjacentContentInBothModes() throws {
        for source in [false, true] {
            for kind in [
                "heading", "subheading", "heading3", "heading4", "heading5", "heading6", "paragraph", "bullet",
                "numbered", "task", "quote",
            ] {
                let fixture = try FormattingFixture()
                defer { fixture.close() }
                if source { fixture.coordinator.perform(.source) }
                try fixture.select("Target words")
                fixture.actions.captureFormatting()
                fixture.actions.performFormatting(.paragraph(kind))
                XCTAssertEqual(fixture.actions.sourceMode, source, kind)
                let target = try XCTUnwrap(
                    fixture.document.blocks.first { $0.runs.map(\.text).joined() == "Target words" }, kind)
                XCTAssertEqual(target.kind, kind, "\(source): \(kind)")
                try assertNeighbors(fixture.document)
                let saved = fixture.document.markdown
                fixture.coordinator.perform(.source)
                XCTAssertEqual(fixture.actions.sourceMode, !source, kind)
                XCTAssertEqual(fixture.document.markdown, saved, kind)
                fixture.coordinator.perform(.source)
                XCTAssertEqual(fixture.document.markdown, saved, kind)
            }
        }
    }
    func testEveryInlineStyleAndLinkPreserveSurroundingRunsInBothModes() throws {
        let cases: [(EditorCommand, (TextRun) -> Bool)] = [
            (.bold, { $0.bold }), (.italic, { $0.italic }), (.underline, { $0.underline }),
            (.strikethrough, { $0.strikethrough }), (.code, { $0.code }),
            (.link("https://example.com"), { $0.link == "https://example.com" }),
        ]
        for source in [false, true] {
            for (command, matches) in cases {
                let fixture = try FormattingFixture()
                defer { fixture.close() }
                if source { fixture.coordinator.perform(.source) }
                try fixture.select("Target")
                fixture.actions.captureFormatting()
                fixture.actions.performFormatting(command)
                let target = try XCTUnwrap(
                    fixture.document.blocks.first { $0.runs.map(\.text).joined() == "Target words" })
                XCTAssertTrue(target.runs.contains { $0.text == "Target" && matches($0) })
                XCTAssertTrue(target.runs.contains { $0.text == " words" && !matches($0) })
                try assertNeighbors(fixture.document)
                let saved = fixture.document.markdown
                fixture.coordinator.perform(.source)
                XCTAssertEqual(fixture.actions.sourceMode, !source)
                XCTAssertEqual(fixture.document.markdown, saved)
            }
        }
    }
    func testBlockInsertionsStaySeparateFromExistingParagraphsInBothModes() throws {
        for source in [false, true] {
            for (snippet, kind) in [
                ("```\n\n```\n", "codeBlock"), ("---\n", "rule"), ("|  |  |\n| --- | --- |\n|  |  |\n", "table"),
            ] {
                let fixture = try FormattingFixture()
                defer { fixture.close() }
                if source { fixture.coordinator.perform(.source) }
                try fixture.select("Target words")
                #if os(macOS)
                    fixture.view.setSelectedRange(
                        NSRange(location: NSMaxRange(fixture.view.selectedRange()), length: 0))
                #else
                    fixture.view.selectedRange = NSRange(location: NSMaxRange(fixture.view.selectedRange), length: 0)
                #endif
                fixture.actions.captureFormatting()
                fixture.actions.performFormatting(.insert(snippet))
                XCTAssertEqual(fixture.actions.sourceMode, source)
                XCTAssertEqual(
                    fixture.document.blocks.filter { $0.kind == kind }.count, 1,
                    "\(source): \(kind): \(fixture.document.markdown)")
                XCTAssertTrue(fixture.document.blocks.contains { $0.runs.map(\.text).joined() == "Target words" })
                try assertNeighbors(fixture.document)
                let saved = fixture.document.markdown
                fixture.coordinator.perform(.source)
                XCTAssertEqual(fixture.actions.sourceMode, !source)
                XCTAssertEqual(fixture.document.markdown, saved)
            }
        }
    }
    func testSelectionTracksContentAcrossRepeatedModeChanges() throws {
        let fixture = try FormattingFixture(
            markdown: "# Heading\n\nBefore **repeated** then **repeated** and 👩🏽‍💻 text.\n\nAfter")
        defer { fixture.close() }
        let preview = fixture.text.string as NSString
        let range = preview.range(of: "repeated", options: .backwards)
        #if os(macOS)
            fixture.view.setSelectedRange(range)
        #else
            fixture.view.selectedRange = range
        #endif
        for _ in 0..<3 {
            fixture.actions.captureFormatting()
            fixture.actions.performFormatting(.source)
            #if os(macOS)
                let sourceRange = fixture.view.selectedRange()
            #else
                let sourceRange = fixture.view.selectedRange
            #endif
            XCTAssertEqual(sourceRange, (fixture.text.string as NSString).range(of: "repeated", options: .backwards))
            fixture.actions.captureFormatting()
            fixture.actions.performFormatting(.source)
            #if os(macOS)
                XCTAssertEqual(fixture.view.selectedRange(), range)
            #else
                XCTAssertEqual(fixture.view.selectedRange, range)
            #endif
        }
        try fixture.select("👩🏽‍💻")
        fixture.coordinator.perform(.source)
        #if os(macOS)
            let emojiRange = fixture.view.selectedRange()
        #else
            let emojiRange = fixture.view.selectedRange
        #endif
        XCTAssertEqual((fixture.text.string as NSString).substring(with: emojiRange), "👩🏽‍💻")
    }
    func testPreviewSelectionsAcrossBlocksIndentAndCodeExitChangeOnlyTheirTargets() throws {
        let crossing = try FormattingFixture(markdown: "Before\n\n- one\n- two\n\nAfter\n\nEnd")
        defer { crossing.close() }
        try crossing.select("two\nAfter")
        crossing.actions.captureFormatting()
        crossing.actions.performFormatting(.paragraph("heading3"))
        XCTAssertEqual(
            crossing.document.blocks.map(\.kind), ["paragraph", "bullet", "heading3", "heading3", "paragraph"],
            crossing.document.markdown)
        XCTAssertEqual(
            crossing.document.blocks.map { $0.runs.map(\.text).joined() }, ["Before", "one", "two", "After", "End"])
        try crossing.select("After\nEnd")
        crossing.actions.captureFormatting()
        crossing.actions.performFormatting(.bold)
        XCTAssertEqual(
            crossing.document.blocks.map(\.kind), ["paragraph", "bullet", "heading3", "heading3", "paragraph"])
        XCTAssertFalse(crossing.document.blocks.prefix(3).contains { $0.runs.contains(where: \.bold) })
        // The heading keeps its heading weight; the paragraph after it becomes bold without changing size.
        XCTAssertTrue(crossing.document.blocks[4].runs.allSatisfy(\.bold), crossing.document.markdown)
        let saved = crossing.document.markdown
        crossing.coordinator.perform(.source)
        crossing.coordinator.perform(.source)
        XCTAssertEqual(crossing.document.markdown, saved)

        let list = try FormattingFixture(markdown: "Before\n\n- one\n- two\n\nAfter")
        defer { list.close() }
        try list.select("two")
        list.actions.captureFormatting()
        list.actions.performFormatting(.indent)
        XCTAssertTrue(list.document.markdown.contains("- one\n  - two"), list.document.markdown)
        list.actions.performFormatting(.outdent)
        XCTAssertEqual(list.document.markdown, "Before\n\n- one\n- two\n\nAfter")

        let code = try FormattingFixture(markdown: "Before\n\n```\nlet x = 1\n```\n\nAfter")
        defer { code.close() }
        try code.select("1")
        #if os(macOS)
            code.view.setSelectedRange(NSRange(location: NSMaxRange(code.view.selectedRange()), length: 0))
        #else
            code.view.selectedRange = NSRange(location: NSMaxRange(code.view.selectedRange), length: 0)
        #endif
        code.actions.captureFormatting()
        XCTAssertEqual(code.actions.formattingState.paragraph, "codeBlock")
        code.actions.performFormatting(.insert(""))
        XCTAssertEqual(
            code.document.markdown.trimmingCharacters(in: .newlines), "Before\n\n```\nlet x = 1\n```\n\nAfter")
        #if os(macOS)
            let caret = code.view.selectedRange().location
        #else
            let caret = code.view.selectedRange.location
        #endif
        XCTAssertGreaterThan(caret, (code.text.string as NSString).range(of: "1").location)
    }
    func testInsertedBlocksLeaveTheCaretWhereTypingContinuesCleanly() throws {
        for (snippet, expected) in [
            ("---\n", "Before\n\nOutro text here.\n\n---\n\nNext"),
            ("```\n\n```\n", "Before\n\nOutro text here.\n\n```\nNext\n```"),
        ] {
            let fixture = try FormattingFixture(markdown: "Before\n\nOutro text here.")
            defer { fixture.close() }
            try fixture.select("here.")
            #if os(macOS)
                fixture.view.setSelectedRange(NSRange(location: NSMaxRange(fixture.view.selectedRange()), length: 0))
            #else
                fixture.view.selectedRange = NSRange(location: NSMaxRange(fixture.view.selectedRange), length: 0)
            #endif
            fixture.actions.captureFormatting()
            fixture.actions.performFormatting(.insert(snippet))
            #if os(macOS)
                fixture.view.insertText("Next", replacementRange: fixture.view.selectedRange())
            #else
                fixture.view.insertText("Next")
            #endif
            XCTAssertEqual(
                fixture.document.markdown.trimmingCharacters(in: .newlines), expected.trimmingCharacters(in: .newlines))
        }
    }
    func testTypingNextToATableStaysUndoable() throws {
        let fixture = try FormattingFixture(markdown: "Line one\n\n| A | B |\n| --- | --- |\n| c | d |")
        defer { fixture.close() }
        fixture.coordinator.synchronizeTables()
        try fixture.select("one")
        #if os(macOS)
            fixture.view.setSelectedRange(NSRange(location: NSMaxRange(fixture.view.selectedRange()), length: 0))
            fixture.view.insertText(" more", replacementRange: fixture.view.selectedRange())
        #else
            fixture.view.selectedRange = NSRange(location: NSMaxRange(fixture.view.selectedRange), length: 0)
            fixture.view.insertText(" more")
        #endif
        fixture.coordinator.synchronizeTables()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(fixture.document.markdown.hasPrefix("Line one more"))
        let undo = try XCTUnwrap(fixture.view.undoManager)
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        XCTAssertTrue(fixture.document.markdown.hasPrefix("Line one\n"), fixture.document.markdown)
    }
    private func assertNeighbors(_ document: JournalDocument) throws {
        let before = try XCTUnwrap(document.blocks.first)
        let after = try XCTUnwrap(document.blocks.last)
        XCTAssertEqual(before.runs.map(\.text).joined(), "Before unchanged.")
        XCTAssertEqual(after.runs.map(\.text).joined(), "After unchanged.")
        XCTAssertEqual(before.kind, "paragraph")
        XCTAssertEqual(after.kind, "paragraph")
        XCTAssertTrue(before.runs.contains { $0.text == "unchanged" && $0.bold })
        XCTAssertTrue(after.runs.contains { $0.text == "unchanged" && $0.italic })
    }
}

@MainActor private final class FormattingFixture {
    private let state: DocumentState
    var document: JournalDocument { state.value }
    let actions = EditorActions()
    let view = JournalTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 600))
    let coordinator: NativeEditor.Coordinator
    #if os(macOS)
        let window: NSWindow
    #else
        let window: UIWindow
    #endif
    var text: NSAttributedString {
        #if os(macOS)
            view.attributedString()
        #else
            view.attributedText
        #endif
    }
    init(markdown: String = "Before **unchanged**.\n\nTarget words\n\nAfter *unchanged*.") throws {
        let state = DocumentState(JournalDocument(markdown: markdown))
        self.state = state
        let editor = NativeEditor(
            document: Binding(get: { state.value }, set: { state.value = $0 }), itemID: UUID(), images: [:],
            fontSize: 17, editable: true, actions: actions
        ) { _ in nil }
        coordinator = editor.makeCoordinator()
        #if os(macOS)
            window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
            view.isRichText = true
            view.allowsUndo = true
        #else
            window = UIWindow(frame: view.frame)
            let controller = UIViewController()
            controller.view = view
            window.rootViewController = controller
            window.makeKeyAndVisible()
        #endif
        coordinator.view = view
        view.delegate = coordinator
        coordinator.update(editor)
        #if os(macOS)
            XCTAssertTrue(window.makeFirstResponder(view))
        #else
            XCTAssertTrue(view.becomeFirstResponder())
        #endif
        coordinator.synchronizeTables()
    }
    func select(_ string: String) throws {
        let range = (text.string as NSString).range(of: string)
        XCTAssertNotEqual(range.location, NSNotFound)
        #if os(macOS)
            view.setSelectedRange(range)
        #else
            view.selectedRange = range
        #endif
    }
    func tableRange() throws -> NSRange {
        var result: NSRange?
        text.enumerateAttribute(.journalTable, in: NSRange(location: 0, length: text.length)) { value, range, stop in
            if value != nil {
                result = NSRange(location: range.location, length: 0)
                stop.pointee = true
            }
        }
        return try XCTUnwrap(result)
    }
    func close() {
        #if os(macOS)
            window.orderOut(nil)
        #else
            window.isHidden = true
        #endif
    }
}

@MainActor private final class DocumentState {
    var value: JournalDocument
    init(_ value: JournalDocument) { self.value = value }
}
