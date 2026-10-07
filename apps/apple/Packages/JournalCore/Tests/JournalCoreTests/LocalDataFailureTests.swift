import GRDB
import XCTest

@testable import JournalCore

/// Only a damaged database says “can’t read”. A busy or locked database, a file that is unavailable while the device
/// is locked and a failing disk are temporary, and the data is fine (docs/design/build-18-fixes-2026-10-06.md §1.14).
final class LocalDataFailureTests: XCTestCase {
    func testOnlyMalformedDataIsDamagedAndNewerVersionsNeedAnUpdate() {
        let cases: [(Error, LocalDataFailure)] = [
            (DatabaseError(resultCode: .SQLITE_CORRUPT), .damaged),
            (DatabaseError(resultCode: .SQLITE_NOTADB), .damaged),
            (JournalError.invalidData, .damaged),
            (JournalError.newerVersion, .needsUpdate),
            (JournalError.unsupportedFormat, .needsUpdate),
            (DatabaseError(resultCode: .SQLITE_FULL), .full),
            (CocoaError(.fileWriteOutOfSpace), .full),
            (POSIXError(.ENOSPC), .full),
            (DatabaseError(resultCode: .SQLITE_BUSY), .temporary),
            (DatabaseError(resultCode: .SQLITE_LOCKED), .temporary),
            (DatabaseError(resultCode: .SQLITE_CANTOPEN), .temporary),
            (DatabaseError(resultCode: .SQLITE_IOERR), .temporary),
            (DatabaseError(resultCode: .SQLITE_PERM), .temporary),
            (DatabaseError(resultCode: .SQLITE_READONLY), .temporary),
            (DatabaseError(resultCode: .SQLITE_AUTH), .temporary),
            (CocoaError(.fileReadNoPermission), .temporary),
            (NSError(domain: NSOSStatusErrorDomain, code: -25308), .temporary),
            (URLError(.timedOut), .temporary),
        ]
        for (error, expected) in cases {
            XCTAssertEqual(LocalDataFailure(classifying: error), expected, "\(error)")
        }
    }

    /// The app words database and file-system failures alike, and never shows the app's own errors this way.
    func testDatabaseAndFileSystemFailuresAreLocalDataAndTheAppsOwnErrorsAreNot() {
        XCTAssertTrue(LocalDataFailure.isLocalData(DatabaseError(resultCode: .SQLITE_BUSY)))
        XCTAssertTrue(LocalDataFailure.isLocalData(CocoaError(.fileReadNoPermission)))
        XCTAssertTrue(LocalDataFailure.isLocalData(POSIXError(.EIO)))
        XCTAssertFalse(LocalDataFailure.isLocalData(JournalError.locked))
        XCTAssertFalse(LocalDataFailure.isLocalData(URLError(.timedOut)))
    }

    /// A busy database says nothing about damage, and the sync message makes no claim about saving: the failure is in
    /// the database that would vouch for it.
    func testASyncThatFindsTheDatabaseBusyIsTemporaryAndNeverClaimsDamageOrSaving() {
        for code in [ResultCode.SQLITE_BUSY, .SQLITE_CANTOPEN, .SQLITE_IOERR] {
            let health = SyncHealth(classifying: DatabaseError(resultCode: code))
            XCTAssertEqual(health, .localDataUnavailable, "\(code)")
            XCTAssertEqual(health.kind, .temporary)
            XCTAssertFalse(health.stopsAutomaticSync, "Sync keeps trying.")
            XCTAssertFalse(health.message().localizedCaseInsensitiveContains("saved"))
            XCTAssertFalse(health.message().localizedCaseInsensitiveContains("read"))
        }
        XCTAssertEqual(SyncHealth(classifying: DatabaseError(resultCode: .SQLITE_CORRUPT)), .localDataUnreadable)
    }
}
