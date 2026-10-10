import Foundation

/// An agent of this library with its opened settings. Settings are nil when they can't be opened on this device.
public struct LibraryAgent: Sendable, Identifiable, Equatable {
    public let server: ServerAgent
    public let settings: AgentCopySettings?
    public var id: UUID { server.id }
    public var name: String { settings?.name ?? "Unknown Agent" }
    public var expiresAt: Date? { settings?.expiresAt ?? server.expiresAt }
    public func hasExpired(at date: Date = Date()) -> Bool { expiresAt.map { $0 <= date } ?? false }
    public var needsReconnect: Bool { server.state == .needsReconnect }
}

/// The server operations agent access uses from a device.
protocol AgentCopyServer: Sendable {
    func agents() async throws -> [ServerAgent]
    func revokeAgent(_ id: UUID) async throws
    func approveAgentRequest(
        _ id: UUID, number: Int, grantID: UUID, metadata: String?, wrappedKey: Data, secret: Data, expiresAt: Date?
    ) async throws
    func agentRequestReady(_ id: UUID, complete: Bool) async throws
    func declineAgentRequest(_ id: UUID) async throws
    func agentActivity(_ id: UUID) async throws -> [AgentActivityEvent]
    func changeAgent(_ id: UUID, revision: Int64, metadata: String, expiresAt: Date?, removedItems: [String])
        async throws -> Int64
    func agentManifest(_ id: UUID, after: Int64) async throws -> AgentCopyPage<AgentCopyManifestItem>
    func uploadAgentItems(_ id: UUID, revision: Int64, items: [AgentCopyUpload], complete: Bool?) async throws
        -> [AgentCopyManifestItem]
}
extension ServerClient: AgentCopyServer {}

/// Approves agents' requests, lists and revokes agents, and keeps their copies current from this device's synchronized
/// state (protocol/agent-access-server.md). Nothing here changes the library.
public actor AgentCopyPublisher {
    public static let maximumAgents = 20
    /// How long approval waits for the first copy before letting the agent continue with part of it.
    public static let firstCopyWait: TimeInterval = 15
    /// How long the list of agents is used without changes to publish before it's read again. A device that allows or
    /// changes an agent publishes for it at once, and any change here reads the list first, so this only bounds how
    /// long a device with nothing new takes to notice agents changed elsewhere.
    static let listLifetime: TimeInterval = 10 * 60
    static let batchItems = 200
    static let batchBytes = 6 * 1024 * 1024
    private static let revokedSetting = "agent-copy-revoked"
    private let store: JournalStore
    private let client: any AgentCopyServer
    /// What this device knows each agent's copy holds on the server, by item ID.
    private var published: [UUID: [String: AgentCopyManifestItem]] = [:]
    /// How far this device has read each agent's manifest.
    private var manifestRead: [UUID: Int64] = [:]
    private var agents: [LibraryAgent]?
    private var agentsRead: Date?
    private var publishedFingerprint: String?
    private var running: Task<Void, Never>?
    private var again = false
    /// First uploads of agents this device just approved, by agent.
    private var firstCopies: [UUID: Task<Void, Never>] = [:]

    public init(store: JournalStore, client: ServerClient) {
        self.init(store: store, server: client)
    }
    init(store: JournalStore, server: any AgentCopyServer) {
        self.store = store
        client = server
    }

    // MARK: Agents

    /// The library's agents. Agents this device revoked are revoked again if a server rollback brought them back.
    public func list() async throws -> [LibraryAgent] {
        let revoked = try await revokedAgents()
        var result: [LibraryAgent] = []
        for agent in try await client.agents() {
            if revoked.contains(agent.id) {
                try? await client.revokeAgent(agent.id)
                continue
            }
            let settings = try? AgentCopyCrypto.openSettings(
                agent.metadata, grantID: agent.id, vaultKey: store.key)
            result.append(LibraryAgent(server: agent, settings: settings))
        }
        // What this device knew of a copy whose settings changed since is read again.
        let revisions = Dictionary(uniqueKeysWithValues: (agents ?? []).map { ($0.id, $0.server.revision) })
        for agent in result where revisions[agent.id].map({ $0 != agent.server.revision }) == true {
            published[agent.id] = nil
        }
        agents = result
        agentsRead = Date()
        let listed = Set(result.map(\.id))
        published = published.filter { listed.contains($0.key) }
        return result
    }

    /// Approves an agent's request with the number its page shows, for every journal or the chosen ones. Returns once
    /// the server accepted; the first copy is uploaded in the background (`waitForFirstCopy`), after which the agent
    /// is sent back with its authorization code.
    public func approve(
        _ request: AgentRequest, number: Int, name: String, allJournals: Bool, journalIDs: Set<UUID>, expiresAt: Date?
    ) async throws -> UUID {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 80, allJournals || !journalIDs.isEmpty else {
            throw JournalError.invalidData
        }
        let grantID = UUID()
        let key = try VaultCrypto.random(32)
        let settings = AgentCopySettings(
            name: clean, clientName: request.clientName, allJournals: allJournals, journalIDs: journalIDs,
            expiresAt: expiresAt, key: key)
        let metadata = try AgentCopyCrypto.sealSettings(
            settings, grantID: grantID, vaultKey: store.key)
        let secret = try VaultCrypto.random(32)
        let wrapped = try AgentCopyCrypto.wrapCopyKey(key, secret: secret, grantID: grantID)
        try await client.approveAgentRequest(
            request.id, number: number, grantID: grantID, metadata: metadata, wrappedKey: wrapped, secret: secret,
            expiresAt: expiresAt)
        let server = ServerAgent(
            id: grantID, state: .pending, clientName: request.clientName, clientId: request.clientId,
            redirectHost: request.redirectHost, createdAt: Date(), expiresAt: expiresAt, lastUsedAt: nil,
            updatedAt: nil, copyComplete: false, metadata: metadata, revision: 1)
        let agent = LibraryAgent(server: server, settings: settings)
        published[grantID] = [:]
        agents = (agents ?? []) + [agent]
        firstCopies[grantID] = Task { [weak self] in
            guard let self else { return }
            let complete = await self.firstCopy(agent)
            try? await self.client.agentRequestReady(request.id, complete: complete)
        }
        return grantID
    }

    /// Waits until the first copy of an agent approved on this device is uploaded, or gave up.
    public func waitForFirstCopy(_ id: UUID) async {
        await firstCopies[id]?.value
        firstCopies[id] = nil
    }

    /// Reconnects an agent that signed out, with the number its new request's page shows. It keeps its journals, end
    /// date and copy.
    public func reconnect(_ request: AgentRequest, number: Int, agent: LibraryAgent) async throws {
        guard let settings = agent.settings else { throw JournalError.invalidData }
        let secret = try VaultCrypto.random(32)
        let wrapped = try AgentCopyCrypto.wrapCopyKey(settings.key, secret: secret, grantID: agent.id)
        try await client.approveAgentRequest(
            request.id, number: number, grantID: agent.id, metadata: nil, wrappedKey: wrapped, secret: secret,
            expiresAt: settings.expiresAt)
        try? await client.agentRequestReady(request.id, complete: agent.server.copyComplete)
    }

    public func decline(_ request: AgentRequest) async throws { try await client.declineAgentRequest(request.id) }

    /// Changes an agent's name, journals or end. Journals it no longer reads leave its copy in the same step, so it
    /// can't read them from then on; journals it now reads are published at once. Throws `settingsChanged` when
    /// another device changed the agent first, without changing anything.
    public func change(
        _ agent: LibraryAgent, name: String, allJournals: Bool, journalIDs: Set<UUID>, expiresAt: Date?
    ) async throws -> LibraryAgent {
        guard let old = agent.settings else { throw JournalError.invalidData }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 80, allJournals || !journalIDs.isEmpty else {
            throw JournalError.invalidData
        }
        let settings = AgentCopySettings(
            name: clean, clientName: old.clientName, allJournals: allJournals, journalIDs: journalIDs,
            expiresAt: expiresAt, key: old.key)
        let metadata = try AgentCopyCrypto.sealSettings(
            settings, grantID: agent.id, vaultKey: store.key)
        let source = try await store.agentCopySource()
        let keys = try AgentCopyKeys(old.key)
        // Narrowing from all journals can't be worked out from this device's journals alone (another device may have
        // shared one this device hasn't synced yet), so it looks at what the copy holds.
        if old.allJournals && !settings.allJournals { published[agent.id] = nil }
        let known = old.allJournals && !settings.allJournals ? try await manifest(agent.id) : [:]
        let removed = AgentCopyNarrowing.removedItems(from: old, to: settings, keys: keys, source: source, copy: known)
        let revision = try await client.changeAgent(
            agent.id, revision: agent.server.revision, metadata: metadata, expiresAt: expiresAt,
            removedItems: removed.sorted())
        let server = ServerAgent(
            id: agent.id, state: agent.server.state, clientName: agent.server.clientName,
            clientId: agent.server.clientId, redirectHost: agent.server.redirectHost,
            createdAt: agent.server.createdAt, expiresAt: expiresAt, lastUsedAt: agent.server.lastUsedAt,
            updatedAt: Date(), copyComplete: agent.server.copyComplete, metadata: metadata, revision: revision)
        let changed = LibraryAgent(server: server, settings: settings)
        agents = (agents ?? []).map { $0.id == agent.id ? changed : $0 }
        // The server emptied items this device may have known; read what it holds before publishing again.
        published[agent.id] = nil
        publishedFingerprint = nil
        try? await publish(changed, from: store.agentCopySource())
        return changed
    }

    /// Revokes an agent on the server. This device remembers it, so it's revoked again if a restored server brings
    /// it back.
    public func revoke(_ id: UUID) async throws {
        try await rememberRevoked(id)
        try await client.revokeAgent(id)
        agents?.removeAll { $0.id == id }
        published[id] = nil
        firstCopies[id]?.cancel()
        firstCopies[id] = nil
    }
    public func activity(_ id: UUID) async throws -> [AgentActivityEvent] { try await client.agentActivity(id) }

    /// Uploads the first copy, but lets approval continue after `firstCopyWait`; the upload carries on meanwhile.
    /// Neither task is awaited here, so the agent continues as soon as the upload finishes rather than when the wait
    /// ends. Cancelling, as locking does, stops both.
    private func firstCopy(_ agent: LibraryAgent) async -> Bool {
        let (finished, signal) = AsyncStream<Bool>.makeStream()
        let upload = Task {
            do {
                try await publish(agent, from: store.agentCopySource())
                signal.yield(true)
            } catch {
                signal.yield(false)
            }
        }
        let timeout = Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.firstCopyWait * 1_000_000_000))
            signal.yield(false)
        }
        return await withTaskCancellationHandler {
            var first: Bool?
            for await complete in finished {
                first = complete
                break
            }
            timeout.cancel()
            signal.finish()
            return first ?? false
        } onCancel: {
            upload.cancel()
            timeout.cancel()
            signal.finish()
        }
    }

    // MARK: Publishing

    /// Brings every agent's copy up to date after a synchronization, unless an update is already running, in which
    /// case it runs once more afterwards. Failures wait for the next synchronization.
    public func requestPublishing() {
        guard running == nil else {
            again = true
            return
        }
        running = Task { await publishWhileRequested() }
    }
    /// Stops publishing, for example when the journals lock.
    public func stop() {
        running?.cancel()
        running = nil
        again = false
        for task in firstCopies.values { task.cancel() }
        firstCopies = [:]
    }
    /// Updates every agent's copy now and reports a failure.
    public func publishNow() async throws { try await publishAll() }
    private func publishWhileRequested() async {
        repeat {
            again = false
            try? await publishAll()
        } while again && !Task.isCancelled
        running = nil
    }
    /// Updates every agent's copy that needs it. Returns without reading the library when nothing it depends on
    /// changed since the last complete update.
    func publishAll() async throws {
        let fingerprint = try await store.agentCopyFingerprint()
        // Another device may have allowed or changed an agent. A pass with something new to publish reads the list
        // again, so such an agent gets this device's changes right after the sync that brought or sent them; without
        // changes the list is read again at most every minute.
        let listStale = agentsRead.map { Date().timeIntervalSince($0) > Self.listLifetime } ?? true
        guard listStale || fingerprint != publishedFingerprint else { return }
        _ = try await list()
        let active = (agents ?? []).filter { $0.settings != nil && !$0.hasExpired() }
        guard !active.isEmpty else {
            publishedFingerprint = fingerprint
            return
        }
        let source = try await store.agentCopySource()
        var failure: Error?
        for agent in active {
            try Task.checkCancellation()
            do {
                try await publish(agent, from: source)
            } catch AgentCopyError.settingsChanged {
                // Another device changed this agent: plan again with its settings at the next pass.
                agentsRead = nil
                failure = failure ?? AgentCopyError.settingsChanged
            } catch {
                failure = failure ?? error
            }
        }
        if let failure { throw failure }
        publishedFingerprint = fingerprint
    }
    private func publish(_ agent: LibraryAgent, from source: AgentCopySource) async throws {
        guard let settings = agent.settings, !settings.hasExpired() else { return }
        let keys = try AgentCopyKeys(settings.key)
        let known = try await manifest(agent.id)
        let plan = AgentCopyPlan(settings: settings, keys: keys, grantID: agent.id, source: source)
        let changes = try plan.changes(comparedWith: known)
        // A pass that left nothing out marks the copy complete; one the server already holds as complete needs nothing.
        let complete = plan.skipsNothing && !agent.server.copyComplete ? true : nil
        try await upload(changes, grantID: agent.id, revision: agent.server.revision, complete: complete)
    }
    /// What the server holds of an agent's copy: read once, then kept current from this device's uploads and from what
    /// changed on the server since, so items another device already published from the same synchronized state aren't
    /// uploaded again.
    private func manifest(_ id: UUID) async throws -> [String: AgentCopyManifestItem] {
        let known = published[id]
        var items = known ?? [:]
        var cursor = known == nil ? 0 : manifestRead[id] ?? 0
        var more = true
        while more {
            try Task.checkCancellation()
            let page = try await client.agentManifest(id, after: cursor)
            guard !page.hasMore || page.cursor > cursor else { throw JournalError.invalidData }
            for item in page.items { items[item.id] = item }
            cursor = page.cursor
            more = page.hasMore
        }
        published[id] = items
        manifestRead[id] = cursor
        return items
    }
    private func upload(_ changes: [AgentCopyUpload], grantID: UUID, revision: Int64, complete: Bool?) async throws {
        var batch: [AgentCopyUpload] = []
        var bytes = 0
        for change in changes {
            let size = change.payload?.utf8.count ?? 0
            if !batch.isEmpty && (batch.count == Self.batchItems || bytes + size > Self.batchBytes) {
                try await send(batch, grantID: grantID, revision: revision, complete: nil)
                batch = []
                bytes = 0
            }
            batch.append(change)
            bytes += size
        }
        if !batch.isEmpty || complete != nil {
            try await send(batch, grantID: grantID, revision: revision, complete: complete)
        }
    }
    private func send(_ batch: [AgentCopyUpload], grantID: UUID, revision: Int64, complete: Bool?) async throws {
        try Task.checkCancellation()
        let stale = try await client.uploadAgentItems(grantID, revision: revision, items: batch, complete: complete)
        var known = published[grantID] ?? [:]
        for item in batch {
            known[item.id] = AgentCopyManifestItem(
                id: item.id, version: item.version, digest: item.digest, deleted: item.payload == nil, sequence: 0)
        }
        // Another device published a newer state of these; keep what the server holds.
        for item in stale { known[item.id] = item }
        published[grantID] = known
    }

    private func revokedAgents() async throws -> Set<UUID> {
        guard let data = try await store.setting(Self.revokedSetting) else { return [] }
        return Set(try JournalCoding.decoder().decode([UUID].self, from: data))
    }
    private func rememberRevoked(_ id: UUID) async throws {
        var revoked = try await revokedAgents()
        revoked.insert(id)
        let sorted = revoked.sorted { $0.uuidString < $1.uuidString }
        try await store.setSetting(Self.revokedSetting, value: JournalCoding.encoder().encode(sorted))
    }
}

/// Which items of an agent's copy to empty when its journals are narrowed, so it can't read the journals it no longer
/// may, even ones this device doesn't have.
enum AgentCopyNarrowing {
    static func removedItems(
        from old: AgentCopySettings, to new: AgentCopySettings, keys: AgentCopyKeys, source: AgentCopySource,
        copy: [String: AgentCopyManifestItem]
    ) -> [String] {
        if new.allJournals { return [] }
        let local = Set(source.journals.keys)
        var removed = Set<String>()
        if old.allJournals {
            // Everything in the copy that isn't a still-shared journal or an entry this device knows belongs to one
            // goes; entries of shared journals this device doesn't know are published again by devices that do.
            var kept = Set(new.journalIDs.map { keys.itemID(recordID: $0) })
            for entry in source.entries where entry.journalID.map(new.shares) == true {
                kept.insert(keys.itemID(recordID: entry.id))
            }
            removed.formUnion(copy.values.filter { !$0.deleted && !kept.contains($0.id) }.map(\.id))
        }
        // Chosen journals no longer chosen, whether or not this device has them, and their entries it knows.
        let dropped = old.allJournals ? local.filter { !new.shares($0) } : old.journalIDs.subtracting(new.journalIDs)
        removed.formUnion(dropped.map { keys.itemID(recordID: $0) })
        for entry in source.entries where entry.journalID.map(dropped.contains) == true {
            removed.insert(keys.itemID(recordID: entry.id))
        }
        return removed.sorted()
    }
}

/// The items one agent's copy should hold, compared with what the server holds (protocol/agent-access-server.md,
/// The per-grant copy).
struct AgentCopyPlan {
    let settings: AgentCopySettings
    let keys: AgentCopyKeys
    let grantID: UUID
    let source: AgentCopySource

    /// Whether every shared journal and entry is settled here, so the copy this device publishes is complete.
    var skipsNothing: Bool {
        let journals = source.journals.values.filter { settings.shares($0.id) }
        let entries = source.entries.filter { $0.journalID.map(settings.shares) == true }
        return (journals + entries).allSatisfy(settled)
    }

    /// Uploads and deletions that bring `known` to this device's synchronized state. Items for records with a change
    /// or conflict here, or that this version can't read, are left as they are.
    func changes(comparedWith known: [String: AgentCopyManifestItem]) throws -> [AgentCopyUpload] {
        var desired: [String: AgentCopyItem?] = [:]
        var considered: Set<String> = []
        for (id, journal) in source.journals where settings.shares(id) {
            let itemID = keys.itemID(recordID: id)
            considered.insert(itemID)
            guard settled(journal) else { continue }
            let wanted: AgentCopyItem? = live(journal) ? .journal(id: id, name: journal.title) : nil
            desired[itemID] = .some(wanted)
        }
        for entry in source.entries {
            let itemID = keys.itemID(recordID: entry.id)
            considered.insert(itemID)
            let journal = entry.journalID.flatMap { source.journals[$0] }
            let shared = entry.journalID.map(settings.shares) == true
            guard settled(entry), journal.map(settled) ?? true else { continue }
            if shared, let journal, live(journal), entry.deletedAt == nil, !entry.deletedWithJournal,
                !entry.isPermanentlyDeleted
            {
                desired[itemID] = .some(
                    .entry(
                        id: entry.id, journalID: journal.id, title: entry.title, date: entry.date,
                        archivedAt: entry.archivedAt, text: AgentCopyText.readable(entry.document)))
            } else if known[itemID] != nil {
                desired[itemID] = .some(nil)
            }
        }
        // Items for records no longer here at all can't be checked, and are removed.
        for itemID in known.keys where !considered.contains(itemID) { desired[itemID] = .some(nil) }
        return try desired.keys.sorted().compactMap { itemID in
            guard let wanted = desired[itemID] else { return nil }
            return try change(itemID: itemID, wanted: wanted, known: known[itemID])
        }
    }
    private func change(itemID: String, wanted: AgentCopyItem?, known: AgentCopyManifestItem?) throws
        -> AgentCopyUpload?
    {
        // Another device already published this state or a newer one.
        if let known, known.version >= source.cursor { return nil }
        guard let wanted else {
            guard let known, !known.deleted else { return nil }
            return AgentCopyUpload(id: itemID, version: source.cursor, digest: known.digest, payload: nil)
        }
        let sealed = try AgentCopyCrypto.seal(wanted, grantID: grantID, keys: keys)
        if let known, !known.deleted, known.digest == sealed.digest { return nil }
        return AgentCopyUpload(id: itemID, version: source.cursor, digest: sealed.digest, payload: sealed.payload)
    }
    private func settled(_ item: JournalItem) -> Bool {
        !source.unsettled.contains(item.id) && item.document.isEditable
    }
    private func live(_ journal: JournalItem) -> Bool {
        journal.deletedAt == nil && !journal.isPermanentlyDeleted
    }
}
