import JournalCore
import XCTest
import os

@testable import Journal

/// Waiting for the server's changes instead of polling (docs/design/sync-protocol-efficiency.md §4.6, §7.2).
@MainActor
final class ChangeWaitingTests: XCTestCase {
    private func library(address: String) async throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ChangeWaiting-" + UUID().uuidString)
        let model = AppModel(directory: directory)
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            for account in [model.configuration?.keyID, model.configuration?.connectionKeyID].compactMap({ $0 }) {
                try? Keychain.remove(account)
            }
            try? FileManager.default.removeItem(at: directory)
        }
        await model.start(password: nil, encrypted: false)
        let connection = SyncConnection(address: address, deviceID: UUID(), token: "synthetic-token")
        let account = "ChangeWaitingTests-" + UUID().uuidString
        try Keychain.write(JournalCoding.encoder().encode(connection), account: account)
        model.configuration?.connectionKeyID = account
        model.connection = connection
        model.configureSync()
        model.applicationActive = true
        return model
    }

    /// A change log: pushes are accepted with a full receipt, even when a short one was asked for.
    nonisolated private static func accept(_ request: FakeJournalServer.Request, log: inout [RemoteChange])
        -> (status: Int, body: Data)
    {
        struct Push: Decodable {
            let baseRevision: Int64
            let kind: String
            let payload: String
        }
        guard let push = try? JournalCoding.decoder().decode(Push.self, from: request.body),
            let id = UUID(uuidString: String(request.path.dropFirst("/v1/sync/".count)))
        else { return (400, Data()) }
        let change = RemoteChange(
            cursor: Int64(log.count + 1), recordId: id, revision: push.baseRevision + 1, kind: push.kind,
            payload: push.payload, deviceId: UUID(), modifiedAt: Date())
        log.append(change)
        return (200, (try? JournalCoding.encoder().encode(change)) ?? Data())
    }
    nonisolated private static func page(_ path: String, log: [RemoteChange]) -> Data {
        let after =
            URLComponents(string: path)?.queryItems?.first { $0.name == "after" }?.value.flatMap(Int64.init) ?? 0
        let changes = log.filter { $0.cursor > after }
        struct Page: Encodable {
            let changes: [RemoteChange]
            let cursor: Int64
            let hasMore: Bool
            let serverId: String
            let serverIdCursor: Int64
        }
        let page = Page(
            changes: changes, cursor: changes.last?.cursor ?? after, hasMore: false, serverId: "server",
            serverIdCursor: 0)
        return (try? JournalCoding.encoder().encode(page)) ?? Data()
    }

    /// An idle library that synchronized everything waits for the server's changes instead of asking for pages every
    /// 3 seconds. Nothing the app does after an idle synchronization writes what the quiet mark watches; otherwise
    /// it would never wait.
    func testAnIdleLibraryWaitsInsteadOfPolling() async throws {
        let log = OSAllocatedUnfairLock<[RemoteChange]>(initialState: [])
        let server = try await FakeJournalServer { request in
            switch (request.method, request.path) {
            case ("GET", "/v1/status"):
                return (200, HealthyStatus.json(serverId: "server"))
            case ("GET", let path) where path.hasPrefix("/v1/sync/wait?"):
                return (200, Data(#"{"changed":false,"early":true}"#.utf8))
            case ("GET", let path) where path.hasPrefix("/v1/sync/?"):
                return (200, Self.page(path, log: log.withLock { $0 }))
            case ("PUT", let path) where path.hasPrefix("/v1/sync/"):
                return log.withLock { Self.accept(request, log: &$0) }
            case ("GET", "/v1/recovery"):
                return (200, (try? JournalCoding.encoder().encode(RecoveryParameters(.unprotected))) ?? Data())
            default: return (503, Data("{}".utf8))
            }
        }
        let model = try await library(address: server.address)
        let running = Task { await model.synchronizeAutomatically() }
        defer { running.cancel() }
        let pages = { server.requests.filter { $0.path.hasPrefix("/v1/sync/?") }.count }
        let waits = { server.requests.filter { $0.path.hasPrefix("/v1/sync/wait?") }.count }
        for _ in 0..<750 where waits() == 0 { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertGreaterThan(waits(), 0, "Waiting starts after a settled synchronization")
        let firstWait = Date()
        let pagesWhileWaiting = pages()
        // Answers that prove nothing are spaced by 3 seconds, and three of them turn waiting off: polling resumes.
        for _ in 0..<750 where waits() < 3 { try await Task.sleep(nanoseconds: 20_000_000) }
        let thirdWait = Date()
        for _ in 0..<750 where pages() == pagesWhileWaiting { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertGreaterThan(pages(), pagesWhileWaiting, "Polling resumes after three early answers")
        XCTAssertEqual(waits(), 3, "No page was polled while waiting")
        XCTAssertGreaterThan(Date().timeIntervalSince(thirdWait), 2.5, "The first poll keeps 3 s after the last wait")
        XCTAssertGreaterThan(Date().timeIntervalSince(firstWait), 5.5, "At most one request per 3 seconds")
    }

    /// A synchronization the person or writing starts does what one the watcher asked for would, so the loop
    /// doesn't run another right after it. One that couldn't run (locked) leaves it asked for.
    func testAnySynchronizationThatRunsSatisfiesTheWatchersRequest() async throws {
        let log = OSAllocatedUnfairLock<[RemoteChange]>(initialState: [])
        let server = try await FakeJournalServer { request in
            switch (request.method, request.path) {
            case ("GET", "/v1/status"):
                return (200, HealthyStatus.json(serverId: "server"))
            case ("GET", let path) where path.hasPrefix("/v1/sync/?"):
                return (200, Self.page(path, log: log.withLock { $0 }))
            case ("PUT", let path) where path.hasPrefix("/v1/sync/"):
                return log.withLock { Self.accept(request, log: &$0) }
            case ("GET", "/v1/recovery"):
                return (200, (try? JournalCoding.encoder().encode(RecoveryParameters(.unprotected))) ?? Data())
            default: return (503, Data("{}".utf8))
            }
        }
        let model = try await library(address: server.address)
        model.locked = true
        model.syncTiming.watcherSyncDue = true
        await model.sync()
        XCTAssertTrue(model.syncTiming.watcherSyncDue, "A sync that couldn't run leaves the request")
        model.locked = false
        let synchronized = await model.sync(retryingRefused: true)
        XCTAssertTrue(synchronized)
        XCTAssertFalse(model.syncTiming.watcherSyncDue, "Sync Now satisfied it")
    }

    /// A wait's confirmation is dated when it was sent, and answers arriving in any order never move Last Synced back.
    func testLastSyncedFromAWaitNeverMovesBack() {
        let activity = SyncActivity(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            defaults: UserDefaults(suiteName: "ChangeWaitingTests-" + UUID().uuidString) ?? .standard)
        let later = Date(timeIntervalSince1970: 2_000_000_000)
        activity.synced(at: later)
        activity.syncedByWait(at: later.addingTimeInterval(-20))
        XCTAssertEqual(activity.lastSynced, later)
        activity.syncedByWait(at: later.addingTimeInterval(20))
        XCTAssertEqual(activity.lastSynced, later.addingTimeInterval(20))
    }
}
