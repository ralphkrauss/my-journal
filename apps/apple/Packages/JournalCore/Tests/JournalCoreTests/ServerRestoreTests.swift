import XCTest

@testable import JournalCore

/// A minimal in-memory server with the protocol's revision and cursor rules. Copying it is a backup.
private struct FakeServer {
    var records: [UUID: RemoteChange] = [:]
    var log: [RemoteChange] = []
    var nextCursor: Int64 = 1
    var identityCursor: Int64 = 0
    mutating func push(_ pending: PendingChange, device: UUID) -> RemoteChange? {
        let current = records[pending.recordID]?.revision ?? 0
        guard current == pending.baseRevision else { return nil }
        let change = RemoteChange(
            cursor: nextCursor, recordId: pending.recordID, revision: current + 1, kind: pending.kind,
            payload: pending.payload, deviceId: device, modifiedAt: Date(timeIntervalSince1970: 1_800_000_000))
        nextCursor += 1
        log.append(change)
        records[pending.recordID] = change
        return change
    }
    /// SQLite AUTOINCREMENT continues from the restored database's own sequence.
    mutating func restore(_ backup: FakeServer) {
        self = backup
        identityCursor = backup.log.last?.cursor ?? 0
    }
    func changes(after cursor: Int64) -> [RemoteChange] { log.filter { $0.cursor > cursor } }
}

final class ServerRestoreTests: XCTestCase {
    private var directories: [URL] = []
    override func tearDownWithError() throws {
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
    }
    private func store(key: Data) throws -> JournalStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("journal-restore-\(UUID())")
        directories.append(url)
        return try JournalStore(directory: url, key: key)
    }
    /// Push then pull, as SyncEngine does once the identity matches.
    private func sync(_ store: JournalStore, _ server: inout FakeServer, device: UUID = UUID()) async throws {
        for pending in try await store.pending() {
            if let receipt = server.push(pending, device: device) {
                try await store.acknowledge(pending, receipt: receipt)
            } else if let current = server.records[pending.recordID] {
                try await store.recordConflict(current)
            } else {
                XCTFail("Base revision ahead of the server")
            }
        }
        let cursor = try await store.cursor()
        let changes = server.changes(after: cursor)
        try await store.apply(changes, cursor: changes.last?.cursor ?? cursor)
    }
    private func reconcile(_ store: JournalStore, _ server: FakeServer, serverID: String) async throws {
        let needed = try await store.needsReconciliation(serverID: serverID)
        XCTAssertTrue(needed)
        try await store.beginReconciliation(serverID: serverID)
        try await store.stageReconciliation(server.log, cursor: server.log.last?.cursor ?? 0)
        try await store.finishReconciliation(serverIDCursor: server.identityCursor)
        let stillNeeded = try await store.needsReconciliation(serverID: serverID)
        XCTAssertFalse(stillNeeded)
    }
    private func text(_ store: JournalStore, _ id: UUID) async throws -> String? {
        try await store.item(id)?.document.text
    }

    func testRestoredServerReceivesNewerLocalVersionsAndLostRecordsWithoutConflicts() async throws {
        let key = try VaultCrypto.generateKey()
        let mac = try store(key: key)
        let phone = try store(key: key)
        var server = FakeServer()
        var entry = JournalItem(kind: "entry", document: .plain("Before backup"))
        let unchanged = JournalItem(kind: "entry", document: .plain("Never edited"))
        try await mac.save(entry)
        try await mac.save(unchanged)
        try await sync(mac, &server)
        try await sync(phone, &server)
        let backup = server
        entry.document = .plain("After backup")
        try await mac.save(entry)
        let added = JournalItem(kind: "entry", document: .plain("Created after backup"))
        try await mac.save(added)
        try await sync(mac, &server)
        let imageID = try await mac.addAttachment(Data(repeating: 1, count: 64))
        try await mac.acknowledgeAttachment(imageID)
        let pageCursor = try await mac.cursor()

        server.restore(backup)
        // The restored server reports nothing new after this device's cursor: the silent-loss case.
        XCTAssertTrue(server.changes(after: pageCursor).isEmpty)
        try await reconcile(mac, server, serverID: "restored")
        let pending = try await mac.pending()
        XCTAssertEqual(Set(pending.map(\.recordID)), [entry.id, added.id])
        XCTAssertEqual(pending.first { $0.recordID == entry.id }?.baseRevision, 1)
        XCTAssertEqual(pending.first { $0.recordID == added.id }?.baseRevision, 0)
        let toVerify = try await mac.attachmentsToVerify()
        XCTAssertEqual(toVerify, [imageID])
        try await sync(mac, &server)
        let remaining = try await mac.pending()
        let conflicts = try await mac.conflicts()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(conflicts.isEmpty)

        // Another device that only saw the backup's state catches up normally.
        try await reconcile(phone, server, serverID: "restored")
        try await sync(phone, &server)
        let phoneText = try await text(phone, entry.id)
        let phoneAdded = try await text(phone, added.id)
        let phoneUnchanged = try await text(phone, unchanged.id)
        XCTAssertEqual(phoneText, "After backup")
        XCTAssertEqual(phoneAdded, "Created after backup")
        XCTAssertEqual(phoneUnchanged, "Never edited")
    }

    func testEditsWrittenAfterRestoreAreReviewedNotOverwritten() async throws {
        let key = try VaultCrypto.generateKey()
        let mac = try store(key: key)
        let phone = try store(key: key)
        var server = FakeServer()
        var contested = JournalItem(kind: "entry", document: .plain("Shared"))
        var continued = JournalItem(kind: "entry", document: .plain("Mac version"))
        try await mac.save(contested)
        try await sync(mac, &server)
        let backup = server
        try await mac.save(continued)
        try await sync(mac, &server)
        try await sync(phone, &server)
        contested.document = .plain("Mac edit lost by the restore")
        try await mac.save(contested)
        try await sync(mac, &server)

        server.restore(backup)
        // The phone reconciles first: it re-uploads what it has, then edits on top of it.
        try await reconcile(phone, server, serverID: "restored")
        try await sync(phone, &server)
        contested.document = .plain("Phone edit after restore")
        try await phone.save(contested)
        continued.document = .plain("Phone continued the Mac version")
        try await phone.save(continued)
        try await sync(phone, &server)

        try await reconcile(mac, server, serverID: "restored")
        let conflicts = try await mac.conflicts()
        XCTAssertEqual(conflicts.map(\.id), [contested.id])
        XCTAssertEqual(conflicts.first?.local.document.text, "Mac edit lost by the restore")
        XCTAssertEqual(conflicts.first?.remote.document.text, "Phone edit after restore")
        // The server's version descends from content this device has, so it applies cleanly.
        let continuedText = try await text(mac, continued.id)
        XCTAssertEqual(continuedText, "Phone continued the Mac version")
        try await sync(mac, &server)
        let reviewed = try await mac.conflicts()
        let conflict = try XCTUnwrap(reviewed.first)
        try await mac.resolve(conflict, choice: .keepBoth)
        try await sync(mac, &server)
        let texts = Set(try await mac.items().map(\.document.text))
        XCTAssertTrue(texts.isSuperset(of: ["Mac edit lost by the restore", "Phone edit after restore"]))
        let remaining = try await mac.pending()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testPendingEditBasedOnLostRevisionIsRebasedAndLaterRemoteChangesStillArrive() async throws {
        let key = try VaultCrypto.generateKey()
        let mac = try store(key: key)
        let phone = try store(key: key)
        var server = FakeServer()
        var entry = JournalItem(kind: "entry", document: .plain("One"))
        try await mac.save(entry)
        try await sync(mac, &server)
        let backup = server
        entry.document = .plain("Two")
        try await mac.save(entry)
        try await sync(mac, &server)
        entry.document = .plain("Three, offline")
        try await mac.save(entry)

        server.restore(backup)
        try await reconcile(mac, server, serverID: "restored")
        let pending = try await mac.pending()
        XCTAssertEqual(pending.map(\.baseRevision), [1])
        try await sync(mac, &server)
        // A device that never synchronized before simply adopts the restored server.
        let phoneNeeds = try await phone.needsReconciliation(serverID: "restored")
        XCTAssertFalse(phoneNeeds)
        try await sync(phone, &server)
        entry.document = .plain("Four, from the phone")
        try await phone.save(entry)
        try await sync(phone, &server)
        try await sync(mac, &server)
        let macText = try await text(mac, entry.id)
        XCTAssertEqual(macText, "Four, from the phone")
    }

    func testOnlyAStoreWithSyncHistoryReconcilesWhenFirstSeeingAnIdentity() async throws {
        let key = try VaultCrypto.generateKey()
        let fresh = try store(key: key)
        let freshNeeds = try await fresh.needsReconciliation(serverID: "server")
        XCTAssertFalse(freshNeeds)
        let adopted = try await fresh.syncedServerID()
        XCTAssertEqual(adopted, "server")
        let synced = try store(key: key)
        var server = FakeServer()
        try await synced.save(JournalItem(kind: "entry", document: .plain("Synced before identities")))
        try await sync(synced, &server)
        let syncedNeeds = try await synced.needsReconciliation(serverID: "server")
        XCTAssertTrue(syncedNeeds)
        let oldServerNeeds = try await synced.needsReconciliation(serverID: nil)
        XCTAssertFalse(oldServerNeeds)
    }

    func testPushConflictWithoutCurrentRecordOrOlderRevisionMeansTheServerIsBehind() throws {
        let pending = PendingChange(
            operationId: UUID(), recordID: UUID(), baseRevision: 3, kind: "entry", payload: "")
        func result(_ json: String) throws -> ServerClient.PushResult {
            try ServerClient.pushConflict(Data(json.utf8), pending: pending)
        }
        guard case .serverBehind = try result(#"{"error":"revision_conflict","current":null}"#),
            case .serverBehind = try result(#"{"error":"revision_ahead","current":null}"#),
            case .serverChanged = try result(#"{"error":"server_changed"}"#),
            case .serverBehind = try result(
                #"{"error":"revision_conflict","current":{"id":"\#(pending.recordID)","revision":2,"kind":"entry","payload":"","deviceId":"\#(UUID())","modifiedAt":"2026-09-24T10:00:00Z"}}"#
            ),
            case .conflict = try result(
                #"{"error":"revision_conflict","current":{"id":"\#(pending.recordID)","revision":4,"kind":"entry","payload":"","deviceId":"\#(UUID())","modifiedAt":"2026-09-24T10:00:00Z"}}"#
            )
        else { return XCTFail("Unexpected push result") }
    }
}
