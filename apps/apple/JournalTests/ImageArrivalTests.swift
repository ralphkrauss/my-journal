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
final class ImageArrivalTests: XCTestCase {
    #if os(iOS)
        func testImagePresentationWaitsForNativeCompositionToEnd() throws {
            let imageID = UUID()
            var document = JournalDocument(blocks: [
                DocumentBlock(runs: [TextRun("Writing")]),
                DocumentBlock(
                    kind: "image", attachmentID: imageID, imageDescription: "A sketch", mediaType: "image/png"),
            ])
            var editor = NativeEditor(
                document: Binding(get: { document }, set: { document = $0 }), itemID: UUID(), images: [:],
                loadingImages: [imageID], fontSize: 17, editable: true, actions: EditorActions()
            ) { _ in nil }
            let coordinator = editor.makeCoordinator()
            let view = JournalTextView(frame: CGRect(x: 0, y: 0, width: 360, height: 500))
            coordinator.view = view
            view.delegate = coordinator
            coordinator.update(editor)
            view.selectedRange = NSRange(location: 7, length: 0)
            view.setMarkedText("途中", selectedRange: NSRange(location: 2, length: 0))
            XCTAssertNotNil(view.markedTextRange)
            let composed = document
            view.frame.size.width = 280
            view.layoutIfNeeded()
            editor.loadingImages = []
            coordinator.update(editor)
            XCTAssertNotNil(view.markedTextRange)
            XCTAssertEqual(document, composed)
            let pending = try XCTUnwrap(
                view.textStorage.attribute(.attachment, at: 10, effectiveRange: nil) as? NSTextAttachment)
            XCTAssertEqual(pending.accessibilityLabel, "Loading Image. A sketch")
            XCTAssertEqual(pending.bounds.width, 340)
            view.unmarkText()
            let unavailable = try XCTUnwrap(
                view.textStorage.attribute(.attachment, at: 10, effectiveRange: nil) as? NSTextAttachment)
            XCTAssertNil(view.markedTextRange)
            XCTAssertEqual(unavailable.accessibilityLabel, "Image unavailable. A sketch")
            XCTAssertEqual(unavailable.bounds.width, 260)
            XCTAssertEqual(document, composed)
        }

    #endif

    func testUndoAfterImageArrivalKeepsLoadedPresentationAndRedo() throws {
        let imageID = UUID()
        var document = JournalDocument(blocks: [
            DocumentBlock(runs: [TextRun("Original")]),
            DocumentBlock(
                kind: "image", attachmentID: imageID, imageDescription: "A sketch", mediaType: "image/png"),
        ])
        let original = document
        var editor = NativeEditor(
            document: Binding(get: { document }, set: { document = $0 }), itemID: UUID(), images: [:],
            loadingImages: [imageID], fontSize: 17, editable: true, actions: EditorActions()
        ) { _ in nil }
        let coordinator = editor.makeCoordinator()
        #if os(macOS)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 402, height: 874), styleMask: [.titled], backing: .buffered,
                defer: false)
            let view = JournalTextView(frame: NSRect(x: 0, y: 0, width: 402, height: 874))
            view.allowsUndo = true
            view.isRichText = true
            window.contentView = view
        #else
            let controller = UIViewController()
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = controller
            let view = JournalTextView(frame: window.bounds)
            controller.view.addSubview(view)
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
        #endif
        coordinator.view = view
        view.delegate = coordinator
        coordinator.update(editor)
        #if os(macOS)
            XCTAssertTrue(window.makeFirstResponder(view))
            let storage = try XCTUnwrap(view.textStorage)
        #else
            XCTAssertTrue(view.becomeFirstResponder())
            let storage = view.textStorage
        #endif
        let undo = try XCTUnwrap(view.undoManager)
        undo.beginUndoGrouping()
        let attributes = storage.attributes(at: 0, effectiveRange: nil)
        coordinator.replace(
            NSAttributedString(string: "Edited", attributes: attributes), range: NSRange(location: 0, length: 8))
        undo.endUndoGrouping()
        let edited = document
        #if os(macOS)
            let image = NSImage(size: NSSize(width: 120, height: 240))
            image.lockFocus()
            NSColor.systemBlue.setFill()
            NSRect(x: 0, y: 0, width: 120, height: 240).fill()
            image.unlockFocus()
            editor.images = [imageID: try XCTUnwrap(image.tiffRepresentation)]
        #else
            editor.images = [
                imageID: UIGraphicsImageRenderer(size: CGSize(width: 120, height: 240)).pngData { context in
                    UIColor.systemBlue.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 120, height: 240))
                }
            ]
        #endif
        editor.loadingImages = []
        coordinator.update(editor)
        let loaded = try XCTUnwrap(
            storage.attribute(.attachment, at: 7, effectiveRange: nil) as? NSTextAttachment)
        undo.undo()
        XCTAssertEqual(document, original)
        let restored = try XCTUnwrap(
            storage.attribute(.attachment, at: 9, effectiveRange: nil) as? NSTextAttachment)
        #if os(macOS)
            let loadedCell = try XCTUnwrap(loaded.attachmentCell as? NSTextAttachmentCell)
            let restoredCell = try XCTUnwrap(restored.attachmentCell as? NSTextAttachmentCell)
            XCTAssertEqual(restoredCell.image?.accessibilityDescription, "A sketch")
            XCTAssertEqual(restoredCell.cellSize(), loadedCell.cellSize())
        #else
            XCTAssertEqual(restored.accessibilityLabel, "A sketch")
            XCTAssertEqual(restored.bounds, loaded.bounds)
        #endif
        XCTAssertTrue(undo.canRedo)
        undo.redo()
        XCTAssertEqual(document, edited)
    }

    func testImageOnlyArrivalPreservesNativeSelectionTypingStyleAndDocument() throws {
        try verifyArrival(Data([1, 2, 3]))
        #if os(macOS)
            let image = NSImage(size: NSSize(width: 120, height: 240))
            image.lockFocus()
            NSColor.systemBlue.setFill()
            NSRect(x: 0, y: 0, width: 120, height: 240).fill()
            image.unlockFocus()
            try verifyArrival(XCTUnwrap(image.tiffRepresentation))
        #else
            let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 240)).pngData { context in
                UIColor.systemBlue.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 120, height: 240))
            }
            try verifyArrival(image)
        #endif
    }

    private func verifyArrival(_ bytes: Data) throws {
        let imageID = UUID()
        var document = JournalDocument(blocks: [
            DocumentBlock(runs: [TextRun("Keep this selection")]),
            DocumentBlock(kind: "image", attachmentID: imageID, imageDescription: "A sketch", mediaType: "image/png"),
            DocumentBlock(runs: [TextRun("Keep the writing below")]),
        ])
        let original = document
        var editor = NativeEditor(
            document: Binding(get: { document }, set: { document = $0 }), itemID: UUID(), images: [:],
            loadingImages: [imageID], fontSize: 17, editable: true, actions: EditorActions()
        ) { _ in nil }
        let coordinator = editor.makeCoordinator()
        let view = JournalTextView(frame: CGRect(x: 0, y: 0, width: 360, height: 500))
        coordinator.view = view
        view.delegate = coordinator
        coordinator.update(editor)
        let selection = NSRange(location: 2, length: 8)
        let style = RichText.attributes(kind: "paragraph", size: 17, run: TextRun("", italic: true))
        #if os(macOS)
            view.setSelectedRange(selection)
        #else
            view.selectedRange = selection
        #endif
        view.typingAttributes = style
        // Decode failure is a real completion too: loading must become unavailable without rewriting text.
        editor.images = [imageID: bytes]
        editor.loadingImages = []
        coordinator.update(editor)
        #if os(macOS)
            XCTAssertEqual(view.selectedRange(), selection)
            let storage = try XCTUnwrap(view.textStorage)
        #else
            XCTAssertEqual(view.selectedRange, selection)
            let storage = view.textStorage
        #endif
        XCTAssertEqual(view.typingAttributes[.font] as? PlatformFont, style[.font] as? PlatformFont)
        XCTAssertEqual(RichText.document(storage), original)
        XCTAssertEqual(document, original)
    }
}
