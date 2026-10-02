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
final class EditorIsolationTests: XCTestCase {
    func testSwitchingEntriesClearsUndoAndRejectsPreviousFormattingSession() throws {
        var first = JournalDocument(blocks: [DocumentBlock(runs: [TextRun("First entry")])])
        var second = JournalDocument(blocks: [DocumentBlock(runs: [TextRun("Second entry")])])
        let originalFirst = first
        let originalSecond = second
        let actions = EditorActions()
        let editor = NativeEditor(
            document: Binding(get: { first }, set: { first = $0 }), itemID: UUID(), images: [:],
            fontSize: 17, editable: true, actions: actions
        ) { _ in nil }
        let coordinator = editor.makeCoordinator()
        let view = JournalTextView(frame: CGRect(x: 0, y: 0, width: 360, height: 500))
        #if os(macOS)
            let window = NSWindow(
                contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
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
            let attributes = try XCTUnwrap(view.textStorage).attributes(at: 0, effectiveRange: nil)
        #else
            XCTAssertTrue(view.becomeFirstResponder())
            let attributes = view.textStorage.attributes(at: 0, effectiveRange: nil)
        #endif
        let undo = try XCTUnwrap(view.undoManager)
        undo.beginUndoGrouping()
        coordinator.replace(
            NSAttributedString(string: "Updated", attributes: attributes),
            range: NSRange(location: 0, length: 5))
        #if os(macOS)
            view.breakUndoCoalescing()
        #endif
        undo.endUndoGrouping()
        #if os(macOS)
            let unrelated = UndoManager()
            let boundBeforeNotification = first
            let nativeText = NSAttributedString(attributedString: view.attributedString())
            view.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 7), with: "Foreign")
            NotificationCenter.default.post(name: Notification.Name.NSUndoManagerDidUndoChange, object: unrelated)
            XCTAssertEqual(first, boundBeforeNotification)
            view.textStorage?.setAttributedString(nativeText)
        #endif
        let editedFirst = first
        XCTAssertNotEqual(editedFirst, originalFirst)
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        #if os(macOS)
            XCTAssertEqual(view.string, "First entry", "Native undo content")
        #endif
        XCTAssertEqual(first, originalFirst)
        XCTAssertTrue(undo.canRedo)
        undo.redo()
        XCTAssertEqual(first, editedFirst)
        let staleFormatting = try XCTUnwrap(coordinator.formattingSession())
        let next = NativeEditor(
            document: Binding(get: { second }, set: { second = $0 }), itemID: UUID(), images: [:],
            fontSize: 17, editable: true, actions: actions
        ) { _ in nil }
        coordinator.update(next)
        XCTAssertFalse(undo.canUndo)
        XCTAssertFalse(undo.canRedo)
        staleFormatting(.paragraph("heading"))
        XCTAssertEqual(second, originalSecond)
        XCTAssertEqual(first, editedFirst)
        #if os(macOS)
            let nextAttributes = try XCTUnwrap(view.textStorage).attributes(at: 0, effectiveRange: nil)
        #else
            let nextAttributes = view.textStorage.attributes(at: 0, effectiveRange: nil)
        #endif
        undo.beginUndoGrouping()
        coordinator.replace(
            NSAttributedString(string: "New", attributes: nextAttributes),
            range: NSRange(location: 0, length: 6))
        #if os(macOS)
            view.breakUndoCoalescing()
        #endif
        undo.endUndoGrouping()
        XCTAssertNotEqual(second, originalSecond)
        undo.undo()
        XCTAssertEqual(second, originalSecond)
        XCTAssertEqual(first, editedFirst)
        coordinator.update(editor)
        staleFormatting(.paragraph("heading"))
        XCTAssertEqual(first, editedFirst, "Returning to the same entry must not revive an earlier session.")
        let current = try XCTUnwrap(coordinator.formattingSession())
        current(.paragraph("heading"))
        current(.paragraph("paragraph"))
        XCTAssertEqual(first.blocks.map(\.kind), editedFirst.blocks.map(\.kind))
    }
}
