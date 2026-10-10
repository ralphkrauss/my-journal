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
}
