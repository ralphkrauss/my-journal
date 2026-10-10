import JournalCore
import XCTest
import os

@testable import Journal

/// Erase Journals and Settings (docs/design/erase-device-2026-10-04.md): the library, its Keychain items and its
/// configuration go, nothing else does, the server only hears this device signing out, and a failure before the
/// commit leaves the library as it was.
@MainActor final class EraseLibraryTests: XCTestCase {
    /// A sync server in memory that accepts everything and records what it's asked.
    private final class Server {
        private let log = OSAllocatedUnfairLock<[RemoteChange]>(initialState: [])
        private var server: FakeJournalServer?
        var address: String { server?.address ?? "" }
        var requests: [FakeJournalServer.Request] { server?.requests ?? [] }

        static func start() async throws -> Server {
            let result = Server()
            result.server = try await FakeJournalServer { [log = result.log] request in
                log.withLock { Self.answer(request, log: &$0) }
            }
            return result
        }
        private static func answer(_ request: FakeJournalServer.Request, log: inout [RemoteChange]) -> (
            status: Int, body: Data
        ) {
            switch (request.method, request.path) {
            case ("GET", "/v1/status"):
                return (200, HealthyStatus.json(serverId: "erase-server"))
            case ("GET", "/v1/recovery"):
                return (200, (try? JournalCoding.encoder().encode(RecoveryParameters(.placeholder))) ?? Data())
            case ("DELETE", _): return (204, Data())
            case ("HEAD", let path) where path.hasPrefix("/v1/attachments/"): return (404, Data())
            case ("PUT", let path) where path.hasPrefix("/v1/attachments/"): return (200, Data())
            case ("GET", let path) where path.hasPrefix("/v1/sync/?"):
                struct Page: Encodable {
                    let changes: [RemoteChange]
                    let cursor: Int64
                    let hasMore: Bool
                    let serverId: String
                    let serverIdCursor: Int64
                }
                let page = Page(
                    changes: [], cursor: Int64(log.count), hasMore: false, serverId: "erase-server", serverIdCursor: 0)
                return (200, (try? JournalCoding.encoder().encode(page)) ?? Data())
            case ("PUT", let path) where path.hasPrefix("/v1/sync/"):
                struct Push: Decodable {
                    let baseRevision: Int64
                    let kind: String
                    let payload: String
                }
                guard let push = try? JournalCoding.decoder().decode(Push.self, from: request.body),
                    let id = UUID(uuidString: String(path.dropFirst("/v1/sync/".count)))
                else { return (400, Data()) }
                let change = RemoteChange(
                    cursor: Int64(log.count + 1), recordId: id, revision: push.baseRevision + 1, kind: push.kind,
                    payload: push.payload, deviceId: UUID(), modifiedAt: Date())
                log.append(change)
                return (200, (try? JournalCoding.encoder().encode(change)) ?? Data())
            default: return (503, Data("{}".utf8))
            }
        }
    }

    private func library(connectedTo server: Server? = nil) async throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Erase-" + UUID().uuidString)
        let model = AppModel(directory: directory)
        // Erasing removes preference keys; never from the app's own preferences.
        model.preferences = UserDefaults(suiteName: "Erase-" + UUID().uuidString) ?? .standard
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            for account in [model.configuration?.keyID, model.configuration?.connectionKeyID].compactMap({ $0 }) {
                try? Keychain.remove(account)
            }
            try? FileManager.default.removeItem(at: directory)
        }
        await model.start()
        XCTAssertNotNil(model.store)
        if let server {
            let connection = SyncConnection(address: server.address, deviceID: UUID(), token: "synthetic-token")
            let account = try XCTUnwrap(model.configuration?.connectionKeyID)
            try Keychain.write(JournalCoding.encoder().encode(connection), account: account)
            model.connection = connection
            model.configureSync()
        }
        return model
    }

    private func exists(_ model: AppModel, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: model.directory.appendingPathComponent(name).path)
    }

    /// Waits, without blocking the main actor, until `condition` holds or two seconds have passed.
    private func wait(until condition: () -> Bool) async throws {
        for _ in 0..<80 where !condition() { try await Task.sleep(nanoseconds: 25_000_000) }
    }

    func testErasingRemovesTheLibraryItsKeysAndSettingsAndANewLibraryStarts() async throws {
        let server = try await Server.start()
        let model = try await library(connectedTo: server)
        let synced = await model.sync()
        XCTAssertTrue(synced)
        await model.createJournal("Work")
        let configuration = try XCTUnwrap(model.configuration)
        let folder = try XCTUnwrap(configuration.storageFolder)
        let deviceID = try XCTUnwrap(model.connection?.deviceID)
        // An earlier copy waiting for removal, leftovers of an import and an export, the files of the server earlier
        // Mac builds ran, and another library's Keychain item.
        let manager = FileManager.default
        for name in ["vault-earlier", "import-" + UUID().uuidString, "local-server-data"] {
            try manager.createDirectory(
                at: model.directory.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let export = "export-" + UUID().uuidString + ".journalarchive"
        try Data("archive".utf8).write(to: model.directory.appendingPathComponent(export))
        try Data("{}".utf8).write(to: model.directory.appendingPathComponent("local-server.json"))
        let earlierKey = "erase-test-earlier-" + UUID().uuidString
        let otherKey = "erase-test-other-" + UUID().uuidString
        try Keychain.write(Data("earlier".utf8), account: earlierKey)
        try Keychain.write(Data("other".utf8), account: otherKey)
        addTeardownBlock { try? Keychain.remove(otherKey) }
        model.configuration?.supersededLibraries = [
            SupersededLibrary(storageFolder: "vault-earlier", keyID: earlierKey)
        ]
        try model.persistConfiguration()
        let before = server.requests.count

        let found = await model.eraseWarning()
        let warning = try XCTUnwrap(found)
        XCTAssertEqual(warning, .unsent(count: 1, host: model.connectionHost), "the new journal wasn't sent")
        let outcome = await model.eraseLibrary(shown: warning)

        XCTAssertEqual(outcome, .erased)
        XCTAssertNil(model.configuration)
        XCTAssertNil(model.store)
        XCTAssertNil(model.connection)
        XCTAssertFalse(model.locked)
        XCTAssertTrue(model.items.isEmpty)
        for name in [LocalErasure.configurationName, folder, "vault-earlier", export] {
            XCTAssertFalse(exists(model, name), name)
        }
        XCTAssertFalse(
            try manager.contentsOfDirectory(atPath: model.directory.path).contains { $0.hasPrefix("import-") })
        // The server earlier Mac builds ran may hold the only copy of other devices' changes.
        XCTAssertTrue(exists(model, "local-server-data"))
        XCTAssertTrue(exists(model, "local-server.json"))
        for account in [configuration.keyID, configuration.connectionKeyID, earlierKey].compactMap({ $0 }) {
            XCTAssertNil(try Keychain.read(account), account)
        }
        XCTAssertNotNil(try Keychain.read(otherKey))
        try await wait {
            !((try? manager.contentsOfDirectory(atPath: model.directory.path)) ?? []).contains {
                $0.hasPrefix(LocalErasure.prefix)
            }
        }
        XCTAssertFalse(
            try manager.contentsOfDirectory(atPath: model.directory.path).contains { $0.hasPrefix(LocalErasure.prefix) }
        )

        // The server is only asked to sign this device out: nothing on it is deleted.
        try await wait { server.requests.dropFirst(before).contains { $0.method == "DELETE" } }
        let after = server.requests.dropFirst(before).map { "\($0.method) \($0.path)" }
        XCTAssertTrue(after.contains("DELETE /v1/devices/\(deviceID.uuidString.lowercased())"), "\(after)")
        // Reads that were under way may finish; nothing is written or deleted but this device's access.
        XCTAssertEqual(
            after.filter { !$0.hasPrefix("GET ") }, ["DELETE /v1/devices/\(deviceID.uuidString.lowercased())"])

        await model.start()
        XCTAssertNotNil(model.store)
        XCTAssertNil(model.connection)
        XCTAssertEqual(model.journals.map(\.title), ["Default"])
        XCTAssertNotEqual(model.configuration?.keyID, configuration.keyID)
        XCTAssertNotNil(model.configuration?.connectionKeyID, "a new library names its own connection item")
    }

    /// The warning says what only this device has: nothing in a new library, everything without a server, what the
    /// server hasn't accepted, or that it can't be confirmed after a failed or missing sync.
    func testTheWarningSaysWhatOnlyThisDeviceHas() async throws {
        let alone = try await library()
        let empty = await alone.eraseWarning()
        XCTAssertEqual(empty, .nothingWritten)
        await alone.createJournal("Work")
        let written = await alone.eraseWarning()
        XCTAssertEqual(written, .notSyncing)

        let server = try await Server.start()
        let connected = try await library(connectedTo: server)
        let host = connected.connectionHost
        let neverSynced = await connected.eraseWarning()
        XCTAssertEqual(neverSynced, .unconfirmed(host: host))
        let syncedOnce = await connected.sync()
        XCTAssertTrue(syncedOnce)
        let synced = await connected.eraseWarning()
        XCTAssertEqual(synced, .onServer(host: host))
        await connected.createJournal("Work")
        let waiting = await connected.eraseWarning()
        XCTAssertEqual(waiting, .unsent(count: 1, host: host))
        connected.syncFailed = true
        let failed = await connected.eraseWarning()
        XCTAssertEqual(failed, .unconfirmed(host: host))
    }

    /// Writing after the alert was shown (in another window) stops the erase, so nothing is lost unannounced.
    func testMoreToLoseThanShownStopsTheErase() async throws {
        let model = try await library()
        let found = await model.eraseWarning()
        let shown = try XCTUnwrap(found)
        XCTAssertEqual(shown, .nothingWritten)
        await model.createJournal("Written meanwhile")
        let outcome = await model.eraseLibrary(shown: shown)
        XCTAssertEqual(outcome, .changed(.notSyncing))
        XCTAssertNotNil(model.configuration)
        XCTAssertFalse(model.vaultReplacement)
        XCTAssertTrue(exists(model, LocalErasure.configurationName))
    }

    /// When the configuration can't be moved, nothing is removed: the library opens again with its key.
    func testAFailureBeforeTheCommitLeavesTheLibraryAsItWas() async throws {
        let model = try await library()
        await model.createJournal("Keep me")
        let configuration = try XCTUnwrap(model.configuration)
        let keyID = try XCTUnwrap(configuration.keyID)
        // The data folder refuses new files, so the erase's own folder can't be made.
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: model.directory.path)
        let restore = model.directory.path
        addTeardownBlock { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: restore) }

        let found = await model.eraseWarning()
        let shown = try XCTUnwrap(found)
        let outcome = await model.eraseLibrary(shown: shown)
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: model.directory.path)

        XCTAssertEqual(outcome, .failed)
        XCTAssertFalse(model.vaultReplacement)
        XCTAssertNotNil(model.store)
        XCTAssertNotNil(try Keychain.read(keyID))
        XCTAssertTrue(exists(model, LocalErasure.configurationName))
        XCTAssertTrue(exists(model, try XCTUnwrap(configuration.storageFolder)))
        let reopened = AppModel(directory: model.directory)
        try? await model.store?.close()
        await reopened.load()
        XCTAssertNotNil(reopened.store)
        XCTAssertTrue(reopened.journals.contains { $0.title == "Keep me" })
        try? await reopened.store?.close()
    }

    /// An erase interrupted after its commit is finished at the next launch, before anything is read, and never
    /// touches the library created since.
    func testAnInterruptedEraseIsFinishedAtTheNextLaunch() async throws {
        let model = try await library()
        let erased = try XCTUnwrap(model.configuration)
        let list = model.erasureList(erased)
        try? await model.store?.close()
        // Committed, then stopped before anything else.
        _ = try LocalErasure.commit(list, in: model.directory)

        let relaunched = AppModel(directory: model.directory)
        await relaunched.load()
        XCTAssertNil(relaunched.configuration)
        await relaunched.start()
        let current = try XCTUnwrap(relaunched.configuration)
        addTeardownBlock { @MainActor in
            try? await relaunched.store?.close()
            for account in [current.keyID, current.connectionKeyID].compactMap({ $0 }) { try? Keychain.remove(account) }
        }
        for account in [erased.keyID].compactMap({ $0 }) { XCTAssertNil(try Keychain.read(account)) }
        XCTAssertFalse(exists(model, try XCTUnwrap(erased.storageFolder)))
        XCTAssertNotNil(try Keychain.read(try XCTUnwrap(current.keyID)))
        XCTAssertTrue(exists(relaunched, try XCTUnwrap(current.storageFolder)))
        try await wait {
            !((try? FileManager.default.contentsOfDirectory(atPath: model.directory.path)) ?? []).contains {
                $0.hasPrefix(LocalErasure.prefix)
            }
        }
        XCTAssertNotNil(relaunched.store)
    }

    func testACancelledAuthenticationErasesNothing() async throws {
        let model = try await library()
        await model.turnOnAppLockForTesting()
        let owner = TestDeviceOwner()
        owner.outcome = .cancelled
        model.deviceOwner = owner
        let found = await model.eraseWarning()
        let shown = try XCTUnwrap(found)
        let outcome = await model.eraseLibrary(shown: shown)
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(owner.requests, 1)
        XCTAssertNotNil(model.configuration)
        XCTAssertTrue(exists(model, LocalErasure.configurationName))
    }
}
