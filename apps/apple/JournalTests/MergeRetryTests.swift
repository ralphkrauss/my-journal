import JournalCore
import XCTest

@testable import Journal

/// Joining with this device's journals after something went wrong: access that can't be asked for again is kept for
/// Try Again and given up when the flow is left, consent is checked again when installing, and nothing is left
/// behind by a failed or interrupted attempt (docs/design/join-with-local-journals.md §2.7).
@MainActor
final class MergeRetryTests: XCTestCase {
    private func model(writing: Bool) async throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MergeRetry-" + UUID().uuidString)
        let model = AppModel(directory: directory)
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            for account in [model.configuration?.keyID, model.configuration?.connectionKeyID].compactMap({ $0 }) {
                try? Keychain.remove(account)
            }
            try? FileManager.default.removeItem(at: directory)
        }
        await model.start(password: "this device's own password")
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

    func testAPairingGrantWaitsForTryAgainAndIsGivenUpWhenTheFlowIsLeft() async throws {
        let model = try await model(writing: true)
        let key = try VaultCrypto.generateKey()
        let envelope = try VaultCrypto.makeRecovery(masterKey: key, phrase: "the server's password").0
        let published = try JournalCoding.encoder().encode(envelope)
        let status = HealthyStatus.json(serverId: "fake-server")
        let page = Data(#"{"changes":[],"cursor":0,"hasMore":false,"serverId":"fake-server","serverIdCursor":0}"#.utf8)
        // It downloads nothing and refuses what this device sends.
        let server = try await FakeJournalServer { request in
            switch (request.method, request.path) {
            case ("GET", "/v1/status"): return (200, status)
            case ("GET", "/v1/agents/"): return (200, Data("[]".utf8))
            case ("GET", "/v1/recovery"): return (200, published)
            case ("GET", "/v1/recovery/envelope"): return (200, published)
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
        let model = try await model(writing: false)
        let envelope = try VaultCrypto.makeRecovery(masterKey: VaultCrypto.generateKey(), phrase: "password").0
        let parameters = try JournalCoding.encoder().encode(RecoveryParameters(envelope))
        let status = HealthyStatus.json()
        let server = try await FakeJournalServer { request in
            switch (request.method, request.path) {
            case ("GET", "/v1/status"): return (200, status)
            case ("GET", "/v1/agents/"): return (200, Data("[]".utf8))
            case ("GET", "/v1/recovery"): return (200, parameters)
            case ("GET", "/v1/recovery/envelope"): return (200, parameters)
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
        let model = try await model(writing: false)
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
        let model = try await model(writing: false)
        var configuration = try XCTUnwrap(model.configuration)
        let names = ["superseded", "abandoned", "in-progress"].map { "vault-\($0)-" + UUID().uuidString }
        for name in names {
            let folder = model.directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if name != names[2] { try age(folder) }
        }
        configuration.supersededLibraries = [
            SupersededLibrary(storageFolder: names[0], keyID: nil, connectionKeyID: nil)
        ]
        model.configuration = configuration
        model.removeAbandonedCopies()
        let left = Set(try stagedFolders(model))
        XCTAssertTrue(left.contains(names[0]), "A folder the configuration names is kept.")
        XCTAssertFalse(left.contains(names[1]), "An old copy nothing names is removed.")
        XCTAssertTrue(left.contains(names[2]), "A copy another instance may still be staging is kept.")
    }

    func testACopyLeftByAnInterruptedJoinIsRemovedAtLaunch() async throws {
        let model = try await model(writing: true)
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
