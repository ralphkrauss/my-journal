import JournalCore
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Settings > Agent Access for agents that connect to the sync server's MCP endpoint (docs/design/agent-access-server.md
/// and agent-access-simplified.md). The list and its state belong to the pane; the agents themselves are on the server.
@MainActor
final class ServerAgentsController: ObservableObject {
    enum Phase: Equatable {
        case loading, needsUpdate, unreachable, noAccess, addressUnavailable(String), ready
    }
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var agents: [LibraryAgent] = []
    /// Requests waiting for the owner, newest first.
    @Published private(set) var requests: [AgentRequest] = []
    @Published private(set) var mcpURL: String?
    /// True once a list was loaded, so a later failure keeps showing it.
    @Published private(set) var loaded = false
    // What the pane presents. The form presents it (ServerAgentsPresentation): a sheet attached to a section of an
    // iPhone form is hosted by a row and dismisses Settings instead of appearing.
    @Published var reviewing: AgentRequest?
    @Published var connecting = false
    @Published var selected: LibraryAgent?
    private var loading: Task<Void, Never>?
    /// First uploads of agents allowed here, which continue after the sheet closes (on iOS as a background task).
    private var firstCopies: [UUID: Task<Void, Never>] = [:]

    /// Loads the address and list, unless a load is running.
    func load(_ model: AppModel) async {
        if let loading { return await loading.value }
        let task = Task { await read(model) }
        loading = task
        await task.value
        loading = nil
    }
    private func read(_ model: AppModel) async {
        guard !model.locked else { return }
        guard let publisher = model.agentCopies, let client = try? model.connectedClient() else {
            // Never left loading: Try Again reads the list once the connection is usable.
            if !loaded { phase = .unreachable }
            return
        }
        if !loaded { phase = .loading }
        do {
            let status = try await client.status()
            guard status.supports(ServerClient.agentAccessFeature) else {
                phase = .needsUpdate
                return
            }
            guard let address = status.mcpUrl else {
                phase = .addressUnavailable(status.mcpUnavailable ?? "https-required")
                return
            }
            let list = try await publisher.list()
            guard !model.locked else { return }
            mcpURL = address
            agents = list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            loaded = true
            phase = .ready
        } catch JournalError.unauthorized {
            phase = .noAccess
        } catch AgentCopyError.serverOutdated {
            phase = .needsUpdate
        } catch {
            phase = .unreachable
        }
    }
    /// Reads the waiting requests. Failures keep the last list; the pane's own load reports them.
    func refreshRequests(_ model: AppModel) async {
        guard !model.locked, phase == .ready, let client = try? model.connectedClient() else { return }
        guard let waiting = try? await client.agentRequests(), !model.locked else { return }
        let arrived = Set(waiting.map(\.id)) != Set(requests.map(\.id))
        requests = waiting
        // A connecting agent turns active once the agent collects its access, and a new request may come from an
        // agent that signed out: the list shows their current state.
        if arrived || agents.contains(where: { $0.server.state == .pending }) { await load(model) }
    }
    /// Leaves out a request that ended here (declined for a wrong number), before the next refresh.
    func forget(_ request: AgentRequest) { requests.removeAll { $0.id == request.id } }
    /// A request's details, once the owner opens it.
    func request(_ model: AppModel, id: UUID) async throws -> AgentRequest {
        guard !model.locked else { throw JournalError.locked }
        return try await model.connectedClient().agentRequest(id)
    }
    /// Approves a request with the number its page shows. The agent is named after its client, numbered when another
    /// agent already has that name. The first copy continues in the background.
    func approve(_ model: AppModel, request: AgentRequest, number: Int, allJournals: Bool, journalIDs: Set<UUID>)
        async throws
    {
        guard !model.locked, let publisher = model.agentCopies else { throw JournalError.locked }
        let id = try await publisher.approve(
            request, number: number, name: defaultName(for: request), allJournals: allJournals,
            journalIDs: journalIDs, expiresAt: nil)
        requests.removeAll { $0.id == request.id }
        firstCopies[id] = Task {
            // Switching back to the browser mustn't stall the first upload.
            let activity = UploadActivity()
            await publisher.waitForFirstCopy(id)
            activity.end()
        }
        await load(model)
    }
    func reconnect(_ model: AppModel, request: AgentRequest, number: Int, agent: LibraryAgent) async throws {
        guard !model.locked, let publisher = model.agentCopies else { throw JournalError.locked }
        try await publisher.reconnect(request, number: number, agent: agent)
        requests.removeAll { $0.id == request.id }
        await load(model)
    }
    func decline(_ model: AppModel, request: AgentRequest) async throws {
        requests.removeAll { $0.id == request.id }
        guard !model.locked, let publisher = model.agentCopies else { throw JournalError.locked }
        try await publisher.decline(request)
    }
    /// Changes an agent's name, journals or end, and returns it as changed.
    func change(
        _ model: AppModel, agent: LibraryAgent, name: String, allJournals: Bool, journalIDs: Set<UUID>,
        expiresAt: Date?
    ) async throws -> LibraryAgent {
        guard !model.locked, let publisher = model.agentCopies else { throw JournalError.locked }
        let changed = try await publisher.change(
            agent, name: name, allJournals: allJournals, journalIDs: journalIDs, expiresAt: expiresAt)
        agents = agents.map { $0.id == changed.id ? changed : $0 }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return changed
    }
    func revoke(_ model: AppModel, agent: LibraryAgent) async throws {
        guard !model.locked, let publisher = model.agentCopies else { throw JournalError.locked }
        try await publisher.revoke(agent.id)
        agents.removeAll { $0.id == agent.id }
    }
    func activity(_ model: AppModel, agent: LibraryAgent) async throws -> [AgentActivityEvent] {
        guard !model.locked, let publisher = model.agentCopies else { throw JournalError.locked }
        return try await publisher.activity(agent.id)
    }
    /// Forgets the list, for example when My Journal locks.
    func clear() {
        reviewing = nil
        connecting = false
        selected = nil
        loading?.cancel()
        loading = nil
        for task in firstCopies.values { task.cancel() }
        firstCopies = [:]
        agents = []
        requests = []
        loaded = false
        mcpURL = nil
        phase = .loading
    }
    func agent(_ id: UUID?) -> LibraryAgent? { agents.first { $0.id == id } }
    /// The agent a request would reconnect (one of its client that signed out).
    func reconnectTarget(_ request: AgentRequest) -> LibraryAgent? {
        agent(request.reconnectCandidate).flatMap { $0.settings == nil ? nil : $0 }
    }
    /// The client's name, or "Claude Code 2" when an agent is already called "Claude Code".
    private func defaultName(for request: AgentRequest) -> String {
        let base = ServerAgentText.displayName(request.clientName)
        let names = Set(agents.map(\.name))
        guard names.contains(base) else { return base }
        var number = 2
        while names.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }
}

/// Text shared by the agent screens.
enum ServerAgentText {
    static let guide = URL(string: "https://github.com/ralphkrauss/my-journal/blob/main/docs/guide/agent-access.md")

    /// How the sync server is named in sentences: its host, or "this Mac" for the Mac's own server.
    static func host(_ address: String?) -> String {
        guard let host = address.flatMap({ URL(string: $0)?.host }) else { return "your server" }
        return isLoopback(host: host) ? "this Mac" : host
    }
    /// The same, to begin a sentence.
    static func leadingHost(_ address: String?) -> String {
        let name = host(address)
        return name.prefix(1).uppercased() + name.dropFirst()
    }
    static func isLoopback(host: String) -> Bool { ["127.0.0.1", "localhost", "::1"].contains(host) }

    /// Who can reach an MCP address, when that's limited.
    static func reachability(_ mcpURL: String) -> String? {
        guard let host = URL(string: mcpURL)?.host else { return nil }
        if isLoopback(host: host) {
            return "Only agents running on this Mac, such as Claude Code, can use this address."
        }
        if host.hasSuffix(".ts.net") {
            return
                "Only agents on devices in your tailnet can use this address. Agents that connect from the cloud, such as ChatGPT or Claude on the web, can’t reach it."
        }
        return nil
    }

    static func journalNames(_ agent: LibraryAgent, journals: [JournalItem]) -> String {
        guard let settings = agent.settings else { return "Details aren’t available on this device." }
        if settings.allJournals { return "All Journals" }
        let names = journals.filter { settings.journalIDs.contains($0.id) }.map(\.title)
        return names.isEmpty ? "No journals on this device" : names.joined(separator: ", ")
    }
    /// A name a client chose for itself, as the app shows it (AgentDisplayName).
    static func displayName(_ name: String) -> String { AgentDisplayName.clean(name) }
    /// When a request was made, for its row.
    static func asked(_ date: Date, now: Date = Date()) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return "just now" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
    /// The row's status line.
    static func status(_ agent: LibraryAgent, now: Date = Date()) -> String {
        if let ends = agent.expiresAt, ends <= now {
            return "Access ended \(ends.formatted(date: .abbreviated, time: .omitted))"
        }
        if agent.server.state == .pending { return "Connecting…" }
        if agent.needsReconnect { return "Needs to reconnect" }
        if let ends = agent.expiresAt, ends.timeIntervalSince(now) < 7 * 24 * 3600 {
            return "Access ends \(ends.formatted(date: .abbreviated, time: .omitted))"
        }
        guard let used = agent.server.lastUsedAt else { return "Never used" }
        return "Last used \(used.formatted(.relative(presentation: .named)))"
    }
    static func activity(_ tool: String) -> String {
        switch tool {
        case "search_entries": return "Searched Entries"
        case "read_entry": return "Read an Entry"
        case "list_journals": return "Listed Journals"
        default: return "Used a Tool"
        }
    }
    /// Where the approved agent returns to, as the approval sheet says it.
    static func returns(_ request: AgentRequest) -> String {
        request.returnsToLoopback
            ? "Returns to \(request.redirectHost), an app on the computer that opened the page"
            : "Returns to \(request.redirectHost)"
    }
    /// What an agent can do with the journals it reads.
    static func readOnly(_ name: String) -> String {
        "\(name) can search and read entries in these journals but can’t change anything."
    }
}

/// Copying text that isn't secret.
@MainActor
enum PlainPasteboard {
    static func copy(_ text: String) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #else
            UIPasteboard.general.string = text
        #endif
    }
}

/// Asks iOS for time to finish the first upload after the person switches back to their agent.
@MainActor
private final class UploadActivity {
    #if os(iOS)
        private var identifier = UIBackgroundTaskIdentifier.invalid
        init() {
            identifier = UIApplication.shared.beginBackgroundTask(withName: "Sharing journals with an agent") {
                [weak self] in self?.end()
            }
        }
        func end() {
            guard identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
    #else
        func end() {}
    #endif
}
