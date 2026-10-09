import Foundation
import JournalCore

/// The library an archive install makes current: its key, the configuration that names it, and whether it is a new
/// library (not an open one that took the journals as new ones).
private struct InstalledLibrary {
    var store: JournalStore
    var key: Data
    var configuration: LocalConfiguration
    var isNew: Bool
}

/// What an archive install has made and not yet handed over, removed if the install doesn't finish.
private struct StagedInstall {
    var directory: URL?
    var store: JournalStore?
    var account: String?

    func discard() async {
        if let store { try? await store.close() }
        if let directory { try? FileManager.default.removeItem(at: directory) }
        if let account { try? Keychain.remove(account) }
    }
}

extension AppModel {
    /// Makes the archive's journals this library's: added as new journals to the one that is open, or, when none can
    /// be opened, in place of the journals that can't (docs/design/build-18-fixes-2026-10-06.md §2.1). The archive
    /// was read and checked before; replacing the unopened library records it as superseded, keeps App Lock and asks
    /// for the device's authentication when App Lock is on.
    func installArchive(_ restored: VaultArchive.Restored) async throws {
        try checkArchiveCanBeInstalled()
        guard await finishPendingSave() else {
            throw JournalError.saveRequired
        }
        try Task.checkCancellation()
        try checkArchiveCanBeInstalled()
        if store == nil, configuration != nil, appLockOn {
            guard await authenticateDeviceOwner(reason: "Restore journals on this device") else {
                throw CancellationError()
            }
            try checkArchiveCanBeInstalled()
        }
        vaultReplacement = true
        defer { vaultReplacement = false }
        var staged = StagedInstall()
        do {
            try await install(restored, staging: &staged)
        } catch {
            await staged.discard()
            throw error
        }
    }

    /// Refused while the settings couldn't be read or a newer version wrote the journals, and while locked, except for
    /// the lock screen of a missing device key, which offers it.
    private func checkArchiveCanBeInstalled() throws {
        if let problem = libraryProblem, !problem.offersImport { throw LibraryNotOpenError() }
        guard !replacingVault, !retryingOpen, !locked || libraryProblem == .needsKey else {
            throw JournalError.locked
        }
    }

    private func install(_ restored: VaultArchive.Restored, staging staged: inout StagedInstall) async throws {
        let library = try await libraryToInstall(restored, staging: &staged)
        try Task.checkCancellation()
        guard !locked || libraryProblem == .needsKey else { throw JournalError.locked }
        let account = keyAccount + "-" + UUID().uuidString.lowercased()
        staged.account = account
        try Keychain.write(library.key, account: account)
        var next = library.configuration
        next.keyID = account
        // A library built new names its connection item, as `start` does, never the path-derived name that can
        // belong to another library.
        if library.isNew { next.connectionKeyID = account + "-connection" }
        let previous = configuration
        configuration = next
        do { try persistRestoredConfiguration() } catch {
            configuration = previous
            throw error
        }
        // Ownership transfers only after the configuration pointer is durably committed.
        staged = StagedInstall()
        await open(library.store, key: library.key)
    }

    /// The library the archive becomes and the key it uses, with the configuration that names it. An open library keeps
    /// its connection and settings and takes the journals as new ones; otherwise the archive's own library replaces
    /// whatever the configuration named, which it keeps App Lock from.
    private func libraryToInstall(_ restored: VaultArchive.Restored, staging staged: inout StagedInstall) async throws
        -> InstalledLibrary
    {
        if let store, let configuration, let masterKey {
            let folder = "vault-" + UUID().uuidString.lowercased()
            let path = directory.appendingPathComponent(folder)
            guard !FileManager.default.fileExists(atPath: path.path) else { throw JournalError.invalidData }
            staged.directory = path
            try await store.snapshot(to: path)
            let destination = try JournalStore(
                directory: path, key: masterKey, protection: configuration.recovery.contentProtection)
            staged.store = destination
            try await destination.importAsNewJournals(from: restored.store)
            var next = configuration
            next.storageFolder = folder
            next.supersededLibraries = librariesSuperseded(by: configuration)
            return InstalledLibrary(store: destination, key: masterKey, configuration: next, isNew: false)
        }
        // Opening the archive needed its password.
        var next = LocalConfiguration(
            recovery: restored.recovery, recoveryConfirmed: true,
            storageFolder: await restored.store.directory.lastPathComponent,
            passwordChecked: restored.recovery.formatVersion == 2 ? true : nil)
        if let unopened = configuration {
            next.appLock = unopened.appLock
            next.inactivityLockMinutes = unopened.inactivityLockMinutes
            next.supersededLibraries = librariesSuperseded(by: unopened, includingEncryptionCopy: true)
        }
        return InstalledLibrary(store: restored.store, key: restored.key, configuration: next, isNew: true)
    }

    /// Opens the installed library in place of what was there, and shows it.
    private func open(_ destination: JournalStore, key: Data) async {
        let wasLocked = libraryProblem == .needsKey
        masterKey = key
        let replaced = store
        store = destination
        setLibraryProblem(nil)
        failedRetries = 0
        error = nil
        if wasLocked {
            locked = false
            unlockState.promptPending = false
        }
        configureSync()
        selectedID = nil
        draft = nil
        selectedJournalID = nil
        items = []
        imageLoader.clear()
        // The configuration pointer already committed the import. A display failure must not invite reimport.
        do {
            try await refresh()
            selectInitialEntry()
        } catch {
            self.error = "Your journals were imported, but couldn’t be displayed. Reopen My Journal to try again."
        }
        try? await replaced?.close()
    }
}
