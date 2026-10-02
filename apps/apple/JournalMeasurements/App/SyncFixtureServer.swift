import Foundation
import JournalCore
import os

/// Answers the sync protocol for measurements over loopback HTTP: a library at rest, pushes from typing, and a whole
/// change log with its images for a new device. Images can be slowed down to model a real connection.
final class SyncFixtureServer: Sendable {
    struct Counts: Sendable {
        var cursor: Int64
        var pushes: [UUID: Int] = [:]
        var requests = 0
        var imagesServed = 0
        /// Requests by method and the start of their path, to tell what a synchronization asked for.
        var kinds: [String: Int] = [:]
    }
    private let log: [RemoteChange]
    private let serverID: String
    private let attachments: URL
    /// Seconds each image download waits, plus its size at `bytesPerSecond`.
    private let imageLatency: TimeInterval
    private let bytesPerSecond: Double
    private let counts: OSAllocatedUnfairLock<Counts>
    private let device = UUID()

    /// `cursor` is where the log is, when `log` leaves out what came before: a library synchronized up to there.
    init(
        log: [RemoteChange], cursor: Int64 = 0, serverID: String, attachments: URL, imageLatency: TimeInterval = 0,
        bytesPerSecond: Double = .infinity
    ) {
        self.log = log
        self.serverID = serverID
        self.attachments = attachments
        self.imageLatency = imageLatency
        self.bytesPerSecond = bytesPerSecond
        counts = OSAllocatedUnfairLock(initialState: Counts(cursor: max(cursor, log.last?.cursor ?? 0)))
    }

    var current: Counts { counts.withLock { $0 } }

    func respond(_ request: FakeJournalServer.Request) -> (status: Int, body: Data) {
        let path = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? request.path
        let kind = request.method + " " + path.split(separator: "/").prefix(2).joined(separator: "/")
        counts.withLock {
            $0.requests += 1
            $0.kinds[kind, default: 0] += 1
        }
        do {
            if path == "/v1/status" { return (200, try status()) }
            if path == "/v1/sync/", request.method == "GET" { return (200, try page(request.path)) }
            if path.hasPrefix("/v1/sync/"), request.method == "PUT" { return (200, try push(path, body: request.body)) }
            if path.hasPrefix("/v1/attachments/") { return attachment(path, method: request.method) }
        } catch {
            return (500, Data())
        }
        return (404, Data())
    }

    private func status() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "protocolVersion": 1, "initialized": true, "serverId": serverID, "features": [String](),
        ])
    }

    private func page(_ target: String) throws -> Data {
        let query = URLComponents(string: target)?.queryItems ?? []
        let after = query.first { $0.name == "after" }?.value.flatMap(Int64.init) ?? 0
        let limit = query.first { $0.name == "limit" }?.value.flatMap(Int.init) ?? 100
        let start = log.firstIndex { $0.cursor > after } ?? log.endIndex
        let changes = Array(log[start..<min(log.endIndex, start + limit)])
        struct Page: Encodable {
            let changes: [RemoteChange]
            let cursor: Int64
            let hasMore: Bool
            let serverId: String
        }
        return try JournalCoding.encoder().encode(
            Page(
                changes: changes, cursor: changes.last?.cursor ?? after, hasMore: start + limit < log.endIndex,
                serverId: serverID))
    }

    private func push(_ path: String, body: Data) throws -> Data {
        struct Push: Decodable {
            let baseRevision: Int64
            let kind: String
            let payload: String
        }
        let pushed = try JSONDecoder().decode(Push.self, from: body)
        guard let recordID = UUID(uuidString: String(path.dropFirst("/v1/sync/".count))) else {
            throw MeasurementFailure("The push names no record.")
        }
        let cursor = counts.withLock { counts -> Int64 in
            counts.cursor += 1
            counts.pushes[recordID, default: 0] += 1
            return counts.cursor
        }
        return try JournalCoding.encoder().encode(
            RemoteChange(
                cursor: cursor, recordId: recordID, revision: pushed.baseRevision + 1, kind: pushed.kind,
                payload: pushed.payload, deviceId: device, modifiedAt: Date()))
    }

    private func attachment(_ path: String, method: String) -> (status: Int, body: Data) {
        guard method == "GET" else { return (200, Data()) }
        let name = String(path.dropFirst("/v1/attachments/".count))
        guard let bytes = try? Data(contentsOf: attachments.appendingPathComponent(name)) else { return (404, Data()) }
        let wait = imageLatency + (bytesPerSecond.isFinite ? Double(bytes.count) / bytesPerSecond : 0)
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        counts.withLock { $0.imagesServed += 1 }
        return (200, bytes)
    }
}
