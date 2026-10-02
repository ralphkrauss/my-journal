#if os(iOS)
    import JournalCore
    import SwiftUI
    import UIKit
    import UniformTypeIdentifiers
    import XCTest

    @testable import Journal

    @MainActor
    final class ImageViewportTests: XCTestCase {
        func testLoadingAndUnavailableImagesRemainReadableAtNormalAndLargestText() async throws {
            for (size, appearance) in [(CGFloat(17), UIUserInterfaceStyle.light), (CGFloat(53), .dark)] {
                let state = ImageViewportState()
                let host = UIHostingController(
                    rootView: ImageViewportHarness(state: state, size: size).environment(
                        \.colorScheme, appearance == .dark ? .dark : .light))
                let window = makeWindow(host, appearance: appearance)
                defer { window.isHidden = true }
                let view = try await editor(in: host)
                let original = state.document
                try await waitForImage("Loading Image. A sketch", in: view)
                view.layoutIfNeeded()
                let pending = try XCTUnwrap(
                    view.textStorage.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
                XCTAssertEqual(pending.bounds.width, view.bounds.width - 20, accuracy: 1)
                capture(host, name: "Image loading at \(Int(size)) points")
                state.loading = []
                try await waitForImage("Image unavailable. A sketch", in: view)
                capture(host, name: "Image unavailable at \(Int(size)) points")
                state.images = [state.imageID: imageBytes()]
                try await waitForImage("A sketch", in: view)
                capture(host, name: "Image loaded at \(Int(size)) points")
                XCTAssertEqual(state.document, original)
            }
        }

        /// A picture inserted above the caret pushes the caret line down; it ends up clear of the writing bar's
        /// capsule, which is drawn above the top of the keyboard's area, rather than half hidden behind it.
        func testCaretLineStaysClearOfTheWritingBarAfterInsertingAnImage() throws {
            let id = UUID()
            let png = try EditorClipboardTests.image(.png, width: 1000, height: 1450)
            let harness = EditorHarness(
                JournalDocument(blocks: [DocumentBlock(runs: [TextRun("Body text for the caret line")])]),
                images: [id: png], width: 400)
            defer { harness.close() }
            harness.caret(at: 0)
            let block = DocumentBlock(kind: "image", attachmentID: id, imageDescription: "", mediaType: "image/png")
            harness.coordinator.perform(.image(block))
            harness.settle(0.3)
            let view = harness.view
            XCTAssertTrue(view.isFirstResponder)
            XCTAssertEqual(harness.document.blocks.map(\.kind), ["image", "paragraph"])
            let caret = view.convert(view.caretRect(for: try XCTUnwrap(view.selectedTextRange).end), to: nil)
            let keyboard = view.convert(view.keyboardLayoutGuide.layoutFrame, to: nil)
            let visibleBottom = min(view.convert(view.bounds, to: nil).maxY, keyboard.minY)
            XCTAssertLessThanOrEqual(caret.maxY, visibleBottom - 17)
            XCTAssertGreaterThanOrEqual(caret.minY, view.convert(view.bounds, to: nil).minY)
        }

        func testImageArrivalAboveViewportKeepsVisibleTextAndSelection() async throws {
            let state = ImageViewportState(longDocument: true)
            let host = UIHostingController(rootView: ImageViewportHarness(state: state, size: 17))
            let window = makeWindow(host, appearance: .light)
            defer { window.isHidden = true }
            let view = try await editor(in: host)
            capture(host, name: "Initial viewport layout")
            await Task.yield()
            try await waitForImage("Loading Image. A sketch", in: view)
            XCTAssertTrue(view.becomeFirstResponder())
            let selection = (view.text as NSString).range(of: "Paragraph 18")
            XCTAssertNotEqual(selection.location, NSNotFound)
            view.selectedRange = selection
            let position = try XCTUnwrap(view.position(from: view.beginningOfDocument, offset: selection.location))
            let original = state.document
            view.layoutManager.ensureLayout(for: view.textContainer)
            let caret = view.caretRect(for: position)
            view.setContentOffset(CGPoint(x: 0, y: caret.minY - 100), animated: false)
            capture(host, name: "Writing before image arrival above viewport")
            XCTAssertTrue(view.isFirstResponder)
            let before = view.caretRect(for: position).minY - view.contentOffset.y
            XCTAssertEqual(before, 100, accuracy: 2)
            state.images = [state.imageID: imageBytes()]
            state.loading = []
            try await waitForImage("A sketch", in: view)
            view.layoutIfNeeded()
            let after = view.caretRect(for: position).minY - view.contentOffset.y
            XCTAssertEqual(after, before, accuracy: 2, "Image arrival must not move the visible writing.")
            XCTAssertEqual(view.selectedRange, selection)
            XCTAssertTrue(view.isFirstResponder)
            XCTAssertEqual(state.document, original)
            capture(host, name: "Writing after image arrival above viewport")
        }

        func testHeaderGrowthAndRemovalKeepPassiveReadingPosition() async throws {
            let state = ImageViewportState(longDocument: true)
            let host = UIHostingController(rootView: ImageViewportHarness(state: state, size: 17))
            let window = makeWindow(host, appearance: .light)
            defer { window.isHidden = true }
            let view = try await editor(in: host)
            try await waitForImage("Loading Image. A sketch", in: view)
            view.resignFirstResponder()
            let selection = (view.text as NSString).range(of: "Paragraph 18")
            let position = try XCTUnwrap(view.position(from: view.beginningOfDocument, offset: selection.location))
            view.selectedRange = selection
            view.layoutManager.ensureLayout(for: view.textContainer)
            view.setContentOffset(CGPoint(x: 0, y: view.caretRect(for: position).minY - 100), animated: false)
            let original = state.document
            for title in ["Daily notes\nA second line\nA third line", ""] {
                let oldInset = view.textContainerInset.top
                state.headerText = title
                for _ in 0..<100 {
                    host.view.layoutIfNeeded()
                    if abs(view.textContainerInset.top - oldInset) > 1 { break }
                    try await Task.sleep(for: .milliseconds(10))
                }
                XCTAssertNotEqual(view.textContainerInset.top, oldInset)
                XCTAssertEqual(view.caretRect(for: position).minY - view.contentOffset.y, 100, accuracy: 2)
                XCTAssertEqual(view.selectedRange, selection)
                XCTAssertFalse(view.isFirstResponder)
                XCTAssertEqual(state.document, original)
                XCTAssertGreaterThanOrEqual(view.contentOffset.y, -view.adjustedContentInset.top)
                XCTAssertLessThanOrEqual(
                    view.contentOffset.y,
                    max(
                        -view.adjustedContentInset.top,
                        view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom))
            }
        }

        func testAppearanceChangesPreserveNativeWritingSelectionAndUndo() async throws {
            let state = ImageViewportState(longDocument: true)
            let host = UIHostingController(rootView: ImageViewportHarness(state: state, size: 17))
            let window = makeWindow(host, appearance: .light)
            defer { window.isHidden = true }
            let view = try await editor(in: host)
            try await waitForImage("Loading Image. A sketch", in: view)
            XCTAssertTrue(view.becomeFirstResponder())
            let original = state.document
            let target = (view.text as NSString).range(of: "Paragraph 18")
            XCTAssertNotEqual(target.location, NSNotFound)
            view.selectedRange = target
            let undo = try XCTUnwrap(view.undoManager)
            undo.beginUndoGrouping()
            view.insertText("Today's work")
            undo.endUndoGrouping()
            let edited = state.document
            XCTAssertNotEqual(edited, original)
            XCTAssertEqual(edited.blocks[19].id, original.blocks[19].id)
            XCTAssertEqual(edited.blocks[19].runs.map(\.text).joined(), "Today's work. Keep writing while images load.")
            let selection = (view.text as NSString).range(of: "Today's work")
            view.selectedRange = selection
            let position = try XCTUnwrap(view.position(from: view.beginningOfDocument, offset: selection.location))
            view.layoutManager.ensureLayout(for: view.textContainer)
            view.setContentOffset(CGPoint(x: 0, y: view.caretRect(for: position).minY - 100), animated: false)
            for appearance in [UIUserInterfaceStyle.dark, .light] {
                window.overrideUserInterfaceStyle = appearance
                host.overrideUserInterfaceStyle = appearance
                for _ in 0..<10 {
                    host.view.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(10))
                }
                XCTAssertEqual(view.traitCollection.userInterfaceStyle, appearance)
                XCTAssertEqual(state.document, edited)
                XCTAssertEqual(view.selectedRange, selection)
                XCTAssertTrue(view.isFirstResponder)
                XCTAssertTrue(undo.canUndo)
                XCTAssertEqual(view.caretRect(for: position).minY - view.contentOffset.y, 100, accuracy: 2)
                let foreground = try XCTUnwrap(
                    view.textStorage.attribute(.foregroundColor, at: selection.location, effectiveRange: nil)
                        as? UIColor)
                XCTAssertEqual(
                    foreground.resolvedColor(with: view.traitCollection),
                    UIColor.label.resolvedColor(with: view.traitCollection))
                capture(host, name: "Appearance changes while writing: \(appearance.rawValue)")
            }
            undo.undo()
            XCTAssertEqual(state.document, original)
            undo.redo()
            XCTAssertEqual(state.document, edited)
        }

        private func makeWindow(_ host: UIViewController, appearance: UIUserInterfaceStyle) -> UIWindow {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            window.windowLevel = .alert + 1
            window.overrideUserInterfaceStyle = appearance
            host.overrideUserInterfaceStyle = appearance
            window.rootViewController = host
            window.makeKeyAndVisible()
            return window
        }

        private func editor(in host: UIViewController) async throws -> JournalTextView {
            for _ in 0..<100 {
                host.view.layoutIfNeeded()
                if let view = findEditor(in: host.view), !view.text.isEmpty { return view }
                try await Task.sleep(for: .milliseconds(10))
            }
            return try XCTUnwrap(findEditor(in: host.view))
        }

        private func findEditor(in view: UIView) -> JournalTextView? {
            if let editor = view as? JournalTextView { return editor }
            return view.subviews.lazy.compactMap { self.findEditor(in: $0) }.first
        }

        private func waitForImage(_ label: String, in view: JournalTextView) async throws {
            for _ in 0..<100 {
                let attachment =
                    view.textStorage.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
                if attachment?.accessibilityLabel == label { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            let attachment = try XCTUnwrap(
                view.textStorage.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
            XCTAssertEqual(attachment.accessibilityLabel, label)
        }

        private func imageBytes() -> Data {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 300, height: 600), format: format).pngData { context in
                UIColor.systemBlue.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 300, height: 600))
            }
        }

        private func capture(_ host: UIViewController, name: String) {
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = name + " (hosted native editor)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    private final class ImageViewportState: ObservableObject {
        let imageID = UUID()
        let entryID = UUID()
        @Published var document: JournalDocument
        @Published var images: [UUID: Data] = [:]
        @Published var loading: Set<UUID>
        @Published var headerText = "Daily notes"
        init(longDocument: Bool = false) {
            loading = [imageID]
            document = .init(
                blocks: [
                    DocumentBlock(
                        kind: "image", attachmentID: imageID, imageDescription: "A sketch", mediaType: "image/png")
                ]
                    + (0..<(longDocument ? 60 : 2)).map { index in
                        DocumentBlock(runs: [TextRun("Paragraph \(index). Keep writing while images load.")])
                    })
        }
    }

    private struct ImageViewportHarness: View {
        @ObservedObject var state: ImageViewportState
        let size: CGFloat
        @StateObject private var actions = EditorActions()
        var body: some View {
            NativeEditor(
                document: $state.document, itemID: state.entryID, images: state.images,
                loadingImages: state.loading, fontSize: size, editable: true, actions: actions,
                header: state.headerText.isEmpty
                    ? nil : AnyView(Text(state.headerText).font(.title.bold()).padding(.vertical, 28))
            ) { _ in nil }
            .padding(20)
            .background(Color(uiColor: .systemBackground))
        }
    }
#endif
