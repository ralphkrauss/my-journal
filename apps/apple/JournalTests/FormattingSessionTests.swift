import Combine
import JournalCore
import XCTest

@testable import Journal

/// While the formatting popover or panel is shown, its commands act on the selection as it is now, and styling
/// doesn't redraw the window.
@MainActor final class FormattingSessionTests: XCTestCase {
    private func runs(_ harness: EditorHarness) -> [TextRun] { harness.document.blocks.flatMap(\.runs) }

    func testCommandsFollowTheSelectionAndSurviveWriting() {
        let harness = EditorHarness(markdown: "First word and second word")
        defer { harness.close() }
        harness.select("First")
        harness.actions.beginFormattingPresentation()
        harness.select("second")
        harness.actions.performFormatting(.bold)
        XCTAssertTrue(runs(harness).contains { $0.text == "second" && $0.bold }, harness.document.markdown)
        XCTAssertFalse(runs(harness).contains { $0.text.contains("First") && $0.bold }, harness.document.markdown)
        XCTAssertEqual(harness.actions.formattingState.bold, .on)
        // Writing while it's shown doesn't end it: the next command still applies.
        harness.caret(at: (harness.text.string as NSString).length)
        harness.type(" more")
        harness.select("more")
        harness.actions.performFormatting(.italic)
        XCTAssertTrue(runs(harness).contains { $0.text == "more" && $0.italic }, harness.document.markdown)
        harness.actions.finishPresentation(refocus: false)
    }

    /// Image… in the panel has no source of its own: it must not reopen the camera chosen the time before.
    func testImageInTheFormatPanelAsksForThePhotoLibraryAfterTheCamera() {
        let harness = EditorHarness(markdown: "Words")
        defer { harness.close() }
        harness.actions.insertImage(from: .camera)
        XCTAssertEqual(harness.actions.imageSource, .camera)
        harness.actions.requestImage = false

        harness.actions.performFormatting(.imagePicker)
        XCTAssertEqual(harness.actions.imageSource, .photos)
        XCTAssertTrue(harness.actions.requestImage)

        harness.actions.insertImage(from: .files)
        harness.actions.requestImage = false
        harness.actions.beginFormattingPresentation()
        harness.actions.pendingPresentation = .image
        harness.actions.finishPresentation(refocus: false)
        XCTAssertEqual(harness.actions.imageSource, .photos)
        XCTAssertTrue(harness.actions.requestImage)
    }

    func testTheShownStateFollowsTheSelection() {
        let harness = EditorHarness(markdown: "Plain and **strong** words")
        defer { harness.close() }
        harness.select("Plain")
        harness.actions.beginFormattingPresentation()
        XCTAssertEqual(harness.actions.formattingState.bold, .off)
        harness.select("strong")
        let refreshed = expectation(description: "The state refreshes once the selection has changed.")
        DispatchQueue.main.async { refreshed.fulfill() }
        wait(for: [refreshed], timeout: 1)
        XCTAssertEqual(harness.actions.formattingState.bold, .on)
        harness.actions.finishPresentation(refocus: false)
    }

    func testOpeningStylingAndClosingDoNotRedrawTheWindow() {
        let harness = EditorHarness(markdown: "Plain words")
        defer { harness.close() }
        harness.select("words")
        var changes = 0
        let watch = harness.actions.objectWillChange.sink { _ in changes += 1 }
        defer { watch.cancel() }
        harness.actions.beginFormattingPresentation()
        harness.actions.performFormatting(.bold)
        harness.select("Plain")
        harness.actions.performFormatting(.italic)
        harness.actions.finishPresentation(refocus: false)
        XCTAssertEqual(changes, 0, "Everything observing the editor's actions, such as the window, redraws.")
        XCTAssertTrue(runs(harness).contains { $0.text == "words" && $0.bold })
        XCTAssertTrue(runs(harness).contains { $0.text == "Plain" && $0.italic })
    }
}
