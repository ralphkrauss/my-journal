import Foundation
import JournalCore

/// Why connecting to an existing server was refused before anything was sent to it.
enum ServerConnectionError: Error, LocalizedError, Equatable {
    /// The server's recovery envelope differs from the one this connection was set up with.
    case serverChanged
    /// The server stores journals without encryption (recovery format 3 or 4, as version 1.0 could set one up). 1.1
    /// devices never join, read or send to such a server (docs/design/1-1-encryption-and-passwords.md §3.6).
    case encryptionOff

    /// The one text for the check, for connecting and for pairing (`messages.connection.encryptionOff`).
    static func encryptionOffMessage(host: String?) -> String {
        let name = host.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "This server"
        return name
            + " doesn’t use encryption. On a device that has your journals, turn on encryption in Settings, or connect to a server that uses encryption."
    }

    var errorDescription: String? {
        switch self {
        case .serverChanged: return "This server has changed since you checked it. Choose Continue to check it again."
        case .encryptionOff: return Self.encryptionOffMessage(host: nil)
        }
    }
}

extension AppModel {
    /// The server's recovery envelope decides how typed text is used (a password never leaves this device). It must be
    /// the envelope the person saw when choosing what to type. A server that holds unencrypted data is never joined:
    /// this version only has encrypted libraries.
    func checkServerEnvelope(_ current: RecoveryParameters, shown: RecoveryParameters?) throws {
        if let shown, current != shown { throw ServerConnectionError.serverChanged }
        do { try current.requireEncrypted() } catch JournalError.notEncrypted {
            throw ServerConnectionError.encryptionOff
        }
    }
}
