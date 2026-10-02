import Foundation
import JournalCore

/// End-to-end restore check, driven by scripts/test-sync.sh around a real server:
/// restore-before (sync, then the script backs up), restore-after (more edits the backup lacks; the script
/// stops the server and restores the backup), restore-verify (old credential is revoked; a reconnected
/// copy of the same library re-uploads what the server lost and a new device receives everything).
extension Probe {
    private struct RestoreState: Codable {
        var phrase: String
        var key: Data
        var token: String
        var protection: String
        var firstEntry: UUID
        var secondEntry: UUID?
        var firstImage: UUID
        var secondImage: UUID?
        /// A journal, with an entry, deleted permanently after the backup: restoring must not bring it back.
        var purgedJournal: UUID?
        var purgedEntry: UUID?
    }
    /// Runs `restore-before <URL> <setup-code file> <state>`, `restore-after <URL> <state>` or
    /// `restore-verify <URL> <state>` when requested.
    static func runRestorePhase() async throws -> Bool {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard [3, 4].contains(arguments.count), arguments[0].hasPrefix("restore-") else { return false }
        try await restoreProbe(arguments)
        return true
    }
    private static func restoreProbe(_ arguments: [String]) async throws {
        let stateDirectory = URL(fileURLWithPath: arguments[arguments.count - 1])
        let stateURL = stateDirectory.appendingPathComponent("state.json")
        switch arguments[0] {
        case "restore-before":
            try await restoreBefore(address: arguments[1], setupCodeFile: arguments[2], state: stateDirectory)
        case "restore-after":
            var state = try JournalCoding.decoder().decode(RestoreState.self, from: Data(contentsOf: stateURL))
            try await restoreAfter(address: arguments[1], state: &state, directory: stateDirectory)
            try JournalCoding.encoder().encode(state).write(to: stateURL)
        case "restore-verify":
            let state = try JournalCoding.decoder().decode(RestoreState.self, from: Data(contentsOf: stateURL))
            try await restoreVerify(address: arguments[1], state: state, directory: stateDirectory)
        default: fatalError("Unknown restore phase")
        }
    }
    private static func document(_ text: String, image: UUID) -> JournalDocument {
        .init(blocks: [
            DocumentBlock(runs: [TextRun(text)]),
            DocumentBlock(kind: "image", attachmentID: image, imageDescription: "Earlier", mediaType: "image/png"),
        ])
    }
    private static func openStore(_ state: RestoreState, _ directory: URL) throws -> JournalStore {
        try JournalStore(
            directory: directory, key: state.key,
            protection: ContentProtection(rawValue: state.protection) ?? .encrypted)
    }
    private static func restoreBefore(address: String, setupCodeFile: String, state directory: URL) async throws {
        let code = try String(contentsOfFile: setupCodeFile).trimmingCharacters(in: .whitespacesAndNewlines)
        let (master, phrase, envelope, secret) = try recoveryFixture()
        guard envelope.requiresPassword else {
            throw ProbeFailure("the restore probe needs a password-protected recovery version (1, 2 or 3)")
        }
        let grant = try await ServerClient(address: address).initialize(
            code: code, envelope: envelope, recoverySecret: secret, deviceName: "Restore Mac")
        let protection = try envelope.contentProtection
        let store = try JournalStore(
            directory: directory.appendingPathComponent("mac"), key: master, protection: protection)
        let journal = JournalItem(kind: "journal", title: "Restored work")
        try await store.save(journal)
        let image = try await store.addAttachment(Data(repeating: 3, count: 2048))
        let entry = JournalItem(
            kind: "entry", journalID: journal.id, title: "Edited", document: document("Before backup", image: image))
        try await store.save(entry)
        let purged = JournalItem(kind: "journal", title: "Deleted after the backup")
        let purgedEntry = JournalItem(kind: "entry", journalID: purged.id, title: "Gone for good")
        try await store.save(purged)
        try await store.save(purgedEntry)
        try await SyncEngine(store: store, client: ServerClient(address: address, token: grant.token)).synchronize()
        let state = RestoreState(
            phrase: phrase, key: master, token: grant.token, protection: protection.rawValue, firstEntry: entry.id,
            firstImage: image, purgedJournal: purged.id, purgedEntry: purgedEntry.id)
        try JournalCoding.encoder().encode(state).write(to: directory.appendingPathComponent("state.json"))
        print("PASS: restore probe synchronized before the backup")
    }
    private static func restoreAfter(address: String, state: inout RestoreState, directory: URL) async throws {
        let store = try openStore(state, directory.appendingPathComponent("mac"))
        guard var entry = try await store.item(state.firstEntry), let journalID = entry.journalID else {
            throw ProbeFailure("the entry written before the backup is missing or has no journal")
        }
        entry.document = document("After backup", image: state.firstImage)
        try await store.save(entry)
        let image = try await store.addAttachment(Data(repeating: 4, count: 2048))
        let second = JournalItem(
            kind: "entry", journalID: journalID, title: "Written after the backup",
            document: .init(blocks: [
                DocumentBlock(runs: [TextRun("Created after backup")]),
                DocumentBlock(kind: "image", attachmentID: image, imageDescription: "Later", mediaType: "image/png"),
            ]))
        try await store.save(second)
        if let purged = state.purgedJournal {
            _ = try await store.deleteJournal(store.prepareJournalDeletion(purged))
            try await store.permanentlyDelete(store.preparePermanentDeletion(purged))
        }
        try await SyncEngine(store: store, client: ServerClient(address: address, token: state.token)).synchronize()
        state.secondEntry = second.id
        state.secondImage = image
        print("PASS: restore probe wrote changes the backup doesn't contain")
    }
    private static func restoreVerify(address: String, state: RestoreState, directory: URL) async throws {
        let anonymous = try ServerClient(address: address)
        let store = try openStore(state, directory.appendingPathComponent("mac"))
        do {
            try await SyncEngine(store: store, client: ServerClient(address: address, token: state.token))
                .synchronize()
            throw ProbeFailure("the device signed out by the restore could still sync")
        } catch let failure as SyncFailure where failure.health == .serverReplaced {}
        print("PASS: restoring signed out the previously approved device")
        let parameters = try await anonymous.recoveryParameters()
        // As the app does when reconnecting: a copy of the same library with a new device credential.
        let reconnected = directory.appendingPathComponent("reconnected")
        try await store.snapshot(to: reconnected)
        let copy = try openStore(state, reconnected)
        let grant = try await anonymous.recoverVault(
            state.phrase, parameters: parameters, deviceName: "Reconnected Mac"
        ).grant
        try await SyncEngine(store: copy, client: ServerClient(address: address, token: grant.token)).synchronize()
        let conflicts = try await copy.conflicts()
        let pending = try await copy.pending()
        guard conflicts.isEmpty, pending.isEmpty else {
            throw ProbeFailure("the reconnected copy has conflicts or unsent changes after the restore")
        }
        let fresh = try openStore(state, directory.appendingPathComponent("fresh"))
        let freshGrant = try await anonymous.recoverVault(
            state.phrase, parameters: parameters, deviceName: "New iPhone"
        ).grant
        try await SyncEngine(store: fresh, client: ServerClient(address: address, token: freshGrant.token))
            .synchronize()
        guard let secondEntry = state.secondEntry, let secondImage = state.secondImage,
            try await fresh.item(state.firstEntry)?.document.text.contains("After backup") == true,
            try await fresh.item(secondEntry)?.title == "Written after the backup",
            try await fresh.attachment(state.firstImage) == Data(repeating: 3, count: 2048),
            try await fresh.attachment(secondImage) == Data(repeating: 4, count: 2048)
        else { throw ProbeFailure("a new device did not receive every edit and image after the restore") }
        print("PASS: after restoring an older backup, a reconnected device restored every later edit and image")
        let items = try await fresh.items()
        guard let purged = state.purgedJournal, let purgedEntry = state.purgedEntry,
            items.first(where: { $0.id == purged })?.isPermanentlyDeleted == true,
            items.first(where: { $0.id == purgedEntry })?.isPermanentlyDeleted == true,
            !items.contains(where: { JournalNames.isListed($0) && $0.title == "Deleted after the backup" })
        else { throw ProbeFailure("a journal deleted permanently after the backup came back after the restore") }
        print("PASS: a journal deleted permanently after the backup stays deleted once the restored server is re-read")
    }
}
