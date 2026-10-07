import Foundation
import JournalCore
import os

/// What the person is told when something fails, in words that say what to do. The system's own text, which can be
/// “SQLite error 11: database disk image is malformed - while executing …” or “The operation couldn’t be completed.
/// (OSStatus -25308)”, never reaches the screen (docs/design/build-18-fixes-2026-10-06.md §1.14).
enum FailureMessage {
    /// What the failed operation was doing, which decides what is claimed about the person's writing.
    enum Operation {
        case reading
        case saving
    }

    static let damagedReading =
        "My Journal can’t read your journals on this device. Nothing has been removed. To keep a copy, choose Export Archive in Settings ▸ Backup."
    static let damagedSaving =
        "My Journal can’t save to your journals on this device. Nothing has been removed. To keep a copy, choose Export Archive in Settings ▸ Backup."
    static let temporaryReading = "My Journal couldn’t use its data on this device right now. Try again."
    static let temporarySaving = "My Journal couldn’t save your changes right now. Try again."
    static let full = "There isn’t enough space on this device. Free up space, then try again."
    static let keychain = "My Journal couldn’t use the device key. Try again."
    static let anythingElse = "Something went wrong. Try again."

    private static let log = Logger(subsystem: "org.privatejournal", category: "failures")

    /// The message for `error`. The app's own errors keep their text, which is already plain.
    static func text(for error: Error, _ operation: Operation) -> String {
        let error = unwrapped(error)
        let text = message(for: error, operation)
        if text != (error as? LocalizedError)?.errorDescription { record(error) }
        return text
    }

    private static func message(for error: Error, _ operation: Operation) -> String {
        if let failure = error as? URLError { return NetworkFailureMessage.text(for: failure) }
        switch LocalDataFailure(classifying: error) {
        case .damaged:
            return operation == .reading ? damagedReading : damagedSaving
        case .full:
            return full
        case .needsUpdate:
            return ownText(of: error) ?? anythingElse
        case .temporary:
            break
        }
        if isKeychain(error) { return keychain }
        if LocalDataFailure.isLocalData(error) { return operation == .reading ? temporaryReading : temporarySaving }
        return ownText(of: error) ?? anythingElse
    }

    /// An error that wraps the one that matters, as a merge stopped part way does.
    private static func unwrapped(_ error: Error) -> Error {
        (error as? MergeInterrupted)?.underlying ?? error
    }

    private static func ownText(of error: Error) -> String? {
        (error as? LocalizedError)?.errorDescription
    }

    private static func isKeychain(_ error: Error) -> Bool {
        if error is SecretStoreError { return true }
        return (error as NSError).domain == NSOSStatusErrorDomain
    }

    /// The system's text can hold SQL or a title, so only the domain and code are kept, as private data.
    private static func record(_ error: Error) {
        let failure = error as NSError
        log.error(
            "A failure was shown in words: \(failure.domain, privacy: .private), \(failure.code, privacy: .private).")
    }
}

extension Error {
    /// What the person is told about this failure (FailureMessage.swift).
    func shown(_ operation: FailureMessage.Operation) -> String {
        FailureMessage.text(for: self, operation)
    }
}
