import CryptoKit
import JournalCore
import XCTest

@testable import Journal

/// Libraries written by the real code of TestFlight builds 16 and 19 (JournalTests/Fixtures/README.md). Version 1.1
/// opens every encrypted one with everything intact and lets it change its password and travel through an archive. It
/// opens none of the unencrypted ones: each ends in the screen that says the journals can't be opened, and its files
/// stay on disk byte for byte as the earlier build left them (docs/design/1-1-encryption-and-passwords.md, owner
/// decision of 2026-10-10).
@MainActor
final class EarlierBuildLibraryTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Record: Decodable {
            let id: String
            let kind: String
            let journalID: String?
            let title: String
            let deleted: Bool
            let pinned: Bool
            let historyRows: Int
        }
        struct Image: Decodable {
            let entryID: String
            let id: String
            let sha256: String
            let bytes: Int
        }
        struct Manifest: Decodable {
            let recoveryFormatVersion: Int
            let records: [Record]
            let liveJournalOrder: [String]
            let deletedJournalID: String
            let pinnedEntryIDs: [String]
            let images: [Image]
            let conflictCount: Int
            let conflictedEntryID: String
            let syncedPositionCursor: Int64
            let marker: String
            let markerEntryID: String
            let markerNeedles: [String]
        }
        let build: Int
        let variant: String
        let storageFolder: String
        let configuration: String
        let files: [String: String]
        let keyID: String
        let material: String
        let phrase: String?
        let connectionKeyID: String
        let connectionItem: String?
        let manifest: Manifest
    }

    private static func names(_ variants: [String]) -> [String] {
        variants.flatMap { variant in [16, 19].map { "build\($0)-\(variant)" } }
    }
    private static let encryptedNames = names(["password"])
    private static let unencryptedNames = names(["unencrypted", "unencrypted-synced"])

    /// Writes the fixture as its build left it: the folder, the exact configuration text, and the Keychain items (in
    /// the test keychain).
    private func install(_ name: String) throws -> (directory: URL, fixture: Fixture) {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: "json"), "No fixture named \(name)")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Earlier-" + UUID().uuidString)
        let library = directory.appendingPathComponent(fixture.storageFolder)
        for (path, encoded) in fixture.files {
            let file = library.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try XCTUnwrap(Data(base64Encoded: encoded)).write(to: file)
        }
        try Data(fixture.configuration.utf8).write(to: directory.appendingPathComponent("configuration.json"))
        try Keychain.write(try XCTUnwrap(Data(base64Encoded: fixture.material)), account: fixture.keyID)
        if let item = fixture.connectionItem {
            try Keychain.write(Data(item.utf8), account: fixture.connectionKeyID)
        }
        addTeardownBlock {
            try? Keychain.remove(fixture.keyID)
            try? Keychain.remove(fixture.connectionKeyID)
            try? FileManager.default.removeItem(at: directory)
        }
        return (directory, fixture)
    }

    private func open(_ directory: URL) async -> AppModel {
        let model = AppModel(directory: directory)
        model.preferences = UserDefaults(suiteName: "EarlierBuild-" + UUID().uuidString) ?? .standard
        await model.load()
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            if let account = model.configuration?.keyID { try? Keychain.remove(account) }
        }
        return model
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Everything the manifest lists is in the library: records with their titles and parents, deleted state, the
    /// custom order and pins, the images' exact bytes, the history and the review.
    private func assertHolds(_ fixture: Fixture, in model: AppModel, file: StaticString = #filePath, line: UInt = #line)
        async throws
    {
        let manifest = fixture.manifest
        let store = try XCTUnwrap(model.store, file: file, line: line)
        let items = try await store.items()
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id.uuidString.lowercased(), $0) })
        for record in manifest.records {
            let item = try XCTUnwrap(byID[record.id], "\(record.title) is missing", file: file, line: line)
            XCTAssertEqual(item.kind, record.kind, file: file, line: line)
            XCTAssertEqual(item.title, record.title, file: file, line: line)
            XCTAssertEqual(item.journalID?.uuidString.lowercased(), record.journalID, file: file, line: line)
            XCTAssertEqual(item.deletedAt != nil, record.deleted, record.title, file: file, line: line)
        }
        XCTAssertEqual(
            model.journals.map { $0.id.uuidString.lowercased() }, manifest.liveJournalOrder,
            "The journals keep the order the person chose.", file: file, line: line)
        XCTAssertEqual(
            Set(model.library.pinned.map { $0.uuidString.lowercased() }), Set(manifest.pinnedEntryIDs),
            file: file, line: line)
        for image in manifest.images {
            let bytes = try await store.attachment(try XCTUnwrap(UUID(uuidString: image.id)))
            XCTAssertEqual(bytes.count, image.bytes, file: file, line: line)
            XCTAssertEqual(
                sha256(bytes), image.sha256, "An image's bytes are exactly as they were.", file: file, line: line)
        }
        // The version the earlier build kept for review was settled when the library opened: the entry is as it was, and
        // the other version is an entry of its own, listed in Settings ▸ Sync.
        XCTAssertTrue(model.conflictedIDs.isEmpty, "Nothing is left waiting for the person", file: file, line: line)
        XCTAssertNotNil(byID[manifest.conflictedEntryID], file: file, line: line)
        let copies = items.filter { $0.title.hasSuffix(" (other version)") }
        XCTAssertEqual(copies.count, manifest.conflictCount, "The other version is kept", file: file, line: line)
        XCTAssertEqual(model.keptNoteRows.count, manifest.conflictCount, file: file, line: line)
        let history = try XCTUnwrap(manifest.records.first { $0.historyRows > 0 }, file: file, line: line)
        let versions = try await store.history(for: try XCTUnwrap(UUID(uuidString: history.id)))
        XCTAssertGreaterThan(versions.count, 1, "Version History is kept.", file: file, line: line)
    }

    func testEveryEncryptedLibraryAnEarlierBuildWroteOpensWithEverythingIntact() async throws {
        for name in Self.encryptedNames {
            let (directory, fixture) = try install(name)
            let model = await open(directory)
            XCTAssertNil(model.libraryProblem, name)
            XCTAssertNil(model.error, name)
            XCTAssertEqual(model.configuration?.recovery.formatVersion, fixture.manifest.recoveryFormatVersion, name)
            XCTAssertEqual(model.windowRouting.screen, .journals, name)
            try await assertHolds(fixture, in: model)
            try await model.store?.close()
        }
    }

    /// A digest of every file under `directory` (the shared-memory index, rebuilt each time a database is opened,
    /// holds no data), to show that nothing was changed, created or removed.
    private func digest(of directory: URL) throws -> String {
        let manager = FileManager.default
        var parts: [String] = []
        let paths = manager.enumerator(atPath: directory.path)?.allObjects as? [String] ?? []
        for path in paths.sorted() where !path.hasSuffix("-shm") {
            var isDirectory: ObjCBool = false
            let url = directory.appendingPathComponent(path)
            manager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            parts.append(isDirectory.boolValue ? path + "/" : path + " " + sha256(try Data(contentsOf: url)))
        }
        return parts.joined(separator: "\n")
    }

    /// A library of either build made without encryption can't be opened by this version: the screen says so, with no
    /// Try Again and no Import Archive, and Erase Journals and Settings… is the one way on. Its files, settings and
    /// Keychain items are byte for byte as the build left them, also after more launches and a Try Again that is
    /// refused, so version 1.0 can still read them.
    func testEveryUnencryptedLibraryIsTheCantBeOpenedProblemAndItsFilesStayByteForByte() async throws {
        for name in Self.unencryptedNames {
            let (directory, fixture) = try install(name)
            let before = try digest(of: directory)
            let key = try Keychain.read(fixture.keyID)
            let connection = try Keychain.read(fixture.connectionKeyID)
            XCTAssertEqual(fixture.manifest.recoveryFormatVersion, 4, name)

            let model = await open(directory)
            XCTAssertEqual(model.libraryProblem, .notEncrypted, name)
            XCTAssertEqual(model.windowRouting.screen, .libraryProblem, name)
            XCTAssertNil(model.store, name)
            XCTAssertNil(model.masterKey, name)
            XCTAssertNil(model.connection, "\(name) doesn't sync.")
            XCTAssertFalse(model.locked, name)
            XCTAssertNil(model.error, name)
            XCTAssertFalse(LibraryProblem.notEncrypted.offersTryAgain, name)
            XCTAssertFalse(LibraryProblem.notEncrypted.offersImport, name)
            XCTAssertTrue(LibraryProblem.notEncrypted.allowsErase, name)
            XCTAssertFalse(LibraryProblem.notEncrypted.erasesAfterFailedRetry, "Erase is offered at once.")
            XCTAssertFalse(model.canImportArchive, name)
            XCTAssertTrue(model.refusesImport, name)

            await model.retryOpening()
            XCTAssertEqual(
                model.libraryProblem, .notEncrypted, "There is no Try Again, and a refused one changes nothing.")
            do {
                try model.requireJournalsOpen()
                XCTFail("\(name) started or joined something over journals that can't be opened")
            } catch is LibraryNotOpenError {}
            await model.start()
            XCTAssertNil(model.store, "No new library replaces it.")

            let relaunched = await open(directory)
            XCTAssertEqual(relaunched.libraryProblem, .notEncrypted, name)
            XCTAssertEqual(try digest(of: directory), before, "\(name): every file is as the build left it.")
            XCTAssertEqual(try Keychain.read(fixture.keyID), key, name)
            XCTAssertEqual(try Keychain.read(fixture.connectionKeyID), connection, name)

            // Erase Journals and Settings… is the one way on: it removes the library, and the first-launch screen follows.
            let outcome = await relaunched.eraseUnopenedLibrary()
            XCTAssertEqual(outcome, .erased, name)
            XCTAssertNil(relaunched.libraryProblem, name)
            XCTAssertEqual(relaunched.windowRouting.screen, .welcome, name)
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: directory.appendingPathComponent(fixture.storageFolder).path),
                "\(name): the library is gone.")
            XCTAssertNil(try Keychain.read(fixture.keyID), name)
        }
    }

    /// A master password library changes its password, and an archive made afterwards restores everything.
    func testAMasterPasswordLibraryChangesItsPasswordAndTravelsThroughAnArchive() async throws {
        for name in Self.encryptedNames {
            let (directory, fixture) = try install(name)
            let model = await open(directory)
            let phrase = try XCTUnwrap(fixture.phrase)
            XCTAssertEqual(model.windowRouting.screen, .journals, "An encrypted library is not asked again.")
            let key = try XCTUnwrap(model.masterKey)
            let change = try await model.preparePasswordChange(current: phrase, new: "the new master password")
            try model.savePasswordChange(change.envelope)
            let archive = try await model.prepareArchive()
            let restored = try await VaultArchive.restore(
                from: archive, to: directory.appendingPathComponent("restored"), phrase: "the new master password")
            XCTAssertEqual(restored.key, key, name)
            let restoredItems = try await restored.store.items()
            let originalItems = try await XCTUnwrap(model.store).items()
            XCTAssertEqual(Set(restoredItems.map(\.id)), Set(originalItems.map(\.id)), name)
            try await restored.store.close()
            try await model.store?.close()
        }
    }
}
