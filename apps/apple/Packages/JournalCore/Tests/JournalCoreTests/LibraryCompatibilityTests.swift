import CryptoKit
import GRDB
import XCTest

@testable import JournalCore

/// The library record across versions and damage (docs/design/pinned-entries.md, rule 5 and "Reading rules"): what
/// older and newer versions left, and a library that can't be read.
final class LibraryCompatibilityTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("library-\(UUID().uuidString)")
    private let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func device(_ name: String, key: Data? = nil) throws -> JournalStore {
        let store = try JournalStore(directory: root.appendingPathComponent(name), key: key ?? self.key)
        addTeardownBlock { try? await store.close() }
        return store
    }
    private func journalWithEntries(_ store: JournalStore, count: Int = 2) async throws
        -> (journal: JournalItem, entries: [JournalItem])
    {
        let journal = JournalItem(kind: "journal", title: "Work")
        try await store.save(journal)
        var entries: [JournalItem] = []
        for index in 0..<count {
            let entry = JournalItem(
                kind: "entry", journalID: journal.id, title: "Work \(index)", document: .plain("Text"))
            try await store.save(entry)
            entries.append(entry)
        }
        return (journal, entries)
    }
    private func pinned(_ store: JournalStore) async throws -> Set<UUID> {
        try await store.libraryArrangement().pinned
    }
    private func conflictCount(_ store: JournalStore) async throws -> Int {
        try await store.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM conflicts") ?? 0 }
    }
    private func libraryPayload(_ object: [String: Any], for store: JournalStore) async throws -> String {
        var record = object
        record["id"] = LibraryRecord.id.uuidString
        record["kind"] = LibraryRecord.kind
        record["modifiedAt"] = "2026-10-03T12:00:00Z"
        record["title"] = "Pinned Entries and Journal Order"
        record["version"] = record["version"] ?? 1
        let json = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        return try await store.sealedPayload(json, id: LibraryRecord.id, kind: LibraryRecord.kind)
    }
    private func pinKey(_ id: UUID) -> String { "pinned/\(id.uuidString.lowercased())" }

    /// Checking a password opens the library with a key that may be wrong. What build 12 left for review is then
    /// left as it is, and converted when the right key opens the library: this device's pins stay.
    func testALeftoverReviewIsConvertedOnlyWithTheRightKey() async throws {
        let name = "mac-key"
        var mac: JournalStore? = try device(name)
        let store = try XCTUnwrap(mac)
        let (_, entries) = try await journalWithEntries(store, count: 2)
        try await store.setPinned(true, entry: entries[0].id)
        try await SyncEngine(store: store, server: MemoryServer()).synchronize()
        let other = try await libraryPayload(["values": [pinKey(entries[1].id): true]], for: store)
        try await store.close()
        mac = nil
        let database = try DatabaseQueue(path: root.appendingPathComponent("\(name)/journal.sqlite").path)
        try await database.write { db in
            try db.execute(
                sql: "INSERT INTO conflicts(record,payload,revision,device,modified) VALUES (?,?,?,?,?)",
                arguments: [
                    LibraryRecord.idText, other, 3, "00000000-0000-0000-0000-000000000000", "2026-10-03T12:00:00Z",
                ])
        }
        try database.close()

        let wrong = try device(name, key: try VaultCrypto.generateKey())
        try await wrong.close()
        let reopened = try device(name)
        let shown = try await pinned(reopened)
        XCTAssertEqual(shown, [entries[0].id, entries[1].id], "This device's pin stays and the other is added")
        let reviews = try await conflictCount(reopened)
        XCTAssertEqual(reviews, 0)
    }

    /// A library damaged where its records are kept, with a review an older version left for the library record
    /// still to convert, opens as before: the conversion doesn't stop it, and synchronizing reports that this
    /// device's data can't be read.
    func testADamagedLibraryWithLeftoversStillOpensAndReportsItsDataUnreadable() async throws {
        let name = "damaged"
        var mac: JournalStore? = try device(name)
        let store = try XCTUnwrap(mac)
        let (_, entries) = try await journalWithEntries(store, count: 40)
        try await store.setPinned(true, entry: entries[0].id)
        let other = try await libraryPayload(["values": [pinKey(entries[1].id): true]], for: store)
        try await store.close()
        mac = nil
        let file = root.appendingPathComponent("\(name)/journal.sqlite")
        let database = try DatabaseQueue(path: file.path)
        let (page, rootPage) = try await database.write { db -> (Int, Int) in
            try db.execute(
                sql: "INSERT INTO conflicts(record,payload,revision,device,modified) VALUES (?,?,?,?,?)",
                arguments: [
                    LibraryRecord.idText, other, 3, "00000000-0000-0000-0000-000000000000", "2026-10-03T12:00:00Z",
                ])
            let page = try Int.fetchOne(db, sql: "PRAGMA page_size") ?? 4096
            let rootPage = try Int.fetchOne(db, sql: "SELECT rootpage FROM sqlite_master WHERE name='records'") ?? 0
            return (page, rootPage)
        }
        try database.close()
        // The page where the records table starts is overwritten, as a failing disk would.
        var bytes = try Data(contentsOf: file)
        bytes.replaceSubrange(((rootPage - 1) * page)..<(rootPage * page), with: Data(repeating: 0x5A, count: page))
        try bytes.write(to: file)

        let damaged = try device(name)
        do {
            try await SyncEngine(store: damaged, server: MemoryServer()).synchronize()
            XCTFail("A damaged library synchronized")
        } catch {
            XCTAssertEqual(SyncHealth(classifying: error), .localDataUnreadable)
        }
    }

    /// Intents written by a newer version are of unknown lineage here, never read as this version's and rewritten.
    func testIntentsFromANewerVersionAreOfUnknownLineage() async throws {
        let mac = try device("mac")
        let (_, entries) = try await journalWithEntries(mac)
        let newer = try JSONSerialization.data(withJSONObject: [
            "version": 2,
            "changes": [pinKey(entries[0].id): ["value": true, "removes": false, "ifAbsent": false, "sent": false]],
        ])
        try await mac.setSetting(LibraryChanges.setting, value: Data(newer.base64EncodedString().utf8))
        let library = LibraryStore(key: key)
        let damaged = try await mac.db.read { try library.changes($0).damaged }
        XCTAssertTrue(damaged)
    }
}
