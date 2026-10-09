import XCTest

/// Spec screenshots of the notice above an entry that was kept as two, and of the held line. The conflicts are recorded
/// in a copy of the sample library with the store's own calls, as the checks in JournalUITests do, and the app settles
/// them when it opens the library.
final class SpecConflictCaptureTests: SpecCaptureCase {
    @MainActor func testKeptBothNotice() async throws {
        let library = try copyOfSampleLibrary()
        try await SpecLibraryFixtures.recordConflicts(in: library, password: try password())
        let app = try launch(library: library)
        let show = app.buttons["Show Other Version"].firstMatch
        try require(show, app: app, timeout: 20)
        try shot(app, "entry-editor-kept-both-notice")
    }

    @MainActor func testHeldEntryNotice() async throws {
        let library = try copyOfSampleLibrary()
        try await SpecLibraryFixtures.recordConflicts(in: library, password: try password())
        let app = try launch(library: library)
        try require(app.buttons["Show Other Version"].firstMatch, app: app, timeout: 20)
        NavigationTestSupport.selectCollection("Personal", app: app)
        try require(app.staticTexts["Gratitude"], app: app, timeout: 10)
        try openEntry("Gratitude", journal: "Personal", app: app)
        try require(
            app.staticTexts["This entry has a version from a newer My Journal. Update My Journal to combine them."],
            app: app, timeout: 10)
        try shot(app, "entry-editor-held-notice")
    }
}
