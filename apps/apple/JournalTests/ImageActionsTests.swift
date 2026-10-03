import ImageIO
import JournalCore
import SwiftUI
import UniformTypeIdentifiers
import XCTest

@testable import Journal

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// Acting on a picture in an entry: what Delete removes and what Copy hands other apps
/// (docs/design/image-actions-ios-2026-10-03.md, docs/design/image-actions-mac-2026-10-03.md).
@MainActor
final class ImageActionsTests: XCTestCase {
    private let id = UUID()
    private var link: String { "attachments/" + id.uuidString.lowercased() }

    func testWhatAPictureIsAndWhatDeletingItRemoves() throws {
        let text = RichText.render(
            JournalDocument(markdown: "Before\n\n![A red square](\(link))\n\nAfter"), size: 17, images: [:])
        let item = try XCTUnwrap(ImageItem.at(try XCTUnwrap(attachmentIndex(in: text)), in: text))
        XCTAssertFalse(item.inline)
        XCTAssertEqual(item.description, "A red square")
        XCTAssertEqual(item.type(of: try png(width: 4)), .png, "The type comes from the bytes.")
        XCTAssertEqual(ImageItem.fileName(for: .png), "Image.png", "The description doesn't travel with a shared file.")
        let line = item.deletionRange(in: text.string as NSString)
        XCTAssertEqual((text.string as NSString).substring(with: line), "\u{FFFC}\n", "The picture's own line.")

        let inline = RichText.render(
            JournalDocument(markdown: "A picture ![](\(link)) inside a line."), size: 17, images: [:])
        let inlineItem = try XCTUnwrap(ImageItem.at(try XCTUnwrap(attachmentIndex(in: inline)), in: inline))
        XCTAssertTrue(inlineItem.inline)
        XCTAssertEqual(inlineItem.deletionRange(in: inline.string as NSString).length, 1, "Only the picture.")
    }

    func testPasteboardGetsTheOriginalUnderItsOwnType() throws {
        let original = try png(width: 12)
        let representations = ImageItem.pasteboardRepresentations(of: original, type: .png)
        XCTAssertEqual(representations, [UTType.png.identifier: original])
    }

    #if os(iOS)
        /// Copy reads the stored original, not the smaller display copy the editor shows; the menu offers only Delete
        /// for a picture that isn't shown, and nothing that changes a read-only entry.
        func testMenuActionsFollowWhatIsShownAndCopyHandsOverTheOriginal() async throws {
            let original = try png(width: 40)
            let display = try png(width: 10)
            let harness = EditorHarness(markdown: "Before\n\n![A red square](\(link))\n\nAfter")
            defer { harness.close() }
            harness.view.pasteboard = UIPasteboard.withUniqueName()
            var reported: [String] = []
            harness.update {
                $0.imageActions = ImageActionSupport(
                    original: { [id] requested in requested == id ? original : nil }, report: { reported.append($0) },
                    describe: nil)
            }
            let item = try XCTUnwrap(ImageItem.at(try XCTUnwrap(attachmentIndex(in: harness.text)), in: harness.text))
            XCTAssertEqual(harness.coordinator.imageActions(for: item), [.delete], "Loading: only Delete.")
            harness.update { $0.images = [self.id: display] }
            XCTAssertEqual(harness.coordinator.imageActions(for: item), [.copy, .share, .save, .delete])
            harness.update { $0.editable = false }
            XCTAssertEqual(harness.coordinator.imageActions(for: item), [.copy, .share, .save], "Read-only.")
            harness.update { $0.editable = true }

            harness.coordinator.perform(.copy, on: item)
            for _ in 0..<100 where !harness.view.pasteboard.contains(pasteboardTypes: [UTType.png.identifier]) {
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertEqual(harness.view.pasteboard.data(forPasteboardType: UTType.png.identifier), original)
            XCTAssertTrue(reported.isEmpty)

            // A picture selected with a tap copies as the picture, keeping the entry's own Markdown.
            harness.view.pasteboard.items = []
            harness.select(NSRange(location: item.index, length: 1))
            harness.view.copy(nil)
            for _ in 0..<100 where !harness.view.pasteboard.contains(pasteboardTypes: [UTType.png.identifier]) {
                try await Task.sleep(for: .milliseconds(20))
            }
            let types = Set(harness.view.pasteboard.types)
            XCTAssertEqual(types, [UTType.png.identifier, PastedImages.markdownType])
        }

        /// Delete is one undo step, also when chosen while reading: writing starts, so the step is reachable.
        func testDeleteIsOneUndoStepWhileReading() throws {
            let markdown = "Before\n\n![A red square](\(link))\n\nAfter"
            let harness = EditorHarness(markdown: markdown)
            defer { harness.close() }
            harness.update {
                $0.imageActions = ImageActionSupport(original: { _ in nil }, report: { _ in }, describe: nil)
            }
            XCTAssertTrue(harness.view.resignFirstResponder())
            let item = try XCTUnwrap(ImageItem.at(try XCTUnwrap(attachmentIndex(in: harness.text)), in: harness.text))
            harness.coordinator.perform(.delete, on: item)
            harness.settle()
            XCTAssertEqual(harness.document.markdown, "Before\n\nAfter")
            // Writing started, so the text view's undo history is the one shake and ⌘Z reach.
            XCTAssertTrue(harness.view.isFirstResponder)
            let undo = try XCTUnwrap(harness.view.undoManager)
            XCTAssertEqual(undo.undoActionName, "Delete Image")
            undo.undo()
            harness.settle()
            XCTAssertEqual(harness.document.markdown, markdown)
        }
    #endif

    #if os(macOS)
        /// A right-click on a picture shows the picture's menu: what it offers follows whether the picture is shown
        /// and whether the entry can be edited. A right-click on text keeps the text menu.
        func testRightClickOnAPictureShowsItsMenu() throws {
            let harness = EditorHarness(markdown: "Before\n\n![A red square](\(link))\n\nAfter")
            defer { harness.close() }
            harness.update { $0.imageActions = self.support(original: { _ in nil }) }
            let index = try XCTUnwrap(attachmentIndex(in: harness.text))
            let loading = try XCTUnwrap(menu(rightClickingAt: index, in: harness))
            XCTAssertEqual(harness.selection, NSRange(location: index, length: 1), "The click selects the picture.")
            XCTAssertEqual(titles(loading), ["Cut", "Copy", "Paste", "", "Delete"], "Not shown: nothing to share.")

            let display = try png(width: 10)
            harness.update { $0.images = [self.id: display] }
            let shown = try XCTUnwrap(menu(rightClickingAt: index, in: harness))
            // The system's own Share item, with its own title.
            let share = shown.items.count > 4 ? shown.items[4].title : ""
            XCTAssertEqual(titles(shown), ["Cut", "Copy", "Paste", "", share, "Save Image As…", "", "Delete"])

            harness.update { $0.editable = false }
            let readOnly = try XCTUnwrap(menu(rightClickingAt: index, in: harness))
            XCTAssertEqual(titles(readOnly), ["Copy", "", share, "Save Image As…"])

            harness.update { $0.editable = true }
            let text = try XCTUnwrap(menu(rightClickingAt: 1, in: harness))
            XCTAssertTrue(text.items.contains { $0.title == "Spelling and Grammar" }, "Text keeps the text menu.")
        }

        /// Copy right after selecting a picture, before its original has been read, hands other apps the stored
        /// original, not the smaller display copy, with the entry's own Markdown and no text; another entry pastes it
        /// as the same picture. A drag that starts before the read finishes carries only the entry's content.
        func testCopyingASelectedPictureHandsOverTheOriginal() throws {
            let original = try png(width: 40)
            let markdown = "Before\n\n![A red square](\(link))\n\nAfter"
            let harness = EditorHarness(
                JournalDocument(markdown: markdown), images: [id: try png(width: 10)])
            defer { harness.close() }
            let board = NSPasteboard(name: NSPasteboard.Name("ImageActionsTests-" + UUID().uuidString))
            defer { board.releaseGlobally() }
            harness.view.pasteboard = board
            harness.update { $0.imageActions = self.support(original: { [id] in $0 == id ? original : nil }) }
            let index = try XCTUnwrap(attachmentIndex(in: harness.text))

            harness.select(NSRange(location: index, length: 1))
            let drag = NSPasteboard(name: NSPasteboard.Name("ImageActionsTests-drag-" + UUID().uuidString))
            defer { drag.releaseGlobally() }
            XCTAssertTrue(harness.view.writeSelection(to: drag, types: harness.view.writablePasteboardTypes))
            XCTAssertNil(drag.data(forType: .png), "Not read yet: the drag carries the entry's content only.")
            XCTAssertNotNil(drag.string(forType: .journalMarkdown))

            harness.view.copy(nil)
            harness.wait { board.data(forType: .png) != nil }
            XCTAssertEqual(board.data(forType: .png), original)
            // (The system also offers TIFF translated from the PNG.)
            let types = Set(board.types ?? [])
            XCTAssertTrue(types.isSuperset(of: [.png, .journalMarkdown]))
            XCTAssertTrue(types.isDisjoint(with: [.string, .rtf, .rtfd]), "No text for other apps to take instead.")
            let image = try XCTUnwrap(NSImage(pasteboard: board))
            XCTAssertEqual(image.representations.first?.pixelsWide, 40, "Pastes at the original size.")

            let target = EditorHarness(markdown: "")
            defer { target.close() }
            XCTAssertTrue(target.view.pasteJournalContent(from: board))
            XCTAssertEqual(target.document.references(to: id), 1, "Another entry pastes the same picture.")

            // Share hands services the original in memory, named “Image”, not the description.
            let provider = harness.coordinator.shareProvider(for: try XCTUnwrap(ImageItem.at(index, in: harness.text)))
            XCTAssertEqual(provider.suggestedName, "Image.png")
            let shared = Received()
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, _ in
                Task { @MainActor in shared.data += data.map { [$0] } ?? [] }
            }
            harness.wait { !shared.data.isEmpty }
            XCTAssertEqual(shared.data, [original])

            // Once read, a drag carries the picture too.
            drag.clearContents()
            XCTAssertTrue(harness.view.writeSelection(to: drag, types: harness.view.writablePasteboardTypes))
            XCTAssertEqual(drag.data(forType: .png), original)
        }

        /// Cut and Delete each remove the picture as one undo step, also when Delete is chosen while the entry isn't
        /// focused. A picture whose original can't be read is neither cut nor copied, and the pasteboard keeps what
        /// it had.
        func testCutAndDeleteAreOneUndoStepAndAFailedReadChangesNothing() throws {
            let markdown = "Before\n\n![A red square](\(link))\n\nAfter"
            let original = try png(width: 40)
            var stored: Data?
            var reported: [String] = []
            let harness = EditorHarness(JournalDocument(markdown: markdown), images: [id: try png(width: 10)])
            defer { harness.close() }
            let board = NSPasteboard(name: NSPasteboard.Name("ImageActionsTests-" + UUID().uuidString))
            defer { board.releaseGlobally() }
            harness.view.pasteboard = board
            harness.update {
                $0.imageActions = ImageActionSupport(
                    original: { _ in stored }, report: { reported.append($0) }, describe: nil)
            }
            let index = try XCTUnwrap(attachmentIndex(in: harness.text))
            let undo = try XCTUnwrap(harness.undoManager)

            // An original that can't be read is neither cut nor copied, and the pasteboard keeps what it had.
            stored = nil
            board.clearContents()
            board.setString("Kept", forType: .string)
            harness.select(NSRange(location: index, length: 1))
            harness.view.cut(nil)
            harness.wait { !reported.isEmpty }
            XCTAssertEqual(reported, ["The image couldn’t be copied."])
            XCTAssertEqual(board.string(forType: .string), "Kept")
            XCTAssertEqual(harness.document.markdown, markdown, "The picture stays.")

            // Once it can be read, Cut is tried again and removes the picture as one undo step.
            stored = original
            harness.view.cut(nil)
            harness.wait { board.data(forType: .png) != nil }
            XCTAssertEqual(board.data(forType: .png), original)
            XCTAssertEqual(harness.document.references(to: id), 0)
            XCTAssertEqual(undo.undoActionName, "Cut")
            undo.undo()
            harness.settle()
            XCTAssertEqual(harness.document.markdown, markdown)

            XCTAssertTrue(harness.window.makeFirstResponder(nil))
            let item = try XCTUnwrap(ImageItem.at(index, in: harness.text))
            harness.coordinator.perform(.delete, on: item)
            harness.settle()
            XCTAssertEqual(harness.document.markdown, "Before\n\nAfter")
            XCTAssertTrue(harness.window.firstResponder === harness.view, "⌘Z reaches the step at once.")
            XCTAssertEqual(undo.undoActionName, "Delete Image")
            undo.undo()
            harness.settle()
            XCTAssertEqual(harness.document.markdown, markdown)
        }

        /// VoiceOver reaches the picture's actions through its cell, and Copy there copies the picture without
        /// moving the selection, which VoiceOver's cursor doesn't do either.
        func testVoiceOverActionsActOnThePictureWithoutSelectingIt() throws {
            let original = try png(width: 40)
            let harness = EditorHarness(
                JournalDocument(markdown: "Before\n\n![A red square](\(link))\n\nAfter"),
                images: [id: try png(width: 10)])
            defer { harness.close() }
            let board = NSPasteboard(name: NSPasteboard.Name("ImageActionsTests-" + UUID().uuidString))
            defer { board.releaseGlobally() }
            harness.view.pasteboard = board
            harness.update { $0.imageActions = self.support(original: { _ in original }) }
            harness.coordinator.synchronizeTables()
            let index = try XCTUnwrap(attachmentIndex(in: harness.text))
            let attachment = harness.text.attribute(.attachment, at: index, effectiveRange: nil) as? NSTextAttachment
            let cell = try XCTUnwrap(attachment?.attachmentCell as? JournalImageCell)
            let actions = cell.accessibilityCustomActions() ?? []
            XCTAssertEqual(actions.map(\.name), ["Copy", "Share", "Save Image As", "Delete"])
            XCTAssertEqual(cell.image?.accessibilityDescription, "A red square")

            harness.caret(at: 0)
            _ = actions.first?.handler?()
            harness.wait { board.data(forType: .png) != nil }
            XCTAssertEqual(board.data(forType: .png), original)
            XCTAssertEqual(harness.selection, NSRange(location: 0, length: 0))
        }

        /// The picture's menu closes when the entry leaves the window, as when the app locks, which happens from the
        /// main actor while the menu is open.
        func testLockingClosesAnOpenPictureMenu() throws {
            let harness = EditorHarness(
                JournalDocument(markdown: "Before\n\n![A red square](\(link))\n\nAfter"),
                images: [id: try png(width: 10)])
            defer { harness.close() }
            harness.update { $0.imageActions = self.support(original: { _ in nil }) }
            let index = try XCTUnwrap(attachmentIndex(in: harness.text))
            let event = try rightClick(at: index, in: harness)
            let menu = try XCTUnwrap(harness.view.menu(for: event))
            let view = harness.view
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                view.removeFromSuperview()
            }
            let fallback = Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                menu.cancelTrackingWithoutAnimation()
            }
            defer { fallback.cancel() }
            let start = Date()
            NSMenu.popUpContextMenu(menu, with: event, for: view)
            XCTAssertLessThan(Date().timeIntervalSince(start), 3, "The menu closed when the entry left the window.")
            XCTAssertNil(harness.coordinator.pictureRead)
        }

        private func support(original: @escaping @MainActor (UUID) async -> Data?) -> ImageActionSupport {
            ImageActionSupport(original: original, report: { _ in }, describe: nil)
        }

        private func rightClick(at index: Int, in harness: EditorHarness) throws -> NSEvent {
            let layout = try XCTUnwrap(harness.view.layoutManager)
            let container = try XCTUnwrap(harness.view.textContainer)
            layout.ensureLayout(for: container)
            let glyphs = layout.glyphRange(
                forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            let point = NSPoint(
                x: rect.midX + harness.view.textContainerOrigin.x, y: rect.midY + harness.view.textContainerOrigin.y)
            return try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: .rightMouseDown, location: harness.view.convert(point, to: nil), modifierFlags: [],
                    timestamp: 0, windowNumber: harness.window.windowNumber, context: nil, eventNumber: 0,
                    clickCount: 1, pressure: 1))
        }

        private func menu(rightClickingAt index: Int, in harness: EditorHarness) throws -> NSMenu? {
            harness.caret(at: 0)
            return harness.view.menu(for: try rightClick(at: index, in: harness))
        }

        private func titles(_ menu: NSMenu) -> [String] {
            menu.items.map { $0.isSeparatorItem ? "" : $0.title }
        }
    #endif

    private func attachmentIndex(in text: NSAttributedString) -> Int? {
        var found: Int?
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, stop in
            guard value != nil else { return }
            found = range.location
            stop.pointee = true
        }
        return found
    }

    private func png(width: Int) throws -> Data {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: width, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: 8))
        let image = try XCTUnwrap(context.makeImage())
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return bytes as Data
    }
}
