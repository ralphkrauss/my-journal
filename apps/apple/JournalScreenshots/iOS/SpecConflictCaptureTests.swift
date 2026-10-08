import XCTest

/// Spec screenshots of changes to review. The conflicts are recorded in a copy of the sample library with the store's
/// own calls, as the checks in JournalUITests do, so the app finds them when it opens the library.
final class SpecConflictCaptureTests: SpecCaptureCase {
    @MainActor func testEntryConflict() async throws {
        let library = try copyOfSampleLibrary()
        try await SpecLibraryFixtures.recordConflicts(in: library, password: try password())
        let app = try launch(library: library)
        let review = app.buttons["Review Changes"].firstMatch
        try require(review, app: app, timeout: 20)
        try shot(app, "conflict-review-notice")
        review.tap()
        let versions = app.descendants(matching: .any).matching(identifier: "conflict-version").firstMatch
        try require(versions, app: app, timeout: 10)
        try shot(app, "entry-conflict-default")
        let other = app.buttons["Other Device"].firstMatch
        if other.exists { other.tap() }
        try shot(app, "entry-conflict-other-device")
        let keepOne = app.buttons["Keep One Version"]
        for _ in 0..<5 where !keepOne.isHittable { app.swipeUp() }
        try shot(app, "resolve-conflict-default")
        keepOne.tap()
        try require(app.buttons["Keep Version from Other Device…"], app: app, timeout: 5)
        try shot(app, "resolve-conflict-keep-one")
    }

    @MainActor func testListSignalAndUnsupported() async throws {
        let library = try copyOfSampleLibrary()
        try await SpecLibraryFixtures.recordConflicts(in: library, password: try password())
        let app = try launch(library: library)
        try require(app.buttons["Review Changes"].firstMatch, app: app, timeout: 20)
        NavigationTestSupport.selectCollection("Personal", app: app)
        try require(app.staticTexts["Gratitude"], app: app, timeout: 10)
        try shot(app, "conflict-review-default")
        try openEntry("Gratitude", journal: "Personal", app: app)
        let review = app.buttons["Review Changes"].firstMatch
        try require(review, app: app, timeout: 10)
        review.tap()
        try require(app.staticTexts["Update My Journal to review these changes."], app: app, timeout: 10)
        try shot(app, "entry-conflict-unsupported")
    }
}
