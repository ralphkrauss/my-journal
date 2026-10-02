import Foundation
import JournalCore

/// Why connecting to an existing server was refused before anything was sent to it.
enum ServerConnectionError: Error, LocalizedError, Equatable {
    /// The server's recovery envelope differs from the one this connection was set up with.
    case serverChanged
    /// The server stores journals without encryption, but the journals on this device are encrypted.
    case encryptionOff
    /// The server expects its one-time recovery code, and the typed text isn't one.
    case invalidRecoveryCode

    var errorDescription: String? {
        switch self {
        case .serverChanged: return "This server has changed since you checked it. Choose Continue to check it again."
        case .encryptionOff:
            return
                "Encryption is off for this server, so it can’t store your encrypted journals. Connect to a server that uses encryption."
        case .invalidRecoveryCode: return "That recovery code isn’t valid. Check it and try again."
        }
    }
}

extension AppModel {
    /// The server's recovery envelope decides whether typed text is a password, which never leaves this device, or
    /// a one-time server recovery code, which is sent as is. It must be the envelope the person saw when choosing
    /// what to type, and it must not turn the encrypted journals on this device into unencrypted ones.
    func checkServerEnvelope(_ current: RecoveryParameters, shown: RecoveryParameters?) throws {
        if let shown, current != shown { throw ServerConnectionError.serverChanged }
        if try current.contentProtection == .plaintext, store != nil, configuration?.encrypted == true {
            throw ServerConnectionError.encryptionOff
        }
    }

    /// A one-time recovery code from a server without encryption: 64 hexadecimal digits. Anything else, such as a
    /// password typed by mistake, is never sent.
    static func serverRecoveryCode(_ text: String) -> String? {
        let code = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard code.utf8.count == 64,
            code.utf8.allSatisfy({
                (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0)
                    || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains($0)
            })
        else { return nil }
        return code
    }
}
