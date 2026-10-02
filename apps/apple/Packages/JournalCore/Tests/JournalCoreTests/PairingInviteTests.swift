import CryptoKit
import XCTest

@testable import JournalCore

final class PairingInviteTests: XCTestCase {
    private let server = "https://journal.example.ts.net"

    private func candidate(
        _ host: PairingInviteHost, reading invite: PairingInvite, name: String = "Phone",
        device: Curve25519.KeyAgreement.PrivateKey = .init()
    ) throws -> PairingCandidate {
        let commitment = PairingCheck.commitment(device.publicKey.rawRepresentation)
        return PairingCandidate(
            id: UUID(), deviceName: name, publicKey: nil, keyCommitment: commitment, approverKey: nil,
            inviteProof: try invite.proof(commitment: commitment, deviceName: name), expiresAt: .distantFuture)
    }

    /// The code survives the camera unchanged, and the scanning device learns the connected device's key from it.
    func testScannedCodeCarriesServerAndApproverKey() throws {
        let host = try XCTUnwrap(PairingInviteHost(server: server))
        let scanned = try PairingInvite(text: host.invite.text)
        XCTAssertEqual(scanned, host.invite)
        XCTAssertEqual(scanned.server, server)
        XCTAssertFalse(host.invite.text.contains(":"), "A colon would let another app claim the text as a URL.")
        XCTAssertTrue(scanned.names(approverKey: host.invite.approverKey.base64EncodedString()))
        XCTAssertFalse(scanned.names(approverKey: Data(repeating: 1, count: 32).base64EncodedString()))
        XCTAssertEqual(scanned.code.count, 32)
    }

    func testOnlyARequestFromTheScannerIsAccepted() throws {
        let host = try XCTUnwrap(PairingInviteHost(server: server))
        let scanned = try PairingInvite(text: host.invite.text)
        var request = try candidate(host, reading: scanned)
        XCTAssertTrue(host.verifies(request))

        // A server can't rename the device, swap its key or forge a request without the secret.
        var renamed = request
        renamed.deviceName = "Ralph’s iPhone"
        XCTAssertFalse(host.verifies(renamed))
        var swapped = request
        swapped.keyCommitment = PairingCheck.commitment(
            Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation)
        XCTAssertFalse(host.verifies(swapped))
        request.inviteProof = nil
        XCTAssertFalse(host.verifies(request))
        // A code for another connected device, or relayed to another server, doesn't verify here.
        let other = try XCTUnwrap(PairingInviteHost(server: server))
        XCTAssertFalse(other.verifies(try candidate(host, reading: scanned)))
        let elsewhere = try XCTUnwrap(PairingInviteHost(server: "https://other.example.ts.net"))
        let relayed = PairingInvite(
            server: elsewhere.invite.server, handle: host.invite.handle, approverKey: host.invite.approverKey,
            secret: host.invite.secret)
        XCTAssertFalse(host.verifies(try candidate(host, reading: relayed)))
    }

    func testCodesOtherDevicesCantUseAreRefused() throws {
        XCTAssertNil(PairingInviteHost(server: "http://192.168.1.10:8080"))
        XCTAssertThrowsError(try PairingInvite(text: "https://example.com")) {
            XCTAssertEqual($0 as? PairingInvite.ReadError, .notInvite)
        }
        XCTAssertThrowsError(try PairingInvite(text: "MYJOURNAL2.AAAA")) {
            XCTAssertEqual($0 as? PairingInvite.ReadError, .newerVersion)
        }
        let insecure = PairingInvite(
            server: "http://192.168.1.10:8080", handle: Data(count: 16), approverKey: Data(count: 32),
            secret: Data(count: 32))
        XCTAssertThrowsError(try PairingInvite(text: insecure.text)) {
            XCTAssertEqual($0 as? PairingInvite.ReadError, .unreachableServer)
        }
    }

    /// Other clients must build the same message; protocol/README.md documents it.
    func testProofMessageLayout() {
        let message = PairingInvite.proofMessage(
            handle: Data(repeating: 1, count: 16), approverKey: Data(repeating: 2, count: 32),
            commitment: Data(repeating: 3, count: 32), origin: "https://journal.example.ts.net", deviceName: "iPad")
        var expected = Data("journal:v2:pairing-invite".utf8)
        expected.append(0)
        expected.append(Data(repeating: 1, count: 16))
        expected.append(Data(repeating: 2, count: 32))
        expected.append(Data(repeating: 3, count: 32))
        expected.append(contentsOf: [0, 30])
        expected.append(Data("https://journal.example.ts.net".utf8))
        expected.append(contentsOf: [0, 4])
        expected.append(Data("iPad".utf8))
        XCTAssertEqual(message, expected)
        // The protocol README's vector: the same inputs with a secret of 32 bytes of 0x04.
        let proof = HMAC<SHA256>.authenticationCode(
            for: message, using: SymmetricKey(data: Data(repeating: 4, count: 32)))
        XCTAssertEqual(Data(proof).base64EncodedString(), "xVcRQajP8P9JRb9Q527FO/+5SpxXKy3XXhgAxdoRgvY=")
        XCTAssertEqual(
            PairingInvite.origin(of: "HTTPS://Journal.Example.ts.net:443/"), "https://journal.example.ts.net")
        XCTAssertEqual(
            PairingInvite.origin(of: "https://journal.example.ts.net:8443"), "https://journal.example.ts.net:8443")
    }
}
