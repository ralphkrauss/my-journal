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

extension RecoveryEnvelope {
    /// What version 1.0 saved for a library made with Continue Without Encryption (recovery format 4). This version
    /// never opens, makes or syncs such a library; tests use it to show that.
    static var unprotected: RecoveryEnvelope {
        RecoveryEnvelope(salt: "", wrappedKey: "", iterations: 0, formatVersion: 4)
    }

    /// A master-password envelope for a configuration that is only read, never unlocked.
    static var placeholder: RecoveryEnvelope {
        RecoveryEnvelope(
            salt: Data(repeating: 1, count: 16).base64EncodedString(),
            wrappedKey: Data(repeating: 2, count: 60).base64EncodedString(), iterations: 600_000, formatVersion: 2)
    }
}
