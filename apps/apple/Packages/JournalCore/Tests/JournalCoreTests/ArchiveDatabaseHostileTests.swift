import CJournalArchive
import GRDB
import XCTest
import os

@testable import JournalCore

/// A database inside an archive is written by whoever made the archive. These tests build the ones that cost
/// something to look at (a schema of thousands of objects, a table of a million rows) and check how the inspection
/// meets them: refused from the file's pages or after a bounded read, with the statements it ran as the evidence, and
/// stoppable while it runs (protocol/archive.md, Database and Limits).
final class ArchiveDatabaseHostileTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private static let smallPages = "archive/v2/database/foreign-small-pages.sqlite"

    override func setUp() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    /// A copy of a fixture to change.
    private func fixtureCopy(
        _ fixture: String = ArchiveDatabaseHostileTests.smallPages, as name: String = UUID().uuidString
    ) throws -> URL {
        let target = root.appendingPathComponent(name + ".sqlite")
        try FileManager.default.copyItem(at: Conformance.url(fixture), to: target)
        return target
    }

    /// Inspects `file` and returns the class of its outcome and every statement the inspection ran.
    private func inspect(_ file: URL, budget: Duration? = nil) async -> (String, [String]) {
        let statements = OSAllocatedUnfairLock(initialState: [String]())
        var options = ArchiveOptions.standard
        if let budget { options.inspectionBudget = budget }
        options.inspectionStatements = { sql in
            // The read transaction around each step is GRDB's.
            if sql != "BEGIN DEFERRED TRANSACTION", sql != "COMMIT TRANSACTION" {
                statements.withLock { $0.append(sql) }
            }
        }
        do {
            try await ArchiveDatabaseInspection.inspect(file, options: options)
            return ("accept", statements.withLock { $0 })
        } catch {
            return (ConformanceContainerTests.outcome(of: error), statements.withLock { $0 })
        }
    }

    /// Changes the file with a connection that may edit the schema, as a hostile writer can. The system's SQLite is
    /// already defensive by default on current systems, which would refuse `sqlite_master` edits.
    private func changing(_ file: URL, _ change: (Database) throws -> Void) throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            XCTAssertEqual(journal_sqlite_set_defensive(db.sqliteConnection, 0), SQLITE_OK)
        }
        let queue = try DatabaseQueue(path: file.path, configuration: configuration)
        try queue.write(change)
        try queue.close()
    }

    // MARK: Before SQLite parses the schema

    /// A virtual table connects, running its module's code, the first time a statement or a pragma refers to it, and
    /// `PRAGMA quick_check` refers to every table. It is refused from the schema table, before either runs.
    func testAVirtualTableIsRefusedBeforeAnyStatementTouchesIt() async throws {
        let file = try fixtureCopy("archive/v2/database/foreign-virtual-table.sqlite")
        let (outcome, statements) = await inspect(file)
        XCTAssertEqual(outcome, "damaged")
        // GRDB's own check that the file is a database, then ours; neither names a table of the file.
        XCTAssertEqual(
            statements,
            [
                "SELECT * FROM sqlite_master LIMIT 1",
                "SELECT type, name, tbl_name, rootpage, sql FROM sqlite_master LIMIT \(ArchiveLimits.schemaObjects + 1)",
            ])
    }

    /// A virtual table has no pages of its own (rootpage 0), and SQLite loads such a row without connecting it. One in
    /// the name of a library table is refused from the schema table, so that table is never asked about.
    func testAVirtualTableInTheNameOfALibraryTableIsRefused() async throws {
        let file = try fixtureCopy()
        try changing(file) { db in
            try db.execute(sql: "PRAGMA writable_schema = ON")
            try db.execute(
                sql: """
                    UPDATE sqlite_master SET rootpage = 0, sql = 'CREATE  /* x */ VIRTUAL TABLE attachments USING fts5(id)'
                    WHERE type = 'table' AND name = 'attachments'
                    """)
            try db.execute(sql: "DELETE FROM sqlite_master WHERE name = 'sqlite_autoindex_attachments_1'")
            try db.execute(sql: "PRAGMA writable_schema = OFF")
        }
        let (outcome, statements) = await inspect(file)
        XCTAssertEqual(outcome, "damaged")
        XCTAssertTrue(statements.contains { $0.contains("FROM sqlite_master LIMIT") }, "the schema loaded and was read")
        XCTAssertFalse(statements.contains { $0.lowercased().contains("quick_check") })
        XCTAssertFalse(statements.contains { $0.lowercased().contains("pragma_") })
    }

    /// The statements no pragma reports, found by the words of the stored text and not by where they sit.
    func testTheWordsNoPragmaReportsAreFoundOutsideQuotesAndComments() {
        for (sql, word) in [
            ("CREATE TABLE t (a CHECK (a > 0))", "CHECK"), ("create table t (a text collate nocase)", "COLLATE"),
            ("CREATE TABLE t (a UNIQUE ON CONFLICT REPLACE)", "CONFLICT"),
            ("CREATE TABLE t (a, b AS (a + 1))", "AS"),
            ("CREATE TABLE t (a, FOREIGN KEY (a) REFERENCES p DEFERRABLE INITIALLY DEFERRED)", "DEFERRABLE"),
            ("CREATE TABLE t (a, b GENERATED ALWAYS AS (a))", "GENERATED"),
            ("CREATE  /* x */ VIRTUAL TABLE t USING fts5(a)", "VIRTUAL"),
            ("CREATE TABLE t (a TEXT) -- x\n, CHECK (1)", "CHECK"),
        ] {
            XCTAssertTrue(ArchiveSchemaWords.refusedWords(in: sql).contains(word), "\(word) in \(sql)")
        }
        for sql in [
            "CREATE TABLE t (\"check\" TEXT, [collate] TEXT, `as` TEXT, 'virtual')",
            "CREATE TABLE t (a TEXT /* CHECK */) -- COLLATE",
            "CREATE TABLE t (a TEXT DEFAULT 'GENERATED ALWAYS AS')",
            "CREATE TABLE t (checked TEXT, collated TEXT, as_of TEXT, CHECK\u{E9} TEXT)",
        ] {
            XCTAssertEqual(ArchiveSchemaWords.refusedWords(in: sql), [], sql)
        }
    }

    /// Thousands of schema rows: refused from the pages, so SQLite never parses them and no statement runs at all.
    func testALargeSchemaIsRefusedBeforeSQLiteLoadsIt() async throws {
        let file = try fixtureCopy()
        try changing(file) { db in
            try db.execute(sql: "PRAGMA writable_schema = ON")
            try db.execute(
                sql: """
                    WITH RECURSIVE counter(number) AS (SELECT 1 UNION ALL SELECT number + 1 FROM counter WHERE number < 20000)
                    INSERT INTO sqlite_master(type, name, tbl_name, rootpage, sql)
                    SELECT 'view', 'v' || number, 'v' || number, 0, 'CREATE VIEW v' || number || ' AS SELECT 1' FROM counter
                    """)
            try db.execute(sql: "PRAGMA writable_schema = OFF")
        }
        let (outcome, statements) = await inspect(file)
        XCTAssertEqual(outcome, "damaged")
        XCTAssertEqual(statements, [])
    }

    /// One object whose statement is huge (it spills onto overflow pages) is over the byte limit.
    func testAHugeSchemaStatementIsRefusedBeforeSQLiteLoadsIt() async throws {
        let file = try fixtureCopy()
        try changing(file) { db in
            try db.execute(sql: "PRAGMA writable_schema = ON")
            let filler = String(repeating: "x", count: 1_000_000)
            try db.execute(
                sql:
                    "INSERT INTO sqlite_master(type, name, tbl_name, rootpage, sql) VALUES ('view', 'big', 'big', 0, ?)",
                arguments: ["CREATE VIEW big AS SELECT '\(filler)'"])
            try db.execute(sql: "PRAGMA writable_schema = OFF")
        }
        let (outcome, statements) = await inspect(file)
        XCTAssertEqual(outcome, "damaged")
        XCTAssertEqual(statements, [])
    }

    /// More real objects than a library has, each one valid.
    func testMoreObjectsThanALibraryHasAreRefusedBeforeSQLiteLoadsThem() async throws {
        let file = try fixtureCopy()
        try changing(file) { db in
            for number in 0..<ArchiveLimits.schemaObjects { try db.execute(sql: "CREATE TABLE extra\(number) (a)") }
        }
        let (outcome, statements) = await inspect(file)
        XCTAssertEqual(outcome, "damaged")
        XCTAssertEqual(statements, [])
    }

    // MARK: The scan agrees with SQLite

    func testTheScanCountsWhatSQLiteLists() throws {
        var scanned: [ArchiveSchemaScan.Summary] = []
        for fixture in [
            "archive/v2/database/foreign.sqlite", Self.smallPages, "archive/v2/database/foreign-virtual-table.sqlite",
            "archive/v1/encrypted/journal.sqlite",
        ] {
            let file = try fixtureCopy(fixture)
            let summary = try ArchiveSchemaScan.scan(file)
            let queue = try DatabaseQueue(path: file.path)
            let rows = try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM sqlite_master") }
            try queue.close()
            XCTAssertEqual(summary.rows, rows, fixture)
            scanned.append(summary)
        }
        XCTAssertEqual(scanned[0].pages, 1, "the schema of a 4096-byte page library is one leaf")
        XCTAssertGreaterThan(scanned[1].pages, 1, "the schema of the small-page library has interior pages")
    }

    /// A tree whose page refers to itself ends the scan with damage instead of looping.
    func testAScanOfAPageThatPointsAtItselfEnds() throws {
        let file = try fixtureCopy()
        var bytes = try Data(contentsOf: file)
        XCTAssertEqual(bytes[100], 0x05, "page 1 is an interior page")
        // The first cell pointer, then the 4-byte child number at the start of that cell.
        let cell = Int(bytes[112]) << 8 | Int(bytes[113])
        bytes.replaceSubrange(cell..<(cell + 4), with: [0, 0, 0, 1])
        try bytes.write(to: file)
        XCTAssertThrowsError(try ArchiveSchemaScan.scan(file)) {
            XCTAssertEqual(ConformanceContainerTests.outcome(of: $0), "damaged")
        }
    }

    func testAScanOfAPageThatIsNotATableTreeIsDamaged() throws {
        let file = try fixtureCopy()
        var bytes = try Data(contentsOf: file)
        bytes[100] = 0x0A
        try bytes.write(to: file)
        XCTAssertThrowsError(try ArchiveSchemaScan.scan(file)) {
            XCTAssertEqual(ConformanceContainerTests.outcome(of: $0), "damaged")
        }
    }

    // MARK: Bounded reads

    /// The recorded migrations are read with a limit: a table of a million identifiers is not fetched.
    func testAHugeMigrationTableIsReadWithALimit() async throws {
        let file = try fixtureCopy()
        try changing(file) { db in
            try db.execute(
                sql: """
                    WITH RECURSIVE counter(number) AS (SELECT 1 UNION ALL SELECT number + 1 FROM counter WHERE number < 200000)
                    INSERT INTO grdb_migrations(identifier) SELECT 'later-' || number FROM counter
                    """)
        }
        let (outcome, statements) = await inspect(file)
        XCTAssertEqual(outcome, "newer")
        let migrations = statements.filter { $0.contains("SELECT identifier FROM") }
        XCTAssertEqual(migrations.count, 1)
        XCTAssertTrue(migrations[0].contains("LIMIT \(JournalStore.migrator.migrations.count + 1)"), migrations[0])
    }

    // MARK: Cancellation and the clock

    private static let foreverStatement =
        "WITH RECURSIVE counter(number) AS (SELECT 1 UNION ALL SELECT number + 1 FROM counter) SELECT MAX(number) FROM counter"

    /// A statement that never ends is stopped by cancelling the task: SQLite is interrupted, not waited for.
    func testCancellingTheTaskInterruptsARunningStatement() async throws {
        let queue = try DatabaseQueue()
        let statement = Self.foreverStatement
        let task = Task {
            try await ArchiveDatabaseInspection.bounded(queue, nil) { db in
                try Int.fetchOne(db, sql: statement)
            }
        }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("The statement never ends")
        } catch is CancellationError {}
    }

    /// The same statement meets the wall-clock budget instead: the file is refused as damaged.
    func testAStepThatOutlastsItsBudgetIsDamage() async throws {
        let queue = try DatabaseQueue()
        let statement = Self.foreverStatement
        do {
            _ = try await ArchiveDatabaseInspection.bounded(queue, .milliseconds(150)) { db in
                try Int.fetchOne(db, sql: statement)
            }
            XCTFail("The statement never ends")
        } catch JournalError.invalidData {}
    }

    /// Cancelling while `PRAGMA quick_check` runs ends the inspection as a cancellation, not as damage, and leaves the
    /// file as it was.
    func testCancellingDuringQuickCheckEndsTheInspection() async throws {
        let file = try fixtureCopy()
        let before = try Data(contentsOf: file)
        let holder = OSAllocatedUnfairLock(initialState: Task<Void, Error>?.none)
        var configured = ArchiveOptions.standard
        configured.inspectionStatements = { statement in
            guard statement.contains("quick_check") else { return }
            // The task is stored just after it starts; wait for that, then cancel it from inside its own statement.
            while holder.withLock({ $0 }) == nil { usleep(100) }
            holder.withLock { $0?.cancel() }
        }
        let options = configured
        let task = Task { try await ArchiveDatabaseInspection.inspect(file, options: options) }
        holder.withLock { $0 = task }
        do {
            _ = try await task.value
            XCTFail("A cancelled inspection must not complete")
        } catch is CancellationError {}
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    // MARK: The live store

    /// The library's own connection takes the same precautions, because a restored library is opened by it. (Current
    /// systems' SQLite is defensive and distrusts schemas by default, so this holds with or without the explicit
    /// calls; they are for the builds that don't.)
    func testTheStoreDistrustsItsSchemaAndRefusesToEditIt() async throws {
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root.appendingPathComponent("library"), key: key)
        let (trusted, writable) = try await store.db.write { db -> (Int?, Int?) in
            try db.execute(sql: "PRAGMA writable_schema = ON")
            return (
                try Int.fetchOne(db, sql: "PRAGMA trusted_schema"), try Int.fetchOne(db, sql: "PRAGMA writable_schema")
            )
        }
        XCTAssertEqual(trusted, 0)
        XCTAssertEqual(writable, 0, "defensive mode ignores PRAGMA writable_schema = ON")
        try await store.close()
    }
}
