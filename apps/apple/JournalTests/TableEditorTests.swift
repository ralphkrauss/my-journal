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

    // MARK: One list of table commands (docs/design/1-1-settings-messages-editor.md §6)

    /// A menu as text: groups separated by "|", destructive items marked "!", the checked alignment "*".
    private func signature(_ groups: [[TableMenu.Entry]]) -> String {
        groups.map { group in
            group.map { entry -> String in
                switch entry {
                case .item(let item): return (item.isDestructive ? "!" : "") + item.title
                case .submenu(let title, let items):
                    return title + "[" + items.map { $0.title + ($0.isChecked ? "*" : "") }.joined(separator: ",") + "]"
                }
            }.joined(separator: ",")
        }.joined(separator: "|")
    }
    private func focusedCell(_ harness: EditorHarness, row: Int, column: Int) throws -> (
        InlineTableGrid, TableCellTextView
    ) {
        var table = NSRange()
        harness.text.enumerateAttribute(.journalTable, in: NSRange(location: 0, length: harness.text.length)) {
            value, range, stop in
            if value != nil {
                table = NSRange(location: range.location, length: 0)
                stop.pointee = true
            }
        }
        harness.coordinator.tables?.focus(at: table)
        let grid = try XCTUnwrap(harness.coordinator.tables?.active)
        grid.focus(TableCellAddress(row: row, column: column))
        return (grid, try XCTUnwrap(grid.activeCell))
    }
    /// The Table menu the cell shows, as text, from the platform's own menu type.
    private func cellMenuSignature(_ grid: InlineTableGrid, _ cell: TableCellTextView) -> String? {
        #if os(macOS)
            guard let menu = cell.tableMenu?() else { return nil }
            var groups: [[String]] = [[]]
            for item in menu.items {
                if item.isSeparatorItem {
                    groups.append([])
                } else if let submenu = item.submenu {
                    let choices = submenu.items.map { $0.title + ($0.state == .on ? "*" : "") }
                    groups[groups.count - 1].append(item.title + "[" + choices.joined(separator: ",") + "]")
                } else {
                    groups[groups.count - 1].append(item.title)
                }
            }
            return groups.map { $0.joined(separator: ",") }.joined(separator: "|")
        #else
            guard
                let menu = grid.textView(
                    cell, editMenuForTextIn: NSRange(location: 0, length: 0), suggestedActions: []),
                let table = menu.children.last as? UIMenu
            else { return nil }
            return table.children.compactMap { $0 as? UIMenu }.map { group in
                group.children.map { element -> String in
                    if let submenu = element as? UIMenu {
                        let choices = submenu.children.compactMap { $0 as? UIAction }.map {
                            $0.title + ($0.state == .on ? "*" : "")
                        }
                        return submenu.title + "[" + choices.joined(separator: ",") + "]"
                    }
                    guard let action = element as? UIAction else { return "?" }
                    return (action.attributes.contains(.destructive) ? "!" : "") + action.title
                }.joined(separator: ",")
            }.joined(separator: "|")
        #endif
    }

    func testTheCellMenuIsTheOneListWithTheColumnsAlignmentChecked() throws {
        XCTAssertEqual(
            signature(TableMenu.groups(alignment: nil)),
            "Add Row Below,Add Column After,Alignment[Left*,Center,Right]|!Delete Row,!Delete Column,!Delete Table")
        XCTAssertEqual(
            signature(TableMenu.groups(alignment: "right")),
            "Add Row Below,Add Column After,Alignment[Left,Center,Right*]|!Delete Row,!Delete Column,!Delete Table")
        let harness = EditorHarness(markdown: "| A | B |\n| --- | :-: |\n| c | d |")
        defer { harness.close() }
        let (grid, plain) = try focusedCell(harness, row: 1, column: 0)
        var expected = signature(TableMenu.groups(alignment: nil))
        #if os(macOS)
            // The Mac's destructive items are not coloured, so they are not marked.
            expected = expected.replacingOccurrences(of: "!", with: "")
        #endif
        XCTAssertEqual(cellMenuSignature(grid, plain), expected, "A column with none shows Left checked.")
        let (_, centered) = try focusedCell(harness, row: 1, column: 1)
        var centeredExpected = signature(TableMenu.groups(alignment: "center"))
        #if os(macOS)
            centeredExpected = centeredExpected.replacingOccurrences(of: "!", with: "")
        #endif
        XCTAssertEqual(cellMenuSignature(grid, centered), centeredExpected)
        // Format ▸ Table checks the same alignment: the focused cell's column.
        harness.settle()
        XCTAssertEqual(harness.actions.tableAlignment, "center")
        _ = try focusedCell(harness, row: 1, column: 0)
        harness.settle()
        XCTAssertEqual(harness.actions.tableAlignment, "left")
    }
    func testFormatTableAppliesToTheFocusedCellAndOfferedAlignmentsChange() throws {
        let harness = EditorHarness(markdown: "| A | B |\n| --- | --- |\n| c | d |")
        defer { harness.close() }
        _ = try focusedCell(harness, row: 1, column: 0)
        let action = try XCTUnwrap(harness.actions.tableAction, "The menu bar can reach the table on every device.")
        action(.align("right"))
        action(.addColumn)
        let table = try XCTUnwrap(harness.document.blocks.first { $0.table != nil }?.table)
        XCTAssertEqual(table.columnCount, 3)
        XCTAssertEqual(table.alignments[0], "right")
        harness.settle()
        XCTAssertEqual(harness.actions.tableAlignment, "right")
    }
    func testAReadOnlyEntryOffersNoTableMenu() throws {
        let harness = EditorHarness(markdown: "| A | B |\n| --- | --- |\n| c | d |")
        defer { harness.close() }
        let (grid, cell) = try focusedCell(harness, row: 1, column: 0)
        XCTAssertNotNil(cellMenuSignature(grid, cell))
        harness.update { $0.editable = false }
        XCTAssertNil(cellMenuSignature(grid, cell))
        let before = harness.document
        harness.actions.tableAction?(.deleteTable)
        XCTAssertEqual(harness.document, before, "A read-only entry's table is not changed from the menu bar.")
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
