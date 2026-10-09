import Foundation

/// Why an agent request didn't succeed (protocol/agent-access-server.md).
public enum AgentCopyError: Error, Equatable, Sendable {
    /// The server doesn't support agent access.
    case serverOutdated
    /// The library already has the most agents a server allows.
    case limit
    /// The request expired, was replaced, or was already answered.
    case requestNotFound
    /// The number entered isn't the one the request's page shows; the server declined the request.
    case numberMismatch
    /// Another device changed the agent's settings since this device read them.
    case settingsChanged
    /// The agent was revoked, or never existed.
    case notFound
    /// The agent's access ended.
    case expired
    /// The agent's copy is as large as a server allows.
    case quota
    /// Anything else the server refused; trying again may help.
    case failed
}

/// An agent as the server lists it. Its settings are sealed; only devices of the library can open them.
public struct ServerAgent: Decodable, Sendable, Identifiable, Equatable {
    public enum State: String, Decodable, Sendable {
        case pending, active, needsReconnect
    }
    public let id: UUID
    public let state: State
    public let clientName: String
    public let clientId: String
    public let redirectHost: String
    public let createdAt: Date
    public let expiresAt: Date?
    public let lastUsedAt: Date?
    public let updatedAt: Date?
    public let copyComplete: Bool
    public let metadata: String
    /// Increases with every change of the settings.
    public let revision: Int64
}

/// A request from an MCP client waiting for the owner. The number its page shows is never sent to devices.
public struct AgentRequest: Decodable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let clientName: String
    public let clientId: String
    /// The host a client metadata document proved control of, when the client returns over HTTPS.
    public let identifiedAs: String?
    public let redirectHost: String
    /// "https" or "loopback".
    public let redirectKind: String
    public let requestedAt: Date
    public let expiresAt: Date
    /// An agent of the same client that needs to reconnect.
    public let reconnectCandidate: UUID?
    public var returnsToLoopback: Bool { redirectKind == "loopback" }
}

/// A tool an agent used, and when.
public struct AgentActivityEvent: Decodable, Sendable, Hashable {
    public let at: Date
    public let tool: String
}

/// What the server holds of one item of an agent's copy.
public struct AgentCopyManifestItem: Codable, Sendable, Equatable {
    public let id: String
    public let version: Int64
    public let digest: String
    public let deleted: Bool
    public let sequence: Int64
}

struct AgentCopyPage<Item: Decodable & Sendable>: Decodable, Sendable {
    let items: [Item]
    let cursor: Int64
    let hasMore: Bool
}

/// An item to upload: a sealed item, or a deletion, whose payload is sent as an explicit null.
struct AgentCopyUpload: Encodable, Sendable {
    let id: String
    let version: Int64
    let digest: String
    let payload: String?

    private enum CodingKeys: String, CodingKey { case id, version, digest, payload }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(version, forKey: .version)
        try container.encode(digest, forKey: .digest)
        try container.encode(payload, forKey: .payload)
    }
}

extension ServerClient {
    /// Servers with this capability serve MCP to agents the owner approves.
    public static let agentAccessFeature = "agent-access-2"

    public func agents() async throws -> [ServerAgent] {
        let (data, status) = try await request("/v1/agents/")
        try Self.checkAgentResponse(status, data: data)
        return try JournalCoding.decoder().decode([ServerAgent].self, from: data)
    }
    /// The journals an agent was given one by one (Selected Journals), opened with the library's key. Combining
    /// another journal into one of them would let that agent read more (docs/design/journal-name-uniqueness.md §4.5).
    /// Agents with All Journals add nothing: they read a journal whether it's combined or added. Nil when an agent's
    /// settings can't be read, so which journals it reads isn't known. A server without agent access has none.
    public func journalsAgentsCanRead(vaultKey: Data, protection: ContentProtection) async throws -> Set<UUID>? {
        guard try await status().supports(Self.agentAccessFeature) else { return [] }
        var journals = Set<UUID>()
        for agent in try await agents() {
            guard
                let settings = try? AgentCopyCrypto.openSettings(
                    agent.metadata, grantID: agent.id, vaultKey: vaultKey, protection: protection)
            else { return nil }
            if !settings.allJournals { journals.formUnion(settings.journalIds) }
        }
        return journals
    }
    /// Requests waiting for the owner, newest first.
    public func agentRequests() async throws -> [AgentRequest] {
        let (data, status) = try await request("/v1/agent-requests/")
        try Self.checkAgentResponse(status, data: data)
        return try JournalCoding.decoder().decode([AgentRequest].self, from: data)
    }
    /// A request the owner opened; the server then keeps it until it's decided or expires.
    public func agentRequest(_ id: UUID) async throws -> AgentRequest {
        let (data, status) = try await request("/v1/agent-requests/\(id.uuidString.lowercased())")
        try Self.checkAgentResponse(status, data: data)
        return try JournalCoding.decoder().decode(AgentRequest.self, from: data)
    }
    func approveAgentRequest(
        _ id: UUID, number: Int, grantID: UUID, metadata: String?, wrappedKey: Data, secret: Data, expiresAt: Date?
    ) async throws {
        struct Body: Encodable {
            let number: Int
            let grantId: UUID
            let metadata: String?
            let wrappedKey: String
            let grantSecret: String
            let expiresAt: Date?
        }
        let body = Body(
            number: number, grantId: grantID, metadata: metadata, wrappedKey: wrappedKey.base64EncodedString(),
            grantSecret: secret.base64EncodedString(), expiresAt: expiresAt)
        let (data, status) = try await request(
            "/v1/agent-requests/\(id.uuidString.lowercased())/approve", method: "POST", body: json(body))
        try Self.checkAgentResponse(status, data: data)
    }
    /// Tells the server the first copy is uploaded, so it sends the agent back with its authorization code.
    func agentRequestReady(_ id: UUID, complete: Bool) async throws {
        let (data, status) = try await request(
            "/v1/agent-requests/\(id.uuidString.lowercased())/ready", method: "POST",
            body: json(["complete": complete]))
        try Self.checkAgentResponse(status, data: data)
    }
    /// Declines a request. One the server no longer has (ended, replaced or answered elsewhere) counts as declined:
    /// there is nothing left to decline or retry. Any other refusal, and any failure to reach the server, throws.
    public func declineAgentRequest(_ id: UUID) async throws {
        let (data, status) = try await request(
            "/v1/agent-requests/\(id.uuidString.lowercased())/decline", method: "POST", body: Data("{}".utf8))
        if status == 404, Self.problemCode(data) == "agent_request_not_found" { return }
        try Self.checkAgentResponse(status, data: data)
    }
    /// Revokes an agent. One the server doesn't know counts as revoked.
    public func revokeAgent(_ id: UUID) async throws {
        let (data, status) = try await request("/v1/agents/\(id.uuidString.lowercased())", method: "DELETE")
        if status == 404, Self.problemCode(data) == "agent_not_found" { return }
        try Self.checkAgentResponse(status, data: data)
    }
    public func agentActivity(_ id: UUID) async throws -> [AgentActivityEvent] {
        let (data, status) = try await request("/v1/agents/\(id.uuidString.lowercased())/activity")
        try Self.checkAgentResponse(status, data: data)
        return try JournalCoding.decoder().decode([AgentActivityEvent].self, from: data)
    }
    /// Replaces an agent's sealed settings from `revision`, emptying `removedItems` (the items of journals it no longer
    /// reads) in the same step. Returns the new revision.
    func changeAgent(_ id: UUID, revision: Int64, metadata: String, expiresAt: Date?, removedItems: [String])
        async throws -> Int64
    {
        struct Body: Encodable {
            let revision: Int64
            let metadata: String
            let expiresAt: Date?
            let removedItems: [String]
        }
        struct Result: Decodable { let revision: Int64 }
        let (data, status) = try await request(
            "/v1/agents/\(id.uuidString.lowercased())", method: "PUT",
            body: json(Body(revision: revision, metadata: metadata, expiresAt: expiresAt, removedItems: removedItems)))
        try Self.checkAgentResponse(status, data: data)
        return try JournalCoding.decoder().decode(Result.self, from: data).revision
    }
    func agentManifest(_ id: UUID, after: Int64) async throws -> AgentCopyPage<AgentCopyManifestItem> {
        let (data, status) = try await request(
            "/v1/agents/\(id.uuidString.lowercased())/items?after=\(after)&limit=5000", limit: Self.pageLimit,
            transfer: true)
        try Self.checkAgentResponse(status, data: data)
        return try JournalCoding.decoder().decode(AgentCopyPage<AgentCopyManifestItem>.self, from: data)
    }
    /// Uploads items and deletions planned with the settings of `revision`, and returns the server's newer versions of
    /// the ones it kept instead. `complete` records that this device's last pass covered every shared entry.
    func uploadAgentItems(_ id: UUID, revision: Int64, items: [AgentCopyUpload], complete: Bool?) async throws
        -> [AgentCopyManifestItem]
    {
        struct Body: Encodable {
            let items: [AgentCopyUpload]
            let complete: Bool?
            let revision: Int64
        }
        struct Result: Decodable { let stale: [AgentCopyManifestItem] }
        let (data, status) = try await request(
            "/v1/agents/\(id.uuidString.lowercased())/items", method: "POST",
            body: json(Body(items: items, complete: complete, revision: revision)), transfer: true)
        try Self.checkAgentResponse(status, data: data)
        return try JournalCoding.decoder().decode(Result.self, from: data).stale
    }

    private static func checkAgentResponse(_ status: Int, data: Data) throws {
        guard !(200..<300).contains(status) else { return }
        switch (status, problemCode(data)) {
        case (409, "agent_limit"): throw AgentCopyError.limit
        case (409, "agent_expired"): throw AgentCopyError.expired
        case (409, "agent_quota"): throw AgentCopyError.quota
        case (409, "agent_request_mismatch"): throw AgentCopyError.numberMismatch
        case (409, "agent_settings_changed"): throw AgentCopyError.settingsChanged
        case (404, "agent_not_found"): throw AgentCopyError.notFound
        case (404, "agent_request_not_found"): throw AgentCopyError.requestNotFound
        // Servers without the capability don't know these routes.
        case (404, _), (405, _): throw AgentCopyError.serverOutdated
        default: throw AgentCopyError.failed
        }
    }
}
