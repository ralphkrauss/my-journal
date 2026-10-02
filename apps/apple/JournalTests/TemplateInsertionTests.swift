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
final class TemplateInsertionTests: XCTestCase {
    func testNativeTemplateInsertionUsesAnswerBlockOnceAndRetainsLaterSelection() throws {
        let question = DocumentBlock(kind: "heading", runs: [TextRun("Question?")])
        let image = DocumentBlock(kind: "image", attachmentID: UUID(), mediaType: "image/png")
        for (blocks, expected) in [
            ([question, DocumentBlock()], 10),
            ([question, DocumentBlock(), question], 10),
            ([image, DocumentBlock()], 2),
        ] {
            var document = JournalDocument(blocks: blocks)
            let original = document
            let item = JournalItem(kind: "entry", document: document)
            let request = try XCTUnwrap(InitialEditorInsertion(item: item, fromTemplate: true))
            var editor = NativeEditor(
                document: Binding(get: { document }, set: { document = $0 }), itemID: item.id, images: [:],
                initialInsertion: request, fontSize: 17, editable: true, actions: EditorActions()
            ) { _ in nil }
            let coordinator = editor.makeCoordinator()
            let view = JournalTextView(frame: CGRect(x: 0, y: 0, width: 360, height: 500))
            coordinator.view = view
            view.delegate = coordinator
            coordinator.update(editor)
            XCTAssertEqual(selection(view).location, expected)
            let font = try XCTUnwrap(view.typingAttributes[.font] as? PlatformFont)
            XCTAssertEqual(font.pointSize, 17)
            XCTAssertEqual(view.typingAttributes[.journalKind] as? String, "paragraph")
            #if os(macOS)
                view.setSelectedRange(NSRange(location: 1, length: 0))
            #else
                view.selectedRange = NSRange(location: 1, length: 0)
            #endif
            editor.fontSize = 20
            coordinator.update(editor)
            XCTAssertEqual(selection(view).location, 1)
            let replacement = editor.makeCoordinator()
            let replacementView = JournalTextView(frame: view.frame)
            replacement.view = replacementView
            replacementView.delegate = replacement
            replacement.update(editor)
            XCTAssertEqual(selection(replacementView).location, 0)
            XCTAssertEqual(document, original)
        }
    }

    /// Filling an open empty entry can show the template before its answer line is known, while it's saved. Return
    /// from the title then went to the start of the first question, so the answer was typed into the heading.
    func testAnAnswerLineKnownAfterTheTemplateShowsStillPlacesTheCaret() throws {
        let question = DocumentBlock(kind: "heading", runs: [TextRun("Question?")])
        let entry = JournalItem(kind: "entry", document: JournalDocument())
        var filled = entry
        filled.document = JournalDocument(blocks: [question, DocumentBlock()])
        var document = entry.document
        var editor = NativeEditor(
            document: Binding(get: { document }, set: { document = $0 }), itemID: entry.id, images: [:],
            fontSize: 17, editable: true, actions: EditorActions()
        ) { _ in nil }
        let coordinator = editor.makeCoordinator()
        let view = JournalTextView(frame: CGRect(x: 0, y: 0, width: 360, height: 500))
        coordinator.view = view
        view.delegate = coordinator
        coordinator.update(editor)
        document = filled.document
        coordinator.update(editor)
        XCTAssertEqual(selection(view).location, 0)

        editor.initialInsertion = InitialEditorInsertion(item: filled, fromTemplate: true)
        coordinator.update(editor)
        XCTAssertEqual(selection(view).location, 10)
        XCTAssertEqual(view.typingAttributes[.journalKind] as? String, "paragraph")
        // Only once: a caret the person moves stays where they put it.
        #if os(macOS)
            view.setSelectedRange(NSRange(location: 1, length: 0))
        #else
            view.selectedRange = NSRange(location: 1, length: 0)
        #endif
        coordinator.update(editor)
        XCTAssertEqual(selection(view).location, 1)
    }

    func testChangedOrMissingAnswerTargetIsDiscardedWithoutMovingSelection() throws {
        let question = DocumentBlock(kind: "heading", runs: [TextRun("Question?")])
        let answer = DocumentBlock()
        let original = JournalItem(kind: "entry", document: .init(blocks: [question, answer]))
        for missing in [false, true] {
            let request = try XCTUnwrap(InitialEditorInsertion(item: original, fromTemplate: true))
            var document = original.document
            if missing {
                document.blocks.removeLast()
            } else {
                document.blocks[1].runs = [TextRun("Existing answer")]
            }
            let text = RichText.render(document, size: 17, images: [:])
            XCTAssertNil(request.consume(itemID: original.id, document: document, text: text))
            XCTAssertNil(
                request.consume(
                    itemID: original.id, document: original.document,
                    text: RichText.render(original.document, size: 17, images: [:])))
        }
        XCTAssertNil(InitialEditorInsertion(item: original, fromTemplate: false))
    }

    private func selection(_ view: JournalTextView) -> NSRange {
        #if os(macOS)
            view.selectedRange()
        #else
            view.selectedRange
        #endif
    }
}
