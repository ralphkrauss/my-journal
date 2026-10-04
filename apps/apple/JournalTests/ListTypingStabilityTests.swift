import JournalCore
import SwiftUI
import XCTest

@testable import Journal

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// A new list item doesn't move when its first character is typed: its bullet, number or checkbox and the caret stay
/// on the line where the text then appears. Build 14 placed them on an empty item's line break, which TextKit lays
/// out below the line's baseline, so they jumped up about 7 points with the first letter on iPhone.
@MainActor
final class ListTypingStabilityTests: XCTestCase {
    func testANewItemStaysPutWhenItsFirstCharacterIsTyped() throws {
        let harness = EditorHarness(JournalDocument(), width: 402)
        defer { harness.close() }
        #if os(macOS)
            let sizes: [CGFloat] = [16, 30]
        #else
            let sizes: [CGFloat] = [17, 53]
        #endif
        for size in sizes {
            for prefix in ["- [ ] ", "- ", "1. ", "> "] {
                for item in ["Eggs", "Bread"] {
                    show("Groceries\n\n\(prefix)Milk\n\(prefix)Eggs\n\(prefix)Bread", size: size, in: harness)
                    harness.caret(at: NSMaxRange((harness.text.string as NSString).range(of: item)))
                    harness.pressReturn()
                    try assertFirstCharacterStaysPut(
                        harness, "\(prefix)item after \(item == "Bread" ? "the last" : "a middle") one, \(size) pt")
                }
            }
            // An empty line between paragraphs, and an emptied item after a code block, which leaves room above it.
            show("Milk\n\nEggs\n\nBread", size: size, in: harness)
            harness.caret(at: NSMaxRange((harness.text.string as NSString).range(of: "Eggs")))
            harness.pressReturn()
            try assertFirstCharacterStaysPut(harness, "plain line, \(size) pt")
            show("```\ncode\n```\n\n- [ ] Milk\n- [ ] Eggs", size: size, in: harness)
            harness.caret(at: NSMaxRange((harness.text.string as NSString).range(of: "Milk")))
            for _ in 0..<4 { harness.deleteBackward() }
            try assertFirstCharacterStaysPut(harness, "item after code, \(size) pt")
        }
    }

    /// Types a first character on the caret's empty line: the line, the caret and the line's marker or checkbox stay
    /// where they are, on the baseline the character is then drawn on.
    private func assertFirstCharacterStaysPut(_ harness: EditorHarness, _ name: String) throws {
        harness.coordinator.synchronizeTables()
        let empty = try line(harness)
        XCTAssertTrue(empty.empty, "The caret is on an empty line, \(name)")
        harness.type("A")
        harness.coordinator.synchronizeTables()
        let typed = try line(harness)
        XCTAssertEqual(typed.top, empty.top, accuracy: 0.5, "Line top, \(name)")
        XCTAssertEqual(typed.caret, empty.caret, accuracy: 0.5, "Caret, \(name)")
        XCTAssertEqual(empty.marker == nil, typed.marker == nil, "Marker shown, \(name)")
        if let marker = typed.marker {
            XCTAssertEqual(marker, typed.baseline, accuracy: 0.5, "On the text's baseline, \(name)")
            XCTAssertEqual(try XCTUnwrap(empty.marker), marker, accuracy: 0.5, "Marker, \(name)")
        }
        XCTAssertEqual(empty.box == nil, typed.box == nil, "Checkbox shown, \(name)")
        if let box = typed.box {
            XCTAssertEqual(try XCTUnwrap(empty.box), box, accuracy: 0.5, "Checkbox, \(name)")
        }
    }

    private struct Line {
        /// The top of the caret's line.
        var top: CGFloat
        /// The baseline of the line's first character.
        var baseline: CGFloat
        /// The top of the caret.
        var caret: CGFloat
        /// The baseline the bullet or number is drawn on.
        var marker: CGFloat?
        /// The top of the checkbox.
        var box: CGFloat?
        /// Whether the caret is at the start of an empty line.
        var empty: Bool
    }

    /// The caret's line as it is shown.
    private func line(_ harness: EditorHarness) throws -> Line {
        let view = harness.view
        #if os(macOS)
            let layout = try XCTUnwrap(view.layoutManager)
            let storage = try XCTUnwrap(view.textStorage)
            let origin = view.textContainerOrigin
        #else
            let layout = view.layoutManager
            let storage = view.textStorage
            let origin = CGPoint(x: view.textContainerInset.left, y: view.textContainerInset.top)
        #endif
        let paragraph = (storage.string as NSString).paragraphRange(
            for: NSRange(location: harness.selection.location, length: 0))
        let glyph = layout.glyphIndexForCharacter(at: paragraph.location)
        let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        #if os(macOS)
            let box = view.subviews.compactMap { $0 as? NSButton }.first { $0.tag == paragraph.location }?.frame
            var caretRect = view.firstRect(forCharacterRange: harness.selection, actualRange: nil)
            caretRect = view.convert(try XCTUnwrap(view.window).convertFromScreen(caretRect), from: nil)
            // The text view is flipped; the first rect's top is its smaller y.
            let caret = caretRect.minY
        #else
            let box = view.subviews.compactMap { $0 as? ChecklistBox }.first { $0.tag == paragraph.location }
                .map { $0.box.convert($0.box.bounds, to: view) }
            let caret = view.caretRect(for: try XCTUnwrap(view.selectedTextRange).end).minY
        #endif
        return Line(
            top: origin.y + fragment.minY,
            baseline: origin.y + fragment.minY + layout.location(forGlyphAt: glyph).y,
            caret: caret,
            marker: ListMarkers.marker(atParagraph: paragraph.location, layout: layout).map { origin.y + $0.baseline },
            box: box?.minY,
            empty: paragraph.location == harness.selection.location
                && [0x0A, 0x2028].contains((storage.string as NSString).character(at: paragraph.location)))
    }

    private func show(_ markdown: String, size: CGFloat, in harness: EditorHarness) {
        harness.update { $0.fontSize = size }
        harness.replaceDocument(JournalDocument(markdown: markdown))
        harness.settle(0.1)
        harness.coordinator.synchronizeTables()
    }
}
