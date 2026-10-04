import JournalCore
import SwiftUI
import XCTest

@testable import Journal

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Checkboxes scroll with their text. Build 14's Mac editor placed them only when the text view laid itself out,
/// which scrolling doesn't do, so items scrolled into view showed no checkbox, or showed it late.
@MainActor
final class ChecklistScrollingTests: XCTestCase {
    func testEveryCheckboxInViewIsInPlaceAtEachScrollPosition() throws {
        let editor = try ScrollingEditor(
            markdown: (1...120).map { "- [\($0 % 3 == 0 ? "x" : " ")] Item \($0)" }.joined(separator: "\n"))
        defer { editor.close() }
        let step: CGFloat = 37
        var offset: CGFloat = 0
        var checked = 0
        while offset <= editor.maximumOffset {
            editor.scroll(to: offset)
            // No layout pass or turn of the run loop in between: the screen shows this position next.
            let shown = editor.checkboxes()
            for item in try editor.itemsInView() {
                let box = try XCTUnwrap(shown[item.location], "Item at \(item.location) has a checkbox at \(offset)")
                XCTAssertEqual(box.minX, item.placement.boxX, accuracy: 0.5, "x at \(offset)")
                XCTAssertEqual(box.midY, item.placement.capCenter, accuracy: 2, "y at \(offset)")
                checked += 1
            }
            offset += step
        }
        XCTAssertGreaterThan(checked, 200, "The test scrolled through the checklist.")
    }

    #if os(macOS)
        /// Each checkbox is labelled with its item's words and shows its state, and a click on one toggles its item
        /// while the caret stays in the text, also with Keyboard Navigation on.
        func testCheckboxesAreLabelledAndAClickLeavesTheCaretInTheText() throws {
            let editor = try ScrollingEditor(markdown: "Errands\n\n- [ ] Buy milk\n- [x] Post the letter")
            defer { editor.close() }
            let window = editor.window
            window.orderFront(nil)
            XCTAssertTrue(window.makeFirstResponder(editor.view))
            editor.view.setSelectedRange(NSRange(location: 3, length: 0))
            let buttons = editor.view.subviews.compactMap { $0 as? NSButton }.sorted { $0.frame.minY < $1.frame.minY }
            XCTAssertEqual(buttons.map { $0.accessibilityLabel() ?? "" }, ["Buy milk", "Post the letter"])
            XCTAssertEqual(buttons.map(\.state), [.off, .on])
            let button = try XCTUnwrap(buttons.first)
            XCTAssertFalse(button.acceptsFirstResponder, "The checkbox never takes the focus from the text.")
            let point = button.convert(CGPoint(x: 4, y: button.bounds.midY), to: nil)
            for type in [NSEvent.EventType.leftMouseUp, .leftMouseDown] {
                let event = try XCTUnwrap(
                    NSEvent.mouseEvent(
                        with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                // The button's click tracking reads the release from the queue.
                if type == .leftMouseUp { window.postEvent(event, atStart: false) } else { window.sendEvent(event) }
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            XCTAssertTrue(window.firstResponder === editor.view, "The caret stays in the text.")
            XCTAssertEqual(editor.view.selectedRange(), NSRange(location: 3, length: 0))
            let storage = try XCTUnwrap(editor.view.textStorage)
            let item = (storage.string as NSString).range(of: "Buy milk").location
            XCTAssertEqual(storage.attribute(.journalKind, at: item, effectiveRange: nil) as? String, "checked")
        }
    #endif
}

/// The body editor in a scroll view in a window, as the app shows it.
@MainActor private final class ScrollingEditor {
    private final class State {
        var document: JournalDocument
        init(_ document: JournalDocument) { self.document = document }
    }
    private let state: State
    let view: JournalTextView
    let coordinator: NativeEditor.Coordinator
    #if os(macOS)
        let window: NSWindow
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 402, height: 400))
    #else
        let window: UIWindow
    #endif

    init(markdown: String) throws {
        let state = State(JournalDocument(markdown: markdown))
        self.state = state
        let editor = NativeEditor(
            document: Binding(get: { state.document }, set: { state.document = $0 }), itemID: UUID(), images: [:],
            fontSize: 17, editable: true, actions: EditorActions(), imageHandler: { _ in nil })
        coordinator = editor.makeCoordinator()
        #if os(macOS)
            // As NativeEditor.makeNSView makes it.
            view = JournalTextView(frame: scroll.bounds)
            view.isRichText = true
            view.drawsBackground = false
            view.textContainerInset = NSSize(width: EntryTextInset.body, height: 8)
            view.textContainer?.lineFragmentPadding = EntryTextInset.linePadding
            view.isVerticallyResizable = true
            view.isHorizontallyResizable = false
            view.autoresizingMask = [.width]
            view.textContainer?.widthTracksTextView = true
            view.textContainer?.containerSize = NSSize(width: 402, height: CGFloat.greatestFiniteMagnitude)
            scroll.hasVerticalScroller = true
            scroll.documentView = view
            window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = scroll
        #else
            view = JournalTextView(frame: CGRect(x: 0, y: 0, width: 402, height: 400))
            window = UIWindow(frame: view.frame)
            let controller = UIViewController()
            controller.view = view
            window.rootViewController = controller
            window.makeKeyAndVisible()
        #endif
        coordinator.view = view
        view.delegate = coordinator
        coordinator.update(editor)
        #if os(macOS)
            window.layoutIfNeeded()
            view.layoutManager?.ensureLayout(for: try XCTUnwrap(view.textContainer))
            view.sizeToFit()
        #else
            view.layoutIfNeeded()
        #endif
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }

    var maximumOffset: CGFloat {
        #if os(macOS)
            view.frame.height - scroll.contentView.bounds.height
        #else
            view.contentSize.height - view.bounds.height
        #endif
    }

    /// Scrolls as a person does: on the Mac the clip view moves, on iPhone the content offset changes and UIKit lays
    /// the text view out before the frame is drawn.
    func scroll(to offset: CGFloat) {
        #if os(macOS)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scroll.reflectScrolledClipView(scroll.contentView)
        #else
            view.contentOffset = CGPoint(x: 0, y: offset)
            view.layoutIfNeeded()
        #endif
    }

    /// The checkboxes shown, by the paragraph they belong to, in the text view's coordinates.
    func checkboxes() -> [Int: CGRect] {
        var result: [Int: CGRect] = [:]
        for subview in view.subviews where !subview.isHidden {
            #if os(macOS)
                if let button = subview as? NSButton { result[button.tag] = button.frame }
            #else
                if let button = subview as? ChecklistBox {
                    result[button.tag] = button.box.convert(button.box.bounds, to: view)
                }
            #endif
        }
        return result
    }

    /// The checklist items whose first line is in view.
    func itemsInView() throws -> [InlineTasks.Item] {
        #if os(macOS)
            let visible = view.visibleRect
            let storage = try XCTUnwrap(view.textStorage)
            let layout = try XCTUnwrap(view.layoutManager)
            let container = try XCTUnwrap(view.textContainer)
            let origin = view.textContainerOrigin
        #else
            let visible = view.bounds
            let storage = view.textStorage
            let layout = view.layoutManager
            let container = view.textContainer
            let origin = CGPoint(x: view.textContainerInset.left, y: view.textContainerInset.top)
        #endif
        return InlineTasks.items(in: visible, storage: storage, layout: layout, container: container, origin: origin)
    }

    func close() {
        #if os(macOS)
            window.orderOut(nil)
        #else
            window.isHidden = true
        #endif
    }
}
