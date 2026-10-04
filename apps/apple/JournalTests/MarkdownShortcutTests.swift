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
final class MarkdownShortcutTests: XCTestCase {
    func testLineStartMarkersMapToTheirStyles() {
        XCTAssertEqual(MarkdownShortcuts.style(forMarker: "- ")?.kind, "bullet")
        XCTAssertEqual(MarkdownShortcuts.style(forMarker: "* ")?.kind, "bullet")
        XCTAssertEqual(MarkdownShortcuts.style(forMarker: "7. ")?.number, 7)
        XCTAssertEqual(MarkdownShortcuts.style(forMarker: "3) ")?.kind, "numbered")
        XCTAssertEqual(MarkdownShortcuts.style(forMarker: "[ ] ")?.kind, "task")
        XCTAssertEqual(MarkdownShortcuts.style(forMarker: "[x] ")?.kind, "checked")
        XCTAssertEqual(MarkdownShortcuts.style(forMarker: "> ")?.kind, "quote")
        XCTAssertEqual(MarkdownShortcuts.style(forMarker: "### ")?.kind, "heading3")
        XCTAssertNil(MarkdownShortcuts.style(forMarker: "####### "))
        XCTAssertNil(MarkdownShortcuts.style(forMarker: "1.5 "))
        XCTAssertNil(MarkdownShortcuts.style(forMarker: "Note: "))
        XCTAssertEqual(MarkdownShortcuts.block(forLine: "---"), "---")
        XCTAssertEqual(MarkdownShortcuts.block(forLine: "```swift"), "```swift\n\n```")
        XCTAssertNil(MarkdownShortcuts.block(forLine: "``` not code"))
    }

    func testTypedMarkerBecomesAListAndBackspaceGivesBackTheTypedText() throws {
        let fixture = ShortcutFixture()
        defer { fixture.close() }
        fixture.type("1.")
        fixture.type(" ")
        fixture.settle()
        XCTAssertEqual(fixture.document.blocks.first?.kind, "numbered")
        fixture.type("Plan")
        fixture.settle()
        XCTAssertEqual(fixture.document.blocks.first?.runs.map(\.text).joined(), "Plan")
        XCTAssertEqual(fixture.document.blocks.first?.kind, "numbered")

        let second = ShortcutFixture()
        defer { second.close() }
        second.type("-")
        second.type(" ")
        second.settle()
        XCTAssertEqual(second.document.blocks.first?.kind, "bullet")
        second.deleteBackward()
        second.settle()
        XCTAssertEqual(second.document.blocks.first?.kind, "paragraph")
        XCTAssertEqual(second.document.text, "- ", "Backspace right after the conversion restores the typed text")
        second.type("stays literal")
        second.settle()
        XCTAssertEqual(second.document.text, "- stays literal")
    }

    func testReturnAfterACodeFenceOrRuleCreatesThatBlock() throws {
        let fence = ShortcutFixture()
        defer { fence.close() }
        fence.type("```")
        fence.pressReturn()
        fence.settle()
        XCTAssertEqual(fence.document.blocks.first?.kind, "codeBlock")
        let rule = ShortcutFixture()
        defer { rule.close() }
        rule.type("---")
        rule.pressReturn()
        rule.settle()
        XCTAssertEqual(rule.document.blocks.first?.kind, "rule")
    }
}

@MainActor
private final class ShortcutFixture {
    private final class Storage { var document = JournalDocument() }
    private let storage = Storage()
    var document: JournalDocument { storage.document }
    let view = JournalTextView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
    let coordinator: NativeEditor.Coordinator
    #if os(macOS)
        let window: NSWindow
    #else
        let window: UIWindow
    #endif

    init() {
        let storage = storage
        let editor = NativeEditor(
            document: Binding(get: { storage.document }, set: { storage.document = $0 }), itemID: UUID(), images: [:],
            fontSize: 17, editable: true, actions: EditorActions(), imageHandler: { _ in nil })
        coordinator = NativeEditor.Coordinator(editor)
        #if os(macOS)
            window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
            view.allowsUndo = true
            view.isRichText = true
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
            window.makeFirstResponder(view)
        #else
            view.becomeFirstResponder()
        #endif
    }
    func type(_ text: String) {
        for character in text {
            #if os(macOS)
                view.insertText(String(character), replacementRange: view.selectedRange())
            #else
                // The keyboard asks the delegate before each insertion; programmatic insertText doesn't.
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
            // As a Return key press arrives, through the delegate's command handling.
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
            let range = NSRange(location: max(0, view.selectedRange.location - 1), length: 1)
            if coordinator.textView(view, shouldChangeTextIn: range, replacementText: "") { view.deleteBackward() }
        #endif
    }
    /// Lets the conversion scheduled after a typed space run, as it does between key presses.
    func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    func close() {
        #if os(macOS)
            window.orderOut(nil)
        #else
            window.isHidden = true
        #endif
    }
}
