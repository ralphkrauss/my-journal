import Foundation
import JournalCore

extension Probe {
    /// Row 4: the server was wiped and set up with another library. A is told the server was restored or replaced;
    /// after signing in with that library's password, lineage finds nothing of A's there, so A's journals merge:
    /// same-name journals combine and A's unedited built-in templates end up once each. The other library is from a
    /// build that creates no templates, so A's are added.
    static func replacedByAnotherLibrary(
        address: String, code: String, state: inout HealthState, root: URL
    ) async throws {
        let (otherKey, otherPhrase, otherEnvelope, otherSecret) = try recoveryFixture()
        let anonymous = try ServerClient(address: address)
        let grant = try await anonymous.initialize(
            code: code, envelope: otherEnvelope, recoverySecret: otherSecret, deviceName: "Probe other")
        state.devices["other"] = .init(
            folder: "other", key: otherKey, token: grant.token, deviceID: grant.deviceId)
        let other = try open("other", state, root: root, address: address)
        let journal = JournalItem(kind: "journal", title: "Default")
        try await other.store.save(journal)
        try await other.store.save(JournalItem(kind: "entry", journalID: journal.id, title: "Other library's entry"))
        state.written.append("Other library's entry")
        try await other.synchronize()

        let deviceA = try open("a", state, root: root, address: address)
        try await expectState(.serverReplaced, syncing: deviceA, "set up with another library")
        let recovered = try await anonymous.recoverVault(
            otherPhrase, parameters: anonymous.recoveryParameters(), deviceName: "Probe a")
        let client = try ServerClient(address: address, token: recovered.grant.token)
        guard recovered.key != state.devices["a"]?.key else {
            throw ProbeFailure("another library's server has a's key, so a would join without merging")
        }
        print("PASS: set up with another library: the key differs, so joining asks to merge")
        let folder = "a-merged"
        let staged = try JournalStore(directory: root.appendingPathComponent(folder), key: recovered.key)
        try await SyncEngine(store: staged, client: client).synchronize()
        let server = try await client.status().serverId ?? address
        let readByAgents = try await client.journalsAgentsCanRead(vaultKey: recovered.key)
        try await staged.importMerging(from: deviceA.store, server: server, readByAgents: readByAgents)
        try await deviceA.store.close()
        state.devices["a"] = .init(
            folder: folder, key: recovered.key, token: recovered.grant.token, deviceID: recovered.grant.deviceId)
        // Merged images take new identities; MergeProbe checks images.
        state.image = nil
        let merged = HealthDevice(name: "a", store: staged, client: client)
        try await converge([merged, other], state: state, "merged into another library")
        let journals = try await staged.items().filter { $0.kind == "journal" && $0.deletedAt == nil }
        guard journals.map(\.id) == [journal.id] else {
            throw ProbeFailure("the same-name journals weren't combined: \(journals.map(\.title))")
        }
        let templates = try await staged.items().filter { $0.kind == "template" && $0.deletedAt == nil }.map(\.title)
        guard templates.sorted() == BuiltInTemplates.shipped.map(\.title).sorted() else {
            throw ProbeFailure("the built-in templates aren't there once each: \(templates.sorted())")
        }
        print("PASS: merged into another library: one Default journal and each built-in template once")
    }
}
