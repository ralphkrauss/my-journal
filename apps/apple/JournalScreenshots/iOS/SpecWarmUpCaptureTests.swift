import XCTest

/// Runs first: a new simulator's keyboard shows one-time tips over its keys the first time it is used, which would
/// cover a capture. Typing once in the search field and closing them leaves the later captures clear.
final class SpecWarmUpCaptureTests: SpecCaptureCase {
    @MainActor func testKeyboardTips() throws {
        let app = try launch()
        NavigationTestSupport.selectCollection("Personal", app: app)
        let search = app.searchFields["Search Personal"]
        try require(search, app: app, timeout: 10)
        search.tap()
        search.typeText("w")
        NavigationTestSupport.dismissKeyboardTips(app)
    }
}
