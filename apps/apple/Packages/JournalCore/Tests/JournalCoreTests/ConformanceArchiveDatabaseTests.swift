import GRDB
import XCTest

@testable import JournalCore

/// protocol/conformance/archive/v2/database-v2.json: the structure a library database must have, and databases written
/// by something other than GRDB (database/make-foreign-database.py) that a reader must accept or refuse before it
/// creates a store for them (protocol/archive.md, Database).
final class ConformanceArchiveDatabaseTests: XCTestCase {
    private static let path = "archive/v2/database-v2.json"
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func setUp() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private struct Case: Decodable {
        let name: String
        let file: String
        let expect: String
        let note: String
    }
    private struct Fixture: Decodable {
        let cases: [Case]
    }

    private static let cases: [[String: String]] = [
        [
            "name": "foreign", "file": "database/foreign.sqlite", "expect": "accept",
            "note":
                "An empty library written by Python's sqlite3 in its own style: quoted identifiers, lower-case types, table constraints, NOT NULL on the primary keys.",
        ],
        [
            "name": "foreign-older", "file": "database/foreign-older.sqlite", "expect": "accept",
            "note":
                "Only v1, sync-reconciliation and history-record-index are recorded and created: a reader applies the other two migrations.",
        ],
        [
            "name": "foreign-trigger", "file": "database/foreign-trigger.sqlite", "expect": "damaged",
            "note": "A trigger the migrations do not create.",
        ],
        [
            "name": "foreign-view", "file": "database/foreign-view.sqlite", "expect": "damaged",
            "note": "A view the migrations do not create.",
        ],
        [
            "name": "foreign-extra-table", "file": "database/foreign-extra-table.sqlite", "expect": "damaged",
            "note": "A table the migrations do not create.",
        ],
        [
            "name": "foreign-missing-column", "file": "database/foreign-missing-column.sqlite", "expect": "damaged",
            "note": "records has no dirty column.",
        ],
        [
            "name": "foreign-nullable-column", "file": "database/foreign-nullable-column.sqlite", "expect": "damaged",
            "note": "records.kind may be NULL.",
        ],
        [
            "name": "foreign-unknown-migration", "file": "database/foreign-unknown-migration.sqlite", "expect": "newer",
            "note": "grdb_migrations lists a migration this version does not know: written by a newer version.",
        ],
        [
            "name": "foreign-migration-objects-missing", "file": "database/foreign-migration-objects-missing.sqlite",
            "expect": "damaged", "note": "server-versions is recorded but its table was never created.",
        ],
        [
            "name": "foreign-migrations-out-of-order", "file": "database/foreign-migrations-out-of-order.sqlite",
            "expect": "damaged", "note": "history-checkpoints is recorded without the migrations before it.",
        ],
        [
            "name": "foreign-wal", "file": "database/foreign-wal.sqlite", "expect": "damaged",
            "note": "File format versions 2 and 2 (write-ahead logging): not a one-file snapshot.",
        ],
    ]

    // MARK: The structure, as JSON

    static func describe(_ structure: DatabaseStructure) -> [String: Any] {
        var tables: [String: Any] = [:]
        for (name, table) in structure.tables {
            let columns = table.columns.map { column -> [String: Any] in
                [
                    "name": column.name, "type": column.type, "notNull": column.notNull,
                    "default": column.defaultValue ?? NSNull(), "primaryKey": column.primaryKey,
                ]
            }
            let indexes = table.indexes.map { index -> [String: Any] in
                [
                    "name": index.name ?? NSNull(), "unique": index.unique, "partial": index.partial,
                    "columns": index.columns,
                ]
            }
            tables[name] = ["columns": columns, "indexes": indexes]
        }
        return tables
    }

    private func generated() throws -> [String: Any] {
        let migrations = JournalStore.migrator.migrations
        var structures: [String: Any] = [:]
        for count in 1...migrations.count {
            structures[String(count)] = Self.describe(try DatabaseStructure.expected(afterMigrations: count))
        }
        return [
            "corpusVersion": 1,
            "purpose":
                "The structure of the library database after each migration (protocol/archive.md, Database), and databases written by something other than GRDB that a reader accepts or refuses before it opens them. See README.md in this folder.",
            "migrations": migrations,
            "structureAfter": structures,
            "comparison":
                "Tables, columns (name, declared type in upper case, NOT NULL, default without outer parentheses, primary key position) and indexes (CREATE INDEX name, uniqueness, partial, key columns) are compared; the text of CREATE statements is not. A primary key column counts as NOT NULL. grdb_migrations is compared by its identifier column only. sqlite_sequence is ignored. Triggers, views and any other table or index are refused.",
            "cases": Self.cases,
        ]
    }

    private func fixture() throws -> [String: Any] {
        try Conformance.fixture(Self.path, generate: generated)
    }

    func testTheStructureIsWhatTheMigrationsCreate() throws {
        let stored = try fixture()
        XCTAssertTrue(try Conformance.same(try generated(), stored))
    }

    // MARK: Inspection before a store exists

    func testEveryDatabaseCaseGivesTheStatedOutcome() throws {
        _ = try fixture()
        let cases = try Conformance.decode(Fixture.self, Self.path).cases
        XCTAssertGreaterThanOrEqual(cases.count, 10)
        for item in cases {
            let copy = root.appendingPathComponent(item.name + ".sqlite")
            try FileManager.default.copyItem(at: Conformance.url("archive/v2/" + item.file), to: copy)
            do {
                try ArchiveDatabaseInspection.inspect(copy)
                XCTAssertEqual(item.expect, "accept", item.name)
            } catch {
                XCTAssertEqual(ConformanceContainerTests.outcome(of: error), item.expect, "\(item.name): \(error)")
            }
        }
    }

    /// Inspection reads the file and nothing else: it neither switches it to write-ahead logging nor migrates it.
    func testInspectionLeavesTheDatabaseAsItFoundIt() throws {
        let copy = root.appendingPathComponent("older.sqlite")
        try FileManager.default.copyItem(at: Conformance.url("archive/v2/database/foreign-older.sqlite"), to: copy)
        let before = try Data(contentsOf: copy)
        try ArchiveDatabaseInspection.inspect(copy)
        XCTAssertEqual(try Data(contentsOf: copy), before)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(siblings, ["older.sqlite"])
    }

    /// A hostile database is refused before any migration runs: the trigger in this one would fire on the first write.
    func testAMalformedFileIsDamagedNotAnError() throws {
        let junk = root.appendingPathComponent("junk.sqlite")
        try Data(repeating: 0x41, count: 4096).write(to: junk)
        XCTAssertThrowsError(try ArchiveDatabaseInspection.inspect(junk)) {
            XCTAssertEqual(ConformanceContainerTests.outcome(of: $0), "damaged")
        }
        var bytes = try Data(contentsOf: Conformance.url("archive/v2/database/foreign.sqlite"))
        // The second page is a table's root page: damage there is not in unused space.
        bytes[4096...4296] = Data(repeating: 0xFF, count: 201)
        let torn = root.appendingPathComponent("torn.sqlite")
        try bytes.write(to: torn)
        XCTAssertThrowsError(try ArchiveDatabaseInspection.inspect(torn)) {
            XCTAssertEqual(ConformanceContainerTests.outcome(of: $0), "damaged")
        }
    }

    // MARK: A foreign database through a whole file archive

    private func archive(around database: String) throws -> (URL, Data, RecoveryEnvelope, String) {
        let key = try VaultCrypto.generateKey()
        let phrase = "a password for the foreign database"
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase, formatVersion: 2).0
        let copy = root.appendingPathComponent("\(database)-copy.sqlite")
        try FileManager.default.copyItem(at: Conformance.url("archive/v2/database/\(database).sqlite"), to: copy)
        let archive = root.appendingPathComponent("\(database).zip")
        try FileArchive.write(
            databaseFile: copy, images: [], recovery: recovery, key: key, to: archive, options: .standard)
        return (archive, key, recovery, phrase)
    }

    /// A database from another client opens as a library: its structure is what the migrations create, so the store
    /// opens it, and an older one is migrated up.
    func testAForeignDatabaseRestoresAsALibrary() async throws {
        for name in ["foreign", "foreign-older"] {
            let (archive, _, _, phrase) = try archive(around: name)
            let restored = try await VaultArchive.restore(
                from: archive, to: root.appendingPathComponent("restored-\(name)"), phrase: phrase)
            let items = try await restored.store.items()
            XCTAssertTrue(items.isEmpty, name)
            try await restored.store.validateSchema()
            try await restored.store.close()
            let queue = try DatabaseQueue(path: root.appendingPathComponent("restored-\(name)/journal.sqlite").path)
            let applied = try await queue.read {
                try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations")
            }
            XCTAssertEqual(Set(applied), Set(JournalStore.migrator.migrations), name)
            try queue.close()
        }
    }

    func testARefusedDatabaseLeavesNoStagingDirectory() async throws {
        for (name, expected) in [
            ("foreign-trigger", "damaged"), ("foreign-unknown-migration", "newer"), ("foreign-wal", "damaged"),
        ] {
            let (archive, _, _, phrase) = try archive(around: name)
            let destination = root.appendingPathComponent("restored-\(name)")
            do {
                _ = try await VaultArchive.restore(from: archive, to: destination, phrase: phrase)
                XCTFail("\(name) must be refused")
            } catch {
                XCTAssertEqual(ConformanceContainerTests.outcome(of: error), expected, name)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path), name)
        }
    }
}
