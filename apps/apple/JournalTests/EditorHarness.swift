import JournalCore
import SwiftUI
import XCTest

@testable import Journal

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// A native entry editor in a window, driven the way the keyboard and menus drive it.
@MainActor final class EditorHarness {
    final class State {
        var document: JournalDocument
        init(_ document: JournalDocument) { self.document = document }
    }
    let state: State
    var document: JournalDocument { state.document }
    let actions = EditorActions()
    let view: JournalTextView
    let coordinator: NativeEditor.Coordinator
    private(set) var editor: NativeEditor
    #if os(macOS)
        let window: NSWindow
    #else
        let window: UIWindow
    #endif

    init(
        _ document: JournalDocument, images: [UUID: Data] = [:], width: CGFloat = 480,
        imageHandler: @escaping (Data) async -> DocumentBlock? = { _ in nil }
    ) {
        let state = State(document)
        self.state = state
        view = JournalTextView(frame: CGRect(x: 0, y: 0, width: width, height: 600))
        editor = NativeEditor(
            document: Binding(get: { state.document }, set: { state.document = $0 }), itemID: UUID(), images: images,
            fontSize: 17, editable: true, actions: actions, imageHandler: imageHandler)
        coordinator = editor.makeCoordinator()
        #if os(macOS)
            window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
            view.isRichText = true
            view.importsGraphics = false
            view.allowsUndo = true
        #else
            window = UIWindow(frame: view.frame)
            let controller = UIViewController()
            controller.view = view
            window.rootViewController = controller
            window.makeKeyAndVisible()
            view.allowsEditingTextAttributes = true
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

    convenience init(markdown: String) {
        self.init(JournalDocument(markdown: markdown))
    }

    var text: NSAttributedString {
        #if os(macOS)
            view.attributedString()
        #else
            view.attributedText
        #endif
    }
    var selection: NSRange {
        #if os(macOS)
            view.selectedRange()
        #else
            view.selectedRange
        #endif
    }
    var undoManager: UndoManager? { view.undoManager }

    /// Applies a change from outside the editor, such as a synced edit or a new entry.
    func update(_ change: (inout NativeEditor) -> Void) {
        change(&editor)
        coordinator.update(editor)
    }
    func replaceDocument(_ document: JournalDocument) {
        state.document = document
        coordinator.update(editor)
    }

    func select(_ range: NSRange) {
        #if os(macOS)
            view.setSelectedRange(range)
        #else
            view.selectedRange = range
        #endif
    }
    func select(_ string: String) {
        let range = (text.string as NSString).range(of: string)
        XCTAssertNotEqual(range.location, NSNotFound, string)
        select(range)
    }
    func caret(at location: Int) { select(NSRange(location: location, length: 0)) }

    /// Types each character as the keyboard does, including the delegate's chance to handle it.
    func type(_ string: String) {
        for character in string {
            #if os(macOS)
                view.insertText(String(character), replacementRange: view.selectedRange())
            #else
                if coordinator.textView(
                    view, shouldChangeTextIn: view.selectedRange, replacementText: String(character))
                {
                    view.insertText(String(character))
                }
            #endif
        }
    }
    func pressReturn() {
        #if os(macOS)
            view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #else
            if coordinator.textView(view, shouldChangeTextIn: view.selectedRange, replacementText: "\n") {
                view.insertText("\n")
            }
        #endif
    }
    func deleteBackward() {
        #if os(macOS)
            // As the Delete key arrives, so the editor sees it even at the start of the text.
            view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        #else
            // At the start of the text the keyboard's Backspace changes no text; the text view hears it alone.
            if view.selectedRange == NSRange(location: 0, length: 0) {
                view.deleteBackward()
                return
            }
            let range =
                view.selectedRange.length > 0
                ? view.selectedRange : NSRange(location: max(0, view.selectedRange.location - 1), length: 1)
            if coordinator.textView(view, shouldChangeTextIn: range, replacementText: "") { view.deleteBackward() }
        #endif
    }
    /// Pastes formatted text from another app, the way the text view reads it from the pasteboard.
    func pasteRichText(_ text: NSAttributedString) {
        let rtf = try? text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        XCTAssertNotNil(rtf)
        paste(PasteSample(name: "rich text", rtf: rtf, plain: text.string))
    }
    #if os(iOS)
        /// Inserts text as UIKit does for a paste or drop from another app, with that app's attributes.
        func insertForeign(_ text: NSAttributedString) {
            let range = view.selectedRange
            guard coordinator.textView(view, shouldChangeTextIn: range, replacementText: text.string) else { return }
            view.textStorage.replaceCharacters(in: range, with: text)
            view.selectedRange = NSRange(location: range.location + text.length, length: 0)
            coordinator.textViewDidChange(view)
        }
    #endif
    #if os(macOS)
        func insertForeign(_ text: NSAttributedString) {
            view.insertText(text, replacementRange: view.selectedRange())
        }
    #endif
    /// Starts or continues an input method's composition at the selection.
    func compose(_ text: String) {
        #if os(macOS)
            view.setMarkedText(
                text, selectedRange: NSRange(location: text.utf16.count, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0))
        #else
            view.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0))
        #endif
    }
    var isComposing: Bool {
        #if os(macOS)
            view.hasMarkedText()
        #else
            view.markedTextRange != nil
        #endif
    }
    /// Waits, without blocking the main run loop, until `condition` holds or a second has passed.
    func wait(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(1)
        while !condition(), Date() < deadline { settle(0.01) }
    }
    /// Lets work scheduled for the next turn of the main run loop happen, as it does between key presses.
    func settle(_ seconds: TimeInterval = 0.05) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    func close() {
        #if os(macOS)
            window.orderOut(nil)
        #else
            window.isHidden = true
        #endif
    }
}

extension JournalDocument {
    /// How many times the Markdown refers to `attachment`.
    func references(to attachment: UUID) -> Int {
        markdown.components(separatedBy: "attachments/" + attachment.uuidString.lowercased()).count - 1
    }
}
