import CryptoKit
import Foundation
import JournalCore

extension Probe {
    static func recoveryFixture() throws -> (Data, String, RecoveryEnvelope, String) {
        let version = Int(ProcessInfo.processInfo.environment["JOURNAL_TEST_RECOVERY_VERSION"] ?? "1") ?? 0
        guard (1...2).contains(version) else {
            throw ProbeFailure("JOURNAL_TEST_RECOVERY_VERSION must be 1 or 2")
        }
        let key = try VaultCrypto.generateKey()
        let phrase = version == 1 ? try VaultCrypto.recoveryPhrase() : "  disposable integration password  "
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase, formatVersion: version)
        return (key, phrase, recovery.0, recovery.1)
    }
    static func pairingGrant(_ anonymous: ServerClient, approver: ServerClient, master: Data, version: Int) async throws
        -> DeviceGrant
    {
        let (contents, id) = try await pair(
            anonymous, approver: approver, master: master, version: version, name: "Reconnected Phone")
        return DeviceGrant(deviceId: id, token: contents.token)
    }
    /// Runs both sides of check-code pairing concurrently and verifies both devices derive the same code.
    static func pair(_ anonymous: ServerClient, approver: ServerClient, master: Data, version: Int, name: String)
        async throws -> (PairingContents, UUID)
    {
        let key = Curve25519.KeyAgreement.PrivateKey()
        let ticket = try await anonymous.beginPairing(deviceName: name, publicKey: key.publicKey.rawRepresentation)
        let candidate = try await approver.pairingCandidate(code: ticket.code)
        async let approval = approver.preparePairingApproval(PairingChallenge(candidate))
        var shown: PairingReveal?
        while shown == nil {
            let poll = try await anonymous.pollPairing(ticket)
            if poll.approverKey != nil {
                shown = try await anonymous.revealPairing(ticket, poll: poll, privateKey: key)
            } else {
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        let confirmed = try await approval
        guard let shown, confirmed.checkCode == shown.checkCode else {
            throw ProbeFailure("the two devices showed different check codes")
        }
        try await approver.approvePairing(confirmed, masterKey: master, recoveryVersion: version)
        let poll = try await anonymous.pollPairing(ticket)
        let contents = try ServerClient.openPairing(poll, reveal: shown, ticket: ticket, privateKey: key)
        guard let id = poll.deviceId else { throw ProbeFailure("the approved poll has no device ID") }
        return (contents, id)
    }
}
