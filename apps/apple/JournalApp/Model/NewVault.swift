import Foundation
import JournalCore

struct NewVault: Sendable {
    let store: JournalStore
    let key: Data
    let recovery: RecoveryEnvelope
    let journalID: UUID
    let legacyPhrase: String?
    let folder: String

    static func prepare(in directory: URL, password: String?, encrypted: Bool) async throws -> NewVault {
        if encrypted, let password, password.count < VaultCrypto.minimumPasswordLength {
            throw JournalError.server("Enter a master password.")
        }
        let key = try VaultCrypto.generateKey()
        let phrase = encrypted ? try password ?? VaultCrypto.recoveryPhrase() : ""
        let version = password == nil ? 1 : (encrypted ? 2 : 3)
        let envelope = try await Task.detached {
            encrypted
                ? try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase, formatVersion: version).0 : .unprotected
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
            return NewVault(
                store: storage, key: key, recovery: envelope, journalID: journal.id,
                legacyPhrase: encrypted && password == nil ? phrase : nil, folder: folder)
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
