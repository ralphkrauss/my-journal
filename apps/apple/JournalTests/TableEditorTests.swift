import JournalCore
import SwiftUI
import XCTest

@testable import Journal

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

@MainActor final class TableEditorTests: XCTestCase {
    func testNativeTableCellsShareBodyUndoAndSurviveSourceSwitch() throws {
        let fixture = try TableFixture()
        defer { fixture.close() }
        let undo = try XCTUnwrap(fixture.view.undoManager)
        undo.groupsByEvent = false
        while undo.groupingLevel > 0 { undo.endUndoGrouping() }
        undo.beginUndoGrouping()
        fixture.coordinator.replace(
            NSAttributedString(string: "Changed", attributes: RichText.attributes(kind: "paragraph", size: 17)),
            range: NSRange(location: 0, length: 6))
        undo.endUndoGrouping()
        fixture.coordinator.tables?.focus(at: try fixture.tableRange())
        let grid = try XCTUnwrap(fixture.coordinator.tables?.active)
        let cell = try XCTUnwrap(grid.activeCell)
        #if os(macOS)
            cell.setSelectedRange(NSRange(location: 0, length: cell.string.utf16.count))
        #else
            cell.selectedRange = NSRange(location: 0, length: cell.text.utf16.count)
        #endif
        undo.beginUndoGrouping()
        #if os(macOS)
            cell.insertText("Updated", replacementRange: cell.selectedRange())
        #else
            cell.insertText("Updated")
        #endif
        undo.endUndoGrouping()
        XCTAssertEqual(
            fixture.document.blocks.first { $0.table != nil }?.table?.rows[0][0].map(\.text).joined(), "Updated")
        XCTAssertTrue(fixture.document.text.hasPrefix("Changed"))
        undo.undo()
        XCTAssertEqual(
            fixture.document.blocks.first { $0.table != nil }?.table?.rows[0][0].map(\.text).joined(), "Name")
        undo.undo()
        XCTAssertTrue(fixture.document.text.hasPrefix("Before"))
        undo.redo()
        undo.redo()
        XCTAssertEqual(
            fixture.document.blocks.first { $0.table != nil }?.table?.rows[0][0].map(\.text).joined(), "Updated")
        undo.beginUndoGrouping()
        fixture.coordinator.perform(.source)
        undo.endUndoGrouping()
        XCTAssertTrue(fixture.actions.sourceMode)
        XCTAssertTrue(fixture.document.markdown.contains("Updated"))
        undo.beginUndoGrouping()
        fixture.coordinator.perform(.source)
        undo.endUndoGrouping()
        XCTAssertFalse(fixture.actions.sourceMode)
        XCTAssertEqual(
            fixture.document.blocks.first { $0.table != nil }?.table?.rows[0][0].map(\.text).joined(), "Updated")
        let copied = try XCTUnwrap(
            RichText.tableSelectionMarkdown(fixture.text, range: NSRange(location: 0, length: fixture.text.length)))
        XCTAssertTrue(copied.contains("| Updated | Value |"), copied)
        XCTAssertTrue(copied.contains("After"))
        XCTAssertFalse(copied.contains("\u{fffc}"))
    }

    func testPastingTableMarkdownPreservesCellsAndUndo() throws {
        let fixture = try TableFixture(markdown: "Before")
        defer { fixture.close() }
        let original = fixture.document
        #if os(macOS)
            fixture.view.setSelectedRange(NSRange(location: fixture.text.length, length: 0))
        #else
            fixture.view.selectedRange = NSRange(location: fixture.text.length, length: 0)
        #endif
        let undo = try XCTUnwrap(fixture.view.undoManager)
        undo.groupsByEvent = false
        while undo.groupingLevel > 0 { undo.endUndoGrouping() }
        undo.beginUndoGrouping()
        fixture.coordinator.pasteMarkdown("\n\n| Name | Value |\n| --- | --- |\n| **First** | Second |\n\nAfter")
        undo.endUndoGrouping()
        let pasted = fixture.document
        let table = try XCTUnwrap(pasted.blocks.first { $0.table != nil }?.table)
        XCTAssertEqual(table.rows[1][0].map(\.text).joined(), "First")
        XCTAssertTrue(table.rows[1][0].contains { $0.bold })
        XCTAssertTrue(pasted.text.contains("Before"))
        XCTAssertTrue(pasted.text.contains("After"))
        undo.undo()
        XCTAssertEqual(fixture.document.markdown, original.markdown)
        undo.redo()
        XCTAssertEqual(fixture.document.markdown, pasted.markdown)
    }

    func testInsertTableStaysFormattedAndFocusesFirstHeader() throws {
        let fixture = try TableFixture(markdown: "Before.\n\nAfter.")
        defer { fixture.close() }
        #if os(macOS)
            fixture.view.setSelectedRange(NSRange(location: 0, length: 0))
        #else
            fixture.view.selectedRange = NSRange(location: 0, length: 0)
        #endif
        fixture.coordinator.perform(.insert("|  |  |\n| --- | --- |\n|  |  |\n"))
        XCTAssertFalse(fixture.actions.sourceMode)
        XCTAssertFalse(MarkdownEditing.isSource(fixture.text))
        XCTAssertNotNil(fixture.coordinator.tables?.active?.activeCell)
        XCTAssertEqual(fixture.coordinator.tables?.active?.activeCell?.address, TableCellAddress(row: 0, column: 0))
        XCTAssertEqual(fixture.document.blocks.filter { $0.table != nil }.count, 1)
        XCTAssertTrue(fixture.document.text.contains("Before."))
        XCTAssertTrue(fixture.document.text.contains("After."))
    }
}

@MainActor private final class TableFixture {
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
    init(markdown: String = "Before\n\n| Name | Value |\n| --- | --- |\n| A | B |\n\nAfter") throws {
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
