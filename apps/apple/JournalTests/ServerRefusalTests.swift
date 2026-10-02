import JournalCore
import XCTest

@testable import Journal

/// A refused request is explained by what the person can fix. A wrong setup code or recovery code must never read as
/// this device having lost access, and a pairing request a current server refuses isn't a server that needs an
/// update. Servers from before problem details send no reason, so their refusals are told apart by the request.
@MainActor
final class ServerRefusalTests: XCTestCase {
    private func problem(_ status: Int, _ code: String) -> Data {
        Data(#"{"status":\#(status),"code":"\#(code)","error":"\#(code)"}"#.utf8)
    }

    /// Answers every request with `status`, and a problem body with `code` unless it's nil (an older server).
    private func refusing(_ status: Int, code: String?) async throws -> FakeJournalServer {
        let body = code.map { problem(status, $0) } ?? Data()
        return try await FakeJournalServer { _ in (status, body) }
    }

    private func error(_ operation: () async throws -> Void) async -> Error? {
        do {
            try await operation()
            return nil
        } catch { return error }
    }

    func testRefusedSetupCodesAndRecoverySecretsAreNotReportedAsLostAccess() async throws {
        let envelope = try VaultCrypto.makeRecovery(masterKey: VaultCrypto.generateKey(), phrase: "a phrase").0
        for code in ["invalid_setup_code", nil] as [String?] {
            let server = try await refusing(401, code: code)
            let client = try ServerClient(address: server.address)
            let setup = await error {
                _ = try await client.initialize(
                    code: "code", envelope: envelope, recoverySecret: "secret", deviceName: "Mac")
            }
            XCTAssertEqual(setup?.localizedDescription, JournalError.invalidSetupCode.localizedDescription)
        }
        for code in ["invalid_recovery_secret", nil] as [String?] {
            let server = try await refusing(401, code: code)
            let recovery = await error {
                _ = try await ServerClient(address: server.address).recover(secret: "secret", deviceName: "Mac")
            }
            XCTAssertEqual(recovery?.localizedDescription, JournalError.invalidRecoveryKey.localizedDescription)
        }
        for code in ["unauthorized", nil] as [String?] {
            let server = try await refusing(401, code: code)
            let devices = await error { _ = try await ServerClient(address: server.address, token: "t").devices() }
            XCTAssertEqual(devices?.localizedDescription, JournalError.unauthorized.localizedDescription)
        }
    }

    /// A server without encryption takes a one-time recovery code. One that is wrong or already used is explained
    /// as such.
    func testAWrongServerRecoveryCodeIsExplained() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Refusal-" + UUID().uuidString)
        let model = AppModel(directory: directory)
        addTeardownBlock { @MainActor in try? FileManager.default.removeItem(at: directory) }
        let envelope = try JournalCoding.encoder().encode(RecoveryEnvelope.unprotected)
        let refusal = problem(401, "invalid_recovery_secret")
        let server = try await FakeJournalServer { request in
            request.method == "GET" ? (200, envelope) : (401, refusal)
        }
        let failure = await error {
            try await model.recoverServer(
                address: server.address, phrase: String(repeating: "a", count: 64), uploadLocal: false,
                shown: RecoveryParameters(.unprotected))
        }
        XCTAssertEqual(failure as? ServerConnectionError, .invalidRecoveryCode)
    }

    func testOnlyAServerWithoutCheckCodesIsReportedAsNeedingAnUpdate() async throws {
        let key = PairingPrivateKey().publicKey.rawRepresentation
        let current = try await refusing(400, code: "invalid_pairing_request")
        let refused = await error {
            _ = try await ServerClient(address: current.address).beginPairing(deviceName: "Mac", publicKey: key)
        }
        XCTAssertNotNil(refused)
        XCTAssertNotEqual(refused as? PairingError, .serverOutdated)
        let older = try await refusing(400, code: nil)
        let outdated = await error {
            _ = try await ServerClient(address: older.address).beginPairing(deviceName: "Mac", publicKey: key)
        }
        XCTAssertEqual(outdated as? PairingError, .serverOutdated)
    }
}
