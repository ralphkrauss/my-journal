import Foundation
import JournalCore

/// Setting up, joining and merging with a server (docs/design/connection-onboarding.md,
/// docs/design/join-with-local-journals.md).
extension AppModel {
    func initializeServer(address: String, code: String, phrase: String, uploadLocal: Bool) async throws {
        guard !locked, !replacingVault else { throw JournalError.locked }
        try await checkReconnection(address: address)
        guard await finishPendingSave() else { throw JournalError.server("Save your changes before connecting.") }
        if store != nil && !uploadLocal {
            throw JournalError.server("Choose whether to upload your local journals before connecting.")
        }
        guard store != nil else { throw JournalError.server("Create a journal before setting up your server.") }
        guard let envelope = configuration?.recovery, let key = masterKey else { throw JournalError.invalidData }
        guard !locked, !replacingVault else { throw JournalError.locked }
        do {
            vaultReplacement = true
            connectingToServer = true
            defer {
                vaultReplacement = false
                connectingToServer = false
            }
            let recoveryPhrase = recoveryKey ?? phrase
            let recovered = try await Task.detached {
                if !envelope.requiresPassword {
                    return (key, try VaultCrypto.random(32).map { String(format: "%02x", $0) }.joined())
                }
                return try VaultCrypto.recover(envelope, phrase: recoveryPhrase)
            }.value
            guard recovered.0 == key else { throw JournalError.invalidRecoveryKey }
            try Task.checkCancellation()
            guard !locked else { throw JournalError.locked }
            let client = try ServerClient(address: address)
            let grant = try await client.initialize(
                code: code, envelope: envelope, recoverySecret: recovered.1, deviceName: deviceName)
            do {
                try Task.checkCancellation()
                guard !locked else { throw JournalError.locked }
                try commitConnection(SyncConnection(address: address, deviceID: grant.deviceId, token: grant.token))
            } catch {
                try? await ServerClient(address: address, token: grant.token).revoke(grant.deviceId)
                throw error
            }
        }
        await sync()
    }
    private func commitConnection(_ value: SyncConnection) throws {
        let account = keyAccount + "-connection-" + UUID().uuidString.lowercased()
        try Keychain.write(JournalCoding.encoder().encode(value), account: account)
        let previous = configuration
        configuration?.connectionKeyID = account
        configuration?.stoppedSyncingWithFormerMacServer = nil
        do { try persistConfiguration() } catch {
            configuration = previous
            try? Keychain.remove(account)
            throw error
        }
        // The connection this one replaces, as when setting up a reset server again, is no longer used.
        if let old = previous?.connectionKeyID, old != account { try? Keychain.remove(old) }
        connection = value
        configureSync()
    }
    /// Connects to an initialized server with its password, recovery key or one-time recovery code. `shown` is what
    /// the server published about its recovery envelope when the person chose what to type; it must not change.
    /// `replacingEmptyLibrary` replaces a library with nothing written in it instead of uploading it.
    func recoverServer(
        address: String, phrase: String, uploadLocal: Bool, shown: RecoveryParameters? = nil,
        replacingEmptyLibrary: Bool = false
    ) async throws {
        guard !locked else { throw JournalError.locked }
        guard await flush() else { throw JournalError.server("Save your changes before connecting.") }
        if store != nil && !uploadLocal && !(replacingEmptyLibrary && nothingWritten) {
            throw JournalError.server("Choose whether to upload your local journals before connecting.")
        }
        try await checkReconnection(address: address)
        let client = try ServerClient(address: address)
        let parameters = try await client.recoveryParameters()
        try checkServerEnvelope(parameters, shown: shown)
        if parameters.requiresPassword {
            let recovered: RecoveredVault
            do {
                recovered = try await client.recoverVault(phrase, parameters: parameters, deviceName: deviceName)
            } catch is RecoveryEnvelopeChanged { throw ServerConnectionError.serverChanged }
            try await installServerVault(
                address: address, key: recovered.key, envelope: recovered.envelope, grant: recovered.grant,
                uploadLocal: uploadLocal, replacingEmptyLibrary: replacingEmptyLibrary)
            return
        }
        // A known connection belongs to this library. Retain its plaintext record IDs, revision baselines and
        // pending edits when replacing a device credential.
        let retainedKey = configuration?.recovery.formatVersion == 4 && connection != nil ? masterKey : nil
        let key: Data
        let grant: DeviceGrant
        if let pending = retryGrant, pending.address == address {
            // The one-time code was spent by the attempt that failed; Try Again continues with its access.
            (key, grant) = (pending.key, pending.grant)
        } else {
            // Only the server's own recovery code is ever sent as typed; a password never is.
            guard let code = Self.serverRecoveryCode(phrase) else { throw ServerConnectionError.invalidRecoveryCode }
            do { grant = try await client.recover(secret: code, deviceName: deviceName) } catch JournalError
                .invalidRecoveryKey
            {
                // The server's one-time code was wrong or already used.
                throw ServerConnectionError.invalidRecoveryCode
            }
            key = try retainedKey ?? VaultCrypto.generateKey()
        }
        try await installKeepingGrant(
            address: address, key: key, envelope: .unprotected, grant: grant, uploadLocal: uploadLocal,
            replacingEmptyLibrary: replacingEmptyLibrary)
    }
    /// Installs with access that can't be asked for again, keeping it and the staged copy for Try Again until the
    /// flow is left (`giveUpRetry`).
    private func installKeepingGrant(
        address: String, key: Data, envelope: RecoveryEnvelope, grant: DeviceGrant, uploadLocal: Bool,
        replacingEmptyLibrary: Bool
    ) async throws {
        do {
            try await installServerVault(
                address: address, key: key, envelope: envelope, grant: grant, uploadLocal: uploadLocal,
                keepsStageForRetry: true, replacingEmptyLibrary: replacingEmptyLibrary)
            retryGrant = nil
        } catch {
            // Cancelling or locking gave the access up already.
            retryGrant = Task.isCancelled || locked ? nil : (address, key, grant)
            throw error
        }
    }
    /// Leaving the connection flow gives up access kept for Try Again and the copy staged with it, so writing
    /// continues in the library as it was.
    func giveUpRetry() async {
        let pending = retryGrant
        retryGrant = nil
        await discardStagedVault()
        if let pending { await revokeUnused(pending.grant, address: pending.address) }
    }
    /// Installs the vault key another device sent. `recoveryVersion` comes from that device's grant; `shown` is what
    /// the server published about its recovery envelope while connecting.
    /// `replacingEmptyLibrary` joins with a scanned code on a device whose library has no entries or templates: that
    /// library is replaced instead of uploaded, since there's nothing in it to keep.
    func installPairedVault(
        address: String, key: Data, token: String, deviceID: UUID, uploadLocal: Bool, recoveryVersion: Int = 1,
        shown: RecoveryParameters? = nil, replacingEmptyLibrary: Bool = false
    ) async throws {
        if replacingEmptyLibrary && !nothingWritten { throw JournalError.server("This device already has journals.") }
        // Read with the new device credential: servers with `private-envelope` don't publish the wrapped key.
        let envelope = try await ServerClient(address: address, token: token).recoveryEnvelope()
        guard envelope.formatVersion == recoveryVersion else { throw JournalError.invalidData }
        if let shown, !shown.describes(envelope) { throw ServerConnectionError.serverChanged }
        try checkServerEnvelope(RecoveryParameters(envelope), shown: nil)
        try await installKeepingGrant(
            address: address, key: key, envelope: envelope, grant: DeviceGrant(deviceId: deviceID, token: token),
            uploadLocal: uploadLocal, replacingEmptyLibrary: replacingEmptyLibrary)
    }
    /// What this library holds, as Connect to a Server describes it (docs/design/join-with-local-journals.md).
    var libraryContents: LibraryContents { LibraryContents(items: items, conflicts: conflicts.count) }
    /// No library, or one nobody wrote anything in that isn't connected: joining a server replaces it.
    var nothingWritten: Bool { store == nil || (connection == nil && libraryContents.nothingWritten) }
    /// Joining a server merges this library's journals with the server's, after the Merge Journals step.
    var joinsByMerging: Bool { connection == nil && !nothingWritten }
    /// The grant gives up its access unless the library already uses it. Revoking can fail; the device then stays in
    /// the Devices list, where another device can revoke it.
    private func revokeUnused(_ grant: DeviceGrant, address: String) async {
        guard connection?.deviceID != grant.deviceId else { return }
        try? await ServerClient(address: address, token: grant.token).revoke(grant.deviceId)
    }
    private func installServerVault(
        address: String, key: Data, envelope: RecoveryEnvelope, grant: DeviceGrant, uploadLocal: Bool,
        keepsStageForRetry: Bool = false, replacingEmptyLibrary: Bool = false
    ) async throws {
        do {
            guard !locked else { throw JournalError.locked }
            try await checkReconnection(address: address)
            guard await flush() else { throw JournalError.server("Save your changes before connecting.") }
            if store != nil && !uploadLocal && !(replacingEmptyLibrary && nothingWritten) {
                throw JournalError.server("Choose whether to upload your local journals before connecting.")
            }
            guard !locked else { throw JournalError.locked }
            guard !vaultReplacement, !committingMutation else {
                throw JournalError.server("A connection is already being set up.")
            }
        } catch {
            // A pairing grant stays for Try Again until the flow is left, which gives it up (ConnectionFlow).
            if !keepsStageForRetry { await revokeUnused(grant, address: address) }
            throw error
        }
        if let stagedVault, stagedVault.deviceID != grant.deviceId { await removeStagedVault() }
        vaultReplacement = true
        connectingToServer = true
        mergeSending = false
        defer {
            connectingToServer = false
            joinPhase = nil
            mergeSending = false
        }
        do {
            try await switchToServerVault(
                address: address, key: key, envelope: envelope, grant: grant, uploadLocal: uploadLocal)
            vaultReplacement = false
            // Shows that the library synced with its new connection, and resumes automatic sync.
            await sync()
        } catch {
            vaultReplacement = false
            // Only Try Again with the same grant reuses the staged copy. Until then nothing can change this
            // library (see `replacingVault`), so the copy never misses newer writing.
            if !keepsStageForRetry || Task.isCancelled || locked {
                await removeStagedVault()
                await revokeUnused(grant, address: address)
            }
            // Merging may have sent some journals already; Try Again finishes without duplicates.
            if joinPhase != nil, !(error is CancellationError), !(error is ServerConnectionError),
                !(error is MergeConsentNeeded)
            {
                throw MergeInterrupted(underlying: error, sent: mergeSending)
            }
            throw error
        }
    }
    private func switchToServerVault(
        address: String, key serverKey: Data, envelope: RecoveryEnvelope, grant: DeviceGrant, uploadLocal: Bool
    ) async throws {
        // Both secrets use unique accounts. Only the atomic configuration pointer commits the switch.
        let folder: String
        let destination: JournalStore
        let merges: Bool
        let key: Data
        if let stagedVault, stagedVault.deviceID == grant.deviceId {
            (folder, destination, merges, key) = (
                stagedVault.folder, stagedVault.store, stagedVault.merges, stagedVault.key
            )
        } else {
            let protection = try envelope.contentProtection
            (merges, key) = try await joinPlan(
                address: address, key: serverKey, protection: protection, grant: grant, uploadLocal: uploadLocal)
            folder = "vault-" + UUID().uuidString.lowercased()
            if merges, let old = store {
                destination = try await stageMerge(
                    old, in: folder, key: key, protection: protection, address: address, grant: grant)
            } else {
                destination = try await stageCopy(
                    in: folder, key: key, protection: protection, uploadLocal: uploadLocal)
            }
            stagedVault = (grant.deviceId, folder, destination, merges, key)
        }
        let value = SyncConnection(address: address, deviceID: grant.deviceId, token: grant.token)
        let engine = SyncEngine(store: destination, client: try ServerClient(address: address, token: grant.token))
        if merges {
            joinPhase = .merging
            mergeSending = true
        }
        try await engine.synchronize()
        try Task.checkCancellation()
        guard !locked else { throw JournalError.locked }
        let account = keyAccount + "-" + folder
        let connectionAccount = account + "-connection"
        try Keychain.write(key, account: account)
        try Keychain.write(JournalCoding.encoder().encode(value), account: connectionAccount)
        let oldConfiguration = configuration
        try commitConfiguration(
            LocalConfiguration(
                recovery: envelope, recoveryConfirmed: true, storageFolder: folder, keyID: account,
                connectionKeyID: connectionAccount, appLock: oldConfiguration?.appLock,
                inactivityLockMinutes: oldConfiguration?.inactivityLockMinutes,
                supersededLibraries: librariesSuperseded(by: store == nil ? nil : oldConfiguration)),
            writtenAccounts: [account, connectionAccount])
        stagedVault = nil
        masterKey = key
        let previous = store
        store = destination
        connection = value
        configureSync(keeping: engine)
        selectedID = nil
        draft = nil
        selectedJournalID = nil
        items = []
        imageLoader.clear()
        do {
            try await refresh()
            selectInitialEntry()
            // This library synchronized before it replaced the previous one.
            removeSupersededLibraries(synchronized: true)
        } catch {
            self.error =
                "The server is connected, but your journals couldn’t be displayed. Reopen My Journal to try again."
        }
        // Agents read what has synced: this device's journals, merged or uploaded, reach them now.
        if let agentCopies { await agentCopies.requestPublishing() }
        try? await previous?.close()
    }
    /// Makes `new` the configuration, the one step that switches libraries. When it can't be saved, the previous one
    /// stays and the Keychain items written for the new one are removed. `persist` stands in for saving in tests.
    func commitConfiguration(
        _ new: LocalConfiguration, writtenAccounts: [String], persist: (() throws -> Void)? = nil
    ) throws {
        let previous = configuration
        configuration = new
        do { try (persist ?? persistConfiguration)() } catch {
            configuration = previous
            for account in writtenAccounts { try? Keychain.remove(account) }
            throw error
        }
    }
    /// Removes library copies a connection staged but never committed, for example because the app quit between
    /// sending and saving the configuration, with any Keychain items written for them. Only `vault-` folders that
    /// the configuration doesn't name and that nothing changed for an hour are removed, so a join still in progress
    /// in another instance of the app is left alone; the library itself is unchanged.
    func removeAbandonedCopies(now: Date = Date()) {
        guard let configuration else { return }
        var named = Set((configuration.supersededLibraries ?? []).compactMap(\.storageFolder))
        if let folder = configuration.storageFolder { named.insert(folder) }
        if let upgrade = configuration.encryptionUpgrade { named.insert(upgrade.storageFolder) }
        let manager = FileManager.default
        let folders = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
        for folder in folders where folder.hasPrefix("vault-") && !named.contains(folder) {
            let url = directory.appendingPathComponent(folder)
            let changed = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let changed, now.timeIntervalSince(changed) > 3600 else { continue }
            try? manager.removeItem(at: directory.appendingPathComponent(folder))
            try? Keychain.remove(keyAccount + "-" + folder)
            try? Keychain.remove(keyAccount + "-" + folder + "-connection")
        }
    }
    /// How this library joins a server it was granted access to (docs/design/sync-health-and-recovery.md §3.3): by
    /// identity when the server holds this library, otherwise by merging. Returns whether it merges and the key the
    /// joined library uses. Merging a connected library, whose server was replaced, needs the person's agreement
    /// first; nothing has been sent when `MergeConsentNeeded` is thrown.
    func joinPlan(
        address: String, key: Data, protection: ContentProtection, grant: DeviceGrant, uploadLocal: Bool
    ) async throws -> (merges: Bool, key: Data) {
        guard uploadLocal, let store else { return (false, key) }
        let merges: Bool
        var joinedKey = key
        if protection == .encrypted, configuration?.encrypted == true {
            // Encrypted on both sides: the same vault key is the same library.
            merges = masterKey != key
        } else {
            joinPhase = .checking
            let client = try ServerClient(address: address, token: grant.token)
            merges = try await !SyncLineage.serverHoldsLibrary(store, client: client)
            // Without encryption on the server, the key only protects this device's copy: the library keeps its own,
            // so its stored records are used as they are.
            if !merges, protection == .plaintext, let masterKey { joinedKey = masterKey }
        }
        if merges, connection != nil, agreedMergeHost != ServerAddress.host(address) { throw MergeConsentNeeded() }
        return (merges, joinedKey)
    }
    /// A new folder holding everything the server has, then this library's journals merged into it
    /// (docs/design/join-with-local-journals.md §2.1). Sending them is the next synchronization. A copy that fails part
    /// way is removed; merging again derives the same identities, so nothing is duplicated.
    private func stageMerge(
        _ source: JournalStore, in folder: String, key: Data, protection: ContentProtection, address: String,
        grant: DeviceGrant
    ) async throws -> JournalStore {
        let destinationURL = directory.appendingPathComponent(folder)
        var staged: JournalStore?
        do {
            let destination = try JournalStore(directory: destinationURL, key: key, protection: protection)
            staged = destination
            let client = try ServerClient(address: address, token: grant.token)
            joinPhase = .downloading
            try await SyncEngine(store: destination, client: client).synchronize()
            try Task.checkCancellation()
            joinPhase = .merging
            let server = try await client.status().serverId ?? client.address.absoluteString
            // A journal an agent reads is never combined, so the agent can't read this device's entries.
            let readByAgents = try await client.journalsAgentsCanRead(vaultKey: key, protection: protection)
            try await destination.importMerging(from: source, server: server, readByAgents: readByAgents)
            return destination
        } catch {
            try? await staged?.close()
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }
    /// A new folder for the server's vault key and mode, holding this library's journals when they're uploaded.
    /// A copy that fails part way is removed, so Try Again never continues from an incomplete one.
    private func stageCopy(
        in folder: String, key: Data, protection: ContentProtection, uploadLocal: Bool
    ) async throws -> JournalStore {
        let destinationURL = directory.appendingPathComponent(folder)
        var staged: JournalStore?
        do {
            // Joining by identity (`joinPlan`): a library without encryption is encrypted with the server's key,
            // whether it's still connected (encryption turned on elsewhere) or connects again after Stop Syncing.
            if uploadLocal, let old = store, configuration?.encrypted == false, protection == .encrypted {
                // Encryption was turned on from another device: this library's journals keep their identities.
                return try await reencryptForRejoin(old, to: destinationURL, key: key)
            }
            if uploadLocal, let old = store, masterKey == key {
                // Re-encrypting an existing image would violate the server's immutable-byte contract.
                // Preserve the exact ciphertext, revision baseline and retry receipts for the same vault.
                try await old.snapshot(to: destinationURL)
            }
            let destination = try JournalStore(directory: destinationURL, key: key, protection: protection)
            staged = destination
            return destination
        } catch {
            try? await staged?.close()
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }
    /// Removes the copy staged by a connection that didn't finish, so editing continues. The library is unchanged.
    func discardStagedVault() async {
        guard !vaultReplacement else { return }
        await removeStagedVault()
    }
    private func removeStagedVault() async {
        guard let staged = stagedVault else { return }
        stagedVault = nil
        try? await staged.store.close()
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(staged.folder))
    }
    private func checkReconnection(address: String) async throws {
        guard let connection else { return }
        guard try ServerClient(address: address).address == ServerClient(address: connection.address).address else {
            throw JournalError.server("Reconnect to the same server to keep your journals together.")
        }
        do {
            _ = try await ServerClient(address: connection.address, token: connection.token).devices()
        } catch JournalError.unauthorized { return }
        throw JournalError.server("This device is already connected to this server.")
    }
}

/// What joining a server is doing while it reads the server and merges this library's journals.
enum JoinPhase: Equatable {
    case checking, downloading, merging
    var label: String {
        switch self {
        case .checking: return "Checking…"
        case .downloading: return "Downloading…"
        case .merging: return "Merging…"
        }
    }
}
/// The server holds another library, so this connected library's journals would be merged with it. The person agrees
/// on Merge Journals first (docs/design/sync-health-and-recovery.md §3.2); nothing was sent.
struct MergeConsentNeeded: Error {}
/// Merging stopped part way. When sending had started (`sent`), some of this device's journals may already be on the
/// server.
struct MergeInterrupted: Error, LocalizedError {
    let underlying: Error
    let sent: Bool
    var errorDescription: String? { underlying.localizedDescription }
}
