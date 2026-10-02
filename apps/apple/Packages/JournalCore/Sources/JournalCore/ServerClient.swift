import CryptoKit
import Foundation

public struct DeviceGrant: Codable, Sendable {
    public var deviceId: UUID
    public var token: String
    public init(deviceId: UUID, token: String) {
        self.deviceId = deviceId
        self.token = token
    }
}
public struct ServerStatus: Codable, Sendable {
    public var protocolVersion: Int
    public var initialized: Bool
    public var recoveryVersions: [Int]?
    /// Additive protocol v1 capabilities. Older servers omit this.
    public var features: [String]?
    /// Random identity of the server database, replaced when a backup is restored. Older servers omit this.
    public var serverId: String?
    /// The MCP address agents connect to (capability `agent-access`), or nil with the reason in `mcpUnavailable`:
    /// "https-required" or "public-url-required".
    public var mcpUrl: String?
    public var mcpUnavailable: String?
    public func supports(_ feature: String) -> Bool { features?.contains(feature) == true }
}
public struct ServerDevice: Codable, Identifiable, Sendable {
    /// How a device joined the server.
    public enum Origin: Equatable, Sendable {
        /// It set up the server.
        case setup
        /// With the library's password, recovery key or the server's recovery code.
        case recovery
        /// Approved on another device, which `approvedByDeviceId` names when the server knows it.
        case pairing
        /// An older server doesn't say, or a newer one uses a value this version doesn't know.
        case unknown
    }
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var revoked: Bool
    /// "setup", "recovery" or "pairing". Older servers leave it out.
    public var createdVia: String?
    /// The device that approved this one's pairing, if any. Older servers leave it out.
    public var approvedByDeviceId: UUID?
    public var origin: Origin {
        switch createdVia {
        case "setup": return .setup
        case "recovery": return .recovery
        case "pairing": return .pairing
        default: return .unknown
        }
    }
    public init(
        id: UUID, name: String, createdAt: Date, revoked: Bool, createdVia: String? = nil,
        approvedByDeviceId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.revoked = revoked
        self.createdVia = createdVia
        self.approvedByDeviceId = approvedByDeviceId
    }
    private enum CodingKeys: String, CodingKey { case id, name, createdAt, revoked, createdVia, approvedByDeviceId }
    /// How a device was added only adds detail: a missing, null or unreadable value never hides the device list.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        revoked = try container.decode(Bool.self, forKey: .revoked)
        createdVia = try? container.decodeIfPresent(String.self, forKey: .createdVia)
        approvedByDeviceId = try? container.decodeIfPresent(UUID.self, forKey: .approvedByDeviceId)
    }
}
/// A new device credential and the vault key recovered with a password or recovery key.
public struct RecoveredVault: Sendable {
    public let grant: DeviceGrant
    /// The server's whole recovery envelope, which wraps `key`.
    public let envelope: RecoveryEnvelope
    public let key: Data
}
/// The server accepted the recovery secret but sent an envelope other than the one it published, or one that the
/// password doesn't open. The new device credential was given up.
public struct RecoveryEnvelopeChanged: Error {}
public struct SyncPage: Codable, Sendable {
    public var changes: [RemoteChange]
    public var cursor: Int64
    public var hasMore: Bool
    public var serverId: String?
    /// Changes at or below this cursor existed when the server identity was assigned.
    public var serverIdCursor: Int64?
}
public struct SyncConnection: Codable, Sendable {
    public var address: String
    public var deviceID: UUID
    public var token: String
    public init(address: String, deviceID: UUID, token: String) {
        self.address = address
        self.deviceID = deviceID
        self.token = token
    }
}
/// A rate-limited request. Callers that poll wait and try again instead of failing.
public struct ServerRateLimited: Error, LocalizedError {
    public var retryAfter: TimeInterval?
    public init(retryAfter: TimeInterval? = nil) { self.retryAfter = retryAfter }
    public var errorDescription: String? { "Too many attempts. Try again in a few minutes." }
}
/// The server didn't accept one record or image as it is. Sending it again unchanged won't help, but the
/// server didn't apply it either, so other changes can continue.
public struct SyncRejection: Error, Sendable {
    public enum Reason: Sendable { case tooLarge, invalid }
    public let reason: Reason
}
/// A response larger than this client reads, for example from a faulty server. Any request can receive one, so the
/// message doesn't name what was being done.
public struct ResponseTooLarge: Error, LocalizedError {
    public var errorDescription: String? { "The server sent more data than expected." }
}
/// The server doesn't have the change this device last read at its cursor, so its data was replaced, for example by
/// copying back an older data folder (protocol/README.md, capability `sync-continuity`).
public struct SyncLogChanged: Error {}
/// The change at a position of the server's log. A server with the `sync-continuity` capability confirms it still has
/// this change there before reading on from it; one with `sync-continuity-digest` also confirms its payload `digest`
/// (lower-case hex SHA-256 of the payload text), since a rolled-back server can give the same record and revision to
/// another version.
public struct LoggedChange: Codable, Sendable, Equatable {
    public var recordId: UUID
    public var revision: Int64
    public var digest: String?
    public init(recordId: UUID, revision: Int64, digest: String? = nil) {
        self.recordId = recordId
        self.revision = revision
        self.digest = digest
    }
}
extension LoggedChange {
    init(_ change: RemoteChange) {
        self.init(
            recordId: change.recordId, revision: change.revision, digest: JournalStore.payloadDigest(change.payload))
    }
}
private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) { completionHandler(nil) }
}
public final class ServerClient: Sendable {
    public let address: URL
    private let token: String?
    private let session: URLSession
    /// Images can take longer than other requests on a slow connection, as long as data keeps arriving.
    private let transferSession: URLSession
    /// The most a response to a small request may contain.
    static let responseLimit = 1024 * 1024
    /// The most a page of changes may contain; a smaller page is requested when one is larger.
    static let pageLimit = 64 * 1024 * 1024
    /// The most a push response may contain: it repeats one record of at most 4 MiB, encoded as text.
    static let pushResponseLimit = 16 * 1024 * 1024
    /// A record this large is sent with the time an image transfer gets, since a slow connection needs longer.
    static let largeRecord = 256 * 1024
    public init(address: String, token: String? = nil) throws {
        guard let url = URL(string: address), let host = url.host, !host.isEmpty,
            url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
            url.scheme == "https"
                || (url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host))
        else { throw JournalError.invalidAddress }
        self.address = url
        self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 120
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        let transfers = URLSessionConfiguration.ephemeral
        transfers.timeoutIntervalForRequest = 20
        transfers.timeoutIntervalForResource = 15 * 60
        transfers.urlCache = nil
        transferSession = URLSession(configuration: transfers, delegate: NoRedirects(), delegateQueue: nil)
    }
    deinit {
        session.invalidateAndCancel()
        transferSession.invalidateAndCancel()
    }
    func request(
        _ path: String, method: String = "GET", body: Data? = nil, binary: Bool = false,
        limit: Int = responseLimit, transfer: Bool = false, using override: URLSession? = nil
    ) async throws -> (Data, Int) {
        guard
            let url = URL(string: address.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path)
        else { throw JournalError.invalidAddress }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if body != nil {
            request.setValue(
                binary ? "application/octet-stream" : "application/json", forHTTPHeaderField: "Content-Type")
        }
        let (bytes, response) = try await (override ?? (transfer ? transferSession : session)).bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            bytes.task.cancel()
            throw JournalError.invalidData
        }
        if response.statusCode == 401 {
            let problem = try? await Self.read(
                bytes, expected: response.expectedContentLength, limit: Self.problemLimit)
            throw Self.refusal(problem.flatMap(Self.problemCode), path: path)
        }
        if response.statusCode == 429 {
            bytes.task.cancel()
            throw ServerRateLimited(
                retryAfter: response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init))
        }
        return (try await Self.read(bytes, expected: response.expectedContentLength, limit: limit), response.statusCode)
    }
    /// Reads a response body, stopping as soon as it exceeds `limit` instead of holding whatever a server sends.
    private static func read(_ bytes: URLSession.AsyncBytes, expected: Int64, limit: Int) async throws -> Data {
        guard expected <= Int64(limit) else {
            bytes.task.cancel()
            throw ResponseTooLarge()
        }
        var body: [UInt8] = []
        body.reserveCapacity(Int(max(0, expected)))
        for try await byte in bytes {
            guard body.count < limit else {
                bytes.task.cancel()
                throw ResponseTooLarge()
            }
            body.append(byte)
        }
        return Data(body)
    }
    /// The most an error body is read for its reason.
    private static let problemLimit = 16 * 1024
    /// The stable reason in an error response's problem details (protocol/README.md, Errors). Servers from before
    /// problem details send none, so callers then decide by the status alone.
    static func problemCode(_ data: Data) -> String? {
        struct Problem: Decodable { var code: String? }
        return (try? JSONDecoder().decode(Problem.self, from: data))?.code
    }
    /// Why a request was refused as unauthorized. Setup and recovery send no device credential, so their refusal is
    /// about the code or password typed, never this device's access, even from servers that send no reason.
    private static func refusal(_ code: String?, path: String) -> Error {
        let legacy = [
            "/v1/setup": "invalid_setup_code", "/v1/setup/check": "invalid_setup_code",
            "/v1/recovery": "invalid_recovery_secret",
        ]
        switch code ?? legacy[path] {
        case "invalid_setup_code": return JournalError.invalidSetupCode
        case "invalid_recovery_secret": return JournalError.invalidRecoveryKey
        default: return JournalError.unauthorized
        }
    }
    func call<T: Decodable>(
        _ path: String, method: String = "GET", body: Data? = nil, limit: Int = responseLimit,
        using override: URLSession? = nil
    ) async throws -> T {
        let (data, status) = try await request(path, method: method, body: body, limit: limit, using: override)
        guard (200..<300).contains(status) else {
            // A malformed code, such as one from a newer or older server's format, is still a wrong code.
            if status == 400 && path == "/v1/setup" && Self.problemCode(data) == "invalid_setup_code" {
                throw JournalError.invalidSetupCode
            }
            throw Self.failure(status: status, path: path)
        }
        return try JournalCoding.decoder().decode(T.self, from: data)
    }
    /// A failed request that `request` didn't already explain.
    private static func failure(status: Int, path: String) -> Error {
        if status == 503 && ["/v1/setup", "/v1/setup/check"].contains(path) {
            return JournalError.server("The server has no setup code. Restart the server to create a new one.")
        }
        // Every journal server answers its status; anything else at this address isn't one.
        if path == "/v1/status" && !(500..<600).contains(status) { return SyncFailure(.notJournalServer) }
        return unanswered(status: status)
    }
    /// A request the server didn't answer as expected and that nothing more specific explains.
    static func unanswered(status: Int) -> Error {
        if (500..<600).contains(status) { return ServerUnavailable() }
        return JournalError.server(unansweredMessage)
    }
    static let unansweredMessage = "Couldn’t reach the server. Check the address and your connection, then try again."
    func json<T: Encodable>(_ value: T) throws -> Data { try JournalCoding.encoder().encode(value) }
    public func status() async throws -> ServerStatus { try await call("/v1/status") }
    /// The status of a server this device may not have reached before. For an address on the local network, the
    /// system first asks the person for permission and may refuse the connection while it asks (TN3179), so this
    /// request waits for the connection to become possible, as long as an unresponsive server takes to fail (20
    /// seconds), instead of failing at once.
    public func statusOnFirstContact() async throws -> ServerStatus {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 20
        configuration.urlCache = nil
        let waiting = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { waiting.finishTasksAndInvalidate() }
        return try await call("/v1/status", using: waiting)
    }
    public func initialize(code: String, envelope: RecoveryEnvelope, recoverySecret: String, deviceName: String)
        async throws -> DeviceGrant
    {
        if envelope.formatVersion != 1 {
            let supported = try await status().recoveryVersions ?? [1]
            guard supported.contains(envelope.formatVersion) else {
                throw JournalError.server("Update your server before connecting this journal.")
            }
        }
        struct Setup: Encodable {
            let setupCode: String
            let salt: String
            let wrappedKey: String
            let iterations: Int
            let formatVersion: Int

            let recoverySecret: String
            let deviceName: String
        }
        return try await call(
            "/v1/setup", method: "POST",
            body: json(
                Setup(
                    setupCode: code, salt: envelope.salt, wrappedKey: envelope.wrappedKey,
                    iterations: envelope.iterations, formatVersion: envelope.formatVersion,
                    recoverySecret: recoverySecret, deviceName: deviceName)))
    }
    /// Servers with this capability check a setup code with `checkSetupCode` without using it.
    public static let setupCheckFeature = "setup-check"
    /// Checks a setup code before the person chooses a password, so a wrong one is reported right away. The code
    /// stays valid for `initialize`, and wrong codes count toward the same limit as setup's.
    public func checkSetupCode(_ code: String) async throws {
        struct Check: Encodable { let setupCode: String }
        let path = "/v1/setup/check"
        let (data, status) = try await request(path, method: "POST", body: json(Check(setupCode: code)))
        guard status != 204 else { return }
        if status == 400 && Self.problemCode(data) == "invalid_setup_code" { throw JournalError.invalidSetupCode }
        throw Self.failure(status: status, path: path)
    }
    /// Servers with this capability publish only `RecoveryParameters` and send the wrapped vault key with a new
    /// device credential or to a connected device.
    public static let privateEnvelopeFeature = "private-envelope"
    /// What deriving the recovery secret needs; anyone may read it.
    public func recoveryParameters() async throws -> RecoveryParameters { try await call("/v1/recovery") }
    /// The server's whole recovery envelope, read with this client's device credential. Servers without the
    /// `private-envelope` capability publish it instead.
    public func recoveryEnvelope() async throws -> RecoveryEnvelope {
        guard try await status().supports(Self.privateEnvelopeFeature) else { return try await call("/v1/recovery") }
        return try await call("/v1/recovery/envelope")
    }
    public func recover(secret: String, deviceName: String) async throws -> DeviceGrant {
        try await recoverDevice(secret: secret, deviceName: deviceName).grant
    }
    private func recoverDevice(secret: String, deviceName: String) async throws -> (
        grant: DeviceGrant, envelope: RecoveryEnvelope?
    ) {
        // Servers with `private-envelope` include the envelope once the secret is verified.
        struct Recovered: Decodable {
            let deviceId: UUID
            let token: String
            let envelope: RecoveryEnvelope?
        }
        let recovered: Recovered = try await call(
            "/v1/recovery", method: "POST", body: json(["recoverySecret": secret, "deviceName": deviceName]))
        return (DeviceGrant(deviceId: recovered.deviceId, token: recovered.token), recovered.envelope)
    }
    /// Adds this device with a password or recovery key typed for `parameters`, what this server published. Only the
    /// derived recovery secret is sent, never what was typed. When the server published the whole envelope (older
    /// servers), the password is checked here first and nothing is sent for a wrong one; otherwise the server checks
    /// the secret and only then sends the envelope, which must be the one described by `parameters`.
    public func recoverVault(_ phrase: String, parameters: RecoveryParameters, deviceName: String) async throws
        -> RecoveredVault
    {
        if let published = parameters.envelope {
            let (key, secret) = try VaultCrypto.recover(published, phrase: phrase)
            let grant = try await recover(secret: secret, deviceName: deviceName)
            return RecoveredVault(grant: grant, envelope: published, key: key)
        }
        let derivations = try VaultCrypto.recoveryDerivations(phrase, for: parameters)
        for (index, derivation) in derivations.enumerated() {
            let recovered: (grant: DeviceGrant, envelope: RecoveryEnvelope?)
            do {
                recovered = try await recoverDevice(secret: derivation.secret, deviceName: deviceName)
            } catch JournalError
                .invalidRecoveryKey where index < derivations.count - 1
            {
                continue
            }
            guard let envelope = recovered.envelope, parameters.describes(envelope),
                let key = try? VaultCrypto.unwrap(envelope, with: derivation)
            else {
                try? await ServerClient(address: address.absoluteString, token: recovered.grant.token)
                    .revoke(recovered.grant.deviceId)
                throw RecoveryEnvelopeChanged()
            }
            return RecoveredVault(grant: recovered.grant, envelope: envelope, key: key)
        }
        throw JournalError.invalidRecoveryKey
    }
    /// Atomically replaces the server's password envelope; the current password's secret is verified.
    public func changePassword(_ change: PasswordChange) async throws {
        struct Body: Encodable {
            let currentRecoverySecret: String
            let salt: String
            let wrappedKey: String
            let iterations: Int
            let recoverySecret: String
            let formatVersion: Int
        }
        let body = Body(
            currentRecoverySecret: change.currentRecoverySecret, salt: change.envelope.salt,
            wrappedKey: change.envelope.wrappedKey, iterations: change.envelope.iterations,
            recoverySecret: change.newRecoverySecret, formatVersion: change.envelope.formatVersion)
        let status: Int
        do { status = try await request("/v1/recovery/password", method: "POST", body: json(body)).1 } catch let error
            as URLError
        {
            throw error.code == .cancelled ? error : PasswordChangeError.failed
        }
        switch status {
        case 204: return
        case 403: throw PasswordChangeError.incorrectPassword
        case 404, 405: throw PasswordChangeError.serverOutdated
        case 409: throw PasswordChangeError.unsupported
        default: throw PasswordChangeError.failed
        }
    }
    /// The changes after `after`. `applied` is the change this device last read at `after`; a server with the
    /// `sync-continuity` capability then refuses with `SyncLogChanged` when it has a different change there.
    public func changes(after: Int64, limit: Int = 100, applied: LoggedChange? = nil) async throws -> SyncPage {
        var path = "/v1/sync/?after=\(after)&limit=\(limit)"
        if let applied {
            path += "&afterRecord=\(applied.recordId.uuidString.lowercased())&afterRevision=\(applied.revision)"
            if let digest = applied.digest { path += "&afterDigest=\(digest)" }
        }
        // A page can hold megabytes of records; like an image, it may take longer while data keeps arriving.
        let (data, status) = try await request(path, limit: Self.pageLimit, transfer: true)
        if status == 409, Self.problemCode(data) == "server_changed" { throw SyncLogChanged() }
        guard status == 200 else { throw Self.syncFailure(status: status) }
        return try JournalCoding.decoder().decode(SyncPage.self, from: data)
    }
    public enum PushResult: Sendable {
        case accepted(RemoteChange), conflict(RemoteChange)
        /// The server has fewer revisions than this device saw, for example after restoring a backup.
        case serverBehind
        /// The server database is not the one this device last synchronized with.
        case serverChanged
    }
    public func push(_ pending: PendingChange, serverID: String? = nil) async throws -> PushResult {
        struct Body: Encodable {
            let operationId: UUID
            let baseRevision: Int64
            let kind: String
            let payload: String
            let serverId: String?
        }
        let (data, status) = try await request(
            "/v1/sync/\(pending.recordID.uuidString.lowercased())", method: "PUT",
            body: json(
                Body(
                    operationId: pending.operationId, baseRevision: pending.baseRevision, kind: pending.kind,
                    payload: pending.payload, serverId: serverID)), limit: Self.pushResponseLimit,
            transfer: pending.payload.utf8.count > Self.largeRecord)
        switch status {
        case 200: return .accepted(try JournalCoding.decoder().decode(RemoteChange.self, from: data))
        case 409: return try Self.pushConflict(data, pending: pending)
        // Rejected before anything was stored, for example as too large or not a valid record.
        case 413: throw SyncRejection(reason: .tooLarge)
        case 400: throw SyncRejection(reason: .invalid)
        default: throw Self.syncFailure(status: status)
        }
    }
    /// A sync request the server answered with an error it doesn't explain: a server error is temporary, and a
    /// server without the endpoint needs an update.
    static func syncFailure(status: Int) -> Error {
        switch status {
        case 500..<600: return ServerUnavailable()
        case 404, 405: return SyncFailure(.serverUpdateNeeded)
        default: return JournalError.server("Couldn’t sync. Your changes are saved on this device.")
        }
    }
    static func pushConflict(_ data: Data, pending: PendingChange) throws -> PushResult {
        struct Current: Decodable {
            var id: UUID
            var revision: Int64
            var kind: String
            var payload: String
            var deviceId: UUID
            var modifiedAt: Date
        }
        // Servers from before problem details send the reason only as `error`.
        struct Conflict: Decodable {
            var code: String?
            var error: String?
            var current: Current?
        }
        let conflict = try JournalCoding.decoder().decode(Conflict.self, from: data)
        switch conflict.code ?? conflict.error {
        case "server_changed": return .serverChanged
        case "revision_ahead": return .serverBehind
        case "revision_conflict":
            // Older servers report a base ahead of the server as a conflict with an older or missing record.
            guard let current = conflict.current, current.revision >= pending.baseRevision else { return .serverBehind }
            return .conflict(
                RemoteChange(
                    cursor: 0, recordId: current.id, revision: current.revision, kind: current.kind,
                    payload: current.payload, deviceId: current.deviceId, modifiedAt: current.modifiedAt))
        // The operation identifier was used for a different request; this one wasn't applied.
        case "operation_reused": throw SyncRejection(reason: .invalid)
        default: throw JournalError.invalidData
        }
    }
    public func upload(_ bytes: Data, id: UUID) async throws {
        let (_, status) = try await request(
            "/v1/attachments/\(id.uuidString.lowercased())", method: "PUT", body: bytes, binary: true, transfer: true)
        switch status {
        case 200: return
        case 413: throw SyncRejection(reason: .tooLarge)
        case 400, 409: throw SyncRejection(reason: .invalid)
        case 500..<600: throw ServerUnavailable()
        default: throw JournalError.server("Couldn’t upload an image. Try again.")
        }
    }
    /// Whether the server still has an image. Nil when the server can't tell (older servers).
    public func hasAttachment(_ id: UUID) async throws -> Bool? {
        let (_, status) = try await request("/v1/attachments/\(id.uuidString.lowercased())", method: "HEAD")
        switch status {
        case 200: return true
        case 404: return false
        default: return nil
        }
    }
    public func downloadAttachment(_ id: UUID) async throws -> Data {
        let (data, status) = try await request(
            "/v1/attachments/\(id.uuidString.lowercased())", limit: JournalStore.maximumAttachmentBytes, transfer: true)
        guard status == 200 else { throw JournalError.server("Image unavailable.") }
        return data
    }
    public func devices() async throws -> [ServerDevice] { try await call("/v1/devices/") }
    public func revoke(_ id: UUID) async throws {
        let (_, status) = try await request("/v1/devices/\(id.uuidString.lowercased())", method: "DELETE")
        guard status == 204 else { throw JournalError.server("Couldn’t revoke this device.") }
    }
}
