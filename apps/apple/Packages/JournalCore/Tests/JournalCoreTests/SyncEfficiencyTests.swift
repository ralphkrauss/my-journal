import CryptoKit
import GRDB
import XCTest
import os

@testable import JournalCore

/// Short push receipts, the store's quiet mark and when a device may wait for changes
/// (docs/design/sync-protocol-efficiency.md §7.2).
final class SyncEfficiencyTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
    private func device(_ name: String) throws -> JournalStore {
        let store = try JournalStore(directory: root.appendingPathComponent(name), key: key)
        addTeardownBlock { try? await store.close() }
        return store
    }
    private let pending = PendingChange(
        operationId: UUID(), recordID: UUID(), baseRevision: 3, kind: "entry", payload: "c2VhbGVkIGNvbnRlbnQ=")
    private func receipt(_ fields: [String: Any]) throws -> Data {
        var object: [String: Any] = [
            "cursor": 42, "recordId": pending.recordID.uuidString.lowercased(), "revision": 4, "kind": "entry",
            "deviceId": UUID().uuidString.lowercased(), "modifiedAt": "2026-10-02T09:14:03.1234567+00:00",
            "payloadDigest": JournalStore.payloadDigest(pending.payload),
        ]
        for (name, value) in fields { object[name] = value }
        return try JSONSerialization.data(withJSONObject: object.filter { !($0.value is Skip) })
    }
    private struct Skip {}

    // MARK: Short receipts

    func testAShortReceiptIsCompletedWithExactlyThePayloadSent() throws {
        let change = try ServerClient.receipt(try receipt([:]), for: pending)
        XCTAssertEqual(change.payload, pending.payload)
        XCTAssertEqual(change.recordId, pending.recordID)
        XCTAssertEqual(change.revision, 4)
        XCTAssertEqual(change.cursor, 42)
        // Both forms present and agreeing is still accepted; a full receipt is read as before.
        XCTAssertNoThrow(try ServerClient.receipt(try receipt(["payload": pending.payload]), for: pending))
        let full = try ServerClient.receipt(
            try receipt(["payload": pending.payload, "payloadDigest": Skip()]), for: pending)
        XCTAssertEqual(full.payload, pending.payload)
    }

    func testAReceiptThatDoesNotProveThePayloadSentIsRejected() throws {
        let wrong: [[String: Any]] = [
            ["recordId": UUID().uuidString],
            ["kind": "journal"],
            ["revision": 5],
            ["payloadDigest": JournalStore.payloadDigest("b3RoZXI=")],
            ["payload": "b3RoZXI="],
            ["payload": NSNull()],
            ["payloadDigest": NSNull()],
            ["payloadDigest": Skip()],
            ["cursor": Skip()],
        ]
        for fields in wrong {
            XCTAssertThrowsError(try ServerClient.receipt(try receipt(fields), for: pending), "\(fields)") {
                guard case JournalError.invalidData = $0 else { return XCTFail("\($0)") }
            }
        }
    }

    func testShortReceiptsAreAskedForOnlyFromServersThatOfferThem() async throws {
        for offered in [false, true] {
            let server = MemoryServer()
            if offered { await server.offerShortReceipts() }
            let phone = try device("phone-\(offered)")
            try await phone.save(JournalItem(kind: "entry", journalID: UUID(), document: .plain("Hello")))
            try await SyncEngine(store: phone, server: server).synchronize()
            let requests = await server.shortReceiptRequests
            XCTAssertEqual(requests, [offered])
        }
    }

    // MARK: Waiting for changes: answers

    func testOnlyABooleanAnswerIsAnAnswer() {
        func answer(_ status: Int, _ body: String) -> WaitAnswer {
            ServerClient.waitAnswer(status: status, body: Data(body.utf8))
        }
        XCTAssertEqual(answer(200, #"{"changed":true}"#), .changed)
        XCTAssertEqual(answer(200, #"{"changed":false}"#), .unchanged(early: false))
        XCTAssertEqual(answer(200, #"{"changed":false,"early":true,"other":1}"#), .unchanged(early: true))
        for (status, body) in [
            (401, #"{"changed":false}"#), (429, #"{"changed":false}"#), (404, ""), (302, #"{"changed":false}"#),
            (200, #"{"changed":"no"}"#), (200, #"{"changed":false,"early":"yes"}"#), (200, "<html>"),
            (200, #"{"changed":false,"pad":""# + String(repeating: "x", count: 1100) + #""}"#),
        ] {
            XCTAssertEqual(answer(status, body), .failed, "\(status) \(body)")
        }
    }

    // MARK: The quiet mark

    func testAnObservedCommitAdvancesTheCountButARolledBackOneDoesNot() throws {
        let database = try DatabaseQueue()
        try database.write { db in
            try db.execute(sql: "CREATE TABLE records (id TEXT); CREATE TABLE other (id TEXT)")
        }
        let counter = WriteCounter()
        database.add(transactionObserver: SyncedTableWrites(counter: counter), extent: .databaseLifetime)
        try database.write { try $0.execute(sql: "INSERT INTO records VALUES ('a'); INSERT INTO records VALUES ('b')") }
        XCTAssertEqual(counter.value, 1)
        try database.write { try $0.execute(sql: "INSERT INTO other VALUES ('a')") }
        XCTAssertEqual(counter.value, 1)
        struct Abort: Error {}
        XCTAssertThrowsError(
            try database.write { db in
                try db.execute(sql: "INSERT INTO records VALUES ('c')")
                throw Abort()
            })
        XCTAssertEqual(counter.value, 1)
        // Nothing of the rolled-back change carries over to the next commit.
        try database.write { try $0.execute(sql: "INSERT INTO other VALUES ('b')") }
        XCTAssertEqual(counter.value, 1)
    }

    func testAnyLocalWriteOrOtherSynchronizationEndsTheQuietMark() async throws {
        let server = MemoryServer()
        let phone = try device("phone")
        let sync = SyncEngine(store: phone, server: server)
        let journal = try await phone.save(JournalItem(kind: "journal", title: "Work"))
        var entry = try await phone.save(JournalItem(kind: "entry", journalID: journal.id, document: .plain("One")))
        let image = Data("image".utf8)
        func settledMark() async throws -> QuietMark {
            let report = try await sync.synchronize()
            XCTAssertTrue(report.settled)
            let mark = try XCTUnwrap(report.quietMark)
            let position = try await phone.quietPosition(since: mark)
            XCTAssertNotNil(position, "An idle synchronization writes nothing after its mark")
            return mark
        }
        var mark = try await settledMark()
        entry.document = .plain("Two")
        entry = try await phone.save(entry)
        var quiet = await phone.isQuiet(mark)
        XCTAssertFalse(quiet, "An edit")

        mark = try await settledMark()
        let stored = try await phone.item(journal.id)
        var renamed = try XCTUnwrap(stored)
        renamed.title = "Office"
        try await phone.save(renamed)
        quiet = await phone.isQuiet(mark)
        XCTAssertFalse(quiet, "A journal renamed")

        mark = try await settledMark()
        _ = try await phone.addAttachment(image)
        quiet = await phone.isQuiet(mark)
        XCTAssertFalse(quiet, "An image added without a record change")

        mark = try await settledMark()
        try await SyncEngine(store: phone, server: server).synchronize()
        quiet = await phone.isQuiet(mark)
        XCTAssertFalse(quiet, "A synchronization through another engine")
    }

    func testAWriteBeforeTheGateIsReleasedOrASyncHandedTheGateEndsQuiet() async throws {
        let phone = try device("phone")
        try await phone.beginSynchronization()
        _ = try await phone.settledFacts()
        try await phone.save(JournalItem(kind: "journal", title: "Written meanwhile"))
        var mark = await phone.endSynchronization()
        var quiet = await phone.isQuiet(mark)
        XCTAssertFalse(quiet, "A write after the facts were read")

        try await phone.beginSynchronization()
        _ = try await phone.settledFacts()
        let next = Task { try await phone.beginSynchronization() }
        while await phone.synchronizationWaiters.isEmpty { await Task.yield() }
        mark = await phone.endSynchronization()
        try await next.value
        quiet = await phone.isQuiet(mark)
        XCTAssertFalse(quiet, "A synchronization handed the gate")
        await phone.endSynchronization()
    }

    func testAMarkNeverAppliesToAnotherStore() async throws {
        func mark(_ store: JournalStore) async throws -> QuietMark {
            try await store.beginSynchronization()
            _ = try await store.settledFacts()
            return await store.endSynchronization()
        }
        let previous = try device("previous")
        let current = try device("current")
        let previousMark = try await mark(previous)
        let currentMark = try await mark(current)
        let own = await current.isQuiet(currentMark)
        let other = await current.isQuiet(previousMark)
        XCTAssertTrue(own)
        XCTAssertFalse(other, "Same counts, but another library")
    }

    // MARK: Settled

    func testRefusedItemsAndOutstandingRenamesKeepTheDevicePolling() async throws {
        let server = MemoryServer()
        await server.offerShortReceipts()
        let phone = try device("phone")
        let tooLarge = SyncEngine(store: phone, server: server, recordLimit: 10)
        try await phone.save(JournalItem(kind: "entry", journalID: UUID(), document: .plain("Too large to sync")))
        var report = try await tooLarge.synchronize()
        XCTAssertNotNil(report.problem)
        XCTAssertFalse(report.settled, "Something refused")

        let mac = try device("mac")
        let macSync = SyncEngine(store: mac, server: server)
        try await mac.save(JournalItem(kind: "journal", title: "travel", date: Date(timeIntervalSince1970: 2_000)))
        try await macSync.synchronize()
        let tablet = try device("tablet")
        try await tablet.save(JournalItem(kind: "journal", title: "Travel", date: Date(timeIntervalSince1970: 1_000)))
        let tabletSync = SyncEngine(store: tablet, server: server)
        // The tablet's own journal is sent, then its rename of the duplicate fails and is left for later.
        await server.failPush(number: 2)
        report = try await tabletSync.synchronize()
        XCTAssertFalse(report.settled, "A rename outstanding")
        report = try await tabletSync.synchronize()
        XCTAssertTrue(report.settled)
        let requests = await server.shortReceiptRequests
        XCTAssertFalse(requests.contains(false), "Renames ask for short receipts too")
    }

    func testRetryTimesDoNotStopWaitingAndOnlyCountForItemsStillQueued() async throws {
        let server = MemoryServer()
        let clock = TestClock()
        let phone = try device("phone")
        let mac = try device("mac")
        let phoneSync = SyncEngine(store: phone, server: server, now: { clock.now })
        let macSync = SyncEngine(store: mac, server: server)
        var entry = try await phone.save(JournalItem(kind: "entry", journalID: UUID(), document: .plain("Shared")))
        try await phoneSync.synchronize()
        try await macSync.synchronize()

        entry.document = .plain("Edited on the phone")
        entry = try await phone.save(entry)
        await server.failPush(number: 1)
        do {
            try await phoneSync.synchronize()
            XCTFail("The server failed")
        } catch is ServerUnavailable {}
        clock.advance(by: 1)
        var report = try await phoneSync.synchronize()
        XCTAssertTrue(report.settled, "Waiting for a retry time")
        XCTAssertEqual(report.earliestRetry ?? 0, 14, accuracy: 0.5)

        // The Mac edits it too: the phone's change now waits for a review, and its retry time schedules nothing.
        let onMac = try await mac.item(entry.id)
        var fromMac = try XCTUnwrap(onMac)
        fromMac.document = .plain("Edited on the Mac")
        try await mac.save(fromMac)
        try await macSync.synchronize()
        report = try await phoneSync.synchronize()
        let reviews = try await phone.conflicts()
        XCTAssertEqual(reviews.count, 1)
        XCTAssertTrue(report.settled, "A change waiting for a review is settled")
        XCTAssertNil(report.earliestRetry)
    }
}

/// A clock tests move by hand.
final class TestClock: Sendable {
    private let current = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_900_000_000))
    var now: Date { current.withLock { $0 } }
    func advance(by seconds: TimeInterval) { current.withLock { $0.addTimeInterval(seconds) } }
}
