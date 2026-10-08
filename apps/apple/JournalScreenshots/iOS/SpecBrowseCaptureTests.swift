import XCTest

/// Spec screenshots of browsing the sample library: the library window, journals, entry lists and the editor.
final class SpecBrowseCaptureTests: SpecCaptureCase {
    @MainActor func testBrowse() throws {
        let app = try launch()
        // The library opens where it was left: the editor on iPhone, all three columns on iPad.
        try require(NavigationTestSupport.title(app), app: app, timeout: 20)
        if isPad { showSidebar(app) }
        try shot(app, "library-window-default")
        try shot(app, "entry-editor-default")
        if !isPad {
            let back = app.navigationBars.buttons.matching(
                NSPredicate(format: "identifier == %@ OR label == %@", "BackButton", "Back")
            ).firstMatch
            back.tap()
            try shot(app, "entry-list-default")
        } else {
            try shot(app, "entry-list-default")
        }
        NavigationTestSupport.showJournals(app)
        try shot(app, "journals-default")
    }
}
