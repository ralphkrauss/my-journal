import CryptoKit
import Foundation

public struct PairingTicket: Codable, Sendable {
    public var id: UUID
    public var code: String
    public var pollToken: String
    public var expiresAt: Date
    /// How long after `expiresAt` the server keeps an approved grant readable (protocol/README.md, Expiry).
    static let grantGrace: TimeInterval = 120
    /// When the new device stops asking for approval. An approval arriving shortly before `expiresAt` can still be
    /// collected for a while after it, even if this device's clock runs ahead; a request that wasn't approved in
    /// time is reported as expired by the server itself.
    public var pollingDeadline: Date { expiresAt.addingTimeInterval(Self.grantGrace) }
}
public struct PairingCandidate: Codable, Sendable {
    public var id: UUID
    public var deviceName: String
    /// Revealed only after the approving device has contributed its key.
    public var publicKey: String?
    /// Nil for devices that don't support check codes.
    public var keyCommitment: String?
    public var approverKey: String?
    /// Present when the new device read a QR code (`pairing-invite`); checked with `PairingInviteHost.verifies`.
    public var inviteProof: String?
    public var expiresAt: Date
}
public struct PairingPoll: Codable, Sendable {
    public var approved: Bool
    public var encryptedGrant: String?
    public var deviceId: UUID?
    public var approverKey: String?
    public var declined: Bool?
}
public struct PairingContents: Codable, Sendable {
    public var recoveryVersion: Int?
    public var masterKey: Data
    public var token: String
}

/// The approving device's one-time key for a candidate. Retrying with the same challenge is safe.
public struct PairingChallenge: Sendable {
    public let candidate: PairingCandidate
    let approverPrivateKey: Data
    public init(_ candidate: PairingCandidate) {
        self.candidate = candidate
        approverPrivateKey = Curve25519.KeyAgreement.PrivateKey().rawRepresentation
    }
    /// With the key a shown QR code named.
    init(_ candidate: PairingCandidate, privateKey: Data) {
        self.candidate = candidate
        approverPrivateKey = privateKey
    }
}

/// What the new device shows: its check code and the approving device's key the code was computed from.
/// Only a grant sealed with that same key is accepted.
public struct PairingReveal: Sendable, Equatable {
    /// Six digits, without grouping.
    public let checkCode: String
    let approverKey: Data
}

/// A candidate whose key has been revealed and checked, ready for the person to compare codes.
public struct PairingApproval: Sendable {
    public let candidate: PairingCandidate
    public let devicePublicKey: Data
    /// Six digits, without grouping.
    public let checkCode: String
    let approverPrivateKey: Data
}

public enum PairingError: Error, LocalizedError, Equatable {
    case serverOutdated, deviceOutdated, insecureCandidate, insecureGrant, declined, expired, codeNotFound, inviteUsed
    case noResponse(String)
    public var errorDescription: String? {
        switch self {
        case .serverOutdated: return "This server needs an update before you can add devices."
        case .deviceOutdated: return "Update My Journal on the new device, then try again."
        case .insecureCandidate:
            return "Couldn’t add this device securely. Get a new code on the new device and try again."
        case .insecureGrant: return "Couldn’t add this device securely. Get a new code and try again."
        case .declined: return "Your other device didn’t approve this request."
        case .expired: return "This pairing code has expired."
        case .codeNotFound: return "That pairing code wasn’t found. Check the code and try again."
        case .inviteUsed: return "This code was already used. Show a new code on your other device."
        case .noResponse(let name): return "\(name) didn’t respond. Get a new code on the new device and try again."
        }
    }
}

/// A Curve25519 key-agreement private key used only for one pairing.
public typealias PairingPrivateKey = Curve25519.KeyAgreement.PrivateKey  // gitleaks:allow -- Type, not a credential.

/// Check-code pairing (protocol/README.md). The new device commits to its key before the approving
/// device contributes a one-time key, so a dishonest server can't search for keys with a matching code.
public enum PairingCheck {
    public static let feature = "pairing-check-code"
    public static func commitment(_ publicKey: Data) -> String {
        Data(SHA256.hash(data: Data("journal:v2:pairing-commitment".utf8) + publicKey)).base64EncodedString()
    }
    public static func code(pairingID: UUID, devicePublicKey: Data, approverPublicKey: Data) -> String {
        let digest = SHA256.hash(
            data: Data("journal:v2:pairing-check:\(pairingID.uuidString.lowercased()):".utf8) + devicePublicKey
                + approverPublicKey)
        let value = digest.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        let digits = String(value % 1_000_000)
        return String(repeating: "0", count: 6 - digits.count) + digits
    }
    /// "123 456"
    public static func grouped(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return String(code.prefix(3)) + " " + String(code.suffix(3))
    }
    static func grantKey(
        privateKey: PairingPrivateKey,
        publicKey: Curve25519.KeyAgreement.PublicKey, pairingID: UUID
    ) throws -> Data {
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        return shared.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: Data(pairingID.uuidString.lowercased().utf8),
            sharedInfo: Data("journal:v1:pairing".utf8), outputByteCount: 32
        ).withUnsafeBytes { Data($0) }
    }
}

// New device side.
extension ServerClient {
    /// Starts a request, answering a scanned code when `invite` is given.
    public func beginPairing(
        deviceName: String, publicKey: Data, invite: PairingInvite? = nil
    ) async throws -> PairingTicket {
        struct Begin: Encodable {
            let deviceName: String
            let keyCommitment: String
            let invite: String?
            let inviteProof: String?
        }
        let commitment = PairingCheck.commitment(publicKey)
        let (data, status) = try await request(
            "/v1/pairing", method: "POST",
            body: json(
                Begin(
                    deviceName: deviceName, keyCommitment: commitment, invite: invite?.code,
                    inviteProof: try invite?.proof(commitment: commitment, deviceName: deviceName))))
        if status == 409, Self.problemCode(data) == "invite_used" { throw PairingError.inviteUsed }
        // Servers from before check codes require the key itself and refuse a commitment without giving a reason.
        if status == 400, Self.problemCode(data) == nil { throw PairingError.serverOutdated }
        guard status == 200 else { throw Self.unanswered(status: status) }
        return try JournalCoding.decoder().decode(PairingTicket.self, from: data)
    }
    public func cancelPairing(_ ticket: PairingTicket) async throws {
        let (_, status) = try await request(
            "/v1/pairing/\(ticket.id.uuidString.lowercased())/cancel", method: "POST",
            body: json(["pollToken": ticket.pollToken]))
        guard status == 204 || status == 404 else { throw JournalError.server("Couldn’t cancel pairing.") }
    }
    public func pollPairing(_ ticket: PairingTicket) async throws -> PairingPoll {
        try await pairingCall(
            "/v1/pairing/\(ticket.id.uuidString.lowercased())/poll", method: "POST",
            body: json(["pollToken": ticket.pollToken]))
    }
    /// Reveals this device's key once the approving device's key is known. The result holds the check code to
    /// show and the approving key it belongs to, which `openPairing` requires the grant to come from.
    public func revealPairing(
        _ ticket: PairingTicket, poll: PairingPoll,
        privateKey: PairingPrivateKey
    ) async throws -> PairingReveal {
        guard let approver = poll.approverKey.flatMap({ Data(base64Encoded: $0) }), approver.count == 32 else {
            throw PairingError.insecureGrant
        }
        let publicKey = privateKey.publicKey.rawRepresentation
        let (data, status) = try await request(
            "/v1/pairing/\(ticket.id.uuidString.lowercased())/reveal", method: "POST",
            body: json(["pollToken": ticket.pollToken, "publicKey": publicKey.base64EncodedString()]))
        if status == 404 { throw PairingError.expired }
        if status == 409, Self.problemCode(data) == "pairing_declined" { throw PairingError.declined }
        guard status == 204 else { throw PairingError.insecureGrant }
        return PairingReveal(
            checkCode: PairingCheck.code(pairingID: ticket.id, devicePublicKey: publicKey, approverPublicKey: approver),
            approverKey: approver)
    }
    /// Opens a grant, requiring it to come from the approver key used for the displayed check code. A server that
    /// substitutes its own key after the code was shown can't deliver a key or mode of its choosing.
    public static func openPairing(
        _ poll: PairingPoll, reveal: PairingReveal, ticket: PairingTicket,
        privateKey: PairingPrivateKey
    ) throws -> PairingContents {
        guard let encoded = poll.encryptedGrant, let data = Data(base64Encoded: encoded), data.count > 60,
            reveal.approverKey.count == 32, data.prefix(32) == reveal.approverKey,
            poll.approverKey.flatMap({ Data(base64Encoded: $0) }) == reveal.approverKey
        else {
            throw PairingError.insecureGrant
        }
        let remote = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: data.prefix(32))
        let key = try PairingCheck.grantKey(privateKey: privateKey, publicKey: remote, pairingID: ticket.id)
        do {
            return try JournalCoding.decoder().decode(
                PairingContents.self,
                from: VaultCrypto.open(
                    data.dropFirst(32), key: key, context: "journal:v1:pairing:\(ticket.id.uuidString.lowercased())"))
        } catch { throw PairingError.insecureGrant }
    }
}

// Approving device side.
extension ServerClient {
    public func pairingCandidate(code: String) async throws -> PairingCandidate {
        try await pairingCall(
            "/v1/pairing/lookup", method: "POST", body: json(["code": code]), missing: .codeNotFound)
    }
    /// Contributes the challenge's one-time key, waits for the new device to reveal its key, and checks it
    /// against the commitment made before the one-time key existed.
    public func preparePairingApproval(_ challenge: PairingChallenge) async throws -> PairingApproval {
        let candidate = challenge.candidate
        guard let commitment = candidate.keyCommitment else { throw PairingError.deviceOutdated }
        let approverKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: challenge.approverPrivateKey)
        let approverPublic = approverKey.publicKey.rawRepresentation.base64EncodedString()
        let path = "/v1/pairing/\(candidate.id.uuidString.lowercased())"
        let (_, status) = try await request(
            path + "/challenge", method: "POST", body: json(["approverKey": approverPublic]))
        if status == 404 { throw PairingError.expired }
        guard status == 204 else { throw PairingError.insecureCandidate }
        var delay: UInt64 = 1_000_000_000
        while true {
            try Task.checkCancellation()
            guard candidate.expiresAt > Date() else { throw PairingError.noResponse(candidate.deviceName) }
            do {
                let current: PairingCandidate = try await pairingCall(path)
                if let revealed = current.publicKey {
                    return try Self.checkedApproval(
                        current, revealed: revealed, commitment: commitment, challenge: challenge)
                }
                delay = 1_000_000_000
            } catch is ServerRateLimited {
                delay = min(delay * 2, 16_000_000_000)
            }
            try await Task.sleep(nanoseconds: delay)
        }
    }
    private static func checkedApproval(
        _ current: PairingCandidate, revealed: String, commitment: String, challenge: PairingChallenge
    ) throws -> PairingApproval {
        let approverPublic = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: challenge.approverPrivateKey)
            .publicKey.rawRepresentation
        guard current.id == challenge.candidate.id, current.keyCommitment == commitment,
            current.approverKey == approverPublic.base64EncodedString(),
            let bytes = Data(base64Encoded: revealed), bytes.count == 32, PairingCheck.commitment(bytes) == commitment
        else { throw PairingError.insecureCandidate }
        return PairingApproval(
            candidate: current, devicePublicKey: bytes,
            checkCode: PairingCheck.code(
                pairingID: current.id, devicePublicKey: bytes, approverPublicKey: approverPublic),
            approverPrivateKey: challenge.approverPrivateKey)
    }
    /// Sends the vault key to the device whose check code the person confirmed.
    public func approvePairing(_ approval: PairingApproval, masterKey: Data, recoveryVersion: Int = 1) async throws {
        let id = approval.candidate.id
        let token = try VaultCrypto.random(32).map { String(format: "%02x", $0) }.joined()
        let grant = try Self.sealGrant(
            PairingContents(recoveryVersion: recoveryVersion, masterKey: masterKey, token: token),
            approverPrivateKey: approval.approverPrivateKey, devicePublicKey: approval.devicePublicKey, pairingID: id)
        struct Approved: Decodable { var id: UUID }
        let _: Approved = try await pairingCall(
            "/v1/pairing/\(id.uuidString.lowercased())/approve", method: "POST",
            body: json(["deviceToken": token, "encryptedGrant": grant.base64EncodedString()]))
    }
    /// The approver's one-time public key followed by the sealed contents (protocol/README.md, Grant encryption).
    static func sealGrant(
        _ contents: PairingContents, approverPrivateKey: Data, devicePublicKey: Data, pairingID id: UUID
    ) throws -> Data {
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: approverPrivateKey)
        let remoteKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: devicePublicKey)
        let symmetric = try PairingCheck.grantKey(privateKey: privateKey, publicKey: remoteKey, pairingID: id)
        let encrypted = try VaultCrypto.seal(
            try JournalCoding.encoder().encode(contents), key: symmetric,
            context: "journal:v1:pairing:\(id.uuidString.lowercased())")
        return privateKey.publicKey.rawRepresentation + encrypted
    }
    /// Tells the new device the request wasn't approved. Best effort: an unanswered request also expires.
    public func declinePairing(_ id: UUID) async throws {
        let (_, status) = try await request("/v1/pairing/\(id.uuidString.lowercased())/decline", method: "POST")
        guard status == 204 || status == 404 || status == 409 else { throw Self.unanswered(status: status) }
    }
}

extension ServerClient {
    /// A pairing request. A missing request is reported as a typed error, so callers never match on its wording.
    fileprivate func pairingCall<T: Decodable>(
        _ path: String, method: String = "GET", body: Data? = nil, missing: PairingError = .expired
    ) async throws -> T {
        let (data, status) = try await request(path, method: method, body: body)
        if status == 404 { throw missing }
        guard (200..<300).contains(status) else { throw Self.unanswered(status: status) }
        return try JournalCoding.decoder().decode(T.self, from: data)
    }
}
