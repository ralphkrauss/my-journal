import Foundation
import JournalCore

struct NewVault: Sendable {
    let store: JournalStore
    let key: Data
    let recovery: RecoveryEnvelope
    let journalID: UUID
    let folder: String

    /// A new library is always encrypted, with a master password the person chose (docs/design/
    /// 1-1-encryption-and-passwords.md §3.3). Libraries without encryption exist only from earlier versions.
    static func prepare(in directory: URL, password: String) async throws -> NewVault {
        guard password.count >= VaultCrypto.minimumPasswordLength else {
            throw JournalError.server("Enter a master password.")
        }
        let key = try VaultCrypto.generateKey()
        let envelope = try await Task.detached {
            try VaultCrypto.makeRecovery(masterKey: key, phrase: password, formatVersion: 2).0
        }.value
        let folder = "vault-" + UUID().uuidString.lowercased()
        let path = directory.appendingPathComponent(folder)
        var staged: JournalStore?
        do {
            let storage = try JournalStore(directory: path, key: key, protection: envelope.contentProtection)
            staged = storage
            let journal = JournalItem(kind: "journal", title: "Default")
            // No templates: a new library has only what the person makes (no-built-in-templates-2026-10-04.md).
            try await storage.save(journal)
            // Nothing an earlier version left can be in a library that is just being made.
            try await storage.recordOpeningPassWhenThereAreNoConflicts()
            return NewVault(store: storage, key: key, recovery: envelope, journalID: journal.id, folder: folder)
        } catch {
            try? await staged?.close()
            try? FileManager.default.removeItem(at: path)
            throw error
        }
    }
    func discard() async {
        try? await store.close()
        let directory = await store.directory
        try? FileManager.default.removeItem(at: directory)
    }
}
