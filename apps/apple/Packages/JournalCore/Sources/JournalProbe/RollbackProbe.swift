import Foundation
import JournalCore

/// End-to-end check of a server whose data folder is replaced by an older copy without a new identity, driven by
/// scripts/test-sync.sh around a real server (protocol/README.md, capability `sync-continuity-digest`). The phone's
/// accepted edits are lost by the copy, and the Mac's edits of the same entries then get the same positions, record
/// and revision numbers. The phone must keep both versions, the Mac's as an entry of its own, instead of writing over
/// the Mac's:
/// - rollback-setup: both devices synchronize three entries; the script copies the server's data folder;
/// - rollback-unsent: the phone sends an edit without reading on, then edits again; the script restores the copy;
/// - rollback-check-unsent: the Mac edits the same entry; the phone synchronizes; the script copies the data again;
/// - rollback-read: the phone sends two edits and reads past them, then edits one again; the script restores it;
/// - rollback-check-read: the Mac edits both entries; the phone synchronizes.
extension Probe {
    private struct RollbackState: Codable {
        var phrase: String
        var secret: String
        var key: Data
        var phoneToken: String
        var macToken: String
        var entries: [UUID]
    }
    /// Runs `rollback-setup <URL> <setup-code file> <state>` or `rollback-<phase> <URL> <state>` when requested.
    static func runRollbackPhase() async throws -> Bool {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard [3, 4].contains(arguments.count), arguments[0].hasPrefix("rollback-") else { return false }
        let directory = URL(fileURLWithPath: arguments[arguments.count - 1])
        if arguments[0] == "rollback-setup" {
            try await rollbackSetup(address: arguments[1], setupCodeFile: arguments[2], directory: directory)
            return true
        }
        let state = try JournalCoding.decoder().decode(
            RollbackState.self, from: Data(contentsOf: directory.appendingPathComponent("state.json")))
        let phone = try rollbackDevice("phone", state: state, address: arguments[1], directory: directory)
        let mac = try rollbackDevice("mac", state: state, address: arguments[1], directory: directory)
        switch arguments[0] {
        case "rollback-unsent": try await rollbackUnsent(phone, state: state)
        case "rollback-check-unsent":
            try await rollbackCheck(
                phone: phone, mac: mac, entries: [state.entries[2]], phase: "sent without reading on")
        case "rollback-read": try await rollbackRead(phone, state: state)
        case "rollback-check-read":
            try await rollbackCheck(phone: phone, mac: mac, entries: Array(state.entries[0...1]), phase: "read past")
        default: fatalError("Unknown rollback phase")
        }
        return true
    }
    private struct RollbackDevice {
        let store: JournalStore
        let client: ServerClient
        var sync: SyncEngine { SyncEngine(store: store, client: client) }
    }
    private static func rollbackDevice(_ name: String, state: RollbackState, address: String, directory: URL) throws
        -> RollbackDevice
    {
        let store = try JournalStore(
            directory: directory.appendingPathComponent(name), key: state.key)
        let token = name == "phone" ? state.phoneToken : state.macToken
        return RollbackDevice(store: store, client: try ServerClient(address: address, token: token))
    }
    private static func rollbackSetup(address: String, setupCodeFile: String, directory: URL) async throws {
        let code = try String(contentsOfFile: setupCodeFile).trimmingCharacters(in: .whitespacesAndNewlines)
        let (master, phrase, envelope, secret) = try recoveryFixture()
        let anonymous = try ServerClient(address: address)
        let phoneGrant = try await anonymous.initialize(
            code: code, envelope: envelope, recoverySecret: secret, deviceName: "Rollback Phone")
        let parameters = try await anonymous.recoveryParameters()
        let macGrant = try await anonymous.recoverVault(phrase, parameters: parameters, deviceName: "Rollback Mac")
            .grant
        let journal = JournalItem(kind: "journal", title: "Notes")
        let entries = (1...3).map {
            JournalItem(kind: "entry", journalID: journal.id, document: .plain("Entry \($0) before the copy"))
        }
        let state = RollbackState(
            phrase: phrase, secret: secret, key: master, phoneToken: phoneGrant.token,
            macToken: macGrant.token, entries: entries.map(\.id))
        try JournalCoding.encoder().encode(state).write(to: directory.appendingPathComponent("state.json"))
        let phone = try rollbackDevice("phone", state: state, address: address, directory: directory)
        let mac = try rollbackDevice("mac", state: state, address: address, directory: directory)
        try await phone.store.save(journal)
        for entry in entries { try await phone.store.save(entry) }
        try await phone.sync.synchronize()
        try await mac.sync.synchronize()
        try await phone.sync.synchronize()
    }
    private static func edit(_ store: JournalStore, _ id: UUID, _ text: String) async throws {
        guard var item = try await store.item(id) else { throw ProbeFailure("rollback probe: an entry is missing") }
        item.document = .plain(text)
        try await store.save(item)
    }
    /// The phone's edit is accepted, but the phone doesn't read on, as when the connection drops right after it.
    private static func rollbackUnsent(_ phone: RollbackDevice, state: RollbackState) async throws {
        try await edit(phone.store, state.entries[2], "Phone, sent without reading on")
        for pending in try await phone.store.pending() {
            guard case .accepted(let receipt) = try await phone.client.push(pending) else {
                throw ProbeFailure("rollback probe: the phone's edit wasn't accepted")
            }
            try await phone.store.acknowledge(pending, receipt: receipt)
        }
        try await edit(phone.store, state.entries[2], "Phone, edited again")
    }
    private static func rollbackRead(_ phone: RollbackDevice, state: RollbackState) async throws {
        try await edit(phone.store, state.entries[0], "Phone, read past")
        try await edit(phone.store, state.entries[1], "Phone, read past")
        try await phone.sync.synchronize()
        try await edit(phone.store, state.entries[1], "Phone, read past and edited again")
    }
    /// The Mac edits the entries in the order the phone did, so its changes take the positions the server lost.
    private static func rollbackCheck(phone: RollbackDevice, mac: RollbackDevice, entries: [UUID], phase: String)
        async throws
    {
        for entry in entries { try await edit(mac.store, entry, "Mac, after the copy") }
        try await mac.sync.synchronize()
        let expected = try await entries.asyncMap { try await phone.store.item($0)?.document.text }
        try await phone.sync.synchronize()
        try await phone.sync.synchronize()
        let reviews = try await phone.store.conflicts()
        guard reviews.isEmpty else {
            throw ProbeFailure("rollback probe (\(phase)): the phone left the versions for review")
        }
        let phoneItems = try await phone.store.items()
        for (entry, phoneText) in zip(entries, expected) {
            let record = phoneItems.first { $0.id == entry }
            guard record?.document.text == phoneText else {
                throw ProbeFailure("rollback probe (\(phase)): the phone's version isn't the entry")
            }
        }
        let phoneCopies = phoneItems.filter { isMacCopy($0) }
        guard phoneCopies.count == entries.count else {
            throw ProbeFailure("rollback probe (\(phase)): the Mac's versions aren't kept as entries of their own")
        }
        try await mac.sync.synchronize()
        let macItems = try await mac.store.items()
        for (entry, phoneText) in zip(entries, expected) {
            guard macItems.first(where: { $0.id == entry })?.document.text == phoneText else {
                throw ProbeFailure("rollback probe (\(phase)): the version kept on the phone didn't reach the Mac")
            }
        }
        guard macItems.filter({ isMacCopy($0) }).count == entries.count else {
            throw ProbeFailure("rollback probe (\(phase)): the Mac lost its own version")
        }
        print("PASS: after the server lost edits it accepted (\(phase)), both versions are kept as entries")
    }
    private static func isMacCopy(_ item: JournalItem) -> Bool {
        item.kind == "entry" && item.title.hasSuffix("(other version)")
            && item.document.text == "Mac, after the copy"
    }
}

extension Array {
    fileprivate func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        for element in self { result.append(try await transform(element)) }
        return result
    }
}
