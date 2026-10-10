import JournalCore
import XCTest

@testable import Journal

/// Libraries for tests. Version 1.1 makes and opens only encrypted libraries, so every test library is one.
@MainActor
extension AppModel {
    static let testPassword = "a test master password"

    /// A new encrypted library with a password of this test's own.
    func start() async { await start(password: Self.testPassword) }
}
