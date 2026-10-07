import CryptoKit
import JournalCore
import SQLite3
import XCTest

@testable import Journal

/// A library folder with a configuration and a device key in the (in-memory) test keychain, made the way the app makes
/// one, for the states in which the journals can't be opened (docs/design/build-18-fixes-2026-10-06.md §2.1).
struct LibraryFixture {
    let directory: URL
    let folder: String
    let key: Data
    let account: String
    let phrase: String
    let entryID: UUID
    var configuration: LocalConfiguration

    var libraryURL: URL { directory.appendingPathComponent(folder) }
    var databaseURL: URL { libraryURL.appendingPathComponent("journal.sqlite") }
    var configurationURL: URL { directory.appendingPathComponent("configuration.json") }

    /// A library with one journal and one entry. The temporary folder and the key are removed after the test.
    @MainActor static func make(
        _ test: XCTestCase, appLock: Bool = false, folder: String = "vault"
    ) async throws -> LibraryFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Problem-" + UUID().uuidString)
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let account = "problem-key-" + UUID().uuidString
        let store = try JournalStore(directory: directory.appendingPathComponent(folder), key: key)
        let journal = JournalItem(kind: "journal", title: "Personal")
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Still here")
        try await store.save(journal)
        try await store.save(entry)
        try await store.close()
        try Keychain.write(key, account: account)
        var configuration = LocalConfiguration(
            recovery: try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0,
            recoveryConfirmed: true, storageFolder: folder, keyID: account, appLock: appLock ? true : nil)
        configuration.lastJournalID = journal.id
        let fixture = LibraryFixture(
            directory: directory, folder: folder, key: key, account: account, phrase: phrase, entryID: entry.id,
            configuration: configuration)
        try fixture.saveConfiguration()
        test.addTeardownBlock {
            try? Keychain.remove(account)
            try? FileManager.default.removeItem(at: directory)
        }
        return fixture
    }

    func saveConfiguration() throws {
        try JournalCoding.encoder().encode(configuration).write(to: configurationURL)
    }

    /// A model for this folder, closed with the test.
    @MainActor func model(_ test: XCTestCase) -> AppModel {
        let model = AppModel(directory: directory)
        // Erasing removes preference keys; never from the app's own preferences.
        model.preferences = UserDefaults(suiteName: "LibraryFixture-" + UUID().uuidString) ?? .standard
        test.addTeardownBlock { @MainActor in
            try? await model.store?.close()
            for account in [model.configuration?.keyID, model.configuration?.connectionKeyID].compactMap({ $0 }) {
                try? Keychain.remove(account)
            }
        }
        return model
    }

    /// A digest of every file under the folder, to show that nothing was changed, created or removed.
    func digest() throws -> String {
        let manager = FileManager.default
        var parts: [String] = []
        let paths = manager.enumerator(atPath: directory.path)?.allObjects as? [String] ?? []
        // The shared-memory index is rebuilt each time a database is opened; it holds no data.
        for path in paths.sorted() where !path.hasSuffix("-shm") {
            let url = directory.appendingPathComponent(path)
            var isDirectory: ObjCBool = false
            manager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                parts.append(path + "/")
            } else {
                let hash = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
                parts.append(path + " " + hash)
            }
        }
        return parts.joined(separator: "\n")
    }

    /// Overwrites the page where the records start, as a failing disk would: the library still opens, and the first
    /// read finds it malformed.
    func damageRecords() throws {
        let database = try SQLiteFile(databaseURL)
        let page = try database.integer("PRAGMA page_size")
        let root = try database.integer("SELECT rootpage FROM sqlite_master WHERE name='records'")
        database.close()
        var bytes = try Data(contentsOf: databaseURL)
        bytes.replaceSubrange(((root - 1) * page)..<(root * page), with: Data(repeating: 0x5A, count: page))
        try bytes.write(to: databaseURL)
    }

    /// Records a change from a version this one doesn't know, as a downgrade leaves.
    func markAsSavedByNewerVersion() throws {
        let database = try SQLiteFile(databaseURL)
        defer { database.close() }
        try database.run("INSERT INTO grdb_migrations(identifier) VALUES ('from-a-newer-version')")
    }
}

/// The few SQLite calls these fixtures need, without the package's database layer.
final class SQLiteFile {
    private var handle: OpaquePointer?

    struct Failure: Error { let code: Int32 }

    init(_ url: URL) throws {
        let status = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil)
        guard status == SQLITE_OK else { throw Failure(code: status) }
    }

    func close() {
        sqlite3_close(handle)
        handle = nil
    }

    func run(_ sql: String) throws {
        let status = sqlite3_exec(handle, sql, nil, nil, nil)
        guard status == SQLITE_OK else { throw Failure(code: status) }
    }

    func integer(_ sql: String) throws -> Int {
        var statement: OpaquePointer?
        var status = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard status == SQLITE_OK else { throw Failure(code: status) }
        defer { sqlite3_finalize(statement) }
        status = sqlite3_step(statement)
        guard status == SQLITE_ROW else { throw Failure(code: status) }
        return Int(sqlite3_column_int64(statement, 0))
    }
}
