import JournalCore
import SwiftUI
import XCTest

@testable import Journal

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// One rule for Bold, Italic, Underline, Strikethrough and Inline Code: with a selection the style turns on unless
/// every character that can carry it has it, and the control shows what the command is about to do
/// (docs/design/1-1-settings-messages-editor.md §4).
@MainActor
final class InlineStyleRuleTests: XCTestCase {
    private func state(_ harness: EditorHarness, _ style: InlineStyle) -> FormattingToggle {
        harness.actions.captureFormatting()
        return harness.actions.formattingState.toggle(for: style)
    }
    private func press(_ harness: EditorHarness, _ style: InlineStyle) {
        harness.actions.captureFormatting()
        harness.actions.performFormatting(style.command)
    }
    private func hasStyle(_ run: TextRun, _ style: InlineStyle) -> Bool {
        switch style {
        case .bold: return run.bold
        case .italic: return run.italic
        case .underline: return run.underline
        case .strikethrough: return run.strikethrough
        case .code: return run.code
        }
    }
    private func everyRunHasStyle(_ block: DocumentBlock, _ style: InlineStyle) -> Bool {
        !block.runs.isEmpty && block.runs.allSatisfy { hasStyle($0, style) }
    }

    /// None, some and all of the selection styled: the style turns on unless all of it has it, and the control reads
    /// what the next press does. Strikethrough and Inline Code used to follow the first selected character.
    func testEveryStyleTurnsOnUnlessTheWholeSelectionHasIt() {
        for style in InlineStyle.allCases {
            let harness = EditorHarness(markdown: "alpha beta gamma")
            defer { harness.close() }
            harness.select("beta")
            XCTAssertEqual(state(harness, style), .off, "\(style)")
            press(harness, style)
            XCTAssertEqual(state(harness, style), .on, "\(style)")
            harness.select("alpha beta gamma")
            XCTAssertEqual(state(harness, style), .mixed, "\(style)")
            press(harness, style)
            XCTAssertEqual(state(harness, style), .on, "A Mixed control turns the style on: \(style)")
            XCTAssertTrue(everyRunHasStyle(harness.document.blocks[0], style), "\(style)")
            // The first character has it and the rest doesn't: it still turns on, not off.
            harness.select("alpha beta gamma")
            press(harness, style)
            XCTAssertEqual(state(harness, style), .off, "\(style)")
            XCTAssertFalse(harness.document.blocks[0].runs.contains { hasStyle($0, style) }, "\(style)")
            harness.select("alpha ")
            press(harness, style)
            harness.select("alpha beta")
            XCTAssertEqual(state(harness, style), .mixed, "\(style)")
            press(harness, style)
            XCTAssertEqual(state(harness, style), .on, "The first character having it doesn't turn it off: \(style)")
        }
    }

    /// A heading's weight is its style, not Bold: it doesn't count, so the control and the command agree.
    func testBoldIgnoresHeadingsAndAfterOnePressTheControlReadsOn() {
        let harness = EditorHarness(markdown: "## Heading\n\nPlain **bold** words")
        defer { harness.close() }
        let end = (harness.text.string as NSString).range(of: "bold").upperBound
        harness.select(NSRange(location: 0, length: end))
        XCTAssertEqual(state(harness, .bold), .mixed)
        press(harness, .bold)
        XCTAssertEqual(state(harness, .bold), .on)
        XCTAssertFalse(harness.document.blocks[0].runs.contains(where: \.bold), "The heading is not marked bold.")
        XCTAssertEqual(harness.document.blocks[0].kind, "subheading")
        XCTAssertEqual(
            harness.document.blocks[1].runs.filter(\.bold).map(\.text).joined(), "Plain bold",
            "Only the characters that can carry Bold change.")
        press(harness, .bold)
        XCTAssertEqual(state(harness, .bold), .off)
    }

    /// Line breaks never decide the state, and receive the new value: a struck word, a line break and a plain word
    /// is Mixed, and one press strikes all of it, the line break included.
    func testALineBreakNeverDecidesAndTakesTheNewValue() {
        let harness = EditorHarness(markdown: "~~one~~\n\ntwo")
        defer { harness.close() }
        harness.select(NSRange(location: 0, length: harness.text.length))
        XCTAssertEqual(state(harness, .strikethrough), .mixed)
        press(harness, .strikethrough)
        XCTAssertEqual(state(harness, .strikethrough), .on)
        let lineBreak = (harness.text.string as NSString).range(of: "\n")
        XCTAssertNotNil(harness.text.attribute(.strikethroughStyle, at: lineBreak.location, effectiveRange: nil))
        // Struck words with a plain line break between them are On, not Mixed, and the press turns them off.
        let struck = EditorHarness(markdown: "~~one~~\n\n~~two~~")
        defer { struck.close() }
        struck.select(NSRange(location: 0, length: struck.text.length))
        XCTAssertEqual(state(struck, .strikethrough), .on)
        press(struck, .strikethrough)
        XCTAssertEqual(state(struck, .strikethrough), .off)
    }

    /// Pictures and code blocks cannot carry a style. They neither decide the state nor change.
    func testPicturesAndCodeBlocksAreLeftAlone() {
        let image = DocumentBlock(
            kind: "image", attachmentID: UUID(), imageDescription: "A path", mediaType: "image/png")
        let withImage = EditorHarness(
            JournalDocument(blocks: [
                DocumentBlock(runs: [TextRun("a "), TextRun("b", bold: true)]), image,
                DocumentBlock(runs: [TextRun("c")]),
            ]))
        defer { withImage.close() }
        withImage.select(NSRange(location: 0, length: withImage.text.length))
        XCTAssertEqual(state(withImage, .bold), .mixed)
        press(withImage, .bold)
        XCTAssertEqual(state(withImage, .bold), .on)
        XCTAssertEqual(withImage.document.blocks.map(\.kind), ["paragraph", "image", "paragraph"])
        XCTAssertEqual(withImage.document.blocks[1].attachmentID, image.attachmentID)
        XCTAssertTrue(everyRunHasStyle(withImage.document.blocks[2], .bold))

        let withCode = EditorHarness(markdown: "Plain words\n\n```\nlet x = 1\n```")
        defer { withCode.close() }
        withCode.select(NSRange(location: 0, length: withCode.text.length))
        for style in InlineStyle.allCases {
            XCTAssertEqual(state(withCode, style), .off, "\(style)")
        }
        press(withCode, .italic)
        let code = withCode.document.blocks.first { $0.kind == "codeBlock" }
        XCTAssertNotNil(code)
        XCTAssertFalse(code?.runs.contains(where: \.italic) ?? true)
        XCTAssertTrue(everyRunHasStyle(withCode.document.blocks[0], .italic))
        // A selection that is only code has nothing to change.
        withCode.select("let x = 1")
        let before = withCode.document
        press(withCode, .bold)
        XCTAssertEqual(withCode.document, before)
    }

    /// Without a selection the style is pending for the next typed text: on unless the typing style has it.
    func testWithoutASelectionTheNextTypedTextTakesTheStyle() {
        for style in InlineStyle.allCases {
            let harness = EditorHarness(markdown: "word")
            defer { harness.close() }
            harness.caret(at: 4)
            press(harness, style)
            XCTAssertEqual(state(harness, style), .on, "\(style)")
            harness.type("s")
            XCTAssertTrue(
                harness.document.blocks[0].runs.contains { $0.text.contains("s") && hasStyle($0, style) }, "\(style)")
            press(harness, style)
            XCTAssertEqual(state(harness, style), .off, "\(style)")
        }
    }

    /// A table cell follows the same rule for all five styles.
    func testATableCellFollowsTheSameRule() throws {
        for style in InlineStyle.allCases {
            let harness = EditorHarness(
                markdown: "| Name | Value |\n| --- | --- |\n| plain strong words | B |")
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
            let grid = try XCTUnwrap(harness.coordinator.tables?.active)
            grid.focus(TableCellAddress(row: 1, column: 0))
            let cell = try XCTUnwrap(grid.activeCell, "\(style)")
            let strong = (cell.attributedTextForTesting.string as NSString).range(of: "strong")
            cell.selectForTesting(strong)
            XCTAssertTrue(grid.formatCell(style.command), "\(style)")
            cell.selectForTesting(NSRange(location: 0, length: cell.attributedTextForTesting.length))
            let mixed = try XCTUnwrap(harness.coordinator.tables?.selectedCellStyle)
            XCTAssertEqual(mixed.toggle(for: style), .mixed, "\(style)")
            XCTAssertTrue(grid.formatCell(style.command), "\(style)")
            let on = try XCTUnwrap(harness.coordinator.tables?.selectedCellStyle)
            XCTAssertEqual(on.toggle(for: style), .on, "A Mixed control turns the style on in a cell: \(style)")
            let runs = harness.document.blocks.first { $0.table != nil }?.table?.rows[1][0] ?? []
            XCTAssertTrue(runs.allSatisfy { hasStyle($0, style) }, "\(style)")
        }
    }

    #if os(iOS)
        /// The system's own routes to Bold, Italic and Underline, the edit menu and hardware keys UIKit handles,
        /// run the editor's rule rather than UIKit's own for a mixed selection.
        func testTheSystemsBoldItalicAndUnderlineActionsUseTheEditorsRule() {
            let actions: [(InlineStyle, (JournalTextView) -> Void)] = [
                (.bold, { $0.toggleBoldface(nil) }), (.italic, { $0.toggleItalics(nil) }),
                (.underline, { $0.toggleUnderline(nil) }),
            ]
            for (style, toggle) in actions {
                let harness = EditorHarness(markdown: "## Heading\n\nPlain words")
                defer { harness.close() }
                harness.select("Plain")
                toggle(harness.view)
                harness.select(NSRange(location: 0, length: harness.text.length))
                let mixedSelection = state(harness, style)
                XCTAssertTrue([.mixed, .on].contains(mixedSelection), "\(style)")
                toggle(harness.view)
                XCTAssertEqual(state(harness, style), .on, "A Mixed selection turns on: \(style)")
                toggle(harness.view)
                XCTAssertEqual(state(harness, style), .off, "\(style)")
                XCTAssertFalse(
                    harness.document.blocks.contains { $0.runs.contains { hasStyle($0, style) } }, "\(style)")
            }
        }
        func testTheEditMenuShowsTheStateTheFormattingControlShows() throws {
            let harness = EditorHarness(markdown: "Plain **bold** words")
            defer { harness.close() }
            let command = UICommand(title: "Bold", action: #selector(UIResponder.toggleBoldface(_:)))
            harness.select("Plain bold")
            harness.view.validate(command)
            XCTAssertEqual(command.state, .mixed)
            harness.select("bold")
            harness.view.validate(command)
            XCTAssertEqual(command.state, .on)
            harness.select("words")
            harness.view.validate(command)
            XCTAssertEqual(command.state, .off)
        }
    #endif
}

#if os(macOS)
    extension TableCellTextView {
        var attributedTextForTesting: NSAttributedString { attributedString() }
        func selectForTesting(_ range: NSRange) { setSelectedRange(range) }
    }
#else
    extension TableCellTextView {
        var attributedTextForTesting: NSAttributedString { attributedText }
        func selectForTesting(_ range: NSRange) { selectedRange = range }
    }
#endif
