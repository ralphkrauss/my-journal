import JournalCore
import XCTest
import os

@testable import Journal

/// Connecting to a server or importing an archive switches to a new copy of the library. The copy it replaced still
/// holds everything, including entries later deleted permanently, and its key, so it's removed once the new copy
/// works. Nothing the app still uses may be removed, and a removal cut short is finished at the next launch.
@MainActor
final class SupersededLibraryTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Superseded-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func closing(_ model: AppModel) {
        addTeardownBlock { @MainActor in
            await model.supersededRemoval?.value
            try? await model.store?.close()
            for account in [model.configuration?.keyID, model.configuration?.connectionKeyID].compactMap({ $0 }) {
                try? Keychain.remove(account)
            }
        }
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func testImportingAnArchiveRemovesTheCopyItReplacedOnceTheNewOneOpens() async throws {
        let root = temporaryDirectory()
        let source = AppModel(directory: root.appendingPathComponent("source"))
        closing(source)
        await source.start(password: "the archive's master password")
        let archive = try await source.prepareArchive()
        let model = AppModel(directory: root.appendingPathComponent("library"))
        closing(model)
        await model.start(password: "this library's master password")
        await model.newEntry()
        let entry = try XCTUnwrap(model.draft)
        let previous = try XCTUnwrap(model.configuration)
        let previousFolder = model.directory.appendingPathComponent(try XCTUnwrap(previous.storageFolder))
        let previousKey = try XCTUnwrap(previous.keyID)

        let restored = try await model.inspectArchive(archive, phrase: "the archive's master password")
        try await model.installArchive(restored)
        await model.discardImportedCopy(restored)
        await model.supersededRemoval?.value

        XCTAssertFalse(exists(previousFolder))
        XCTAssertNil(try Keychain.read(previousKey))
        XCTAssertNil(model.configuration?.supersededLibraries)
        let current = model.directory.appendingPathComponent(try XCTUnwrap(model.configuration?.storageFolder))
        XCTAssertTrue(exists(current))
        XCTAssertNotNil(try Keychain.read(XCTUnwrap(model.configuration?.keyID)))
        XCTAssertNotNil(model.items.first { $0.id == entry.id }, "The new copy holds this library's journals.")
    }

    /// A removal interrupted by quitting is finished after the next launch, but for a connected library only after
    /// it has synchronized, so its content is on the server. What the configuration uses, and folders the app
    /// didn't create for a library, are never removed.
    func testAnInterruptedRemovalIsFinishedAfterRelaunchingAndSyncingButKeepsWhatIsInUse() async throws {
        let directory = temporaryDirectory()
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: directory.appendingPathComponent("vault-current"), key: key)
        try await store.close()
        let old = try JournalStore(directory: directory.appendingPathComponent("vault-old"), key: key)
        try await old.save(JournalItem(kind: "entry", title: "Only in the old copy"))
        try await old.close()
        let unrelated = directory.appendingPathComponent("local-server-data")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        let accounts = (0..<4).map { "superseded-test-\($0)-" + UUID().uuidString }
        let (currentKey, currentConnection, oldKey, oldConnection) = (
            accounts[0], accounts[1], accounts[2], accounts[3]
        )
        addTeardownBlock { for account in accounts { try? Keychain.remove(account) } }
        for account in [currentKey, oldKey] { try Keychain.write(key, account: account) }
        let answering = OSAllocatedUnfairLock(initialState: false)
        let server = try await FakeJournalServer { request in
            guard answering.withLock({ $0 }) else { return (503, Data("{}".utf8)) }
            switch request.path {
            case "/v1/status": return (200, Data(#"{"protocolVersion":1,"initialized":true}"#.utf8))
            case let path where path.hasPrefix("/v1/sync/"):
                return (200, Data(#"{"changes":[],"cursor":0,"hasMore":false}"#.utf8))
            default: return (404, Data("{}".utf8))
            }
        }
        let connection = SyncConnection(address: server.address, deviceID: UUID(), token: "token")
        for account in [currentConnection, oldConnection] {
            try Keychain.write(JournalCoding.encoder().encode(connection), account: account)
        }
        let configuration = LocalConfiguration(
            recovery: try VaultCrypto.makeRecovery(masterKey: key, phrase: VaultCrypto.recoveryPhrase()).0,
            recoveryConfirmed: true, storageFolder: "vault-current", keyID: currentKey,
            connectionKeyID: currentConnection,
            supersededLibraries: [
                SupersededLibrary(storageFolder: "vault-old", keyID: oldKey, connectionKeyID: oldConnection),
                // A damaged list must still never remove what's in use or what isn't a library copy.
                SupersededLibrary(
                    storageFolder: "vault-current", keyID: currentKey, connectionKeyID: currentConnection),
                SupersededLibrary(storageFolder: "local-server-data"),
            ])
        try JournalCoding.encoder().encode(configuration).write(
            to: directory.appendingPathComponent("configuration.json"))

        let model = AppModel(directory: directory)
        closing(model)
        await model.load()
        XCTAssertNil(model.error)
        let synced = await model.sync()
        XCTAssertFalse(synced)
        await model.supersededRemoval?.value
        XCTAssertTrue(exists(directory.appendingPathComponent("vault-old")), "Kept until the library has synchronized.")
        XCTAssertNotNil(try Keychain.read(oldKey))

        answering.withLock { $0 = true }
        let retried = await model.sync()
        XCTAssertTrue(retried)
        await model.supersededRemoval?.value
        XCTAssertFalse(exists(directory.appendingPathComponent("vault-old")))
        XCTAssertNil(try Keychain.read(oldKey))
        XCTAssertNil(try Keychain.read(oldConnection))
        XCTAssertNil(model.configuration?.supersededLibraries)
        XCTAssertTrue(exists(directory.appendingPathComponent("vault-current")))
        XCTAssertTrue(exists(unrelated))
        XCTAssertNotNil(try Keychain.read(currentKey))
        XCTAssertNotNil(try Keychain.read(currentConnection))
        let saved = try JournalCoding.decoder().decode(
            LocalConfiguration.self, from: Data(contentsOf: directory.appendingPathComponent("configuration.json")))
        XCTAssertNil(saved.supersededLibraries)
    }

    /// Importing over journals that can't be opened leaves them to remove like any library a switch leaves, with the
    /// ones earlier switches left, keeps App Lock on, and gives the restored library its own connection item. The
    /// device owner is asked once, and a cancelled prompt replaces nothing.
    func testImportingOverJournalsThatCantBeOpenedSupersedesThemAndKeepsAppLock() async throws {
        let root = temporaryDirectory()
        let source = AppModel(directory: root.appendingPathComponent("source"))
        closing(source)
        await source.start(password: "the archive's master password")
        await source.newEntry()
        let entry = try XCTUnwrap(source.draft)
        let archive = try await source.prepareArchive()

        var fixture = try await LibraryFixture.make(self, appLock: true, folder: "vault-old")
        let earlierKey = "superseded-earlier-" + UUID().uuidString
        try Keychain.write(Data("earlier".utf8), account: earlierKey)
        let earlierFolder = fixture.directory.appendingPathComponent("vault-earlier")
        try FileManager.default.createDirectory(at: earlierFolder, withIntermediateDirectories: true)
        fixture.configuration.inactivityLockMinutes = 10
        fixture.configuration.supersededLibraries = [
            SupersededLibrary(storageFolder: "vault-earlier", keyID: earlierKey)
        ]
        try fixture.saveConfiguration()
        try fixture.damageRecords()
        let model = fixture.model(self)
        closing(model)
        let owner = TestDeviceOwner()
        model.deviceOwner = owner
        model.applicationActive = true
        await model.load()
        await model.unlockWithDevice()
        XCTAssertEqual(model.libraryProblem, .cantOpen)
        let restored = try await model.inspectArchive(archive, phrase: "the archive's master password")

        owner.outcome = .cancelled
        let before = try fixture.digest()
        do {
            try await model.installArchive(restored)
            XCTFail("A cancelled prompt replaced the journals")
        } catch is CancellationError {}
        XCTAssertEqual(try fixture.digest(), before, "Nothing was replaced.")
        XCTAssertEqual(model.libraryProblem, .cantOpen)

        owner.outcome = .success
        try await model.installArchive(restored)
        await model.discardImportedCopy(restored)
        let installed = try XCTUnwrap(model.configuration)
        XCTAssertNil(model.libraryProblem)
        XCTAssertEqual(installed.appLock, true)
        XCTAssertEqual(installed.inactivityLockMinutes, 10)
        XCTAssertEqual(installed.connectionKeyID, installed.keyID.map { $0 + "-connection" })
        XCTAssertNotEqual(installed.connectionKeyID, fixture.account + "-connection")
        await model.supersededRemoval?.value
        XCTAssertFalse(
            exists(fixture.libraryURL), "The library that couldn't be opened is removed once the new one opens.")
        XCTAssertFalse(exists(earlierFolder), "So is the one an earlier switch left.")
        XCTAssertNil(try Keychain.read(fixture.account))
        XCTAssertNil(try Keychain.read(earlierKey))
        XCTAssertNil(model.configuration?.supersededLibraries)
        XCTAssertNotNil(model.items.first { $0.id == entry.id })
    }
}
