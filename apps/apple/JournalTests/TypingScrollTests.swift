#if os(iOS)
    import JournalCore
    import SwiftUI
    import UIKit
    import XCTest

    @testable import Journal

    /// Typing at the bottom of an entry scrolls it the way the text view does in Notes: forward, a line at a time, with
    /// the system's animation. Build 9 also revealed the caret itself after every keystroke, without animation, so
    /// each Return's scrolling was cut short by a jump (docs/design/typing-scroll.md).
    @MainActor
    final class TypingScrollTests: XCTestCase {
        func testTypingAtTheBottomScrollsForwardWithoutJumps() async throws {
            let state = TypingState()
            let host = UIHostingController(rootView: TypingHarness(state: state))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 480))
            window.windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            window.windowLevel = .alert + 1
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            let view = try await editor(in: host)
            XCTAssertTrue(view.becomeFirstResponder())
            view.selectedRange = NSRange(location: view.textStorage.length, length: 0)
            // The keyboard or its controls arrive and the entry gets its room.
            try await settle(0.6)
            let coordinator = try XCTUnwrap(view.delegate as? NativeEditor.Coordinator)
            let inset = view.contentInset.bottom
            let start = view.contentOffset.y
            let caretBefore = caretFrame(view).minY
            type("\nLine 1", in: view, coordinator: coordinator)
            try await settle(0.4)
            let line = caretFrame(view).minY - caretBefore
            XCTAssertGreaterThan(line, 10, "Return started a new line.")

            let offsets = OffsetRecorder()
            let observation = view.observe(\.contentOffset, options: [.new]) { _, change in
                guard let offset = change.newValue else { return }
                MainActor.assumeIsolated { offsets.values.append(offset.y) }
            }
            offsets.values = [view.contentOffset.y]
            for index in 2...14 {
                type("\nLine \(index)", in: view, coordinator: coordinator)
                // The text view's own scrolling takes about a third of a second.
                try await settle(0.4)
            }
            observation.invalidate()

            let values = offsets.values
            XCTAssertGreaterThan(view.contentOffset.y - start, 3 * line, "Typing reached the bottom and scrolled.")
            for (previous, next) in zip(values, values.dropFirst()) {
                XCTAssertGreaterThanOrEqual(next, previous - 0.5, "The entry scrolled back: \(values)")
                XCTAssertLessThan(next - previous, 0.6 * line, "The entry jumped instead of scrolling: \(values)")
            }
            XCTAssertEqual(view.contentInset.bottom, inset, accuracy: 0.5, "Typing doesn't add room below the text.")
            let visibleBottom = view.contentOffset.y + view.bounds.height - view.adjustedContentInset.bottom
            XCTAssertLessThanOrEqual(caretFrame(view).maxY, visibleBottom + 0.5, "The line being typed is in view.")
        }

        /// Types as the keyboard does, including the delegate's chance to handle each character.
        private func type(_ text: String, in view: JournalTextView, coordinator: NativeEditor.Coordinator) {
            for character in text {
                let string = String(character)
                if coordinator.textView(view, shouldChangeTextIn: view.selectedRange, replacementText: string) {
                    view.insertText(string)
                }
            }
        }

        private func caretFrame(_ view: JournalTextView) -> CGRect {
            view.caretRect(for: view.endOfDocument)
        }

        private func settle(_ seconds: Double) async throws {
            try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
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
    }

    @MainActor private final class OffsetRecorder {
        var values: [CGFloat] = []
    }

    private final class TypingState: ObservableObject {
        let entryID = UUID()
        @Published var document = JournalDocument(
            blocks: (1...6).map { DocumentBlock(runs: [TextRun("Paragraph \($0) of the day so far.")]) })
    }

    private struct TypingHarness: View {
        @ObservedObject var state: TypingState
        @StateObject private var actions = EditorActions()
        var body: some View {
            NativeEditor(
                document: $state.document, itemID: state.entryID, images: [:], fontSize: 17, editable: true,
                actions: actions, header: AnyView(Text("Today").font(.title.bold()).padding(.vertical, 28))
            ) { _ in nil }
            .background(Color(uiColor: .systemBackground))
        }
    }
#endif
