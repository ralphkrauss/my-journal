import CryptoKit
import Foundation

/// What a connected device shows as a QR code to add a new device (protocol/README.md, Invite pairing): the
/// server's address, a lookup handle, the connected device's one-time key and a secret the server never sees.
public struct PairingInvite: Sendable, Equatable {
    public static let feature = "pairing-invite"
    /// The text starts with this and has no colon, so no app can register it as a URL scheme and receive it.
    static let prefix = "MYJOURNAL1."
    public let server: String
    let handle: Data
    let approverKey: Data
    let secret: Data

    public enum ReadError: Error, Equatable, LocalizedError {
        /// Not a My Journal code at all; scanning continues.
        case notInvite
        case newerVersion
        /// The address isn't HTTPS, so another device can't use it.
        case unreachableServer
        public var errorDescription: String? {
            switch self {
            case .notInvite: return nil
            case .newerVersion: return "Update My Journal to use this code."
            case .unreachableServer: return "This code points to a server this device can’t reach."
            }
        }
    }

    /// The lookup handle as the server stores it: 32 lower-case hexadecimal characters.
    public var code: String { handle.map { String(format: "%02x", $0) }.joined() }

    /// The QR code's text.
    public var text: String {
        Self.prefix + Self.base64URL(handle + approverKey + secret + Data(server.utf8))
    }

    /// Reads scanned text.
    public init(text: String) throws {
        guard text.hasPrefix(Self.prefix) else {
            if text.hasPrefix("MYJOURNAL"), text.dropFirst(9).first?.isNumber == true { throw ReadError.newerVersion }
            throw ReadError.notInvite
        }
        guard let bytes = Self.decodeBase64URL(String(text.dropFirst(Self.prefix.count))), bytes.count > 80,
            let server = String(data: bytes.dropFirst(80), encoding: .utf8)
        else { throw ReadError.notInvite }
        guard Self.origin(of: server) != nil else { throw ReadError.unreachableServer }
        self.server = server
        handle = Data(bytes.prefix(16))
        approverKey = Data(bytes.dropFirst(16).prefix(32))
        secret = Data(bytes.dropFirst(48).prefix(32))
    }

    init(server: String, handle: Data, approverKey: Data, secret: Data) {
        self.server = server
        self.handle = handle
        self.approverKey = approverKey
        self.secret = secret
    }

    /// The server's origin as the proof binds it: lower-case `https://host`, with the port only when it isn't 443.
    /// Nil for anything another device can't reach: only HTTPS, or loopback HTTP in debug builds for tests.
    public static func origin(of address: String) -> String? {
        guard let components = URLComponents(string: address), let scheme = components.scheme?.lowercased(),
            let host = components.host?.lowercased(), !host.isEmpty, components.user == nil,
            components.password == nil
        else { return nil }
        #if DEBUG
            let allowed = scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1"].contains(host))
        #else
            let allowed = scheme == "https"
        #endif
        guard allowed else { return nil }
        let port = components.port.flatMap { $0 == 443 && scheme == "https" ? nil : $0 }
        return scheme + "://" + host + (port.map { ":\($0)" } ?? "")
    }

    /// What the proof authenticates (HMAC-SHA256 with the secret): the handle, the approving key, the new device's
    /// key commitment, the server's origin and the device name, the variable-length fields length-prefixed.
    static func proofMessage(
        handle: Data, approverKey: Data, commitment: Data, origin: String, deviceName: String
    ) -> Data {
        var message = Data("journal:v2:pairing-invite".utf8) + Data([0]) + handle + approverKey + commitment
        for field in [Data(origin.utf8), Data(deviceName.utf8)] {
            message += Data([UInt8(field.count >> 8 & 0xff), UInt8(field.count & 0xff)]) + field
        }
        return message
    }

    /// The new device's proof that it read this code, sent with its pairing request.
    public func proof(commitment: String, deviceName: String) throws -> String {
        guard let origin = Self.origin(of: server), let commitment = Data(base64Encoded: commitment) else {
            throw PairingError.insecureGrant
        }
        let message = Self.proofMessage(
            handle: handle, approverKey: approverKey, commitment: commitment, origin: origin, deviceName: deviceName)
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: secret)))
            .base64EncodedString()
    }

    /// Whether the connected device's key in a pairing poll is the one this code named.
    public func names(approverKey key: String?) -> Bool {
        key.flatMap { Data(base64Encoded: $0) } == approverKey
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decodeBase64URL(_ text: String) -> Data? {
        guard text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            return nil
        }
        var standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        standard += String(repeating: "=", count: (4 - standard.count % 4) % 4)
        return Data(base64Encoded: standard)
    }
}

/// The connected device's side of a code it shows: the code, and the one-time key only this device holds.
public struct PairingInviteHost: Sendable {
    public let invite: PairingInvite
    let approverPrivateKey: Data

    /// Nil when the address isn't one another device can reach.
    public init?(server: String) {
        guard PairingInvite.origin(of: server) != nil else { return nil }
        let key = Curve25519.KeyAgreement.PrivateKey()
        approverPrivateKey = key.rawRepresentation
        invite = PairingInvite(
            server: server, handle: Self.random(16), approverKey: key.publicKey.rawRepresentation,
            secret: Self.random(32))
    }

    /// Whether a pairing request came from a device that read this code. Checked over this device's own values,
    /// never ones the server echoes, before the request's name is shown.
    public func verifies(_ candidate: PairingCandidate) -> Bool {
        guard let origin = PairingInvite.origin(of: invite.server),
            let commitment = candidate.keyCommitment.flatMap({ Data(base64Encoded: $0) }), commitment.count == 32,
            let proof = candidate.inviteProof.flatMap({ Data(base64Encoded: $0) }), proof.count == 32
        else { return false }
        let message = PairingInvite.proofMessage(
            handle: invite.handle, approverKey: invite.approverKey, commitment: commitment, origin: origin,
            deviceName: candidate.deviceName)
        return HMAC<SHA256>.isValidAuthenticationCode(
            proof, authenticating: message, using: SymmetricKey(data: invite.secret))
    }

    /// The challenge for a verified request, using the key the code named.
    public func challenge(_ candidate: PairingCandidate) -> PairingChallenge {
        PairingChallenge(candidate, privateKey: approverPrivateKey)
    }

    private static func random(_ count: Int) -> Data {
        Data(SymmetricKey(size: SymmetricKeySize(bitCount: count * 8)).withUnsafeBytes { Data($0) })
    }
}
