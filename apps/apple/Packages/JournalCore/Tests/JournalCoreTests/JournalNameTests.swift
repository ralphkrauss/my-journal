import XCTest

@testable import JournalCore

/// Journal names stay unique among journals that aren't in Recently Deleted
/// (docs/design/journal-name-uniqueness.md).
final class JournalNameTests: XCTestCase {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Names-" + UUID().uuidString)
    var key = Data()

    override func setUpWithError() throws { key = try VaultCrypto.generateKey() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func store() throws -> JournalStore {
        try JournalStore(directory: root.appendingPathComponent(UUID().uuidString), key: key)
    }
    func listedTitles(_ store: JournalStore) async throws -> [String] {
        try await store.items().filter(JournalNames.isListed).map(\.title).sorted()
    }
    func deleted(_ store: JournalStore, _ journal: JournalItem) async throws {
        _ = try await store.deleteJournal(store.prepareJournalDeletion(journal.id))
    }

    func testNamesTakenByLiveJournalsAreRefused() async throws {
        let store = try store()
        let travel = try await store.save(JournalItem(kind: "journal", title: "Travel"))
        for taken in ["Travel", " travel ", "TRAVEL"] {
            do {
                try await store.save(JournalItem(kind: "journal", title: taken))
                XCTFail("“\(taken)” is taken.")
            } catch JournalNameError.taken(let name) { XCTAssertEqual(name, "Travel") }
        }
        var work = try await store.save(JournalItem(kind: "journal", title: "Work"))
        work.title = "travel"
        do {
            try await store.save(work)
            XCTFail("Renaming to a taken name is refused.")
        } catch JournalNameError.taken {}

        var renamed = travel
        renamed.title = "travel"
        try await store.save(renamed)
        let afterCase = try await listedTitles(store)
        XCTAssertEqual(afterCase, ["Work", "travel"], "A journal may change the case of its own name.")

        try await deleted(store, work)
        try await store.save(JournalItem(kind: "journal", title: "Work"))
        let afterDeletion = try await listedTitles(store)
        XCTAssertEqual(afterDeletion, ["Work", "travel"], "A name held only in Recently Deleted is free.")
    }

    func testRestoringIntoATakenNameAddsANumber() async throws {
        let store = try store()
        let first = JournalItem(kind: "journal", title: "Travel")
        let entry = JournalItem(kind: "entry", journalID: first.id, title: "Lisbon")
        try await store.save(first)
        try await store.save(entry)
        try await deleted(store, first)
        try await store.save(JournalItem(kind: "journal", title: "Travel"))
        let restoredTitle = try await store.restoredTitle(of: first.id)
        XCTAssertEqual(restoredTitle, "Travel 2", "The restore sheet can say the name first.")
        let restored = try await store.restoreJournal(first.id, expectedTitle: "Travel")
        XCTAssertEqual(restored.title, "Travel 2")
        let titles = try await listedTitles(store)
        XCTAssertEqual(titles, ["Travel", "Travel 2"])
    }

    func testImportedJournalsWithTakenNamesAreNumbered() async throws {
        let travel = JournalItem(kind: "journal", title: "Travel")
        // An earlier version could write two journals with one name; saving through the store can't.
        let archive = try await fixture(with: [
            travel, JournalItem(kind: "journal", title: "Work", date: Date(timeIntervalSince1970: 1_000)),
            JournalItem(kind: "journal", title: "Work", date: Date(timeIntervalSince1970: 2_000)),
            JournalItem(kind: "entry", journalID: travel.id, title: "Lisbon"),
        ])
        let library = try store()
        try await library.save(JournalItem(kind: "journal", title: "travel"))
        try await library.importAsNewJournals(from: archive)
        let titles = try await listedTitles(library)
        XCTAssertEqual(titles, ["Travel 2", "Work", "Work 2", "travel"])
        let items = try await library.items()
        let imported = try XCTUnwrap(items.first { $0.title == "Travel 2" })
        XCTAssertEqual(items.filter { $0.journalID == imported.id }.map(\.title), ["Lisbon"])
    }

    func testExistingDuplicatesAreNumberedWhenOpened() async throws {
        let library = try await fixture(with: [
            JournalItem(kind: "journal", title: "Default", date: Date(timeIntervalSince1970: 1_000)),
            JournalItem(kind: "journal", title: "default", date: Date(timeIntervalSince1970: 2_000)),
            JournalItem(kind: "journal", title: "Default 2", date: Date(timeIntervalSince1970: 3_000)),
        ])
        let renamed = try await library.numberDuplicateJournals()
        XCTAssertEqual(renamed, 1)
        let titles = try await listedTitles(library)
        XCTAssertEqual(titles, ["Default", "Default 2", "default 3"], "The oldest keeps its name.")
        let allItems = try await library.items()
        let renamedJournal = try XCTUnwrap(allItems.first { $0.title == "default 3" })
        let versions = try await library.history(for: renamedJournal.id)
        XCTAssertTrue(versions.isEmpty, "1.1 writes no journal history; renaming again fixes a name")
        let again = try await library.numberDuplicateJournals()
        XCTAssertEqual(again, 0)
    }

    /// A store holding `items` as an earlier version or another device could have written them.
    func fixture(with items: [JournalItem]) async throws -> JournalStore {
        let fixture = try store()
        try await fixture.insertWithoutChecks(items)
        return fixture
    }
}

extension JournalStore {
    /// Saves `items` as they are, without the checks local saves make; for fixtures.
    func insertWithoutChecks(_ items: [JournalItem]) throws {
        try db.write { db in
            for item in items { try save(db, item: item) }
        }
    }
    /// Keeps `item` as an earlier version of its record.
    func keepInHistory(_ item: JournalItem) throws {
        try db.write { db in
            try db.execute(
                sql: "INSERT INTO history(record,kind,payload,saved) VALUES (?,?,?,?)",
                arguments: [id(item.id), item.kind, try encode(item), JournalCoding.timestamp(Date())])
        }
    }
}
