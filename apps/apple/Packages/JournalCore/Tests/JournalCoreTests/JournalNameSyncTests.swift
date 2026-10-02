import XCTest

@testable import JournalCore

/// Two devices that give journals the same name before either has the other's change
/// (docs/design/journal-name-uniqueness.md §4.6).
final class JournalNameSyncTests: XCTestCase {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("NameSync-" + UUID().uuidString)
    var key = Data()

    override func setUpWithError() throws { key = try VaultCrypto.generateKey() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func device(_ server: MergeServer) async throws -> (JournalStore, SyncEngine) {
        let store = try JournalStore(directory: root.appendingPathComponent(UUID().uuidString), key: key)
        let engine = SyncEngine(store: store, server: server)
        try await engine.synchronize()
        return (store, engine)
    }
    func journals(_ store: JournalStore) async throws -> [String: UUID] {
        Dictionary(
            try await store.items().filter(JournalNames.isListed).map { ($0.title, $0.id) },
            uniquingKeysWith: { first, _ in first })
    }
    func settled(_ store: JournalStore) async throws -> Bool {
        let conflicts = try await store.conflicts()
        let pending = try await store.pending()
        return conflicts.isEmpty && pending.isEmpty
    }

    func testSameNameJournalsFromTwoDevicesAreNumberedOnce() async throws {
        for macFirst in [true, false] {
            let server = MergeServer()
            let (mac, macSync) = try await device(server)
            let (phone, phoneSync) = try await device(server)
            let older = JournalItem(kind: "journal", title: "Travel", date: Date(timeIntervalSince1970: 1_000))
            let newer = JournalItem(kind: "journal", title: "travel", date: Date(timeIntervalSince1970: 2_000))
            try await mac.save(older)
            try await mac.save(JournalItem(kind: "entry", journalID: older.id, title: "Lisbon"))
            try await phone.save(newer)
            try await phone.save(JournalItem(kind: "entry", journalID: newer.id, title: "Porto"))
            let order = macFirst ? [macSync, phoneSync, macSync] : [phoneSync, macSync, phoneSync]
            for engine in order { try await engine.synchronize() }

            for store in [mac, phone] {
                let titles = try await journals(store)
                XCTAssertEqual(titles, ["Travel": older.id, "travel 2": newer.id], "The oldest keeps its name.")
                let entries = try await store.items().filter { $0.kind == "entry" }
                XCTAssertEqual(Set(entries.map(\.journalID)), [older.id, newer.id])
                let isSettled = try await settled(store)
                XCTAssertTrue(isSettled, "Nothing to review and nothing unsent.")
            }

            // A third device, offline meanwhile with a "Travel 2" of its own, numbers only its own.
            let third = try JournalStore(directory: root.appendingPathComponent(UUID().uuidString), key: key)
            let offline = JournalItem(kind: "journal", title: "Travel 2", date: Date(timeIntervalSince1970: 3_000))
            try await third.save(offline)
            let thirdEngine = SyncEngine(store: third, server: server)
            try await thirdEngine.synchronize()
            try await macSync.synchronize()
            let thirdTitles = try await journals(third)
            XCTAssertEqual(thirdTitles, ["Travel": older.id, "travel 2": newer.id, "Travel 2 2": offline.id])
            let macTitles = try await journals(mac)
            XCTAssertEqual(macTitles, thirdTitles)
            let macSettled = try await settled(mac)
            XCTAssertTrue(macSettled)
        }
    }

    /// Receiving never refuses or changes a journal because of its name; only the rule after reading renames it.
    func testIncomingJournalsAreAcceptedAsTheyAre() async throws {
        let store = try JournalStore(directory: root.appendingPathComponent(UUID().uuidString), key: key)
        try await store.save(JournalItem(kind: "journal", title: "Travel", date: Date(timeIntervalSince1970: 1_000)))
        let incoming = JournalItem(kind: "journal", title: "Travel", date: Date(timeIntervalSince1970: 500))
        try await store.apply([try await remote(incoming, from: store, cursor: 1)], cursor: 1)
        let received = try await store.item(incoming.id)
        XCTAssertEqual(received?.title, "Travel")
        let renames = try await store.automaticRenames()
        XCTAssertEqual(renames.count, 0, "The only other one is waiting to be sent, so this device leaves it alone.")
    }

    func testARefusedRenameLeavesNothingToReview() async throws {
        // The server refuses the first rename as stale: the device reads again, works the rule out again and sends it.
        let server = MergeServer()
        let (mac, macSync) = try await device(server)
        let (phone, phoneSync) = try await device(server)
        let older = JournalItem(kind: "journal", title: "Travel", date: Date(timeIntervalSince1970: 1_000))
        let newer = JournalItem(kind: "journal", title: "Travel", date: Date(timeIntervalSince1970: 2_000))
        try await mac.save(older)
        try await macSync.synchronize()
        try await phone.save(newer)
        await server.refuseNextPush()
        try await phoneSync.synchronize()
        let titles = try await journals(phone)
        XCTAssertEqual(titles, ["Travel": older.id, "Travel 2": newer.id])
        let isSettled = try await settled(phone)
        XCTAssertTrue(isSettled)

        // Another device renamed it first: this device's rename is refused and nothing of it is stored.
        let (tablet, _) = try await device(server)
        try await tablet.insertWithoutChecks([
            JournalItem(kind: "journal", title: "Work", date: Date(timeIntervalSince1970: 1_000)),
            JournalItem(kind: "journal", title: "Work", date: Date(timeIntervalSince1970: 2_000)),
        ])
        for pending in try await tablet.pending() {
            guard case .accepted(let receipt) = try await server.push(pending, serverID: nil) else {
                return XCTFail("The fixture wasn't accepted.")
            }
            try await tablet.acknowledge(pending, receipt: receipt)
        }
        let page = try await server.changes(after: try await phone.cursor(), limit: 200, applied: nil)
        try await phone.apply(page.changes, cursor: page.cursor)
        let late = try await phone.automaticRenames()
        XCTAssertEqual(late.count, 1)
        try await macSync.synchronize()
        let rename = try XCTUnwrap(late.first)
        guard case .conflict = try await server.push(rename.change, serverID: nil) else {
            return XCTFail("The Mac renamed it first.")
        }
        let beforeSync = try await settled(phone)
        XCTAssertTrue(beforeSync, "A refused rename leaves nothing to send or review.")
    }

    func testAJournalWithAReviewOrAnUnsentChangeIsNotRenamed() async throws {
        let store = try JournalStore(directory: root.appendingPathComponent(UUID().uuidString), key: key)
        let dates = [1_000, 2_000, 3_000, 4_000].map { Date(timeIntervalSince1970: $0) }
        let journals = dates.map { JournalItem(kind: "journal", title: "Travel", date: $0) }
        var changes: [RemoteChange] = []
        for (index, journal) in journals.enumerated() {
            changes.append(try await remote(journal, from: store, cursor: Int64(index + 1)))
        }
        try await store.apply(changes, cursor: 4)
        // The second has a change to review, the third a change waiting to be sent.
        var edited = journals[1]
        edited.defaultTemplateID = UUID()
        try await store.insertWithoutChecks([edited])
        var other = journals[1]
        other.defaultTemplateID = UUID()
        _ = try await store.recordConflict(try await remote(other, from: store, cursor: 5, revision: 2))
        var waiting = journals[2]
        waiting.defaultTemplateID = UUID()
        try await store.insertWithoutChecks([waiting])

        let renames = try await store.automaticRenames()
        let decoded = try await renames.asyncMap { try await store.decodeForTest($0.change) }
        XCTAssertEqual(decoded.map(\.id), [journals[3].id], "Only the journal that can be renamed is.")
        XCTAssertEqual(decoded.map(\.title), ["Travel 4"], "Its number doesn't depend on which others can be renamed.")
    }

    /// `item` as another device's change at revision `revision`.
    func remote(_ item: JournalItem, from store: JournalStore, cursor: Int64, revision: Int64 = 1) async throws
        -> RemoteChange
    {
        RemoteChange(
            cursor: cursor, recordId: item.id, revision: revision, kind: item.kind,
            payload: try await store.encode(item), deviceId: UUID(), modifiedAt: Date())
    }
}

extension JournalStore {
    func decodeForTest(_ change: PendingChange) throws -> JournalItem {
        try decode(change.payload, id: change.recordID, kind: change.kind)
    }
}

extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        for element in self { result.append(try await transform(element)) }
        return result
    }
}
