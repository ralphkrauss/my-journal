import Foundation
import JournalCore

/// Why connecting to an existing server was refused before anything was sent to it.
enum ServerConnectionError: Error, LocalizedError, Equatable {
    /// The server's recovery envelope differs from the one this connection was set up with.
    case serverChanged
    /// The server stores journals without encryption, and this device has encrypted journals or none. 1.1 devices
    /// never join such a server (docs/design/1-1-encryption-and-passwords.md §3.6).
    case encryptionOff
    /// The server expects its one-time recovery code, and the typed text isn't one.
    case invalidRecoveryCode

    /// The one text for the check, for pairing and for the encryption form's check (`messages.connection.encryptionOff`).
    static func encryptionOffMessage(host: String?) -> String {
        let name = host.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "This server"
        return name
            + " doesn’t use encryption. On a device that has your journals, turn on encryption in Settings, or connect to a server that uses encryption."
    }

    var errorDescription: String? {
        switch self {
        case .serverChanged: return "This server has changed since you checked it. Choose Continue to check it again."
        case .encryptionOff: return Self.encryptionOffMessage(host: nil)
        case .invalidRecoveryCode: return "That recovery code isn’t valid. Check it and try again."
        }
    }
}

extension AppModel {
    /// The server's recovery envelope decides whether typed text is a password, which never leaves this device, or
    /// a one-time server recovery code, which is sent as is. It must be the envelope the person saw when choosing
    /// what to type. A server that holds unencrypted data is joined only by a device whose own library is unencrypted
    /// (1.0 behaviour, until Not Now is removed): a device with encrypted journals, or none, would otherwise turn
    /// them into unencrypted ones or start an unencrypted library.
    func checkServerEnvelope(_ current: RecoveryParameters, shown: RecoveryParameters?) throws {
        if let shown, current != shown { throw ServerConnectionError.serverChanged }
        guard try current.contentProtection == .plaintext else { return }
        if store == nil || configuration?.encrypted == true { throw ServerConnectionError.encryptionOff }
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
