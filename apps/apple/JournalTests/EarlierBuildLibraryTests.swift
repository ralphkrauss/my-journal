import CryptoKit
import JournalCore
import XCTest

@testable import Journal

/// Libraries written by the real code of TestFlight builds 16 and 19 (JournalTests/Fixtures/README.md). Version 1.1
/// must open every one with everything intact, ask the unencrypted ones to encrypt without losing or leaving anything
/// readable, and let a master password library change its password and travel through an archive.
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

    private static let names = ["password", "unencrypted", "unencrypted-synced"].flatMap { variant in
        [16, 19].map { "build\($0)-\(variant)" }
    }

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
            for account in [model.configuration?.keyID, model.configuration?.encryptionUpgrade?.keyID] {
                if let account { try? Keychain.remove(account) }
            }
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
        XCTAssertEqual(model.conflicts.count, manifest.conflictCount, file: file, line: line)
        XCTAssertEqual(
            model.conflicts.first?.id.uuidString.lowercased(), manifest.conflictedEntryID, file: file, line: line)
        let history = try XCTUnwrap(manifest.records.first { $0.historyRows > 0 }, file: file, line: line)
        let versions = try await store.history(for: try XCTUnwrap(UUID(uuidString: history.id)))
        XCTAssertGreaterThan(versions.count, 1, "Version History is kept.", file: file, line: line)
    }

    func testEveryLibraryAnEarlierBuildWroteOpensWithEverythingIntact() async throws {
        for name in Self.names {
            let (directory, fixture) = try install(name)
            let model = await open(directory)
            XCTAssertNil(model.libraryProblem, name)
            XCTAssertNil(model.error, name)
            XCTAssertEqual(model.configuration?.recovery.formatVersion, fixture.manifest.recoveryFormatVersion, name)
            try await assertHolds(fixture, in: model)
            if fixture.variant == "unencrypted-synced" {
                XCTAssertNotNil(model.connection, "\(name) keeps its server connection.")
                let position = try await XCTUnwrap(model.store).syncedPosition()
                XCTAssertEqual(position.cursor, fixture.manifest.syncedPositionCursor, "\(name) keeps its position.")
            }
            try await model.store?.close()
        }
    }

    /// An unencrypted library of either build goes through Encrypt Your Journals: everything equals the manifest,
    /// and nothing readable is left in the data folder, however it is searched.
    func testEveryUnencryptedLibraryIsEncryptedWithEverythingIntactAndNothingReadableLeft() async throws {
        for name in Self.names where name.contains("unencrypted") {
            let (directory, fixture) = try install(name)
            // The synced library's server is gone; a stand-in takes its place at the saved address.
            var server: EncryptionServer?
            if let item = fixture.connectionItem {
                let stand = try await EncryptionServer.start()
                addTeardownBlock { stand.release() }
                server = stand
                let address = stand.address.replacingOccurrences(of: "/", with: "\\/")
                let moved = item.replacingOccurrences(of: "http:\\/\\/127.0.0.1:9", with: address)
                XCTAssertNotEqual(moved, item)
                try Keychain.write(Data(moved.utf8), account: fixture.connectionKeyID)
            }
            let model = await open(directory)
            XCTAssertEqual(model.windowRouting.screen, .encryptForm, "\(name) is asked to encrypt.")
            let readable = try Self.readableFiles(in: directory, containing: fixture.manifest.markerNeedles)
            XCTAssertFalse(readable.isEmpty, "\(name) starts readable, so the search below can find something.")
            try await model.turnOnEncryption(password: "a new master password", current: nil) { _ in }
            await model.supersededRemoval?.value
            try await model.refresh()
            XCTAssertEqual(model.configuration?.recovery.formatVersion, 2, name)
            if let server {
                XCTAssertEqual(server.count("POST", "/v1/recovery/encrypt"), 1, "\(name) switched its server once.")
            }
            try await assertHolds(fixture, in: model)
            if server != nil {
                // A connected library keeps the plaintext copy until the encrypted one has synchronized.
                let ok = await model.sync()
                XCTAssertTrue(ok, "\(name) synced after encrypting: \(String(describing: model.syncError))")
            }
            await model.supersededRemoval?.value
            XCTAssertEqual(
                try Self.readableFiles(in: directory, containing: fixture.manifest.markerNeedles), [],
                "\(name) leaves nothing readable.")
            XCTAssertEqual(model.windowRouting.screen, .journals)
            try await model.store?.close()
        }
    }

    /// A master password library changes its password, and an archive made afterwards restores everything.
    func testAMasterPasswordLibraryChangesItsPasswordAndTravelsThroughAnArchive() async throws {
        for name in Self.names where name.hasSuffix("password") {
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

    /// Mixed versions: another device (1.0 or 1.1) encrypted the server, which purged it and revoked this device, a
    /// device whose state build 19 wrote. It is asked to sign in, never switches the server itself, signs in with the
    /// master password and loses nothing.
    func testADeviceBuild19WroteRejoinsAServerAnotherDeviceEncryptedWithTheMasterPassword() async throws {
        let (directory, fixture) = try install("build19-unencrypted-synced")
        let password = "the other device's master password"
        let (envelope, _) = try VaultCrypto.makeRecovery(
            masterKey: VaultCrypto.generateKey(), phrase: password, formatVersion: 2)
        let published = RecoveryParameters(envelope)
        let item = try XCTUnwrap(fixture.connectionItem)
        let oldToken = try XCTUnwrap(
            (try JSONSerialization.jsonObject(with: Data(item.utf8)) as? [String: Any])?["token"] as? String)
        let server = try await EncryptionServer.start {
            $0.parameters = published
            $0.revokedTokens = [oldToken]
            $0.grantsRecovery = true
        }
        addTeardownBlock { server.release() }
        let address = server.address.replacingOccurrences(of: "/", with: "\\/")
        try Keychain.write(
            Data(item.replacingOccurrences(of: "http:\\/\\/127.0.0.1:9", with: address).utf8),
            account: fixture.connectionKeyID)
        let model = await open(directory)
        model.encryption.notNow()

        // The check finds a server that already uses encryption: sign in, no purge.
        model.encryption.formAppeared()
        await model.encryption.finishedChecking()
        XCTAssertEqual(model.encryption.variant, .signIn)
        XCTAssertEqual(server.count("POST", "/v1/recovery/encrypt"), 0)

        try await model.recoverServer(address: server.address, phrase: password, uploadLocal: true, shown: published)
        XCTAssertEqual(
            model.configuration?.recovery.formatVersion, 2, "Its own journals are encrypted with the server's key.")
        XCTAssertEqual(model.configuration?.encrypted, true)
        XCTAssertEqual(server.count("POST", "/v1/recovery/encrypt"), 0)
        try await model.refresh()
        try await assertHolds(fixture, in: model)
        try await model.store?.close()
    }

    /// The paths of files under `directory` that hold any of `needles` as bytes.
    private static func readableFiles(in directory: URL, containing needles: [String]) throws -> [String] {
        let manager = FileManager.default
        let paths = manager.enumerator(atPath: directory.path)?.allObjects as? [String] ?? []
        var found: [String] = []
        for path in paths {
            let url = directory.appendingPathComponent(path)
            var isDirectory: ObjCBool = false
            manager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            guard !isDirectory.boolValue, let data = try? Data(contentsOf: url) else { continue }
            if needles.contains(where: { data.range(of: Data($0.utf8)) != nil }) { found.append(path) }
        }
        return found
    }
}
