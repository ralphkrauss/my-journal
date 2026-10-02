import JournalCore
import SwiftUI
import XCTest

@testable import Journal

/// App Lock uses the device's own authentication (docs/design/app-lock-system-auth.md).
@MainActor
final class AppLockTests: XCTestCase {
    private struct Library {
        let directory: URL
        let phrase: String
        var file: URL { directory.appendingPathComponent("configuration.json") }
    }

    /// A library with one journal whose configuration `configure` shapes, as an earlier build may have saved it.
    private func library(_ configure: (inout LocalConfiguration) throws -> Void = { _ in }) async throws -> Library {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AppLock-" + UUID().uuidString)
        let account = "app-lock-" + UUID().uuidString
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        // In a folder of its own, so that a test can stop only the settings file from being saved.
        let store = try JournalStore(directory: directory.appendingPathComponent("vault"), key: key)
        let journal = JournalItem(kind: "journal", title: "Personal")
        try await store.save(journal)
        try await store.close()
        try Keychain.write(key, account: account)
        var configuration = LocalConfiguration(
            recovery: try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0,
            recoveryConfirmed: true, storageFolder: "vault", keyID: account, lastJournalID: journal.id)
        try configure(&configuration)
        let library = Library(directory: directory, phrase: phrase)
        try JournalCoding.encoder().encode(configuration).write(to: library.file)
        addTeardownBlock {
            try? Keychain.remove(account)
            try? FileManager.default.removeItem(at: directory)
        }
        return library
    }

    private func launch(_ library: Library, owner: TestDeviceOwner = TestDeviceOwner()) async -> AppModel {
        let model = AppModel(directory: library.directory)
        model.deviceOwner = owner
        model.applicationActive = true
        addTeardownBlock { @MainActor in try? await model.store?.close() }
        await model.load()
        return model
    }

    private func saved(_ library: Library) throws -> LocalConfiguration {
        try JournalCoding.decoder().decode(LocalConfiguration.self, from: Data(contentsOf: library.file))
    }

    /// A device that used an App Lock PIN stays locked, now with the device's authentication, and the PIN's
    /// verifier is gone from disk. Nothing was encrypted with it, so the journals open as before.
    func testAppLockPINMovesToTheDevicesAuthentication() async throws {
        let library = try await library { configuration in
            let salt = try VaultCrypto.random(16)
            configuration.pinSalt = salt
            configuration.pinHash = try VaultCrypto.derive("654321", salt: salt)
            configuration.useBiometrics = true
            configuration.failedUnlocks = 2
        }
        let model = await launch(library)
        XCTAssertTrue(model.locked)
        let raw = try String(contentsOf: library.file, encoding: .utf8)
        for field in ["pinHash", "pinSalt", "useBiometrics", "failedUnlocks"] {
            XCTAssertFalse(raw.contains(field), "\(field) must not stay on disk.")
        }
        XCTAssertEqual(try saved(library).appLock, true)
        XCTAssertEqual(try saved(library).pinRetiredNotice, true)

        await model.unlockWithDevice()
        XCTAssertFalse(model.locked)
        XCTAssertEqual(model.journals.map(\.title), ["Personal"])
        XCTAssertNil(try saved(library).pinRetiredNotice, "The notice is shown until the first unlock.")
        XCTAssertEqual(try saved(library).appLock, true)
    }

    /// Without a PIN there was no App Lock; the old default switch is cleared and the journals open.
    func testLibraryWithoutAPINStaysUnlocked() async throws {
        let library = try await library { $0.useBiometrics = false }
        let model = await launch(library)
        XCTAssertFalse(model.locked)
        XCTAssertNil(try saved(library).appLock)
        XCTAssertNil(try saved(library).useBiometrics)
    }

    /// If moving from the PIN can't be saved, the app still opens locked, and the next launch tries again.
    func testUnsavedMoveFromThePINNeverOpensUnlocked() async throws {
        let library = try await library { configuration in
            configuration.pinSalt = Data([1])
            configuration.pinHash = Data([2])
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: library.directory.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: library.directory.path)
        let model = await launch(library)
        try FileManager.default.setAttributes(
            [.posixPermissions: attributes[.posixPermissions] ?? 0o755], ofItemAtPath: library.directory.path)
        XCTAssertTrue(model.locked)
        XCTAssertNotNil(try saved(library).pinHash, "The save failed, so the PIN is still on disk.")

        let relaunched = await launch(library)
        XCTAssertTrue(relaunched.locked)
        XCTAssertNil(try saved(library).pinHash)
    }

    /// A success that answers an earlier lock must not unlock after a new one, and a success that arrives while the
    /// app isn't active waits for it.
    func testStaleSuccessNeverUnlocks() async throws {
        let owner = TestDeviceOwner()
        owner.holdsRequests = true
        let library = try await library { $0.appLock = true }
        let model = await launch(library, owner: owner)
        XCTAssertTrue(model.locked)

        let first = Task { await model.unlockWithDevice() }
        while !owner.showing { await Task.yield() }
        XCTAssertTrue(model.lockImmediately())
        owner.answer(.success)
        await first.value
        XCTAssertTrue(model.locked, "The request belonged to the earlier lock.")

        let second = Task { await model.unlockWithDevice() }
        while !owner.showing { await Task.yield() }
        model.applicationActive = false
        owner.answer(.success)
        await second.value
        XCTAssertTrue(model.locked, "A success while inactive waits for the app to be active.")
        XCTAssertTrue(model.lockImmediately())
        await model.applicationBecameActive()
        XCTAssertTrue(model.locked, "A lock in between drops the waiting success.")

        let third = Task { await model.unlockWithDevice() }
        while !owner.showing { await Task.yield() }
        model.applicationActive = false
        owner.answer(.success)
        await third.value
        await model.applicationBecameActive()
        XCTAssertFalse(model.locked)
    }

    /// Face ID's panel keeps the app inactive for about a second after a success. On iPhone and iPad the journals
    /// open at once, behind the closing panel, instead of showing the lock screen until the app is active again; the
    /// Mac waits, since its window stays visible behind other apps. Leaving the app before the answer still keeps
    /// them locked.
    func testSuccessWhileTheSystemsPanelCloses() async throws {
        let owner = TestDeviceOwner()
        owner.holdsRequests = true
        let library = try await library { $0.appLock = true }
        let model = await launch(library, owner: owner)

        let unlocking = Task { await model.unlockWithDevice() }
        while !owner.showing { await Task.yield() }
        model.applicationResignedActive()
        owner.answer(.success)
        await unlocking.value
        #if os(iOS)
            XCTAssertFalse(model.locked, "Unlocked without waiting for the app to be active again.")
            XCTAssertEqual(model.journals.map(\.title), ["Personal"])
            XCTAssertFalse(model.openingJournals)
            XCTAssertTrue(model.unlockState.requestInFront, "Nothing covers the journals while the panel closes.")
        #else
            XCTAssertTrue(model.locked, "The Mac applies it once the app is active.")
        #endif
        await model.applicationBecameActive()
        XCTAssertFalse(model.locked)
        XCTAssertFalse(model.unlockState.requestInFront)

        // Going to the background while the panel shows locks again; its success answers the earlier lock.
        XCTAssertTrue(model.lockImmediately())
        let leaving = Task { await model.unlockWithDevice() }
        while !owner.showing { await Task.yield() }
        model.applicationResignedActive()
        XCTAssertTrue(model.lockImmediately())
        XCTAssertFalse(model.unlockState.inactiveForRequest, "The background shows the cover.")
        owner.answer(.success)
        await leaving.value
        await model.applicationBecameActive()
        XCTAssertTrue(model.locked)
        XCTAssertTrue(model.journals.isEmpty)
    }

    /// Cancelling says nothing; a failure offers the recovery credential; no passcode turns App Lock off once.
    func testUnlockOutcomes() async throws {
        let owner = TestDeviceOwner()
        let library = try await library { $0.appLock = true }
        let model = await launch(library, owner: owner)

        owner.outcome = .cancelled
        await model.unlockWithDevice()
        XCTAssertTrue(model.locked)
        XCTAssertFalse(model.unlockState.problem)
        XCTAssertNil(model.error)

        owner.outcome = .failed
        await model.unlockWithDevice()
        XCTAssertTrue(model.locked)
        XCTAssertTrue(model.unlockState.problem, "The lock screen offers the recovery credential.")
        await model.unlockWithRecovery(library.phrase)
        XCTAssertFalse(model.locked)
        XCTAssertEqual(try saved(library).appLock, true, "Recovery keeps App Lock on.")

        XCTAssertTrue(model.lockImmediately())
        owner.availabilityResult = .unavailable
        await model.unlockWithDevice()
        XCTAssertTrue(model.locked)
        XCTAssertTrue(model.unlockState.problem)

        owner.availabilityResult = .noPasscode
        model.applicationActive = false
        await model.unlockWithDevice()
        XCTAssertTrue(model.locked, "Checked only while the app is active.")
        await model.applicationBecameActive()
        XCTAssertFalse(model.locked)
        XCTAssertEqual(model.unlockState.turnedOff, .passcodeRemoved)
        XCTAssertNil(try saved(library).appLock)
    }

    /// Turning App Lock on or off needs the device owner; a cancel, a missing passcode, a lock or a failed save
    /// leaves it as it was.
    func testTurningAppLockOnAndOffNeedsTheDeviceOwner() async throws {
        let owner = TestDeviceOwner()
        let library = try await library()
        let model = await launch(library, owner: owner)
        XCTAssertFalse(model.locked)

        owner.availabilityResult = .noPasscode
        var result = await model.setAppLock(true)
        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(owner.requests, 0, "Without a passcode there is nothing to ask.")
        XCTAssertNil(try saved(library).appLock)

        owner.availabilityResult = .available(.faceID)
        owner.outcome = .cancelled
        result = await model.setAppLock(true)
        XCTAssertEqual(result, .cancelled)
        XCTAssertFalse(model.appLockOn)

        owner.outcome = .success
        result = await model.setAppLock(true)
        XCTAssertEqual(result, .saved)
        XCTAssertEqual(try saved(library).appLock, true)

        owner.outcome = .cancelled
        result = await model.setAppLock(false)
        XCTAssertEqual(result, .cancelled)
        XCTAssertTrue(model.appLockOn)

        await model.lock()
        owner.outcome = .success
        result = await model.setAppLock(false)
        XCTAssertEqual(result, .cancelled, "A locked journal can’t be opened by turning App Lock off.")
        XCTAssertTrue(model.locked)
        await model.unlockWithDevice()

        // A folder where the settings file belongs makes every save fail.
        try FileManager.default.removeItem(at: library.file)
        try FileManager.default.createDirectory(at: library.file, withIntermediateDirectories: false)
        result = await model.setAppLock(false)
        XCTAssertEqual(result, .notSaved)
        XCTAssertTrue(model.appLockOn, "App Lock stays on when turning it off wasn’t saved.")
    }

    #if os(macOS)
        /// Locking while File ▸ Import Archive… shows its open panel closes the panel, so no archive can be chosen
        /// over the lock screen.
        func testLockingClosesTheImportArchivePanel() async throws {
            let library = try await library { $0.appLock = true }
            let model = await launch(library)
            await model.unlockWithDevice()
            XCTAssertFalse(model.locked)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720), styleMask: [.titled, .resizable],
                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(
                rootView: RootView().environmentObject(model).environmentObject(EditorActions()))
            window.orderFront(nil)
            defer { window.close() }

            model.archiveImportRequested = true
            try await waitUntil("the open panel is shown") { window.attachedSheet is NSOpenPanel }
            await model.lock()
            try await waitUntil("the open panel is closed") {
                !model.archiveImportRequested && window.attachedSheet == nil
            }
        }

        /// Locking an open journal window removes its toolbar once. Removing it lays out the window, which takes the
        /// columns away; they removed it again, AppKit released it twice, and their next toolbar update crashed.
        func testLockingRemovesTheJournalToolbarOnce() async throws {
            let library = try await library { $0.appLock = true }
            let model = await launch(library)
            await model.unlockWithDevice()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720), styleMask: [.titled, .resizable],
                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(
                rootView: RootView().environmentObject(model).environmentObject(EditorActions()))
            window.orderFront(nil)
            defer { window.close() }
            try await waitUntil("the journal toolbar is shown") { window.toolbar != nil }
            let columns = try XCTUnwrap(Self.columns(in: window.contentView))
            let toolbar = Watched(window.toolbar)

            await model.lock()
            try await waitUntil("the journal toolbar is removed") { window.toolbar == nil }
            // Lets the autorelease pools drain, which freed a toolbar released twice.
            try await Task.sleep(nanoseconds: 200_000_000)
            XCTAssertNotNil(toolbar.object, "The columns still own their toolbar.")
            if toolbar.object == nil {
                // Their release of the freed toolbar would crash the remaining tests.
                _ = Unmanaged.passRetained(columns)
            }
        }

        private final class Watched {
            weak var object: AnyObject?
            init(_ object: AnyObject?) { self.object = object }
        }

        private static func columns(in view: NSView?) -> JournalSplitViewController? {
            guard let view else { return nil }
            if let controller = (view as? NSSplitView)?.delegate as? JournalSplitViewController { return controller }
            return view.subviews.lazy.compactMap { columns(in: $0) }.first
        }

        private func waitUntil(
            _ description: String, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool
        ) async throws {
            let deadline = Date().addingTimeInterval(5)
            while !condition(), Date() < deadline {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertTrue(condition(), "Waited until \(description)", file: file, line: line)
        }
    #endif
}
