import CJournalCrypto
import CryptoKit
import Foundation
import Security

public struct RecoveryEnvelope: Codable, Sendable {
    public var salt: String
    public var wrappedKey: String
    public var iterations: Int
    public var formatVersion: Int
    public init(salt: String, wrappedKey: String, iterations: Int = 600_000, formatVersion: Int = 1) {
        self.salt = salt
        self.wrappedKey = wrappedKey
        self.iterations = iterations
        self.formatVersion = formatVersion
    }
}
/// What anyone may read about a server's recovery envelope: enough to derive the recovery secret from a password,
/// but not the wrapped vault key. A server with the `private-envelope` capability returns that key only with a new
/// device credential, after verifying the secret, or to a connected device. Older servers also publish `wrappedKey`.
public struct RecoveryParameters: Codable, Sendable, Equatable {
    public var salt: String
    public var iterations: Int
    public var formatVersion: Int
    public var wrappedKey: String?
    public init(salt: String, iterations: Int, formatVersion: Int, wrappedKey: String? = nil) {
        self.salt = salt
        self.iterations = iterations
        self.formatVersion = formatVersion
        self.wrappedKey = wrappedKey
    }
    public init(_ envelope: RecoveryEnvelope) {
        self.init(
            salt: envelope.salt, iterations: envelope.iterations, formatVersion: envelope.formatVersion,
            wrappedKey: envelope.wrappedKey)
    }
}

extension RecoveryParameters {
    public var requiresPassword: Bool { formatVersion != 4 }
    public var contentProtection: ContentProtection {
        get throws {
            try RecoveryEnvelope(
                salt: salt, wrappedKey: wrappedKey ?? "", iterations: iterations, formatVersion: formatVersion
            ).contentProtection
        }
    }
    /// The whole envelope, when the server published it (servers without `private-envelope`).
    public var envelope: RecoveryEnvelope? {
        wrappedKey.map {
            RecoveryEnvelope(salt: salt, wrappedKey: $0, iterations: iterations, formatVersion: formatVersion)
        }
    }
    /// Whether `envelope` is the one these parameters describe: the same format, salt and iterations, and the same
    /// wrapped key when it was published.
    public func describes(_ envelope: RecoveryEnvelope) -> Bool {
        salt == envelope.salt && iterations == envelope.iterations && formatVersion == envelope.formatVersion
            && (wrappedKey == nil || wrappedKey == envelope.wrappedKey)
    }
}

/// A credential's recovery derivation: the key that wraps the vault key, and the secret the server verifies.
public struct RecoveryDerivation: Sendable {
    public let wrappingKey: Data
    public let secret: String
}

public enum ContentProtection: String, Sendable {
    case encrypted, plaintext

    func encode(_ data: Data, key: Data, context: String) throws -> Data {
        switch self {
        case .encrypted: return try VaultCrypto.seal(data, key: key, context: context)
        case .plaintext: return data
        }
    }
    func decode(_ data: Data, key: Data, context: String) throws -> Data {
        switch self {
        case .encrypted: return try VaultCrypto.open(data, key: key, context: context)
        case .plaintext: return data
        }
    }
}

extension RecoveryEnvelope {
    public static var unprotected: Self { Self(salt: "", wrappedKey: "", iterations: 0, formatVersion: 4) }
    public var requiresPassword: Bool { formatVersion != 4 }
    public var contentProtection: ContentProtection {
        get throws {
            switch formatVersion {
            case 1, 2: return .encrypted
            case 3: return .plaintext
            case 4:
                guard salt.isEmpty, wrappedKey.isEmpty, iterations == 0 else { throw JournalError.invalidData }
                return .plaintext
            default: throw JournalError.unsupportedFormat
            }
        }
    }
}

public enum VaultCrypto {
    public static func random(_ count: Int) throws -> Data {
        guard count > 0 else { throw JournalError.invalidData }
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let pointer = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, count, pointer)
        }
        guard status == errSecSuccess else { throw JournalError.invalidData }
        return bytes
    }
    public static func generateKey() throws -> Data { try random(32) }
    public static func recoveryPhrase() throws -> String {
        let encoded = try random(24).map { String(format: "%02x", $0) }.joined()
        return stride(from: 0, to: encoded.count, by: 6).map { offset in
            let start = encoded.index(encoded.startIndex, offsetBy: offset)
            return String(encoded[start..<encoded.index(start, offsetBy: 6)])
        }.joined(separator: "-")
    }
    public static func seal(_ data: Data, key: Data, context: String) throws -> Data {
        guard key.count == 32 else { throw JournalError.invalidData }
        let box = try AES.GCM.seal(data, using: SymmetricKey(data: key), authenticating: Data(context.utf8))
        guard let combined = box.combined else { throw JournalError.invalidData }
        return combined
    }
    public static func open(_ data: Data, key: Data, context: String) throws -> Data {
        guard key.count == 32 else { throw JournalError.invalidData }
        return try AES.GCM.open(
            AES.GCM.SealedBox(combined: data), using: SymmetricKey(data: key), authenticating: Data(context.utf8))
    }
    public static func recordContext(id: UUID, kind: String) -> String {
        "journal:v1:record:\(kind):\(id.uuidString.lowercased())"
    }
    public static func attachmentContext(id: UUID) -> String { "journal:v1:attachment:\(id.uuidString.lowercased())" }
    public static func derive(_ phrase: String, salt: Data, iterations: Int = 600_000, trim: Bool = true) throws -> Data
    {
        guard salt.count == 16, iterations >= 100_000, iterations <= 2_000_000 else { throw JournalError.invalidData }
        let password = Array((trim ? phrase.trimmingCharacters(in: .whitespacesAndNewlines) : phrase).utf8)
        guard !password.isEmpty else { throw JournalError.invalidRecoveryKey }
        var output = Data(count: 32)
        let result = output.withUnsafeMutableBytes { out in
            salt.withUnsafeBytes { saltBytes in
                password.withUnsafeBytes { passBytes -> Int32 in
                    guard let passwordPointer = passBytes.baseAddress, let saltPointer = saltBytes.baseAddress,
                        let outputPointer = out.baseAddress
                    else { return -1 }
                    return journal_pbkdf2(
                        passwordPointer.assumingMemoryBound(to: CChar.self), password.count,
                        saltPointer.assumingMemoryBound(to: UInt8.self), salt.count, UInt32(iterations),
                        outputPointer.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
        }
        guard result == 0 else { throw JournalError.invalidData }
        return output
    }
    public static func recoverySecret(derivedKey: Data) -> String {
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: derivedKey), salt: Data(), info: Data("journal:v1:recovery-auth".utf8),
            outputByteCount: 32)
        return key.withUnsafeBytes { Data($0).map { String(format: "%02x", $0) }.joined() }
    }
    public static func makeRecovery(masterKey: Data, phrase: String, formatVersion: Int = 1) throws -> (
        RecoveryEnvelope, String
    ) {
        guard (1...3).contains(formatVersion) else { throw JournalError.unsupportedFormat }
        let salt = try random(16)
        let credential = credentials(phrase, formatVersion: formatVersion)[0]
        let derived = try derive(credential, salt: salt, trim: formatVersion == 1)
        let wrapped = try seal(masterKey, key: derived, context: "journal:v\(formatVersion):recovery")
        return (
            RecoveryEnvelope(
                salt: salt.base64EncodedString(), wrappedKey: wrapped.base64EncodedString(),
                formatVersion: formatVersion),
            recoverySecret(derivedKey: derived)
        )
    }
    /// The texts a typed credential may have been derived from, in the order to try them. Passwords (formats 2 and 3)
    /// are derived from their Unicode NFC form, so the same password typed or pasted as composed or decomposed
    /// characters opens the same envelope. Envelopes made before that rule used the exact typed text, which comes
    /// second when it differs. Generated recovery keys (format 1) are trimmed and otherwise used as typed.
    static func credentials(_ phrase: String, formatVersion: Int) -> [String] {
        guard formatVersion != 1 else { return [phrase] }
        let normalized = phrase.precomposedStringWithCanonicalMapping
        return Array(normalized.utf8) == Array(phrase.utf8) ? [phrase] : [normalized, phrase]
    }
    /// The derivations to try for a credential typed for an envelope with these parameters, most likely first.
    public static func recoveryDerivations(_ phrase: String, for parameters: RecoveryParameters) throws
        -> [RecoveryDerivation]
    {
        guard (1...3).contains(parameters.formatVersion) else { throw JournalError.unsupportedFormat }
        guard let salt = Data(base64Encoded: parameters.salt) else { throw JournalError.invalidData }
        return try credentials(phrase, formatVersion: parameters.formatVersion).map { credential in
            let derived = try derive(
                credential, salt: salt, iterations: parameters.iterations, trim: parameters.formatVersion == 1)
            return RecoveryDerivation(wrappingKey: derived, secret: recoverySecret(derivedKey: derived))
        }
    }
    /// The vault key in `envelope`, if `derivation` wraps it.
    public static func unwrap(_ envelope: RecoveryEnvelope, with derivation: RecoveryDerivation) throws -> Data {
        guard (1...3).contains(envelope.formatVersion) else { throw JournalError.unsupportedFormat }
        guard let wrapped = Data(base64Encoded: envelope.wrappedKey) else { throw JournalError.invalidData }
        do {
            return try open(
                wrapped, key: derivation.wrappingKey, context: "journal:v\(envelope.formatVersion):recovery")
        } catch { throw JournalError.invalidRecoveryKey }
    }
    public static func recover(_ envelope: RecoveryEnvelope, phrase: String) throws -> (Data, String) {
        guard (1...3).contains(envelope.formatVersion) else { throw JournalError.unsupportedFormat }
        guard Data(base64Encoded: envelope.wrappedKey) != nil else { throw JournalError.invalidData }
        for derivation in try recoveryDerivations(phrase, for: RecoveryParameters(envelope)) {
            if let key = try? unwrap(envelope, with: derivation) { return (key, derivation.secret) }
        }
        throw JournalError.invalidRecoveryKey
    }
}

public enum PasswordChangeError: Error, LocalizedError, Equatable {
    case incorrectPassword, samePassword, tooShort, unsupported, failed
    /// The server has the new password; saving it on this device failed. Retry with this envelope.
    case notSavedLocally
    public var errorDescription: String? {
        switch self {
        case .incorrectPassword: return "The current password is incorrect."
        case .samePassword: return "Choose a password that’s different from your current password."
        case .tooShort: return "Enter a new password."
        case .unsupported: return "This journal library doesn’t use a master password."
        case .failed:
            return
                "Couldn’t change your password. Your current password still works. Check your connection and try again."
        case .notSavedLocally:
            return "Your password was changed on your server but not on this device. Try again to finish."
        }
    }
}

/// A new password envelope for the same vault key, with the recovery secrets proving both passwords.
public struct PasswordChange: Sendable {
    public let envelope: RecoveryEnvelope
    public let currentRecoverySecret: String
    public let newRecoverySecret: String
}

extension VaultCrypto {
    /// The shortest master password, in characters: any password will do (the owner's choice for a personal
    /// journal). Journals are only as safe as it is: anyone with the server's data, a backup or an archive has its
    /// envelope and can guess it offline, which SECURITY.md explains.
    public static let minimumPasswordLength = 1
    /// Re-wraps `masterKey` with a new master password after verifying the current one opens the same key.
    /// Only master-password (version 2) libraries can change their password.
    public static func changePassword(
        _ envelope: RecoveryEnvelope, current: String, new: String, masterKey: Data
    ) throws -> PasswordChange {
        guard envelope.formatVersion == 2 else { throw PasswordChangeError.unsupported }
        guard current != new else { throw PasswordChangeError.samePassword }
        guard new.count >= minimumPasswordLength else { throw PasswordChangeError.tooShort }
        let opened: (Data, String)
        do { opened = try recover(envelope, phrase: current) } catch JournalError.invalidRecoveryKey {
            throw PasswordChangeError.incorrectPassword
        }
        guard opened.0 == masterKey else { throw PasswordChangeError.incorrectPassword }
        let replacement = try makeRecovery(masterKey: masterKey, phrase: new, formatVersion: 2)
        return PasswordChange(
            envelope: replacement.0, currentRecoverySecret: opened.1, newRecoverySecret: replacement.1)
    }
}
