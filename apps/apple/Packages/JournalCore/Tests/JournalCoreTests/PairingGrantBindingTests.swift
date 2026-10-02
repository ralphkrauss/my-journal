import CryptoKit
import XCTest

@testable import JournalCore

/// The new device must accept only a grant sealed with the approving key its check code was computed from
/// (protocol/README.md, Pairing step 6). Otherwise a server could install a vault key of its own choosing.
final class PairingGrantBindingTests: XCTestCase {
    func testGrantFromAKeyOtherThanTheCheckCodeKeyIsRefused() throws {
        let device = PairingPrivateKey()
        let approver = PairingPrivateKey()
        let substitute = PairingPrivateKey()
        let ticket = PairingTicket(id: UUID(), code: "123456789", pollToken: "poll", expiresAt: .distantFuture)
        let shown = PairingReveal(
            checkCode: PairingCheck.code(
                pairingID: ticket.id, devicePublicKey: device.publicKey.rawRepresentation,
                approverPublicKey: approver.publicKey.rawRepresentation),
            approverKey: approver.publicKey.rawRepresentation)
        let vaultKey = try VaultCrypto.generateKey()
        func poll(sealedBy sealer: PairingPrivateKey, announcing announced: PairingPrivateKey) throws -> PairingPoll {
            let grant = try ServerClient.sealGrant(
                PairingContents(recoveryVersion: 2, masterKey: vaultKey, token: "token"),
                approverPrivateKey: sealer.rawRepresentation, devicePublicKey: device.publicKey.rawRepresentation,
                pairingID: ticket.id)
            return PairingPoll(
                approved: true, encryptedGrant: grant.base64EncodedString(), deviceId: UUID(),
                approverKey: announced.publicKey.rawRepresentation.base64EncodedString())
        }

        // The server swaps in its own key after the code was shown, consistently in the poll and the grant.
        XCTAssertThrowsError(
            try ServerClient.openPairing(
                poll(sealedBy: substitute, announcing: substitute), reveal: shown, ticket: ticket, privateKey: device)
        ) { XCTAssertEqual($0 as? PairingError, .insecureGrant) }
        // Or it keeps announcing the original key while delivering a grant sealed with its own.
        XCTAssertThrowsError(
            try ServerClient.openPairing(
                poll(sealedBy: substitute, announcing: approver), reveal: shown, ticket: ticket, privateKey: device)
        ) { XCTAssertEqual($0 as? PairingError, .insecureGrant) }

        let opened = try ServerClient.openPairing(
            poll(sealedBy: approver, announcing: approver), reveal: shown, ticket: ticket, privateKey: device)
        XCTAssertEqual(opened.masterKey, vaultKey)
        XCTAssertEqual(opened.recoveryVersion, 2)
    }
}
