import Foundation
import JournalCore
import os

/// Opening the library the configuration names at launch and on Try Again (docs/design/build-18-fixes-2026-10-06.md
/// §2.1). Whatever fails ends in a problem the person can act on, never in an alert over a store that is half open,
/// and opening never repairs: a damaged database is left as it is.
extension AppModel {
    func load() async {
        guard !loaded else { return }
        defer { loaded = true }
        await openSavedLibrary()
    }

    /// Reads the configuration, runs the cleanups that need no store, and opens the library it names. A missing file
    /// is a first launch; a file that exists but can't be read is a problem of its own, never a first launch.
    func openSavedLibrary() async {
        // An erase an earlier run didn't finish is finished before anything is read (EraseOperations.swift). It is
        // skipped while the configuration exists but can't be read, because it couldn't tell what to protect.
        finishEarlierErasures()
        guard FileManager.default.fileExists(atPath: configURL.path) else { return }
        do {
            configuration = try JournalCoding.decoder().decode(
                LocalConfiguration.self, from: Data(contentsOf: configURL))
        } catch {
            configuration = nil
            setLibraryProblem(.settingsUnread)
            Logger(subsystem: "org.privatejournal", category: "library").error("The settings couldn’t be read.")
            return
        }
        // Before anything is shown: App Lock's PIN becomes the device's own authentication.
        retireAppLockPIN()
        // A copy staged by a connection that the app quit during is never used.
        removeAbandonedCopies()
        // A copy made while turning on encryption that the server never saw is removed.
        discardUnsentEncryptionCopy()
        await openConfiguredLibrary()
    }

    private func openConfiguredLibrary() async {
        do {
            let account = configuration?.keyID ?? keyAccount
            var savedKey = try Keychain.read(account)
            if savedKey == nil && configuration?.requiresPassword == false {
                savedKey = try VaultCrypto.generateKey()
                if let savedKey { try Keychain.write(savedKey, account: account) }
            }
            if savedKey != nil { rememberKeyAccount(account) }
            guard let key = savedKey else {
                lockForMissingDeviceKey()
                return
            }
            masterKey = key
            try await openLibrary(key: key, protection: configuration?.recovery.contentProtection ?? .encrypted)
        } catch {
            await failOpening(error)
            return
        }
        setLibraryProblem(nil)
        await finishOpening()
    }

    /// Once the library is open: a server that switched to encryption meanwhile is waited for, App Lock locks the
    /// journals, and otherwise they are read, which is also the first read that can fail (`refresh`).
    private func finishOpening() async {
        do {
            // The server may have switched to encryption while the app last ran; writing waits until that's known.
            if encryptionUnfinished {
                pauseWriting(true)
                encryption.finishAfterLaunch()
            } else {
                await numberDuplicateJournalsWithoutServer()
            }
            locked = appLockOn
            unlockState.promptPending = locked
            if !locked {
                if configuration?.recoveryConfirmed == false { try await replaceUnconfirmedRecoveryKey() }
                try await refresh()
                selectInitialEntry(reveal: true)
            }
        } catch { report(error, .reading) }
    }

    /// Journals an earlier version named alike get numbers each time a library without a server opens
    /// (docs/design/journal-name-uniqueness.md §4.6); a connected library does this after synchronizing.
    func numberDuplicateJournalsWithoutServer() async {
        guard connection == nil, let store else { return }
        do { try await store.numberDuplicateJournals() } catch {
            Logger(subsystem: "org.privatejournal", category: "journals").error(
                "Could not number journals that share a name.")
        }
    }

    /// Opens the store with the device key and resumes the saved server connection. Loading and recovering a
    /// missing device key both use it, so either way the library is ready to sync. The store and the connection are
    /// assigned only when everything succeeded; a store that opened before the connection failed is closed first,
    /// so Try Again can never overlap an open handle on the same file.
    func openLibrary(key: Data, protection: ContentProtection) async throws {
        let folder = configuration?.storageFolder.map { directory.appendingPathComponent($0) } ?? directory
        // Opening never creates a library: a restore or cleanup that left the settings naming a folder that is gone
        // would otherwise give an empty library, which sync then uploads.
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("journal.sqlite").path) else {
            throw LibraryDatabaseMissing()
        }
        let opened = try JournalStore(directory: folder, key: key, protection: protection)
        let connectionAccount = configuration?.connectionKeyID ?? keyAccount + "-connection"
        let saved: SyncConnection?
        do {
            saved = try Keychain.read(connectionAccount).map {
                try JournalCoding.decoder().decode(SyncConnection.self, from: $0)
            }
        } catch {
            try? await opened.close()
            throw error
        }
        store = opened
        firstReadPending = true
        connection = saved
        if saved != nil, configuration?.connectionKeyID == nil {
            configuration?.connectionKeyID = connectionAccount
            saveMigratedConfiguration()
        }
        #if os(macOS)
            retireFormerMacServer()
        #endif
        configureSync()
    }
}
