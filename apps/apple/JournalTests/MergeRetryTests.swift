import JournalCore
import XCTest

@testable import Journal

/// Joining with this device's journals after something went wrong: access that can't be asked for again is kept for
/// Try Again and given up when the flow is left, consent is checked again when installing, and nothing is left
/// behind by a failed or interrupted attempt (docs/design/join-with-local-journals.md §2.7).
@MainActor
final class MergeRetryTests: XCTestCase {
    private let recoveryCode = String(repeating: "ab", count: 32)

    private func model(writing: Bool, encrypted: Bool) async throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MergeRetry-" + UUID().uuidString)
        let model = AppModel(directory: directory)
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            for account in [model.configuration?.keyID, model.configuration?.connectionKeyID].compactMap({ $0 }) {
                try? Keychain.remove(account)
            }
            try? FileManager.default.removeItem(at: directory)
        }
        await model.start(password: encrypted ? "this device's own password" : nil, encrypted: encrypted)
        if writing {
            await model.newEntry()
            _ = await model.finishPendingSave()
            try await model.refresh()
        }
        return model
    }
    private func stagedFolders(_ model: AppModel) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: model.directory.path).filter { $0.hasPrefix("vault-") }
    }
    private func settle(_ flow: ConnectionFlow) async throws {
        for _ in 0..<200 where flow.busy { try await Task.sleep(nanoseconds: 25_000_000) }
    }
    private func requests(_ server: FakeJournalServer, _ method: String, _ path: String) -> Int {
        server.requests.filter { $0.method == method && $0.path.hasPrefix(path) }.count
    }

    /// A server without encryption that hands out access for a one-time recovery code. It can't download
    /// (`sends: false`) or it downloads nothing and refuses what this device sends (`sends: true`).
    private func recoveryCodeServer(grant: DeviceGrant, sends: Bool) async throws -> FakeJournalServer {
        let parameters = try JournalCoding.encoder().encode(RecoveryParameters(RecoveryEnvelope.unprotected))
        let status = Data(#"{"protocolVersion":1,"initialized":true,"serverId":"fake-server"}"#.utf8)
        let recovered = try JournalCoding.encoder().encode(grant)
        let page = Data(#"{"changes":[],"cursor":0,"hasMore":false,"serverId":"fake-server","serverIdCursor":0}"#.utf8)
        return try await FakeJournalServer { request in
            switch (request.method, request.path) {
            case ("GET", "/v1/status"): return (200, status)
            case ("GET", "/v1/recovery"): return (200, parameters)
            case ("POST", "/v1/recovery"): return (200, recovered)
            case ("DELETE", _): return (204, Data())
            case ("GET", let path) where path.hasPrefix("/v1/sync/") && sends: return (200, page)
            default: return (503, Data("{}".utf8))
            }
        }
    }

    func testARecoveryCodeJoinKeepsItsAccessForTryAgainUntilTheFlowIsLeft() async throws {
        for sends in [false, true] {
            let model = try await model(writing: true, encrypted: false)
            let grant = DeviceGrant(deviceId: UUID(), token: String(repeating: "r", count: 64))
            let server = try await recoveryCodeServer(grant: grant, sends: sends)
            let before = try stagedFolders(model)
            let flow = ConnectionFlow(model: model)
            flow.address = server.address
            flow.check()
            try await settle(flow)
            XCTAssertEqual(flow.path, [.merge])
            flow.confirmMerge()
            flow.path = [.merge, .recoveryCode]
            flow.phrase = recoveryCode
            flow.signIn()
            try await settle(flow)
            XCTAssertEqual(
                flow.errorMessage(on: .recoveryCode),
                sends
                    ? "Couldn’t finish connecting. Your journals are still on this device, and some may already be on \(flow.host). Try again, or cancel to keep writing."
                    : "Couldn’t finish connecting. Your journals are still on this device. Try again, or cancel to keep writing.",
                "Only once sending started may some journals be on the server.")
            XCTAssertNotNil(model.retryGrant, "The one-time code's access is kept for Try Again.")
            XCTAssertEqual(requests(server, "DELETE", "/v1/devices/"), 0)
            XCTAssertEqual(
                try stagedFolders(model).count, before.count + (sends ? 1 : 0),
                "A copy that finished merging waits for Try Again; one that couldn't download was removed.")

            flow.signIn()
            try await settle(flow)
            XCTAssertEqual(requests(server, "POST", "/v1/recovery"), 1, "Try Again doesn't spend another code.")

            flow.cancel()
            for _ in 0..<100 where requests(server, "DELETE", "/v1/devices/") == 0 {
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            XCTAssertEqual(
                requests(server, "DELETE", "/v1/devices/\(grant.deviceId.uuidString.lowercased())"), 1,
                "Leaving the flow gives the access up.")
            XCTAssertNil(model.retryGrant)
            XCTAssertEqual(try stagedFolders(model), before)
            XCTAssertTrue(model.canEdit)
        }
    }

    func testAPairingGrantWaitsForTryAgainAndIsGivenUpWhenTheFlowIsLeft() async throws {
        let model = try await model(writing: true, encrypted: true)
        let key = try VaultCrypto.generateKey()
        let envelope = try VaultCrypto.makeRecovery(masterKey: key, phrase: "the server's password").0
        let published = try JournalCoding.encoder().encode(envelope)
        let status = Data(#"{"protocolVersion":1,"initialized":true,"serverId":"fake-server"}"#.utf8)
        let page = Data(#"{"changes":[],"cursor":0,"hasMore":false,"serverId":"fake-server","serverIdCursor":0}"#.utf8)
        // It downloads nothing and refuses what this device sends.
        let server = try await FakeJournalServer { request in
            switch (request.method, request.path) {
            case ("GET", "/v1/status"): return (200, status)
            case ("GET", "/v1/recovery"): return (200, published)
            case ("GET", let path) where path.hasPrefix("/v1/sync/"): return (200, page)
            case ("DELETE", _): return (204, Data())
            default: return (503, Data("{}".utf8))
            }
        }
        let deviceID = UUID()
        let before = try stagedFolders(model)
        do {
            try await model.installPairedVault(
                address: server.address, key: key, token: String(repeating: "p", count: 64), deviceID: deviceID,
                uploadLocal: true, recoveryVersion: envelope.formatVersion, shown: RecoveryParameters(envelope))
            XCTFail("The server can't synchronize.")
        } catch {}
        XCTAssertEqual(requests(server, "DELETE", "/v1/devices/"), 0, "Try Again uses the same access.")
        XCTAssertEqual(try stagedFolders(model).count, before.count + 1)
        await model.giveUpRetry()
        XCTAssertEqual(requests(server, "DELETE", "/v1/devices/\(deviceID.uuidString.lowercased())"), 1)
        XCTAssertEqual(try stagedFolders(model), before)
        XCTAssertTrue(model.canEdit)
    }

    func testWritingAfterTheServerWasCheckedStillAsksToMerge() async throws {
        let model = try await model(writing: false, encrypted: true)
        let envelope = try VaultCrypto.makeRecovery(masterKey: VaultCrypto.generateKey(), phrase: "password").0
        let parameters = try JournalCoding.encoder().encode(RecoveryParameters(envelope))
        let status = Data(#"{"protocolVersion":1,"initialized":true}"#.utf8)
        let server = try await FakeJournalServer { request in
            switch (request.method, request.path) {
            case ("GET", "/v1/status"): return (200, status)
            case ("GET", "/v1/recovery"): return (200, parameters)
            default: return (503, Data("{}".utf8))
            }
        }
        let flow = ConnectionFlow(model: model)
        flow.address = server.address
        flow.check()
        try await settle(flow)
        XCTAssertEqual(flow.path, [.signIn], "Nothing is written yet, so no Merge step.")
        // Meanwhile, in another window, the person writes an entry.
        await model.newEntry()
        _ = await model.finishPendingSave()
        try await model.refresh()
        flow.phrase = "password"
        flow.signIn()
        XCTAssertEqual(flow.path, [.merge], "Merge Journals comes first.")
        XCTAssertEqual(requests(server, "POST", "/v1/recovery"), 0, "Nothing was sent.")
        flow.close()
    }

    func testAConfigurationThatCantBeSavedLeavesNoSecretsBehind() async throws {
        let model = try await model(writing: false, encrypted: true)
        let previous = try XCTUnwrap(model.configuration)
        let accounts = ["merge-test-key-" + UUID().uuidString, "merge-test-connection-" + UUID().uuidString]
        for account in accounts { try Keychain.write(Data([1, 2, 3]), account: account) }
        var next = previous
        next.storageFolder = "vault-" + UUID().uuidString.lowercased()
        XCTAssertThrowsError(
            try model.commitConfiguration(next, writtenAccounts: accounts) {
                throw CocoaError(.fileWriteNoPermission)
            })
        for account in accounts { XCTAssertNil(try Keychain.read(account)) }
        XCTAssertEqual(model.configuration?.storageFolder, previous.storageFolder)
    }

    /// Makes a folder look untouched for two hours.
    private func age(_ folder: URL) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-7200)], ofItemAtPath: folder.path)
    }

    func testOnlyOldUnnamedCopiesAreRemoved() async throws {
        let model = try await model(writing: false, encrypted: true)
        var configuration = try XCTUnwrap(model.configuration)
        let names = ["superseded", "upgrade", "abandoned", "in-progress"].map { "vault-\($0)-" + UUID().uuidString }
        for name in names {
            let folder = model.directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if name != names[3] { try age(folder) }
        }
        configuration.supersededLibraries = [
            SupersededLibrary(storageFolder: names[0], keyID: nil, connectionKeyID: nil)
        ]
        configuration.encryptionUpgrade = EncryptionUpgradeMarker(
            storageFolder: names[1], keyID: "unused", recovery: configuration.recovery)
        model.configuration = configuration
        model.removeAbandonedCopies()
        let left = Set(try stagedFolders(model))
        XCTAssertTrue(left.isSuperset(of: [names[0], names[1]]), "Folders the configuration names are kept.")
        XCTAssertFalse(left.contains(names[2]), "An old copy nothing names is removed.")
        XCTAssertTrue(left.contains(names[3]), "A copy another instance may still be staging is kept.")
    }

    func testACopyLeftByAnInterruptedJoinIsRemovedAtLaunch() async throws {
        let model = try await model(writing: true, encrypted: true)
        let current = try XCTUnwrap(model.configuration?.storageFolder)
        let abandoned = "vault-" + UUID().uuidString.lowercased()
        let folder = model.directory.appendingPathComponent(abandoned)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("staged".utf8).write(to: folder.appendingPathComponent("journal.sqlite"))
        try Keychain.write(Data([4]), account: model.keyAccount + "-" + abandoned)
        try age(folder)
        try await model.store?.close()

        let reopened = AppModel(directory: model.directory)
        await reopened.load()
        addTeardownBlock { @MainActor in try? await reopened.store?.close() }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertNil(try Keychain.read(model.keyAccount + "-" + abandoned))
        XCTAssertEqual(try stagedFolders(reopened), [current], "The library itself is kept.")
        XCTAssertFalse(reopened.items.isEmpty)
    }
}
