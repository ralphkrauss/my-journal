import CryptoKit
import Foundation
import JournalCore

/// End-to-end check of agent access through the server's MCP endpoint (protocol/agent-access-server.md), run by
/// scripts/test-sync.sh against a disposable server:
/// - `agent-connect <address> <setup-code file> <state directory>`: a device sets up the server, syncs two journals and
///   approves a scripted OAuth client (registration, authorization page, number, PKCE, token) for one of them. The client
///   then lists, searches and reads over MCP in both protocol eras, and a synchronized edit reaches it. The access token
///   is left in the state directory for the MCP Inspector and the conformance suite.
/// - `agent-revoke <address> <state directory>`: the device revokes the agent, which can then read nothing.
extension Probe {
    private struct AgentProbeState: Codable {
        var deviceToken: String
        var grantID: UUID
        var accessToken: String
    }

    static func runAgentProbe() async throws -> Bool {
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch (arguments.first, arguments.count) {
        case ("agent-connect", 4):
            try await agentConnect(
                address: arguments[1], setupCodeFile: arguments[2], state: URL(fileURLWithPath: arguments[3]))
        case ("agent-revoke", 3):
            try await agentRevoke(address: arguments[1], state: URL(fileURLWithPath: arguments[2]))
        default:
            return false
        }
        return true
    }

    private static func agentConnect(address: String, setupCodeFile: String, state: URL) async throws {
        let code = try String(contentsOfFile: setupCodeFile).trimmingCharacters(in: .whitespacesAndNewlines)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("journal-agent-probe-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (master, _, envelope, recoverySecret) = try recoveryFixture()
        let grant = try await ServerClient(address: address).initialize(
            code: code, envelope: envelope, recoverySecret: recoverySecret, deviceName: "Probe Mac")
        let device = try ServerClient(address: address, token: grant.token)
        let store = try JournalStore(directory: root, key: master)
        let sync = SyncEngine(store: store, client: device)
        let shared = JournalItem(kind: "journal", title: "Shared work")
        let unshared = JournalItem(kind: "journal", title: "Private thoughts")
        var entry = JournalItem(
            kind: "entry", journalID: shared.id, title: "Planning", document: .plain("First version of the café plan"))
        let secret = JournalItem(
            kind: "entry", journalID: unshared.id, title: "Secret", document: .plain("Never shared"))
        for item in [shared, unshared, entry, secret] { try await store.save(item) }
        try await sync.synchronize()
        let status = try await device.status()
        guard let mcpURL = status.mcpUrl, let mcp = URL(string: mcpURL) else {
            throw ProbeFailure("the server didn't report an MCP address")
        }
        var agent = try OAuthProbeClient(mcp: mcp)
        try await agent.register()
        let page = try await agent.openAuthorizationPage()
        let publisher = AgentCopyPublisher(store: store, client: device)
        guard let waiting = try await device.agentRequests().first else {
            throw ProbeFailure("the request didn't appear on the device")
        }
        let request = try await device.agentRequest(waiting.id)
        guard request.clientName == "Probe Agent", request.returnsToLoopback else {
            throw ProbeFailure("the device saw a different client than the one that asked")
        }
        let approved = Date()
        let grantID = try await publisher.approve(
            request, number: page.number, name: "Probe agent", allJournals: false, journalIDs: [shared.id],
            expiresAt: nil)
        await publisher.waitForFirstCopy(grantID)
        // The page sends the agent back once the device reports its first copy, not when the server stops waiting.
        let readyAfter = Date().timeIntervalSince(approved)
        guard readyAfter < AgentCopyPublisher.firstCopyWait / 3 else {
            throw ProbeFailure("the agent waited \(Int(readyAfter)) s for a small first copy")
        }
        try await agent.redeem(handle: page.handle)
        print("PASS: an OAuth client registers, is approved with its page's number on a device and receives tokens")
        print("PASS: an approved agent is sent back as soon as its first copy is uploaded")
        // Merging another device's journals never combines them into a journal an agent reads
        // (docs/design/join-with-local-journals.md), so a device joining must learn which ones those are.
        let readByAgents = try await device.journalsAgentsCanRead(vaultKey: master)
        let unreadable = try await device.journalsAgentsCanRead(
            vaultKey: try VaultCrypto.generateKey())
        guard readByAgents == [shared.id], unreadable == nil else {
            throw ProbeFailure("a joining device can't tell which journals agents read")
        }
        print("PASS: a device joining can tell which journals agents read")

        let journals = try await agent.callTool("list_journals", [:])
        guard journals.contains("Shared work"), !journals.contains("Private thoughts") else {
            throw ProbeFailure("list_journals didn't return exactly the shared journal")
        }
        guard try await agent.callTool("search_entries", ["query": "CAFE"]).contains("Planning"),
            try await agent.callTool("search_entries", ["query": "Never"]).contains("\"entries\":[]"),
            try await agent.callTool("read_entry", ["entry_id": secret.id.uuidString]).hasPrefix("Not found")
        else { throw ProbeFailure("the agent could read outside the shared journal") }
        guard try await agent.callToolLegacy("read_entry", ["entry_id": entry.id.uuidString]).contains("café plan")
        else { throw ProbeFailure("a 2025-11-25 client couldn't read the shared entry") }
        print("PASS: the agent lists, searches and reads only the shared journal, in both protocol eras")

        entry.document = .plain("Second version after sync")
        try await store.save(entry)
        try await sync.synchronize()
        try await publisher.publishNow()
        guard try await agent.callTool("read_entry", ["entry_id": entry.id.uuidString]).contains("Second version")
        else { throw ProbeFailure("a synchronized edit didn't reach the agent's copy") }
        print("PASS: a synchronized edit reaches the agent")

        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        let saved = AgentProbeState(
            deviceToken: grant.token, grantID: try await publisher.list()[0].id, accessToken: agent.accessToken)
        try JournalCoding.encoder().encode(saved).write(to: state.appendingPathComponent("state.json"))
        try Data(agent.accessToken.utf8).write(to: state.appendingPathComponent("access-token"))
        try Data(mcpURL.utf8).write(to: state.appendingPathComponent("mcp-url"))
    }

    private static func agentRevoke(address: String, state: URL) async throws {
        let saved = try JournalCoding.decoder().decode(
            AgentProbeState.self, from: Data(contentsOf: state.appendingPathComponent("state.json")))
        let device = try ServerClient(address: address, token: saved.deviceToken)
        try await device.revokeAgent(saved.grantID)
        guard let mcpURL = try await device.status().mcpUrl, let mcp = URL(string: mcpURL) else {
            throw ProbeFailure("the server didn't report an MCP address")
        }
        var agent = try OAuthProbeClient(mcp: mcp)
        agent.accessToken = saved.accessToken
        guard try await agent.statusOfToolsList() == 401, try await device.agents().isEmpty else {
            throw ProbeFailure("a revoked agent could still read")
        }
        print("PASS: revoking stops the agent and removes it")
    }
}

/// A minimal OAuth 2.1 and MCP client, doing what a generic MCP client does: dynamic registration, PKCE, the
/// authorization page, the token exchange and Streamable HTTP requests.
struct OAuthProbeClient {
    let mcp: URL
    let origin: String
    let redirect = "http://127.0.0.1:45678/callback"
    let verifier = "probe-verifier-" + UUID().uuidString + UUID().uuidString
    var clientID = ""
    var accessToken = ""
    private let session: URLSession

    init(mcp: URL) throws {
        self.mcp = mcp
        guard let scheme = mcp.scheme, let host = mcp.host else { throw ProbeFailure("invalid MCP address") }
        origin = scheme + "://" + host + (mcp.port.map { ":\($0)" } ?? "")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration, delegate: NoFollow(), delegateQueue: nil)
    }

    private final class NoFollow: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
        ) { completionHandler(nil) }
    }

    mutating func register() async throws {
        var request = URLRequest(url: try url("/oauth/register"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_name": "Probe Agent", "redirect_uris": [redirect], "token_endpoint_auth_method": "none",
        ])
        let (data, _) = try await session.data(for: request)
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = body["client_id"] as? String
        else { throw ProbeFailure("registration failed") }
        clientID = id
    }

    private func url(_ path: String) throws -> URL {
        guard let url = URL(string: origin + path) else { throw ProbeFailure("invalid server address") }
        return url
    }

    var challenge: String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    func openAuthorizationPage() async throws -> (number: Int, handle: String) {
        guard var components = URLComponents(url: try url("/oauth/authorize"), resolvingAgainstBaseURL: false) else {
            throw ProbeFailure("invalid authorization address")
        }
        components.queryItems = [
            .init(name: "response_type", value: "code"), .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect), .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "state", value: "probe"),
            .init(name: "resource", value: mcp.absoluteString),
        ]
        guard let authorize = components.url else { throw ProbeFailure("invalid authorization address") }
        let (data, _) = try await session.data(from: authorize)
        let page = String(decoding: data, as: UTF8.self)
        let numberRange = page.range(of: #"class="number">[0-9]{2}<"#, options: .regularExpression)
        let handleRange = page.range(of: #"data-handle="[0-9a-f]{64}""#, options: .regularExpression)
        guard let numberRange, let handleRange, let number = Int(page[numberRange].dropLast().suffix(2)) else {
            throw ProbeFailure("the authorization page showed no number")
        }
        let handle = String(page[handleRange].dropLast().suffix(64))
        return (number, handle)
    }

    mutating func redeem(handle: String) async throws {
        let (data, _) = try await session.data(from: try url("/oauth/authorize/status?handle=" + handle))
        guard let status = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let redirectTo = status["redirect"] as? String, let components = URLComponents(string: redirectTo),
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
            components.queryItems?.first(where: { $0.name == "iss" })?.value == origin,
            components.queryItems?.first(where: { $0.name == "state" })?.value == "probe"
        else { throw ProbeFailure("the authorization page didn't return a code with the issuer and state") }
        var request = URLRequest(url: try url("/oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            .init(name: "grant_type", value: "authorization_code"), .init(name: "code", value: code),
            .init(name: "redirect_uri", value: redirect), .init(name: "client_id", value: clientID),
            .init(name: "code_verifier", value: verifier), .init(name: "resource", value: mcp.absoluteString),
        ]
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        let (tokens, _) = try await session.data(for: request)
        guard let body = try JSONSerialization.jsonObject(with: tokens) as? [String: Any],
            let token = body["access_token"] as? String
        else { throw ProbeFailure("the token exchange failed") }
        accessToken = token
    }

    /// A 2026-07-28 tools/call; returns the result's text.
    func callTool(_ name: String, _ arguments: [String: Any]) async throws -> String {
        let body: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": [
                "name": name, "arguments": arguments,
                "_meta": [
                    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
                    "io.modelcontextprotocol/clientCapabilities": [:],
                ],
            ],
        ]
        let headers = ["MCP-Protocol-Version": "2026-07-28", "Mcp-Method": "tools/call", "Mcp-Name": name]
        return try await text(post(body, headers: headers))
    }

    /// A 2025-11-25 tools/call, as clients that use the handshake send it.
    func callToolLegacy(_ name: String, _ arguments: [String: Any]) async throws -> String {
        let body: [String: Any] = [
            "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": name, "arguments": arguments],
        ]
        return try await text(post(body, headers: ["MCP-Protocol-Version": "2025-11-25"]))
    }

    func statusOfToolsList() async throws -> Int {
        let body: [String: Any] = [
            "jsonrpc": "2.0", "id": 3, "method": "tools/list",
            "params": [
                "_meta": [
                    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
                    "io.modelcontextprotocol/clientCapabilities": [:],
                ]
            ],
        ]
        return try await post(body, headers: ["MCP-Protocol-Version": "2026-07-28", "Mcp-Method": "tools/list"]).1
    }

    private func post(_ body: [String: Any], headers: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: mcp)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func text(_ response: (Data, Int)) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: response.0) as? [String: Any],
            let result = object["result"] as? [String: Any], let content = result["content"] as? [[String: Any]],
            let text = content.first?["text"] as? String
        else { throw ProbeFailure("the MCP endpoint sent an invalid tool reply (HTTP \(response.1))") }
        return text
    }
}
