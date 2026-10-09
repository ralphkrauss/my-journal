import Foundation
import JournalCore
import os

@testable import Journal

/// A journal server in memory over loopback HTTP, for what encrypting an unencrypted library asks of it: its public
/// encryption details, whether it can switch, access, the log, and the switch itself (`/v1/recovery/encrypt`) in the
/// ways it can go wrong. It records every request.
final class EncryptionServer {
    /// How the server answers the request to switch to encryption.
    enum Switch {
        /// It switches and says so.
        case switches
        /// It switches, but the answer is lost (a server error): only its envelope tells.
        case switchesButFails
        /// It says yes but keeps its envelope: it never switched.
        case acceptsWithoutSwitching
        /// Another device encrypted it first.
        case alreadyEncrypted
        /// Another device wrote since the position sent.
        case serverChanged
        /// It doesn't answer until `release()`.
        case hangs
    }
    struct State {
        var parameters = RecoveryParameters(.unprotected)
        var features = ["encryption-upgrade"]
        var refusesDevices = false
        /// Tokens that were revoked (the purge revokes every device but the one that switched); everything
        /// authenticated with one is refused.
        var revokedTokens: Set<String> = []
        /// Answers a device's request to sign in with the password (a server that published its envelope).
        var grantsRecovery = false
        var switchMode = Switch.switches
        /// Called on the server's queue as it switches, for a test to change the disk under the app meanwhile.
        var onSwitch: (@Sendable () -> Void)?
        /// Requests to these paths wait for `release()` (GET /v1/recovery, sync pages).
        var hangingPrefixes: [String] = []
        var log: [RemoteChange] = []
        var serverID = "server-one"
        /// Images by path, as uploaded.
        var attachments: [String: Data] = [:]
    }
    let state = OSAllocatedUnfairLock(initialState: State())
    private let gate = DispatchSemaphore(value: 0)
    private var server: FakeJournalServer?

    static func start(_ configure: @Sendable (inout State) -> Void = { _ in }) async throws -> EncryptionServer {
        let result = EncryptionServer()
        result.state.withLock { configure(&$0) }
        let gate = result.gate
        result.server = try await FakeJournalServer { [state = result.state] request in
            let hang = state.withLock { state in
                state.hangingPrefixes.contains { request.path.hasPrefix($0) }
                    || (request.path == "/v1/recovery/encrypt" && state.switchMode == .hangs)
            }
            if hang { gate.wait() }
            return state.withLock { Self.answer(request, state: &$0) }
        }
        return result
    }
    var address: String { server?.address ?? "" }
    var requests: [FakeJournalServer.Request] { server?.requests ?? [] }
    func update(_ change: @Sendable (inout State) -> Void) { state.withLock { change(&$0) } }
    /// Lets every waiting request go, and any later one.
    func release() {
        update {
            $0.hangingPrefixes = []
            if $0.switchMode == .hangs { $0.switchMode = .switchesButFails }
        }
        for _ in 0..<8 { gate.signal() }
    }
    func count(_ method: String, _ path: String) -> Int {
        requests.filter { $0.method == method && $0.path.hasPrefix(path) }.count
    }

    private static func answer(_ request: FakeJournalServer.Request, state: inout State) -> (status: Int, body: Data) {
        let json = { (text: String) in Data(text.utf8) }
        switch (request.method, request.path) {
        case ("GET", "/v1/status"):
            let features = state.features.map { "\"\($0)\"" }.joined(separator: ",")
            return (
                200,
                json(
                    #"{"protocolVersion":1,"initialized":true,"recoveryVersions":[1,2,3,4],"features":[\#(features)],"serverId":"\#(state.serverID)"}"#
                )
            )
        case ("GET", "/v1/recovery"): return (200, (try? JournalCoding.encoder().encode(state.parameters)) ?? Data())
        case ("POST", "/v1/recovery/encrypt"): return switchEncryption(request, state: &state)
        case ("POST", "/v1/recovery") where state.grantsRecovery:
            // A device that knows the password gets new access, as a server that published its envelope gives it.
            let grant = DeviceGrant(deviceId: UUID(), token: String(repeating: "g", count: 64))
            return (200, (try? JournalCoding.encoder().encode(grant)) ?? Data())
        case ("DELETE", _): return (204, Data())
        case ("HEAD", let path) where path.hasPrefix("/v1/attachments/"):
            return (state.attachments[path] == nil ? 404 : 200, Data())
        case ("GET", let path) where path.hasPrefix("/v1/attachments/"):
            return state.attachments[path].map { (200, $0) } ?? (404, Data())
        case ("PUT", let path) where path.hasPrefix("/v1/attachments/"):
            state.attachments[path] = request.body
            return (200, Data())
        case (_, _) where state.refusesDevices || state.revokedTokens.contains(Self.token(of: request)):
            return (401, json(#"{"code":"unauthorized"}"#))
        case ("GET", "/v1/devices/"): return (200, json("[]"))
        case ("GET", let path) where path.hasPrefix("/v1/sync/?"): return (200, page(path, state: state))
        case ("PUT", let path) where path.hasPrefix("/v1/sync/"): return accept(request, state: &state)
        default: return (503, json("{}"))
        }
    }
    private static func token(of request: FakeJournalServer.Request) -> String {
        request.authorization.replacingOccurrences(of: "Bearer ", with: "")
    }
    private static func switchEncryption(
        _ request: FakeJournalServer.Request, state: inout State
    ) -> (status: Int, body: Data) {
        struct Body: Decodable {
            let salt: String
            let wrappedKey: String
            let iterations: Int
        }
        func switched() {
            guard let body = try? JournalCoding.decoder().decode(Body.self, from: request.body) else { return }
            state.parameters = RecoveryParameters(
                salt: body.salt, iterations: body.iterations, formatVersion: 2, wrappedKey: nil)
            // The real server purges its records and images as it re-keys; the device sends everything again.
            state.log = []
            state.attachments = [:]
            state.onSwitch?()
        }
        switch state.switchMode {
        case .switches, .hangs:
            switched()
            return (200, Data(#"{"serverId":"server-two"}"#.utf8))
        case .switchesButFails:
            switched()
            return (500, Data("{}".utf8))
        case .acceptsWithoutSwitching:
            state.onSwitch?()
            return (200, Data(#"{"serverId":"server-two"}"#.utf8))
        case .alreadyEncrypted: return (409, Data(#"{"code":"already_encrypted"}"#.utf8))
        case .serverChanged: return (409, Data(#"{"code":"server_changed"}"#.utf8))
        }
    }
    private static func page(_ path: String, state: State) -> Data {
        let after =
            URLComponents(string: path)?.queryItems?.first { $0.name == "after" }?.value.flatMap(Int64.init) ?? 0
        let changes = state.log.filter { $0.cursor > after }
        struct Page: Encodable {
            let changes: [RemoteChange]
            let cursor: Int64
            let hasMore: Bool
            let serverId: String
            let serverIdCursor: Int64
        }
        let page = Page(
            changes: changes, cursor: changes.last?.cursor ?? after, hasMore: false, serverId: state.serverID,
            serverIdCursor: 0)
        return (try? JournalCoding.encoder().encode(page)) ?? Data()
    }
    private static func accept(_ request: FakeJournalServer.Request, state: inout State) -> (status: Int, body: Data) {
        struct Push: Decodable {
            let baseRevision: Int64
            let kind: String
            let payload: String
        }
        guard let push = try? JournalCoding.decoder().decode(Push.self, from: request.body),
            let id = UUID(uuidString: String(request.path.dropFirst("/v1/sync/".count)))
        else { return (400, Data()) }
        let change = RemoteChange(
            cursor: Int64(state.log.count + 1), recordId: id, revision: push.baseRevision + 1, kind: push.kind,
            payload: push.payload, deviceId: UUID(), modifiedAt: Date())
        state.log.append(change)
        return (200, (try? JournalCoding.encoder().encode(change)) ?? Data())
    }
}
