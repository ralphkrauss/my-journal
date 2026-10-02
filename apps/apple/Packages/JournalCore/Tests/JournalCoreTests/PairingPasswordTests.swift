import XCTest

@testable import JournalCore

final class PairingPasswordTests: XCTestCase {
    /// Shared with protocol/README.md and the server's commitment check.
    func testPairingCommitmentAndCheckCodeMatchTheProtocolVectors() throws {
        let device = Data(repeating: 7, count: 32)
        let approver = Data(repeating: 9, count: 32)
        let id = try XCTUnwrap(UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301"))
        XCTAssertEqual(PairingCheck.commitment(device), "2kHrWMfI9jssNr6LMzi1CnMfO8j59ftEu0NEGULOHFY=")
        XCTAssertEqual(PairingCheck.code(pairingID: id, devicePublicKey: device, approverPublicKey: approver), "479111")
        XCTAssertEqual(PairingCheck.grouped("479111"), "479 111")
        // A substituted key yields a different code.
        XCTAssertNotEqual(
            PairingCheck.code(pairingID: id, devicePublicKey: approver, approverPublicKey: approver), "479111")
    }

    func testChangingPasswordRewrapsTheSameKeyOnlyWithTheCurrentPassword() throws {
        let key = try VaultCrypto.generateKey()
        let (envelope, secret) = try VaultCrypto.makeRecovery(
            masterKey: key, phrase: "current password", formatVersion: 2)
        XCTAssertThrowsError(
            try VaultCrypto.changePassword(envelope, current: "wrong password", new: "a new password", masterKey: key)
        ) { XCTAssertEqual($0 as? PasswordChangeError, .incorrectPassword) }
        XCTAssertThrowsError(
            try VaultCrypto.changePassword(
                envelope, current: "current password", new: "a new password", masterKey: VaultCrypto.generateKey())
        ) { XCTAssertEqual($0 as? PasswordChangeError, .incorrectPassword) }
        XCTAssertThrowsError(
            try VaultCrypto.changePassword(
                envelope, current: "current password", new: "current password", masterKey: key)
        ) { XCTAssertEqual($0 as? PasswordChangeError, .samePassword) }
        XCTAssertThrowsError(
            try VaultCrypto.changePassword(envelope, current: "current password", new: "", masterKey: key)
        ) {
            XCTAssertEqual($0 as? PasswordChangeError, .tooShort, "An empty password is refused, not only by the view")
        }

        let change = try VaultCrypto.changePassword(
            envelope, current: "current password", new: "a new password", masterKey: key)
        XCTAssertEqual(change.currentRecoverySecret, secret)
        XCTAssertEqual(change.envelope.formatVersion, 2)
        let reopened = try VaultCrypto.recover(change.envelope, phrase: "a new password")
        XCTAssertEqual(reopened.0, key)
        XCTAssertEqual(reopened.1, change.newRecoverySecret)
        XCTAssertThrowsError(try VaultCrypto.recover(change.envelope, phrase: "current password"))

        let (legacy, _) = try VaultCrypto.makeRecovery(masterKey: key, phrase: "recovery key", formatVersion: 1)
        XCTAssertThrowsError(
            try VaultCrypto.changePassword(legacy, current: "recovery key", new: "a new password", masterKey: key)
        ) { XCTAssertEqual($0 as? PasswordChangeError, .unsupported) }
    }
}
