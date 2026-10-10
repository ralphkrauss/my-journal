import CJournalArchive
import Foundation
import GRDB

/// One row of `sqlite_master`.
struct SchemaObject: Equatable {
    let type: String
    let name: String
    let table: String
    let rootPage: Int
    let sql: String?

    init(_ row: Row) {
        type = row["type"]
        name = row["name"]
        table = row["tbl_name"]
        rootPage = row["rootpage"]
        sql = row["sql"]
    }

    /// Why this object cannot be part of a library, in words for a log: a trigger or a view, which would act on later
    /// writes; a virtual table, which runs a module's code when it is first touched; anything stored without pages
    /// or without its statement; and the clauses of `ArchiveSchemaWords.refused`.
    var refusals: [String] {
        guard type == "table" || type == "index" else { return ["\(type) \(name)"] }
        guard rootPage > 0 else { return ["\(type) \(name) has no pages"] }
        guard let sql else {
            // The index SQLite makes for a primary key or a UNIQUE constraint has no statement of its own.
            let automatic = type == "index" && name.hasPrefix("sqlite_autoindex_")
            return automatic ? [] : ["\(type) \(name) has no statement"]
        }
        return ArchiveSchemaWords.refusedWords(in: sql).map { "\(type) \(name) uses \($0)" }
    }
}

/// The structure of a library database, read from SQLite's own descriptions rather than from `CREATE` text, which EF
/// Core, Microsoft.Data.Sqlite and GRDB each write differently for the same table (protocol/archive.md, Database).
struct DatabaseStructure: Equatable {
    struct Column: Equatable {
        let name: String
        let type: String
        let notNull: Bool
        let defaultValue: String?
        let primaryKey: Int
    }
    struct Index: Equatable {
        /// Only an index made by `CREATE INDEX` has a name that counts; the ones SQLite makes for a primary key or a
        /// `UNIQUE` constraint are named by the order of the constraints.
        let name: String?
        let unique: Bool
        let partial: Bool
        let columns: [String]

        var sortKey: String { "\(name ?? "")|\(unique)|\(partial)|\(columns.joined(separator: ","))" }
    }
    struct ForeignKey: Equatable {
        let table: String
        let from: String
        /// The parent column; a key that names none refers to the parent's primary key, and is read as that column.
        var to: String?
        let onUpdate: String
        let onDelete: String
        let match: String

        var sortKey: String { "\(from)|\(table)|\(to ?? "")|\(onUpdate)|\(onDelete)|\(match)" }
    }
    struct Table: Equatable {
        var columns: [Column]
        var indexes: [Index]
        var foreignKeys: [ForeignKey]
        /// Whether the statement says `AUTOINCREMENT`, which no pragma reports.
        var autoincrement: Bool
    }
    var tables: [String: Table]
    /// Triggers, views, virtual tables, generated or hidden columns, `WITHOUT ROWID` and `STRICT` tables, the clauses of
    /// `ArchiveSchemaWords.refused`, any other object a migration doesn't create, and too many objects to look at.
    var unexpected: [String]

    static let migrationTable = "grdb_migrations"

    /// The objects of the open database, at most `ArchiveLimits.schemaObjects`: more is not a library.
    static func schemaObjects(_ db: Database) throws -> [SchemaObject] {
        let rows = try Row.fetchAll(
            db,
            sql:
                "SELECT type, name, tbl_name, rootpage, sql FROM sqlite_master LIMIT \(ArchiveLimits.schemaObjects + 1)"
        )
        guard rows.count <= ArchiveLimits.schemaObjects else { throw JournalError.invalidData }
        return rows.map(SchemaObject.init)
    }

    /// The structure of the open database. Look-ups take the table name as an argument, so a hostile name can't change
    /// the statement, and they are made only when no object has been refused: the pragmas connect a virtual table.
    static func read(_ db: Database) throws -> DatabaseStructure {
        let objects = try schemaObjects(db)
        var structure = DatabaseStructure(tables: [:], unexpected: objects.flatMap(\.refusals))
        guard structure.unexpected.isEmpty else { return structure }
        for object in objects where object.type == "table" && object.name != "sqlite_sequence" {
            structure.tables[object.name] = try table(object, in: db, unexpected: &structure.unexpected)
        }
        structure.resolveImplicitParentColumns()
        return structure
    }

    private static func table(_ object: SchemaObject, in db: Database, unexpected: inout [String]) throws -> Table {
        let name = object.name
        try requirePlainTable(name, in: db, unexpected: &unexpected)
        let columns = try Row.fetchAll(
            db, sql: "SELECT name, type, \"notnull\", dflt_value, pk, hidden FROM pragma_table_xinfo(?)",
            arguments: [name]
        ).map { row in
            if (row["hidden"] as Int) != 0 { unexpected.append("column \(row["name"] as String) of \(name) is hidden") }
            // A primary key column counts as NOT NULL whether or not it says so: SQLite lets `TEXT PRIMARY KEY` hold
            // NULL, and a writer that adds NOT NULL has not made a different table.
            return Column(
                name: row["name"], type: (row["type"] as String).uppercased(),
                notNull: (row["notnull"] as Int) != 0 || (row["pk"] as Int) > 0,
                defaultValue: (row["dflt_value"] as String?).map(normalizedDefault), primaryKey: row["pk"])
        }
        let words = ArchiveSchemaWords.words(in: object.sql ?? "")
        return Table(
            columns: columns.sorted { $0.name < $1.name }, indexes: try indexes(of: name, in: db),
            foreignKeys: try foreignKeys(of: name, in: db).sorted { $0.sortKey < $1.sortKey },
            autoincrement: words.contains("AUTOINCREMENT"))
    }

    /// A table that is not virtual (the module's code would run), not `WITHOUT ROWID` and not `STRICT`.
    private static func requirePlainTable(_ name: String, in db: Database, unexpected: inout [String]) throws {
        let rows = try Row.fetchAll(
            db, sql: "SELECT type, wr, strict FROM pragma_table_list(?) WHERE schema = 'main' AND name = ?",
            arguments: [name, name])
        guard rows.count == 1, let row = rows.first, (row["type"] as String) == "table" else {
            unexpected.append("table \(name) is not an ordinary table")
            return
        }
        if (row["wr"] as Int) != 0 { unexpected.append("table \(name) is WITHOUT ROWID") }
        if (row["strict"] as Int) != 0 { unexpected.append("table \(name) is STRICT") }
    }

    private static func indexes(of table: String, in db: Database) throws -> [Index] {
        let listed = try Row.fetchAll(
            db, sql: "SELECT name, \"unique\", origin, partial FROM pragma_index_list(?)", arguments: [table])
        var indexes: [Index] = []
        for row in listed {
            let indexName: String = row["name"]
            let origin: String = row["origin"]
            let keyColumns = try String?.fetchAll(
                db, sql: "SELECT name FROM pragma_index_xinfo(?) WHERE key = 1 ORDER BY seqno", arguments: [indexName]
            ).map { $0 ?? "<expression>" }
            indexes.append(
                Index(
                    name: origin == "c" ? indexName : nil, unique: (row["unique"] as Int) != 0,
                    partial: (row["partial"] as Int) != 0, columns: keyColumns))
        }
        return indexes.sorted { $0.sortKey < $1.sortKey }
    }

    private static func foreignKeys(of table: String, in db: Database) throws -> [ForeignKey] {
        try Row.fetchAll(
            db,
            sql:
                "SELECT \"table\", \"from\", \"to\", on_update, on_delete, \"match\" FROM pragma_foreign_key_list(?)",
            arguments: [table]
        ).map { row in
            ForeignKey(
                table: row["table"], from: row["from"], to: row["to"],
                onUpdate: (row["on_update"] as String).uppercased(),
                onDelete: (row["on_delete"] as String).uppercased(), match: (row["match"] as String).uppercased())
        }
    }

    /// `REFERENCES records` and `REFERENCES records (id)` are the same key when `id` is the primary key.
    private mutating func resolveImplicitParentColumns() {
        for (name, table) in tables {
            var resolved = table
            resolved.foreignKeys = table.foreignKeys.map { key in
                guard key.to == nil, let parent = tables[key.table] else { return key }
                let primary = parent.columns.filter { $0.primaryKey > 0 }
                var copy = key
                if primary.count == 1 { copy.to = primary[0].name }
                return copy
            }
            resolved.foreignKeys.sort { $0.sortKey < $1.sortKey }
            tables[name] = resolved
        }
    }

    /// `DEFAULT 0` and `DEFAULT (0)` are the same default.
    private static func normalizedDefault(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("("), value.hasSuffix(")") {
            value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    /// Whether `other` is the same structure. The migration library's own table is compared by its column only: its
    /// text and its constraints differ between versions of the library and between writers.
    func matches(_ other: DatabaseStructure) -> Bool {
        guard unexpected.isEmpty, other.unexpected.isEmpty, Set(tables.keys) == Set(other.tables.keys) else {
            return false
        }
        for (name, table) in tables {
            guard let counterpart = other.tables[name] else { return false }
            if name == Self.migrationTable {
                let columns = { (table: Table) in table.columns.map { [$0.name, String($0.primaryKey)] } }
                guard columns(table) == columns(counterpart) else { return false }
            } else {
                guard table == counterpart else { return false }
            }
        }
        return true
    }

    /// The structure the first `count` migrations of this build create.
    static func expected(afterMigrations count: Int) throws -> DatabaseStructure {
        let queue = try DatabaseQueue()
        let migrator = JournalStore.migrator
        if count == 0 {
            try queue.write {
                try $0.execute(sql: "CREATE TABLE \(migrationTable) (identifier TEXT NOT NULL PRIMARY KEY)")
            }
        } else {
            try migrator.migrate(queue, upTo: migrator.migrations[count - 1])
        }
        return try queue.read(read)
    }

    /// The names of the tables and of the indexes made by `CREATE INDEX` that any migration of this build creates.
    static func knownNames() throws -> (tables: Set<String>, indexes: Set<String>) {
        let latest = try expected(afterMigrations: JournalStore.migrator.migrations.count)
        let indexes = latest.tables.values.flatMap(\.indexes).compactMap(\.name)
        return (Set(latest.tables.keys).union(["sqlite_sequence"]), Set(indexes))
    }
}

extension Database {
    /// For a database whose schema someone else wrote: a view, trigger, default or generated column may call only
    /// functions SQLite marks innocuous (`trusted_schema` off), and the connection can't edit the schema or the
    /// shadow tables of a virtual table (`SQLITE_DBCONFIG_DEFENSIVE`).
    func hardenAgainstHostileSchema() throws {
        try execute(sql: "PRAGMA trusted_schema = OFF")
        guard journal_sqlite_set_defensive(sqliteConnection, 1) == SQLITE_OK else { throw JournalError.invalidData }
    }
}

/// The check an archived database passes before a store is created for it, because creating one switches the file to
/// write-ahead logging and runs migrations that alter its tables. A hostile or damaged file must not get that far.
///
/// The order matters, because each step must be safe given the ones before it:
/// 1. the file header, then the size of the schema table, read from the file's pages with no SQL at all;
/// 2. the objects the schema table lists, which must be the library's own (a virtual table connects, running its
///    module's code, the first time a statement or a pragma touches it, and quick_check does);
/// 3. `PRAGMA quick_check`, so nothing below reads a malformed file;
/// 4. the recorded migrations and the structure, from the pragmas.
enum ArchiveDatabaseInspection {
    private static let fileHeader = Array("SQLite format 3\0".utf8)

    /// Throws `JournalError.invalidData` for a file that is not a rollback-journal SQLite database of this library,
    /// that fails SQLite's quick check, whose recorded migrations are not a prefix of this build's, or whose
    /// structure differs from what those migrations create (triggers and views included), and
    /// `JournalError.newerVersion` for a database with a migration this build doesn't know. Cancelling the task
    /// interrupts the running statement; a step that takes longer than `options.inspectionBudget` is refused.
    static func inspect(_ file: URL, options: ArchiveOptions = .standard) async throws {
        try checkFileHeader(file)
        _ = try ArchiveSchemaScan.scan(file)
        let known = JournalStore.migrator.migrations
        let (recorded, actual): ([String], DatabaseStructure)
        do {
            let queue = try openReadOnly(file, options: options)
            defer { try? queue.close() }
            try await bounded(queue, options.inspectionBudget, checkObjects)
            try await bounded(queue, nil, checkIntegrity)
            (recorded, actual) = try await bounded(queue, options.inspectionBudget) { db in
                guard try db.tableExists(DatabaseStructure.migrationTable) else { throw JournalError.invalidData }
                // One more than there are migrations: more is a repeated identifier or an unknown one.
                let identifiers = try String.fetchAll(
                    db,
                    sql:
                        "SELECT identifier FROM \(DatabaseStructure.migrationTable) ORDER BY rowid LIMIT \(known.count + 1)"
                )
                return (identifiers, try DatabaseStructure.read(db))
            }
        } catch is DatabaseError {
            throw JournalError.invalidData
        }
        guard recorded.allSatisfy(known.contains) else { throw JournalError.newerVersion }
        // A reader applies the migrations that are not recorded, in order, so the recorded ones are the first ones.
        guard Set(recorded) == Set(known.prefix(recorded.count)), recorded.count == Set(recorded).count else {
            throw JournalError.invalidData
        }
        guard try DatabaseStructure.expected(afterMigrations: recorded.count).matches(actual) else {
            throw JournalError.invalidData
        }
    }

    private static func openReadOnly(_ file: URL, options: ArchiveOptions) throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.readonly = true
        let statements = options.inspectionStatements
        configuration.prepareDatabase { db in
            try db.hardenAgainstHostileSchema()
            if let statements {
                db.trace(options: .statement) { event in
                    if case .statement(let statement) = event { statements(statement.sql) }
                }
            }
        }
        return try DatabaseQueue(path: file.path, configuration: configuration)
    }

    /// Runs `work` on the connection, off the calling thread. Cancelling the task, or `budget` passing, interrupts the
    /// statement that runs (SQLite stops it at its next step), which is damage unless the task was cancelled.
    static func bounded<T: Sendable>(
        _ queue: DatabaseQueue, _ budget: Duration?, _ work: @escaping @Sendable (Database) throws -> T
    ) async throws -> T {
        try Task.checkCancellation()
        let watchdog = budget.map { limit in
            Task {
                try? await Task.sleep(for: limit)
                if !Task.isCancelled { queue.interrupt() }
            }
        }
        defer { watchdog?.cancel() }
        do {
            return try await withTaskCancellationHandler {
                try await queue.read(work)
            } onCancel: {
                queue.interrupt()
            }
        } catch let error as DatabaseError where error.resultCode == .SQLITE_INTERRUPT {
            try Task.checkCancellation()
            throw JournalError.invalidData
        }
    }

    /// Step 2: only the library's own tables and indexes, written without the clauses no pragma reports.
    @Sendable private static func checkObjects(_ db: Database) throws {
        let objects = try DatabaseStructure.schemaObjects(db)
        guard objects.allSatisfy({ $0.refusals.isEmpty }) else { throw JournalError.invalidData }
        let known = try DatabaseStructure.knownNames()
        for object in objects {
            let isKnown = object.type == "table" ? known.tables : known.indexes
            // An index without a statement is the one SQLite makes for a key; `refusals` checked its name.
            guard object.sql == nil || isKnown.contains(object.name) else { throw JournalError.invalidData }
        }
    }

    /// Step 3. Reads every page of the file, which is the cost of having extracted it.
    @Sendable private static func checkIntegrity(_ db: Database) throws {
        guard try String.fetchAll(db, sql: "PRAGMA quick_check") == ["ok"] else { throw JournalError.invalidData }
    }

    /// The first 100 bytes: the magic text and, at offsets 18 and 19, the file format write and read versions, which
    /// are 1 for rollback-journal mode (2 means write-ahead logging, which a one-file snapshot must not use).
    private static func checkFileHeader(_ file: URL) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let header = [UInt8](try handle.read(upToCount: 100) ?? Data())
        guard header.count == 100, header.starts(with: fileHeader), header[18] == 1, header[19] == 1 else {
            throw JournalError.invalidData
        }
    }
}

/// Opens the database a restore or an archive inspection extracted.
enum ArchiveStaging {
    /// Inspects the staged database, then opens it as a library and runs the checks that need a store. The caller
    /// owns `directory` and removes it if this throws.
    static func open(
        _ directory: URL, key: Data, recovery: RecoveryEnvelope,
        options: ArchiveOptions = .standard
    ) async throws -> VaultArchive.Restored {
        try await ArchiveDatabaseInspection.inspect(
            directory.appendingPathComponent(ArchiveNames.database), options: options)
        var opened: JournalStore?
        do {
            let store = try JournalStore(directory: directory, key: key)
            opened = store
            try await store.validateSchema()
            try await store.validateSnapshot()
            try Task.checkCancellation()
            return VaultArchive.Restored(store: store, key: key, recovery: recovery)
        } catch {
            try? await opened?.close()
            throw error
        }
    }
}
