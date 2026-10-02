import JournalCore
import SwiftUI
import XCTest

@testable import Journal

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// The title's first letter starts exactly where the body's does: with text and with the placeholders ("Title",
/// "Start writing…"), at the usual and the largest text size (docs/design/quiet-sync-and-title-alignment.md).
@MainActor
final class TitleAlignmentTests: XCTestCase {
    #if os(macOS)
        func testTitleAndBodyStartAtTheSameEdge() async throws {
            for (title, body) in [("Title", "Body"), ("", "")] {
                for size in [AppModel.defaultTextSize, 30] {
                    let window = try await EntryWindow(title: title, body: body, textSize: size)
                    let context = "title “\(title)”, body “\(body)”, size \(size)"
                    do {
                        let bodyX = try XCTUnwrap(window.bodyTextX(), context)
                        XCTAssertEqual(try window.titleTextX(), bodyX, accuracy: 0.5, context)
                        if !body.isEmpty {
                            window.actions.toggleSourceMode()
                            try await window.settle()
                            let source = try XCTUnwrap(window.bodyTextX())
                            XCTAssertEqual(source, bodyX, accuracy: 0.5, "View Source, \(context)")
                        }
                    } catch {
                        await window.close()
                        throw error
                    }
                    await window.close()
                }
            }
        }
    #else
        func testTitleAndBodyStartAtTheSameEdge() async throws {
            for (title, body) in [("Title", "Body"), ("", "")] {
                for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
                    let window = try await EntryWindow(title: title, body: body, category: category)
                    let context = "title “\(title)”, body “\(body)”, \(category.rawValue)"
                    let measured = Result { (title: try window.titleTextX(), body: try window.bodyTextX()) }
                    await window.close()
                    let start = try measured.get()
                    XCTAssertEqual(start.title, start.body, accuracy: 0.5, context)
                }
            }
        }
    #endif
}

/// An open entry with the real title and body, as the journal window shows it.
@MainActor
private final class EntryWindow {
    let model: AppModel
    let actions = EditorActions()
    private let root: URL
    #if os(macOS)
        let window: NSWindow
        private let host: NSView
    #else
        let window: UIWindow
        private let host: UIViewController
    #endif

    #if os(macOS)
        init(title: String, body: String, textSize: Double) async throws {
            (root, model) = try await Self.library(title: title, body: body)
            model.textSize = textSize
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720), styleMask: [.titled, .resizable],
                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            host = NSHostingView(rootView: RootView().environmentObject(model).environmentObject(actions))
            window.contentView = host
            window.orderFront(nil)
            try await settle()
        }
    #else
        init(title: String, body: String, category: UIContentSizeCategory) async throws {
            (root, model) = try await Self.library(title: title, body: body)
            let item = try XCTUnwrap(model.draft)
            let size = UIFont.preferredFont(
                forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: category)
            ).pointSize
            let editor = NativeEditor(
                document: .constant(item.document), itemID: item.id, images: [:], fontSize: size, editable: true,
                actions: actions, header: AnyView(EntryHeaderView(item: item, title: .constant(item.title))),
                imageHandler: { _ in nil })
            let controller = UIHostingController(
                rootView: editor.padding(.horizontal, RootView.editorMargin).environmentObject(model)
                    .environmentObject(actions))
            if #available(iOS 17.0, *) { controller.traitOverrides.preferredContentSizeCategory = category }
            host = controller
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            try await settle()
        }
    #endif

    private static func library(title: String, body: String) async throws -> (URL, AppModel) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try JournalStore(directory: root, key: try VaultCrypto.generateKey())
        let journal = JournalItem(kind: "journal", title: "Personal")
        var entry = JournalItem(kind: "entry", journalID: journal.id, title: title)
        if !body.isEmpty { entry.document = JournalDocument(blocks: [DocumentBlock(runs: [TextRun(body)])]) }
        for item in [journal, entry] { try await store.save(item) }
        let model = AppModel(directory: root)
        model.store = store
        model.loaded = true
        model.items = [journal, entry]
        model.selectedJournalID = journal.id
        model.selectedID = entry.id
        model.draft = entry
        return (root, model)
    }

    func close() async {
        #if os(macOS)
            window.close()
        #else
            window.isHidden = true
        #endif
        try? await model.store?.close()
        try? FileManager.default.removeItem(at: root)
    }

    func settle() async throws {
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 50_000_000)
            #if os(macOS)
                host.layoutSubtreeIfNeeded()
            #else
                host.view.layoutIfNeeded()
            #endif
        }
    }

    #if os(macOS)
        /// Where the title's text starts: its insertion point at the start, while editing it.
        func titleTextX() throws -> CGFloat {
            let title = try XCTUnwrap(Self.find(TitleTextField.self, in: host))
            XCTAssertTrue(window.makeFirstResponder(title))
            let editor = try XCTUnwrap(title.currentEditor() as? NSTextView)
            let start = editor.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)
            return window.convertFromScreen(start).minX
        }

        /// Where the body's first letter starts, or the placeholder's while the body is empty.
        func bodyTextX() -> CGFloat? {
            guard let text = Self.find(JournalTextView.self, in: host) else { return nil }
            if text.string.isEmpty {
                guard let placeholder = Self.find(PlaceholderTextView.self, in: text), !placeholder.isHidden,
                    let glyph = placeholder.rect(of: NSRange(location: 0, length: 1))
                else { return nil }
                return placeholder.convert(glyph, to: nil).minX
            }
            let glyph = text.firstRect(forCharacterRange: NSRange(location: 0, length: 1), actualRange: nil)
            return window.convertFromScreen(glyph).minX
        }

        private static func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
            if let match = view as? T { return match }
            return view.subviews.lazy.compactMap { find(type, in: $0) }.first
        }
    #else
        /// Where the title's text starts, or its placeholder's.
        func titleTextX() throws -> CGFloat {
            let title = try XCTUnwrap(Self.find(TitleTextView.self, in: host.view))
            if title.text.isEmpty {
                let placeholder = try XCTUnwrap(Self.find(UILabel.self, in: title))
                XCTAssertEqual(placeholder.text, "Title")
                let glyphs = placeholder.textRect(forBounds: placeholder.bounds, limitedToNumberOfLines: 1)
                return placeholder.convert(glyphs, to: nil).minX
            }
            return try Self.firstLetter(in: title)
        }

        /// Where the body's first letter starts, or the placeholder's while the body is empty.
        func bodyTextX() throws -> CGFloat {
            let text = try XCTUnwrap(Self.find(JournalTextView.self, in: host.view))
            if text.text.isEmpty {
                let placeholder = try XCTUnwrap(Self.find(PlaceholderTextView.self, in: text))
                XCTAssertFalse(placeholder.isHidden)
                let glyph = placeholder.rect(of: NSRange(location: 0, length: 1))
                    .offsetBy(dx: placeholder.textContainerInset.left, dy: placeholder.textContainerInset.top)
                return placeholder.convert(glyph, to: nil).minX
            }
            return try Self.firstLetter(in: text)
        }

        private static func firstLetter(in view: UITextView) throws -> CGFloat {
            let start = view.beginningOfDocument
            let end = try XCTUnwrap(view.position(from: start, offset: 1))
            let range = try XCTUnwrap(view.textRange(from: start, to: end))
            return view.convert(view.firstRect(for: range), to: nil).minX
        }

        private static func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
            if let match = view as? T { return match }
            return view.subviews.lazy.compactMap { find(type, in: $0) }.first
        }
    #endif
}
