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
            // Build 13's hidden ☐ fell back to a font with a deeper descent, so unchecked items' first lines were
            // taller and checking one moved the text below it.
            XCTAssertEqual(items[2].firstLineHeight, items[3].firstLineHeight, accuracy: 0.01, "at \(size) pt")
            XCTAssertEqual(items[0].firstLineHeight, items[2].firstLineHeight, accuracy: 0.01, "at \(size) pt")
            try checkBoxes(harness, items: items, size: size)
        }
    }

    /// A numbered list's numbers keep at least a space before their text, two-digit and three-digit ones included,
    /// and every item's text lines up, at the default and the largest text size: the list's column fits its widest
    /// number. A Return that makes the list's first wider number widens every item's column with it.
    func testNumbersKeepASpaceBeforeTheirTextAndTheListLinesUp() throws {
        let harness = EditorHarness(JournalDocument(), width: 402)
        defer { harness.close() }
        #if os(macOS)
            let sizes: [CGFloat] = [16, 30]
        #else
            let sizes: [CGFloat] = [17, 53]
        #endif
        for size in sizes {
            for markdown in ["97. One\n98. Two \(Self.long)\n99. Three", "98. One\n99. Two\n100. Three \(Self.long)"] {
                show(markdown, size: size, in: harness)
                try assertNumbersFit(harness, size: size, markdown)
            }
            // Return after item 9 makes item 10.
            show("8. Eight\n9. Nine", size: size, in: harness)
            harness.caret(at: harness.text.length - 1)
            harness.pressReturn()
            harness.type("Ten")
            try assertNumbersFit(harness, size: size, "after Return makes item 10")
        }
    }

    private func assertNumbersFit(_ harness: EditorHarness, size: CGFloat, _ name: String) throws {
        let items = try paragraphs(harness)
        let font = ListMarkers.font(size: size)
        let space = (" " as NSString).size(withAttributes: [.font: font]).width
        for item in items {
            let number = try XCTUnwrap(
                harness.text.attribute(.journalListNumber, at: item.location, effectiveRange: nil) as? Int)
            let width = ("\(number)." as NSString).size(withAttributes: [.font: font]).width
            XCTAssertGreaterThanOrEqual(
                item.textX - item.markerX, width + space - 0.5, "\(number). keeps a space at \(size) pt, \(name)")
            XCTAssertEqual(item.textX, items[0].textX, accuracy: 0.5, "\(number). lines up at \(size) pt, \(name)")
            for line in item.lines.dropFirst() { XCTAssertEqual(line, item.textX, accuracy: 0.5, name) }
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

    /// Lists start the list inset (the quote indent) in from the body text at every text size, with their text a
    /// column further in. Nesting and the content of an item move with it: a nested marker sits under its parent's
    /// text, and an item's second paragraph lines up with the item's text. A list in a quote starts its inset after
    /// the quote's own indent. Only the presentation moves: an edit saves the Markdown as written
    /// (docs/design/client-only-mac-lists-markdown-2026-10-05.md).
    func testListsStartAtTheListInsetAndTheirContentMovesWithThem() throws {
        let harness = EditorHarness(JournalDocument(), width: 402)
        defer { harness.close() }
        #if os(macOS)
            let sizes: [CGFloat] = [13, 16, 30]
        #else
            let sizes: [CGFloat] = [17, 53]
        #endif
        let markdown = """
            Body text \(Self.long)

            - Bullet \(Self.long)

              Second paragraph \(Self.long)
              - Nested bullet

            1. Numbered

            - [ ] Unchecked

            > Quoted text
            > - Quoted item
            """
        for size in sizes {
            show(markdown, size: size, in: harness)
            let body = try XCTUnwrap(try lineStarts(of: "Body text", in: harness).first)
            let items = try paragraphs(harness)
            XCTAssertEqual(items.map(\.kind), ["bullet", "bullet", "numbered", "task", "bullet"])
            for index in [0, 2, 3] {
                XCTAssertEqual(
                    items[index].markerX, body + RichText.listInset, accuracy: 0.5,
                    "\(items[index].kind) marker at \(size) pt")
                XCTAssertEqual(
                    items[index].textX, body + RichText.listInset + RichText.listColumn(size: size), accuracy: 0.5,
                    "\(items[index].kind) text at \(size) pt")
            }
            XCTAssertEqual(items[1].markerX, items[0].textX, accuracy: 0.5, "Nested marker at \(size) pt")
            let second = try lineStarts(of: "Second paragraph", in: harness)
            XCTAssertGreaterThan(second.count, 1, "The second paragraph wraps at \(size) pt")
            for line in second {
                XCTAssertEqual(line, items[0].textX, accuracy: 0.5, "Second paragraph at \(size) pt")
            }
            // A quote's "> " moves what it holds in by half an em per character; its list's inset comes after that.
            XCTAssertEqual(
                items[4].markerX, body + size + RichText.listInset, accuracy: 0.5, "Quoted list at \(size) pt")
            let quote = try XCTUnwrap(try lineStarts(of: "Quoted text", in: harness).first)
            XCTAssertGreaterThan(items[4].markerX, quote, "The quoted list starts inside the quote at \(size) pt")
        }
        harness.caret(at: (harness.text.string as NSString).range(of: "Nested bullet").upperBound)
        harness.type("!")
        XCTAssertEqual(
            harness.document.markdown, markdown.replacingOccurrences(of: "Nested bullet", with: "Nested bullet!"))
    }

    /// A tap or click on a checkbox where it is drawn, at the list inset, reaches the checkbox and toggles its item,
    /// a nested item's too.
    func testCheckboxTapsToggleTheirItems() throws {
        let harness = EditorHarness(JournalDocument(), width: 402)
        defer { harness.close() }
        #if os(macOS)
            let sizes: [CGFloat] = [13, 30]
        #else
            let sizes: [CGFloat] = [17, 53]
        #endif
        for size in sizes {
            show("- [ ] Parent item\n  - [ ] Nested item", size: size, in: harness)
            let (storage, layout, container, origin) = try parts(harness)
            for name in ["Parent item", "Nested item"] {
                let location = (storage.string as NSString).range(of: name).location
                let placement = try XCTUnwrap(
                    InlineTasks.placement(
                        at: location, storage: storage, layout: layout, container: container, origin: origin))
                let point = CGPoint(x: placement.boxX + placement.font.capHeight / 2, y: placement.capCenter)
                #if os(macOS)
                    let hit = harness.view.hitTest(harness.view.convert(point, to: harness.view.superview))
                    let button = try XCTUnwrap(hit as? NSButton, "\(name)'s checkbox is hit at \(size) pt")
                    button.performClick(nil)
                #else
                    let hit = harness.view.hitTest(point, with: nil)
                    let button = try XCTUnwrap(hit as? ChecklistBox, "\(name)'s checkbox is hit at \(size) pt")
                    button.sendActions(for: .touchUpInside)
                #endif
                harness.settle(0.05)
                XCTAssertEqual(
                    harness.text.attribute(.journalKind, at: location, effectiveRange: nil) as? String, "checked",
                    "\(name) at \(size) pt")
            }
            XCTAssertEqual(harness.document.markdown, "- [x] Parent item\n  - [x] Nested item", "at \(size) pt")
        }
    }

    /// Bullets and numbers are drawn, not stored, and they must look exactly as the characters the text system drew
    /// in their place did: same glyph, size, position and colour.
    func testDrawnBulletsAndNumbersMatchTheCharactersTheyReplace() throws {
        let harness = EditorHarness(JournalDocument(), width: 402)
        defer { harness.close() }
        #if os(macOS)
            let sizes: [CGFloat] = [16, 30]
        #else
            let sizes: [CGFloat] = [17, 53]
        #endif
        for size in sizes {
            for (markdown, marker, text) in [("- Bullet", "•", "Bullet"), ("1. Number", "1.", "Number")] {
                show(markdown, size: size, in: harness)
                let (_, layout, container, _) = try parts(harness)
                let column = RichText.listColumn(size: size)
                let margin = container.lineFragmentPadding + RichText.listInset + column - 1
                let drawn = try XCTUnwrap(ink(of: layout, width: container.size.width, before: margin))
                // The same line as the text system laid it out with the marker's characters, as build 13 stored it,
                // moved in by the list inset.
                var attributes = RichText.attributes(kind: "bullet", size: size)
                let style = NSMutableParagraphStyle()
                style.setParagraphStyle(try XCTUnwrap(attributes[.paragraphStyle] as? NSParagraphStyle))
                style.firstLineHeadIndent = RichText.listInset
                style.tabStops = [NSTextTab(textAlignment: .left, location: RichText.listInset + column)]
                attributes[.paragraphStyle] = style
                let storage = NSTextStorage(string: marker + "\t" + text, attributes: attributes)
                let reference = NSLayoutManager()
                storage.addLayoutManager(reference)
                let referenceContainer = NSTextContainer(size: container.size)
                referenceContainer.lineFragmentPadding = container.lineFragmentPadding
                reference.addTextContainer(referenceContainer)
                let expected = try XCTUnwrap(ink(of: reference, width: container.size.width, before: margin))
                XCTAssertEqual(drawn.minX, expected.minX, accuracy: 0.5, "\(marker) at \(size) pt")
                XCTAssertEqual(drawn.maxX, expected.maxX, accuracy: 0.5, "\(marker) at \(size) pt")
                XCTAssertEqual(drawn.minY, expected.minY, accuracy: 0.5, "\(marker) at \(size) pt")
                XCTAssertEqual(drawn.maxY, expected.maxY, accuracy: 0.5, "\(marker) at \(size) pt")
            }
        }
    }

    /// The bounds, in points, of what `layout` draws left of `before` points from the container's edge.
    private func ink(of layout: NSLayoutManager, width: CGFloat, before limit: CGFloat) -> CGRect? {
        guard let container = layout.textContainers.first else { return nil }
        let glyphs = layout.glyphRange(for: container)
        let height = layout.usedRect(for: container).height + 20
        #if os(macOS)
            let image = NSImage(size: CGSize(width: width, height: height), flipped: true) { _ in
                layout.drawGlyphs(forGlyphRange: glyphs, at: .zero)
                return true
            }
            var rect = CGRect(x: 0, y: 0, width: width, height: height)
            guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        #else
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { _ in
                layout.drawGlyphs(forGlyphRange: glyphs, at: .zero)
            }
            guard let cgImage = image.cgImage else { return nil }
        #endif
        let pixelsWide = cgImage.width
        let pixelsHigh = cgImage.height
        var pixels = [UInt8](repeating: 0, count: pixelsWide * pixelsHigh * 4)
        guard
            let context = CGContext(
                data: &pixels, width: pixelsWide, height: pixelsHigh, bitsPerComponent: 8, bytesPerRow: pixelsWide * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
        let points = CGFloat(pixelsWide) / width
        var bounds: CGRect?
        for row in 0..<pixelsHigh {
            for column in 0..<min(pixelsWide, Int(limit * points))
            where pixels[(row * pixelsWide + column) * 4 + 3] > 64 {
                let pixel = CGRect(
                    x: CGFloat(column) / points, y: CGFloat(row) / points, width: 1 / points, height: 1 / points)
                bounds = bounds.map { $0.union(pixel) } ?? pixel
            }
        }
        return bounds
    }

    // MARK: - Measuring

    private struct Paragraph {
        let location: Int
        let kind: String
        let text: String
        /// Where the bullet or number is drawn, or the checkbox placed: the start of the item's column.
        let markerX: CGFloat
        /// The first character of the item's text.
        let textX: CGFloat
        /// Where each line of the item starts; the first is its text.
        let lines: [CGFloat]
        let firstLineHeight: CGFloat
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
        let (storage, layout, container, origin) = try parts(harness)
        XCTAssertTrue(layout is ListLayoutManager, "The editor draws its list markers with TextKit 1.")
        let source = storage.string as NSString
        var result: [Paragraph] = []
        var position = 0
        while position < storage.length {
            let range = source.paragraphRange(for: NSRange(location: position, length: 0))
            position = NSMaxRange(range)
            guard let kind = storage.attribute(.journalKind, at: range.location, effectiveRange: nil) as? String,
                ["bullet", "numbered", "task", "checked"].contains(kind)
            else { continue }
            var lines: [CGFloat] = []
            var heights: [CGFloat] = []
            layout.enumerateLineFragments(
                forGlyphRange: layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            ) { rect, _, _, glyphs, _ in
                lines.append(origin.x + rect.minX + layout.location(forGlyphAt: glyphs.location).x)
                heights.append(rect.height)
            }
            // Bullets and numbers where the layout manager draws them; checkboxes where they are placed.
            let drawn = ListMarkers.marker(atParagraph: range.location, layout: layout).map { origin.x + $0.x }
            let box = InlineTasks.placement(
                at: range.location, storage: storage, layout: layout, container: container, origin: origin)?.boxX
            let markerX = try XCTUnwrap(["task", "checked"].contains(kind) ? box : drawn, kind)
            result.append(
                Paragraph(
                    location: range.location, kind: kind, text: source.substring(with: range),
                    markerX: markerX, textX: lines.first ?? markerX, lines: lines,
                    firstLineHeight: heights.first ?? 0))
        }
        return result
    }

    /// Where each line of the paragraph that holds `string` starts.
    private func lineStarts(of string: String, in harness: EditorHarness) throws -> [CGFloat] {
        let (storage, layout, _, origin) = try parts(harness)
        let source = storage.string as NSString
        let found = source.range(of: string)
        XCTAssertNotEqual(found.location, NSNotFound, string)
        var lines: [CGFloat] = []
        layout.enumerateLineFragments(
            forGlyphRange: layout.glyphRange(
                forCharacterRange: source.paragraphRange(for: found), actualCharacterRange: nil)
        ) { rect, _, _, glyphs, _ in
            lines.append(origin.x + rect.minX + layout.location(forGlyphAt: glyphs.location).x)
        }
        return lines
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
