import JournalCore
import SwiftUI
import XCTest

@testable import Journal

/// Connecting a device that already has journals (docs/design/join-with-local-journals.md): nothing that would upload
/// them is sent before the person agrees to merge with the named server, and a join that fails gives up the access it
/// received and leaves the journals on this device as they were.
@MainActor
final class MergeJoinTests: XCTestCase {
    private let serverPassword = "the server's master password"

    private func model(writing: Bool, encrypted: Bool = true) async throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MergeJoin-" + UUID().uuidString)
        let model = AppModel(directory: directory)
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            for account in [model.configuration?.keyID, model.configuration?.connectionKeyID].compactMap({ $0 }) {
                try? Keychain.remove(account)
            }
            try? FileManager.default.removeItem(at: directory)
        }
        await model.start(password: encrypted ? "this device's own password" : nil, encrypted: encrypted)
        XCTAssertTrue(model.nothingWritten, "Start a Journal writes nothing yet.")
        if writing {
            await model.newEntry()
            _ = await model.finishPendingSave()
            try await model.refresh()
            XCTAssertFalse(model.nothingWritten)
            XCTAssertTrue(model.joinsByMerging)
        }
        return model
    }
    /// A server that checks out for a scanned code. Pairing requests are refused, since only whether one was sent
    /// matters here.
    private func scanServer(encrypted: Bool = true) async throws -> FakeJournalServer {
        let envelope =
            encrypted
            ? try VaultCrypto.makeRecovery(masterKey: VaultCrypto.generateKey(), phrase: serverPassword).0
            : RecoveryEnvelope.unprotected
        let parameters = try JournalCoding.encoder().encode(RecoveryParameters(envelope))
        let status = Data(#"{"protocolVersion":1,"initialized":true,"features":["pairing-invite"]}"#.utf8)
        return try await FakeJournalServer { request in
            switch (request.method, request.path) {
            case ("GET", "/v1/status"): return (200, status)
            case ("GET", "/v1/recovery"): return (200, parameters)
            default: return (503, Data("{}".utf8))
            }
        }
    }
    private func pairingRequests(_ server: FakeJournalServer) -> Int {
        server.requests.filter { $0.method == "POST" && $0.path == "/v1/pairing" }.count
    }
    private func settle(_ flow: ConnectionFlow, until done: () -> Bool = { true }) async throws {
        for _ in 0..<200 where flow.busy || !done() { try await Task.sleep(nanoseconds: 25_000_000) }
    }
    private func invite(_ server: FakeJournalServer) throws -> PairingInvite {
        // The fake server is plain HTTP on loopback, which only Debug builds accept for scanned codes; Release
        // refuses it by design, so these tests run in the Debug lanes.
        try XCTUnwrap(
            PairingInviteHost(server: server.address),
            "Scanned codes for a loopback test server need a Debug build."
        ).invite
    }

    func testAScannedCodeAsksToMergeBeforeTheConnectedDeviceIsAsked() async throws {
        let model = try await model(writing: true)
        let server = try await scanServer()
        let flow = ConnectionFlow(model: model)
        flow.join(try invite(server))
        try await settle(flow)
        XCTAssertEqual(flow.path, [.merge])
        XCTAssertEqual(pairingRequests(server), 0, "Nothing is asked of the other device before Merge.")
        await captureDesign(.merge, flow: flow, model: model, name: "Merge Journals")

        flow.confirmMerge()
        XCTAssertEqual(flow.path, [.finish])
        try await settle(flow) { self.pairingRequests(server) > 0 }
        XCTAssertEqual(pairingRequests(server), 1)
        await captureDesign(.finish, flow: flow, model: model, name: "Finish after a refused request")

        // A new code for the server just agreed to doesn't ask again; one for another server does.
        flow.join(try invite(server))
        try await settle(flow) { self.pairingRequests(server) > 1 }
        XCTAssertEqual(flow.path, [.finish])
        XCTAssertEqual(pairingRequests(server), 2)
        let other = try await scanServer()
        flow.join(try invite(other))
        try await settle(flow)
        XCTAssertEqual(flow.path, [.merge])
        XCTAssertEqual(pairingRequests(other), 0)
        flow.close()
    }

    /// With JOURNAL_CAPTURE_DESIGN=1, attaches how a step looks, for checking the layout against the design.
    private func captureDesign(
        _ step: ConnectionFlow.Step, flow: ConnectionFlow, model: AppModel, name: String
    ) async {
        guard ProcessInfo.processInfo.environment["JOURNAL_CAPTURE_DESIGN"] == "1" else { return }
        let view = NavigationStack { ConnectionStepView(step: step, flow: flow) }.environmentObject(model)
        if let preview = await NativeTestPreview.capture(view, name: name, width: 480, height: 560) { add(preview) }
    }

    func testANewLibraryWithNothingWrittenJoinsWithoutMerging() async throws {
        let model = try await model(writing: false)
        let server = try await scanServer()
        let flow = ConnectionFlow(model: model)
        flow.join(try invite(server))
        try await settle(flow) { self.pairingRequests(server) > 0 }
        XCTAssertEqual(flow.path, [.finish])
        XCTAssertEqual(flow.downloadFooter, "Your journals will download to this device.")
        flow.close()
    }

    func testEncryptedJournalsAreRefusedByAServerWithoutEncryptionBeforeAnythingIsSent() async throws {
        let model = try await model(writing: true)
        let server = try await scanServer(encrypted: false)
        let flow = ConnectionFlow(model: model)
        flow.join(try invite(server))
        try await settle(flow)
        XCTAssertTrue(flow.path.isEmpty)
        XCTAssertEqual(
            flow.errorMessage(on: nil),
            "The journals on this device are encrypted, but \(flow.host) doesn’t use encryption. Turn on encryption in Settings > Privacy on a connected device, then try again."
        )
        XCTAssertEqual(pairingRequests(server), 0)
        flow.close()
    }

    /// A password server that hands out access but can't synchronize, so merging stops while downloading.
    private func failingServer(grant: DeviceGrant) async throws -> (FakeJournalServer, RecoveryEnvelope) {
        let envelope = try VaultCrypto.makeRecovery(masterKey: VaultCrypto.generateKey(), phrase: serverPassword).0
        let parameters = try JournalCoding.encoder().encode(RecoveryParameters(envelope))
        struct Recovered: Encodable {
            let deviceId: UUID
            let token: String
            let envelope: RecoveryEnvelope
        }
        let recovered = try JournalCoding.encoder().encode(
            Recovered(deviceId: grant.deviceId, token: grant.token, envelope: envelope))
        let status = Data(#"{"protocolVersion":1,"initialized":true}"#.utf8)
        let server = try await FakeJournalServer { request in
            switch (request.method, request.path) {
            case ("GET", "/v1/status"): return (200, status)
            case ("GET", "/v1/recovery"): return (200, parameters)
            case ("POST", "/v1/recovery"): return (200, recovered)
            case ("DELETE", _): return (204, Data())
            default: return (503, Data("{}".utf8))
            }
        }
        return (server, envelope)
    }

    func testAMergeThatFailsGivesUpItsAccessAndKeepsTheJournals() async throws {
        let model = try await model(writing: true)
        let entry = try XCTUnwrap(model.items.first { $0.kind == "entry" })
        let grant = DeviceGrant(deviceId: UUID(), token: String(repeating: "t", count: 64))
        let (server, envelope) = try await failingServer(grant: grant)
        let folders = { () throws -> [String] in
            try FileManager.default.contentsOfDirectory(atPath: model.directory.path).filter { $0.hasPrefix("vault-") }
        }
        let before = try folders()
        do {
            try await model.recoverServer(
                address: server.address, phrase: serverPassword, uploadLocal: true,
                shown: RecoveryParameters(envelope))
            XCTFail("The server can't synchronize.")
        } catch {
            XCTAssertTrue(error is MergeInterrupted, "Merging had started: \(error)")
        }
        XCTAssertTrue(
            server.requests.contains {
                $0.method == "DELETE" && $0.path == "/v1/devices/\(grant.deviceId.uuidString.lowercased())"
            }, "The access received for this attempt is given up.")
        XCTAssertEqual(try folders(), before, "The staged copy is removed.")
        XCTAssertNil(model.connection)
        XCTAssertNil(model.joinPhase)
        XCTAssertTrue(model.canEdit)
        let kept = try await model.store?.item(entry.id)
        XCTAssertEqual(kept, entry)
    }

    /// A server opened by a recovery key asks for one, so a wrong key or too many tries must not say "password".
    func testSigningInWithARecoveryKeyNamesTheKeyInItsErrors() async throws {
        let model = try await model(writing: false)
        let recoveryKey = "ABCD-EFGH-JKLM-NPQR-STUV-WXYZ"
        let envelope = try VaultCrypto.makeRecovery(
            masterKey: VaultCrypto.generateKey(), phrase: recoveryKey, formatVersion: 1
        ).0
        let parameters = try JournalCoding.encoder().encode(RecoveryParameters(envelope))
        let status = Data(#"{"protocolVersion":1,"initialized":true}"#.utf8)
        let server = try await FakeJournalServer { request in
            switch (request.method, request.path) {
            case ("GET", "/v1/status"): return (200, status)
            case ("GET", "/v1/recovery"): return (200, parameters)
            default: return (429, Data("{}".utf8))
            }
        }
        let flow = ConnectionFlow(model: model)
        flow.address = server.address
        flow.check()
        try await settle(flow)
        XCTAssertEqual(flow.path, [.signIn])
        XCTAssertEqual(flow.credentialName, "Recovery Key")

        flow.phrase = "WRNG-KEYS-WRNG-KEYS-WRNG-KEYS"
        flow.signIn()
        try await settle(flow)
        XCTAssertEqual(flow.fieldErrors[.phrase], "That recovery key isn’t correct.")

        flow.phrase = recoveryKey
        flow.signIn()
        try await settle(flow)
        XCTAssertEqual(
            flow.fieldErrors[.phrase],
            "Too many recovery key attempts on this server. Try again in a few minutes, or use a connected device.")
        flow.close()
    }

    /// Joining sets up publishing to agents as opening the app does: the library joined publishes after its first
    /// sync, and Agent Access lists the agents without a relaunch.
    func testAJoinedLibraryPublishesToAgentsAndListsThemWithoutRelaunching() async throws {
        let model = try await model(writing: false)
        let key = try VaultCrypto.generateKey()
        let envelope = try VaultCrypto.makeRecovery(masterKey: key, phrase: serverPassword).0
        let published = try JournalCoding.encoder().encode(envelope)
        let status = Data(
            #"{"protocolVersion":1,"initialized":true,"serverId":"fake-server","features":["agent-access-2"],"mcpUrl":"https://journal.test/mcp"}"#
                .utf8)
        let page = Data(#"{"changes":[],"cursor":0,"hasMore":false,"serverId":"fake-server","serverIdCursor":0}"#.utf8)
        let server = try await FakeJournalServer { request in
            switch (request.method, request.path) {
            case ("GET", "/v1/status"): return (200, status)
            case ("GET", "/v1/recovery"): return (200, published)
            case ("GET", let path) where path.hasPrefix("/v1/sync/"): return (200, page)
            case ("GET", "/v1/agents/"): return (200, Data("[]".utf8))
            default: return (503, Data("{}".utf8))
            }
        }
        func agentLists() -> Int { server.requests.filter { $0.method == "GET" && $0.path == "/v1/agents/" }.count }
        try await model.installPairedVault(
            address: server.address, key: key, token: String(repeating: "p", count: 64), deviceID: UUID(),
            uploadLocal: false, recoveryVersion: envelope.formatVersion, shown: RecoveryParameters(envelope),
            replacingEmptyLibrary: true)
        XCTAssertNotNil(model.connection)
        for _ in 0..<200 where agentLists() == 0 { try await Task.sleep(nanoseconds: 25_000_000) }
        XCTAssertEqual(agentLists(), 1, "The joined library publishes to agents after its first sync.")

        let controller = ServerAgentsController()
        await controller.load(model)
        XCTAssertEqual(controller.phase, .ready, "Agent Access lists the agents instead of loading forever.")
        XCTAssertEqual(controller.mcpURL, "https://journal.test/mcp")
    }
}
