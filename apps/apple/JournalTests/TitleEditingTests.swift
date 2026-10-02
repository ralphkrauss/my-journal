#if os(iOS)
    import SwiftUI
    import UIKit
    import XCTest

    @testable import Journal

    @MainActor
    final class TitleEditingTests: XCTestCase {
        func testNativePastePreservesLineBreaksWithoutSubmitting() async throws {
            let state = TitleState()
            let host = UIHostingController(rootView: TitleHarness(state: state))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = host
            window.makeKeyAndVisible()
            let previousPasteboard = UIPasteboard.general.items
            defer {
                UIPasteboard.general.items = previousPasteboard
                window.isHidden = true
            }
            await Task.yield()
            host.view.layoutIfNeeded()
            let title = try XCTUnwrap(findTitle(in: host.view))
            XCTAssertTrue(title.becomeFirstResponder())
            for (pasted, selection) in [
                ("First\nSecond", NSRange(location: 8, length: 0)),
                ("\n", NSRange(location: 8, length: 0)),
                ("Replacement\n", NSRange(location: 1, length: 4)),
            ] {
                title.selectedRange = selection
                let original = state.text
                let expected = (original as NSString).replacingCharacters(in: selection, with: pasted)
                UIPasteboard.general.string = pasted
                title.paste(nil)
                for _ in 0..<100 {
                    if state.text == expected { break }
                    try await Task.sleep(for: .milliseconds(10))
                }
                XCTAssertEqual(title.text, expected)
                XCTAssertEqual(state.text, expected)
                XCTAssertEqual(state.submissions, 0)
                let undo = try XCTUnwrap(title.undoManager)
                XCTAssertTrue(undo.canUndo)
                undo.undo()
                XCTAssertEqual(title.text, original)
                XCTAssertEqual(state.text, original)
            }
        }

        private func findTitle(in view: UIView) -> TitleTextView? {
            if let title = view as? TitleTextView { return title }
            return view.subviews.lazy.compactMap { self.findTitle(in: $0) }.first
        }
    }

    @MainActor
    private final class TitleState: ObservableObject {
        @Published var text = "Original"
        var submissions = 0
        let actions = EditorActions()
    }

    private struct TitleHarness: View {
        @ObservedObject var state: TitleState
        var body: some View {
            // The app always provides the shared editor actions; the title reports editing through them.
            EntryTitleEditor(text: $state.text) { state.submissions += 1 }
                .frame(width: 360, height: 200)
                .environmentObject(state.actions)
        }
    }
#endif
#if os(macOS)
    import AppKit
    import SwiftUI
    import XCTest

    @testable import Journal

    @MainActor
    final class MacTitleSizingTests: XCTestCase {
        /// A long or pasted multiline title is shown in full, wrapped at the column's width, not cut to one line.
        func testTitleGrowsToShowEveryLineAtTheAvailableWidth() throws {
            let long = "A long first line that certainly needs more than one line at this width\nSecond line"
            let single = height(of: "Short", width: 300)
            let multiline = height(of: long, width: 300)
            XCTAssertGreaterThan(single, 0)
            XCTAssertGreaterThanOrEqual(multiline, single * 2.8, "Three lines: two wrapped and one pasted")
            XCTAssertLessThan(height(of: long, width: 900), multiline, "A wider window needs fewer lines")
            XCTAssertEqual(height(of: "", width: 300), single, "The placeholder keeps one line")
        }

        private func height(of title: String, width: CGFloat) -> CGFloat {
            let host = NSHostingView(
                rootView: EntryTitleEditor(text: .constant(title)) {}.frame(width: width).fixedSize(
                    horizontal: false, vertical: true))
            host.frame = CGRect(x: 0, y: 0, width: width, height: 1000)
            host.layoutSubtreeIfNeeded()
            return host.fittingSize.height
        }
    }
#endif
