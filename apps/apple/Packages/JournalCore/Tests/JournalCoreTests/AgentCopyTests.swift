import CryptoKit
import XCTest

@testable import JournalCore

/// Agent access through the server (protocol/agent-access-server.md): what devices publish into an agent's copy, and
/// what the connector accepts from a server it doesn't trust.
final class AgentCopyTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testCopyOpensOnlyWithItsGrantsKeyAndAtItsOwnPosition() throws {
        let grant = UUID()
        let keys = try AgentCopyKeys(VaultCrypto.random(32))
        let other = try AgentCopyKeys(VaultCrypto.random(32))
        let entry = AgentCopyItem.entry(
            id: UUID(), journalID: UUID(), title: "Plans", date: Date(timeIntervalSince1970: 1_700_000_000),
            archivedAt: nil, text: "Private text")
        let sealed = try AgentCopyCrypto.seal(entry, grantID: grant, keys: keys)
        XCTAssertEqual(try AgentCopyCrypto.open(sealed.payload, itemID: sealed.id, grantID: grant, keys: keys), entry)
        // Another agent's key, another agent's position, or another item's position don't open it.
        XCTAssertThrowsError(try AgentCopyCrypto.open(sealed.payload, itemID: sealed.id, grantID: grant, keys: other))
        XCTAssertThrowsError(try AgentCopyCrypto.open(sealed.payload, itemID: sealed.id, grantID: UUID(), keys: keys))
        let moved = keys.itemID(recordID: UUID())
        XCTAssertThrowsError(try AgentCopyCrypto.open(sealed.payload, itemID: moved, grantID: grant, keys: keys))
        // The settings that hold the key open only with the library's vault key.
        let vaultKey = try VaultCrypto.generateKey()
        let settings = AgentCopySettings(
            name: "Claude", clientName: "Claude Code", journalIDs: [UUID()], expiresAt: nil, key: Data(count: 32))
        let metadata = try AgentCopyCrypto.sealSettings(
            settings, grantID: grant, vaultKey: vaultKey)
        XCTAssertEqual(
            try AgentCopyCrypto.openSettings(metadata, grantID: grant, vaultKey: vaultKey),
            settings)
        XCTAssertThrowsError(
            try AgentCopyCrypto.openSettings(
                metadata, grantID: grant, vaultKey: VaultCrypto.generateKey()))
        XCTAssertThrowsError(
            try AgentCopyCrypto.openSettings(metadata, grantID: UUID(), vaultKey: vaultKey))
    }

    /// Only synchronized state reaches the copy: shared journals' live entries are published, and an entry with a
    /// change or conflict on this device is neither published nor removed.
    func testPublishingSharesOnlySettledEntriesOfSharedLiveJournals() async throws {
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        let shared = JournalItem(kind: "journal", title: "Work")
        let unshared = JournalItem(kind: "journal", title: "Private")
        let visible = JournalItem(kind: "entry", journalID: shared.id, title: "Visible", document: .plain("Notes"))
        let hidden = JournalItem(kind: "entry", journalID: unshared.id, title: "Hidden")
        var deleted = JournalItem(kind: "entry", journalID: shared.id, title: "Deleted")
        deleted.deletedAt = Date()
        let pending = JournalItem(kind: "entry", journalID: shared.id, title: "Pending")
        try await synchronized(store, [shared, unshared, visible, hidden, deleted, pending], cursor: 7)
        var edited = pending
        edited.title = "Pending edit"
        try await store.save(edited)
        let keys = try AgentCopyKeys(VaultCrypto.random(32))
        let grant = UUID()
        let settings = AgentCopySettings(
            name: "Claude", clientName: "Claude Code", journalIDs: [shared.id], expiresAt: nil, key: Data())
        let source = try await store.agentCopySource()
        let plan = AgentCopyPlan(settings: settings, keys: keys, grantID: grant, source: source)
        let uploads = try plan.changes(comparedWith: [:])
        let items = try uploads.compactMap { upload in
            try upload.payload.map { try AgentCopyCrypto.open($0, itemID: upload.id, grantID: grant, keys: keys) }
        }
        XCTAssertEqual(Set(items.map(\.id)), [shared.id, visible.id])
        XCTAssertTrue(uploads.allSatisfy { $0.version == 7 })
        XCTAssertEqual(items.first { $0.id == visible.id }?.text, "Notes")

        // The server holds the pending entry from before; it's left alone until the edit syncs.
        let pendingItem = keys.itemID(recordID: pending.id)
        let known = [
            pendingItem: AgentCopyManifestItem(id: pendingItem, version: 3, digest: "", deleted: false, sequence: 1)
        ]
        XCTAssertFalse(try plan.changes(comparedWith: known).contains { $0.id == pendingItem })
    }

    /// Deleting a shared journal removes its entries from the copy, and an entry moved to another journal leaves it.
    func testDeletedJournalsAndMovedEntriesLeaveTheCopy() async throws {
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        var shared = JournalItem(kind: "journal", title: "Work")
        let other = JournalItem(kind: "journal", title: "Other")
        let staying = JournalItem(kind: "entry", journalID: shared.id, title: "Staying")
        var moving = JournalItem(kind: "entry", journalID: shared.id, title: "Moving")
        try await synchronized(store, [shared, other, staying, moving], cursor: 4)
        let keys = try AgentCopyKeys(VaultCrypto.random(32))
        let grant = UUID()
        let settings = AgentCopySettings(
            name: "Claude", clientName: "Claude Code", journalIDs: [shared.id], expiresAt: nil, key: Data())
        let firstSource = try await store.agentCopySource()
        let first = try AgentCopyPlan(settings: settings, keys: keys, grantID: grant, source: firstSource)
            .changes(comparedWith: [:])
        var known: [String: AgentCopyManifestItem] = [:]
        for upload in first {
            known[upload.id] = AgentCopyManifestItem(
                id: upload.id, version: upload.version, digest: upload.digest, deleted: false, sequence: 0)
        }
        XCTAssertEqual(known.count, 3)
        moving.journalID = other.id
        shared.deletedAt = Date()
        var withDeletedJournal = staying
        withDeletedJournal.deletedWithJournal = true
        try await synchronized(store, [shared, moving, withDeletedJournal], cursor: 9)
        let secondSource = try await store.agentCopySource()
        let second = try AgentCopyPlan(settings: settings, keys: keys, grantID: grant, source: secondSource)
            .changes(comparedWith: known)
        XCTAssertEqual(Set(second.map(\.id)), Set(known.keys))
        XCTAssertTrue(second.allSatisfy { $0.payload == nil && $0.version == 9 })
    }

    /// Settings from before "all journals" (version 1) still open; version 2 keeps "all journals", and chosen journals
    /// this device doesn't have are kept, never dropped.
    func testSettingsOfBothVersionsOpenAndKeepEveryChosenJournal() throws {
        let grant = UUID()
        let vaultKey = try VaultCrypto.generateKey()
        let journal = UUID()
        let key = try VaultCrypto.random(32)
        let version1: [String: Any] = [
            "version": 1, "name": "Claude", "clientName": "Claude Code", "journalIds": [journal.uuidString],
            "key": key.base64EncodedString(),
        ]
        let sealed = try VaultCrypto.seal(
            JSONSerialization.data(withJSONObject: version1), key: vaultKey,
            context: AgentCopyCrypto.settingsContext(grantID: grant)
        ).base64EncodedString()
        let opened = try AgentCopyCrypto.openSettings(
            sealed, grantID: grant, vaultKey: vaultKey)
        XCTAssertEqual(opened.journalIDs, [journal])
        XCTAssertFalse(opened.allJournals)
        XCTAssertTrue(opened.shares(journal))
        XCTAssertFalse(opened.shares(UUID()))

        let everything = AgentCopySettings(
            name: "Claude", clientName: "Claude Code", allJournals: true, journalIDs: [], expiresAt: nil, key: key)
        let reopened = try AgentCopyCrypto.openSettings(
            AgentCopyCrypto.sealSettings(everything, grantID: grant, vaultKey: vaultKey),
            grantID: grant, vaultKey: vaultKey)
        XCTAssertEqual(reopened, everything)
        XCTAssertTrue(reopened.shares(UUID()))
        let unknown = UUID()
        let chosen = AgentCopySettings(
            name: "Claude", clientName: "Claude Code", journalIDs: [journal, unknown], expiresAt: nil, key: key)
        XCTAssertEqual(
            try AgentCopyCrypto.openSettings(
                AgentCopyCrypto.sealSettings(chosen, grantID: grant, vaultKey: vaultKey),
                grantID: grant, vaultKey: vaultKey
            ).journalIDs, [journal, unknown])
    }

    /// "All journals" follows the library: a journal created and synced after approval joins the copy, a renamed
    /// one is published again under its new name, and a deleted one leaves.
    func testAllJournalsFollowsJournalsCreatedRenamedAndDeletedLater() async throws {
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        var first = JournalItem(kind: "journal", title: "Work")
        let entry = JournalItem(kind: "entry", journalID: first.id, title: "Plans", document: .plain("Notes"))
        try await synchronized(store, [first, entry], cursor: 2)
        let keys = try AgentCopyKeys(VaultCrypto.random(32))
        let grant = UUID()
        let settings = AgentCopySettings(
            name: "Claude", clientName: "Claude Code", allJournals: true, journalIDs: [], expiresAt: nil, key: Data())
        var known: [String: AgentCopyManifestItem] = [:]
        func publish() async throws -> [AgentCopyUpload] {
            let source = try await store.agentCopySource()
            let changes = try AgentCopyPlan(settings: settings, keys: keys, grantID: grant, source: source)
                .changes(comparedWith: known)
            for upload in changes {
                known[upload.id] = AgentCopyManifestItem(
                    id: upload.id, version: upload.version, digest: upload.digest, deleted: upload.payload == nil,
                    sequence: 0)
            }
            return changes
        }
        let initial = try await publish()
        XCTAssertEqual(initial.count, 2)

        let later = JournalItem(kind: "journal", title: "Created later")
        let laterEntry = JournalItem(kind: "entry", journalID: later.id, title: "New", document: .plain("Fresh"))
        first.title = "Renamed"
        try await synchronized(store, [later, laterEntry, first], cursor: 6)
        let second = try await publish()
        XCTAssertEqual(
            Set(second.map(\.id)),
            [keys.itemID(recordID: later.id), keys.itemID(recordID: laterEntry.id), keys.itemID(recordID: first.id)])
        let renamed = try XCTUnwrap(second.first { $0.id == keys.itemID(recordID: first.id) }?.payload)
        XCTAssertEqual(
            try AgentCopyCrypto.open(renamed, itemID: keys.itemID(recordID: first.id), grantID: grant, keys: keys).name,
            "Renamed")

        var deleted = later
        deleted.deletedAt = Date()
        try await synchronized(store, [deleted], cursor: 8)
        let third = try await publish()
        XCTAssertEqual(Set(third.map(\.id)), [keys.itemID(recordID: later.id), keys.itemID(recordID: laterEntry.id)])
        XCTAssertTrue(third.allSatisfy { $0.payload == nil })
    }

    /// Narrowing an agent's journals empties the items of every journal it may no longer read: chosen journals this
    /// device doesn't have, a dropped journal and its entries, and, when leaving All Journals, whatever the copy holds
    /// that another device shared and this one hasn't synced yet ("Therapy" created on the Mac, narrowed on an iPhone).
    func testNarrowingRemovesJournalsThisDeviceDoesNotKnow() throws {
        let keys = try AgentCopyKeys(VaultCrypto.random(32))
        let kept = JournalItem(kind: "journal", title: "Work")
        let dropped = JournalItem(kind: "journal", title: "Personal")
        let keptEntry = JournalItem(kind: "entry", journalID: kept.id, title: "Plans")
        let droppedEntry = JournalItem(kind: "entry", journalID: dropped.id, title: "Diary")
        let source = AgentCopySource(
            cursor: 5, journals: [kept.id: kept, dropped.id: dropped], entries: [keptEntry, droppedEntry],
            unsettled: [])
        func settings(all: Bool = false, _ journals: Set<UUID>) -> AgentCopySettings {
            AgentCopySettings(
                name: "Claude", clientName: "Claude Code", allJournals: all, journalIDs: journals, expiresAt: nil,
                key: Data(count: 32))
        }
        func item(_ id: UUID) -> String { keys.itemID(recordID: id) }

        // Selected to fewer selected: the dropped journal and its entries, and a chosen journal this device lacks.
        let unknown = UUID()
        let fewer = AgentCopyNarrowing.removedItems(
            from: settings([kept.id, dropped.id, unknown]), to: settings([kept.id]), keys: keys, source: source,
            copy: [:])
        XCTAssertEqual(Set(fewer), [item(dropped.id), item(droppedEntry.id), item(unknown)])

        // All to selected: the copy's items of a journal this device doesn't have go too; kept items stay.
        let therapy = UUID()
        let therapyEntry = UUID()
        let unknownEntryOfKept = UUID()
        var copy: [String: AgentCopyManifestItem] = [:]
        for id in [kept.id, keptEntry.id, dropped.id, droppedEntry.id, therapy, therapyEntry, unknownEntryOfKept] {
            copy[item(id)] = AgentCopyManifestItem(id: item(id), version: 5, digest: "d", deleted: false, sequence: 1)
        }
        let narrowed = AgentCopyNarrowing.removedItems(
            from: settings(all: true, []), to: settings([kept.id]), keys: keys, source: source, copy: copy)
        XCTAssertEqual(
            Set(narrowed),
            [item(dropped.id), item(droppedEntry.id), item(therapy), item(therapyEntry), item(unknownEntryOfKept)])
        XCTAssertFalse(narrowed.contains(item(kept.id)))
        XCTAssertFalse(narrowed.contains(item(keptEntry.id)))

        // Widening removes nothing.
        XCTAssertTrue(
            AgentCopyNarrowing.removedItems(
                from: settings([kept.id]), to: settings(all: true, []), keys: keys, source: source, copy: copy
            ).isEmpty)
    }

    /// Client names are the client's own text: formatting characters that could reorder it are removed, lines are
    /// folded into one, and long names are cut at 40 characters.
    func testClientNamesAreShownWithoutFormattingCharactersOnOneShortLine() {
        XCTAssertEqual(AgentDisplayName.clean("Claude\u{202E}Code"), "ClaudeCode")
        XCTAssertEqual(AgentDisplayName.clean("Claude\u{200B} Code\u{2066}"), "Claude Code")
        XCTAssertEqual(AgentDisplayName.clean("Claude\nCode\r\n\tAgent"), "Claude Code Agent")
        XCTAssertEqual(AgentDisplayName.clean("\u{202E}\n "), "An agent")
        XCTAssertEqual(
            AgentDisplayName.clean("An agent with a remarkably long self-chosen name, longer than forty"),
            "An agent with a remarkably long self-cho…")
    }

    /// Images embedded as `data:` URIs in Markdown source or raw HTML reach an agent as a short placeholder instead
    /// of megabytes of encoded data. What is stored stays exactly as written.
    func testEmbeddedImageDataIsLeftOutOfWhatAnAgentReads() async throws {
        let payload = String(repeating: "iVBORw0KGgo", count: 500)
        var source = JournalDocument(markdown: "Before ![A photo](data:image/png;base64,\(payload)) after")
        source.requiresSource = true
        XCTAssertEqual(
            AgentCopyText.readable(source), "Before ![A photo](data:image/png;base64,[data omitted]) after")
        XCTAssertTrue(source.markdown.contains(payload))
        let html = JournalDocument(markdown: "Notes\n\n<img alt=\"Scan\" src=\"DATA:image/jpeg;base64,\(payload)\">\n")
        let readable = AgentCopyText.readable(html)
        XCTAssertTrue(readable.contains(#"src="DATA:image/jpeg;base64,[data omitted]">"#), readable)
        XCTAssertFalse(readable.contains(payload))
    }

    /// protocol/conformance/agent-copy/agent-copy-v1.json: the app's item IDs, digests, sealed items and key wraps match the public
    /// corpus the server and other clients are checked against.
    func testPublicAgentCopyFixture() throws {
        let data = try Conformance.data("agent-copy/agent-copy-v1.json")
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let item = try XCTUnwrap(fixture["item"] as? [String: Any])
        let wrap = try XCTUnwrap(fixture["wrap"] as? [String: Any])
        func bytes(_ object: [String: Any], _ name: String) throws -> Data {
            try XCTUnwrap(Data(base64Encoded: XCTUnwrap(object[name] as? String)))
        }
        let copyKey = try bytes(fixture, "copyKey")
        let grant = try XCTUnwrap(UUID(uuidString: XCTUnwrap(fixture["grantId"] as? String)))
        let keys = try AgentCopyKeys(copyKey)
        let record = try XCTUnwrap(UUID(uuidString: XCTUnwrap(item["recordId"] as? String)))
        let itemID = keys.itemID(recordID: record)
        XCTAssertEqual(itemID, item["itemId"] as? String)
        XCTAssertEqual(keys.digest(try bytes(item, "plaintext")), item["digest"] as? String)
        let opened = try AgentCopyCrypto.open(
            XCTUnwrap(item["combined"] as? String), itemID: itemID, grantID: grant, keys: keys)
        XCTAssertEqual(opened.title, "Fixture entry")
        XCTAssertThrowsError(
            try AgentCopyCrypto.open(
                XCTUnwrap(item["combined"] as? String), itemID: itemID, grantID: UUID(), keys: keys))
        // The wrap opens with its secret and the grant's context, as the server opens it.
        let wrapKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: try bytes(wrap, "secret")),
            info: Data("journal:v1:agent-grant-wrap".utf8), outputByteCount: 32)
        let unwrapped = try AES.GCM.open(
            AES.GCM.SealedBox(combined: bytes(wrap, "wrappedKey")), using: wrapKey,
            authenticating: Data(AgentCopyCrypto.grantContext(grantID: grant).utf8))
        XCTAssertEqual(unwrapped, copyKey)
        let rewrapped = try AgentCopyCrypto.wrapCopyKey(copyKey, secret: bytes(wrap, "secret"), grantID: grant)
        XCTAssertEqual(
            try AES.GCM.open(
                AES.GCM.SealedBox(combined: rewrapped), using: wrapKey,
                authenticating: Data(AgentCopyCrypto.grantContext(grantID: grant).utf8)), copyKey)
    }

    /// Saves records as if they arrived from the server at `cursor`, with nothing left to send.
    /// After a synchronization that leaves an agent's journals as they were, publishing sends nothing: the copy isn't
    /// uploaded or marked complete again. What changed is published once.
    func testPublishingSendsOnlyWhatChangedForAnAgent() async throws {
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        let work = JournalItem(kind: "journal", title: "Work")
        let personal = JournalItem(kind: "journal", title: "Personal")
        var plans = JournalItem(kind: "entry", journalID: work.id, title: "Plans", document: .plain("First"))
        try await synchronized(store, [work, personal, plans], cursor: 3)
        let grant = UUID()
        let settings = AgentCopySettings(
            name: "Claude", clientName: "Claude Code", journalIDs: [work.id], expiresAt: nil,
            key: try VaultCrypto.random(32))
        let metadata = try AgentCopyCrypto.sealSettings(
            settings, grantID: grant, vaultKey: await store.key)
        let server = RecordingAgentServer(grant: grant, metadata: metadata)
        let publisher = AgentCopyPublisher(store: store, server: server)
        try await publisher.publishAll()
        var uploads = await server.uploads
        XCTAssertEqual(uploads.map(\.items), [2])
        XCTAssertEqual(uploads.map(\.complete), [true])

        // A synchronization brought an entry of a journal the agent doesn't read.
        try await synchronized(store, [JournalItem(kind: "entry", journalID: personal.id, title: "Diary")], cursor: 4)
        try await publisher.publishAll()
        try await publisher.publishAll()
        uploads = await server.uploads
        let lists = await server.lists
        XCTAssertEqual(uploads.count, 1, "Nothing is sent for a copy that is complete and current")
        XCTAssertEqual(lists, 2, "The list is read again only when there's something new")

        plans.document = .plain("Second")
        try await synchronized(store, [plans], cursor: 6)
        try await publisher.publishAll()
        uploads = await server.uploads
        XCTAssertEqual(uploads.count, 2)
        XCTAssertEqual(uploads.last?.items, 1, "Only the edited entry is uploaded")
        XCTAssertNil(uploads.last?.complete)

        // The device that wrote the next edit published it before this one received it.
        plans.document = .plain("Third")
        let keys = try AgentCopyKeys(settings.key)
        await server.publishElsewhere(keys.itemID(recordID: plans.id), version: 7)
        try await synchronized(store, [plans], cursor: 7)
        try await publisher.publishAll()
        uploads = await server.uploads
        XCTAssertEqual(uploads.count, 2, "What another device published from the same state isn't uploaded again")
    }

    private func synchronized(_ store: JournalStore, _ items: [JournalItem], cursor: Int64) async throws {
        var changes: [RemoteChange] = []
        for (index, item) in items.enumerated() {
            let payload = try await store.encode(item)
            changes.append(
                RemoteChange(
                    cursor: cursor - Int64(items.count) + Int64(index) + 1, recordId: item.id,
                    revision: cursor + Int64(index), kind: item.kind, payload: payload, deviceId: UUID(),
                    modifiedAt: Date()))
        }
        try await store.apply(changes, cursor: cursor)
    }
}

/// A server with one agent that keeps its copy and records what a device asks of it.
private actor RecordingAgentServer: AgentCopyServer {
    private let grant: UUID
    private let metadata: String
    private var complete = false
    private var items: [String: AgentCopyManifestItem] = [:]
    private var sequence: Int64 = 0
    private(set) var lists = 0
    private(set) var uploads: [(items: Int, complete: Bool?)] = []

    init(grant: UUID, metadata: String) {
        self.grant = grant
        self.metadata = metadata
    }
    func agents() -> [ServerAgent] {
        lists += 1
        return [
            ServerAgent(
                id: grant, state: .active, clientName: "Claude Code", clientId: "client", redirectHost: "127.0.0.1",
                createdAt: Date(), expiresAt: nil, lastUsedAt: nil, updatedAt: nil, copyComplete: complete,
                metadata: metadata, revision: 1)
        ]
    }
    func agentManifest(_ id: UUID, after: Int64) -> AgentCopyPage<AgentCopyManifestItem> {
        let newer = items.values.filter { $0.sequence > after }.sorted { $0.sequence < $1.sequence }
        return AgentCopyPage(items: newer, cursor: newer.last?.sequence ?? after, hasMore: false)
    }
    /// Another device of the library publishes an item.
    func publishElsewhere(_ id: String, version: Int64) {
        sequence += 1
        items[id] = AgentCopyManifestItem(id: id, version: version, digest: "", deleted: false, sequence: sequence)
    }
    func uploadAgentItems(_ id: UUID, revision: Int64, items batch: [AgentCopyUpload], complete: Bool?)
        -> [AgentCopyManifestItem]
    {
        uploads.append((batch.count, complete))
        for item in batch {
            sequence += 1
            items[item.id] = AgentCopyManifestItem(
                id: item.id, version: item.version, digest: item.digest, deleted: item.payload == nil,
                sequence: sequence)
        }
        if complete == true { self.complete = true }
        return []
    }
    func revokeAgent(_ id: UUID) throws { throw JournalError.invalidData }
    func approveAgentRequest(
        _ id: UUID, number: Int, grantID: UUID, metadata: String?, wrappedKey: Data, secret: Data, expiresAt: Date?
    ) throws { throw JournalError.invalidData }
    func agentRequestReady(_ id: UUID, complete: Bool) throws { throw JournalError.invalidData }
    func declineAgentRequest(_ id: UUID) throws { throw JournalError.invalidData }
    func agentActivity(_ id: UUID) throws -> [AgentActivityEvent] { throw JournalError.invalidData }
    func changeAgent(_ id: UUID, revision: Int64, metadata: String, expiresAt: Date?, removedItems: [String]) throws
        -> Int64
    { throw JournalError.invalidData }
}
