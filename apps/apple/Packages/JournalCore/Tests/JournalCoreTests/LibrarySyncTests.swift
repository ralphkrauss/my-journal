import CryptoKit
import GRDB
import XCTest

@testable import JournalCore

/// The library record, which holds pins and journal order (docs/design/pinned-entries.md, "Data and sync design"):
/// per-key merging instead of reviews, the capability gate, restores and older versions.
final class LibrarySyncTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("library-\(UUID().uuidString)")
    private let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Helpers

    private func device(_ name: String, protection: ContentProtection = .encrypted, key: Data? = nil) throws
        -> JournalStore
    {
        let store = try JournalStore(
            directory: root.appendingPathComponent(name), key: key ?? self.key, protection: protection)
        addTeardownBlock { try? await store.close() }
        return store
    }
    /// A journal and two entries in it, saved on `store`.
    private func journalWithEntries(_ store: JournalStore, title: String = "Work", count: Int = 2) async throws
        -> (journal: JournalItem, entries: [JournalItem])
    {
        let journal = JournalItem(kind: "journal", title: title)
        try await store.save(journal)
        var entries: [JournalItem] = []
        for index in 0..<count {
            let entry = JournalItem(
                kind: "entry", journalID: journal.id, title: "\(title) \(index)", document: .plain("Text \(index)"),
                date: Date(timeIntervalSince1970: 1_800_000_000 + Double(index) * 86_400))
            try await store.save(entry)
            entries.append(entry)
        }
        return (journal, entries)
    }
    private func pinned(_ store: JournalStore) async throws -> Set<UUID> {
        try await store.libraryArrangement().pinned
    }
    private func libraryPushes(_ server: MemoryServer) async -> [PendingChange] {
        await server.pushes.filter { $0.kind == LibraryRecord.kind }
    }
    private func conflictCount(_ store: JournalStore) async throws -> Int {
        try await store.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM conflicts") ?? 0 }
    }
    private func libraryHistoryCount(_ store: JournalStore) async throws -> Int {
        try await store.db.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM history WHERE kind='library'") ?? 0
        }
    }
    /// The library record as another client writes it, sealed for `store`'s library.
    private func libraryPayload(_ object: [String: Any], for store: JournalStore) async throws -> String {
        var record = object
        record["id"] = record["id"] ?? LibraryRecord.id.uuidString
        record["kind"] = record["kind"] ?? LibraryRecord.kind
        record["modifiedAt"] = record["modifiedAt"] ?? "2026-10-03T12:00:00Z"
        record["title"] = record["title"] ?? "Pinned Entries and Journal Order"
        record["version"] = record["version"] ?? 1
        let json = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        return try await store.sealedPayload(json, id: LibraryRecord.id, kind: LibraryRecord.kind)
    }
    /// Sends a change as another device would, straight to the server.
    private func write(
        _ payload: String, kind: String = LibraryRecord.kind, id: UUID = LibraryRecord.id, to server: MemoryServer
    )
        async throws
    {
        let base = await server.record(id)?.revision ?? 0
        let result = try await server.push(
            PendingChange(operationId: UUID(), recordID: id, baseRevision: base, kind: kind, payload: payload),
            serverID: nil, shortReceipt: false)
        guard case .accepted = result else { return XCTFail("The server refused the change") }
    }
    private func pinKey(_ id: UUID) -> String { "pinned/\(id.uuidString.lowercased())" }
    private func stored(_ store: JournalStore, _ id: UUID) async throws -> JournalItem {
        let item = try await store.item(id)
        return try XCTUnwrap(item)
    }

    // MARK: 1–3: merging instead of reviews

    func testPinsOfDifferentEntriesOnTwoDevicesBothSurviveInEitherOrder() async throws {
        for macFirst in [true, false] {
            let server = MemoryServer()
            let mac = try device("mac-\(macFirst)")
            let phone = try device("phone-\(macFirst)")
            let macSync = SyncEngine(store: mac, server: server)
            let phoneSync = SyncEngine(store: phone, server: server)
            let (_, entries) = try await journalWithEntries(mac)
            try await macSync.synchronize()
            try await phoneSync.synchronize()

            try await mac.setPinned(true, entry: entries[0].id)
            try await phone.setPinned(true, entry: entries[1].id)
            // A refused push is merged and sent again by the next synchronization.
            let order =
                macFirst
                ? [macSync, phoneSync, macSync, phoneSync, macSync]
                : [phoneSync, macSync, phoneSync, macSync, phoneSync]
            for engine in order { try await engine.synchronize() }

            let expected = Set(entries.map(\.id))
            let onMac = try await pinned(mac)
            let onPhone = try await pinned(phone)
            XCTAssertEqual(onMac, expected)
            XCTAssertEqual(onPhone, expected)
            let reviews = try await conflictCount(mac) + conflictCount(phone)
            XCTAssertEqual(reviews, 0, "Pins never become changes to review")
            let onServer = await server.libraryValues(openedBy: mac)
            XCTAssertEqual(onServer.map { Set($0.keys) }, Set(entries.map { pinKey($0.id) }))
        }
    }

    func testTheSameKeyChangedOnTwoDevicesTakesTheValueSyncedLastWithANewOperation() async throws {
        let server = MemoryServer()
        let mac = try device("mac")
        let phone = try device("phone")
        let macSync = SyncEngine(store: mac, server: server)
        let phoneSync = SyncEngine(store: phone, server: server)
        let (_, entries) = try await journalWithEntries(mac)
        let entry = entries[0].id
        try await macSync.synchronize()
        try await phoneSync.synchronize()

        // Pinned on the Mac; pinned and unpinned again on the phone, which syncs last.
        try await mac.setPinned(true, entry: entry)
        try await phone.setPinned(true, entry: entry)
        try await phone.setPinned(false, entry: entry)
        try await macSync.synchronize()
        let refused = try await phoneSync.synchronize()
        XCTAssertNil(refused.problem, "A refused library push is merged, never reported")
        try await phoneSync.synchronize()
        try await macSync.synchronize()

        let onMac = try await pinned(mac)
        let onPhone = try await pinned(phone)
        XCTAssertEqual(onMac, [])
        XCTAssertEqual(onPhone, [])
        let onServer = await server.libraryValues(openedBy: mac)
        XCTAssertEqual(onServer, [:])
        let operations = Dictionary(grouping: await libraryPushes(server), by: \.operationId)
        XCTAssertTrue(
            operations.values.allSatisfy { Set($0.map(\.payload)).count == 1 },
            "An operation is never sent again with other content")
        let reviews = try await conflictCount(mac) + conflictCount(phone)
        XCTAssertEqual(reviews, 0)

        // The same pin made on both devices: the merge equals the server's version, so nothing more is sent.
        let other = entries[1].id
        try await mac.setPinned(true, entry: other)
        try await phone.setPinned(true, entry: other)
        try await macSync.synchronize()
        let before = await libraryPushes(server).count
        try await phoneSync.synchronize()
        try await phoneSync.synchronize()
        let after = await libraryPushes(server).count
        XCTAssertEqual(after - before, 1, "Only the refused push; the merge equal to the server's sends nothing")
        let waiting = try await phone.pending()
        XCTAssertTrue(waiting.isEmpty)
        let intents = try await phone.libraryChanges()
        XCTAssertTrue(intents.isEmpty)
    }

    func testAPinWhoseAnswerWasLostIsAcknowledgedWhenReadBack() async throws {
        let server = MemoryServer()
        let mac = try device("mac")
        let macSync = SyncEngine(store: mac, server: server)
        let (_, entries) = try await journalWithEntries(mac)
        try await macSync.synchronize()

        try await mac.setPinned(true, entry: entries[0].id)
        await server.loseNextAnswer()
        do {
            try await macSync.synchronize()
            XCTFail("The lost answer stops the synchronization")
        } catch {}
        // Reading the log brings the device's own change back.
        let cursor = try await mac.cursor()
        let page = try await server.changes(after: cursor, limit: 100, applied: nil)
        try await mac.apply(page.changes, cursor: page.cursor)

        let intents = try await mac.libraryChanges()
        XCTAssertTrue(intents.isEmpty, "Reading its own change back clears what it asked for")
        let waiting = try await mac.pending()
        XCTAssertTrue(waiting.isEmpty)
        let pushes = await libraryPushes(server).count
        try await macSync.synchronize()
        let later = await libraryPushes(server).count
        XCTAssertEqual(later, pushes, "Nothing is merged or sent twice")
        let reviews = try await conflictCount(mac)
        XCTAssertEqual(reviews, 0)
        let shown = try await pinned(mac)
        XCTAssertEqual(shown, [entries[0].id])
    }

    // MARK: 4–5: newer and older versions

    /// A library record from a newer version is never written over: importing an archive still imports its journals,
    /// and a server that lost the record gets it back as it was.
    func testANewerRecordIsKeptThroughAnImportAndAServerRestore() async throws {
        let server = MemoryServer()
        let mac = try device("mac")
        let macSync = SyncEngine(store: mac, server: server)
        _ = try await journalWithEntries(mac, title: "Home")
        try await macSync.synchronize()
        let backup = await server.state
        let newer = try await libraryPayload(["version": 2, "values": "a different shape"], for: mac)
        try await write(newer, to: server)
        try await macSync.synchronize()

        let source = try device("source")
        let (_, imported) = try await journalWithEntries(source, title: "Imported")
        try await source.setPinned(true, entry: imported[0].id)
        try await mac.importAsNewJournals(from: source)
        let titles = try await mac.arrangedJournals().map(\.title)
        XCTAssertEqual(Set(titles), ["Home", "Imported"])

        await server.restore(backup, identity: "restored")
        try await macSync.synchronize()
        try await macSync.synchronize()
        let onServer = await server.record(LibraryRecord.id)?.payload
        XCTAssertEqual(onServer, newer, "Sent again unchanged")
        let local = try await mac.db.read {
            try String.fetchOne($0, sql: "SELECT payload FROM records WHERE id=?", arguments: [LibraryRecord.idText])
        }
        XCTAssertEqual(local, newer)
    }

    func testUnknownMembersSurviveAndANewerVersionIsNeverWritten() async throws {
        let server = MemoryServer()
        let mac = try device("mac")
        let macSync = SyncEngine(store: mac, server: server)
        let (_, entries) = try await journalWithEntries(mac)
        try await macSync.synchronize()
        let future: [String: Any] = ["note": "kept", "list": [1, 2.5, "three"]]
        try await write(
            libraryPayload(
                ["future": future, "values": ["pinned/\(UUID().uuidString.lowercased())": true, "label/x": ["a": 1]]],
                for: mac), to: server)
        try await macSync.synchronize()

        // A newer device changes the record while this one pins: the push is refused and merged.
        try await write(
            libraryPayload(
                ["future": future, "values": ["label/x": ["a": 1], "label/y": "two"]], for: mac), to: server)
        try await mac.setPinned(true, entry: entries[0].id)
        try await macSync.synchronize()
        try await macSync.synchronize()

        let stored = await server.record(LibraryRecord.id)
        let record = try XCTUnwrap(stored)
        let plaintext = try await mac.openedPayload(record.payload, id: LibraryRecord.id, kind: LibraryRecord.kind)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: plaintext) as? [String: Any])
        XCTAssertEqual(object["future"] as? NSDictionary, future as NSDictionary)
        let values = try XCTUnwrap(object["values"] as? [String: Any])
        XCTAssertEqual(values["label/x"] as? NSDictionary, ["a": 1] as NSDictionary)
        XCTAssertEqual(values["label/y"] as? String, "two")
        XCTAssertEqual(values[pinKey(entries[0].id)] as? Bool, true)

        // Version 2 is kept byte for byte, and this version never writes over it.
        let newer = try await libraryPayload(["version": 2, "values": "a different shape"], for: mac)
        try await write(newer, to: server)
        try await mac.setPinned(true, entry: entries[1].id)
        try await macSync.synchronize()
        try await macSync.synchronize()
        let kept = await server.record(LibraryRecord.id)?.payload
        XCTAssertEqual(kept, newer)
        let local = try await mac.db.read {
            try String.fetchOne($0, sql: "SELECT payload FROM records WHERE id=?", arguments: [LibraryRecord.idText])
        }
        XCTAssertEqual(local, newer)
        let arrangement = try await mac.libraryArrangement()
        XCTAssertFalse(arrangement.available)
        XCTAssertEqual(arrangement.pinned, [])
        do {
            try await mac.setPinned(false, entry: entries[0].id)
            XCTFail("A newer library record can't be changed")
        } catch {}
        let state = try await mac.librarySyncState()
        XCTAssertTrue(state.needsUpdate)
    }

    /// The generic path versions without the library record use for it: a kind they don't know.
    func testARecordOfAnUnknownKindStaysInvisibleAndUnchangedThroughSyncArchiveAndRestore() async throws {
        let server = MemoryServer()
        let mac = try device("mac")
        let macSync = SyncEngine(store: mac, server: server)
        let (journal, _) = try await journalWithEntries(mac)
        try await macSync.synchronize()
        let backup = await server.state
        let unknownID = UUID()
        let json = Data(
            #"{"id":"\#(unknownID)","kind":"notebook","modifiedAt":"2026-10-03T12:00:00Z","title":"Later"}"#.utf8)
        let payload = try await mac.sealedPayload(json, id: unknownID, kind: "notebook")
        try await write(payload, kind: "notebook", id: unknownID, to: server)
        let before = try await mac.lifecycleSnapshot()
        try await macSync.synchronize()

        let snapshot = try await mac.viewSnapshot()
        if let unknown = snapshot.items.first(where: { $0.id == unknownID }) {
            XCTAssertFalse(unknown.document.isEditable, "Kept read-only")
        }
        let lifecycle = try await mac.lifecycleSnapshot()
        XCTAssertEqual(lifecycle.liveJournals.map(\.id), before.liveJournals.map(\.id))
        XCTAssertEqual(lifecycle.liveJournals.map(\.id), [journal.id])
        let contents = LibraryContents(items: snapshot.items, conflicts: 0)
        XCTAssertEqual(contents.journals, 1)
        XCTAssertEqual(contents.entries, 2)
        let count = try await mac.pendingItemCount()
        XCTAssertEqual(count, 0)

        // Archived and restored unchanged.
        let phrase = try VaultCrypto.recoveryPhrase()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase)
        let archive = root.appendingPathComponent("unknown.journalarchive")
        try await VaultArchive.export(store: mac, recovery: recovery.0, key: key, to: archive)
        let restored = try await VaultArchive.restore(
            from: archive, to: root.appendingPathComponent("restored"), phrase: phrase)
        addTeardownBlock { try? await restored.store.close() }
        let copied = try await restored.store.db.read {
            try String.fetchOne(
                $0, sql: "SELECT payload FROM records WHERE id=?", arguments: [unknownID.uuidString.lowercased()])
        }
        XCTAssertEqual(copied, payload)

        // A server restored from a backup without it gets it again, unchanged.
        await server.restore(backup, identity: "restored")
        try await macSync.synchronize()
        let again = await server.record(unknownID)?.payload
        XCTAssertEqual(again, payload)
        let reviews = try await conflictCount(mac)
        XCTAssertEqual(reviews, 0)
    }

    // MARK: 6–7: archives

    func testUnsentPinsInARestoredArchiveReachTheServer() async throws {
        let mac = try device("mac")
        let (_, entries) = try await journalWithEntries(mac)
        try await mac.setPinned(true, entry: entries[1].id)
        let phrase = try VaultCrypto.recoveryPhrase()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase)
        let archive = root.appendingPathComponent("pins.journalarchive")
        try await VaultArchive.export(store: mac, recovery: recovery.0, key: key, to: archive)
        let restored = try await VaultArchive.restore(
            from: archive, to: root.appendingPathComponent("restored"), phrase: phrase)
        addTeardownBlock { try? await restored.store.close() }

        let server = MemoryServer()
        try await SyncEngine(store: restored.store, server: server).synchronize()
        let phone = try device("phone")
        try await SyncEngine(store: phone, server: server).synchronize()
        let onPhone = try await pinned(phone)
        XCTAssertEqual(onPhone, [entries[1].id])
    }

    // MARK: 8: restores, rollbacks and leftovers from older versions

    func testARestoredServerThatLostAnAcknowledgedPinGetsItAgainWithoutAReview() async throws {
        let server = MemoryServer()
        let mac = try device("mac")
        let phone = try device("phone")
        let macSync = SyncEngine(store: mac, server: server)
        let (_, entries) = try await journalWithEntries(mac)
        try await macSync.synchronize()
        let backup = await server.state
        try await mac.setPinned(true, entry: entries[0].id)
        try await macSync.synchronize()

        await server.restore(backup, identity: "restored")
        try await macSync.synchronize()
        try await macSync.synchronize()
        try await SyncEngine(store: phone, server: server).synchronize()
        let onPhone = try await pinned(phone)
        XCTAssertEqual(onPhone, [entries[0].id])
        let reviews = try await conflictCount(mac)
        XCTAssertEqual(reviews, 0)
    }

    func testADeviceThatWasBehindAtARestoreDoesNotRevertNewerChanges() async throws {
        let server = MemoryServer()
        let mac = try device("mac")
        let iPad = try device("ipad")
        let macSync = SyncEngine(store: mac, server: server)
        let iPadSync = SyncEngine(store: iPad, server: server)
        let (_, entries) = try await journalWithEntries(mac, count: 4)
        try await mac.setPinned(true, entry: entries[0].id)
        try await mac.setPinned(true, entry: entries[1].id)
        try await macSync.synchronize()
        try await iPadSync.synchronize()
        // Newer revisions the iPad never read: an unpin and a pin.
        try await mac.setPinned(false, entry: entries[0].id)
        try await macSync.synchronize()
        try await mac.setPinned(true, entry: entries[2].id)
        try await macSync.synchronize()
        let backup = await server.state
        await server.restore(backup, identity: "restored")

        try await iPadSync.synchronize()
        try await iPadSync.synchronize()
        let onIPad = try await pinned(iPad)
        XCTAssertEqual(onIPad, [entries[1].id, entries[2].id], "The unpin and the pin it never read stand")
        let onServer = await server.libraryValues(openedBy: iPad)
        XCTAssertEqual(onServer.map { Set($0.keys) }, [pinKey(entries[1].id), pinKey(entries[2].id)])
    }

    func testSigningInAfterEncryptionWasTurnedOnElsewhereAddsOnlyWhatTheServerLacks() async throws {
        let server = MemoryServer()
        let mac = try device("mac", protection: .plaintext)
        let phone = try device("phone", protection: .plaintext)
        let macSync = SyncEngine(store: mac, server: server)
        let phoneSync = SyncEngine(store: phone, server: server)
        let (_, entries) = try await journalWithEntries(mac, count: 3)
        let more = JournalItem(kind: "journal", title: "Travel")
        try await mac.save(more)
        try await mac.setPinned(true, entry: entries[0].id)
        try await mac.setPinned(true, entry: entries[1].id)
        try await macSync.synchronize()
        try await phoneSync.synchronize()

        // The Mac moves a journal, then turns on encryption, which empties the server.
        let shown = try await mac.arrangedJournals().map(\.id)
        try await mac.moveJournal(more.id, shown: shown, to: 0)
        try await macSync.synchronize()
        let newKey = try VaultCrypto.generateKey()
        let encrypted = try await mac.reencryptedCopy(
            to: root.appendingPathComponent("mac-encrypted"), key: newKey, baseline: .restart)
        addTeardownBlock { try? await encrypted.close() }
        await server.restore(.init(), identity: "encrypted")
        try await SyncEngine(store: encrypted, server: server).synchronize()

        // The phone, offline meanwhile, pinned an entry, unpinned another and moved the same journal.
        try await phone.setPinned(true, entry: entries[2].id)
        try await phone.setPinned(false, entry: entries[0].id)
        let phoneShown = try await phone.arrangedJournals().map(\.id)
        try await phone.moveJournal(more.id, shown: phoneShown, to: phoneShown.count - 1)
        let signedIn = try await phone.reencryptedCopy(
            to: root.appendingPathComponent("phone-encrypted"), key: newKey, baseline: .reconcile)
        addTeardownBlock { try? await signedIn.close() }
        let signedInSync = SyncEngine(store: signedIn, server: server)
        try await signedInSync.synchronize()
        try await signedInSync.synchronize()
        try await SyncEngine(store: encrypted, server: server).synchronize()

        let onPhone = try await signedIn.libraryArrangement()
        let onMac = try await encrypted.libraryArrangement()
        XCTAssertEqual(onPhone, onMac)
        XCTAssertEqual(onPhone.pinned, [entries[1].id, entries[2].id], "The never-sent unpin still applies")
        let order = try await encrypted.arrangedJournals().map(\.id)
        XCTAssertEqual(order.last, more.id, "The phone's never-sent move applies")
        let reviews = try await conflictCount(signedIn)
        XCTAssertEqual(reviews, 0)
    }

    func testAnotherVersionAtTheSameRevisionAfterARollbackDoesNotUnpinItsPins() async throws {
        let server = MemoryServer()
        let mac = try device("mac")
        let phone = try device("phone")
        let macSync = SyncEngine(store: mac, server: server)
        let phoneSync = SyncEngine(store: phone, server: server)
        let (_, entries) = try await journalWithEntries(mac, count: 3)
        try await mac.setPinned(true, entry: entries[0].id)
        try await macSync.synchronize()
        try await phoneSync.synchronize()
        let snapshot = await server.state
        try await mac.setPinned(true, entry: entries[1].id)
        try await macSync.synchronize()

        // The server's data folder is copied back: it loses the Mac's pin and gives its revision to the phone's.
        await server.rollBack(to: snapshot)
        let unrelated = JournalItem(kind: "entry", journalID: entries[0].journalID, document: .plain("Elsewhere"))
        try await phone.save(unrelated)
        try await phoneSync.synchronize()
        try await phone.setPinned(true, entry: entries[2].id)
        try await phoneSync.synchronize()
        try await macSync.synchronize()
        try await macSync.synchronize()
        try await phoneSync.synchronize()

        let onPhone = try await pinned(phone)
        let onMac = try await pinned(mac)
        XCTAssertTrue(onMac.contains(entries[2].id), "The phone's new pin stands")
        XCTAssertEqual(onMac, Set(entries.map(\.id)))
        XCTAssertEqual(onPhone, onMac)
        let reviews = try await conflictCount(mac)
        XCTAssertEqual(reviews, 0)
    }

    func testAPinSentWithoutAnAnswerDoesNotUndoALaterUnpinAfterARestore() async throws {
        let server = MemoryServer()
        let mac = try device("mac")
        let phone = try device("phone")
        let macSync = SyncEngine(store: mac, server: server)
        let phoneSync = SyncEngine(store: phone, server: server)
        let (_, entries) = try await journalWithEntries(mac)
        try await macSync.synchronize()
        try await phoneSync.synchronize()
        try await mac.setPinned(true, entry: entries[0].id)
        await server.loseNextAnswer()
        _ = try? await macSync.synchronize()
        try await phoneSync.synchronize()
        try await phone.setPinned(false, entry: entries[0].id)
        try await phoneSync.synchronize()

        let current = await server.state
        await server.restore(current, identity: "restored")
        try await macSync.synchronize()
        try await macSync.synchronize()
        let onMac = try await pinned(mac)
        XCTAssertEqual(onMac, [])
        let onServer = await server.libraryValues(openedBy: mac)
        XCTAssertEqual(onServer, [:])
    }

    func testAReviewOrHistoryAnOlderVersionKeptForTheLibraryIsMergedWhenTheStoreOpens() async throws {
        for revision: Int64 in [2, 0] {
            let server = MemoryServer()
            let name = "mac-\(revision)"
            var mac: JournalStore? = try device(name)
            let store = try XCTUnwrap(mac)
            let (_, entries) = try await journalWithEntries(store, count: 3)
            try await store.setPinned(true, entry: entries[0].id)
            try await SyncEngine(store: store, server: server).synchronize()
            let other = try await libraryPayload(
                ["values": [pinKey(entries[0].id): true, pinKey(entries[1].id): true]], for: store)
            try await store.close()
            mac = nil

            // What build 12 left behind: the other version kept for review, and a library version in history.
            let database = try DatabaseQueue(path: root.appendingPathComponent("\(name)/journal.sqlite").path)
            try await database.write { db in
                try db.execute(
                    sql: "INSERT INTO conflicts(record,payload,revision,device,modified) VALUES (?,?,?,?,?)",
                    arguments: [
                        LibraryRecord.idText, other, revision, "00000000-0000-0000-0000-000000000000",
                        "2026-10-03T12:00:00Z",
                    ])
                try db.execute(
                    sql: "INSERT INTO history(record,kind,payload,saved) VALUES (?,?,?,?)",
                    arguments: [LibraryRecord.idText, LibraryRecord.kind, other, "2026-10-03T12:00:00Z"])
                try db.execute(sql: "UPDATE records SET dirty=1 WHERE id=?", arguments: [LibraryRecord.idText])
            }
            try database.close()

            let reopened = try device(name)
            let reviews = try await conflictCount(reopened)
            XCTAssertEqual(reviews, 0)
            let history = try await libraryHistoryCount(reopened)
            XCTAssertEqual(history, 0)
            let shown = try await pinned(reopened)
            XCTAssertEqual(shown, [entries[0].id, entries[1].id])
            if revision == 0 {
                let queued = try await reopened.pending().filter { $0.kind == LibraryRecord.kind }
                XCTAssertEqual(queued.map(\.baseRevision), [0])
            }
        }
    }

    /// Another version at the revision a queued change is based on (a fork after a rollback), which the queued change's
    /// values already cover but with a member a newer version added: the change sent is the merge, keeping it.
    func testAQueuedChangeWithTheSameValuesStillTakesTheOtherVersionsMembers() async throws {
        let server = MemoryServer()
        let mac = try device("mac")
        let macSync = SyncEngine(store: mac, server: server)
        let (_, entries) = try await journalWithEntries(mac)
        try await mac.setPinned(true, entry: entries[0].id)
        try await macSync.synchronize()
        try await mac.setPinned(true, entry: entries[1].id)
        let onServer = await server.record(LibraryRecord.id)
        let revision = try XCTUnwrap(onServer).revision
        let other = try await libraryPayload(
            ["future": "kept", "values": [pinKey(entries[0].id): true]], for: mac)
        let change = RemoteChange(
            cursor: 0, recordId: LibraryRecord.id, revision: revision, kind: LibraryRecord.kind, payload: other,
            deviceId: UUID(), modifiedAt: Date())
        try await mac.apply([change], cursor: try await mac.cursor())
        let queued = try await mac.pending().filter { $0.kind == LibraryRecord.kind }
        let payload = try XCTUnwrap(queued.first?.payload)
        let plaintext = try await mac.openedPayload(payload, id: LibraryRecord.id, kind: LibraryRecord.kind)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: plaintext) as? [String: Any])
        XCTAssertEqual(object["future"] as? String, "kept")
    }

    // MARK: 9–12: import, lifecycle, sealing, leftovers

    func testImportingAnArchiveAddsItsPinsAndAppendsItsJournals() async throws {
        let destination = try device("destination")
        let alpha = JournalItem(kind: "journal", title: "Alpha")
        let beta = JournalItem(kind: "journal", title: "Beta")
        try await destination.save(alpha)
        try await destination.save(beta)
        let own = JournalItem(kind: "entry", journalID: alpha.id, document: .plain("Mine"))
        try await destination.save(own)
        try await destination.setPinned(true, entry: own.id)

        let source = try device("source")
        let (zulu, entries) = try await journalWithEntries(source, title: "Zulu")
        let aardvark = JournalItem(kind: "journal", title: "Aardvark")
        try await source.save(aardvark)
        let sourceShown = try await source.arrangedJournals().map(\.id)
        try await source.moveJournal(zulu.id, shown: sourceShown, to: 0)
        try await source.setPinned(true, entry: entries[0].id)

        try await destination.importAsNewJournals(from: source)
        let order = try await destination.arrangedJournals().map(\.title)
        XCTAssertEqual(order, ["Alpha", "Beta", "Zulu", "Aardvark"])
        let items = try await destination.items()
        let imported = try XCTUnwrap(items.first { $0.kind == "entry" && $0.title == entries[0].title })
        let shown = try await pinned(destination)
        XCTAssertEqual(shown, [own.id, imported.id])
        let libraries = try await destination.db.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM records WHERE kind='library'")
        }
        XCTAssertEqual(libraries, 1)
    }

    func testJoiningAServerWithLocalJournalsKeepsOneLibraryRecordAndItsPins() async throws {
        let server = MemoryServer()
        let other = try device("other")
        let (_, serverEntries) = try await journalWithEntries(other, title: "Home")
        try await other.setPinned(true, entry: serverEntries[0].id)
        try await SyncEngine(store: other, server: server).synchronize()

        let local = try device("local")
        let (_, localEntries) = try await journalWithEntries(local, title: "Travel")
        try await local.setPinned(true, entry: localEntries[1].id)
        let staged = try device("staged")
        try await SyncEngine(store: staged, server: server).synchronize()
        try await staged.importMerging(from: local, server: "memory-server", readByAgents: [])
        try await SyncEngine(store: staged, server: server).synchronize()
        try await SyncEngine(store: other, server: server).synchronize()

        let libraries = try await staged.db.read {
            try String.fetchAll($0, sql: "SELECT id FROM records WHERE kind='library'")
        }
        XCTAssertEqual(libraries, [LibraryRecord.idText])
        let onOther = try await pinned(other)
        XCTAssertEqual(onOther.count, 2, "The server's pin and the merged library's pin")
        XCTAssertTrue(onOther.contains(serverEntries[0].id))
        let synced = try await staged.syncedRecordIDs()
        XCTAssertFalse(synced.contains(LibraryRecord.id), "Every library has this record; it proves nothing")
    }

    func testAnUntouchedLibraryWithOnlyALibraryRecordLeftIsStillNothingWritten() async throws {
        let store = try device("untouched")
        let journal = JournalItem(kind: "journal", title: "Default")
        try await store.save(journal)
        var entry = JournalItem(kind: "entry", journalID: journal.id, document: .plain("Gone"))
        try await store.save(entry)
        try await store.setPinned(true, entry: entry.id)
        entry = try await stored(store, entry.id)
        entry.deletedAt = Date()
        try await store.save(entry)
        let confirmation = try await store.preparePermanentDeletion(entry.id)
        try await store.permanentlyDelete(confirmation)
        let items = try await store.items()
        XCTAssertTrue(LibraryContents(items: items, conflicts: 0).nothingWritten)
    }

    func testAPinStaysWithItsEntryThroughDeletionRestorationAndMoves() async throws {
        let store = try device("lifecycle")
        let (journal, entries) = try await journalWithEntries(store, count: 3)
        let other = JournalItem(kind: "journal", title: "Other")
        try await store.save(other)
        var entry = entries[0]
        try await store.setPinned(true, entry: entry.id)

        entry = try await stored(store, entry.id)
        entry.deletedAt = Date()
        try await store.save(entry)
        var shown = try await pinned(store)
        XCTAssertEqual(shown, [entry.id], "Kept while in Recently Deleted")
        entry = try await stored(store, entry.id)
        entry.deletedAt = nil
        try await store.save(entry)
        _ = try await store.moveEntry(entry.id, to: other.id)
        entry = try await stored(store, entry.id)
        entry.deletedAt = Date()
        try await store.save(entry)
        _ = try await store.restoreEntry(entry.id, fallback: journal.id)
        shown = try await pinned(store)
        XCTAssertEqual(shown, [entry.id])

        // A permanently deleted entry's pin is ignored, and removed with the next change to pins.
        try await store.setPinned(true, entry: entries[1].id)
        var deleted = try await stored(store, entries[1].id)
        deleted.deletedAt = Date()
        try await store.save(deleted)
        let confirmation = try await store.preparePermanentDeletion(deleted.id)
        try await store.permanentlyDelete(confirmation)
        shown = try await pinned(store)
        XCTAssertEqual(shown, [entry.id])
        // A pin for an entry this device hasn't received yet is never removed.
        let notYetHere = UUID()
        try await store.setLibraryValues([pinKey(notYetHere): .bool(true)])
        try await store.setPinned(true, entry: entries[2].id)
        let values = try await store.libraryValues()
        XCTAssertNil(values[pinKey(entries[1].id)])
        XCTAssertEqual(values[pinKey(notYetHere)], .bool(true))
        XCTAssertEqual(values[pinKey(entries[2].id)], .bool(true))
    }

    func testTurningOnEncryptionSealsUnsentChangesAndADamagedValueBlocksNothing() async throws {
        let plain = try device("plain", protection: .plaintext)
        let (_, entries) = try await journalWithEntries(plain)
        try await plain.setPinned(true, entry: entries[0].id)
        let raw = try await plain.setting(LibraryChanges.setting)
        let plaintextValue = try XCTUnwrap(raw)
        XCTAssertNotNil(
            Data(base64Encoded: plaintextValue).flatMap { try? JSONSerialization.jsonObject(with: $0) },
            "Readable in a library without encryption")
        let newKey = try VaultCrypto.generateKey()
        let copy = try await plain.reencryptedCopy(
            to: root.appendingPathComponent("sealed"), key: newKey, baseline: .reconcile)
        addTeardownBlock { try? await copy.close() }
        let sealed = try await copy.setting(LibraryChanges.setting)
        let sealedValue = try XCTUnwrap(sealed)
        XCTAssertNil(Data(base64Encoded: sealedValue).flatMap { try? JSONSerialization.jsonObject(with: $0) })
        let intents = try await copy.libraryChanges()
        XCTAssertEqual(Set(intents.keys), [pinKey(entries[0].id)])

        // A value that can't be opened: the library opens, pins and syncs.
        try await copy.setSetting(LibraryChanges.setting, value: Data("not sealed".utf8))
        let server = MemoryServer()
        try await SyncEngine(store: copy, server: server).synchronize()
        try await copy.setPinned(true, entry: entries[1].id)
        try await SyncEngine(store: copy, server: server).synchronize()
        let onServer = await server.libraryValues(openedBy: copy)
        XCTAssertEqual(onServer.map { Set($0.keys) }, Set(entries.map { pinKey($0.id) }))
    }

    /// A value that can't be opened still learns what the server acknowledged, so this device's sent unpin isn't
    /// asserted again over a pin another device made after it.
    func testADamagedValueDoesNotUndoALaterPinFromAnotherDevice() async throws {
        let server = MemoryServer()
        let mac = try device("mac")
        let phone = try device("phone")
        let macSync = SyncEngine(store: mac, server: server)
        let phoneSync = SyncEngine(store: phone, server: server)
        let (_, entries) = try await journalWithEntries(mac)
        try await mac.setPinned(true, entry: entries[0].id)
        try await macSync.synchronize()
        try await phoneSync.synchronize()
        try await mac.setSetting(LibraryChanges.setting, value: Data("!!".utf8))
        try await mac.setPinned(false, entry: entries[0].id)
        try await macSync.synchronize()
        try await phoneSync.synchronize()
        let unpinned = try await pinned(phone)
        XCTAssertEqual(unpinned, [])
        try await phone.setPinned(true, entry: entries[0].id)
        try await phoneSync.synchronize()
        for sync in [macSync, macSync, phoneSync] { try await sync.synchronize() }
        for store in [mac, phone] {
            let shown = try await pinned(store)
            XCTAssertEqual(shown, [entries[0].id], "The pin synced last stands")
        }
    }

    /// Pinned, answer lost, unpinned and pinned again, then another device unpins: the Mac's second pin synced last
    /// and stands. Sending the earlier payload again doesn't count as sending the second pin, though they're equal.
    func testAPinMadeAgainAfterALostAnswerIsNotTakenAsSent() async throws {
        let server = MemoryServer()
        let mac = try device("mac")
        let phone = try device("phone")
        let macSync = SyncEngine(store: mac, server: server)
        let phoneSync = SyncEngine(store: phone, server: server)
        let (_, entries) = try await journalWithEntries(mac)
        try await macSync.synchronize()
        try await phoneSync.synchronize()
        try await mac.setPinned(true, entry: entries[0].id)
        await server.loseNextAnswer()
        do {
            try await macSync.synchronize()
            XCTFail("The lost answer stops the synchronization")
        } catch {}
        try await mac.setPinned(false, entry: entries[0].id)
        try await mac.setPinned(true, entry: entries[0].id)
        try await phoneSync.synchronize()
        try await phone.setPinned(false, entry: entries[0].id)
        try await phoneSync.synchronize()
        for sync in [macSync, macSync, phoneSync] { try await sync.synchronize() }
        for store in [mac, phone] {
            let shown = try await pinned(store)
            XCTAssertEqual(shown, [entries[0].id], "The Mac's second pin synced last")
            let reviews = try await conflictCount(store)
            XCTAssertEqual(reviews, 0)
        }
    }

    func testAnAutomaticRankLeftOverIsClearedOnceTheServerHasAValue() async throws {
        let server = MemoryServer()
        let mac = try device("mac")
        let phone = try device("phone")
        let macSync = SyncEngine(store: mac, server: server)
        let phoneSync = SyncEngine(store: phone, server: server)
        for title in ["A", "B", "C"] { try await mac.save(JournalItem(kind: "journal", title: title)) }
        try await macSync.synchronize()
        try await phoneSync.synchronize()
        let macShown = try await mac.arrangedJournals().map(\.id)
        try await mac.moveJournal(macShown[2], shown: macShown, to: 0)
        let phoneShown = try await phone.arrangedJournals().map(\.id)
        try await phone.moveJournal(phoneShown[0], shown: phoneShown, to: 2)
        try await macSync.synchronize()
        try await phoneSync.synchronize()
        try await phoneSync.synchronize()
        let left = try await phone.libraryChanges()
        XCTAssertTrue(left.isEmpty, "Automatic ranks the server has a value for are cleared")

        // Another device removes a rank; the phone never puts its automatic one back.
        let values = await server.libraryValues(openedBy: mac) ?? [:]
        let removed = "journal-rank/\(macShown[1].uuidString.lowercased())"
        var trimmed = values
        trimmed[removed] = nil
        let object = trimmed.mapValues(\.foundationValue)
        try await write(libraryPayload(["values": object], for: mac), to: server)
        try await phoneSync.synchronize()
        try await phoneSync.synchronize()
        let after = await server.libraryValues(openedBy: phone)
        XCTAssertNil(after?[removed])
    }

    // MARK: Fixture

    func testTheLibraryRecordFixtureOpensAndReadsAsOlderVersionsReadIt() throws {
        let corpus = try LibraryFixture.load()
        let plaintext = try VaultCrypto.open(
            corpus.record.combined, key: corpus.vaultKey, context: corpus.record.context)
        XCTAssertEqual(plaintext, Data(corpus.record.plaintext.utf8))
        XCTAssertEqual(corpus.record.context, "journal:v1:record:library:\(LibraryRecord.idText)")
        XCTAssertThrowsError(
            try VaultCrypto.open(
                corpus.record.combined, key: corpus.vaultKey,
                context: "journal:v1:record:entry:\(LibraryRecord.idText)"))
        guard case .readable(let record) = LibraryRecord.read(plaintext) else { return XCTFail("Not readable") }
        let arrangement = LibraryArrangement(values: record.values)
        XCTAssertEqual(arrangement.pinned, Set(corpus.expected.pinned))
        XCTAssertEqual(
            arrangement.ranks,
            Dictionary(
                uniqueKeysWithValues: corpus.expected.ranks.compactMap { key, rank in
                    UUID(uuidString: key).map { ($0, rank) }
                }))
        XCTAssertEqual(Set(record.values.keys), Set(corpus.expected.keys))

        // Versions without the library record read it as a record of an unknown kind: invisible and read-only.
        XCTAssertThrowsError(try PortableRecord.decode(plaintext))
        let old = PortableRecord.unreadable(plaintext, id: LibraryRecord.id, kind: LibraryRecord.kind)
        XCTAssertEqual(old.title, "Pinned Entries and Journal Order")
        XCTAssertFalse(old.document.isEditable)
        XCTAssertNil(old.journalID)
        let snapshot = JournalLifecycleSnapshot(items: [old])
        XCTAssertTrue(snapshot.liveJournals.isEmpty)
        let contents = LibraryContents(items: [old], conflicts: 0)
        XCTAssertEqual(
            [contents.journals, contents.entries, contents.templates, contents.recentlyDeleted], [0, 0, 0, 0])
    }
}

/// protocol/conformance/records/library-record-v1.json, with the vault key of encryption-v2.json.
struct LibraryFixture: Decodable {
    struct Record: Decodable {
        let context: String
        let plaintext: String
        let combined: Data
    }
    struct Expected: Decodable {
        let pinned: [UUID]
        let ranks: [String: String]
        let keys: [String]
    }
    let record: Record
    let expected: Expected
    var vaultKey = Data()
    private enum CodingKeys: String, CodingKey { case record, expected }

    static func load() throws -> LibraryFixture {
        struct Recovery: Decodable { let vaultKey: Data }
        struct Corpus: Decodable { let recovery: Recovery }
        var fixture = try Conformance.decode(LibraryFixture.self, "records/library-record-v1.json")
        fixture.vaultKey = try Conformance.decode(Corpus.self, "crypto/encryption-v2.json").recovery.vaultKey
        return fixture
    }
}
