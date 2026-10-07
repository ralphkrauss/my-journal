import JournalCore
import XCTest

@testable import Journal

/// Journals that can't be opened end in a problem the person can act on, never in a half-open library and an alert
/// with the database's own text (docs/design/build-18-fixes-2026-10-06.md §2.1).
@MainActor
final class LibraryProblemTests: XCTestCase {
    private func assertNothingIsOpen(_ model: AppModel, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(model.store, "A problem state never has a live store.", file: file, line: line)
        XCTAssertNil(model.masterKey, file: file, line: line)
        XCTAssertNil(model.connection, file: file, line: line)
        XCTAssertFalse(model.locked, "A problem state is never locked.", file: file, line: line)
        XCTAssertNil(model.error, "No alert, and no raw error text.", file: file, line: line)
    }

    /// The commonest real corruption: the library opens and the first read finds the records malformed.
    func testDamageFoundByTheFirstReadIsAProblemWithAppLockOffAndOn() async throws {
        for appLock in [false, true] {
            let fixture = try await LibraryFixture.make(self, appLock: appLock)
            try fixture.damageRecords()
            let before = try fixture.digest()
            let model = fixture.model(self)

            await model.load()
            if appLock {
                XCTAssertTrue(model.locked, "App Lock still locks at launch; the first read follows the unlock.")
                XCTAssertNil(model.libraryProblem)
                await model.unlockForTesting()
            }

            XCTAssertEqual(model.libraryProblem, .cantOpen, "App Lock \(appLock)")
            assertNothingIsOpen(model)
            XCTAssertTrue(model.showsLibraryProblem)
            XCTAssertEqual(try fixture.digest(), before, "Opening never repairs: the library is left as it is.")
        }
    }

    func testAConnectionThatDoesNotDecodeLeavesNoLiveStoreAndTryAgainReopensItOnceItIsFixed() async throws {
        var fixture = try await LibraryFixture.make(self)
        let connectionAccount = fixture.account + "-connection"
        fixture.configuration.connectionKeyID = connectionAccount
        try fixture.saveConfiguration()
        try Keychain.write(Data("not a connection".utf8), account: connectionAccount)
        let model = fixture.model(self)

        await model.load()
        XCTAssertEqual(model.libraryProblem, .cantOpen)
        assertNothingIsOpen(model)

        // The item is fine again (a restart, or a moment later): Try Again opens the same library.
        try Keychain.remove(connectionAccount)
        await model.retryOpening()
        XCTAssertNil(model.libraryProblem)
        XCTAssertNotNil(model.store)
        XCTAssertEqual(model.items.first { $0.id == fixture.entryID }?.title, "Still here")
    }

    /// A restore or cleanup that leaves the settings naming a library that is gone gives an empty library today, and
    /// sync then uploads emptiness.
    func testAMissingLibraryOrDatabaseIsNeverCreatedEmpty() async throws {
        let fixture = try await LibraryFixture.make(self)
        try FileManager.default.removeItem(at: fixture.libraryURL)
        let missingFolder = fixture.fixtureFolderListing()
        let model = fixture.model(self)

        await model.load()
        XCTAssertEqual(model.libraryProblem, .cantOpen)
        assertNothingIsOpen(model)
        XCTAssertEqual(fixture.fixtureFolderListing(), missingFolder, "Nothing was created.")

        // The folder is there but its database isn't.
        try FileManager.default.createDirectory(at: fixture.libraryURL, withIntermediateDirectories: true)
        let emptyFolder = fixture.fixtureFolderListing()
        await model.retryOpening()
        XCTAssertEqual(model.libraryProblem, .cantOpen)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.databaseURL.path), "No empty library appears.")
        XCTAssertEqual(fixture.fixtureFolderListing(), emptyFolder)
    }

    func testJournalsFromANewerVersionAreItsOwnProblemAndNothingImportsOverThem() async throws {
        let fixture = try await LibraryFixture.make(self)
        try fixture.markAsSavedByNewerVersion()
        let before = try fixture.digest()
        let model = fixture.model(self)

        await model.load()
        XCTAssertEqual(model.libraryProblem, .newerVersion)
        assertNothingIsOpen(model)
        XCTAssertFalse(model.canImportArchive, "Replacing what an update opens would be the opposite of the fix.")
        XCTAssertEqual(try fixture.digest(), before)
        await model.retryOpening()
        XCTAssertEqual(model.libraryProblem, .newerVersion, "There is no Try Again for a newer version.")
    }

    func testAFormatThisVersionDoesNotKnowIsTheNewerVersionProblem() async throws {
        var fixture = try await LibraryFixture.make(self)
        fixture.configuration.recovery.formatVersion = 99
        try fixture.saveConfiguration()
        let model = fixture.model(self)

        await model.load()
        XCTAssertEqual(model.libraryProblem, .newerVersion)
        assertNothingIsOpen(model)
    }

    /// A file that exists but can't be read is not a first launch: nothing replaces it, and nothing the app does at
    /// launch acts on what it can't see.
    func testUnreadableSettingsAreNeverReplacedAndEarlierErasuresWait() async throws {
        let fixture = try await LibraryFixture.make(self)
        // An erase left unfinished: finishing it needs to know what the library uses.
        let leftover = fixture.directory.appendingPathComponent("erased-" + UUID().uuidString.lowercased())
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: leftover.appendingPathComponent("configuration.json"))
        try JournalCoding.encoder().encode(ErasureList(accounts: [fixture.account], attempts: 0)).write(
            to: leftover.appendingPathComponent(LocalErasure.listName))
        try Data("{ this isn't a configuration".utf8).write(to: fixture.configurationURL)
        let before = try fixture.digest()
        let model = fixture.model(self)

        await model.load()
        XCTAssertEqual(model.libraryProblem, .settingsUnread)
        XCTAssertNil(model.configuration)
        XCTAssertNil(model.store)
        XCTAssertNotNil(try Keychain.read(fixture.account), "The library's key wasn't removed as a leftover.")
        await model.retryOpening()
        XCTAssertEqual(model.libraryProblem, .settingsUnread)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(try fixture.digest(), before, "The file is byte for byte as it was, and so is everything else.")

        // Nothing that replaces the configuration goes ahead.
        await model.start(encrypted: false)
        XCTAssertNil(model.configuration)
        XCTAssertNil(model.store)
        do {
            try await model.recoverServer(address: "https://journal.example.com", phrase: "x", uploadLocal: false)
            XCTFail("Connecting replaced settings that couldn't be read")
        } catch is LibraryNotOpenError {}
        XCTAssertEqual(try fixture.digest(), before)
    }

    func testASettingsFileThatCannotBeReadAtAllIsTheSameState() async throws {
        let fixture = try await LibraryFixture.make(self)
        try FileManager.default.removeItem(at: fixture.configurationURL)
        try FileManager.default.createDirectory(at: fixture.configurationURL, withIntermediateDirectories: false)
        let model = fixture.model(self)
        await model.load()
        XCTAssertEqual(model.libraryProblem, .settingsUnread, "A read error is not a first launch either.")
    }

    /// Only a person's tap counts, and Erase is offered after one failed tap. A success clears the problem, and with App
    /// Lock on it ends locked, as at any launch.
    func testTryAgainCountsOnlyTapsAndEndsLockedWithAppLockOn() async throws {
        let fixture = try await LibraryFixture.make(self, appLock: true)
        try FileManager.default.moveItem(at: fixture.libraryURL, to: fixture.directory.appendingPathComponent("moved"))
        let model = fixture.model(self)
        await model.load()
        XCTAssertEqual(model.libraryProblem, .cantOpen)
        XCTAssertEqual(model.failedRetries, 0, "The launch's own failure isn't a tap.")

        await model.retryOpening(tapped: false)
        XCTAssertEqual(model.failedRetries, 0, "The automatic retry never counts.")
        model.protectedDataAvailable = false
        await model.retryOpening()
        XCTAssertEqual(model.failedRetries, 0, "A tap while protected data isn't available never counts.")
        model.protectedDataAvailable = true
        await model.retryOpening()
        XCTAssertEqual(model.failedRetries, 1)
        XCTAssertFalse(model.lockImmediately(), "A problem state is never locked: there is no store to unlock.")
        XCTAssertFalse(model.locked)

        try FileManager.default.moveItem(at: fixture.directory.appendingPathComponent("moved"), to: fixture.libraryURL)
        await model.retryOpening()
        XCTAssertNil(model.libraryProblem)
        XCTAssertTrue(model.locked, "With App Lock on, opening ends at the lock screen, not on the journals.")
        XCTAssertTrue(model.items.isEmpty)
    }

    /// The automatic retry, when protected data becomes available, is the same: it never lands on the journals.
    func testTheAutomaticRetryEndsLockedWithAppLockOn() async throws {
        let fixture = try await LibraryFixture.make(self, appLock: true)
        let hidden = fixture.directory.appendingPathComponent("hidden")
        try FileManager.default.moveItem(at: fixture.libraryURL, to: hidden)
        let model = fixture.model(self)
        model.protectedDataAvailable = false
        await model.load()
        XCTAssertEqual(model.libraryProblem, .cantOpen)

        try FileManager.default.moveItem(at: hidden, to: fixture.libraryURL)
        await model.protectedDataBecameAvailable()
        XCTAssertNil(model.libraryProblem)
        XCTAssertTrue(model.locked)
        XCTAssertTrue(model.items.isEmpty, "The journals aren't read until the person unlocks.")
        XCTAssertEqual(model.failedRetries, 0)
        XCTAssertTrue(model.protectedDataAvailable)
    }

    /// Every overwrite of the configuration goes through `persistConfiguration`, which refuses while the journals can't
    /// be opened or the settings read, whatever future entry point asks.
    func testSavingTheConfigurationIsRefusedWhileTheJournalsCannotBeOpened() async throws {
        for problem in [LibraryProblem.settingsUnread, .cantOpen, .newerVersion] {
            let fixture = try await LibraryFixture.make(self)
            switch problem {
            case .settingsUnread: try Data("garbage".utf8).write(to: fixture.configurationURL)
            case .newerVersion: try fixture.markAsSavedByNewerVersion()
            default: try FileManager.default.removeItem(at: fixture.libraryURL)
            }
            let model = fixture.model(self)
            await model.load()
            XCTAssertEqual(model.libraryProblem, problem)
            let before = try fixture.digest()
            model.configuration = fixture.configuration
            XCTAssertThrowsError(try model.persistConfiguration(), "\(problem)")
            XCTAssertEqual(try fixture.digest(), before, "\(problem): the file is byte for byte unchanged.")
            if !problem.offersImport {
                XCTAssertThrowsError(try model.persistRestoredConfiguration(), "Only the archive install may switch.")
                XCTAssertEqual(try fixture.digest(), before)
            }
        }
    }

    /// Replacing settings that couldn't be read, or journals a newer version wrote, is what no archive may do; over
    /// journals that can't be opened it is the way back (SupersededLibraryTests, MissingDeviceKeyTests).
    func testAnArchiveIsNeverInstalledOverUnreadableSettingsOrANewerVersion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Source-" + UUID().uuidString)
        let source = AppModel(directory: directory)
        source.preferences = UserDefaults(suiteName: "Source-" + UUID().uuidString) ?? .standard
        await source.start(encrypted: false)
        let account = source.configuration?.keyID
        let archive = try await source.prepareArchive()
        addTeardownBlock { @MainActor in
            try? await source.store?.close()
            if let account { try? Keychain.remove(account) }
            try? FileManager.default.removeItem(at: directory)
        }

        for problem in [LibraryProblem.settingsUnread, .newerVersion, .cantOpen] {
            let fixture = try await LibraryFixture.make(self)
            switch problem {
            case .settingsUnread: try Data("garbage".utf8).write(to: fixture.configurationURL)
            case .newerVersion: try fixture.markAsSavedByNewerVersion()
            default: try FileManager.default.removeItem(at: fixture.libraryURL)
            }
            let model = fixture.model(self)
            await model.load()
            XCTAssertEqual(model.libraryProblem, problem)
            XCTAssertEqual(model.canImportArchive, problem.offersImport, "\(problem)")
            let file = try Data(contentsOf: fixture.configurationURL)
            let restored = try await model.inspectArchive(archive, phrase: "")
            do {
                try await model.installArchive(restored)
                XCTAssertTrue(problem.offersImport, "\(problem) was replaced")
            } catch is LibraryNotOpenError {
                XCTAssertFalse(problem.offersImport, "\(problem)")
                XCTAssertEqual(try Data(contentsOf: fixture.configurationURL), file, "Nothing replaced the settings.")
            }
            await model.discardImportedCopy(restored)
        }
    }

    func testErasingAndStartingAgainLeavesNoProblemBehind() async throws {
        let fixture = try await LibraryFixture.make(self)
        try fixture.damageRecords()
        let model = fixture.model(self)
        await model.load()
        XCTAssertEqual(model.libraryProblem, .cantOpen)
        model.failedRetries = 1
        let warning = await model.unopenedEraseWarning()
        XCTAssertNotNil(warning)
        let outcome = await model.eraseUnopenedLibrary()
        XCTAssertEqual(outcome, .erased)
        XCTAssertNil(model.libraryProblem, "The welcome screen isn't followed by the problem screen.")
        XCTAssertEqual(model.failedRetries, 0)
        XCTAssertFalse(model.showsLibraryProblem)
        XCTAssertNil(model.configuration)
    }
}

extension LibraryFixture {
    /// The names directly in the data folder and in the library's folder, for "nothing was created".
    func fixtureFolderListing() -> [String] {
        let manager = FileManager.default
        let top = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
        let inner = (try? manager.contentsOfDirectory(atPath: libraryURL.path)) ?? []
        return top.sorted() + inner.sorted().map { folder + "/" + $0 }
    }
}
