import CryptoKit
import GRDB
import XCTest
import os

@testable import JournalCore

/// A server whose status, identity and failures each test sets (docs/design/sync-health-and-recovery.md §2).
private actor HealthServer: SyncServer {
    var initialized = true
    var protocolVersion = 1
    var serverID: String? = "server-one"
    var statusFailure: Error?
    var pageFailure: Error?
    var pushFailures: [UUID: Error] = [:]
    var uploadFailures: [UUID: Error] = [:]
    var protection: ContentProtection? = .plaintext
    /// Pages from a database with another identity than the status reports, as while the server changes again.
    var pageServerID: String?
    private var log: [RemoteChange] = []
    private(set) var pageRequests = 0
    private(set) var statusRequests = 0
    private(set) var pushes: [UUID] = []
    private(set) var uploads: [UUID] = []
    private var images: [UUID: Data] = [:]

    func set(
        initialized: Bool? = nil, protocolVersion: Int? = nil, serverID: String?? = nil, statusFailure: Error?? = nil,
        pageFailure: Error?? = nil, protection: ContentProtection?? = nil
    ) {
        if let initialized { self.initialized = initialized }
        if let protocolVersion { self.protocolVersion = protocolVersion }
        if let serverID { self.serverID = serverID }
        if let statusFailure { self.statusFailure = statusFailure }
        if let pageFailure { self.pageFailure = pageFailure }
        if let protection { self.protection = protection }
    }
    func failPush(of record: UUID, with error: Error?) { pushFailures[record] = error }
    func failUpload(of image: UUID, with error: Error?) { uploadFailures[image] = error }
    func movePages(to identity: String) { pageServerID = identity }

    func status() throws -> ServerStatus {
        statusRequests += 1
        if let statusFailure { throw statusFailure }
        var status = ServerStatus.healthy(serverId: serverID, initialized: initialized)
        status.protocolVersion = protocolVersion
        return status
    }
    func changes(after cursor: Int64, limit: Int, applied: LoggedChange?) throws -> SyncPage {
        pageRequests += 1
        if let pageFailure { throw pageFailure }
        let newer = log.filter { $0.cursor > cursor }.prefix(limit)
        return SyncPage(
            changes: Array(newer), cursor: newer.last?.cursor ?? cursor, hasMore: false,
            serverId: pageServerID ?? serverID,
            serverIdCursor: 0)
    }
    func push(_ pending: PendingChange, serverID: String?, shortReceipt: Bool) throws -> ServerClient.PushResult {
        pushes.append(pending.recordID)
        if let failure = pushFailures[pending.recordID] { throw failure }
        let change = RemoteChange(
            cursor: Int64(log.count + 1), recordId: pending.recordID, revision: pending.baseRevision + 1,
            kind: pending.kind, payload: pending.payload, deviceId: UUID(), modifiedAt: Date())
        log.append(change)
        return .accepted(change)
    }
    func upload(_ bytes: Data, id: UUID) throws {
        uploads.append(id)
        if let failure = uploadFailures[id] { throw failure }
        images[id] = bytes
    }
    func hasAttachment(_ id: UUID) -> Bool? { images[id] != nil }
    func downloadAttachment(_ id: UUID) throws -> Data {
        guard let image = images[id] else { throw JournalError.server("Image unavailable.") }
        return image
    }
    func contentProtection() -> ContentProtection? { protection }
}

final class SyncHealthTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
    private func library(protection: ContentProtection = .plaintext) throws -> JournalStore {
        let store = try JournalStore(
            directory: root.appendingPathComponent(UUID().uuidString),
            key: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }, protection: protection)
        addTeardownBlock { try? await store.close() }
        return store
    }
    private func health(_ engine: SyncEngine, file: StaticString = #filePath, line: UInt = #line) async -> SyncHealth? {
        do {
            try await engine.synchronize()
            return nil
        } catch {
            return SyncHealth(classifying: error)
        }
    }

    func testEveryFailureMapsToOneStateAndOnlyStatesThatCantHealStopAutomaticSync() {
        let cases: [(Error, SyncHealth)] = [
            (URLError(.notConnectedToInternet), .offline),
            (URLError(.cannotConnectToHost), .unreachable),
            (URLError(.timedOut), .unreachable),
            (URLError(.cannotFindHost), .unreachable),
            (URLError(.serverCertificateUntrusted), .certificateInvalid),
            (URLError(.secureConnectionFailed), .certificateInvalid),
            (ServerRateLimited(retryAfter: 30), .unavailable),
            (ServerUnavailable(), .unavailable),
            (DatabaseError(resultCode: .SQLITE_CORRUPT), .localDataUnreadable),
            (DatabaseError(resultCode: .SQLITE_BUSY), .localDataUnavailable),
            (JournalError.unauthorized, .accessRemoved),
            (JournalError.unsupportedFormat, .appUpdateNeeded),
            (SyncFailure(.serverNotSetUp), .serverNotSetUp),
            (JournalError.invalidData, .unexpected),
        ]
        for (error, expected) in cases {
            XCTAssertEqual(SyncHealth(classifying: error), expected, "\(error)")
        }
        let stopping = cases.map(\.1).filter(\.stopsAutomaticSync)
        XCTAssertEqual(Set(stopping.map { "\($0)" }), ["accessRemoved", "appUpdateNeeded", "serverNotSetUp"])
        for health: SyncHealth in [.signInNeeded, .serverReplaced] { XCTAssertTrue(health.stopsAutomaticSync) }
        for (_, health) in cases {
            let message = health.message(host: "journal.example.ts.net")
            for detail in ["request", "HTTP", "SQL", "error", "401", "500"] {
                XCTAssertFalse(message.contains(detail), "“\(message)” shows an implementation detail")
            }
        }
    }

    /// The device was removed on purpose, so the message says what signing in again needs: a library without a
    /// password has none, and the way back is a connected device or the server's recovery code. Every state that
    /// stops sync names the one Reconnect action, never a button that no longer exists.
    func testRemovedAccessSaysWhatReconnectingNeedsForTheLibrarysMode() {
        XCTAssertEqual(
            SyncHealth.accessRemoved.message(),
            "This device no longer has access to the server. Your journals are still on this device. To reconnect, you need your password or a connected device."
        )
        XCTAssertEqual(
            SyncHealth.accessRemoved.message(hasPassword: false),
            "This device no longer has access to the server. Your journals are still on this device. To reconnect, you need a connected device or a recovery code."
        )
        XCTAssertEqual(
            SyncHealth.signInNeeded.message(),
            "The server now uses encryption or was replaced. Reconnect to keep syncing.")
        for health: SyncHealth in [.signInNeeded, .serverNotSetUp, .serverReplaced, .accessRemoved] {
            for hasPassword in [true, false] {
                let message = health.message(hasPassword: hasPassword)
                for oldLabel in ["Sign in", "Connect again", "Set up the server again"] {
                    XCTAssertFalse(message.contains(oldLabel), "“\(message)” names an action that is now Reconnect")
                }
            }
        }
    }

    func testAResetServerIsNotSetUpAndNothingElseIsAsked() async throws {
        let server = HealthServer()
        let store = try library()
        try await store.save(JournalItem(kind: "entry", journalID: UUID(), title: "Written offline"))
        await server.set(initialized: false, serverID: .some(nil))
        let engine = SyncEngine(store: store, server: server)

        let state = await health(engine)
        XCTAssertEqual(state, .serverNotSetUp)
        let asked = await (server.pageRequests, server.pushes.count)
        XCTAssertEqual(asked.0, 0)
        XCTAssertEqual(asked.1, 0)
        XCTAssertEqual(state?.message(), "The server isn’t set up. Your journals are still on this device.")
    }

    func testAServerOfAnotherProtocolOrNoJournalServerNeedsAnUpdateOrAFix() async throws {
        let server = HealthServer()
        let engine = SyncEngine(store: try library(), server: server)
        await server.set(protocolVersion: 2)
        var state = await health(engine)
        XCTAssertEqual(state, .appUpdateNeeded)
        XCTAssertEqual(state?.stopsAutomaticSync, true)
        await server.set(
            protocolVersion: 1,
            statusFailure: .some(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "HTML"))))
        state = await health(engine)
        XCTAssertEqual(state, .notJournalServer)
        XCTAssertEqual(state?.stopsAutomaticSync, false, "A server that's being fixed is checked again by itself")
    }

    func testARefusedDeviceIsToldApartByTheServersIdentity() async throws {
        let server = HealthServer()
        let store = try library()
        let engine = SyncEngine(store: store, server: server)
        try await engine.synchronize()

        await server.set(pageFailure: .some(JournalError.unauthorized))
        var state = await health(engine)
        XCTAssertEqual(state, .accessRemoved, "The same server refusing this device removed it")

        await server.set(serverID: .some("server-two"))
        state = await health(engine)
        XCTAssertEqual(state, .serverReplaced, "Another identity means the server was restored or replaced")

        await server.set(protection: .some(.encrypted))
        state = await health(engine)
        XCTAssertEqual(state, .signInNeeded, "An encrypted server may be encryption turned on elsewhere")
    }

    func testARecordThatTimesOutEndsThePassAndIsSentAgainWithoutWaiting() async throws {
        let server = HealthServer()
        let store = try library()
        let engine = SyncEngine(store: store, server: server)
        try await engine.synchronize()
        let entry = JournalItem(kind: "entry", journalID: UUID(), title: "Slow")
        try await store.save(entry)
        await server.failPush(of: entry.id, with: URLError(.timedOut))
        let pagesBefore = await server.pageRequests

        let state = await health(engine)
        XCTAssertEqual(state, .unreachable)
        let pagesAfter = await server.pageRequests
        XCTAssertEqual(pagesAfter, pagesBefore, "Nothing else waits on a server that timed out")

        await server.failPush(of: entry.id, with: nil)
        try await engine.synchronize()
        let pushes = await server.pushes.filter { $0 == entry.id }.count
        XCTAssertEqual(pushes, 2, "The record is sent at the next sync, not after a wait")
    }

    func testAnImageThatTimesOutWaitsAloneWhileRecordsSync() async throws {
        let server = HealthServer()
        let store = try library()
        let slow = try await store.addAttachment(Data(repeating: 1, count: 100))
        try await store.save(
            JournalItem(
                kind: "entry", journalID: UUID(),
                document: .init(blocks: [DocumentBlock(kind: "image", attachmentID: slow, imageDescription: "")])))
        let text = JournalItem(kind: "entry", journalID: UUID(), title: "Text only")
        try await store.save(text)
        await server.failUpload(of: slow, with: URLError(.timedOut))

        _ = await health(SyncEngine(store: store, server: server))
        let sent = await server.pushes
        let pages = await server.pageRequests
        XCTAssertEqual(sent, [text.id], "Records go on while a large image is slow; the entry using it waits")
        XCTAssertGreaterThan(pages, 0, "Changes are still received")
    }

    func testARecordTheServerKeepsFailingOnIsRefusedAloneAfterThreeAttempts() async throws {
        let server = HealthServer()
        let store = try library()
        let clock = OSAllocatedUnfairLock(initialState: Date())
        let engine = SyncEngine(store: store, server: server, now: { clock.withLock { $0 } })
        let failing = JournalItem(kind: "entry", journalID: UUID(), title: "Breaks the server")
        let fine = JournalItem(kind: "entry", journalID: UUID(), title: "Fine")
        try await store.save(failing)
        try await store.save(fine)
        await server.failPush(of: failing.id, with: ServerUnavailable())

        for attempt in 1...2 {
            let state = await health(engine)
            XCTAssertEqual(state, .unavailable, "Attempt \(attempt) still looks like a busy server")
            clock.withLock { $0 = $0.addingTimeInterval(700) }
        }
        let report = try await engine.synchronize()
        XCTAssertEqual(
            report.problem,
            "Your server didn’t accept “Breaks the server”. It’s saved on this device. Edit it to try again.")
        let sent = await server.pushes
        XCTAssertTrue(sent.contains(fine.id), "The other record syncs")
        XCTAssertEqual(sent.filter { $0 == failing.id }.count, 3)
        _ = try await engine.synchronize()
        let after = await server.pushes.filter { $0 == failing.id }.count
        XCTAssertEqual(after, 3, "A refused record waits until it's edited or Try Again")
    }

    func testAServerWhoseIdentityKeepsChangingIsOnlyTemporarilyUnavailable() async throws {
        let server = HealthServer()
        let engine = SyncEngine(store: try library(), server: server)
        try await engine.synchronize()
        await server.movePages(to: "server-moving")
        let state = await health(engine)
        XCTAssertEqual(state, .unavailable, "Changing again while it's read is retried, not shown as broken")
        XCTAssertEqual(state?.stopsAutomaticSync, false)
    }

    /// A synchronization that only receives reuses the status read within the last minute, so an idle pass is one
    /// request. Sending, Sync Now, a minute passing and a failure read it again, and it explains the failure.
    func testAnIdleSynchronizationOnlyAsksForNewChanges() async throws {
        let server = HealthServer()
        let store = try library()
        let clock = OSAllocatedUnfairLock(initialState: Date())
        let engine = SyncEngine(store: store, server: server, now: { clock.withLock { $0 } })
        try await engine.synchronize()
        try await engine.synchronize()
        var statuses = await server.statusRequests
        let pages = await server.pageRequests
        XCTAssertEqual([statuses, pages], [1, 2], "The second pass only asks for new changes")

        try await store.save(JournalItem(kind: "entry", journalID: UUID(), title: "Written"))
        try await engine.synchronize()
        statuses = await server.statusRequests
        XCTAssertEqual(statuses, 2, "Sending follows a status read just before")
        try await engine.synchronize(retryingRefused: true)
        try await engine.synchronize()
        statuses = await server.statusRequests
        XCTAssertEqual(statuses, 3, "Sync Now reads the status; the pass after it reuses it")
        clock.withLock { $0 = $0.addingTimeInterval(SyncEngine.statusLifetime + 1) }
        try await engine.synchronize()
        statuses = await server.statusRequests
        XCTAssertEqual(statuses, 4, "After a minute the status is read again")

        // A reset server no longer knows this device; the status read after the failure says why.
        await server.set(initialized: false, pageFailure: JournalError.unauthorized)
        let state = await health(engine)
        XCTAssertEqual(state, .serverNotSetUp)
        statuses = await server.statusRequests
        XCTAssertEqual(statuses, 5)
    }

    func testAnswersNothingExplainsSayWhatToDo() {
        XCTAssertEqual(
            ServerClient.unanswered(status: 404).localizedDescription,
            "Couldn’t reach the server. Check the address and your connection, then try again.")
        XCTAssertTrue(ServerClient.unanswered(status: 502) is ServerUnavailable)
        XCTAssertEqual(
            ServerUnavailable().localizedDescription, "The server isn’t available right now. Try again in a moment.")
        XCTAssertTrue(ServerClient.syncFailure(status: 500) is ServerUnavailable)
    }
}
