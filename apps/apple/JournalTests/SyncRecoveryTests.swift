import JournalCore
import XCTest
import os

@testable import Journal

/// A journal server in memory over loopback HTTP, enough for a library to sync, lose access, and be set up or
/// joined again (docs/design/sync-health-and-recovery.md).
private final class LibraryServer {
    struct State {
        var initialized = true
        var serverID = "server-one"
        /// Answers every authenticated request but the status with 401, as for a removed device.
        var refusesDevices = false
        var parameters = (try? JournalCoding.encoder().encode(RecoveryParameters(.unprotected))) ?? Data()
        var grant = DeviceGrant(deviceId: UUID(), token: String(repeating: "g", count: 64))
        var log: [RemoteChange] = []
        /// Refuses every image as too large, as a server behind a proxy with a small upload limit does.
        var refusesImages = false
        /// Another web server answers at the address.
        var impostor = false
        /// A server from before protocol revision 1: no revision, and 12 of the 13 capability names.
        var tooOld = false
    }
    let state = OSAllocatedUnfairLock(initialState: State())
    private var server: FakeJournalServer?

    static func start() async throws -> LibraryServer {
        let library = LibraryServer()
        library.server = try await FakeJournalServer { [state = library.state] request in
            state.withLock { Self.answer(request, state: &$0) }
        }
        return library
    }
    var address: String { server?.address ?? "" }
    var requests: [FakeJournalServer.Request] { server?.requests ?? [] }
    func update(_ change: @Sendable (inout State) -> Void) { state.withLock { change(&$0) } }

    private static func answer(_ request: FakeJournalServer.Request, state: inout State) -> (status: Int, body: Data) {
        let json = { (text: String) in Data(text.utf8) }
        if state.impostor { return (404, json("<html>Not found</html>")) }
        switch (request.method, request.path) {
        case ("GET", "/v1/status") where state.tooOld:
            let names = ServerStatus.revisionOneFeatures.dropLast().map { "\"\($0)\"" }.joined(separator: ",")
            return (
                200,
                json(
                    #"{"protocolVersion":1,"initialized":true,"features":[\#(names)],"serverId":"\#(state.serverID)"}"#)
            )
        case ("GET", "/v1/status"):
            return (200, HealthyStatus.json(serverId: state.serverID, initialized: state.initialized))
        case ("GET", "/v1/recovery"): return (200, state.parameters)
        case ("POST", "/v1/setup"):
            state.initialized = true
            return (200, (try? JournalCoding.encoder().encode(state.grant)) ?? Data())
        case ("POST", "/v1/recovery"):
            return (200, (try? JournalCoding.encoder().encode(state.grant)) ?? Data())
        case ("DELETE", _): return (204, Data())
        case ("PUT", let path) where path.hasPrefix("/v1/attachments/") && state.refusesImages: return (413, Data())
        case ("HEAD", let path) where path.hasPrefix("/v1/attachments/"): return (404, Data())
        case (_, _) where state.refusesDevices: return (401, json(#"{"code":"unauthorized"}"#))
        case ("GET", "/v1/devices/"): return (401, json(#"{"code":"unauthorized"}"#))
        case ("GET", let path) where path.hasPrefix("/v1/sync/?"): return (200, page(path, state: state))
        case ("PUT", let path) where path.hasPrefix("/v1/sync/"): return accept(request, state: &state)
        default: return (503, json("{}"))
        }
    }
    private static func page(_ path: String, state: State) -> Data {
        let after =
            URLComponents(string: path)?.queryItems?.first { $0.name == "after" }?.value.flatMap(Int64.init) ?? 0
        let changes = state.log.filter { $0.cursor > after }
        struct Page: Encodable {
            let changes: [RemoteChange]
            let cursor: Int64
            let hasMore: Bool
            let serverId: String
            let serverIdCursor: Int64
        }
        let page = Page(
            changes: changes, cursor: changes.last?.cursor ?? after, hasMore: false, serverId: state.serverID,
            serverIdCursor: 0)
        return (try? JournalCoding.encoder().encode(page)) ?? Data()
    }
    private static func accept(_ request: FakeJournalServer.Request, state: inout State) -> (status: Int, body: Data) {
        struct Push: Decodable {
            let baseRevision: Int64
            let kind: String
            let payload: String
        }
        guard let push = try? JournalCoding.decoder().decode(Push.self, from: request.body),
            let id = UUID(uuidString: String(request.path.dropFirst("/v1/sync/".count)))
        else { return (400, Data()) }
        let change = RemoteChange(
            cursor: Int64(state.log.count + 1), recordId: id, revision: push.baseRevision + 1, kind: push.kind,
            payload: push.payload, deviceId: state.grant.deviceId, modifiedAt: Date())
        state.log.append(change)
        return (200, (try? JournalCoding.encoder().encode(change)) ?? Data())
    }
}

@MainActor
final class SyncRecoveryTests: XCTestCase {
    private func library(address: String, encrypted: Bool = false) async throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SyncRecovery-" + UUID().uuidString)
        let model = AppModel(directory: directory)
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            for account in [model.configuration?.keyID, model.configuration?.connectionKeyID].compactMap({ $0 }) {
                try? Keychain.remove(account)
            }
            try? FileManager.default.removeItem(at: directory)
        }
        await model.start(password: encrypted ? "this device's own password" : nil, encrypted: encrypted)
        let connection = SyncConnection(address: address, deviceID: UUID(), token: "synthetic-token")
        let account = "SyncRecoveryTests-" + UUID().uuidString
        try Keychain.write(JournalCoding.encoder().encode(connection), account: account)
        model.configuration?.connectionKeyID = account
        model.connection = connection
        model.configureSync()
        return model
    }
    private func settle(_ flow: ConnectionFlow, until done: () -> Bool = { true }) async throws {
        for _ in 0..<200 where flow.busy || !done() { try await Task.sleep(nanoseconds: 25_000_000) }
    }
    /// Lets automatic sync run for `seconds`, then stops it as leaving the foreground does.
    private func runAutomaticSync(_ model: AppModel, for seconds: Double) async throws {
        let running = Task { await model.synchronizeAutomatically() }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        running.cancel()
        await running.value
    }

    /// A server below protocol revision 1 is a gate and nothing else (docs/design/1-1-server-cleanup.md §3.5): every
    /// place that needs the server says the same thing, nothing queued is lost or sent, and syncing resumes by itself
    /// once the server is updated.
    func testAServerThatNeedsAnUpdateIsRefusedEverywhereWithOneMessageAndNothingIsLost() async throws {
        let message = "This server needs an update before this device can connect."
        let server = try await LibraryServer.start()
        let model = try await library(address: server.address, encrypted: true)
        let envelope = try XCTUnwrap(model.configuration?.recovery)
        server.update { $0.parameters = (try? JournalCoding.encoder().encode(RecoveryParameters(envelope))) ?? Data() }
        await model.sync()
        XCTAssertNil(model.syncHealth)
        let store = try XCTUnwrap(model.store)
        try await store.save(JournalItem(kind: "entry", journalID: UUID(), document: .plain("Written meanwhile")))
        let queued = try await store.pending().map(\.operationId)
        XCTAssertFalse(queued.isEmpty)
        let identity = try await store.syncedServerID()
        let pushes = { server.requests.filter { $0.method == "PUT" }.count }
        let before = pushes()

        server.update { $0.tooOld = true }
        await model.sync()
        XCTAssertEqual(model.syncHealth, .serverUpdateNeeded)
        XCTAssertEqual(
            model.syncError,
            "The server needs an update before this device can sync. Your changes are saved on this device.")
        XCTAssertEqual(pushes(), before, "Nothing is sent to it")

        // Connect to a Server stops on its first page and asks nothing else.
        let requestsBefore = server.requests.count
        let flow = ConnectionFlow(model: model)
        flow.address = server.address
        flow.check()
        try await settle(flow)
        XCTAssertEqual(flow.errorMessage(on: nil), message)
        XCTAssertTrue(flow.path.isEmpty)
        XCTAssertEqual(server.requests.dropFirst(requestsBefore).map(\.path), ["/v1/status"])
        flow.close()

        // Change Password and Agent Access say the same.
        do {
            _ = try await model.preparePasswordChange(current: "this device's own password", new: "another password")
            XCTFail("A server that needs an update isn't asked to change the password")
        } catch let refusal as ServerRefusal {
            XCTAssertEqual(refusal.localizedDescription, message)
        }
        let agents = ServerAgentsController()
        await agents.load(model)
        XCTAssertEqual(agents.phase, .needsUpdate(.serverNeedsUpdate))

        // Nothing changed on this device.
        let kept = try await (store.pending().map(\.operationId), store.syncedServerID())
        XCTAssertEqual(kept.0, queued)
        XCTAssertEqual(kept.1, identity)

        // Once the server is updated, the next sync sends the work with no other action.
        server.update { $0.tooOld = false }
        await model.sync()
        XCTAssertNil(model.syncHealth)
        XCTAssertGreaterThan(pushes(), before)
        let remaining = try await store.pending()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testAResetServerOffersReconnectAndStopsAskingIt() async throws {
        let server = try await LibraryServer.start()
        server.update { $0.initialized = false }
        let model = try await library(address: server.address)

        await model.sync()
        XCTAssertEqual(model.syncHealth, .serverNotSetUp)
        XCTAssertEqual(model.syncError, "The server isn’t set up. Your journals are still on this device.")
        XCTAssertEqual(model.syncStatusAction, .reconnect)
        XCTAssertEqual(
            server.requests.map(\.path), ["/v1/status"], "Nothing else is asked of a server that isn't set up")

        model.syncWhenWritingPauses()
        try await runAutomaticSync(model, for: 3)
        XCTAssertEqual(server.requests.count, 1, "Neither writing nor automatic sync asks again")

        model.syncTiming.stoppedCheckAt = Date().addingTimeInterval(-AppModel.stoppedCheckInterval - 1)
        try await runAutomaticSync(model, for: 1.5)
        XCTAssertEqual(server.requests.count, 2, "Becoming active after a while checks once")

        // Reconnect… goes straight to the setup-code step at this device's server.
        XCTAssertTrue(model.reconnectsOnConnect)
        let flow = ConnectionFlow(model: model)
        flow.address = server.address
        flow.check()
        try await settle(flow)
        XCTAssertEqual(flow.path, [.setUpServer])
        flow.close()
    }

    func testReconnectingToAResetServerReplacesTheOldConnectionEntirely() async throws {
        let server = try await LibraryServer.start()
        server.update { $0.initialized = false }
        let model = try await library(address: server.address)
        let oldAccount = try XCTUnwrap(model.configuration?.connectionKeyID)

        try await model.initializeServer(address: server.address, code: "ABC-234", phrase: "", uploadLocal: true)

        XCTAssertEqual(model.connection?.deviceID, server.state.withLock { $0.grant.deviceId })
        XCTAssertNil(try Keychain.read(oldAccount), "The connection it replaced leaves nothing behind")
        let account = try XCTUnwrap(model.configuration?.connectionKeyID)
        XCTAssertNotNil(try Keychain.read(account))
    }

    func testReconnectAsksToMergeOnlyOnceAccessShowsAnotherLibrary() async throws {
        let server = try await LibraryServer.start()
        let password = "the other library's password"
        let envelope = try VaultCrypto.makeRecovery(masterKey: VaultCrypto.generateKey(), phrase: password).0
        server.update {
            $0.refusesDevices = true
            $0.serverID = "another-library"
            $0.parameters = (try? JournalCoding.encoder().encode(RecoveryParameters(envelope))) ?? Data()
        }
        let model = try await library(address: server.address)
        await model.sync()
        XCTAssertEqual(model.syncStatusAction, .reconnect)
        let folders = { () throws -> [String] in
            try FileManager.default.contentsOfDirectory(atPath: model.directory.path).filter { $0.hasPrefix("vault-") }
        }
        let before = try folders()

        let flow = ConnectionFlow(model: model)
        flow.address = server.address
        flow.check()
        try await settle(flow)
        XCTAssertEqual(flow.path, [.signIn], "A connected library signs in first")
        flow.phrase = password
        flow.signIn()
        try await settle(flow) { flow.path.last == .merge }

        XCTAssertEqual(flow.path, [.signIn, .merge], "The server holds another library, so Merge Journals asks first")
        let grant = server.state.withLock { $0.grant.deviceId.uuidString.lowercased() }
        XCTAssertTrue(
            server.requests.contains { $0.method == "DELETE" && $0.path == "/v1/devices/\(grant)" },
            "The access received before asking is given up; signing in again asks for new access")
        XCTAssertFalse(server.requests.contains { $0.method == "PUT" }, "Nothing is sent before Merge")
        XCTAssertEqual(try folders(), before)
        XCTAssertEqual(model.connection?.token, "synthetic-token")
        flow.cancel()
        XCTAssertNil(model.agreedMergeHost)
    }

    /// Back from Merge Journals gives up the access obtained before it asked, so the person is asked for a new one
    /// instead of the step reusing a spent one-time code (docs/design/sync-health-and-recovery.md §3.2).
    func testBackFromMergeJournalsGivesUpTheAccessAndAsksForANewRecoveryCode() async throws {
        let server = try await LibraryServer.start()
        server.update {
            $0.refusesDevices = true
            $0.serverID = "another-library"
        }
        let model = try await library(address: server.address)
        let flow = ConnectionFlow(model: model)
        flow.address = server.address
        flow.check()
        try await settle(flow)
        flow.path = [.addThisDevice, .recoveryCode]
        let code = String(repeating: "ab", count: 32)
        let requests = { (method: String, prefix: String) in
            server.requests.filter { $0.method == method && $0.path.hasPrefix(prefix) }.count
        }
        flow.phrase = code
        flow.signIn()
        try await settle(flow) { flow.path.last == .merge }
        XCTAssertEqual(flow.path, [.addThisDevice, .recoveryCode, .merge])
        XCTAssertNotNil(model.retryGrant, "The one-time code's access waits for the person to agree.")
        XCTAssertEqual(requests("POST", "/v1/recovery"), 1)
        XCTAssertEqual(requests("DELETE", "/v1/devices/"), 0)

        flow.path.removeLast()
        for _ in 0..<100 where requests("DELETE", "/v1/devices/") == 0 { try await Task.sleep(nanoseconds: 25_000_000) }
        XCTAssertEqual(requests("DELETE", "/v1/devices/"), 1, "Back gives the access up.")
        XCTAssertNil(model.retryGrant)
        XCTAssertEqual(flow.phrase, "", "The spent code isn't left in the field.")
        XCTAssertEqual(flow.codeUsedNotice, "That code was used. Enter a new one.")
        XCTAssertEqual(flow.path, [.addThisDevice, .recoveryCode])
        flow.phrase = "typing a new code"
        XCTAssertNil(flow.codeUsedNotice, "The line stays only until a new code is typed.")

        flow.phrase = code
        flow.signIn()
        try await settle(flow) { flow.path.last == .merge }
        XCTAssertEqual(requests("POST", "/v1/recovery"), 2, "A new code is spent, not the old access reused.")
        flow.close()
    }

    /// The password step starts again too: nothing typed stays, and nothing is said about a wrong password.
    func testBackFromMergeJournalsClearsThePasswordWithoutAnError() async throws {
        let server = try await LibraryServer.start()
        let password = "the other library's password"
        let envelope = try VaultCrypto.makeRecovery(masterKey: VaultCrypto.generateKey(), phrase: password).0
        server.update {
            $0.refusesDevices = true
            $0.serverID = "another-library"
            $0.parameters = (try? JournalCoding.encoder().encode(RecoveryParameters(envelope))) ?? Data()
        }
        let model = try await library(address: server.address)
        let flow = ConnectionFlow(model: model)
        flow.address = server.address
        flow.check()
        try await settle(flow)
        flow.phrase = password
        flow.signIn()
        try await settle(flow) { flow.path.last == .merge }
        XCTAssertEqual(flow.path, [.signIn, .merge])

        flow.path.removeLast()
        XCTAssertEqual(flow.path, [.signIn])
        XCTAssertEqual(flow.phrase, "")
        XCTAssertNil(flow.errorMessage(on: .signIn))
        XCTAssertNil(flow.codeUsedNotice)
        flow.phrase = password
        flow.signIn()
        try await settle(flow) { flow.path.last == .merge }
        XCTAssertEqual(flow.path, [.signIn, .merge], "Signing in asks for Merge Journals again.")
        flow.close()
    }

    func testTheSameLibraryRejoinsByIdentityAndAnotherOnlyWithAgreement() async throws {
        let server = try await LibraryServer.start()
        let model = try await library(address: server.address)
        await model.sync()
        XCTAssertNil(model.syncHealth)
        let ownKey = try XCTUnwrap(model.masterKey)
        let grant = server.state.withLock { $0.grant }

        // Without a password on the server, a new key means nothing: the library's records decide.
        let same = try await model.joinPlan(
            address: server.address, key: VaultCrypto.generateKey(), protection: .plaintext, grant: grant,
            uploadLocal: true)
        XCTAssertFalse(same.merges)
        XCTAssertEqual(same.key, ownKey, "The library keeps its key and its records as they are")

        // An empty server, as after encryption was turned on elsewhere and before that device sent its copy, combines
        // nothing: the library joins it by identity.
        server.update {
            $0.serverID = "another-identity"
            $0.log = []
        }
        let empty = try await model.joinPlan(
            address: server.address, key: VaultCrypto.generateKey(), protection: .plaintext, grant: grant,
            uploadLocal: true)
        XCTAssertFalse(empty.merges)

        server.update {
            $0.serverID = "another-library"
            $0.log = [
                RemoteChange(
                    cursor: 1, recordId: UUID(), revision: 1, kind: "entry", payload: "another library's entry",
                    deviceId: UUID(), modifiedAt: Date())
            ]
        }
        do {
            _ = try await model.joinPlan(
                address: server.address, key: VaultCrypto.generateKey(), protection: .plaintext, grant: grant,
                uploadLocal: true)
            XCTFail("Another library merges only after Merge Journals")
        } catch {
            XCTAssertTrue(error is MergeConsentNeeded, "\(error)")
        }
        model.agreedMergeHost = ServerAddress.host(server.address)
        let other = try await model.joinPlan(
            address: server.address, key: VaultCrypto.generateKey(), protection: .plaintext, grant: grant,
            uploadLocal: true)
        XCTAssertTrue(other.merges)
    }

    /// While another app is active, as with My Journal's window behind others on a Mac, automatic sync asks the server
    /// every 30 seconds instead of every 3; becoming active again syncs at once.
    func testAutomaticSyncSlowsWhileAnotherAppIsActiveAndCatchesUpOnReturning() async throws {
        let server = try await LibraryServer.start()
        let model = try await library(address: server.address)
        await model.sync()
        model.applicationActive = false
        XCTAssertEqual(model.nextSyncDelay(afterFailures: 0), AppModel.inactiveSyncInterval)
        let pages = { server.requests.filter { $0.path.hasPrefix("/v1/sync/?") }.count }
        let before = pages()
        let running = Task { await model.synchronizeAutomatically() }
        defer { running.cancel() }
        for _ in 0..<100 where pages() == before { try await Task.sleep(nanoseconds: 20_000_000) }
        try await Task.sleep(nanoseconds: 4_200_000_000)
        XCTAssertEqual(pages(), before + 1, "Nothing more is asked after the usual 3 seconds")

        model.applicationActive = true
        for _ in 0..<30 where pages() == before + 1 { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertEqual(pages(), before + 2, "Becoming active syncs without waiting")
    }

    func testWaitsFollowTheServerAndEndWhenTheNetworkReturns() async throws {
        let server = try await FakeJournalServer { _ in (503, Data("{}".utf8)) }
        let model = try await library(address: server.address)
        model.recordSyncHealth(.unavailable, failure: ServerRateLimited(retryAfter: 120))
        XCTAssertEqual(model.nextSyncDelay(afterFailures: 1), 120, "A server that limited requests is given its time")
        model.recordSyncHealth(.certificateInvalid, failure: URLError(.serverCertificateUntrusted))
        XCTAssertEqual(model.nextSyncDelay(afterFailures: 1), 300, "A server being fixed is checked every 5 minutes")
        model.recordSyncHealth(nil, failure: nil)

        let running = Task { await model.synchronizeAutomatically() }
        defer { running.cancel() }
        for _ in 0..<100 where server.requests.isEmpty { try await Task.sleep(nanoseconds: 20_000_000) }
        try await Task.sleep(nanoseconds: 300_000_000)
        let afterFirst = server.requests.count
        model.syncTiming.networkReturn.update(available: false)
        model.syncTiming.networkReturn.update(available: true)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertGreaterThan(server.requests.count, afterFirst, "The network returning ends the 6 second wait")
    }

    /// Changes that wait while sync works, or while it retries by itself, stay out of sight. Sync failing while
    /// changes wait more than a day asks for attention, measured from the last sync, or from the first failure when
    /// none succeeded yet.
    func testChangesWaitingMoreThanADayWhileSyncFailsAreFlagged() async throws {
        let model = try await library(address: "http://127.0.0.1:9")
        await model.sync()
        XCTAssertEqual(model.syncHealth?.kind, .temporary)
        model.pendingSync = true
        let failedAt = try XCTUnwrap(model.syncTiming.failingSince)
        XCTAssertNil(model.syncActivity.lastSynced)
        model.updateSyncLongWait(now: failedAt.addingTimeInterval(3600))
        XCTAssertFalse(model.showsSyncStatus, "Retrying by itself")
        model.updateSyncLongWait(now: failedAt.addingTimeInterval(24 * 3600 + 60))
        XCTAssertTrue(model.showsSyncStatus, "Never synced, failing for more than a day")

        let now = Date(timeIntervalSince1970: 1_790_000_000)
        model.syncActivity.synced(at: now.addingTimeInterval(-(23 * 3600 + 59 * 60)))
        model.updateSyncLongWait(now: now)
        XCTAssertFalse(model.showsSyncStatus, "23 hours 59 minutes isn't a day yet")
        model.syncActivity.synced(at: now.addingTimeInterval(-(24 * 3600 + 60)))
        model.updateSyncLongWait(now: now)
        XCTAssertTrue(model.showsSyncStatus)
        XCTAssertFalse(model.syncNeedsAttention, "Flagged for the wait, not for the state")
        model.pendingSync = false
        model.updateSyncLongWait(now: now)
        XCTAssertFalse(model.showsSyncStatus, "Nothing waits, so nothing is flagged")

        // At launch, changes from days ago wait only until the first sync: no failure, no flag.
        model.pendingSync = true
        model.recordSyncHealth(nil, failure: nil)
        model.syncError = nil
        model.syncFailed = false
        model.updateSyncLongWait(now: now)
        XCTAssertNil(model.syncTiming.failingSince)
        XCTAssertFalse(model.showsSyncStatus)
    }

    /// Syncing normally and Temporary problems stay out of sight, however many changes wait; every other state, and a
    /// record the server refused, shows Sync Status.
    func testOnlyStatesThatNeedThePersonAskForAttention() async throws {
        let model = try await library(address: "http://127.0.0.1:9")
        model.pendingSync = true
        let states: [SyncHealth] = [
            .offline, .unreachable, .unavailable, .signInNeeded, .serverNotSetUp, .serverReplaced, .accessRemoved,
            .appUpdateNeeded, .serverUpdateNeeded, .certificateInvalid, .notJournalServer, .localDataUnreadable,
            .localDataUnavailable, .unexpected,
        ]
        for state in states {
            model.syncHealth = state
            model.syncError = state.message()
            let quiet = [.offline, .unreachable, .unavailable, .localDataUnavailable].contains(state)
            XCTAssertEqual(model.syncNeedsAttention, !quiet, "\(state)")
            XCTAssertEqual(model.showsSyncStatus, !quiet, "\(state)")
        }
        model.syncHealth = nil
        model.syncError = nil
        XCTAssertFalse(model.syncNeedsAttention, "Syncing normally")
        XCTAssertFalse(model.showsSyncStatus, "Changes waiting while syncing normally")
        model.syncError = "Your server didn’t accept “Notes”. It’s saved on this device. Edit it to try again."
        XCTAssertTrue(model.syncNeedsAttention, "A refused record")
        XCTAssertTrue(model.showsSyncStatus)
        model.connection = nil
        XCTAssertFalse(model.showsSyncStatus, "Without a server there's nothing to sync")
    }

    /// The action follows the state the last sync found, and nothing else: after Reconnect… was offered for one state,
    /// a reset server offers it for another, and a server that works again offers Sync Now with a quiet symbol.
    func testTheActionFollowsOnlyTheCurrentState() async throws {
        let server = try await LibraryServer.start()
        let model = try await library(address: server.address)
        await model.sync()
        XCTAssertNil(model.syncHealth)
        let encrypted = try JournalCoding.encoder().encode(
            RecoveryParameters(try VaultCrypto.makeRecovery(masterKey: VaultCrypto.generateKey(), phrase: "password").0)
        )
        let plain = try JournalCoding.encoder().encode(RecoveryParameters(.unprotected))
        let replacedByEncrypted: @Sendable (inout LibraryServer.State) -> Void = {
            $0.serverID = "an-encrypted-library"
            $0.parameters = encrypted
            $0.refusesDevices = true
        }
        server.update(replacedByEncrypted)
        await model.sync()
        XCTAssertEqual(model.syncHealth, .signInNeeded)
        XCTAssertEqual(model.syncStatusAction, .reconnect)

        server.update { $0.initialized = false }
        await model.sync()
        XCTAssertEqual(model.syncHealth, .serverNotSetUp)
        XCTAssertEqual(model.syncStatusAction, .reconnect)

        server.update {
            $0.initialized = true
            $0.serverID = "another-library"
            $0.parameters = plain
        }
        await model.syncNow()
        XCTAssertEqual(model.syncHealth, .serverReplaced)
        XCTAssertEqual(model.syncStatusAction, .reconnect)

        server.update { $0.serverID = "server-one" }
        await model.syncNow()
        XCTAssertEqual(model.syncHealth, .accessRemoved)
        XCTAssertEqual(model.syncStatusAction, .reconnect)

        server.update(replacedByEncrypted)
        await model.syncNow()
        XCTAssertEqual(model.syncStatusAction, .reconnect)
        server.update {
            $0.serverID = "server-one"
            $0.parameters = plain
            $0.refusesDevices = false
        }
        await model.syncNow()
        XCTAssertNil(model.syncHealth)
        XCTAssertEqual(model.syncStatusAction, .syncNow)
        XCTAssertFalse(model.encryption.offersSignIn)
        XCTAssertFalse(model.syncNeedsAttention)
        XCTAssertFalse(model.showsSyncStatus)
    }

    /// One Reconnect… for every state in which the server doesn't accept this device as it is, and only that action
    /// opens the connection sheet.
    func testEveryStateThatNeedsAReconnectOffersTheSameAction() async throws {
        let model = try await library(address: "http://127.0.0.1:9")
        let states: [SyncHealth] = [
            .signInNeeded, .serverNotSetUp, .serverReplaced, .accessRemoved, .offline, .unreachable, .unavailable,
            .appUpdateNeeded, .serverUpdateNeeded, .certificateInvalid, .notJournalServer, .localDataUnreadable,
            .localDataUnavailable, .unexpected,
        ]
        for state in states {
            model.syncHealth = state
            let reconnects = [.needsYou, .serverChanged, .noAccess].contains(state.kind)
            XCTAssertEqual(model.syncStatusAction == .reconnect, reconnects, "\(state)")
            XCTAssertEqual(model.syncStatusAction.connects, reconnects, "\(state)")
            XCTAssertEqual(model.serverRefusesThisDevice, reconnects, "\(state)")
        }
        let others: [SyncStatusAction] = [.syncNow, .tryAgain, .checkAgain]
        XCTAssertEqual(others.filter(\.connects), [])
        XCTAssertEqual(SyncStatusAction.reconnect.title, "Reconnect…")
    }

    /// Devices has nothing to show once the server refuses this device, and the Server section says why: the state a
    /// sync found, or "no longer has access" when the device list was refused before any sync could say.
    func testARefusedDeviceListLearnsWhyFromTheSyncAndFallsBackToRemoved() async throws {
        let server = try await LibraryServer.start()
        let model = try await library(address: server.address)
        await model.sync()
        XCTAssertFalse(model.serverRefusesThisDevice)

        server.update { $0.refusesDevices = true }
        await model.learnWhyAccessWasRefused()
        XCTAssertEqual(model.syncHealth, .accessRemoved)
        XCTAssertTrue(model.serverRefusesThisDevice)
        XCTAssertEqual(model.syncError, model.syncMessage(of: .accessRemoved))
        XCTAssertEqual(model.syncStatusAction, .reconnect)

        let plain = try JournalCoding.encoder().encode(RecoveryParameters(.unprotected))
        server.update {
            $0.serverID = "another-library"
            $0.parameters = plain
        }
        await model.learnWhyAccessWasRefused()
        XCTAssertEqual(model.syncHealth, .serverReplaced, "The sync's answer is kept, not replaced by a guess")
        XCTAssertEqual(model.syncError, model.syncMessage(of: .serverReplaced))
    }

    /// The message after a removal follows the library on this device: a password, or a recovery code without one.
    func testTheRemovedMessageFollowsTheLibrarysMode() async throws {
        let withPassword = try await library(address: "http://127.0.0.1:9", encrypted: true)
        XCTAssertTrue(
            withPassword.syncMessage(of: .accessRemoved).hasSuffix("you need your password or a connected device."))
        let without = try await library(address: "http://127.0.0.1:9")
        XCTAssertTrue(
            without.syncMessage(of: .accessRemoved).hasSuffix("you need a connected device or a recovery code."))
    }

    /// A stopped state doesn't retry on unlock, so its own sentence must still be there afterwards.
    func testLockingKeepsAStoppedSyncStatesMessageAndAction() async throws {
        let server = try await LibraryServer.start()
        let model = try await library(address: server.address)
        await model.turnOnAppLockForTesting()
        server.update { $0.refusesDevices = true }
        await model.syncNow()
        XCTAssertEqual(model.syncHealth, .accessRemoved)
        let message = try XCTUnwrap(model.syncError)

        await model.lock()
        await model.unlockForTesting()
        XCTAssertEqual(model.syncHealth, .accessRemoved)
        XCTAssertEqual(model.syncError, message)
        XCTAssertEqual(model.syncStatusAction, .reconnect)
    }

    func testStopSyncingKeepsTheLibraryAndGivesUpAccess() async throws {
        let server = try await LibraryServer.start()
        server.update { $0.refusesDevices = true }
        let model = try await library(address: server.address)
        let account = try XCTUnwrap(model.configuration?.connectionKeyID)
        let device = try XCTUnwrap(model.connection?.deviceID)
        await model.newEntry()
        _ = await model.finishPendingSave()
        let store = try XCTUnwrap(model.store)
        let items = try await store.items()
        let waiting = try await store.pendingItemCount()
        XCTAssertGreaterThan(waiting, 0)

        model.stopSyncing()

        XCTAssertNil(model.connection)
        XCTAssertNil(try Keychain.read(account))
        XCTAssertNil(model.syncActivity.lastSynced)
        let kept = try await store.items()
        XCTAssertEqual(kept, items)
        let stillWaiting = try await store.pendingItemCount()
        XCTAssertEqual(stillWaiting, waiting, "What wasn't sent stays queued for connecting again")
        XCTAssertTrue(model.joinsByMerging, "Connecting again asks Merge Journals first")
        for _ in 0..<100 where !server.requests.contains(where: { $0.method == "DELETE" }) {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(
            server.requests.contains {
                $0.method == "DELETE" && $0.path == "/v1/devices/\(device.uuidString.lowercased())"
            })
    }

    /// Every failure only a faulty or different server can send (docs/design/sync-health-and-recovery.md, coverage):
    /// its state, message, single action, and whether automatic sync stops or waits, and for how long.
    func testEveryFailureAServerCanSendShowsItsStateActionAndRetry() async throws {
        let status = HealthyStatus.text(serverId: "faulty")
        struct Case {
            let name: String
            let answer: @Sendable (FakeJournalServer.Request) -> (Int, String)
            let health: SyncHealth
            let action: SyncStatusAction
            let wait: TimeInterval?
        }
        let cases: [Case] = [
            Case(name: "server error", answer: { _ in (503, "{}") }, health: .unavailable, action: .tryAgain, wait: 6),
            Case(
                name: "newer protocol", answer: { _ in (200, #"{"protocolVersion":2,"initialized":true}"#) },
                health: .appUpdateNeeded, action: .checkAgain, wait: nil),
            Case(
                name: "a web page", answer: { _ in (200, "<html><body>Welcome</body></html>") },
                health: .notJournalServer, action: .checkAgain, wait: 300),
            Case(
                name: "no sync endpoint",
                answer: { request in
                    request.path == "/v1/status" ? (200, HealthyStatus.text()) : (404, "")
                },
                health: .serverUpdateNeeded, action: .checkAgain, wait: 300),
            Case(
                name: "unknown recovery format",
                answer: { request in
                    request.path == "/v1/status"
                        ? (200, status) : (200, #"{"salt":"","iterations":0,"formatVersion":9}"#)
                }, health: .appUpdateNeeded, action: .checkAgain, wait: nil),
            Case(
                name: "a page that goes back",
                answer: { request in
                    switch request.path {
                    case "/v1/status": return (200, HealthyStatus.text())
                    case let path where path.hasPrefix("/v1/sync/?"):
                        return (200, #"{"changes":[],"cursor":-5,"hasMore":true}"#)
                    default: return (503, "{}")
                    }
                }, health: .unexpected, action: .tryAgain, wait: 6),
        ]
        for testCase in cases {
            let answer = testCase.answer
            let server = try await FakeJournalServer { request in
                let (code, body) = answer(request)
                return (code, Data(body.utf8))
            }
            let model = try await library(address: server.address)
            await model.sync()
            XCTAssertEqual(model.syncHealth, testCase.health, testCase.name)
            XCTAssertEqual(model.syncError, model.syncMessage(of: testCase.health), testCase.name)
            XCTAssertEqual(model.syncStatusAction, testCase.action, testCase.name)
            XCTAssertTrue(model.syncNeedsAttention || testCase.health.kind == .temporary, testCase.name)
            XCTAssertEqual(model.automaticSyncStopped, testCase.wait == nil, testCase.name)
            if let wait = testCase.wait {
                XCTAssertEqual(model.nextSyncDelay(afterFailures: 1), wait, testCase.name)
            }
        }
    }

    func testAnImageTheServerRefusesIsExplainedWhileEverythingElseSyncs() async throws {
        let server = try await LibraryServer.start()
        server.update { $0.refusesImages = true }
        let model = try await library(address: server.address)
        let store = try XCTUnwrap(model.store)
        let image = try await store.addAttachment(Data(repeating: 4, count: 2048))
        try await store.save(
            JournalItem(
                kind: "entry", journalID: nil, title: "With a photo",
                document: .init(blocks: [DocumentBlock(kind: "image", attachmentID: image, imageDescription: "")])))

        await model.sync()
        XCTAssertNil(model.syncHealth, "One refused image isn't a sync failure")
        XCTAssertEqual(
            model.syncError, "An image is too large for your server. Entries that include it are saved on this device.")
        XCTAssertFalse(model.automaticSyncStopped)
        XCTAssertGreaterThan(server.state.withLock { $0.log.count }, 0, "Everything else was sent")
    }

    func testCheckAgainSyncsOnceTheJournalServerIsBack() async throws {
        let server = try await LibraryServer.start()
        let model = try await library(address: server.address)
        await model.sync()
        XCTAssertNil(model.syncHealth)
        server.update { $0.impostor = true }
        await model.syncNow()
        XCTAssertEqual(model.syncHealth, .notJournalServer)
        XCTAssertEqual(model.syncStatusAction, .checkAgain)

        server.update { $0.impostor = false }
        await model.syncNow()
        XCTAssertNil(model.syncHealth)
        XCTAssertNil(model.syncError)
        XCTAssertEqual(model.syncStatusAction, .syncNow)
    }
}
