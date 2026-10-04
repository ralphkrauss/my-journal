#if os(macOS)
    import AppKit
    import JournalCore
    import SwiftUI
    import XCTest

    @testable import Journal

    /// Writing at the bottom of the Mac editor keeps room below the line being typed, so the writing isn't pressed
    /// against the window's edge (docs/design/mac-typing-room-2026-10-04.md). Build 14 scrolled only as far as the
    /// caret, 14 points from the edge, and Return in a list at the bottom didn't scroll at all.
    @MainActor
    final class TypingRoomTests: XCTestCase {
        func testTypingAtTheEndOfALongEntryKeepsRoomBelowTheLine() throws {
            for size: CGFloat in [16, 30] {
                let editor = try HostedEditor(paragraphs: 40, size: size)
                defer { editor.close() }
                editor.caretAtEnd()
                for index in 1...8 {
                    editor.pressReturn()
                    editor.type("Line \(index) of the evening")
                    try editor.assertRoom("typing at the end, line \(index), \(size) pt")
                }
            }
        }

        func testTypingInTheMiddleAtTheBottomOfTheWindowKeepsRoom() throws {
            let editor = try HostedEditor(paragraphs: 40, size: 16)
            defer { editor.close() }
            editor.caret(after: "Paragraph 20 of the day.")
            editor.scrollCaretToTheBottomEdge()
            for index in 1...6 {
                editor.pressReturn()
                editor.type("Added \(index)")
                try editor.assertRoom("typing in the middle, line \(index)")
            }
        }

        /// The editor's own edits for a key reveal the caret with the room too: Return in a checklist and after a
        /// heading, a rule made by Return, Down out of a code block, a Markdown shortcut, a long paste, and undo.
        func testTheEditorsOwnEditsKeepRoom() throws {
            let editor = try HostedEditor(paragraphs: 40, size: 16)
            defer { editor.close() }
            editor.caretAtEnd()
            editor.pressReturn()
            editor.type("[] Milk")
            try editor.assertRoom("the checklist shortcut")
            for item in ["Eggs", "Bread", "Butter", "Flour", "Sugar"] {
                editor.pressReturn()
                try editor.assertRoom("Return in a checklist")
                editor.type(item)
            }
            editor.pressReturn()
            editor.pressReturn()
            editor.type("# Heading")
            editor.pressReturn()
            try editor.assertRoom("Return after a heading")
            editor.type("---")
            editor.pressReturn()
            try editor.assertRoom("a rule made by Return")
            editor.type("```")
            editor.pressReturn()
            editor.type("let room = 2")
            editor.pressDown()
            try editor.assertRoom("Down out of a code block")
            editor.paste((1...30).map { "Pasted line \($0)" }.joined(separator: "\n\n"))
            try editor.assertRoom("a long paste")
            editor.scrollToTop()
            editor.undo()
            try editor.assertRoom("undo")
        }

        /// The find bar (Edit ▸ Find ▸ Find…) shows above the entry instead of over its first line, and the text moves
        /// back up when the bar closes. With the insets the editor sets itself, AppKit left the bar over the first
        /// line, which no scrolling could reveal, so a match there was hidden.
        func testTheFindBarDoesntCoverTheFirstLine() throws {
            let editor = try HostedEditor(paragraphs: 40, size: 16)
            defer { editor.close() }
            editor.scrollToTop()
            editor.showFindBar(true)
            let bar = try XCTUnwrap(editor.scroll.findBarView)
            XCTAssertTrue(editor.scroll.isFindBarVisible)
            let barFrame = bar.convert(bar.bounds, to: nil)
            let firstLine = editor.lineRect(at: 0)
            XCTAssertLessThanOrEqual(firstLine.maxY, barFrame.minY + 0.5, "The first line is below the find bar.")
            editor.caretAtEnd()
            try editor.assertRoom("typing at the end with the find bar shown")
            editor.scrollToTop()
            editor.showFindBar(false)
            XCTAssertFalse(editor.scroll.isFindBarVisible)
            let frame = editor.scroll.convert(editor.scroll.bounds, to: nil)
            XCTAssertEqual(
                frame.maxY - editor.lineRect(at: 0).maxY, 8, accuracy: 0.5,
                "Without the bar, the first line is back at the top.")
        }

        /// Undoing something that isn't the entry's text, such as Pin Entry or Move Journal, which share the window's
        /// undo manager, leaves the entry scrolled where it is. The editor revealed the caret after every undo.
        func testUndoingSomethingElseLeavesTheEntryWhereItIs() throws {
            let editor = try HostedEditor(paragraphs: 40, size: 16)
            defer { editor.close() }
            editor.caretAtEnd()
            editor.scrollToTop()
            let undo = try XCTUnwrap(editor.view.undoManager)
            let step = UndoTarget()
            undo.registerUndo(withTarget: step) { $0.undone = true }
            undo.setActionName("Pin Entry")
            editor.undo()
            XCTAssertTrue(step.undone)
            XCTAssertEqual(
                editor.scroll.contentView.bounds.minY, 0, accuracy: 0.5, "The entry didn't scroll to the caret.")
        }

        /// Less room, here in a shorter window, leaves no empty space below the end of an entry scrolled to its end.
        func testLessRoomLeavesNoEmptySpaceAtTheEnd() throws {
            let editor = try HostedEditor(paragraphs: 40, size: 16)
            defer { editor.close() }
            editor.caretAtEnd()
            editor.scrollToEnd()
            let room = editor.scroll.contentInsets.bottom
            editor.resize(height: 140)
            XCTAssertLessThan(editor.scroll.contentInsets.bottom, room, "A short editor has less room.")
            let clip = editor.scroll.contentView
            XCTAssertLessThanOrEqual(
                clip.bounds.maxY, editor.view.frame.height + editor.scroll.contentInsets.bottom + 0.5,
                "No more than the room is left below the end.")
        }
    }

    /// The target of an undo step that isn't the editor's, as a pin's or a journal move's.
    private final class UndoTarget {
        var undone = false
    }

    /// The body editor as the app shows it: NativeEditor's own scroll view in a window.
    @MainActor private final class HostedEditor {
        private final class State: ObservableObject {
            @Published var document: JournalDocument
            init(_ document: JournalDocument) { self.document = document }
        }
        private struct Host: View {
            @ObservedObject var state: State
            let actions: EditorActions
            let id: UUID
            let size: CGFloat
            var body: some View {
                NativeEditor(
                    document: $state.document, itemID: id, images: [:], fontSize: size, editable: true,
                    actions: actions, imageHandler: { _ in nil })
            }
        }
        private let state: State
        let window: NSWindow
        let view: JournalTextView
        let scroll: NSScrollView
        let size: CGFloat

        init(paragraphs: Int, size: CGFloat) throws {
            self.size = size
            state = State(
                JournalDocument(
                    blocks: (1...paragraphs).map { DocumentBlock(runs: [TextRun("Paragraph \($0) of the day.")]) }))
            let host = NSHostingView(rootView: Host(state: state, actions: EditorActions(), id: UUID(), size: size))
            window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 600, height: 420), styleMask: [.titled], backing: .buffered,
                defer: false)
            window.contentView = host
            window.orderFront(nil)
            host.layoutSubtreeIfNeeded()
            view = try XCTUnwrap(Self.find(in: host))
            scroll = try XCTUnwrap(view.enclosingScrollView)
            XCTAssertTrue(window.makeFirstResponder(view))
            settle(0.2)
        }

        /// The caret's line ends at least the room above the editor's bottom edge, and the room is about two lines.
        func assertRoom(_ name: String) throws {
            settle(0.05)
            let room = scroll.contentInsets.bottom
            XCTAssertGreaterThanOrEqual(room, 2 * size, "The room is about two lines, \(name)")
            let caret = window.convertFromScreen(
                view.firstRect(forCharacterRange: view.selectedRange(), actualRange: nil))
            let frame = scroll.convert(scroll.bounds, to: nil)
            XCTAssertGreaterThanOrEqual(caret.minY - frame.minY, room - 0.5, "Room below the line, \(name)")
            XCTAssertLessThanOrEqual(caret.maxY, frame.maxY + 0.5, "The line is in view, \(name)")
        }

        func caretAtEnd() {
            view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
            view.scrollRangeToVisible(view.selectedRange())
            settle(0.1)
        }
        func caret(after text: String) {
            view.setSelectedRange(NSRange(location: NSMaxRange((view.string as NSString).range(of: text)), length: 0))
        }
        /// Scrolls so that the caret's line is at the bottom edge, as after clicking the last line in view.
        func scrollCaretToTheBottomEdge() {
            let caret = view.convert(
                window.convertFromScreen(view.firstRect(forCharacterRange: view.selectedRange(), actualRange: nil)),
                from: nil)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: caret.maxY - scroll.contentView.bounds.height))
            scroll.reflectScrolledClipView(scroll.contentView)
            settle(0.05)
        }
        /// Shows or closes the find bar, as Edit ▸ Find ▸ Find… and the bar's Done button do.
        func showFindBar(_ shown: Bool) {
            let item = NSMenuItem(
                title: "Find", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "")
            item.tag = (shown ? NSTextFinder.Action.showFindInterface : .hideFindInterface).rawValue
            view.performFindPanelAction(item)
            settle(0.3)
        }
        /// The line of the character at `location`, in window coordinates.
        func lineRect(at location: Int) -> CGRect {
            window.convertFromScreen(
                view.firstRect(forCharacterRange: NSRange(location: location, length: 1), actualRange: nil))
        }
        func scrollToTop() {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: -scroll.contentInsets.top))
            scroll.reflectScrolledClipView(scroll.contentView)
            settle(0.05)
        }
        func scrollToEnd() {
            let clip = scroll.contentView
            clip.scroll(
                to: clip.constrainBoundsRect(
                    CGRect(x: 0, y: .greatestFiniteMagnitude / 4, width: clip.bounds.width, height: clip.bounds.height)
                ).origin)
            scroll.reflectScrolledClipView(clip)
            settle(0.05)
        }
        func resize(height: CGFloat) {
            window.setContentSize(CGSize(width: 600, height: height))
            window.contentView?.layoutSubtreeIfNeeded()
            settle(0.1)
        }
        func type(_ text: String) {
            for character in text { view.insertText(String(character), replacementRange: view.selectedRange()) }
            settle(0.05)
        }
        func pressReturn() {
            view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            settle(0.05)
        }
        func pressDown() {
            view.doCommand(by: #selector(NSResponder.moveDown(_:)))
            settle(0.05)
        }
        func paste(_ markdown: String) {
            view.receiveMarkdown?(markdown)
            settle(0.05)
        }
        func undo() {
            view.undoManager?.undo()
            settle(0.05)
        }
        func settle(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func close() { window.orderOut(nil) }

        private static func find(in view: NSView) -> JournalTextView? {
            if let editor = view as? JournalTextView { return editor }
            return view.subviews.lazy.compactMap { find(in: $0) }.first
        }
    }
#endif
