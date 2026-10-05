import Foundation
import JournalCore
import os

/// What Erase Journals and Settings warns about (docs/design/erase-device-2026-10-04.md §2).
enum EraseWarning: Equatable {
    /// Connected, syncing normally, nothing waiting: the journals stay on the server.
    case onServer(host: String)
    /// Connected, and this many items haven't reached the server.
    case unsent(count: Int, host: String)
    /// Connected, but the last sync failed or never completed: what the server has can't be confirmed.
    case unconfirmed(host: String)
    /// Not syncing: the journals are only on this device.
    case notSyncing
    /// Not syncing, and nothing was written yet.
    case nothingWritten

    /// Whether erasing loses journals that exist only on this device, so an archive is offered first.
    var losesJournals: Bool {
        switch self {
        case .onServer, .nothingWritten: return false
        case .unsent, .unconfirmed, .notSyncing: return true
        }
    }

    /// Whether erasing now loses nothing the person wasn't told about when they saw `shown`.
    func isCovered(by shown: EraseWarning) -> Bool {
        if self == shown || !losesJournals { return true }
        if case .unsent(let count, let host) = self, case .unsent(let shownCount, let shownHost) = shown {
            return count <= shownCount && host == shownHost
        }
        return false
    }
}

/// Why Erase Journals and Settings is unavailable at the moment.
enum EraseBlock: Equatable {
    /// This Mac runs the sync server for the person's devices (§4.2).
    case serverOnThisMac
    /// Another operation is changing the library, or a save failed (§4.3).
    case busy
}

/// How an erase ended.
enum EraseOutcome: Equatable {
    case erased
    /// Nothing was erased: the authentication was cancelled or the app locked.
    case cancelled
    /// Nothing was erased: more would be lost than the person was told, which is shown again.
    case changed(EraseWarning)
    /// Nothing was erased: the configuration couldn't be moved.
    case failed
}

extension AppModel {
    var eraseBlock: EraseBlock? {
        #if os(macOS)
            if localServer.hasSetup || localServer.isConfigured { return .serverOnThisMac }
            if localServer.busy { return .busy }
        #endif
        if replacingVault || connectingToServer || deleteAllPhase != .idle || saveFailure || encryption.busy
            || erasingLibrary
        {
            return .busy
        }
        return nil
    }

    /// Saves the open writing, then says what erasing would lose; nil when there is no library to erase.
    func eraseWarning() async -> EraseWarning? {
        guard store != nil, !locked else { return nil }
        _ = await flush()
        #if DEBUG
            if let shown = Self.uiTestEraseWarning { return shown }
        #endif
        return await currentEraseWarning()
    }

    #if DEBUG
        /// A warning a UI test chooses (`JOURNAL_UI_TEST_ERASE_WARNING`: onServer, unsent:<count>, unconfirmed,
        /// notSyncing, nothingWritten), so each alert can be seen without a server. It is only shown: Erase checks
        /// what would really be lost, and a library with more to lose than shown gets the real alert instead.
        private static var uiTestEraseWarning: EraseWarning? {
            guard let value = ProcessInfo.processInfo.environment["JOURNAL_UI_TEST_ERASE_WARNING"] else { return nil }
            let host = "journal.example.com"
            switch value.split(separator: ":").first {
            case "onServer": return .onServer(host: host)
            case "unsent": return .unsent(count: Int(value.split(separator: ":").last ?? "") ?? 1, host: host)
            case "unconfirmed": return .unconfirmed(host: host)
            case "notSyncing": return .notSyncing
            case "nothingWritten": return .nothingWritten
            default: return nil
            }
        }
    #endif

    /// What erasing would lose now, from the store's own count of what the server hasn't accepted.
    private func currentEraseWarning() async -> EraseWarning? {
        guard let store else { return nil }
        let unsent = try? await store.unsentItemCount()
        guard connection != nil else {
            return nothingWritten ? .nothingWritten : .notSyncing
        }
        let host = connectionHost
        let healthy =
            syncHealth == nil && !syncFailed && !encryption.turnedOnElsewhere && syncActivity.lastSynced != nil
        guard healthy, let unsent else { return .unconfirmed(host: host) }
        return unsent > 0 ? .unsent(count: unsent, host: host) : .onServer(host: host)
    }

    /// Erases this device's journals and settings and returns to the first-launch screen (§5). `shown` is what the
    /// person was warned about. Nothing is removed unless the configuration moves; once it has, the rest follows,
    /// and what can't be finished now is finished at the next launch.
    func eraseLibrary(shown: EraseWarning) async -> EraseOutcome {
        guard !locked, configuration != nil, store != nil, eraseBlock == nil else { return .cancelled }
        if appLockOn {
            guard await authenticateToErase() else { return .cancelled }
        }
        // Pause: nothing writes to the library or syncs it from here on.
        vaultReplacement = true
        _ = await flush()
        guard let configuration, store != nil, !locked, let warning = await currentEraseWarning() else {
            vaultReplacement = false
            return .cancelled
        }
        guard warning.isCovered(by: shown) else {
            vaultReplacement = false
            return .changed(warning)
        }
        let list = erasureList(configuration)
        let folder: URL
        do { folder = try LocalErasure.commit(list, in: directory) } catch {
            vaultReplacement = false
            Logger(subsystem: "org.privatejournal", category: "erase").error("The erase couldn't start.")
            return .failed
        }
        await finishErasing(list: list, folder: folder)
        return .erased
    }

    /// The device's own authentication when App Lock is on, as turning App Lock off asks for it.
    private func authenticateToErase() async -> Bool {
        refreshDeviceOwnerAvailability()
        let lockCount = unlockState.lockCount
        unlockState.authenticating = true
        let outcome = await deviceOwner.authenticate(
            reason: Self.authenticationReason("Erase journals on this device"))
        unlockState.authenticating = false
        guard !locked, lockCount == unlockState.lockCount else { return false }
        switch outcome {
        case .success, .noPasscode: return true
        case .cancelled, .failed: return false
        }
    }

    /// After the commit: the Keychain items go first, then the library's files move aside before the first-launch
    /// screen can start a new library; the deletion and the sign-out continue in the background.
    private func finishErasing(list: ErasureList, folder: URL) async {
        let keysRemoved = LocalErasure.removeAccounts(list, protected: [])
        let previousStore = store
        let previousConnection = connection
        erasingLibrary = true
        clearErasedLibrary()
        try? await previousStore?.close()
        LocalErasure.moveListed(list, from: directory, into: folder, protected: [])
        UserDefaults.standard.removeObject(forKey: MarkdownShortcuts.settingKey)
        erasingLibrary = false
        Task.detached(priority: .utility) {
            LocalErasure.delete(folder, list: list, keysRemoved: keysRemoved)
        }
        if let previousConnection {
            // Best effort, with the token only this request still holds (§4.1).
            Task {
                try? await ServerClient(address: previousConnection.address, token: previousConnection.token)
                    .revoke(previousConnection.deviceID)
            }
        }
    }

    /// Everything the configuration names, with the older path-derived names, earlier copies, an unfinished
    /// encryption copy and leftovers of imports and exports, fixed before the commit (§3).
    func erasureList(_ configuration: LocalConfiguration) -> ErasureList {
        var list = ErasureList()
        let legacyFiles = ["journal.sqlite", "journal.sqlite-wal", "journal.sqlite-shm", "attachments"]
        list.names += configuration.storageFolder.map { [$0] } ?? legacyFiles
        list.accounts += [
            configuration.keyID ?? keyAccount, configuration.connectionKeyID ?? keyAccount + "-connection",
            keyAccount, keyAccount + "-connection",
        ]
        for library in configuration.supersededLibraries ?? [] {
            list.names += library.storageFolder.map { [$0] } ?? legacyFiles
            list.accounts += [library.keyID, library.connectionKeyID].compactMap { $0 }
        }
        if let upgrade = configuration.encryptionUpgrade {
            list.names.append(upgrade.storageFolder)
            list.accounts.append(upgrade.keyID)
        }
        let manager = FileManager.default
        let contents = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
        list.names += contents.filter { $0.hasPrefix("import-") || ArchiveExportLeftovers.isStagedExport($0) }.sorted()
        let temporary = manager.temporaryDirectory
        list.temporaryFiles =
            ((try? manager.contentsOfDirectory(atPath: temporary.path)) ?? []).filter(
                ArchiveExportLeftovers.isDialogCopy
            )
            .sorted().map { temporary.appendingPathComponent($0) }
        list.names = Array(Set(list.names.filter(LocalErasure.isMovable))).sorted()
        list.accounts = Array(Set(list.accounts)).sorted()
        return list
    }

    /// Finishes an erase an earlier run left, before the configuration is read (§5, step 7). The current library's
    /// files and Keychain items are never touched.
    func finishEarlierErasures() {
        let current = (try? Data(contentsOf: directory.appendingPathComponent(LocalErasure.configurationName)))
            .flatMap { try? JournalCoding.decoder().decode(LocalConfiguration.self, from: $0) }
        var accounts: Set<String> = []
        var names: Set<String> = []
        if let current {
            let inUse = erasureList(current)
            accounts = Set(inUse.accounts)
            names = Set(inUse.names)
        }
        let leftovers = LocalErasure.leftovers(in: directory, protectedAccounts: accounts, protectedNames: names)
        for leftover in leftovers {
            Task.detached(priority: .utility) {
                LocalErasure.delete(leftover.folder, list: leftover.list, keysRemoved: leftover.keysRemoved)
            }
        }
    }
}
