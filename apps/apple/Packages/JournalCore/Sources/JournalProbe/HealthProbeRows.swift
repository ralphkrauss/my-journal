import Foundation
import JournalCore

extension Probe {
    /// Row 4: the server was wiped and set up with another library. A is told the server was restored or replaced;
    /// after signing in with that library's password, lineage finds nothing of A's there, so A's journals merge:
    /// same-name journals combine and A's unedited built-in templates end up once each. Without `encrypted` the other
    /// library is from a build that creates no templates, so A's are added; with it, the other library is from an
    /// earlier build and has its own, so A's aren't. With `encrypted`, the other library is also encrypted and A's
    /// isn't (case 10): A is asked to sign in, since that looks like encryption turned on elsewhere.
    static func replacedByAnotherLibrary(
        address: String, code: String, state: inout HealthState, root: URL, encrypted: Bool?
    ) async throws {
        let (otherKey, otherPhrase, otherEnvelope, otherSecret) = try otherLibraryFixture(encrypted: encrypted)
        let anonymous = try ServerClient(address: address)
        let grant = try await anonymous.initialize(
            code: code, envelope: otherEnvelope, recoverySecret: otherSecret, deviceName: "Probe other")
        let protection = try otherEnvelope.contentProtection
        state.devices["other"] = .init(
            folder: "other", key: otherKey, token: grant.token, deviceID: grant.deviceId,
            protection: protection.rawValue)
        let other = try open("other", state, root: root, address: address)
        if encrypted == true {
            for template in BuiltInTemplates.asEarlierBuildsCreated() { try await other.store.save(template) }
        }
        let journal = JournalItem(kind: "journal", title: "Default")
        try await other.store.save(journal)
        try await other.store.save(JournalItem(kind: "entry", journalID: journal.id, title: "Other library's entry"))
        state.written.append("Other library's entry")
        try await other.synchronize()

        let deviceA = try open("a", state, root: root, address: address)
        try await expectState(
            encrypted == true ? .signInNeeded : .serverReplaced, syncing: deviceA, "set up with another library")
        let recovered = try await anonymous.recoverVault(
            otherPhrase, parameters: anonymous.recoveryParameters(), deviceName: "Probe a")
        let client = try ServerClient(address: address, token: recovered.grant.token)
        guard try await !SyncLineage.serverHoldsLibrary(deviceA.store, client: client) else {
            throw ProbeFailure("another library's server was taken for a's own, so a would join without merging")
        }
        print("PASS: set up with another library: lineage asks to merge")
        let folder = "a-merged"
        let staged = try JournalStore(
            directory: root.appendingPathComponent(folder), key: recovered.key, protection: protection)
        try await SyncEngine(store: staged, client: client).synchronize()
        let server = try await client.status().serverId ?? address
        let readByAgents = try await client.journalsAgentsCanRead(vaultKey: recovered.key, protection: protection)
        try await staged.importMerging(from: deviceA.store, server: server, readByAgents: readByAgents)
        try await deviceA.store.close()
        state.devices["a"] = .init(
            folder: folder, key: recovered.key, token: recovered.grant.token, deviceID: recovered.grant.deviceId,
            protection: protection.rawValue)
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

    /// Row 10 without a password: after Stop Syncing and writing, A connects again with the server's recovery code.
    /// Its key only protects its own copy, so lineage alone tells it's the same library, and it joins by identity.
    static func plainReconnect(
        address: String, recoveryCode: String, state: inout HealthState, root: URL
    ) async throws {
        let deviceA = try open("a", state, root: root, address: address)
        try await write("P1 while not syncing", on: deviceA, state: &state)
        let grant = try await ServerClient(address: address).recover(secret: recoveryCode, deviceName: "Probe a")
        let client = try ServerClient(address: address, token: grant.token)
        guard try await SyncLineage.serverHoldsLibrary(deviceA.store, client: client) else {
            throw ProbeFailure("a library without a password wasn't recognized on its own server")
        }
        guard let key = state.devices["a"]?.key else { throw ProbeFailure("a has no key") }
        let rejoined = try await rejoinByIdentity(
            deviceA, grant: grant, key: key, client: client, state: &state, root: root)
        let deviceB = try open("b", state, root: root, address: address)
        try await converge(
            [rejoined, deviceB], state: state, "stopped syncing without a password, then connected again")
    }

    /// Another library's recovery: the run's format, or an encrypted one with a password.
    private static func otherLibraryFixture(encrypted: Bool?) throws -> (Data, String, RecoveryEnvelope, String) {
        guard encrypted == true else { return try recoveryFixture() }
        let key = try VaultCrypto.generateKey()
        let phrase = "another library's password"
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase, formatVersion: 2)
        return (key, phrase, recovery.0, recovery.1)
    }
}
