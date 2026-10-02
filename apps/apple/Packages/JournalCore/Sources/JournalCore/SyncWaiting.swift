import Foundation
import GRDB
import os

/// The store's state when a synchronization ended: no other synchronization ran and nothing was written since, while
/// `JournalStore.quietPosition(since:)` still answers for it (docs/design/sync-protocol-efficiency.md §4.6).
public struct QuietMark: Sendable, Equatable {
    /// The store instance the mark belongs to: a mark never applies to another library or a reopened one.
    let store: UUID
    let generation: UInt64
    let writes: Int
}

/// Where this device is in the server's log, and the identity it last synchronized with.
public struct QuietPosition: Sendable, Equatable {
    public var cursor: Int64
    public var applied: LoggedChange?
    public var serverID: String?
}

/// The store's state behind its quiet marks.
struct QuietState {
    /// Identifies this store instance in its marks.
    let epoch = UUID()
    /// Advances when a synchronization takes the gate and when it releases it (odd while one runs), whichever engine.
    var generation: UInt64 = 0
    /// Commits to the tables synchronization depends on (`SyncedTableWrites`).
    let writes = WriteCounter()
    /// The count the last settled facts were read at, for the mark `endSynchronization` records.
    var factsWrites: Int?
}

/// Counts commits that changed what synchronization sends or keeps for review. Advanced on the database's queue by
/// `SyncedTableWrites`, read by the store.
final class WriteCounter: Sendable {
    private let count = OSAllocatedUnfairLock(initialState: 0)
    var value: Int { count.withLock { $0 } }
    func advance() { count.withLock { $0 += 1 } }
}

/// Notes every committed change to the tables synchronization depends on, whatever code wrote it, so no write can
/// slip past a quiet mark. Called only on the database's writer queue.
final class SyncedTableWrites: TransactionObserver {
    static let tables: Set<String> = ["records", "outbox", "attachments", "conflicts"]
    private let counter: WriteCounter
    private var changed = false
    init(counter: WriteCounter) { self.counter = counter }
    func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool { Self.tables.contains(eventKind.tableName) }
    func databaseDidChange(with event: DatabaseEvent) {
        changed = true
        // One change is enough to know; imports and reconciliation don't pay a callback per row.
        stopObservingDatabaseChangesUntilNextTransaction()
    }
    func databaseDidCommit(_ db: Database) {
        if changed { counter.advance() }
        changed = false
    }
    func databaseDidRollback(_ db: Database) { changed = false }
}

/// What the store holds that decides whether a synchronization left anything to do, read in one actor step together
/// with the write count the quiet mark uses.
struct SettledFacts {
    var writes: Int
    var queuedOperations: Set<UUID>
    var imagesToUpload: Set<UUID>
    var reconciling: Bool
    var renameOutstanding: Bool
    var position: QuietPosition
}

extension JournalStore {
    /// Read as a synchronization's last step before it releases the gate. Every store write goes through this actor,
    /// so nothing can be written between these reads; the write count is taken first, so anything written later
    /// breaks the quiet mark.
    func settledFacts() throws -> SettledFacts {
        let writes = quiet.writes.value
        // Changes waiting for a review aren't sent until it's resolved (`pending()` leaves them out).
        let queued = Set(try pending().map(\.operationId))
        let images = Set(try attachmentsToUpload()).union(try attachmentsToVerify())
        let position = try syncPosition()
        let facts = SettledFacts(
            writes: writes, queuedOperations: queued, imagesToUpload: images, reconciling: try reconciliation() != nil,
            renameOutstanding: !(try automaticRenames().isEmpty),
            position: QuietPosition(cursor: position.cursor, applied: position.applied, serverID: try syncedServerID()))
        quiet.factsWrites = writes
        return facts
    }
    /// The position and identity to wait from, while nothing synchronized or was written since `mark`; nil otherwise.
    public func quietPosition(since mark: QuietMark) throws -> QuietPosition? {
        guard isQuiet(mark) else { return nil }
        let position = try syncPosition()
        return QuietPosition(cursor: position.cursor, applied: position.applied, serverID: try syncedServerID())
    }
    /// Whether nothing synchronized or was written since `mark`. Reads no database.
    public func isQuiet(_ mark: QuietMark) -> Bool {
        mark.store == quiet.epoch && quiet.generation == mark.generation && quiet.writes.value == mark.writes
    }
    /// The position after a synchronization, to tell whether it read anything.
    public func currentPosition() throws -> QuietPosition {
        let position = try syncPosition()
        return QuietPosition(cursor: position.cursor, applied: position.applied, serverID: try syncedServerID())
    }
}

/// The answer to waiting for changes (GET /v1/sync/wait).
public enum WaitAnswer: Sendable, Equatable {
    /// Something may differ: synchronize.
    case changed
    /// Nothing to exchange. `early` when the server answered before the timeout (replaced or stopping), which proves
    /// nothing about the position.
    case unchanged(early: Bool)
    /// Anything else: an error, a refusal, a redirect or an unreadable answer. Never a health state by itself; the
    /// synchronization that follows explains it.
    case failed
}

extension ServerClient {
    /// The longest wait the client asks for: below the server's 25 s, leaving margin under QUIC idle timeouts and
    /// UDP NAT mappings (docs/design/sync-protocol-efficiency.md §4.6).
    public static let waitSeconds = 20
    /// Waits for the server's log to move past `position`. Throws only `CancellationError`.
    public func waitForChange(_ position: QuietPosition, digest: Bool, timeout: Int = waitSeconds) async throws
        -> WaitAnswer
    {
        var path = "/v1/sync/wait?after=\(position.cursor)&timeout=\(timeout)"
        if position.cursor > 0, let applied = position.applied {
            path += "&afterRecord=\(applied.recordId.uuidString.lowercased())&afterRevision=\(applied.revision)"
            if digest, let value = applied.digest { path += "&afterDigest=\(value)" }
        }
        if let serverID = position.serverID,
            let encoded = serverID.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(["-"]))
        {
            path += "&serverId=\(encoded)"
        }
        guard
            let url = URL(string: address.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path)
        else { return .failed }
        var request = URLRequest(url: url)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (bytes, response) = try await waitSession.bytes(for: request)
            var body = Data()
            for try await byte in bytes {
                guard body.count < Self.waitAnswerLimit else {
                    bytes.task.cancel()
                    return .failed
                }
                body.append(byte)
            }
            return Self.waitAnswer(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: body)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
                throw CancellationError()
            }
            return .failed
        }
    }
    static let waitAnswerLimit = 1024
    /// Reads a wait's answer: only a 200 with a boolean `changed` (and, if present, a boolean `early`) is an answer.
    static func waitAnswer(status: Int, body: Data) -> WaitAnswer {
        struct Body: Decodable {
            var changed: Bool
            var early: Bool?
        }
        guard status == 200, body.count <= waitAnswerLimit,
            let answer = try? JSONDecoder().decode(Body.self, from: body)
        else { return .failed }
        return answer.changed ? .changed : .unchanged(early: answer.early == true)
    }
}

/// Logs why a receipt was rejected, without content, digests or IDs, so a fault that keeps recurring can be told
/// apart: a client or a server bug.
enum ReceiptLog {
    private static let logger = Logger(subsystem: "io.github.ralphkrauss.myjournal", category: "sync")
    static func rejected(short: Bool, check: String) {
        logger.error(
            "Rejected a \(short ? "short" : "full", privacy: .public) push receipt: \(check, privacy: .public)")
    }
}
