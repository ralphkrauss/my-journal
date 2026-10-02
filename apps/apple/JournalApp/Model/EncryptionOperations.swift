import Foundation
import JournalCore
import os

/// A switch to an encrypted copy of the library in progress (docs/design/enable-encryption.md). It's saved before
/// the copy is made, so the next launch removes a copy that was never used, or finishes a switch the server made.
struct EncryptionUpgradeMarker: Codable {
    /// The copy's folder in the app's data folder, and the Keychain account of its new vault key.
    var storageFolder: String
    var keyID: String
    var recovery: RecoveryEnvelope
    /// The server was asked to switch. Only its answer decides whether this device finishes or discards the copy.
    var contactingServer = false
}

/// Why turning on encryption stopped. Each leaves the library as it was, except `unfinished`.
enum EncryptionFailure: Error, Equatable {
    case unreachable, serverOutdated, accessLost, turnedOnElsewhere, stillSyncing, imagesMissing
    case incorrectPassword, rateLimited, failed
    case notEnoughSpace(Int64)
    /// The server switched, but this device couldn't open its encrypted copy yet; writing stays paused.
    case unfinished
    /// Another device wrote to the server after this one last read it.
    case serverChanged
}

/// What the app is doing while it turns on encryption.
enum EncryptionPhase: Equatable {
    case checking, syncing, encrypting(Double), updatingServer
}

extension AppModel {
    /// Checks what Continue on the first step checks: free space and, when synced, that the server can do this and
    /// this device still has access.
    func checkEncryptionReadiness() async throws {
        guard !locked, !replacingVault, let store, configuration?.encrypted == false else {
            throw EncryptionFailure.failed
        }
        try await requireSpace(for: store)
        guard let connection else { return }
        let client = try ServerClient(address: connection.address, token: connection.token)
        do {
            guard try await client.status().supports(ServerClient.encryptionUpgradeFeature) else {
                throw EncryptionFailure.serverOutdated
            }
            _ = try await client.devices()
        } catch JournalError.unauthorized {
            throw await lostAccess(connection)
        } catch let failure as EncryptionFailure {
            throw failure
        } catch {
            throw EncryptionFailure.unreachable
        }
    }

    /// Turns on encryption with `password`. `current` is the access password of a library that has one. `report`
    /// follows what's happening. Cancelling before the server is asked leaves the library unchanged.
    func turnOnEncryption(
        password: String, current: String?, report: @escaping @MainActor @Sendable (EncryptionPhase) -> Void
    ) async throws {
        guard !locked, !replacingVault, let configuration, !configuration.encrypted, let source = store,
            let oldKey = masterKey
        else { throw EncryptionFailure.failed }
        let currentSecret = try await verifyAccessPassword(current, envelope: configuration.recovery, key: oldKey)
        guard await finishPendingSave() else { throw EncryptionFailure.failed }
        let key = try VaultCrypto.generateKey()
        let made = try await Task.detached {
            try VaultCrypto.makeRecovery(masterKey: key, phrase: password, formatVersion: 2)
        }.value
        for attempt in 1...2 {
            try Task.checkCancellation()
            if connection != nil {
                report(.syncing)
                try await synchronizeBeforeEncrypting()
            }
            do {
                try await encrypt(
                    source, key: key, envelope: made.0, secret: made.1, currentSecret: currentSecret, report: report)
                return
            } catch EncryptionFailure.serverChanged where attempt == 1 {
                // Another device wrote meanwhile: read it, then make the copy again, once.
                continue
            } catch EncryptionFailure.serverChanged {
                throw EncryptionFailure.stillSyncing
            }
        }
    }

    /// The access password's recovery secret for a library that has one, after checking it opens this library's key.
    private func verifyAccessPassword(_ current: String?, envelope: RecoveryEnvelope, key: Data) async throws
        -> String?
    {
        guard envelope.formatVersion == 3 else { return nil }
        let phrase = current ?? ""
        let opened = try? await Task.detached { try VaultCrypto.recover(envelope, phrase: phrase) }.value
        guard let opened, opened.0 == key else { throw EncryptionFailure.incorrectPassword }
        return opened.1
    }

    /// Receives everything the server has, including every image, which the server removes when it switches.
    private func synchronizeBeforeEncrypting() async throws {
        guard let syncEngine, let connection, let store else { throw EncryptionFailure.failed }
        var remaining = Int.max
        while true {
            let report: SyncReport
            do {
                report = try await syncEngine.synchronize(retryingRefused: true)
            } catch let failure as SyncFailure
                where [.needsYou, .serverChanged, .noAccess].contains(failure.health.kind)
            {
                throw await lostAccess(connection)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw error is URLError ? EncryptionFailure.unreachable : EncryptionFailure.failed
            }
            // Images download a few at a time; stop once a pass gets none.
            guard report.imagesToDownload > 0, report.imagesToDownload < remaining else { break }
            remaining = report.imagesToDownload
        }
        try? await refresh()
        let missing = await store.missingAttachments(try store.referencedAttachmentIDs())
        guard !missing.isEmpty else { return }
        let client = try ServerClient(address: connection.address, token: connection.token)
        for image in missing where try await client.hasAttachment(image) == true {
            throw EncryptionFailure.imagesMissing
        }
    }

    private func encrypt(
        _ source: JournalStore, key: Data, envelope: RecoveryEnvelope, secret: String, currentSecret: String?,
        report: @escaping @MainActor @Sendable (EncryptionPhase) -> Void
    ) async throws {
        try await requireSpace(for: source)
        let folder = "vault-" + UUID().uuidString.lowercased()
        var marker = EncryptionUpgradeMarker(
            storageFolder: folder, keyID: keyAccount + "-" + folder, recovery: envelope)
        try Keychain.write(key, account: marker.keyID)
        do { try saveEncryptionMarker(marker) } catch {
            try? Keychain.remove(marker.keyID)
            throw error
        }
        pauseWriting(true)
        // A synchronization already running finishes first, and none starts until the encrypted copy replaced this
        // library: one that ran across the switch would find a server that no longer matches this library.
        do { try await source.holdSynchronization() } catch {
            await discardEncryptionCopy(nil, marker: marker)
            throw error
        }
        var staged: JournalStore?
        do {
            guard await finishPendingSave() else { throw EncryptionFailure.failed }
            let position = try await source.syncedPosition()
            report(.encrypting(0))
            let copy = try await source.reencryptedCopy(
                to: directory.appendingPathComponent(folder), key: key, baseline: .restart
            ) { fraction in Task { @MainActor in report(.encrypting(fraction)) } }
            staged = copy
            if let connection {
                try Task.checkCancellation()
                marker.contactingServer = true
                try saveEncryptionMarker(marker)
                report(.updatingServer)
                try await askServerToEncrypt(
                    connection, envelope: envelope, secret: secret, currentSecret: currentSecret, position: position,
                    marker: marker)
            }
            try await commitEncryption(copy, key: key, marker: marker)
            await source.releaseSynchronization()
        } catch {
            await source.releaseSynchronization()
            if marker.contactingServer, !(error is EncryptionFailure) || error as? EncryptionFailure == .unfinished {
                // The server may have switched; writing stays paused until this device knows. Try Again and the next
                // launch open the copy again from its folder.
                try? await staged?.close()
                throw EncryptionFailure.unfinished
            }
            await discardEncryptionCopy(staged, marker: marker)
            throw error
        }
    }

    /// Asks the server to replace its vault. A refusal changed nothing; when the answer is lost, the server is asked
    /// which envelope it has.
    private func askServerToEncrypt(
        _ connection: SyncConnection, envelope: RecoveryEnvelope, secret: String, currentSecret: String?,
        position: (cursor: Int64, change: LoggedChange?), marker: EncryptionUpgradeMarker
    ) async throws {
        let client = try ServerClient(address: connection.address, token: connection.token)
        do {
            _ = try await client.turnOnEncryption(
                envelope, recoverySecret: secret, currentRecoverySecret: currentSecret, after: position)
        } catch let refusal as EncryptionUpgradeRefusal {
            switch refusal {
            case .serverChanged: throw EncryptionFailure.serverChanged
            case .serverOutdated: throw EncryptionFailure.serverOutdated
            case .incorrectPassword: throw EncryptionFailure.incorrectPassword
            case .alreadyEncrypted: throw EncryptionFailure.turnedOnElsewhere
            case .failed:
                guard try await serverAdopted(marker, address: connection.address) else {
                    throw EncryptionFailure.failed
                }
            }
        } catch is ServerRateLimited {
            throw EncryptionFailure.rateLimited
        } catch JournalError.unauthorized {
            throw await lostAccess(connection)
        } catch {
            // The request may have arrived: only the server's envelope says.
            guard let adopted = try? await serverAdopted(marker, address: connection.address) else {
                throw EncryptionFailure.unfinished
            }
            guard adopted else { throw EncryptionFailure.unreachable }
        }
    }

    /// Whether the server has the envelope this device sent: the same salt and wrapped key.
    private func serverAdopted(_ marker: EncryptionUpgradeMarker, address: String) async throws -> Bool {
        let parameters = try await ServerClient(address: address).recoveryParameters()
        return parameters.formatVersion == 2 && parameters.salt == marker.recovery.salt
    }

    /// Switches to the encrypted copy with one configuration write, as connecting to a server does. The previous
    /// library is removed once the copy opened and, when synced, has synchronized.
    private func commitEncryption(_ destination: JournalStore, key: Data, marker: EncryptionUpgradeMarker) async throws
    {
        guard let previous = configuration else { throw EncryptionFailure.failed }
        var next = previous
        next.recovery = marker.recovery
        next.recoveryConfirmed = true
        next.passwordChecked = true
        next.storageFolder = marker.storageFolder
        next.keyID = marker.keyID
        next.encryptionUpgrade = nil
        next.supersededLibraries = librariesSuperseded(by: previous)
        configuration = next
        do { try persistConfiguration() } catch {
            configuration = previous
            throw error
        }
        await openReplacedLibrary(destination, key: key)
        pauseWriting(false)
        syncWhenWritingPauses()
    }

    private func discardEncryptionCopy(_ staged: JournalStore?, marker: EncryptionUpgradeMarker) async {
        try? await staged?.close()
        removeEncryptionCopy(marker)
        pauseWriting(false)
        try? await refresh()
    }
    private func removeEncryptionCopy(_ marker: EncryptionUpgradeMarker) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(marker.storageFolder))
        try? Keychain.remove(marker.keyID)
        configuration?.encryptionUpgrade = nil
        saveMigratedConfiguration()
    }
    private func saveEncryptionMarker(_ marker: EncryptionUpgradeMarker) throws {
        let previous = configuration?.encryptionUpgrade
        configuration?.encryptionUpgrade = marker
        do { try persistConfiguration() } catch {
            configuration?.encryptionUpgrade = previous
            throw error
        }
    }

    /// At launch, before the library opens: a copy that never reached the server is removed, and the library opens
    /// as it was.
    func discardUnsentEncryptionCopy() {
        guard let marker = configuration?.encryptionUpgrade, !marker.contactingServer else { return }
        removeEncryptionCopy(marker)
    }
    /// Whether a switch the server may have made waits to be finished on this device.
    var encryptionUnfinished: Bool { configuration?.encryptionUpgrade?.contactingServer == true }

    /// Finishes a switch the server may have made: with the server's new envelope, this device opens its encrypted
    /// copy; with the old one, the copy is removed and nothing changed. Writing stays paused until it's known.
    func finishInterruptedEncryption() async throws {
        guard let marker = configuration?.encryptionUpgrade, marker.contactingServer else { return }
        guard let connection else {
            removeEncryptionCopy(marker)
            return
        }
        pauseWriting(true)
        let adopted: Bool
        do { adopted = try await serverAdopted(marker, address: connection.address) } catch {
            throw EncryptionFailure.unfinished
        }
        guard adopted else {
            await discardEncryptionCopy(nil, marker: marker)
            return
        }
        // As when turning on encryption, no synchronization of the unencrypted library runs while it's replaced.
        let previous = store
        do { try await previous?.holdSynchronization() } catch { throw EncryptionFailure.unfinished }
        do {
            guard let key = try Keychain.read(marker.keyID) else { throw EncryptionFailure.failed }
            let staged = try JournalStore(
                directory: directory.appendingPathComponent(marker.storageFolder), key: key, protection: .encrypted)
            try await staged.validateSnapshot()
            try await commitEncryption(staged, key: key, marker: marker)
            await previous?.releaseSynchronization()
        } catch {
            await previous?.releaseSynchronization()
            throw EncryptionFailure.unfinished
        }
    }

    /// Stops with the space still needed when the copy won't fit.
    private func requireSpace(for store: JournalStore) async throws {
        let needed = try await store.reencryptionSize() + 50 * 1024 * 1024
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values?.volumeAvailableCapacityForImportantUsage, available < needed else { return }
        throw EncryptionFailure.notEnoughSpace(needed - available)
    }

    /// Why the server refused this device: encryption was turned on from another device, or it was signed out.
    func lostAccess(_ connection: SyncConnection) async -> EncryptionFailure {
        let parameters = try? await ServerClient(address: connection.address).recoveryParameters()
        guard let parameters, [1, 2].contains(parameters.formatVersion), configuration?.encrypted == false else {
            return .accessLost
        }
        encryption.turnedOnElsewhere = true
        return .turnedOnElsewhere
    }

    /// Encrypts this library's journals with the server's key for signing in again, reporting how far it has come.
    func reencryptForRejoin(_ source: JournalStore, to destination: URL, key: Data) async throws -> JournalStore {
        encryption.rejoinProgress = 0
        defer { encryption.rejoinProgress = nil }
        let upgrade = encryption
        return try await source.reencryptedCopy(to: destination, key: key, baseline: .reconcile) { fraction in
            Task { @MainActor in
                if upgrade.rejoinProgress != nil { upgrade.rejoinProgress = fraction }
            }
        }
    }
}
