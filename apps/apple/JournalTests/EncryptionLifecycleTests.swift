import JournalCore
import SwiftUI
import XCTest

@testable import Journal

/// Turning on encryption for a library on this device, and what the next launch does after an interruption
/// (docs/design/enable-encryption.md).
@MainActor
final class EncryptionLifecycleTests: XCTestCase {
    private func library(accessPassword: String? = nil) async throws -> AppModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(directory: root)
        addTeardownBlock { @MainActor in
            _ = await model.finishPendingSave()
            try? await model.store?.close()
            for account in [model.configuration?.keyID, model.configuration?.encryptionUpgrade?.keyID] {
                if let account { try? Keychain.remove(account) }
            }
            try? FileManager.default.removeItem(at: root)
        }
        await model.start(encrypted: false)
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
        return model
    }
    private func folders(in model: AppModel) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: model.directory.path).filter { $0.hasPrefix("vault-") })
    }

    func testTurningOnEncryptionKeepsTheJournalsAndRemovesTheUnencryptedCopy() async throws {
        let model = try await library()
        let entryID = try XCTUnwrap(model.draft?.id)
        let before = try folders(in: model)
        let phases = PhaseLog()
        try await model.turnOnEncryption(password: "a", current: nil) { phases.record($0) }
        await model.supersededRemoval?.value

        let configuration = try XCTUnwrap(model.configuration)
        XCTAssertEqual(configuration.recovery.formatVersion, 2)
        XCTAssertTrue(configuration.encrypted)
        XCTAssertEqual(configuration.passwordChecked, true)
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

    func testAWrongAccessPasswordChangesNothing() async throws {
        let model = try await library(accessPassword: "current")
        let before = try XCTUnwrap(model.configuration)
        do {
            try await model.turnOnEncryption(password: "new", current: "wrong") { _ in }
            XCTFail("The access password is checked first")
        } catch EncryptionFailure.incorrectPassword {}
        XCTAssertEqual(model.configuration?.recovery.formatVersion, 3)
        XCTAssertEqual(model.configuration?.storageFolder, before.storageFolder)
        XCTAssertNil(model.configuration?.encryptionUpgrade)
        try await model.turnOnEncryption(password: "new", current: "current") { _ in }
        XCTAssertEqual(model.configuration?.recovery.formatVersion, 2)
    }

    /// The app quit while making the copy: the next launch removes it and opens the library as it was.
    func testACopyInterruptedBeforeTheSwitchIsRemovedAtTheNextLaunch() async throws {
        let model = try await library()
        _ = await model.finishPendingSave()
        let folder = "vault-" + UUID().uuidString.lowercased()
        let account = model.keyAccount + "-" + folder
        try Keychain.write(try VaultCrypto.generateKey(), account: account)
        let envelope = try VaultCrypto.makeRecovery(masterKey: VaultCrypto.generateKey(), phrase: "a", formatVersion: 2)
            .0
        try FileManager.default.createDirectory(
            at: model.directory.appendingPathComponent(folder), withIntermediateDirectories: true)
        model.configuration?.encryptionUpgrade = EncryptionUpgradeMarker(
            storageFolder: folder, keyID: account, recovery: envelope)
        try model.persistConfiguration()
        try await model.store?.close()

        let relaunched = AppModel(directory: model.directory)
        await relaunched.load()
        addTeardownBlock { @MainActor in try? await relaunched.store?.close() }
        XCTAssertNil(relaunched.configuration?.encryptionUpgrade)
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.directory.appendingPathComponent(folder).path))
        XCTAssertNil(try Keychain.read(account))
        XCTAssertEqual(relaunched.configuration?.encrypted, false)
        XCTAssertTrue(relaunched.items.contains { $0.title == "Written before encryption" })
        XCTAssertFalse(relaunched.replacingVault)
    }
}

@MainActor
private final class PhaseLog {
    var entries: [EncryptionPhase] = []
    func record(_ phase: EncryptionPhase) { entries.append(phase) }
}
