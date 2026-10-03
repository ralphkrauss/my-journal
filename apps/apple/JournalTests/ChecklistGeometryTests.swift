import JournalCore
import SwiftUI
import XCTest

@testable import Journal

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Lists line up: bulleted, numbered and checklist text share one column that grows with the text, wrapped lines
/// start where their text does, a nested item's marker sits under its parent's text, and a checkbox sits with its
/// first line, clear of the text (docs/design/checklists-2026-10-03.md). Build 12 put iPhone checklist text 22 pt
/// further in than other lists and nested items 5 to 18 pt short of their parent's text, at every text size.
@MainActor
final class ChecklistGeometryTests: XCTestCase {
    private static let long = "that is long enough to wrap onto a second line in the editor, even on a wide screen"

    func testListsShareOneColumnAtTheDefaultAndLargestTextSize() throws {
        let harness = EditorHarness(JournalDocument(), width: 402)
        defer { harness.close() }
        #if os(macOS)
            let sizes: [CGFloat] = [16, 30]
        #else
            let sizes: [CGFloat] = [17, 53]
        #endif
        for size in sizes {
            show(
                """
                - Bullet \(Self.long)

                1. Numbered \(Self.long)

                - [ ] Unchecked \(Self.long)
                - [x] Checked \(Self.long)
                """, size: size, in: harness)
            let items = try paragraphs(harness)
            XCTAssertEqual(items.map(\.kind), ["bullet", "numbered", "task", "checked"])
            for item in items {
                XCTAssertEqual(item.textX, items[0].textX, accuracy: 0.5, "\(item.kind) text at \(size) pt")
                XCTAssertGreaterThan(item.lines.count, 1, "\(item.kind) wraps at \(size) pt")
                for line in item.lines.dropFirst() {
                    XCTAssertEqual(line, item.textX, accuracy: 0.5, "\(item.kind) wrapped line at \(size) pt")
                }
            }
            XCTAssertEqual(
                items[0].textX - items[0].markerX, RichText.listColumn(size: size), accuracy: 0.5,
                "The column grows with the text.")
            try checkBoxes(harness, items: items, size: size)
        }
    }

    func testNestedItemsStartAtTheirParentsTextAndDeepNestingKeepsRoom() throws {
        let harness = EditorHarness(JournalDocument(), width: 402)
        defer { harness.close() }
        #if os(macOS)
            let sizes: [CGFloat] = [16, 30]
        #else
            let sizes: [CGFloat] = [17, 53]
        #endif
        for size in sizes {
            show(
                """
                - Parent bullet
                  - Nested bullet \(Self.long)

                1. Parent number
                   1. Nested number

                - [ ] Parent item
                  - [x] Nested item \(Self.long)
                      - [ ] Written six spaces in
                """, size: size, in: harness)
            let items = try paragraphs(harness)
            XCTAssertEqual(items.count, 7)
            for (parent, child) in [(0, 1), (2, 3), (4, 5), (5, 6)] {
                XCTAssertEqual(
                    items[child].markerX, items[parent].textX, accuracy: 0.5,
                    "\(items[child].text) starts at its parent's text at \(size) pt")
            }
            for line in items[5].lines.dropFirst() { XCTAssertEqual(line, items[5].textX, accuracy: 0.5) }
            try checkBoxes(harness, items: items.filter { ["task", "checked"].contains($0.kind) }, size: size)

            show(
                """
                - [ ] One
                  - [ ] Two
                    - [ ] Three
                      - [ ] Four levels deep
                """, size: size, in: harness)
            let deep = try paragraphs(harness)
            XCTAssertEqual(deep.count, 4)
            XCTAssertLessThanOrEqual(deep[3].textX - deep[0].textX, 160.5, "Nesting stops at 160 pt.")
            XCTAssertLessThanOrEqual(
                deep[3].textX + 2 * size, harness.view.bounds.width, "The deepest item's text keeps room on its line.")
        }
    }

    // MARK: - Measuring

    private struct Paragraph {
        let location: Int
        let kind: String
        let text: String
        /// The marker's or box's position: the start of the item's column.
        let markerX: CGFloat
        /// The first character of the item's text.
        let textX: CGFloat
        /// Where each line of the item starts; the first is its text.
        let lines: [CGFloat]
    }

    private func show(_ markdown: String, size: CGFloat, in harness: EditorHarness) {
        harness.update { $0.fontSize = size }
        harness.replaceDocument(JournalDocument(markdown: markdown))
        #if os(macOS)
            harness.window.setContentSize(CGSize(width: 402, height: 900))
            harness.view.frame = CGRect(x: 0, y: 0, width: 402, height: 900)
        #else
            harness.window.frame = CGRect(x: 0, y: 0, width: 402, height: 2400)
            harness.view.frame = harness.window.bounds
        #endif
        harness.settle(0.2)
        harness.coordinator.synchronizeTables()
    }

    private func paragraphs(_ harness: EditorHarness) throws -> [Paragraph] {
        let (storage, layout, _, origin) = try parts(harness)
        let source = storage.string as NSString
        var result: [Paragraph] = []
        var position = 0
        while position < storage.length {
            let range = source.paragraphRange(for: NSRange(location: position, length: 0))
            position = NSMaxRange(range)
            guard let kind = storage.attribute(.journalKind, at: range.location, effectiveRange: nil) as? String,
                ["bullet", "numbered", "task", "checked"].contains(kind)
            else { continue }
            var text = range.location
            while text < NSMaxRange(range) - 1,
                storage.attribute(.journalMarker, at: text, effectiveRange: nil) != nil
            {
                text += 1
            }
            var lines: [CGFloat] = []
            layout.enumerateLineFragments(
                forGlyphRange: layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            ) { rect, _, _, glyphs, _ in
                let first = max(glyphs.location, layout.glyphIndexForCharacter(at: text))
                lines.append(origin.x + rect.minX + layout.location(forGlyphAt: first).x)
            }
            let marker = layout.glyphIndexForCharacter(at: range.location)
            let markerX =
                origin.x + layout.lineFragmentRect(forGlyphAt: marker, effectiveRange: nil).minX
                + layout.location(forGlyphAt: marker).x
            result.append(
                Paragraph(
                    location: range.location, kind: kind,
                    text: source.substring(with: NSRange(location: text, length: NSMaxRange(range) - text)),
                    markerX: markerX, textX: lines.first ?? markerX, lines: lines))
        }
        return result
    }

    private func parts(_ harness: EditorHarness) throws -> (NSTextStorage, NSLayoutManager, NSTextContainer, CGPoint) {
        #if os(macOS)
            let view = harness.view
            return (
                try XCTUnwrap(view.textStorage), try XCTUnwrap(view.layoutManager), try XCTUnwrap(view.textContainer),
                view.textContainerOrigin
            )
        #else
            let view = harness.view
            return (
                view.textStorage, view.layoutManager, view.textContainer,
                CGPoint(x: view.textContainerInset.left, y: view.textContainerInset.top)
            )
        #endif
    }

    /// Each checklist item has one checkbox, centred on its first line's capital letters and at least as tall as
    /// them, in its column and clear of the text; on iPhone and iPad no two touch areas overlap.
    private func checkBoxes(_ harness: EditorHarness, items: [Paragraph], size: CGFloat) throws {
        let (storage, layout, container, origin) = try parts(harness)
        var touchAreas: [CGRect] = []
        for item in items where ["task", "checked"].contains(item.kind) {
            let placement = try XCTUnwrap(
                InlineTasks.placement(
                    at: item.location, storage: storage, layout: layout, container: container, origin: origin))
            #if os(macOS)
                let button = try XCTUnwrap(
                    harness.view.subviews.compactMap { $0 as? NSButton }.first { $0.tag == item.location },
                    "\(item.text) has a checkbox at \(size) pt")
                XCTAssertEqual(button.state == .on, item.kind == "checked")
                let box = button.frame
                let boxHeight = button.cell?.cellSize.height ?? 0
            #else
                let button = try XCTUnwrap(
                    harness.view.subviews.compactMap { $0 as? ChecklistBox }.first { $0.tag == item.location },
                    "\(item.text) has a checkbox at \(size) pt")
                XCTAssertEqual(button.accessibilityValue, item.kind == "checked" ? "Checked" : "Unchecked")
                let box = button.box.convert(button.box.bounds, to: harness.view)
                let boxHeight = box.height
                XCTAssertGreaterThanOrEqual(button.frame.height, min(InlineTasks.touchHeight, 30))
                XCTAssertLessThanOrEqual(button.frame.maxX, item.textX + 0.5, "The touch area is clear of the text.")
                XCTAssertTrue(
                    button.frame.insetBy(dx: -0.5, dy: -0.5).contains(box),
                    "The touch area \(button.frame) holds the box \(box).")
                touchAreas.append(button.frame)
            #endif
            // Within a tenth of an em: symbols sit on the text's baseline, as Apple draws them beside text.
            XCTAssertEqual(box.midY, placement.capCenter, accuracy: max(1.5, size * 0.1), "Centred at \(size) pt")
            #if os(macOS)
                // The large checkbox is the Mac's largest; above 20 pt the text outgrows it, which is accepted.
                if size <= 20 { XCTAssertGreaterThanOrEqual(boxHeight, placement.font.capHeight, "\(item.text)") }
                XCTAssertEqual(button.controlSize, size > 20 ? .large : .regular)
            #else
                XCTAssertGreaterThanOrEqual(boxHeight, placement.font.capHeight, "\(item.text) at \(size) pt")
            #endif
            XCTAssertGreaterThanOrEqual(box.minX, item.markerX - 0.5)
            #if os(iOS)
                XCTAssertLessThanOrEqual(box.maxX, item.textX - 2, "A gap between the box and the text.")
            #endif
        }
        for (index, area) in touchAreas.enumerated() {
            for other in touchAreas.dropFirst(index + 1) {
                XCTAssertFalse(area.intersects(other), "Touch areas \(area) and \(other) overlap at \(size) pt")
            }
        }
    }
}
