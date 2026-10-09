import JournalCore
import XCTest

@testable import Journal

/// Libraries as earlier versions made them. Version 1.1 creates only encrypted libraries, so the unencrypted ones that
/// tests still need (unencrypted libraries persist for 1.0 holders until Not Now is removed) are made here, with the
/// same steps `AppModel.start` takes.
@MainActor
extension AppModel {
    static let testPassword = "a test master password"

    /// A new encrypted library with a password of this test's own.
    func start() async { await start(password: Self.testPassword) }

    /// `encrypted: false` makes the library 1.0's "Continue Without Encryption" made (format 4), as a library whose
    /// person chose Not Now: the paths that stay while Not Now exists (sync with its server, Markdown export) behave as
    /// they did. An archive of it can't be written: a file archive holds only encrypted libraries. Otherwise a master
    /// password library.
    func start(encrypted: Bool) async { await start(password: nil, encrypted: encrypted) }

    func start(password: String?, encrypted: Bool) async {
        if encrypted {
            await start(password: password ?? Self.testPassword)
        } else {
            await startLegacyUnencrypted()
            encryption.notNow()
        }
    }

    /// A format 4 library: the journals are not encrypted, and no password opens them.
    func startLegacyUnencrypted() async {
        guard configuration == nil, libraryProblem == nil else { return }
        var staged: JournalStore?
        let folder = "vault-" + UUID().uuidString.lowercased()
        let path = directory.appendingPathComponent(folder)
        do {
            let key = try VaultCrypto.generateKey()
            let store = try JournalStore(directory: path, key: key, protection: .plaintext)
            staged = store
            let journal = JournalItem(kind: "journal", title: "Default")
            try await store.save(journal)
            let account = "master-" + UUID().uuidString.lowercased()
            try Keychain.write(key, account: account)
            configuration = LocalConfiguration(
                recovery: .unprotected, recoveryConfirmed: true, storageFolder: folder, keyID: account,
                connectionKeyID: account + "-connection")
            do { try persistConfiguration() } catch {
                configuration = nil
                try? Keychain.remove(account)
                throw error
            }
            masterKey = key
            self.store = store
            selectedJournalID = journal.id
            try await refresh()
        } catch {
            if configuration == nil {
                try? await staged?.close()
                try? FileManager.default.removeItem(at: path)
            }
            self.error = error.shown(.saving)
        }
    }
}
