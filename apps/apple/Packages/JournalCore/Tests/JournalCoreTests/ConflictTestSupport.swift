import XCTest
import os

@testable import JournalCore

/// Stores and server changes for the tests of conflicts settled on their own (protocol/conflicts.md).
class ConflictTestCase: XCTestCase {
    private(set) var root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let key = Data((0..<32).map { UInt8($0 &+ 64) })
    private var cursors: [String: Int64] = [:]
    /// What every store's clock reads. A record counts as being written for a moment after it was saved.
    let time = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_800_000_000))

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        cursors = [:]
    }

    /// A store for a device. By default its one-time pass over conflicts an earlier version left has run already, as in
    /// a library that was opened before: conflicts made afterwards wait for a completed pull.
    func openStore(_ name: String = "device", key: Data? = nil, runPass: Bool = true) async throws -> JournalStore {
        let store = try JournalStore(directory: root.appendingPathComponent(name), key: key ?? self.key)
        addTeardownBlock { try? await store.close() }
        let time = time
        await store.useClock { time.withLock { $0 } }
        if runPass { try await store.resolveConflicts(at: .opening(serverConfigured: true)) }
        return store
    }

    /// Lets the person's pause after writing pass, then settles conflicts at the end of a completed pull.
    @discardableResult func settleAfterPause(_ store: JournalStore, _ point: ConflictResolutionPoint = .completedPull)
        async throws -> ConflictResolutionReport
    {
        time.withLock { $0 = $0.addingTimeInterval(3) }
        return try await store.resolveConflicts(at: point)
    }

    /// A change the server sent, sealed as this library seals records.
    func remote(
        _ item: JournalItem, revision: Int64, cursor: Int64? = nil, device: UUID = UUID(), key: Data? = nil
    ) throws -> RemoteChange {
        let payload = try VaultCrypto.seal(
            PortableRecord.encode(item), key: key ?? self.key,
            context: VaultCrypto.recordContext(id: item.id, kind: item.kind))
        return RemoteChange(
            cursor: cursor ?? revision, recordId: item.id, revision: revision, kind: item.kind,
            payload: payload.base64EncodedString(), deviceId: device, modifiedAt: item.modifiedAt)
    }

    /// Delivers `item` as the server's version `revision` and moves the position past it.
    @discardableResult func deliver(_ item: JournalItem, revision: Int64, to store: JournalStore, device: UUID = UUID())
        async throws -> Int64
    {
        let name = String(describing: ObjectIdentifier(store))
        let cursor = (cursors[name] ?? 0) + 1
        cursors[name] = cursor
        try await store.apply([remote(item, revision: revision, cursor: cursor, device: device)], cursor: cursor)
        return cursor
    }

    /// Saves `item` and pretends the server accepted it at `revision`, so the record is clean.
    func settle(_ item: JournalItem, revision: Int64 = 1, in store: JournalStore) async throws {
        try await store.save(item)
        for change in try await store.pending() where change.recordID == item.id {
            let receipt = RemoteChange(
                cursor: revision, recordId: item.id, revision: change.baseRevision + 1, kind: change.kind,
                payload: change.payload, deviceId: UUID(), modifiedAt: Date())
            try await store.acknowledge(change, receipt: receipt)
        }
    }

    func marker(for item: JournalItem, at seconds: TimeInterval = 1_800_000_000) -> JournalItem {
        JournalItem.permanentDeletionMarker(for: item, at: Date(timeIntervalSince1970: seconds))
    }

    func side(_ item: JournalItem) throws -> ConflictSide {
        ConflictSide(item: item, plaintext: try PortableRecord.encode(item))
    }
    func entry(_ title: String, text: String, journal: UUID? = nil, seconds: TimeInterval = 1_700_000_000)
        -> JournalItem
    {
        var item = JournalItem(
            kind: "entry", journalID: journal ?? UUID(), title: title, document: .plain(text),
            date: Date(timeIntervalSince1970: seconds))
        item.modifiedAt = Date(timeIntervalSince1970: seconds)
        return item
    }
    func journal(_ title: String, seconds: TimeInterval = 1_700_000_000) -> JournalItem {
        var item = JournalItem(kind: "journal", title: title, date: Date(timeIntervalSince1970: seconds))
        item.modifiedAt = Date(timeIntervalSince1970: seconds)
        return item
    }
    func stored(_ store: JournalStore, _ id: UUID) async throws -> JournalItem {
        let item = try await store.item(id)
        return try XCTUnwrap(item)
    }
    /// The entries and templates other than `excluding`, which are not permanent deletions.
    func parkedItems(in store: JournalStore, excluding id: UUID) async throws -> [JournalItem] {
        try await store.items().filter { $0.kind != "journal" && $0.id != id && !$0.isPermanentlyDeleted }
    }
}

/// One device's view of an in-memory server: its changes carry the device's own identity, as a real server records it,
/// so a conflict knows which device the other version came from.
struct DeviceServer: SyncServer {
    let server: MemoryServer
    let device: UUID

    func status() async throws -> ServerStatus { await server.status() }
    func changes(after cursor: Int64, limit: Int, applied: LoggedChange?) async throws -> SyncPage {
        try await server.changes(after: cursor, limit: limit, applied: applied)
    }
    func push(_ pending: PendingChange, serverID: String?, shortReceipt: Bool) async throws -> ServerClient.PushResult {
        try await server.push(pending, from: device, shortReceipt: shortReceipt)
    }
    func upload(_ bytes: Data, id: UUID) async throws { try await server.upload(bytes, id: id) }
    func hasAttachment(_ id: UUID) async throws -> Bool? { await server.hasAttachment(id) }
    func downloadAttachment(_ id: UUID) async throws -> Data { try await server.downloadAttachment(id) }
}
