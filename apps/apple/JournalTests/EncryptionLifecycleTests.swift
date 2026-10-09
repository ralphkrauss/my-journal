import JournalCore
import SwiftUI
import XCTest

@testable import Journal

/// Encrypt Your Journals for a library on this device that is not encrypted, and what the next launch does after an
/// interruption (docs/design/1-1-encryption-and-passwords.md §3.4, docs/design/enable-encryption.md). The unencrypted
/// libraries here are made as earlier versions made them (`startLegacyUnencrypted`).
@MainActor
final class EncryptionLifecycleTests: XCTestCase {
    private func library(
        accessPassword: String? = nil, server: EncryptionServer? = nil, address: String? = nil, quickChecks: Bool = true
    ) async throws -> AppModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(directory: root)
        model.preferences = UserDefaults(suiteName: "EncryptionLifecycle-" + UUID().uuidString) ?? .standard
        if quickChecks { model.serverQuestionSeconds = 0.5 }
        addTeardownBlock { @MainActor in
            server?.release()
            _ = await model.finishPendingSave()
            try? await model.store?.close()
            for account in [
                model.configuration?.keyID, model.configuration?.encryptionUpgrade?.keyID,
                model.configuration?.connectionKeyID,
            ] {
                if let account { try? Keychain.remove(account) }
            }
            try? FileManager.default.removeItem(at: root)
        }
        await model.startLegacyUnencrypted()
        model.loaded = true
        if let accessPassword, let key = model.masterKey {
            // A library from before libraries without encryption lost their password (format 3).
            model.configuration?.recovery = try VaultCrypto.makeRecovery(
                masterKey: key, phrase: accessPassword, formatVersion: 3
            ).0
            try model.persistConfiguration()
        }
        await model.newEntry()
        var draft = try XCTUnwrap(model.draft)
        draft.title = "Written before encryption"
        model.updateDraft(draft)
        _ = await model.finishPendingSave()
        if let location = address ?? server?.address { try connect(model, to: location) }
        return model
    }
    /// Gives the library a saved connection, as a library that synced with that server has.
    private func connect(_ model: AppModel, to address: String) throws {
        let connection = SyncConnection(address: address, deviceID: UUID(), token: "synthetic-token")
        let account = "EncryptionLifecycleTests-" + UUID().uuidString
        try Keychain.write(JournalCoding.encoder().encode(connection), account: account)
        model.configuration?.connectionKeyID = account
        try model.persistConfiguration()
        model.connection = connection
        model.configureSync()
    }
    private func folders(in model: AppModel) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: model.directory.path).filter { $0.hasPrefix("vault-") })
    }
    private func relaunch(_ model: AppModel) async throws -> AppModel {
        try await model.store?.close()
        let relaunched = AppModel(directory: model.directory)
        relaunched.serverQuestionSeconds = model.serverQuestionSeconds
        await relaunched.load()
        addTeardownBlock { @MainActor in
            try? await relaunched.store?.close()
            if let account = relaunched.configuration?.keyID { try? Keychain.remove(account) }
        }
        return relaunched
    }
    private func enterPassword(_ upgrade: EncryptionUpgrade, _ password: String = "a master password") {
        upgrade.password = password
        upgrade.verify = password
    }
    /// Waits for a condition the work reaches on its own.
    private func eventually(_ what: String, _ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<400 where !condition() { try await Task.sleep(nanoseconds: 25_000_000) }
        XCTAssertTrue(condition(), what)
    }

    // MARK: The work itself

    func testEncryptingKeepsTheJournalsAndRemovesTheUnencryptedCopy() async throws {
        let model = try await library()
        let entryID = try XCTUnwrap(model.draft?.id)
        let before = try folders(in: model)
        let phases = PhaseLog()
        try await model.turnOnEncryption(password: "a", current: nil) { phases.record($0) }
        await model.supersededRemoval?.value

        let configuration = try XCTUnwrap(model.configuration)
        XCTAssertEqual(configuration.recovery.formatVersion, 2)
        XCTAssertTrue(configuration.encrypted)
        XCTAssertNil(configuration.encryptionUpgrade)
        XCTAssertFalse(model.replacingVault, "Writing continues")
        let protection = await model.store?.protection
        XCTAssertEqual(protection, .encrypted)
        XCTAssertEqual(model.items.first { $0.id == entryID }?.title, "Written before encryption")
        XCTAssertTrue(before.isDisjoint(with: try folders(in: model)), "The unencrypted copy is removed")
        XCTAssertTrue(phases.entries.contains { if case .encrypting = $0 { true } else { false } })
        // The password opens the library, as for any encrypted library.
        let key = try VaultCrypto.recover(configuration.recovery, phrase: "a").0
        XCTAssertEqual(key, model.masterKey)
    }

    /// A sync that is running when encryption is turned on finishes before the copy is made, and a sync of the
    /// unencrypted library that starts meanwhile waits until the encrypted library replaced it, so none of them runs
    /// across the server's switch (where it would send readable journals to the encrypted server).
    func testSyncsOfTheUnencryptedLibraryDontRunAcrossTheSwitch() async throws {
        let model = try await library()
        _ = await model.finishPendingSave()
        let source = try XCTUnwrap(model.store)
        // Stands for a sync that is already running.
        try await source.holdSynchronization()
        let phases = PhaseLog()
        let turningOn = Task { try await model.turnOnEncryption(password: "a", current: nil) { phases.record($0) } }
        while !model.replacingVault { try await Task.sleep(nanoseconds: 10_000_000) }
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(
            phases.entries.contains { if case .encrypting = $0 { true } else { false } },
            "Nothing is copied while a sync runs")
        // Another sync of the unencrypted library starts while encryption waits.
        let later = Task { @MainActor in
            try await source.holdSynchronization()
            let replaced = model.store !== source && model.configuration?.encrypted == true
            await source.releaseSynchronization()
            return replaced
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        await source.releaseSynchronization()
        try await turningOn.value
        XCTAssertEqual(model.configuration?.encrypted, true)
        let replacedFirst = try await later.value
        XCTAssertTrue(replacedFirst, "A later sync of the unencrypted library waits until it was replaced")
    }

    /// The access password of a library from before libraries without encryption (format 3) is asked only when the
    /// library is on a server, and a wrong one changes nothing.
    func testAWrongAccessPasswordChangesNothingAndALocalLibraryNeedsNone() async throws {
        let local = try await library(accessPassword: "current")
        XCTAssertFalse(local.encryption.needsCurrentPassword, "A local format 3 library has no server to ask.")
        try await local.turnOnEncryption(password: "new", current: nil) { _ in }
        XCTAssertEqual(local.configuration?.recovery.formatVersion, 2)

        let model = try await library(accessPassword: "current", address: "http://127.0.0.1:9")
        XCTAssertTrue(model.encryption.needsCurrentPassword)
        let before = try XCTUnwrap(model.configuration)
        do {
            try await model.turnOnEncryption(password: "new", current: "wrong") { _ in }
            XCTFail("The access password is checked first")
        } catch EncryptionFailure.incorrectPassword {}
        XCTAssertEqual(model.configuration?.recovery.formatVersion, 3)
        XCTAssertEqual(model.configuration?.storageFolder, before.storageFolder)
        XCTAssertNil(model.configuration?.encryptionUpgrade)
        XCTAssertFalse(model.replacingVault)
    }

    // MARK: Which screen the window shows

    /// Loading, locked, a library problem, the first-launch screen, a run or an unfinished switch (the journals,
    /// read-only), the form, the recovery key, the journals.
    func testTheWindowRoutesByPrecedence() {
        var routing = WindowRouting()
        XCTAssertEqual(routing.screen, .opening)
        routing.loaded = true
        routing.needsEncryption = true
        routing.hasLibrary = true
        routing.recoveryKey = true
        XCTAssertEqual(routing.screen, .encryptForm)
        routing.encryptionInProgress = true
        XCTAssertEqual(routing.screen, .journals, "A marker or a run is shown before the form is.")
        routing.encryptionInProgress = false
        routing.needsEncryption = false
        XCTAssertEqual(routing.screen, .recoveryKey)
        routing.recoveryKey = false
        XCTAssertEqual(routing.screen, .journals)
        routing.hasLibrary = false
        XCTAssertEqual(routing.screen, .welcome)
        routing.libraryProblem = true
        XCTAssertEqual(routing.screen, .libraryProblem)
        routing.locked = true
        XCTAssertEqual(routing.screen, .locked)
    }

    func testAnUnencryptedLibraryShowsTheFormUntilItIsEncryptedOrNotNowIsChosen() async throws {
        let model = try await library()
        XCTAssertEqual(model.windowRouting.screen, .encryptForm)
        XCTAssertFalse(model.isReady, "The menu commands that need journals are off.")
        XCTAssertFalse(model.canImportArchive)
        XCTAssertTrue(model.encryptionHoldsSynchronization)
        // From Settings, after Not Now, the form is a sheet over the journals: the window does not change.
        model.encryption.notNow()
        XCTAssertEqual(model.windowRouting.screen, .journals)
        XCTAssertTrue(model.isReady)
        XCTAssertFalse(model.encryptionHoldsSynchronization, "Sync resumes as in 1.0.")
        model.encryption.present()
        XCTAssertTrue(model.encryption.formPresented)
        XCTAssertEqual(model.windowRouting.screen, .journals)
        model.encryption.dismissSheet()
        XCTAssertFalse(model.encryption.formPresented)

        let encrypted = try await library()
        try await encrypted.turnOnEncryption(password: "a", current: nil) { _ in }
        XCTAssertEqual(encrypted.windowRouting.screen, .journals)
    }

    // MARK: Not Now

    /// The person's own Cancel returns to the plain form and never unlocks Not Now; the journals are read-only from
    /// Encrypt on, with the entries still shown, and writing returns on cancel.
    func testCancelReturnsToThePlainFormWithoutOfferingNotNow() async throws {
        let server = try await EncryptionServer.start { $0.hangingPrefixes = ["/v1/sync/"] }
        let model = try await library(server: server)
        let upgrade = model.encryption
        upgrade.formAppeared()
        await upgrade.finishedChecking()
        XCTAssertEqual(upgrade.variant, .synced)
        XCTAssertFalse(upgrade.offersNotNow, "A healthy library sees only Encrypt.")
        enterPassword(upgrade)
        upgrade.encrypt()

        try await eventually("The journals pause once Encrypt is chosen") { upgrade.phase == .syncing }
        XCTAssertTrue(model.replacingVault, "Writing is paused from Encrypt, before the pre-sync.")
        XCTAssertTrue(model.writingPausedForEncryption)
        XCTAssertFalse(model.canEdit)
        XCTAssertFalse(model.canCreateEntry)
        XCTAssertFalse(model.items.isEmpty, "The journals stay readable.")
        XCTAssertEqual(model.windowRouting.screen, .journals)
        XCTAssertTrue(upgrade.showsNotice)

        upgrade.cancel()
        server.release()
        await upgrade.finishedWorking()
        XCTAssertFalse(model.replacingVault, "Cancelling gives writing back.")
        XCTAssertNil(upgrade.noticeError)
        XCTAssertEqual(model.windowRouting.screen, .encryptForm, "The plain form returns.")
        upgrade.formAppeared()
        await upgrade.finishedChecking()
        XCTAssertFalse(upgrade.offersNotNow, "Cancel does not unlock Not Now.")
        XCTAssertEqual(model.configuration?.encrypted, false)
        XCTAssertNil(model.configuration?.encryptionUpgrade)
        XCTAssertEqual(server.count("POST", "/v1/recovery/encrypt"), 0)
    }

    /// Each failure leaves the library readable and unchanged and offers Not Now, which opens it with 1.0's behaviour.
    func testEachFailureLeavesTheLibraryReadableAndUnchangedAndOffersNotNow() async throws {
        // Not enough space is found before the journals pause.
        let low = try await library()
        let before = try folders(in: low)
        low.availableStorage = { _ in 1 }
        enterPassword(low.encryption)
        low.encryption.encrypt()
        await low.encryption.finishedWorking()
        XCTAssertTrue(low.encryption.formError?.contains("There isn’t enough space to encrypt your journals") == true)
        XCTAssertTrue(low.encryption.offersNotNow)
        XCTAssertFalse(low.replacingVault)
        XCTAssertEqual(try folders(in: low), before)
        XCTAssertEqual(low.windowRouting.screen, .encryptForm)
        low.encryption.notNow()
        XCTAssertEqual(low.windowRouting.screen, .journals)
        await low.newEntry()
        XCTAssertNotNil(low.draft, "Not Now opens the library as 1.0 did: writing works.")

        // A copy that fails its checks: an image whose file is gone.
        let damaged = try await library()
        let source = try XCTUnwrap(damaged.store)
        let image = try await source.addAttachment(Data("not really a picture".utf8))
        let attachments = await source.directory.appendingPathComponent("attachments")
        for file in try FileManager.default.contentsOfDirectory(atPath: attachments.path) {
            try FileManager.default.removeItem(at: attachments.appendingPathComponent(file))
        }
        _ = image
        let damagedFolders = try folders(in: damaged)
        enterPassword(damaged.encryption)
        damaged.encryption.encrypt()
        await damaged.encryption.finishedWorking()
        XCTAssertEqual(damaged.encryption.noticeError, "Your journals couldn’t be encrypted. They are unchanged.")
        XCTAssertTrue(damaged.encryption.noticeOffersNotNow)
        XCTAssertTrue(damaged.encryption.noticeOffersTryAgain)
        XCTAssertFalse(damaged.encryption.noticeOffersStopSyncing, "A local library has no server to stop using.")
        XCTAssertFalse(damaged.replacingVault, "The journals are back in full use.")
        XCTAssertEqual(try folders(in: damaged), damagedFolders, "The staged copy is removed.")
        XCTAssertNil(damaged.configuration?.encryptionUpgrade)
        XCTAssertEqual(damaged.configuration?.encrypted, false)
        XCTAssertTrue(damaged.items.contains { $0.title == "Written before encryption" })
        XCTAssertEqual(damaged.windowRouting.screen, .journals, "The failure notice is over the journals.")
        damaged.encryption.notNow()
        XCTAssertNil(damaged.encryption.noticeError)
        XCTAssertEqual(damaged.windowRouting.screen, .journals)

        // Other devices are still writing: the second attempt fails the same way.
        let server = try await EncryptionServer.start { $0.switchMode = .serverChanged }
        let busy = try await library(server: server)
        enterPassword(busy.encryption)
        busy.encryption.encrypt()
        await busy.encryption.finishedWorking()
        XCTAssertEqual(busy.encryption.noticeFailure, .stillSyncing)
        XCTAssertTrue(busy.encryption.noticeOffersTryAgain)
        XCTAssertTrue(busy.encryption.noticeOffersNotNow)
        XCTAssertFalse(busy.encryption.noticeOffersStopSyncing, "Another attempt can succeed.")
        XCTAssertEqual(busy.configuration?.encrypted, false)
        XCTAssertFalse(busy.replacingVault)
        XCTAssertEqual(server.count("POST", "/v1/recovery/encrypt"), 2)
    }

    /// An unreachable server offers Try Again and Not Now but not Stop Syncing; a server that is too old and a device
    /// without access offer Stop Syncing, after which the local library encrypts.
    func testServerFailuresOfferTheirExits() async throws {
        let unreachable = try await library(address: "http://127.0.0.1:9")
        unreachable.encryption.formAppeared()
        await unreachable.encryption.finishedChecking()
        XCTAssertEqual(unreachable.encryption.variant, .unavailable)
        XCTAssertEqual(unreachable.encryption.formFailure, .unreachable)
        XCTAssertTrue(unreachable.encryption.offersNotNow)
        XCTAssertFalse(unreachable.encryption.offersStopSyncing, "An unreachable server is not a reason to leave it.")

        let old = try await EncryptionServer.start { $0.tooOld = true }
        let outdated = try await library(server: old)
        outdated.encryption.formAppeared()
        await outdated.encryption.finishedChecking()
        XCTAssertEqual(outdated.encryption.formFailure, .serverOutdated)
        XCTAssertTrue(outdated.encryption.offersNotNow)
        XCTAssertTrue(outdated.encryption.offersStopSyncing)
        XCTAssertEqual(outdated.encryption.formError, "This server needs an update before this device can connect.")
        XCTAssertEqual(old.count("POST", "/v1/recovery/encrypt"), 0)
        outdated.encryption.stopSyncing()
        XCTAssertNil(outdated.connection, "This device stopped using the server.")
        XCTAssertEqual(outdated.encryption.variant, .local)
        XCTAssertFalse(outdated.encryption.offersNotNow, "A local library is healthy.")
        enterPassword(outdated.encryption)
        outdated.encryption.encrypt()
        await outdated.encryption.finishedWorking()
        XCTAssertEqual(outdated.configuration?.encrypted, true, "Stop Syncing leaves a library that then encrypts.")

        let refusing = try await EncryptionServer.start { $0.refusesDevices = true }
        let lost = try await library(server: refusing)
        lost.encryption.formAppeared()
        await lost.encryption.finishedChecking()
        XCTAssertEqual(lost.encryption.formFailure, .accessLost)
        XCTAssertTrue(lost.encryption.offersStopSyncing)
        XCTAssertTrue(lost.encryption.offersNotNow)
    }

    /// Not Now is held in memory: backgrounding, locking and unlocking don't clear it, and a cold start asks again.
    func testNotNowSurvivesLockingAndTheNextColdStartAsksAgain() async throws {
        let model = try await library(address: "http://127.0.0.1:9")
        model.encryption.formAppeared()
        await model.encryption.finishedChecking()
        XCTAssertTrue(model.encryption.offersNotNow)
        model.encryption.notNow()
        model.locked = true
        model.locked = false
        XCTAssertTrue(model.encryption.notNowChosen)
        XCTAssertEqual(model.windowRouting.screen, .journals)
        XCTAssertFalse(model.encryptionHoldsSynchronization)

        let relaunched = try await relaunch(model)
        XCTAssertFalse(relaunched.encryption.notNowChosen)
        XCTAssertEqual(relaunched.windowRouting.screen, .encryptForm, "Nothing remembers Not Now.")
        XCTAssertTrue(relaunched.encryptionHoldsSynchronization)
    }

    // MARK: The server

    /// Until the person chooses Encrypt or Not Now, nothing the app does on its own reaches the server: not a sync,
    /// sending writing, the automatic loop or the sync after a pause in writing.
    func testNoRequestReachesTheServerBeforeTheDecision() async throws {
        let server = try await EncryptionServer.start()
        let model = try await library(server: server)
        _ = await model.sync()
        _ = await model.sync(retryingRefused: true)
        await model.sendWriting()
        model.syncWhenWritingPauses()
        let running = Task { await model.synchronizeAutomatically() }
        try await Task.sleep(nanoseconds: UInt64((SyncEngine.writingPause + 0.5) * 1_000_000_000))
        running.cancel()
        await running.value
        XCTAssertTrue(server.requests.isEmpty, "Nothing reached the server before the decision.")

        model.encryption.notNow()
        let synced = await model.sync()
        XCTAssertTrue(synced)
        XCTAssertFalse(server.requests.isEmpty, "After Not Now the library syncs as it did in 1.0.")
    }

    /// A server that already uses encryption is the sign-in variant: the purge is never called.
    func testAServerThatAlreadyUsesEncryptionIsTheSignInVariantAndIsNeverSwitched() async throws {
        let parameters = RecoveryParameters(
            salt: "c2FsdHNhbHRzYWx0c2FsdA==", iterations: 600_000, formatVersion: 2, wrappedKey: nil)
        let server = try await EncryptionServer.start { $0.parameters = parameters }
        let model = try await library(server: server)
        model.encryption.formAppeared()
        await model.encryption.finishedChecking()
        XCTAssertEqual(model.encryption.variant, .signIn)
        XCTAssertTrue(model.encryption.offersNotNow)
        XCTAssertTrue(model.encryption.offersSignIn)
        XCTAssertEqual(model.windowRouting.screen, .encryptForm, "The form stays; its button is Reconnect.")
        XCTAssertEqual(server.count("POST", "/v1/recovery/encrypt"), 0)
        XCTAssertEqual(model.configuration?.encrypted, false)
    }

    /// The whole run against a server: the journals sync first, the server switches once, the encrypted library
    /// takes over and the Done sheet is shown.
    func testEncryptingASyncedLibrarySwitchesTheServerOnceAndShowsDone() async throws {
        let server = try await EncryptionServer.start()
        let model = try await library(server: server)
        let upgrade = model.encryption
        upgrade.formAppeared()
        await upgrade.finishedChecking()
        XCTAssertEqual(upgrade.variant, .synced)
        enterPassword(upgrade)
        upgrade.encrypt()
        await upgrade.finishedWorking()
        XCTAssertEqual(model.configuration?.encrypted, true)
        XCTAssertNil(model.configuration?.encryptionUpgrade)
        XCTAssertFalse(model.replacingVault)
        XCTAssertTrue(upgrade.donePresented)
        XCTAssertEqual(server.count("POST", "/v1/recovery/encrypt"), 1)
        XCTAssertGreaterThan(server.count("PUT", "/v1/sync/"), 0, "The server received everything first.")
        XCTAssertEqual(server.state.withLock { $0.parameters.formatVersion }, 2)
        XCTAssertEqual(model.windowRouting.screen, .journals)
        XCTAssertTrue(model.items.contains { $0.title == "Written before encryption" })
    }

    /// Another device turned encryption on while this one worked: the purge answers "already encrypted" and the form
    /// becomes the sign-in variant, with the library unchanged.
    func testAnEncryptionAnotherDeviceTurnedOnBecomesTheSignInVariant() async throws {
        let server = try await EncryptionServer.start { $0.switchMode = .alreadyEncrypted }
        let model = try await library(server: server)
        enterPassword(model.encryption)
        model.encryption.encrypt()
        await model.encryption.finishedWorking()
        XCTAssertEqual(model.encryption.variant, .signIn)
        XCTAssertNil(model.encryption.noticeError)
        XCTAssertEqual(model.configuration?.encrypted, false)
        XCTAssertFalse(model.replacingVault)
        XCTAssertEqual(model.windowRouting.screen, .encryptForm)
        XCTAssertTrue(model.encryption.offersNotNow)
    }

    // MARK: Interrupted runs

    /// The disk fills after the server switched: the commit can't be saved. The journals stay readable and paused,
    /// with the server's answer unknown to this device until it tries again.
    private func unfinishedLibrary(
        mode: EncryptionServer.Switch = .switches
    ) async throws -> (AppModel, EncryptionServer) {
        let server = try await EncryptionServer.start { $0.switchMode = mode }
        let model = try await library(server: server)
        let configURL = model.configURL
        server.update {
            $0.onSwitch = {
                try? FileManager.default.removeItem(at: configURL)
                try? FileManager.default.createDirectory(at: configURL, withIntermediateDirectories: true)
            }
        }
        enterPassword(model.encryption)
        model.encryption.encrypt()
        await model.encryption.finishedWorking()
        XCTAssertTrue(model.encryption.unfinished)
        XCTAssertTrue(model.replacingVault, "The journals stay paused until this device knows.")
        XCTAssertEqual(model.windowRouting.screen, .journals)
        XCTAssertFalse(model.items.isEmpty, "They stay readable.")
        XCTAssertTrue(model.encryption.noticeOffersTryAgain)
        XCTAssertTrue(model.encryption.noticeOffersStopSyncing)
        XCTAssertFalse(model.encryption.noticeOffersNotNow)
        return (model, server)
    }
    private func freeTheDisk(_ model: AppModel) throws {
        try FileManager.default.removeItem(at: model.configURL)
        try model.persistConfiguration()
    }

    func testAnUnfinishedSwitchFinishesWithTryAgain() async throws {
        let (model, server) = try await unfinishedLibrary()
        try freeTheDisk(model)
        model.encryption.tryAgain()
        await model.encryption.finishedWorking()
        XCTAssertFalse(model.encryption.unfinished)
        XCTAssertEqual(model.configuration?.encrypted, true)
        XCTAssertNil(model.configuration?.encryptionUpgrade)
        XCTAssertFalse(model.replacingVault)
        XCTAssertTrue(model.encryption.donePresented)
        XCTAssertEqual(server.count("POST", "/v1/recovery/encrypt"), 1, "The server is not asked again.")
        XCTAssertTrue(model.items.contains { $0.title == "Written before encryption" })
    }

    /// The next launch finishes by itself when the server switched.
    func testTheNextLaunchFinishesASwitchTheServerMade() async throws {
        let (model, _) = try await unfinishedLibrary()
        try freeTheDisk(model)
        let relaunched = try await relaunch(model)
        await relaunched.encryption.finishedWorking()
        XCTAssertEqual(relaunched.configuration?.encrypted, true)
        XCTAssertNil(relaunched.configuration?.encryptionUpgrade)
        XCTAssertFalse(relaunched.replacingVault)
        XCTAssertFalse(relaunched.encryption.donePresented, "Finishing at launch is quiet.")
        XCTAssertTrue(relaunched.items.contains { $0.title == "Written before encryption" })
    }

    /// The next launch after the server said yes but kept its envelope: nothing changed, the copy is removed.
    func testTheNextLaunchDiscardsACopyTheServerNeverSwitchedTo() async throws {
        let (model, _) = try await unfinishedLibrary(mode: .acceptsWithoutSwitching)
        let original = try XCTUnwrap(model.configuration?.storageFolder)
        try freeTheDisk(model)
        let relaunched = try await relaunch(model)
        await relaunched.encryption.finishedWorking()
        XCTAssertEqual(relaunched.configuration?.encrypted, false)
        XCTAssertEqual(relaunched.configuration?.storageFolder, original)
        XCTAssertNil(relaunched.configuration?.encryptionUpgrade)
        XCTAssertEqual(try folders(in: relaunched), [original], "The unused copy is gone.")
        XCTAssertEqual(relaunched.windowRouting.screen, .encryptForm)
        XCTAssertTrue(relaunched.items.contains { $0.title == "Written before encryption" })
    }

    /// A copy made but never sent to the server, in every state it can be killed in, is removed at the next launch.
    func testACopyThatNeverReachedTheServerIsRemovedAtTheNextLaunchWhateverItsState() async throws {
        for stagedCopy in [false, true] {
            let model = try await library()
            _ = await model.finishPendingSave()
            let folder = "vault-" + UUID().uuidString.lowercased()
            let account = model.keyAccount + "-" + folder
            let key = try VaultCrypto.generateKey()
            try Keychain.write(key, account: account)
            let envelope = try VaultCrypto.makeRecovery(masterKey: key, phrase: "a", formatVersion: 2).0
            if stagedCopy {
                // The copy made, verified and waiting, as a kill just before asking the server leaves it.
                let source = try XCTUnwrap(model.store)
                let copy = try await source.reencryptedCopy(
                    to: model.directory.appendingPathComponent(folder), key: key, baseline: .restart)
                try await copy.close()
            } else {
                try FileManager.default.createDirectory(
                    at: model.directory.appendingPathComponent(folder), withIntermediateDirectories: true)
            }
            model.configuration?.encryptionUpgrade = EncryptionUpgradeMarker(
                storageFolder: folder, keyID: account, recovery: envelope)
            try model.persistConfiguration()

            let relaunched = try await relaunch(model)
            XCTAssertNil(relaunched.configuration?.encryptionUpgrade)
            XCTAssertFalse(FileManager.default.fileExists(atPath: model.directory.appendingPathComponent(folder).path))
            XCTAssertNil(try Keychain.read(account))
            XCTAssertEqual(relaunched.configuration?.encrypted, false)
            XCTAssertTrue(relaunched.items.contains { $0.title == "Written before encryption" })
            XCTAssertFalse(relaunched.replacingVault)
        }
    }

    /// A kill after the configuration was written: the next launch opens the encrypted library and removes the
    /// readable one.
    func testAKillAfterTheConfigurationWriteLeavesTheEncryptedLibraryAndRemovesTheReadableOne() async throws {
        let model = try await library()
        let readable = try folders(in: model)
        try await model.turnOnEncryption(password: "a", current: nil) { _ in }
        let relaunched = try await relaunch(model)
        await relaunched.supersededRemoval?.value
        XCTAssertEqual(relaunched.configuration?.encrypted, true)
        XCTAssertTrue(readable.isDisjoint(with: try folders(in: relaunched)), "The readable copy is removed.")
        XCTAssertTrue(relaunched.items.contains { $0.title == "Written before encryption" })
    }

    // MARK: The unfinished notice's Stop Syncing

    /// With the server switched, Stop Syncing adopts the verified encrypted copy and drops the connection: nothing is
    /// lost, and the server being gone for good no longer matters.
    func testStopSyncingOnAnUnfinishedSwitchAdoptsTheEncryptedCopy() async throws {
        let (model, _) = try await unfinishedLibrary()
        try freeTheDisk(model)
        model.encryption.stopSyncing()
        await model.encryption.finishedWorking()
        XCTAssertNil(model.connection)
        XCTAssertEqual(model.configuration?.encrypted, true)
        XCTAssertNil(model.configuration?.encryptionUpgrade)
        XCTAssertFalse(model.replacingVault)
        XCTAssertFalse(model.encryption.unfinished)
        XCTAssertTrue(model.encryption.donePresented, "The person learns what to keep.")
        XCTAssertTrue(model.items.contains { $0.title == "Written before encryption" })
    }

    /// If the server answers that it had not switched, nothing is adopted: the original library stays, the copy is
    /// discarded and the connection is dropped.
    func testStopSyncingWhenTheServerHadNotSwitchedKeepsTheOriginal() async throws {
        let (model, _) = try await unfinishedLibrary(mode: .acceptsWithoutSwitching)
        let original = try XCTUnwrap(model.configuration?.storageFolder)
        try freeTheDisk(model)
        model.encryption.stopSyncing()
        await model.encryption.finishedWorking()
        XCTAssertNil(model.connection)
        XCTAssertEqual(model.configuration?.encrypted, false)
        XCTAssertEqual(model.configuration?.storageFolder, original)
        XCTAssertNil(model.configuration?.encryptionUpgrade)
        XCTAssertEqual(try folders(in: model), [original])
        XCTAssertFalse(model.replacingVault)
        XCTAssertFalse(model.encryption.unfinished)
        XCTAssertFalse(model.encryption.donePresented)
        XCTAssertEqual(model.windowRouting.screen, .encryptForm, "A local library is asked again.")
        XCTAssertTrue(model.items.contains { $0.title == "Written before encryption" })
    }

    /// A server that doesn't answer ends in the same two buttons after the time limit, instead of holding the
    /// read-only state, and Stop Syncing then adopts the copy without it.
    func testAHungServerEndsInTheSameTwoButtonsAndStopSyncingAdoptsTheCopy() async throws {
        let (model, server) = try await unfinishedLibrary()
        try freeTheDisk(model)
        server.update { $0.hangingPrefixes = ["/v1/recovery"] }
        model.encryption.tryAgain()
        await model.encryption.finishedWorking()
        XCTAssertTrue(model.encryption.unfinished, "Try Again could not learn the answer.")
        XCTAssertTrue(model.replacingVault)
        XCTAssertTrue(model.encryption.noticeOffersTryAgain)
        XCTAssertTrue(model.encryption.noticeOffersStopSyncing)

        model.encryption.stopSyncing()
        await model.encryption.finishedWorking()
        XCTAssertEqual(model.configuration?.encrypted, true, "An unanswered question adopts the verified copy.")
        XCTAssertNil(model.connection)
        XCTAssertFalse(model.replacingVault)
        XCTAssertTrue(model.items.contains { $0.title == "Written before encryption" })
    }

    /// The task is stopped while the server is being asked, as a background-time expiry does: the run ends as
    /// unfinished, never as lost journals, and the next launch can finish it.
    func testBeingStoppedWhileTheServerIsAskedEndsUnfinishedNotLost() async throws {
        let server = try await EncryptionServer.start { $0.switchMode = .hangs }
        let model = try await library(server: server)
        let plan = try await model.prepareEncryption(password: "a master password", current: nil)
        let running = Task { try await model.runEncryption(plan) { _ in } }
        try await eventually("The request to switch is on its way") { server.count("POST", "/v1/recovery/encrypt") > 0 }
        running.cancel()
        do {
            try await running.value
            XCTFail("The run could not have finished.")
        } catch EncryptionFailure.unfinished {}
        XCTAssertTrue(model.replacingVault, "Writing stays paused until this device knows.")
        XCTAssertTrue(model.encryptionUnfinished)
        XCTAssertEqual(model.configuration?.encrypted, false, "Nothing was discarded or replaced.")
        let folder = try XCTUnwrap(model.configuration?.encryptionUpgrade?.storageFolder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: model.directory.appendingPathComponent(folder).path))
        XCTAssertTrue(model.items.contains { $0.title == "Written before encryption" })
    }
}

@MainActor
private final class PhaseLog {
    var entries: [EncryptionPhase] = []
    func record(_ phase: EncryptionPhase) { entries.append(phase) }
}
