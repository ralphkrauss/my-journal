import JournalCore
import XCTest

@testable import Journal

/// The system's own text never reaches the person: a damaged database, a failing disk, a network error, a Keychain
/// failure and an unknown error each give one plain message, and a leaked SQL string is the plausible failure
/// (docs/design/build-18-fixes-2026-10-06.md §1.14). Which database results are damaged, and which are busy, is
/// tested where the classification lives, in JournalCore.
@MainActor
final class FailureMessageTests: XCTestCase {
    private struct Unknown: Error, CustomStringConvertible {
        var description: String { "SELECT payload FROM records WHERE title = 'My secret diary'" }
    }

    /// The error a damaged library gives on its first read, as the store throws it.
    private func damagedDatabaseError() async throws -> Error {
        let fixture = try await LibraryFixture.make(self)
        try fixture.damageRecords()
        let store = try JournalStore(directory: fixture.libraryURL, key: fixture.key)
        defer { Task { try? await store.close() } }
        do {
            _ = try await store.viewSnapshot()
        } catch {
            return error
        }
        throw XCTSkip("The records page was not read.")
    }

    func testEachFailureGivesItsOwnPlainMessageWithoutTheOriginalText() async throws {
        let damaged = try await damagedDatabaseError()
        let cases: [(Error, FailureMessage.Operation, String)] = [
            (damaged, .reading, FailureMessage.damagedReading),
            (damaged, .saving, FailureMessage.damagedSaving),
            (JournalError.invalidData, .reading, FailureMessage.damagedReading),
            (CocoaError(.fileReadNoPermission), .reading, FailureMessage.temporaryReading),
            (CocoaError(.fileWriteNoPermission), .saving, FailureMessage.temporarySaving),
            (CocoaError(.fileWriteOutOfSpace), .saving, FailureMessage.full),
            (POSIXError(.ENOSPC), .saving, FailureMessage.full),
            (URLError(.notConnectedToInternet), .saving, "You’re offline. Check your connection."),
            (URLError(.timedOut), .reading, "Couldn’t reach the server. Check your connection."),
            (
                URLError(.serverCertificateUntrusted), .saving,
                "Can’t connect securely to the server because its certificate isn’t valid."
            ),
            (NSError(domain: NSOSStatusErrorDomain, code: -25308), .reading, FailureMessage.keychain),
            (SecretStoreError.unavailable, .saving, FailureMessage.keychain),
            (Unknown(), .saving, FailureMessage.anythingElse),
        ]
        for (error, operation, expected) in cases {
            let message = error.shown(operation)
            XCTAssertEqual(message, expected, "\(error)")
            for leak in ["SELECT", "secret diary", "malformed", "OSStatus", "SQLite", "NSCocoaErrorDomain"] {
                XCTAssertFalse(message.contains(leak), "“\(message)” shows \(leak)")
            }
        }
    }

    /// The app's own errors are already plain and keep their text, also when a merge stopped part way wraps them.
    func testTheAppsOwnErrorsKeepTheirText() {
        XCTAssertEqual(JournalError.locked.shown(.saving), "Unlock My Journal to continue.")
        let saveFirst = "Save your changes before connecting."
        XCTAssertEqual(JournalError.server(saveFirst).shown(.saving), saveFirst)
        XCTAssertEqual(JournalLifecycleError.changed.shown(.saving), JournalLifecycleError.changed.errorDescription)
        XCTAssertEqual(
            JournalError.newerVersion.shown(.reading),
            "These journals were saved by a newer version of My Journal. Update My Journal to open them.")
        let interrupted = MergeInterrupted(underlying: CocoaError(.fileWriteNoPermission), sent: false)
        XCTAssertEqual(interrupted.shown(.saving), FailureMessage.temporarySaving)
        XCTAssertEqual(interrupted.errorDescription, FailureMessage.temporarySaving)
    }
}
