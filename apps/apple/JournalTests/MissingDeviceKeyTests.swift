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
        XCTAssertNil(model.store)
        await model.unlockForTesting()
        XCTAssertTrue(model.locked, "Face ID or a passcode cannot replace a missing encryption key.")
        XCTAssertEqual(model.error, "Your device key is unavailable. Use your recovery key to unlock your journals.")
        XCTAssertNil(model.draft)
        await model.unlockWithRecovery(phrase)
        XCTAssertFalse(model.locked)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.configuration?.appLock, true, "Recovering the key keeps App Lock on.")
        let restored = try await model.store?.item(entry.id)
        XCTAssertEqual(restored, expected)
    }
    func testStoreOpenFailureCannotBeDismissedByUnlocking() async throws {
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
        let loadError = try XCTUnwrap(model.error)
        XCTAssertTrue(model.locked, "An existing vault that cannot open must not look like an empty journal.")
        XCTAssertNil(model.store)
        await model.unlockForTesting()
        XCTAssertTrue(model.locked)
        XCTAssertEqual(model.error, loadError)
        XCTAssertNil(model.draft)
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
