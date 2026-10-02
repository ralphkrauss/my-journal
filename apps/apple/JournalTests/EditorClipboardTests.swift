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

/// Copy, cut, paste and drop keep what the person copied: structure within the journal, original image files from
/// elsewhere, and text rather than a picture of it.
@MainActor final class EditorClipboardTests: XCTestCase {
    func testCopyAndPasteWithinTheJournalKeepImagesListsAndTables() throws {
        let attachment = UUID()
        var table = DocumentBlock(kind: "table")
        table.table = DocumentTable(
            rows: [[[TextRun("Name")], [TextRun("Value")]], [[TextRun("A")], [TextRun("B")]]], alignments: [nil, nil])
        let original = JournalDocument(blocks: [
            DocumentBlock(runs: [TextRun("Intro "), TextRun("bold", bold: true)]),
            DocumentBlock(kind: "image", attachmentID: attachment, imageDescription: "A path", mediaType: "image/png"),
            DocumentBlock(kind: "task", runs: [TextRun("Buy milk")]),
            table,
            DocumentBlock(kind: "quote", runs: [TextRun("Quoted")]),
        ])
        let source = EditorHarness(original)
        defer { source.close() }
        let target = EditorHarness(markdown: "")
        defer { target.close() }
        source.select(NSRange(location: 0, length: source.text.length))
        #if os(macOS)
            let board = NSPasteboard(name: NSPasteboard.Name("EditorClipboardTests-" + UUID().uuidString))
            defer { board.releaseGlobally() }
            XCTAssertTrue(source.view.writeSelection(to: board, types: source.view.writablePasteboardTypes))
            XCTAssertFalse(board.string(forType: .string)?.contains("\u{FFFC}") ?? true)
            XCTAssertTrue(target.view.readSelection(from: board))
        #else
            source.view.cut(nil)
            XCTAssertEqual(source.document.text, "")
            target.view.paste(nil)
        #endif
        let pasted = target.document.blocks.filter { $0.kind != "paragraph" || !$0.runs.isEmpty }
        XCTAssertEqual(pasted.map(\.kind), ["paragraph", "image", "task", "table", "quote"], target.document.markdown)
        XCTAssertEqual(pasted.map { $0.runs.map(\.text).joined() }, ["Intro bold", "", "Buy milk", "", "Quoted"])
        XCTAssertTrue(pasted[0].runs.contains { $0.bold })
        XCTAssertEqual(pasted[1].attachmentID, attachment)
        XCTAssertEqual(pasted[1].imageDescription, "A path")
        XCTAssertEqual(pasted[3].table, table.table)
    }

    /// As in Notes, a web page's or document's lists, headings, quote and code become the entry's own blocks, and a
    /// link's underline, which is how other apps draw links, isn't stored as underline formatting.
    func testFormattedTextFromAnotherAppKeepsItsBlocksAndLinksWithoutUnderline() throws {
        let page = """
            <h1>Trip notes</h1><p>Some <b>bold</b> and <a href="https://example.com/x">a link</a>.</p>
            <ul><li>one</li><li>two<ul><li>nested</li></ul></li></ul><ol><li>first</li><li>second</li></ol>
            <blockquote>Quoted words</blockquote><pre>let x = 1
            let y = 2</pre><p>After</p>
            """
        #if os(macOS)
            let quote = "quote"
        #else
            // UIKit's importer doesn't indent a page's quotation, so nothing marks it as one on iPhone and iPad.
            let quote = "paragraph"
        #endif
        let kinds = [
            "heading", "paragraph", "bullet", "bullet", "bullet", "numbered", "numbered", quote, "codeBlock",
            "paragraph",
        ]
        let texts = [
            "Trip notes", "Some bold and a link.", "one", "two", "nested", "first", "second", "Quoted words",
            "let x = 1\nlet y = 2", "After",
        ]
        let text = try Self.html(page)
        let fragment = try XCTUnwrap(PastedRichText.fragment(text))
        let markdown = JournalDocument(blocks: fragment.blocks).markdown
        let reopened = JournalDocument(markdown: markdown).blocks.filter { $0.kind != "paragraph" || !$0.runs.isEmpty }
        XCTAssertEqual(reopened.map(\.kind), kinds, markdown)
        XCTAssertEqual(reopened.map { $0.runs.map(\.text).joined().trimmingCharacters(in: .newlines) }, texts)
        XCTAssertEqual(reopened.map { $0.listIndents?.count ?? 0 }, [0, 0, 0, 0, 1, 0, 0, 0, 0, 0], markdown)
        XCTAssertTrue(markdown.contains("[a link](<https://example.com/x>)"), markdown)
        XCTAssertFalse(markdown.contains("<u>"), markdown)
        #if os(macOS)
            // The Mac's text view reads it from the pasteboard, as it does for a paste or drop.
            let pasted = EditorHarness(markdown: "")
            defer { pasted.close() }
            pasted.pasteRichText(text)
            let blocks = pasted.document.blocks.filter { $0.kind != "paragraph" || !$0.runs.isEmpty }
            XCTAssertEqual(blocks.map(\.kind), kinds, pasted.document.markdown)
        #endif
        // Text without blocks of its own is pasted by the text view itself; its link isn't underlined either.
        let harness = EditorHarness(markdown: "")
        defer { harness.close() }
        harness.pasteRichText(try Self.html("<p>See <a href=\"https://example.com/y\">this page</a>.</p>"))
        let link = try XCTUnwrap(harness.document.blocks.flatMap(\.runs).first { $0.link != nil })
        XCTAssertEqual(link.text, "this page")
        XCTAssertFalse(link.underline)
    }

    private static func html(_ page: String) throws -> NSAttributedString {
        try NSAttributedString(
            data: Data(page.utf8),
            options: [
                .documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil)
    }

    func testTextCopiedWithinAParagraphJoinsTheParagraphItIsPastedInto() throws {
        let source = EditorHarness(markdown: "# A heading to copy from")
        defer { source.close() }
        let target = EditorHarness(markdown: "Body text")
        defer { target.close() }
        source.select("heading")
        let markdown = try XCTUnwrap(source.coordinator.markdown(for: source.selection))
        target.caret(at: 4)
        target.coordinator.pasteMarkdown(markdown)
        XCTAssertEqual(target.document.markdown.trimmingCharacters(in: .newlines), "Bodyheading text")
    }

    /// A line copied with its line break, from a web page or as plain text, fills a template's empty answer line
    /// as typing it does, without an empty paragraph left beside it.
    func testALinePastedOnAnEmptyAnswerLineFillsIt() throws {
        let line = "Fixed the sync bug, wrote docs *twice*."
        let content = NSAttributedString(
            string: line + "\n", attributes: [.font: PlatformFont.systemFont(ofSize: 12, weight: .bold)])
        let rtf = try content.data(
            from: NSRange(location: 0, length: content.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        for sample in [
            PasteSample(name: "plain text", plain: line + "\n"),
            PasteSample(name: "web page", html: Data("<p>\(line)</p>".utf8), plain: line),
            PasteSample(name: "formatted text", rtf: rtf, plain: line),
        ] {
            let name = sample.name
            let harness = EditorHarness(
                JournalDocument(
                    blocks: ["What I worked on", "Decisions and context"].flatMap {
                        [DocumentBlock(kind: "heading", runs: [TextRun($0)]), DocumentBlock()]
                    }))
            defer { harness.close() }
            harness.caret(at: ("What I worked on\n" as NSString).length)
            harness.paste(sample)
            let blocks = harness.document.blocks.filter { $0.kind != "paragraph" || !$0.runs.isEmpty }
            XCTAssertEqual(blocks.map(\.kind), ["heading", "paragraph", "heading"], name)
            XCTAssertEqual(blocks[1].runs.map(\.text).joined(), line, name)
            XCTAssertEqual(harness.document.blocks.count, 4, "\(name): \(harness.document.markdown)")
            XCTAssertFalse(blocks[1].runs.contains { $0.italic }, "The asterisks are the line's own text.")
            XCTAssertEqual(blocks[1].runs.contains { $0.bold }, name == "formatted text", name)
            XCTAssertEqual(harness.selection.location, ("What I worked on\n" + line as NSString).length, name)
        }
    }

    func testImagesPastedOrDroppedAsFormattedContentAreStoredAsJournalImages() throws {
        let stored = UUID()
        let received = Received()
        let harness = EditorHarness(JournalDocument(blocks: [DocumentBlock(runs: [TextRun("Before")])])) { data in
            received.data.append(data)
            return DocumentBlock(kind: "image", attachmentID: stored, imageDescription: "", mediaType: "image/png")
        }
        defer { harness.close() }
        let png = try Self.image(.png, width: 40, height: 20)
        let content = NSMutableAttributedString(string: "Pasted ")
        content.append(NSAttributedString(attachment: NSTextAttachment(data: png, ofType: UTType.png.identifier)))
        harness.caret(at: harness.text.length)
        harness.insertForeign(content)
        XCTAssertFalse(harness.document.markdown.contains("\u{FFFC}"), harness.document.markdown)
        harness.wait { harness.document.references(to: stored) == 1 }
        XCTAssertEqual(harness.document.references(to: stored), 1, harness.document.markdown)
        XCTAssertEqual(received.data, [png], "The picture is stored as the file it was")
        XCTAssertTrue(harness.document.text.contains("BeforePasted"), harness.document.markdown)
        XCTAssertFalse(harness.document.markdown.contains("\u{FFFC}"))
    }

    #if os(macOS)
        func testDroppedJournalContentAndPictureFilesGoWhereTheyAreDropped() throws {
            let attachment = UUID()
            let source = EditorHarness(
                JournalDocument(blocks: [
                    DocumentBlock(runs: [TextRun("Dragged")]),
                    DocumentBlock(
                        kind: "image", attachmentID: attachment, imageDescription: "", mediaType: "image/png"),
                ]))
            defer { source.close() }
            let board = NSPasteboard(name: NSPasteboard.Name("EditorClipboardTests-" + UUID().uuidString))
            defer { board.releaseGlobally() }
            source.select(NSRange(location: 0, length: source.text.length))
            XCTAssertTrue(source.view.writeSelection(to: board, types: source.view.writablePasteboardTypes))
            let stored = [UUID(), UUID()]
            let imported = Received()
            let target = EditorHarness(JournalDocument(markdown: "First line\n\nSecond line")) { data in
                imported.data.append(data)
                let id = stored[min(imported.data.count, stored.count) - 1]
                return DocumentBlock(kind: "image", attachmentID: id, imageDescription: "", mediaType: "image/png")
            }
            defer { target.close() }
            try drop(board, on: target, at: (target.text.string as NSString).range(of: "Second").location)
            XCTAssertEqual(
                target.document.blocks.map(\.kind), ["paragraph", "paragraph", "image", "paragraph"],
                target.document.markdown)
            XCTAssertEqual(target.document.blocks[2].attachmentID, attachment)
            XCTAssertEqual(target.document.blocks.last?.runs.map(\.text).joined(), "Second line")
            // Several picture files dropped together all arrive, in order, as the files they are.
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let files = [folder.appendingPathComponent("one.png"), folder.appendingPathComponent("two.jpg")]
            let pictures = [try Self.image(.png, width: 8, height: 8), try Self.image(.jpeg, width: 8, height: 8)]
            for (file, picture) in zip(files, pictures) { try picture.write(to: file) }
            board.clearContents()
            board.writeObjects(files.map { $0 as NSURL })
            try drop(board, on: target, at: 0)
            target.wait { target.document.references(to: stored[1]) == 1 }
            XCTAssertEqual(imported.data, pictures)
            let images = target.document.blocks.compactMap(\.attachmentID)
            XCTAssertEqual(Array(images.prefix(2)), stored)
        }

        private func drop(_ board: NSPasteboard, on harness: EditorHarness, at location: Int) throws {
            let layout = try XCTUnwrap(harness.view.layoutManager)
            let container = try XCTUnwrap(harness.view.textContainer)
            let glyph = layout.glyphIndexForCharacter(at: location)
            var point = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).origin
            point.x += harness.view.textContainerOrigin.x + 1
            point.y += harness.view.textContainerOrigin.y + 1
            let drag = TestDrag(board, location: harness.view.convert(point, to: nil), window: harness.window)
            XCTAssertNotEqual(harness.view.draggingEntered(drag), [])
            XCTAssertNotEqual(harness.view.draggingUpdated(drag), [])
            XCTAssertTrue(harness.view.prepareForDragOperation(drag))
            XCTAssertTrue(harness.view.performDragOperation(drag))
            harness.view.concludeDragOperation(drag)
        }

        func testPasteboardChoiceKeepsDocumentTextAndOriginalPictures() async throws {
            let board = NSPasteboard(name: NSPasteboard.Name("EditorClipboardTests-" + UUID().uuidString))
            defer { board.releaseGlobally() }
            let png = try Self.image(.png, width: 30, height: 30)
            let jpeg = try Self.image(.jpeg, width: 30, height: 30)
            let tiff = try Self.image(.tiff, width: 300, height: 300)
            // A word processor offers its text together with a picture of it.
            board.clearContents()
            let rtf = NSAttributedString(string: "Words").rtf(
                from: NSRange(location: 0, length: 5), documentAttributes: [:])
            board.declareTypes([.rtf, .string, .png], owner: nil)
            board.setData(rtf, forType: .rtf)
            board.setString("Words", forType: .string)
            board.setData(png, forType: .png)
            XCTAssertTrue(PastedImages.images(on: board).isEmpty)
            // A photo keeps its own bytes, and a picture with only its web address is still a picture.
            board.clearContents()
            board.declareTypes([.string, NSPasteboard.PasteboardType(UTType.jpeg.identifier), .tiff], owner: nil)
            board.setString("https://example.com/photo.jpg", forType: .string)
            board.setData(jpeg, forType: NSPasteboard.PasteboardType(UTType.jpeg.identifier))
            board.setData(tiff, forType: .tiff)
            let photo = PastedImages.images(on: board)
            XCTAssertEqual(photo.count, 1)
            let photoData = await PastedImages.data(for: try XCTUnwrap(photo.first))
            XCTAssertEqual(photoData, jpeg)
            // A bitmap alone is encoded once, not kept as uncompressed TIFF, and the paste menu accepts it.
            board.clearContents()
            board.setData(tiff, forType: .tiff)
            let view = JournalTextView(frame: .zero)
            XCTAssertNotNil(board.availableType(from: view.readablePasteboardTypes))
            let encoded = await PastedImages.data(for: try XCTUnwrap(PastedImages.images(on: board).first))
            let bitmap = try XCTUnwrap(encoded)
            XCTAssertLessThan(bitmap.count, tiff.count / 4)
            XCTAssertNoThrow(try ImportedImage.mediaType(for: bitmap))
            // Every picture file dropped or pasted is kept, in order, as the file it is.
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let files = [folder.appendingPathComponent("one.png"), folder.appendingPathComponent("two.jpg")]
            try png.write(to: files[0])
            try jpeg.write(to: files[1])
            board.clearContents()
            board.writeObjects(files.map { $0 as NSURL })
            var read: [Data] = []
            for source in PastedImages.images(on: board) {
                let data = await PastedImages.data(for: source)
                read.append(try XCTUnwrap(data))
            }
            XCTAssertEqual(read, [png, jpeg])
        }
    #else
        func testPasteboardChoiceKeepsDocumentTextAndOriginalPictures() async throws {
            let board = try XCTUnwrap(
                UIPasteboard(name: UIPasteboard.Name("EditorClipboardTests-" + UUID().uuidString), create: true))
            defer { UIPasteboard.remove(withName: board.name) }
            let png = try Self.image(.png, width: 30, height: 30)
            let jpeg = try Self.image(.jpeg, width: 30, height: 30)
            // A word processor offers its text together with a picture of it.
            let rtf = try NSAttributedString(string: "Words").data(
                from: NSRange(location: 0, length: 5),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            board.setItems([
                [UTType.rtf.identifier: rtf, UTType.utf8PlainText.identifier: "Words", UTType.png.identifier: png]
            ])
            XCTAssertTrue(PastedImages.images(on: board).isEmpty)
            // A photo keeps its own bytes, and a picture with only its web address is still a picture.
            board.setItems([
                [UTType.jpeg.identifier: jpeg, UTType.utf8PlainText.identifier: "https://example.com/photo.jpg"],
                [UTType.png.identifier: png],
            ])
            var read: [Data] = []
            for source in PastedImages.images(on: board) {
                let data = await PastedImages.data(for: source)
                read.append(try XCTUnwrap(data))
            }
            XCTAssertEqual(read, [jpeg, png])
        }
    #endif

    static func image(_ type: UTType, width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return bytes as Data
    }
}

@MainActor final class Received {
    var data: [Data] = []
}

#if os(macOS)
    /// A drag arriving from another app, as AppKit describes it to the view it is over.
    @MainActor private final class TestDrag: NSObject, @MainActor NSDraggingInfo {
        let draggingPasteboard: NSPasteboard
        let draggingLocation: NSPoint
        let draggingDestinationWindow: NSWindow?
        init(_ pasteboard: NSPasteboard, location: NSPoint, window: NSWindow) {
            draggingPasteboard = pasteboard
            draggingLocation = location
            draggingDestinationWindow = window
        }
        var draggingSourceOperationMask: NSDragOperation { [.copy, .generic] }
        var draggedImageLocation: NSPoint { draggingLocation }
        var draggedImage: NSImage? { nil }
        var draggingSource: Any? { nil }
        var draggingSequenceNumber: Int { 1 }
        var draggingFormation: NSDraggingFormation = .none
        var animatesToDestination = false
        var numberOfValidItemsForDrop = 1
        var springLoadingHighlight: NSSpringLoadingHighlight { .none }
        func slideDraggedImage(to screenPoint: NSPoint) {}
        override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
        func enumerateDraggingItems(
            options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass],
            searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
            using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
        ) {}
        func resetSpringLoading() {}
    }
#endif
