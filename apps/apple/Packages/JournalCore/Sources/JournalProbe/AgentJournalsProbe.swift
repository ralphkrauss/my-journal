import Foundation
import JournalCore

/// Journals entering and leaving agents' copies (docs/design/agent-access-simplified.md and
/// journal-name-uniqueness.md §5). With All Journals, a second journal (as a merge adds, "Default 2") is shared too;
/// moving its entries away and then moving it to Recently Deleted removes it from what the agent lists and finds once
/// a device syncs. Merge Into… moves entries into the copy of an agent that reads only the destination, and out of the
/// copy of one that reads only the merged journal. A device that listed the agents before another device allowed a new
/// one publishes its next synced change to that agent at once. Run by scripts/test-sync.sh:
/// `agent-journals <address> <setup-code file>`.
extension Probe {
    static func runAgentJournalsProbe() async throws -> Bool {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.first == "agent-journals", arguments.count == 3 else { return false }
        try await agentJournals(address: arguments[1], setupCodeFile: arguments[2])
        return true
    }

    private struct AgentJournalsDevice {
        let client: ServerClient
        let store: JournalStore
        let sync: SyncEngine
        let publisher: AgentCopyPublisher
        let mcp: URL
        let key: Data

        /// Sends this device's changes and brings every agent's copy up to date.
        func publish() async throws {
            try await sync.synchronize()
            try await publisher.publishNow()
        }
        /// An agent approved for All Journals or for `journals`, with its tokens.
        func connectAgent(allJournals: Bool, journals: Set<UUID>) async throws -> OAuthProbeClient {
            var agent = try OAuthProbeClient(mcp: mcp)
            try await agent.register()
            let page = try await agent.openAuthorizationPage()
            guard let waiting = try await client.agentRequests().first else { throw ProbeFailure("no request") }
            let request = try await client.agentRequest(waiting.id)
            let grantID = try await publisher.approve(
                request, number: page.number, name: "Probe agent", allJournals: allJournals, journalIDs: journals,
                expiresAt: nil)
            await publisher.waitForFirstCopy(grantID)
            try await agent.redeem(handle: page.handle)
            return agent
        }
    }

    private static func agentJournals(address: String, setupCodeFile: String) async throws {
        let code = try String(contentsOfFile: setupCodeFile).trimmingCharacters(in: .whitespacesAndNewlines)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("journal-agent-journals-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (master, phrase, envelope, recoverySecret) = try recoveryFixture()
        let grant = try await ServerClient(address: address).initialize(
            code: code, envelope: envelope, recoverySecret: recoverySecret, deviceName: "Probe Mac")
        let client = try ServerClient(address: address, token: grant.token)
        let store = try JournalStore(directory: root, key: master)
        guard let mcpURL = try await client.status().mcpUrl, let mcp = URL(string: mcpURL) else {
            throw ProbeFailure("the server didn't report an MCP address")
        }
        let device = AgentJournalsDevice(
            client: client, store: store, sync: SyncEngine(store: store, client: client),
            publisher: AgentCopyPublisher(store: store, client: client), mcp: mcp, key: master)
        let kept = JournalItem(kind: "journal", title: "Default")
        try await leavingWithAllJournals(device, kept: kept)
        try await mergingIntoSelectedJournals(device, kept: kept)
        let anonymous = try ServerClient(address: address)
        let phoneGrant = try await anonymous.recoverVault(
            phrase, parameters: anonymous.recoveryParameters(), deviceName: "Probe iPhone"
        ).grant
        let phoneClient = try ServerClient(address: address, token: phoneGrant.token)
        let phoneRoot = root.appendingPathExtension("phone")
        defer { try? FileManager.default.removeItem(at: phoneRoot) }
        let phoneStore = try JournalStore(directory: phoneRoot, key: master)
        let phone = AgentJournalsDevice(
            client: phoneClient, store: phoneStore, sync: SyncEngine(store: phoneStore, client: phoneClient),
            publisher: AgentCopyPublisher(store: phoneStore, client: phoneClient), mcp: mcp, key: master)
        try await allowedOnAnotherDevice(device, phone: phone, kept: kept)
    }

    /// The phone read the list of agents before the Mac allowed a new one; its next synced entry reaches that agent
    /// with that sync, not when its list would have been read again minutes later.
    private static func allowedOnAnotherDevice(
        _ mac: AgentJournalsDevice, phone: AgentJournalsDevice, kept: JournalItem
    ) async throws {
        try await phone.publish()
        let agent = try await mac.connectAgent(allJournals: true, journals: [])
        let entry = JournalItem(
            kind: "entry", journalID: kept.id, title: "Sprint planning", document: .plain("Draft the roadmap"))
        try await phone.store.save(entry)
        try await phone.publish()
        let found = try await agent.callTool("search_entries", ["query": "roadmap"])
        guard found.contains("Sprint planning") else {
            throw ProbeFailure("an agent allowed on another device didn't get this device's synced entry: \(found)")
        }
        print("PASS: an agent allowed on another device gets this device's next synced change")
    }

    private static func leavingWithAllJournals(_ device: AgentJournalsDevice, kept: JournalItem) async throws {
        let store = device.store
        let merged = JournalItem(kind: "journal", title: "Default 2")
        let moved = JournalItem(
            kind: "entry", journalID: merged.id, title: "Moved", document: .plain("Walk by the river"))
        let left = JournalItem(kind: "entry", journalID: merged.id, title: "Left", document: .plain("Quiet morning"))
        for item in [kept, merged, moved, left] { try await store.save(item) }
        try await device.sync.synchronize()
        let agent = try await device.connectAgent(allJournals: true, journals: [])
        let before = try await agent.callTool("list_journals", [:])
        guard before.contains(kept.id.uuidString), before.contains(merged.id.uuidString) else {
            throw ProbeFailure("All Journals didn't share both journals: \(before)")
        }
        // An agent with All Journals reads a journal whether or not a joining device combines into it.
        let readByAgents = try await device.client.journalsAgentsCanRead(
            vaultKey: device.key)
        guard readByAgents == [] else {
            throw ProbeFailure("an All Journals agent kept a joining device from combining journals")
        }
        print("PASS: an agent with All Journals doesn't keep a joining device from combining journals")

        // One entry moves to the kept journal; the other journal goes to Recently Deleted with its last entry.
        _ = try await store.moveEntry(moved.id, to: kept.id)
        _ = try await store.deleteJournal(store.prepareJournalDeletion(merged.id))
        try await device.publish()
        let after = try await agent.callTool("list_journals", [:])
        let found = try await agent.callTool("search_entries", [:])
        guard after.contains(kept.id.uuidString), !after.contains(merged.id.uuidString),
            found.contains("Walk by the river"), !found.contains("Quiet morning")
        else {
            throw ProbeFailure("a journal moved to Recently Deleted is still in the agent's copy: \(after) \(found)")
        }
        print("PASS: a journal moved to Recently Deleted leaves what an agent lists and finds after a sync")
    }

    /// Merge Into… with agents that read only the destination, only the merged journal, or all journals.
    private static func mergingIntoSelectedJournals(_ device: AgentJournalsDevice, kept: JournalItem) async throws {
        let store = device.store
        let travel = JournalItem(kind: "journal", title: "Travel")
        let notes = JournalItem(kind: "journal", title: "Notes")
        let harbour = JournalItem(
            kind: "entry", journalID: travel.id, title: "Harbour", document: .plain("Boats in the harbour"))
        let idea = JournalItem(kind: "entry", journalID: notes.id, title: "Idea", document: .plain("A reading lamp"))
        for item in [travel, notes, harbour, idea] { try await store.save(item) }
        try await device.sync.synchronize()
        let allJournals = try await device.connectAgent(allJournals: true, journals: [])
        let readsDefault = try await device.connectAgent(allJournals: false, journals: [kept.id])
        let readsNotes = try await device.connectAgent(allJournals: false, journals: [notes.id])
        let before = try await readsDefault.callTool("search_entries", [:])
        guard !before.contains("Boats in the harbour"), !before.contains("A reading lamp") else {
            throw ProbeFailure("an agent reads entries of journals it wasn't given: \(before)")
        }

        // Combining two journals is moving their entries one at a time and deleting what is left.
        for entry in [harbour, idea] {
            _ = try await store.moveEntry(entry.id, to: kept.id)
        }
        for journal in [travel, notes] {
            _ = try await store.deleteJournal(try await store.prepareJournalDeletion(journal.id))
        }
        try await device.publish()
        let gained = try await readsDefault.callTool("search_entries", [:])
        let lost = try await readsNotes.callTool("search_entries", [:])
        let everything = try await allJournals.callTool("search_entries", [:])
        guard gained.contains("Boats in the harbour"), gained.contains("A reading lamp") else {
            throw ProbeFailure("entries moved into a journal an agent reads aren't in its copy: \(gained)")
        }
        guard !lost.contains("A reading lamp") else {
            throw ProbeFailure("entries moved out of a journal an agent reads are still in its copy: \(lost)")
        }
        guard everything.contains("Boats in the harbour"), everything.contains("A reading lamp") else {
            throw ProbeFailure("an agent with All Journals lost moved entries: \(everything)")
        }
        print("PASS: merged entries enter the copy of an agent reading the destination and leave the others'")
    }
}
