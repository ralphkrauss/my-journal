import Foundation
import GRDB

/// What a failure to open, read or write the journals on this device means, decided in one place for the open screen,
/// the messages of alerts and the sync states (docs/design/build-18-fixes-2026-10-06.md §1.14).
public enum LocalDataFailure: Equatable, Sendable {
    /// The database is malformed or isn't a database, or the store's own validation found its data inconsistent.
    /// Nothing else is damaged: a busy or locked database, a file that is unavailable while the device is locked and
    /// a failing disk are temporary or environmental, and the data is fine.
    case damaged
    /// The journals or the format were written by a newer version of My Journal.
    case needsUpdate
    /// The device has no space left.
    case full
    /// Everything else: every other database, Keychain or file-system failure, and anything unknown.
    case temporary

    public init(classifying error: Error) {
        switch error {
        case let database as DatabaseError:
            self = Self.classify(database)
        case JournalError.invalidData:
            self = .damaged
        case JournalError.newerVersion, JournalError.unsupportedFormat:
            self = .needsUpdate
        default:
            self = Self.isOutOfSpace(error) ? .full : .temporary
        }
    }

    /// Whether the error comes from the local database or the file system, rather than being the app's own.
    public static func isLocalData(_ error: Error) -> Bool {
        if error is DatabaseError { return true }
        let domain = (error as NSError).domain
        return domain == NSCocoaErrorDomain || domain == NSPOSIXErrorDomain
    }

    private static func classify(_ error: DatabaseError) -> LocalDataFailure {
        switch error.resultCode {
        case .SQLITE_CORRUPT, .SQLITE_NOTADB: return .damaged
        case .SQLITE_FULL: return .full
        default: return .temporary
        }
    }

    private static func isOutOfSpace(_ error: Error) -> Bool {
        let failure = error as NSError
        switch failure.domain {
        case NSCocoaErrorDomain: return failure.code == NSFileWriteOutOfSpaceError
        case NSPOSIXErrorDomain: return failure.code == Int(ENOSPC)
        default: return false
        }
    }
}
