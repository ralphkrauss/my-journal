import JournalCore
import XCTest

@testable import Journal

@MainActor
final class MissingDeviceKeyTests: XCTestCase {
    func testDeviceAuthenticationCannotOpenUnavailableVaultAndRecoveryRestoresEntry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MissingKey-" + UUID().uuidString)
        let account = "missing-device-key-" + UUID().uuidString
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let store = try JournalStore(directory: directory, key: key)
        let journal = JournalItem(kind: "journal", title: "Personal")
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Preserve this reflection")
        try await store.save(journal)
        try await store.save(entry)
        let expected = try await store.item(entry.id)
        try await store.close()
        let configuration = LocalConfiguration(
            recovery: try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0,
            recoveryConfirmed: true, keyID: account, appLock: true, lastJournalID: journal.id, lastEntryID: entry.id)
        try JournalCoding.encoder().encode(configuration).write(
            to: directory.appendingPathComponent("configuration.json"))
        let model = AppModel(directory: directory)
        addTeardownBlock { @MainActor in
            try await model.store?.close()
            try? Keychain.remove(account)
            try? FileManager.default.removeItem(at: directory)
        }
        await model.load()
        XCTAssertTrue(model.locked)
        XCTAssertEqual(model.libraryProblem, .needsKey)
        XCTAssertFalse(model.showsLibraryProblem, "The missing key keeps the lock screen, with its credential field.")
        XCTAssertNil(model.store)
        await model.unlockForTesting()
        XCTAssertTrue(model.locked, "Face ID or a passcode cannot replace a missing encryption key.")
        XCTAssertEqual(model.error, "Your device key is unavailable. Use your recovery key to unlock your journals.")
        XCTAssertNil(model.draft)
        await model.unlockWithRecovery(phrase)
        XCTAssertFalse(model.locked)
        XCTAssertNil(model.libraryProblem, "Unlocking with the credential still works, and saves the configuration.")
        XCTAssertNil(model.error)
        XCTAssertEqual(model.configuration?.appLock, true, "Recovering the key keeps App Lock on.")
        let restored = try await model.store?.item(entry.id)
        XCTAssertEqual(restored, expected)
    }
    /// A library that can't be opened is no longer a lock screen with a button that leads nowhere: it is a problem the
    /// person can act on, and nothing is locked.
    func testStoreOpenFailureIsAProblemNotALockScreen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "UnavailableStore-" + UUID().uuidString)
        let account = "unavailable-store-" + UUID().uuidString
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("A file cannot be a vault directory".utf8).write(to: directory.appendingPathComponent("vault"))
        let key = try VaultCrypto.generateKey()
        try Keychain.write(key, account: account)
        let configuration = LocalConfiguration(
            recovery: try VaultCrypto.makeRecovery(masterKey: key, phrase: VaultCrypto.recoveryPhrase()).0,
            recoveryConfirmed: true, storageFolder: "vault", keyID: account, appLock: true)
        try JournalCoding.encoder().encode(configuration).write(
            to: directory.appendingPathComponent("configuration.json"))
        defer {
            try? Keychain.remove(account)
            try? FileManager.default.removeItem(at: directory)
        }
        let model = AppModel(directory: directory)
        await model.load()
        XCTAssertEqual(model.libraryProblem, .cantOpen)
        XCTAssertFalse(model.locked, "A library that can't be opened has nothing to unlock.")
        XCTAssertNil(model.store)
        XCTAssertNil(model.error, "The raw error never reaches the screen.")
        await model.unlockForTesting()
        XCTAssertEqual(model.libraryProblem, .cantOpen)
        XCTAssertNil(model.draft)
    }
    /// With the key gone and the credential forgotten, the lock screen offers the two ways on: an archive, or erasing
    /// and connecting to a server again.
    func testTheMissingKeyScreenOffersImportAndEraseAndBothWork() async throws {
        let fixture = try await LibraryFixture.make(self, appLock: true)
        try Keychain.remove(fixture.account)
        let source = AppModel(
            directory: fixture.directory.deletingLastPathComponent().appendingPathComponent(
                "Source-" + UUID().uuidString))
        addTeardownBlock { @MainActor in
            try? await source.store?.close()
            try? FileManager.default.removeItem(at: source.directory)
            if let account = source.configuration?.keyID { try? Keychain.remove(account) }
        }
        await source.start(encrypted: false)
        await source.newEntry()
        let entry = try XCTUnwrap(source.draft)
        let archive = try await source.prepareArchive()
        let model = fixture.model(self)
        let owner = TestDeviceOwner()
        model.deviceOwner = owner
        model.applicationActive = true
        await model.load()
        XCTAssertEqual(model.libraryProblem, .needsKey)
        XCTAssertTrue(model.locked)
        XCTAssertTrue(model.canImportArchive, "The lock screen of a missing key offers Import Archive….")

        let restored = try await model.inspectArchive(archive, phrase: "")
        try await model.installArchive(restored)
        await model.discardImportedCopy(restored)
        await model.supersededRemoval?.value
        XCTAssertEqual(owner.requests, 1, "With App Lock on, replacing the journals asks for the device owner.")
        XCTAssertNil(model.libraryProblem)
        XCTAssertFalse(model.locked)
        XCTAssertEqual(model.configuration?.appLock, true, "Restoring never turns App Lock off.")
        XCTAssertNotNil(model.items.first { $0.id == entry.id })

        // And erasing, from the same lock screen, on a library that lost its key.
        let second = try await LibraryFixture.make(self)
        try Keychain.remove(second.account)
        let other = second.model(self)
        await other.load()
        XCTAssertEqual(other.libraryProblem, .needsKey)
        let found = await other.unopenedEraseWarning()
        XCTAssertNotNil(found)
        let outcome = await other.eraseUnopenedLibrary()
        XCTAssertEqual(outcome, .erased)
        XCTAssertFalse(other.locked)
        XCTAssertNil(other.libraryProblem)
        XCTAssertNil(other.configuration)
    }
    /// Recovering a missing device key opens the library ready to sync with its saved server, as a normal launch does.
    func testRecoveryResumesTheSavedServerConnection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MissingKey-" + UUID().uuidString)
        let account = "missing-device-key-" + UUID().uuidString
        let credential = account + "-connection"
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let store = try JournalStore(directory: directory, key: key)
        try await store.save(JournalItem(kind: "journal", title: "Personal"))
        try await store.close()
        let saved = SyncConnection(address: "http://127.0.0.1:9", deviceID: UUID(), token: "synthetic-token")
        try Keychain.write(JournalCoding.encoder().encode(saved), account: credential)
        let configuration = LocalConfiguration(
            recovery: try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0,
            recoveryConfirmed: true, keyID: account, connectionKeyID: credential)
        try JournalCoding.encoder().encode(configuration).write(
            to: directory.appendingPathComponent("configuration.json"))
        let model = AppModel(directory: directory)
        addTeardownBlock { @MainActor in
            try await model.store?.close()
            try? Keychain.remove(account)
            try? Keychain.remove(credential)
            try? FileManager.default.removeItem(at: directory)
        }
        await model.load()
        XCTAssertTrue(model.locked)
        await model.unlockWithRecovery(phrase)
        XCTAssertFalse(model.locked)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.connection?.deviceID, saved.deviceID)
        XCTAssertNotNil(model.syncEngine, "Changes made after recovery must sync without relaunching.")
    }
}
