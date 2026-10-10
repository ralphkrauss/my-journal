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
    /// The journals can't be opened, so nothing can be exported first (docs/design/build-18-fixes-2026-10-06.md
    /// §2.1). `credential` names what opening them needs when the device key is missing; `host` is the server the
    /// saved connection names, when that item could be read. Absence of the item proves nothing: after restoring an
    /// iPhone from a backup it is gone though the library synced.
    case unopened(credential: String?, host: String?)

    /// Whether erasing loses journals that exist only on this device, so an archive is offered first.
    var losesJournals: Bool {
        switch self {
        case .onServer, .nothingWritten, .unopened: return false
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
        if replacingVault || connectingToServer || deleteAllPhase != .idle || saveFailure || erasingLibrary {
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
            syncHealth == nil && !syncFailed && syncActivity.lastSynced != nil
        guard healthy, let unsent else { return .unconfirmed(host: host) }
        return unsent > 0 ? .unsent(count: unsent, host: host) : .onServer(host: host)
    }

    /// Erases this device's journals and settings and returns to the first-launch screen (§5). `shown` is what the
    /// person was warned about. Nothing is removed unless the configuration moves; once it has, the rest follows,
    /// and what can't be finished now is finished at the next launch.
    func eraseLibrary(shown: EraseWarning) async -> EraseOutcome {
        guard !locked, configuration != nil, store != nil, eraseBlock == nil else { return .cancelled }
        if appLockOn {
            guard await authenticateDeviceOwner(reason: "Erase journals on this device") else { return .cancelled }
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
        await finishErasing(list: list, folder: folder, signingOutOf: connection)
        return .erased
    }

    /// The warning for erasing journals that can't be opened, after the device's authentication when App Lock is on or
    /// can't be known; nil when cancelled or when there is nothing to erase from here.
    func unopenedEraseWarning() async -> EraseWarning? {
        guard store == nil, let problem = libraryProblem, problem.allowsErase, eraseBlock == nil else { return nil }
        if removalNeedsAuthentication {
            guard await authenticateDeviceOwner(reason: "Erase journals on this device") else { return nil }
        }
        guard store == nil, libraryProblem == problem else { return nil }
        let credential = problem == .needsKey ? configuration?.credentialName : nil
        return .unopened(credential: credential, host: savedConnection().map { ServerAddress.host($0.address) })
    }

    /// Erases what can't be opened. Nothing is read: the configuration moves as it is (a file that doesn't decode
    /// leaves the same way), and everything else the app stored goes with it by the list built first. The alert's
    /// Erase doesn't ask for authentication again.
    func eraseUnopenedLibrary() async -> EraseOutcome {
        guard store == nil, libraryProblem?.allowsErase == true, eraseBlock == nil else { return .cancelled }
        // Read before the keys go: the sign-out needs the token only the connection item holds.
        let previousConnection = savedConnection()
        let list = erasureList(configuration)
        let folder: URL
        do { folder = try LocalErasure.commit(list, in: directory) } catch {
            Logger(subsystem: "org.privatejournal", category: "erase").error("The erase couldn't start.")
            return .failed
        }
        await finishErasing(list: list, folder: folder, signingOutOf: previousConnection)
        return .erased
    }

    /// The connection the Keychain holds for the library the settings name, read independently of the store. Nil when
    /// the settings can't be read, the item is absent or it doesn't decode.
    private func savedConnection() -> SyncConnection? {
        guard let configuration else { return nil }
        let account = configuration.connectionKeyID ?? keyAccount + "-connection"
        guard let data = try? Keychain.read(account) else { return nil }
        return try? JournalCoding.decoder().decode(SyncConnection.self, from: data)
    }

    /// After the commit: the Keychain items go first, then the library's files move aside before the first-launch
    /// screen can start a new library; the deletion and the sign-out continue in the background.
    private func finishErasing(list: ErasureList, folder: URL, signingOutOf previousConnection: SyncConnection?) async {
        let keysRemoved = LocalErasure.removeAccounts(list, protected: [])
        let previousStore = store
        erasingLibrary = true
        clearErasedLibrary()
        try? await previousStore?.close()
        LocalErasure.moveListed(list, from: directory, into: folder, protected: [])
        preferences.removeObject(forKey: MarkdownShortcuts.settingKey)
        preferences.removeObject(forKey: ReviewUsageStore.defaultsKey)
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

    /// What the library uses, from the configuration's own names only: its folder and Keychain accounts, with the older
    /// path-derived names and earlier copies. This is what finishing an earlier erase
    /// protects; it is never the sweeping list, which would protect everything.
    func libraryNames(_ configuration: LocalConfiguration) -> ErasureList {
        var list = ErasureList()
        list.names += configuration.storageFolder.map { [$0] } ?? Self.legacyLibraryFiles
        list.accounts += [
            configuration.keyID ?? keyAccount, configuration.connectionKeyID ?? keyAccount + "-connection",
            keyAccount, keyAccount + "-connection",
        ]
        for library in configuration.supersededLibraries ?? [] {
            list.names += library.storageFolder.map { [$0] } ?? Self.legacyLibraryFiles
            list.accounts += [library.keyID, library.connectionKeyID].compactMap { $0 }
        }
        list.names = Array(Set(list.names.filter(LocalErasure.isMovable))).sorted()
        list.accounts = Array(Set(list.accounts)).sorted()
        return list
    }

    private static let legacyLibraryFiles = [
        "journal.sqlite", "journal.sqlite-wal", "journal.sqlite-shm", "attachments",
    ]

    /// Everything Erase removes, fixed before the commit and whether or not a configuration can be read: what the
    /// library names, every entry of the data folder the app can move (copies, imports, exports and anything else it
    /// left) and, in the app's own data folder, every Keychain item of its service (docs/design/build-18-fixes-2026-
    /// 10-06.md §2.1). A listing that fails is logged and Erase goes on with the names it can derive.
    func erasureList(_ configuration: LocalConfiguration?) -> ErasureList {
        var list = configuration.map(libraryNames) ?? ErasureList()
        list.accounts += [keyAccount, keyAccount + "-connection"]
        let manager = FileManager.default
        list.names += ((try? manager.contentsOfDirectory(atPath: directory.path)) ?? []).filter(LocalErasure.isMovable)
        let temporary = manager.temporaryDirectory
        list.temporaryFiles =
            ((try? manager.contentsOfDirectory(atPath: temporary.path)) ?? []).filter {
                ArchiveExportLeftovers.isDialogCopy($0) || ArchiveExportLeftovers.isSnapshotDatabase($0)
            }
            .sorted().map { temporary.appendingPathComponent($0) }
        if sweepsKeychain { list.accounts += sweptKeychainAccounts() }
        list.names = Array(Set(list.names.filter(LocalErasure.isMovable))).sorted()
        list.accounts = Array(Set(list.accounts)).sorted()
        return list
    }

    /// The service's accounts that this erase removes. On the Mac only those of this data folder, and the legacy agent
    /// ones: development and preview copies share the team's keychain group. On iPhone and iPad all of them, because
    /// the container path, and so the folder's hash, changes after a reinstall and the orphans of earlier installs are
    /// what the sweep is for.
    private func sweptKeychainAccounts() -> [String] {
        let listed: [String]
        do { listed = try keychainListing() } catch {
            let failure = error as NSError
            Logger(subsystem: "org.privatejournal", category: "erase").error(
                "The Keychain couldn’t be listed: \(failure.domain, privacy: .private) \(failure.code, privacy: .private)."
            )
            return []
        }
        #if os(macOS)
            let own = keyAccount
            return listed.filter { $0.hasPrefix(own) || $0.hasPrefix("agent-") }
        #else
            return listed
        #endif
    }

    /// Finishes an erase an earlier run left, before the configuration is read (§5, step 7). The current library's
    /// files and Keychain items are never touched, and nothing is finished while the configuration exists but can't be
    /// read: what the library uses can't be told then.
    func finishEarlierErasures() {
        var inUse = ErasureList()
        let configurationFile = directory.appendingPathComponent(LocalErasure.configurationName)
        if FileManager.default.fileExists(atPath: configurationFile.path) {
            guard let data = try? Data(contentsOf: configurationFile),
                let current = try? JournalCoding.decoder().decode(LocalConfiguration.self, from: data)
            else { return }
            inUse = libraryNames(current)
        }
        let leftovers = LocalErasure.leftovers(
            in: directory, protectedAccounts: Set(inUse.accounts), protectedNames: Set(inUse.names))
        for leftover in leftovers {
            Task.detached(priority: .utility) {
                LocalErasure.delete(leftover.folder, list: leftover.list, keysRemoved: leftover.keysRemoved)
            }
        }
    }
}
