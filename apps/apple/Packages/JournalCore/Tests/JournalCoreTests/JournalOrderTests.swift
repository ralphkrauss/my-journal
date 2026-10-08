import CryptoKit
import XCTest

@testable import JournalCore

/// Journal order (docs/design/journal-order.md, "Data and sync design"): one rank per journal in the library record.
final class JournalOrderTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("order-\(UUID().uuidString)")
    private let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
    private func device(_ name: String) throws -> JournalStore {
        let store = try JournalStore(directory: root.appendingPathComponent(name), key: key)
        addTeardownBlock { try? await store.close() }
        return store
    }
    /// Journals named `titles`, saved on `store`.
    private func journals(_ store: JournalStore, _ titles: [String]) async throws -> [String: UUID] {
        var identities: [String: UUID] = [:]
        for title in titles {
            let journal = JournalItem(kind: "journal", title: title)
            try await store.save(journal)
            identities[title] = journal.id
        }
        return identities
    }
    private func journal(_ store: JournalStore, _ title: String) async throws -> JournalItem {
        let journal = try await store.arrangedJournals().first { $0.title == title }
        return try XCTUnwrap(journal)
    }
    private func order(_ store: JournalStore) async throws -> [String] {
        try await store.arrangedJournals().map(\.title)
    }
    /// Moves the journal named `title` to `index` of the list without it, as a drop does.
    private func move(_ store: JournalStore, _ title: String, to index: Int) async throws {
        let shown = try await store.arrangedJournals()
        let journal = try XCTUnwrap(shown.first { $0.title == title })
        try await store.moveJournal(journal.id, shown: shown.map(\.id), to: index)
    }
    private func pair() async throws -> (MemoryServer, JournalStore, SyncEngine, JournalStore, SyncEngine) {
        let server = MemoryServer()
        let mac = try device("mac-\(UUID())")
        let phone = try device("phone-\(UUID())")
        let macSync = SyncEngine(store: mac, server: server)
        let phoneSync = SyncEngine(store: phone, server: server)
        _ = try await journals(mac, ["Default", "Travel", "Work", "Home"])
        try await macSync.synchronize()
        try await phoneSync.synchronize()
        return (server, mac, macSync, phone, phoneSync)
    }

    func testWithoutMovesJournalsAreListedByName() async throws {
        let store = try device("names")
        _ = try await journals(store, ["work", "Travel", "Default", "Ärzte"])
        let names = try await order(store)
        XCTAssertEqual(names, ["Ärzte", "Default", "Travel", "work"])
    }

    func testMovesOfDifferentJournalsOnTwoDevicesAreBothKept() async throws {
        for macFirst in [true, false] {
            let (_, mac, macSync, phone, phoneSync) = try await pair()
            // Default, Home, Travel, Work: the Mac moves Work to the top, the phone moves Default to the bottom.
            try await move(mac, "Work", to: 0)
            try await move(phone, "Default", to: 3)
            let engines =
                macFirst
                ? [macSync, phoneSync, macSync, phoneSync, macSync]
                : [phoneSync, macSync, phoneSync, macSync, phoneSync]
            for engine in engines { try await engine.synchronize() }
            let onMac = try await order(mac)
            let onPhone = try await order(phone)
            XCTAssertEqual(onMac, ["Work", "Home", "Travel", "Default"])
            XCTAssertEqual(onPhone, onMac)
        }
    }

    func testTheSameJournalMovedOnTwoDevicesEndsWhereTheLaterPushPutIt() async throws {
        let (_, mac, macSync, phone, phoneSync) = try await pair()
        try await move(mac, "Work", to: 0)
        try await move(phone, "Work", to: 1)
        try await macSync.synchronize()
        try await phoneSync.synchronize()
        try await phoneSync.synchronize()
        try await macSync.synchronize()
        let onMac = try await order(mac)
        let onPhone = try await order(phone)
        XCTAssertEqual(onMac, ["Default", "Work", "Home", "Travel"])
        XCTAssertEqual(onPhone, onMac)
    }

    func testSimultaneousFirstMovesGiveTheOtherJournalsTheSameRanks() async throws {
        let (_, mac, macSync, phone, phoneSync) = try await pair()
        try await move(mac, "Travel", to: 0)
        try await move(phone, "Home", to: 3)
        let macRanks = try await mac.libraryArrangement().ranks
        let phoneRanks = try await phone.libraryArrangement().ranks
        let journals = try await mac.arrangedJournals()
        for journal in journals where !["Travel", "Home"].contains(journal.title) {
            XCTAssertEqual(macRanks[journal.id], phoneRanks[journal.id])
        }
        try await macSync.synchronize()
        try await phoneSync.synchronize()
        try await phoneSync.synchronize()
        try await macSync.synchronize()
        let onMac = try await order(mac)
        XCTAssertEqual(onMac, ["Travel", "Default", "Work", "Home"])
        let onPhone = try await order(phone)
        XCTAssertEqual(onPhone, onMac)
    }

    func testAStaleDevicesFirstMoveKeepsTheOtherDevicesArrangement() async throws {
        let (_, mac, macSync, phone, phoneSync) = try await pair()
        // The Mac arranges every journal: Work, Travel, Home, Default.
        try await move(mac, "Work", to: 0)
        try await move(mac, "Travel", to: 1)
        try await move(mac, "Default", to: 3)
        try await macSync.synchronize()
        // The phone hasn't read that and moves Home to the top.
        try await move(phone, "Home", to: 0)
        try await phoneSync.synchronize()
        try await phoneSync.synchronize()
        try await macSync.synchronize()
        let onMac = try await order(mac)
        let onPhone = try await order(phone)
        XCTAssertEqual(onPhone, onMac)
        XCTAssertEqual(onMac.filter { $0 != "Home" }, ["Work", "Travel", "Default"], "The arrangement is kept")
    }

    func testAJournalWithoutARankFollowsTheArrangedOnesAndAMoveRanksItInPlace() async throws {
        let (server, mac, macSync, phone, phoneSync) = try await pair()
        try await move(mac, "Work", to: 0)
        try await macSync.synchronize()
        // A journal from a version without ranks.
        let old = JournalItem(kind: "journal", title: "Archive")
        let payload = try await phone.sealedPayload(
            PortableRecord.encode(old), id: old.id, kind: "journal")
        _ = try await server.push(
            PendingChange(operationId: UUID(), recordID: old.id, baseRevision: 0, kind: "journal", payload: payload),
            serverID: nil, shortReceipt: false)
        try await phoneSync.synchronize()
        let listed = try await order(phone)
        XCTAssertEqual(listed, ["Work", "Default", "Home", "Travel", "Archive"])
        try await move(phone, "Travel", to: 0)
        let moved = try await order(phone)
        XCTAssertEqual(moved, ["Travel", "Work", "Default", "Home", "Archive"], "No other journal moves")
        try await phoneSync.synchronize()
        try await macSync.synchronize()
        let onMac = try await order(mac)
        XCTAssertEqual(onMac, moved)
    }

    func testRanksStayValidAndBetweenTheirNeighboursThroughManyInsertions() throws {
        var generator = SeededGenerator(seed: 20_261_003)
        var ranks: [String] = []
        var rebalanced = 0
        for _ in 0..<2_000 {
            let position = Int.random(in: 0...ranks.count, using: &generator)
            let choice = Int.random(in: 0..<10, using: &generator)
            let index = choice == 0 ? 0 : choice == 1 ? ranks.count : position
            let lower = index > 0 ? ranks[index - 1] : nil
            let upper = index < ranks.count ? ranks[index] : nil
            guard let rank = JournalRanks.between(lower, upper) else {
                // Only when the rank would be longer than allowed: everything is spaced again.
                rebalanced += 1
                ranks = (0...ranks.count).map { JournalRanks.spaced($0, count: ranks.count + 1) }
                continue
            }
            XCTAssertTrue(JournalRanks.isValid(rank), rank)
            if let lower { XCTAssertLessThan(lower, rank) }
            if let upper { XCTAssertLessThan(rank, upper) }
            ranks.insert(rank, at: index)
        }
        XCTAssertEqual(ranks, ranks.sorted())
        XCTAssertEqual(rebalanced, 0, "Random insertions never need rebalancing")

        // Always into the same gap: rebalancing starts only once a rank would exceed 64 characters.
        var lower = "V"
        let upper = "W"
        var longest = 0
        while let rank = JournalRanks.between(lower, upper) {
            longest = max(longest, rank.count)
            lower = rank
        }
        XCTAssertEqual(longest, 64)
    }

    func testRanksMatchTheProtocolVectors() throws {
        let url = Conformance.url("records/journal-ranks-v1.json")
        let vectors = try JSONDecoder().decode(RankVectors.self, from: Data(contentsOf: url))
        for rank in vectors.valid { XCTAssertTrue(JournalRanks.isValid(rank), rank) }
        for rank in vectors.invalid { XCTAssertFalse(JournalRanks.isValid(rank), rank) }
        for pair in vectors.ordered { XCTAssertTrue(JournalRanks.precedes(pair[0], pair[1]), "\(pair)") }
        for vector in vectors.between {
            XCTAssertEqual(JournalRanks.between(vector.lower, vector.upper), vector.rank, "\(vector)")
        }
        for vector in vectors.spaced {
            XCTAssertEqual(
                (0..<vector.count).map { JournalRanks.spaced($0, count: vector.count) }, vector.ranks, "\(vector.count)"
            )
        }
    }

    func testAnInvalidRankIsIgnoredForOrderAndKeptUnchanged() async throws {
        let store = try device("invalid")
        let identities = try await journals(store, ["Alpha", "Beta", "Gamma"])
        let gamma = try XCTUnwrap(identities["Gamma"])
        let beta = try XCTUnwrap(identities["Beta"])
        let bad = "journal-rank/\(gamma.uuidString.lowercased())"
        try await store.setLibraryValues([
            bad: .string("zz0"), "journal-rank/\(beta.uuidString.lowercased())": .string("1"),
        ])
        let names = try await order(store)
        XCTAssertEqual(names, ["Beta", "Alpha", "Gamma"])
        try await move(store, "Alpha", to: 0)
        let values = try await store.libraryValues()
        XCTAssertEqual(values[bad], .string("zz0"), "A rank this version can't use is kept as it is")
    }

    func testARestoredJournalReturnsToItsPlaceAndADeletedOnesRankGoesWithTheNextMove() async throws {
        let store = try device("lifecycle")
        _ = try await journals(store, ["Alpha", "Beta", "Gamma", "Delta"])
        try await move(store, "Gamma", to: 0)
        var listed = try await order(store)
        XCTAssertEqual(listed, ["Gamma", "Alpha", "Beta", "Delta"])
        var alpha = try await journal(store, "Alpha")
        let plan = try await store.prepareJournalDeletion(alpha.id)
        alpha = try await store.deleteJournal(plan)
        _ = try await store.restoreJournal(alpha.id)
        listed = try await order(store)
        XCTAssertEqual(listed, ["Gamma", "Alpha", "Beta", "Delta"])

        // Deleted permanently: the rank is ignored, and removed by the next move.
        let beta = try await journal(store, "Beta")
        _ = try await store.deleteJournal(try await store.prepareJournalDeletion(beta.id))
        try await store.permanentlyDelete(try await store.preparePermanentDeletion(beta.id))
        try await move(store, "Delta", to: 0)
        let values = try await store.libraryValues()
        XCTAssertNil(values["journal-rank/\(beta.id.uuidString.lowercased())"])
        listed = try await order(store)
        XCTAssertEqual(listed, ["Delta", "Gamma", "Alpha"])
    }

    func testANewJournalGoesToTheEndOnceThereIsAnArrangement() async throws {
        let store = try device("new")
        _ = try await journals(store, ["Beta", "Alpha"])
        let early = JournalItem(kind: "journal", title: "Aaa")
        try await store.save(early)
        try await store.placeJournalAtEnd(early.id)
        var listed = try await order(store)
        XCTAssertEqual(listed, ["Aaa", "Alpha", "Beta"], "Without an arrangement, journals stay in name order")
        try await move(store, "Beta", to: 0)
        let late = JournalItem(kind: "journal", title: "Aab")
        try await store.save(late)
        try await store.placeJournalAtEnd(late.id)
        listed = try await order(store)
        XCTAssertEqual(listed, ["Beta", "Aaa", "Alpha", "Aab"])
    }
}

private struct RankVectors: Decodable {
    struct Between: Decodable {
        let lower: String?
        let upper: String?
        let rank: String?
    }
    struct Spaced: Decodable {
        let count: Int
        let ranks: [String]
    }
    let valid: [String]
    let invalid: [String]
    let ordered: [[String]]
    let between: [Between]
    let spaced: [Spaced]
}

/// A small deterministic generator, so a failing run can be repeated.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
