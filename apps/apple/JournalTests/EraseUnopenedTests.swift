import JournalCore
import XCTest

@testable import Journal

/// Erase Journals and Settings works without reading anything (docs/design/build-18-fixes-2026-10-06.md §2.1): the
/// configuration moves as it is, and everything the app stored goes with it.
@MainActor
final class EraseUnopenedTests: XCTestCase {
    private func exists(_ fixture: LibraryFixture, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent(name).path)
    }

    private func write(_ account: String, _ test: XCTestCase) throws {
        try Keychain.write(Data("secret".utf8), account: account)
        test.addTeardownBlock { try? Keychain.remove(account) }
    }

    /// A library folder the configuration doesn't name, an import, a staged export and an unreadable configuration,
    /// beside the files of the server earlier Mac builds ran.
    private func strayFiles(_ fixture: LibraryFixture) throws -> (names: [String], former: [String]) {
        let manager = FileManager.default
        let export = "export-" + UUID().uuidString + ".journalbackup"
        let names = ["vault-stray", "import-" + UUID().uuidString.lowercased(), "markdown-" + UUID().uuidString]
        for name in names {
            try manager.createDirectory(
                at: fixture.directory.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try Data("archive".utf8).write(to: fixture.directory.appendingPathComponent(export))
        try Data("{}".utf8).write(to: fixture.directory.appendingPathComponent("local-server.json"))
        try manager.createDirectory(
            at: fixture.directory.appendingPathComponent("local-server-data"), withIntermediateDirectories: true)
        return (names + [export], ["local-server.json", "local-server-data"])
    }

    func testEraseRemovesEverythingTheAppStoredFromUnreadableSettingsAndKeepsTheFormerServer() async throws {
        let fixture = try await LibraryFixture.make(self)
        let (stray, former) = try strayFiles(fixture)
        try Data("{ not a configuration".utf8).write(to: fixture.configurationURL)
        let model = fixture.model(self)
        let ownPrefix = model.keyAccount
        let ours = ownPrefix + "-vault-stray"
        let ownConnection = ownPrefix + "-connection-" + UUID().uuidString
        let otherBuild = "master-" + String(repeating: "0", count: 64) + "-connection"
        let legacyAgent = "agent-" + UUID().uuidString
        let accounts = [ours, ownConnection, otherBuild, legacyAgent]
        for account in accounts { try write(account, self) }
        model.sweepsKeychain = true
        model.keychainListing = { accounts }
        await model.load()
        XCTAssertEqual(model.libraryProblem, .settingsUnread)

        let outcome = await model.eraseUnopenedLibrary()

        XCTAssertEqual(outcome, .erased)
        XCTAssertNil(model.libraryProblem)
        XCTAssertFalse(exists(fixture, "configuration.json"), "The unreadable file left with everything else.")
        for name in stray + [fixture.folder] { XCTAssertFalse(exists(fixture, name), name) }
        for name in former { XCTAssertTrue(exists(fixture, name), "The former server's files stay: \(name)") }
        XCTAssertNil(try Keychain.read(ours))
        XCTAssertNil(try Keychain.read(ownConnection))
        XCTAssertNil(try Keychain.read(legacyAgent))
        #if os(macOS)
            XCTAssertNotNil(
                try Keychain.read(otherBuild), "Another build's item in the team's shared group isn't this folder's.")
        #else
            XCTAssertNil(try Keychain.read(otherBuild), "On iPhone and iPad the orphans of earlier installs go too.")
        #endif
    }

    /// Under test, and outside the app's own data folder, only what the configuration names is removed, so erasing
    /// there can't remove the keys of a person's real library.
    func testWithoutTheSweepOnlyNamedAccountsAreRemoved() async throws {
        let fixture = try await LibraryFixture.make(self)
        let stray = fixture.account + "-stray-" + UUID().uuidString
        try write(stray, self)
        let model = fixture.model(self)
        model.sweepsKeychain = false
        model.keychainListing = {
            XCTFail("The Keychain is not listed.")
            return [stray]
        }
        try FileManager.default.removeItem(at: fixture.libraryURL)
        await model.load()
        XCTAssertEqual(model.libraryProblem, .cantOpen)

        let outcome = await model.eraseUnopenedLibrary()
        XCTAssertEqual(outcome, .erased)
        XCTAssertNil(try Keychain.read(fixture.account), "The library's own key is removed by name.")
        XCTAssertNotNil(try Keychain.read(stray))
    }

    /// A Keychain that can't be listed usually can't be removed from either; the files go anyway, with the names that
    /// can be derived, and nothing is reported as failed.
    func testAListingThatFailsStillCommitsTheErase() async throws {
        let fixture = try await LibraryFixture.make(self)
        let (stray, _) = try strayFiles(fixture)
        try Data("garbage".utf8).write(to: fixture.configurationURL)
        let model = fixture.model(self)
        let derived = model.keyAccount + "-connection"
        try write(derived, self)
        model.sweepsKeychain = true
        model.keychainListing = { throw SecretStoreError.unavailable }
        await model.load()

        let outcome = await model.eraseUnopenedLibrary()
        XCTAssertEqual(outcome, .erased, "No “Couldn’t Erase”.")
        for name in stray { XCTAssertFalse(exists(fixture, name), name) }
        XCTAssertFalse(exists(fixture, "configuration.json"))
        XCTAssertNil(try Keychain.read(derived), "The names that need no configuration are still removed.")
    }

    /// An erase left half finished, a new library started, then a launch: what protects the new library is what it
    /// uses, never everything in the folder, or the leftover would never be finished.
    func testAHalfFinishedEraseThenANewLibraryFinishesTheOldOneAndKeepsTheNew() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Half-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let first = AppModel(directory: directory)
        first.preferences = UserDefaults(suiteName: "Half-" + UUID().uuidString) ?? .standard
        first.sweepsKeychain = true
        first.keychainListing = { [] }
        await first.start()
        let old = try XCTUnwrap(first.configuration)
        let oldFolder = try XCTUnwrap(old.storageFolder)
        let oldKey = try XCTUnwrap(old.keyID)
        try await first.store?.close()
        // Committed, then stopped: the folder and the key are still there, and the list is saved.
        let list = first.erasureList(old)
        _ = try LocalErasure.commit(list, in: directory)

        let second = AppModel(directory: directory)
        await second.start()
        let current = try XCTUnwrap(second.configuration)
        let currentFolder = try XCTUnwrap(current.storageFolder)
        let currentKey = try XCTUnwrap(current.keyID)
        try await second.store?.close()
        addTeardownBlock {
            try? Keychain.remove(oldKey)
            try? Keychain.remove(currentKey)
            if let connection = current.connectionKeyID { try? Keychain.remove(connection) }
        }

        let relaunched = AppModel(directory: directory)
        await relaunched.load()
        addTeardownBlock { @MainActor in try? await relaunched.store?.close() }
        for _ in 0..<80
        where FileManager.default.fileExists(atPath: directory.appendingPathComponent(oldFolder).path) {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(oldFolder).path),
            "The old leftover is finished.")
        XCTAssertNil(try Keychain.read(oldKey))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(currentFolder).path),
            "The new library's folder survives.")
        XCTAssertNotNil(try Keychain.read(currentKey), "The new library's key survives.")
        XCTAssertNil(relaunched.libraryProblem)
        XCTAssertNotNil(relaunched.store)
    }

    /// The saved connection lives only in its own Keychain item, which is lost when an iPhone is restored from a
    /// backup although the library synced. Absence proves nothing, so the alert never claims journals will be lost or
    /// that the device isn't connected.
    func testTheAlertSaysOnlyWhatTheAppKnowsAboutTheServer() async throws {
        var fixture = try await LibraryFixture.make(self)
        // The library needs its password and the device key is gone: the connection item went with it.
        try Keychain.remove(fixture.account)
        fixture.configuration.connectionKeyID = fixture.account + "-connection"
        try fixture.saveConfiguration()
        let model = fixture.model(self)
        await model.load()
        XCTAssertEqual(model.libraryProblem, .needsKey)

        let unknownWarning = await model.unopenedEraseWarning()
        let unknown = try XCTUnwrap(unknownWarning)
        guard case .unopened(let credential, let host) = unknown else { return XCTFail("\(unknown)") }
        XCTAssertEqual(credential, fixture.configuration.credentialName)
        XCTAssertNil(host)
        let message = EraseSection.message(unknown)
        XCTAssertTrue(message.contains("If this device syncs with a server, journals that have synced stay there."))
        let credentialName = fixture.configuration.credentialName
        XCTAssertTrue(
            message.contains("My Journal needs your \(credentialName) to open them, so it can’t export them first."))
        for claim in ["will be lost", "isn’t connected", "isn't connected", "Export Archive"] {
            XCTAssertFalse(message.contains(claim), claim)
        }

        // A connection that reads names its host, and Erase signs the device out of it.
        let deviceID = UUID()
        let server = try await FakeJournalServer { _ in (204, Data()) }
        let connection = SyncConnection(address: server.address, deviceID: deviceID, token: "synthetic-token")
        try Keychain.write(JournalCoding.encoder().encode(connection), account: fixture.account + "-connection")
        let knownWarning = await model.unopenedEraseWarning()
        let known = try XCTUnwrap(knownWarning)
        guard case .unopened(_, let named) = known else { return XCTFail("\(known)") }
        XCTAssertEqual(named, ServerAddress.host(server.address))
        XCTAssertTrue(
            EraseSection.message(known).contains(
                "Journals that have synced stay on \(ServerAddress.host(server.address)), and this device is signed out."
            ))

        let outcome = await model.eraseUnopenedLibrary()
        XCTAssertEqual(outcome, .erased)
        for _ in 0..<80 where !server.requests.contains(where: { $0.method == "DELETE" }) {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(
            server.requests.contains {
                $0.method == "DELETE" && $0.path == "/v1/devices/\(deviceID.uuidString.lowercased())"
            },
            "\(server.requests.map { $0.method + " " + $0.path })")
    }

    /// Import and Erase need the device owner when App Lock is on, or when the settings can't be read and so App Lock
    /// can't be known; a cancelled prompt changes nothing.
    func testRemovingNeedsTheDeviceOwnerWhenAppLockIsOnOrUnknown() async throws {
        let locked = try await LibraryFixture.make(self, appLock: true)
        try FileManager.default.removeItem(at: locked.libraryURL)
        let unreadable = try await LibraryFixture.make(self)
        try Data("garbage".utf8).write(to: unreadable.configurationURL)
        let open = try await LibraryFixture.make(self)
        try FileManager.default.removeItem(at: open.libraryURL)

        for (fixture, asks) in [(locked, true), (unreadable, true), (open, false)] {
            let owner = TestDeviceOwner()
            owner.outcome = .cancelled
            let model = fixture.model(self)
            model.deviceOwner = owner
            model.applicationActive = true
            await model.load()
            XCTAssertNotNil(model.libraryProblem)
            XCTAssertFalse(model.locked, "A problem state is never locked.")

            let warning = await model.unopenedEraseWarning()
            XCTAssertEqual(owner.requests, asks ? 1 : 0)
            XCTAssertEqual(warning == nil, asks, "A cancelled prompt shows no alert.")
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.configurationURL.path), "Nothing changed.")
            if asks {
                let outcome = await model.eraseUnopenedLibrary()
                XCTAssertEqual(outcome, .erased, "The alert's Erase doesn't ask again.")
                XCTAssertEqual(owner.requests, 1)
                XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.configurationURL.path))
            }
        }
    }
}
