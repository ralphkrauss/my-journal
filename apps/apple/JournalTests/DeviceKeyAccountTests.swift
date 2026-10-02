import JournalCore
import XCTest

@testable import Journal

/// The vault key must stay reachable when the library's folder moves, as an iOS app's container can after an
/// update. Otherwise a library that is still on the device can only be opened with its password or recovery key.
@MainActor
final class DeviceKeyAccountTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KeyAccount-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func move(_ model: AppModel, to destination: URL) async throws -> AppModel {
        try await model.store?.close()
        try FileManager.default.moveItem(at: model.directory, to: destination)
        let moved = AppModel(directory: destination)
        await moved.load()
        return moved
    }

    func testLibraryFromBeforeKeyNamesWereSavedStillOpensAfterMoving() async throws {
        let original = temporaryDirectory()
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: original.appendingPathComponent("vault"), key: key)
        let entry = JournalItem(kind: "entry", title: "Still here")
        try await store.save(entry)
        try await store.close()
        // Such libraries found their key through an account named after the library's path.
        let legacyAccount = AppModel(directory: original).keyAccount
        try Keychain.write(key, account: legacyAccount)
        addTeardownBlock { try? Keychain.remove(legacyAccount) }
        let configuration = LocalConfiguration(
            recovery: try VaultCrypto.makeRecovery(masterKey: key, phrase: VaultCrypto.recoveryPhrase()).0,
            recoveryConfirmed: true, storageFolder: "vault")
        try JournalCoding.encoder().encode(configuration).write(
            to: original.appendingPathComponent("configuration.json"))

        let opened = AppModel(directory: original)
        await opened.load()
        XCTAssertFalse(opened.locked)
        XCTAssertEqual(opened.configuration?.keyID, legacyAccount)

        let moved = try await move(opened, to: temporaryDirectory())
        addTeardownBlock { @MainActor in try? await moved.store?.close() }
        XCTAssertNil(moved.error)
        XCTAssertFalse(moved.locked)
        XCTAssertEqual(moved.items.first { $0.id == entry.id }?.title, "Still here")
    }

    func testNewLibraryKeyDoesNotDependOnItsFolder() async throws {
        let created = AppModel(directory: temporaryDirectory())
        await created.start(password: "a long enough master password")
        let account = try XCTUnwrap(created.configuration?.keyID)
        addTeardownBlock { try? Keychain.remove(account) }
        XCTAssertNotEqual(account, created.keyAccount)

        let moved = try await move(created, to: temporaryDirectory())
        addTeardownBlock { @MainActor in try? await moved.store?.close() }
        XCTAssertNil(moved.error)
        XCTAssertFalse(moved.locked)
        XCTAssertNotNil(moved.store)
    }
}
