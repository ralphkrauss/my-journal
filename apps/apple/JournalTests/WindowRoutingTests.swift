import XCTest

@testable import Journal

final class WindowRoutingTests: XCTestCase {
    /// Loading, locked, a library problem, the first-launch screen, the recovery key, the journals.
    func testTheWindowRoutesByPrecedence() {
        var routing = WindowRouting()
        XCTAssertEqual(routing.screen, .opening)
        routing.loaded = true
        routing.hasLibrary = true
        routing.recoveryKey = true
        XCTAssertEqual(routing.screen, .recoveryKey)
        routing.recoveryKey = false
        XCTAssertEqual(routing.screen, .journals)
        routing.hasLibrary = false
        XCTAssertEqual(routing.screen, .welcome)
        routing.libraryProblem = true
        XCTAssertEqual(routing.screen, .libraryProblem)
        routing.locked = true
        XCTAssertEqual(routing.screen, .locked)
    }
}
