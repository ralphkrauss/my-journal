#if os(macOS)
    import AppKit
    import Combine
    import JournalCore
    import XCTest

    @testable import Journal

    /// Time for an inactivity lock that only moves when a test says so; due wake-ups run as the system's would.
    @MainActor
    private final class TestInactivityClock: InactivityClock {
        private(set) var now = ContinuousClock.now
        private var pending: [(id: UUID, deadline: ContinuousClock.Instant, action: @MainActor @Sendable () -> Void)] =
            []

        var scheduled: Bool { !pending.isEmpty }

        func wake(at deadline: ContinuousClock.Instant, _ action: @escaping @MainActor @Sendable () -> Void)
            -> AnyCancellable
        {
            let id = UUID()
            pending.append((id, deadline, action))
            return AnyCancellable { [weak self] in
                MainActor.assumeIsolated { self?.pending.removeAll { $0.id == id } }
            }
        }

        /// Moves time on. `firing: false` is a wake-up that runs late, as with App Nap or sleep.
        func advance(by duration: Duration, firing: Bool = true) {
            now += duration
            guard firing else { return }
            while let index = pending.firstIndex(where: { $0.deadline <= now }) {
                let wake = pending.remove(at: index)
                wake.action()
            }
        }
    }

    /// Lock when inactive on the Mac (docs/design/mac-inactivity-lock-2026-10-03.md).
    @MainActor
    final class InactivityLockTests: XCTestCase {
        private struct Library {
            let directory: URL
            let entryID: UUID
            var file: URL { directory.appendingPathComponent("configuration.json") }
        }

        /// A library with App Lock on and one entry, which opens when it's unlocked.
        private func library(minutes: Int? = nil) async throws -> Library {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "InactivityLock-" + UUID().uuidString)
            let account = "inactivity-lock-" + UUID().uuidString
            let key = try VaultCrypto.generateKey()
            let store = try JournalStore(directory: directory.appendingPathComponent("vault"), key: key)
            let journal = JournalItem(kind: "journal", title: "Personal")
            let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Morning", document: .plain("Begun"))
            try await store.save(journal)
            try await store.save(entry)
            try await store.close()
            try Keychain.write(key, account: account)
            var configuration = LocalConfiguration(
                recovery: try VaultCrypto.makeRecovery(masterKey: key, phrase: VaultCrypto.recoveryPhrase()).0,
                recoveryConfirmed: true, storageFolder: "vault", keyID: account, appLock: true,
                inactivityLockMinutes: minutes, lastJournalID: journal.id)
            configuration.lastEntryID = entry.id
            let library = Library(directory: directory, entryID: entry.id)
            try JournalCoding.encoder().encode(configuration).write(to: library.file)
            addTeardownBlock {
                try? Keychain.remove(account)
                try? FileManager.default.removeItem(at: directory)
            }
            return library
        }

        /// Opens and unlocks the library, and starts measuring with `clock`.
        private func unlocked(
            _ library: Library, clock: TestInactivityClock, owner: TestDeviceOwner = TestDeviceOwner()
        ) async throws -> (AppModel, InactivityLock) {
            let model = AppModel(directory: library.directory)
            model.deviceOwner = owner
            model.applicationActive = true
            addTeardownBlock { @MainActor in try? await model.store?.close() }
            await model.load()
            await model.unlockWithDevice()
            XCTAssertFalse(model.locked)
            let lock = InactivityLock(model: model, clock: clock, intervalOverride: nil)
            model.inactivityLock = lock
            lock.start()
            addTeardownBlock { @MainActor in lock.stop() }
            return (model, lock)
        }

        /// Lets a lock that started finish saving and locking.
        private func settle(_ lock: InactivityLock) async {
            await lock.locking?.value
        }

        private func savedMinutes(_ library: Library) throws -> Int? {
            try JournalCoding.decoder().decode(LocalConfiguration.self, from: Data(contentsOf: library.file))
                .inactivityLockMinutes
        }

        func testLocksOnceThirtyMinutesPassWithoutUse() async throws {
            let clock = TestInactivityClock()
            let (model, lock) = try await unlocked(library(), clock: clock)

            clock.advance(by: .seconds(29 * 60))
            await settle(lock)
            XCTAssertFalse(model.locked)

            clock.advance(by: .seconds(60))
            await settle(lock)
            XCTAssertTrue(model.locked)
            XCTAssertTrue(model.journals.isEmpty)
            XCTAssertFalse(clock.scheduled, "Nothing waits while locked.")
        }

        /// Use resets the time: the lock comes a full interval after the last use, with one more wake-up.
        func testUsePostponesTheLock() async throws {
            let clock = TestInactivityClock()
            let (model, lock) = try await unlocked(library(), clock: clock)

            clock.advance(by: .seconds(20 * 60))
            XCTAssertTrue(lock.noteUse())
            clock.advance(by: .seconds(15 * 60))
            await settle(lock)
            XCTAssertFalse(model.locked, "The first deadline passed, but there was use 15 minutes ago.")

            clock.advance(by: .seconds(15 * 60))
            await settle(lock)
            XCTAssertTrue(model.locked)
        }

        /// When the wake-up runs late, as in App Nap or after sleep, the first input after the deadline locks and is
        /// discarded instead of keeping the journals open.
        func testUseAfterTheDeadlineLocksInsteadOfPostponing() async throws {
            let clock = TestInactivityClock()
            let (model, lock) = try await unlocked(library(), clock: clock)

            clock.advance(by: .seconds(45 * 60), firing: false)
            XCTAssertFalse(lock.noteUse(), "The input is discarded.")
            XCTAssertFalse(lock.noteUse(), "So is input while it locks.")
            await settle(lock)
            XCTAssertTrue(model.locked)
        }

        func testNeverDoesntLock() async throws {
            let clock = TestInactivityClock()
            let (model, lock) = try await unlocked(library(minutes: 0), clock: clock)

            XCTAssertFalse(clock.scheduled)
            clock.advance(by: .seconds(24 * 60 * 60))
            lock.checkDeadline()
            XCTAssertTrue(lock.noteUse())
            await settle(lock)
            XCTAssertFalse(model.locked)
        }

        /// A shorter time applies at once, counted from the change, and doesn't ask.
        func testShorterTimeTakesEffectAtOnce() async throws {
            let clock = TestInactivityClock()
            let owner = TestDeviceOwner()
            let library = try await library()
            let (model, lock) = try await unlocked(library, clock: clock, owner: owner)
            let asked = owner.requests

            clock.advance(by: .seconds(10 * 60))
            let result = await model.setInactivityLock(minutes: 5)
            XCTAssertEqual(result, .saved)
            XCTAssertEqual(owner.requests, asked, "Locking sooner needs no authentication.")
            XCTAssertEqual(try savedMinutes(library), 5)

            clock.advance(by: .seconds(4 * 60))
            await settle(lock)
            XCTAssertFalse(model.locked)
            clock.advance(by: .seconds(60))
            await settle(lock)
            XCTAssertTrue(model.locked)
        }

        /// A longer time or Never weakens App Lock, so it needs the device owner; cancelling keeps the time.
        func testLongerTimeOrNeverNeedsTheDeviceOwner() async throws {
            let clock = TestInactivityClock()
            let owner = TestDeviceOwner()
            let library = try await library()
            let (model, lock) = try await unlocked(library, clock: clock, owner: owner)
            let asked = owner.requests

            owner.outcome = .cancelled
            var result = await model.setInactivityLock(minutes: 60)
            XCTAssertEqual(result, .cancelled)
            XCTAssertEqual(owner.requests, asked + 1)
            XCTAssertEqual(model.inactivityLockMinutes, 30)
            XCTAssertNil(try savedMinutes(library))

            owner.outcome = .success
            result = await model.setInactivityLock(minutes: 0)
            XCTAssertEqual(result, .saved)
            XCTAssertEqual(owner.requests, asked + 2)
            XCTAssertEqual(try savedMinutes(library), 0)
            clock.advance(by: .seconds(5 * 60 * 60))
            await settle(lock)
            XCTAssertFalse(model.locked, "Never applies at once.")

            result = await model.setInactivityLock(minutes: 15)
            XCTAssertEqual(result, .saved)
            XCTAssertEqual(owner.requests, asked + 2, "Turning it back on from Never doesn't ask.")
            clock.advance(by: .seconds(15 * 60))
            await settle(lock)
            XCTAssertTrue(model.locked)
        }

        /// An action the person started, such as adding a device, holds the time; it starts again when it ends.
        func testActionInProgressHoldsTheLock() async throws {
            let clock = TestInactivityClock()
            let (model, lock) = try await unlocked(library(), clock: clock)
            let action = UUID()

            lock.hold(true, by: action)
            clock.advance(by: .seconds(2 * 60 * 60))
            XCTAssertTrue(lock.noteUse(), "Input during an action isn't late.")
            await settle(lock)
            XCTAssertFalse(model.locked)

            lock.hold(false, by: action)
            clock.advance(by: .seconds(29 * 60))
            await settle(lock)
            XCTAssertFalse(model.locked, "The time started again when the action ended.")
            clock.advance(by: .seconds(60))
            await settle(lock)
            XCTAssertTrue(model.locked)
        }

        /// Passing the pointer over the window while working in another app isn't use; clicks and scrolling are.
        func testPointerMovementCountsOnlyWhileActive() {
            XCTAssertFalse(InactivityLock.counts(.mouseMoved, applicationActive: false))
            XCTAssertTrue(InactivityLock.counts(.mouseMoved, applicationActive: true))
            XCTAssertTrue(InactivityLock.counts(.scrollWheel, applicationActive: false))
            XCTAssertTrue(InactivityLock.counts(.leftMouseDown, applicationActive: false))
        }

        /// Writing that isn't stored yet is stored before the journals lock, never lost.
        func testUnsavedWritingIsStoredBeforeLocking() async throws {
            let clock = TestInactivityClock()
            let library = try await library()
            let (model, lock) = try await unlocked(library, clock: clock)
            var edited = try XCTUnwrap(model.draft)
            XCTAssertEqual(edited.id, library.entryID)
            edited.document = .plain("Written before stepping away")
            // An edit whose save hasn't run yet.
            model.keepingDraftBase { model.draft = edited }
            XCTAssertFalse(model.draftIsSaved)

            var savedWhenLocking: Bool?
            let watching = model.$locked.dropFirst().sink { locked in
                if locked { savedWhenLocking = model.draftIsSaved }
            }
            defer { watching.cancel() }
            clock.advance(by: .seconds(30 * 60))
            await settle(lock)
            XCTAssertTrue(model.locked)
            XCTAssertEqual(savedWhenLocking, true, "Saved before the lock, not only after it.")

            await model.unlockWithDevice()
            XCTAssertEqual(model.items.first { $0.id == library.entryID }?.document, edited.document)
        }
    }
#endif
