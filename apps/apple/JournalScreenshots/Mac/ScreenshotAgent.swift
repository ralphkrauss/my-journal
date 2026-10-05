import CryptoKit
import Foundation

/// "Writing Assistant", the agent of Mac frame 4: a minimal OAuth and MCP client doing what a generic MCP client does
/// (dynamic registration, the authorization page, PKCE, the token exchange and tool calls), as the probe client in
/// Packages/JournalCore/Sources/JournalProbe/AgentProbe.swift does.
struct ScreenshotAgent {
    static let clientName = "Writing Assistant"
    let server: PublicHostConnection
    let redirect = "http://127.0.0.1:45678/callback"
    let verifier = "screenshot-verifier-" + UUID().uuidString + UUID().uuidString
    private(set) var clientID = ""
    private(set) var accessToken = ""

    /// The MCP resource, named by the server's public address.
    var resource: String { server.origin + "/mcp" }

    private var challenge: String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    mutating func register() async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "client_name": Self.clientName, "redirect_uris": [redirect], "token_endpoint_auth_method": "none",
        ])
        let response = try await server.send(
            "POST", "/oauth/register", headers: ["Content-Type": "application/json"], body: body)
        guard let object = try JSONSerialization.jsonObject(with: response.body) as? [String: Any],
            let id = object["client_id"] as? String
        else { throw CaptureError("The agent's registration failed (HTTP \(response.status)).") }
        clientID = id
    }

    /// Opens the page an agent shows the person: it starts the request and shows the number to enter in My Journal.
    func openAuthorizationPage() async throws -> (number: Int, handle: String) {
        var components = URLComponents()
        components.queryItems = [
            .init(name: "response_type", value: "code"), .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect), .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "state", value: "screenshot"),
            .init(name: "resource", value: resource),
        ]
        let response = try await server.send("GET", "/oauth/authorize?" + (components.percentEncodedQuery ?? ""))
        let page = String(decoding: response.body, as: UTF8.self)
        let numberRange = page.range(of: #"class="number">[0-9]+<"#, options: .regularExpression)
        let handleRange = page.range(of: #"data-handle="[0-9a-f]+""#, options: .regularExpression)
        guard let numberRange, let handleRange, let number = Int(page[numberRange].filter(\.isNumber)) else {
            throw CaptureError("The authorization page showed no number (HTTP \(response.status)).")
        }
        let handle = page[handleRange].dropFirst("data-handle=\"".count).dropLast()
        return (number, String(handle))
    }

    /// Waits until the page sends the agent back, which happens once its first copy is uploaded, then exchanges the
    /// code for an access token.
    mutating func redeem(handle: String, timeout: TimeInterval = 120) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let response = try await server.send("GET", "/oauth/authorize/status?handle=" + handle)
            let status = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
            if let destination = status?["redirect"] as? String {
                return try await exchange(destination)
            }
            try await Task.sleep(nanoseconds: 1_500_000_000)
        }
        throw CaptureError("The agent wasn't sent back in time.")
    }

    private mutating func exchange(_ destination: String) async throws {
        guard let components = URLComponents(string: destination),
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
            components.queryItems?.first(where: { $0.name == "iss" })?.value == server.origin,
            components.queryItems?.first(where: { $0.name == "state" })?.value == "screenshot"
        else { throw CaptureError("The agent was sent back without a code, issuer and state.") }
        var form = URLComponents()
        form.queryItems = [
            .init(name: "grant_type", value: "authorization_code"), .init(name: "code", value: code),
            .init(name: "redirect_uri", value: redirect), .init(name: "client_id", value: clientID),
            .init(name: "code_verifier", value: verifier), .init(name: "resource", value: resource),
        ]
        let response = try await server.send(
            "POST", "/oauth/token", headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: Data((form.percentEncodedQuery ?? "").utf8))
        guard let body = try JSONSerialization.jsonObject(with: response.body) as? [String: Any],
            let token = body["access_token"] as? String
        else { throw CaptureError("The token exchange failed (HTTP \(response.status)).") }
        accessToken = token
    }

    /// A 2026-07-28 tools/call; returns the result's text.
    func callTool(_ name: String, _ arguments: [String: Any]) async throws -> String {
        let request: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": [
                "name": name, "arguments": arguments,
                "_meta": [
                    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
                    "io.modelcontextprotocol/clientCapabilities": [:],
                ],
            ],
        ]
        let headers = [
            "Content-Type": "application/json", "Accept": "application/json, text/event-stream",
            "Authorization": "Bearer " + accessToken, "MCP-Protocol-Version": "2026-07-28", "Mcp-Method": "tools/call",
            "Mcp-Name": name,
        ]
        let response = try await server.send(
            "POST", "/mcp", headers: headers, body: try JSONSerialization.data(withJSONObject: request))
        guard let object = try JSONSerialization.jsonObject(with: response.body) as? [String: Any],
            let result = object["result"] as? [String: Any], let content = result["content"] as? [[String: Any]],
            let text = content.first?["text"] as? String
        else { throw CaptureError("\(name) sent an invalid reply (HTTP \(response.status)).") }
        return text
    }
}

/// HTTP requests to the disposable server on its loopback port, for the host name of its public address. A server
/// with a public address answers agents only for that host (PublicOrigin.RequestHostMatches), and URLSession doesn't
/// let a request choose its Host header, so these are written on a plain connection.
struct PublicHostConnection {
    let port: Int
    let publicHost: String

    /// The server's public origin, which names its MCP resource and OAuth issuer.
    var origin: String { "https://" + publicHost }

    init(loopbackAddress: String, publicURL: String) throws {
        guard let port = URL(string: loopbackAddress)?.port, let host = URL(string: publicURL)?.host else {
            throw CaptureError("Invalid server address \(loopbackAddress) or public address \(publicURL).")
        }
        self.port = port
        publicHost = host
    }

    func send(_ method: String, _ path: String, headers: [String: String] = [:], body: Data? = nil) async throws
        -> (status: Int, body: Data)
    {
        var head = "\(method) \(path) HTTP/1.1\r\nHost: \(publicHost)\r\nConnection: close\r\n"
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        head += "Content-Length: \(body?.count ?? 0)\r\n\r\n"
        var request = Data(head.utf8)
        if let body { request.append(body) }
        let task = URLSession.shared.streamTask(withHostName: "127.0.0.1", port: port)
        task.resume()
        defer { task.cancel() }
        try await task.write(request, timeout: 30)
        var response = Data()
        var finished = false
        while !finished {
            let (chunk, atEnd) = try await task.readData(ofMinLength: 1, maxLength: 65_536, timeout: 30)
            if let chunk { response.append(chunk) }
            finished = atEnd
        }
        return try Self.parse(response)
    }

    /// The status and body of an HTTP/1.1 response that ends with the connection.
    static func parse(_ response: Data) throws -> (status: Int, body: Data) {
        guard let end = response.range(of: Data("\r\n\r\n".utf8)) else {
            throw CaptureError("The server sent no complete response.")
        }
        let lines = String(decoding: response[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let statusLine = lines.first?.split(separator: " ") ?? []
        guard statusLine.count >= 2, let status = Int(statusLine[1]) else {
            throw CaptureError("The server sent an invalid status line.")
        }
        let body = Data(response[end.upperBound...])
        let chunked = lines.dropFirst().contains {
            $0.lowercased().hasPrefix("transfer-encoding:") && $0.lowercased().contains("chunked")
        }
        return (status, chunked ? try dechunk(body) : body)
    }

    private static func dechunk(_ data: Data) throws -> Data {
        var output = Data()
        var index = data.startIndex
        let lineEnd = Data("\r\n".utf8)
        while let sizeEnd = data.range(of: lineEnd, in: index..<data.endIndex) {
            let sizeText = String(decoding: data[index..<sizeEnd.lowerBound], as: UTF8.self)
            let digits = sizeText.split(separator: ";").first.map(String.init) ?? ""
            guard let size = Int(digits.trimmingCharacters(in: .whitespaces), radix: 16) else {
                throw CaptureError("The server sent an invalid chunk.")
            }
            if size == 0 { return output }
            let start = sizeEnd.upperBound
            guard data.distance(from: start, to: data.endIndex) >= size else {
                throw CaptureError("The server sent an incomplete chunk.")
            }
            let stop = data.index(start, offsetBy: size)
            output.append(data[start..<stop])
            index = data.index(stop, offsetBy: lineEnd.count, limitedBy: data.endIndex) ?? data.endIndex
        }
        throw CaptureError("The server's response ended early.")
    }
}
