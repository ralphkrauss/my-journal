import JournalCore
import SwiftUI
import UniformTypeIdentifiers
import XCTest

@testable import Journal

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Changes from elsewhere, input method compositions, images that take a while to import, and undo.
@MainActor final class EditorChangeTests: XCTestCase {
    func testChangeFromElsewhereReplacesTheTextAndItsUndo() throws {
        let harness = EditorHarness(markdown: "First\n\nSecond")
        defer { harness.close() }
        harness.caret(at: harness.text.length)
        harness.type(" typed")
        XCTAssertEqual(harness.undoManager?.canUndo, true)
        var remote = harness.document
        remote.blocks[0].runs = [TextRun("Changed elsewhere")]
        harness.replaceDocument(remote)
        XCTAssertEqual(harness.text.string, "Changed elsewhere\nSecond typed")
        // Undo would otherwise put back text from before the change, over it.
        XCTAssertEqual(harness.undoManager?.canUndo, false)
    }

    /// View ▸ Zoom In changes only how the entry looks; the selection stays for the next formatting command.
    func testZoomKeepsTheSelectionAndUndo() throws {
        let harness = EditorHarness(markdown: "First\n\nSecond words")
        defer { harness.close() }
        harness.caret(at: harness.text.length)
        harness.type(" typed")
        harness.select("Second")
        let selection = harness.selection
        harness.update { $0.fontSize = 22 }
        XCTAssertEqual(harness.selection, selection)
        XCTAssertEqual(harness.text.string, "First\nSecond words typed")
        XCTAssertEqual(harness.undoManager?.canUndo, true)
        harness.update { $0.fontSize = 14 }
        XCTAssertEqual(harness.selection, selection)
    }

    func testChangeFromElsewhereWaitsForTheCompositionAndKeepsBothEdits() throws {
        let harness = EditorHarness(markdown: "First\n\nSecond")
        defer { harness.close() }
        harness.caret(at: 5)
        harness.compose("か")
        var remote = harness.document
        remote.blocks[1].runs = [TextRun("Second, changed elsewhere")]
        harness.replaceDocument(remote)
        XCTAssertTrue(harness.isComposing, "The composition keeps going")
        XCTAssertEqual(harness.text.string, "Firstか\nSecond")
        harness.compose("かな")
        harness.view.unmarkText()
        harness.wait { harness.text.string.contains("elsewhere") }
        XCTAssertEqual(harness.text.string, "Firstかな\nSecond, changed elsewhere")
        XCTAssertEqual(
            harness.document.blocks.map { $0.runs.map(\.text).joined() }, ["Firstかな", "Second, changed elsewhere"])
    }

    func testRebaseKeepsEditsToDifferentBlocksAndThisEditorsVersionOfTheSameBlock() {
        let base = JournalDocument(markdown: "One\n\nTwo\n\nThree")
        var local = base
        local.blocks[0].runs = [TextRun("One, here")]
        local.blocks.insert(DocumentBlock(runs: [TextRun("New here")]), at: 1)
        var remote = base
        remote.blocks[2].runs = [TextRun("Three, elsewhere")]
        remote.blocks.remove(at: 1)
        let merged = ExternalEdits.rebase(local: local, base: base, remote: remote)
        XCTAssertEqual(
            merged.blocks.map { $0.runs.map(\.text).joined() }, ["One, here", "New here", "Three, elsewhere"])
        var conflicting = base
        conflicting.blocks[0].runs = [TextRun("One, elsewhere")]
        XCTAssertEqual(ExternalEdits.rebase(local: local, base: base, remote: conflicting), local)
    }

    func testImageThatFinishesImportingAfterMoreWritingIsStillInserted() throws {
        let attachment = UUID()
        let gate = ImportGate()
        let harness = EditorHarness(JournalDocument(blocks: [DocumentBlock(runs: [TextRun("Start")])])) { _ in
            await gate.wait()
            return DocumentBlock(kind: "image", attachmentID: attachment, imageDescription: "", mediaType: "image/png")
        }
        defer { harness.close() }
        harness.caret(at: 5)
        harness.view.receiveImages?([.original(try EditorClipboardTests.image(.png, width: 10, height: 10))])
        harness.wait { gate.waiting }
        harness.type(" and more")
        gate.open()
        harness.wait { harness.document.references(to: attachment) == 1 }
        XCTAssertEqual(harness.document.references(to: attachment), 1, harness.document.markdown)
        XCTAssertEqual(harness.document.blocks.first?.runs.map(\.text).joined(), "Start")
        XCTAssertTrue(harness.document.text.contains(" and more"), harness.document.markdown)
    }

    func testImagesFollowTheEditorWidthAfterSwitchingViews() throws {
        let id = UUID()
        let image = try EditorClipboardTests.image(.png, width: 1000, height: 500)
        let harness = EditorHarness(
            JournalDocument(blocks: [
                DocumentBlock(runs: [TextRun("Before")]),
                DocumentBlock(kind: "image", attachmentID: id, imageDescription: "", mediaType: "image/png"),
            ]), images: [id: image], width: 300)
        defer { harness.close() }
        harness.coordinator.perform(.source)
        harness.coordinator.perform(.source)
        XCTAssertFalse(harness.actions.sourceMode)
        let location = (harness.text.string as NSString).range(of: "\u{FFFC}").location
        let attachment = try XCTUnwrap(
            harness.text.attribute(.attachment, at: location, effectiveRange: nil) as? NSTextAttachment)
        #if os(macOS)
            let width = try XCTUnwrap(attachment.attachmentCell).cellSize().width
        #else
            let width = attachment.bounds.width
        #endif
        XCTAssertLessThanOrEqual(width, 300)
    }

    func testAnImageLeavesAsMuchRoomBelowItAsAbove() throws {
        let id = UUID()
        let image = try EditorClipboardTests.image(.png, width: 400, height: 200)
        let picture = DocumentBlock(kind: "image", attachmentID: id, imageDescription: "", mediaType: "image/png")
        // A heading right below a photo, as in the entry where the missing space was noticed.
        let opened = EditorHarness(
            JournalDocument(blocks: [
                DocumentBlock(runs: [TextRun("Before")]), picture,
                DocumentBlock(kind: "subheading", runs: [TextRun("After")]),
            ]), images: [id: image], width: 300)
        defer { opened.close() }
        let shown = try imageMargins(opened)
        XCTAssertGreaterThan(shown.above, 0)
        XCTAssertEqual(shown.below, shown.above, accuracy: 1, "An image needs as much room below it as above it.")
        // Inserted in the middle of a paragraph, which splits it around the picture.
        let written = EditorHarness(
            JournalDocument(blocks: [DocumentBlock(runs: [TextRun("BeforeAfter")])]), images: [id: image], width: 300)
        defer { written.close() }
        written.caret(at: (written.text.string as NSString).range(of: "After").location)
        written.coordinator.perform(.image(picture))
        let inserted = try imageMargins(written)
        XCTAssertEqual(inserted.above, shown.above, accuracy: 1)
        XCTAssertEqual(inserted.below, shown.above, accuracy: 1)
    }

    /// The room between the first image's line and the lines of text just above and below it. A text line includes
    /// its line spacing, so between paragraphs of text this is the paragraph spacing. The picture must fill its own
    /// line apart from that line spacing, or the line would hold room the reader can't see.
    private func imageMargins(_ harness: EditorHarness) throws -> (above: CGFloat, below: CGFloat) {
        #if os(macOS)
            let layout = try XCTUnwrap(harness.view.layoutManager)
            let container = try XCTUnwrap(harness.view.textContainer)
        #else
            let layout = harness.view.layoutManager
            let container = harness.view.textContainer
        #endif
        layout.ensureLayout(for: container)
        let text = harness.text.string as NSString
        func line(_ string: String) -> CGRect {
            let glyph = layout.glyphIndexForCharacter(at: text.range(of: string).location)
            return layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
        }
        let glyph = layout.glyphIndexForCharacter(at: text.range(of: "\u{FFFC}").location)
        let picture = line("\u{FFFC}")
        let drawn = layout.attachmentSize(forGlyphAt: glyph).height
        let spacing = try XCTUnwrap(
            harness.text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        )
        .lineSpacing
        XCTAssertEqual(picture.height, drawn + spacing, accuracy: 1)
        return (picture.minY - line("Before").maxY, line("After").minY - picture.maxY)
    }

    func testPicturesAreDecodedAtTheirShownSizeAndKeptWhenOthersArrive() throws {
        let large = UUID()
        let arriving = UUID()
        let harness = EditorHarness(
            JournalDocument(blocks: [
                DocumentBlock(kind: "image", attachmentID: large, imageDescription: "", mediaType: "image/png"),
                DocumentBlock(kind: "image", attachmentID: arriving, imageDescription: "", mediaType: "image/png"),
            ]), images: [large: try EditorClipboardTests.image(.png, width: 2400, height: 1200)], width: 300)
        defer { harness.close() }
        harness.update { $0.loadingImages = [arriving] }
        let pictures = (harness.text.string as NSString)
        let first = pictures.range(of: "\u{FFFC}").location
        let second = pictures.range(of: "\u{FFFC}", options: .backwards).location
        let shown = try XCTUnwrap(
            harness.text.attribute(.attachment, at: first, effectiveRange: nil) as? NSTextAttachment)
        #if os(macOS)
            let pixels = try XCTUnwrap(shown.attachmentCell as? NSTextAttachmentCell).image?.representations.first?
                .pixelsWide
        #else
            let pixels = shown.image?.cgImage?.width
        #endif
        // A 300-point editor needs at most 900 pixels even on a 3× screen, not the photo's 2,400.
        XCTAssertLessThanOrEqual(try XCTUnwrap(pixels), 1024)
        let waiting = harness.text.attribute(.attachment, at: second, effectiveRange: nil) as? NSTextAttachment
        harness.update {
            $0.images[arriving] = try? EditorClipboardTests.image(.png, width: 20, height: 20)
            $0.loadingImages = []
        }
        XCTAssertTrue(
            harness.text.attribute(.attachment, at: first, effectiveRange: nil) as? NSTextAttachment === shown)
        XCTAssertFalse(
            harness.text.attribute(.attachment, at: second, effectiveRange: nil) as? NSTextAttachment === waiting)
    }

    func testTypingInATableCellIsOneUndoStep() throws {
        let harness = EditorHarness(markdown: "Before\n\n| Name | Value |\n| --- | --- |\n| A | B |\n\nAfter")
        defer { harness.close() }
        var table = NSRange()
        harness.text.enumerateAttribute(.journalTable, in: NSRange(location: 0, length: harness.text.length)) {
            value, range, stop in
            if value != nil {
                table = NSRange(location: range.location, length: 0)
                stop.pointee = true
            }
        }
        harness.coordinator.tables?.focus(at: table)
        let cell = try XCTUnwrap(harness.coordinator.tables?.active?.activeCell)
        let undo = try XCTUnwrap(harness.undoManager)
        harness.settle()
        undo.groupsByEvent = false
        while undo.groupingLevel > 0 { undo.endUndoGrouping() }
        undo.removeAllActions()
        // Each key press is its own event, as the keyboard delivers them.
        for character in "xyz" {
            undo.beginUndoGrouping()
            #if os(macOS)
                cell.setSelectedRange(NSRange(location: cell.string.utf16.count, length: 0))
                cell.insertText(String(character), replacementRange: cell.selectedRange())
            #else
                cell.selectedRange = NSRange(location: cell.text.utf16.count, length: 0)
                cell.insertText(String(character))
            #endif
            undo.endUndoGrouping()
        }
        func header() -> String? {
            harness.document.blocks.first { $0.table != nil }?.table?.rows[0][0].map(\.text).joined()
        }
        XCTAssertEqual(header(), "Namexyz")
        undo.undo()
        XCTAssertEqual(header(), "Name")
        undo.redo()
        XCTAssertEqual(header(), "Namexyz")
    }

    func testAnImageOnAnEmptyLineAddsNoBlankParagraph() throws {
        let harness = EditorHarness(
            JournalDocument(blocks: [DocumentBlock(runs: [TextRun("Hello")]), DocumentBlock()]))
        defer { harness.close() }
        harness.caret(at: harness.text.length)
        let attachment = UUID()
        harness.coordinator.perform(
            .image(DocumentBlock(kind: "image", attachmentID: attachment, imageDescription: "", mediaType: "image/png"))
        )
        XCTAssertEqual(Array(harness.document.blocks.map(\.kind).prefix(2)), ["paragraph", "image"])
        XCTAssertEqual(harness.document.blocks.first?.runs.map(\.text).joined(), "Hello")
    }

    #if os(macOS)
        func testSubstitutionChoicesSurviveTheCaretMovingThroughCode() throws {
            let harness = EditorHarness(markdown: "Prose\n\n```\ncode\n```\n\nMore prose")
            defer { harness.close() }
            // As chosen in Edit ▸ Substitutions.
            harness.view.isAutomaticQuoteSubstitutionEnabled = false
            harness.view.isAutomaticDashSubstitutionEnabled = true
            harness.caret(at: 2)
            XCTAssertFalse(harness.view.isAutomaticQuoteSubstitutionEnabled)
            XCTAssertTrue(harness.view.isAutomaticDashSubstitutionEnabled)
            harness.caret(at: (harness.text.string as NSString).range(of: "code").location + 1)
            XCTAssertFalse(harness.view.isAutomaticDashSubstitutionEnabled)
            XCTAssertFalse(harness.view.isContinuousSpellCheckingEnabled)
            harness.caret(at: (harness.text.string as NSString).range(of: "More").location)
            XCTAssertFalse(harness.view.isAutomaticQuoteSubstitutionEnabled)
            XCTAssertTrue(harness.view.isAutomaticDashSubstitutionEnabled)
        }

        /// An item's start is a caret position like any line's (build 13 stepped over hidden marker characters there).
        func testArrowKeysMoveAcrossAnItemsStartLikeAnyLine() throws {
            let harness = EditorHarness(markdown: "Before\n\n- [ ] Task")
            defer { harness.close() }
            let task = (harness.text.string as NSString).range(of: "Task").location
            harness.caret(at: task)
            harness.view.moveLeft(nil)
            XCTAssertEqual(harness.selection, NSRange(location: 6, length: 0), "End of the line before")
            harness.view.moveRight(nil)
            XCTAssertEqual(harness.selection, NSRange(location: task, length: 0), "Start of the task's text")
        }
    #endif
}

@MainActor private final class ImportGate {
    private(set) var waiting = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        waiting = true
        await withCheckedContinuation { continuation = $0 }
    }
    func open() {
        continuation?.resume()
        continuation = nil
    }
}
