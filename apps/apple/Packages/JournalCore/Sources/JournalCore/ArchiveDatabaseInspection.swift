import CJournalArchive
import Foundation
import GRDB

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
    struct Table: Equatable {
        var columns: [Column]
        var indexes: [Index]
    }
    var tables: [String: Table]
    /// Triggers, views and any other object a migration doesn't create, and too many objects to look at.
    var unexpected: [String]

    static let migrationTable = "grdb_migrations"
    private static let objectLimit = 200

    /// The structure of the open database. Look-ups take the table name as an argument, so a hostile name can't change
    /// the statement.
    static func read(_ db: Database) throws -> DatabaseStructure {
        let rows = try Row.fetchAll(db, sql: "SELECT type, name FROM sqlite_master LIMIT \(objectLimit + 1)")
        var structure = DatabaseStructure(tables: [:], unexpected: [])
        if rows.count > objectLimit { structure.unexpected.append("more than \(objectLimit) objects") }
        for row in rows.prefix(objectLimit) {
            let type: String = row["type"]
            let name: String = row["name"]
            switch type {
            case "table" where name == "sqlite_sequence": continue
            case "table": structure.tables[name] = try table(named: name, in: db)
            case "index": continue
            default: structure.unexpected.append("\(type) \(name)")
            }
        }
        return structure
    }

    private static func table(named name: String, in db: Database) throws -> Table {
        let columns = try Row.fetchAll(
            db, sql: "SELECT name, type, \"notnull\", dflt_value, pk FROM pragma_table_info(?)", arguments: [name]
        ).map { row in
            // A primary key column counts as NOT NULL whether or not it says so: SQLite lets `TEXT PRIMARY KEY` hold
            // NULL, and a writer that adds NOT NULL has not made a different table.
            Column(
                name: row["name"], type: (row["type"] as String).uppercased(),
                notNull: (row["notnull"] as Int) != 0 || (row["pk"] as Int) > 0,
                defaultValue: (row["dflt_value"] as String?).map(normalizedDefault), primaryKey: row["pk"])
        }
        let listed = try Row.fetchAll(
            db, sql: "SELECT name, \"unique\", origin, partial FROM pragma_index_list(?)", arguments: [name])
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
        return Table(
            columns: columns.sorted { $0.name < $1.name }, indexes: indexes.sorted { $0.sortKey < $1.sortKey })
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
}

/// The check an archived database passes before a store is created for it, because creating one switches the file to
/// write-ahead logging and runs migrations that alter its tables. A hostile or damaged file must not get that far.
enum ArchiveDatabaseInspection {
    private static let fileHeader = Array("SQLite format 3\0".utf8)

    /// Throws `JournalError.invalidData` for a file that is not a rollback-journal SQLite database of this library,
    /// that fails SQLite's quick check, whose recorded migrations are not a prefix of this build's, or whose
    /// structure differs from what those migrations create (triggers and views included), and
    /// `JournalError.newerVersion` for a database with a migration this build doesn't know.
    static func inspect(_ file: URL) throws {
        try checkFileHeader(file)
        var configuration = Configuration()
        configuration.readonly = true
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA trusted_schema = OFF")
            guard journal_sqlite_enable_defensive(db.sqliteConnection) == SQLITE_OK else {
                throw JournalError.invalidData
            }
        }
        let (recorded, actual) = try describe(file, configuration: configuration)
        let known = JournalStore.migrator.migrations
        guard recorded.allSatisfy(known.contains) else { throw JournalError.newerVersion }
        // A reader applies the migrations that are not recorded, in order, so the recorded ones are the first ones.
        guard Set(recorded) == Set(known.prefix(recorded.count)), recorded.count == Set(recorded).count else {
            throw JournalError.invalidData
        }
        guard try DatabaseStructure.expected(afterMigrations: recorded.count).matches(actual) else {
            throw JournalError.invalidData
        }
    }

    /// The recorded migrations and the structure of a database that passed SQLite's quick check. SQLite reporting that
    /// it can't read the file is damage, not a reason to try again.
    private static func describe(_ file: URL, configuration: Configuration) throws -> ([String], DatabaseStructure) {
        do {
            let queue = try DatabaseQueue(path: file.path, configuration: configuration)
            defer { try? queue.close() }
            return try queue.read { db in
                guard try String.fetchAll(db, sql: "PRAGMA quick_check") == ["ok"] else {
                    throw JournalError.invalidData
                }
                guard try db.tableExists(DatabaseStructure.migrationTable) else { throw JournalError.invalidData }
                let identifiers = try String.fetchAll(
                    db, sql: "SELECT identifier FROM \(DatabaseStructure.migrationTable)")
                return (identifiers, try DatabaseStructure.read(db))
            }
        } catch is DatabaseError {
            throw JournalError.invalidData
        }
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
        _ directory: URL, key: Data, recovery: RecoveryEnvelope, protection: ContentProtection
    ) async throws -> VaultArchive.Restored {
        try ArchiveDatabaseInspection.inspect(directory.appendingPathComponent(ArchiveNames.database))
        var opened: JournalStore?
        do {
            let store = try JournalStore(directory: directory, key: key, protection: protection)
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
