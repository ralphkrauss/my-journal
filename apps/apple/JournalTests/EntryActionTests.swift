import JournalCore
import SwiftUI
import XCTest

@testable import Journal

@MainActor
final class EntryActionTests: XCTestCase {
    #if os(macOS)
        func testFormattingSessionPreservesRangeAndCannotRetargetAnotherEntry() throws {
            var document = JournalDocument(blocks: [DocumentBlock(runs: [TextRun("First second")])])
            let actions = EditorActions()
            let editor = NativeEditor(
                document: Binding(get: { document }, set: { document = $0 }), itemID: UUID(), images: [:],
                fontSize: 17, editable: true, actions: actions, imageHandler: { _ in nil })
            let coordinator = NativeEditor.Coordinator(editor)
            let view = JournalTextView()
            coordinator.view = view
            view.delegate = coordinator
            coordinator.update(editor)
            view.setSelectedRange(NSRange(location: 6, length: 6))
            actions.captureFormatting()
            view.setSelectedRange(NSRange(location: 0, length: 0))
            actions.performFormatting(.bold)
            actions.performFormatting(.italic)
            let runs = document.blocks.flatMap(\.runs)
            XCTAssertEqual(runs.first?.text, "First ")
            XCTAssertEqual(runs.first?.bold, false)
            XCTAssertEqual(runs.last?.text, "second")
            XCTAssertEqual(runs.last?.bold, true)
            XCTAssertEqual(runs.last?.italic, true)
            var replacement = editor
            replacement.itemID = UUID()
            coordinator.update(replacement)
            let before = document
            actions.performFormatting(.underline)
            XCTAssertEqual(document, before)
        }
    #endif
    func testContextTargetFlushesPreviousDraftAndDatePatchPreservesContent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root, key: key)
        let journal = JournalItem(kind: "journal", title: "Personal")
        let first = JournalItem(kind: "entry", journalID: journal.id, title: "First")
        var second = JournalItem(kind: "entry", journalID: journal.id, title: "Second")
        second.date = Date(timeIntervalSince1970: 1_700_000_000)
        for item in [journal, first, second] { try await store.save(item) }
        let model = AppModel(directory: root)
        model.store = store
        model.loaded = true
        model.items = [journal, first, second]
        model.selectedJournalID = journal.id
        model.selectedID = first.id
        model.draft = first
        var edited = first
        edited.title = "Unsaved first entry"
        model.updateDraft(edited)
        let selected = await model.selectEntryForAction(second.id)
        XCTAssertTrue(selected)
        XCTAssertEqual(model.draft?.id, second.id)
        let savedFirst = try await store.item(first.id)
        XCTAssertEqual(savedFirst?.title, edited.title)
        let date = second.date.addingTimeInterval(-86_400)
        try await model.changeEntryDate(second.id, expectedDate: second.date, to: date)
        XCTAssertEqual(model.draft?.date, date)
        XCTAssertEqual(model.draft?.title, second.title)
        // The native render is inspection evidence, not a pixel-baseline test.
        #if os(macOS)
            if let preview = await NativeTestPreview.capture(
                RootView().environmentObject(model).environmentObject(EditorActions()),
                name: "Three-column navigation", width: 1100, height: 720)
            {
                add(preview)
            }
            let actions = EditorActions()
            if let preview = await NativeTestPreview.capture(
                FormattingPopover(editor: actions, session: actions.formatting, close: {}), name: "Visual formatting",
                width: 280, height: 440)
            {
                add(preview)
            }
        #endif
        try await store.close()
        edited = try XCTUnwrap(model.draft)
        edited.title = "Text retained after storage failure"
        model.updateDraft(edited)
        let refused = await model.selectEntryForAction(first.id)
        XCTAssertFalse(refused)
        XCTAssertEqual(model.draft?.id, edited.id)
        XCTAssertEqual(model.draft?.title, edited.title)
        model.locked = true
        let locked = await model.selectEntryForAction(second.id)
        XCTAssertFalse(locked)
    }
}
