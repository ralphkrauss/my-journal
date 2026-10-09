import Foundation
import JournalCore
import SQLite3

/// Libraries for the spec screenshots that need a state the sample library doesn't have: changes to review, and
/// journals that can't be opened. Each works on a copy of the sample library, with the store's own calls or the same
/// damage JournalTests uses (`LibraryFixture`), and is shared by the iPhone and iPad captures and the Mac captures.
enum SpecLibraryFixtures {
    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    enum Problem {
        case settingsUnread
        case cantOpen
        case newerVersion
    }

    private struct Seeded: Decodable {
        var recovery: RecoveryEnvelope
        var storageFolder: String
    }

    /// The other device's id, fixed so the screens are the same each time.
    private static let otherDevice = UUID(uuidString: "00000000-0000-0000-0000-0000000000a2") ?? UUID()

    // MARK: - An earlier version's library

    private struct EarlierConfiguration: Codable {
        let recovery: RecoveryEnvelope
        var recoveryConfirmed = true
        let lastJournalID: UUID
        let lastEntryID: UUID
    }

    /// A library as version 1.0 made it with Continue Without Encryption, in `library`: no password, one journal and
    /// one entry. Version 1.1 asks it to encrypt before it opens (Encrypt Your Journals).
    static func unencryptedLibrary(in library: URL) async throws {
        let store = try JournalStore(directory: library, key: VaultCrypto.generateKey(), protection: .plaintext)
        let journal = JournalItem(kind: "journal", title: "Personal")
        let entry = JournalItem(
            kind: "entry", journalID: journal.id, title: "Slow Sunday",
            document: .plain("Woke up early and walked to the river before breakfast."),
            date: Date(timeIntervalSince1970: 1_700_000_000))
        try await store.save(journal)
        try await store.save(entry)
        try await store.close()
        let configuration = EarlierConfiguration(
            recovery: .unprotected, lastJournalID: journal.id, lastEntryID: entry.id)
        try JournalCoding.encoder().encode(configuration).write(
            to: library.appendingPathComponent("configuration.json"))
    }

    // MARK: - Problems

    /// Damages a library that has been opened once (so the device has its key) as the checks in JournalTests do.
    static func damage(_ problem: Problem, in library: URL) throws {
        switch problem {
        case .settingsUnread:
            try Data("not a configuration".utf8).write(to: library.appendingPathComponent("configuration.json"))
        case .cantOpen:
            for folder in try storageFolders(in: library) {
                try FileManager.default.removeItem(at: folder.appendingPathComponent("journal.sqlite"))
            }
        case .newerVersion:
            for folder in try storageFolders(in: library) {
                try run("INSERT INTO grdb_migrations(identifier) VALUES ('from-a-newer-version')", on: folder)
            }
        }
    }

    private static func storageFolders(in library: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: library, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("vault-") }
    }

    private static func run(_ statement: String, on folder: URL) throws {
        var handle: OpaquePointer?
        let path = folder.appendingPathComponent("journal.sqlite").path
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            throw Failure("The sample library's database didn't open.")
        }
        defer { sqlite3_close(handle) }
        guard sqlite3_exec(handle, statement, nil, nil, nil) == SQLITE_OK else {
            throw Failure("The statement failed: \(statement)")
        }
    }

    // MARK: - Changes to review

    /// An edit of "Slow Sunday" made on the other device that this device hasn't seen, and a change to "Gratitude"
    /// in a format newer than this version reads.
    static func recordConflicts(in library: URL, password: String) async throws {
        let seeded = try JournalCoding.decoder().decode(
            Seeded.self, from: Data(contentsOf: library.appendingPathComponent("configuration.json")))
        let (key, _) = try VaultCrypto.recover(seeded.recovery, phrase: password)
        let store = try JournalStore(
            directory: library.appendingPathComponent(seeded.storageFolder), key: key,
            protection: seeded.recovery.contentProtection)
        let items = try await store.items()
        guard let sunday = items.first(where: { $0.kind == "entry" && $0.title == "Slow Sunday" }),
            let gratitude = items.first(where: { $0.kind == "entry" && $0.title == "Gratitude" })
        else { throw Failure("The sample library lacks its entries.") }
        let other = FileManager.default.temporaryDirectory.appendingPathComponent("spec-other-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: other) }
        let otherStore = try JournalStore(directory: other, key: key)
        var remote = sunday
        remote.storedVersion = nil
        remote.document = JournalDocument(
            markdown: "Woke up early and walked to the river before breakfast. The light was low and gold.\n\n"
                + "## Today\n\n- [x] Feed the sourdough starter\n- [ ] Call my sister\n")
        remote.modifiedAt = sunday.modifiedAt.addingTimeInterval(900)
        try await otherStore.save(remote)
        guard let payload = try await otherStore.pending().first(where: { $0.recordID == sunday.id })?.payload else {
            throw Failure("No change to record.")
        }
        try await store.recordConflict(
            RemoteChange(
                cursor: 1, recordId: sunday.id, revision: 1, kind: "entry", payload: payload, deviceId: otherDevice,
                modifiedAt: remote.modifiedAt))
        try await recordUnsupported(for: gratitude, key: key, in: store)
        try await otherStore.close()
        try await store.close()
    }

    private static func recordUnsupported(for entry: JournalItem, key: Data, in store: JournalStore) async throws {
        guard let saved = try await store.item(entry.id) else { throw Failure("The entry isn't in the library.") }
        var object = try JSONSerialization.jsonObject(with: PortableRecord.encode(saved)) as? [String: Any] ?? [:]
        object["title"] = "Gratitude from a newer version"
        object["futureLayout"] = ["columns": 2] as [String: Any]
        let bytes = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        let sealed = try VaultCrypto.seal(
            bytes, key: key, context: VaultCrypto.recordContext(id: saved.id, kind: saved.kind))
        try await store.recordConflict(
            RemoteChange(
                cursor: 2, recordId: saved.id, revision: 1, kind: saved.kind, payload: sealed.base64EncodedString(),
                deviceId: otherDevice, modifiedAt: saved.modifiedAt.addingTimeInterval(60)))
    }
}
