import XCTest

@testable import JournalCore

final class ImportLifecycleTests: XCTestCase {
    func testArchiveImportPreservesUnavailableReferencesHistoryConflictsAndDeletionStates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let source = try JournalStore(directory: root.appendingPathComponent("source"), key: key)
        let fixture = try await seed(source, key: key)
        let phrase = try VaultCrypto.recoveryPhrase()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        let archive = root.appendingPathComponent("copy.journalarchive")
        try await VaultArchive.export(store: source, recovery: recovery, key: key, to: archive)
        let restored = try await VaultArchive.restore(
            from: archive, to: root.appendingPathComponent("restored"), phrase: phrase)
        let summary = ArchiveSummary(snapshot: try await restored.store.lifecycleSnapshot())
        XCTAssertEqual(summary.journals.count, 1)
        XCTAssertEqual(summary.entries, 0)
        XCTAssertEqual(summary.recentlyDeleted, 3)
        XCTAssertEqual(summary.unavailable, 2)
        let destinationKey = try VaultCrypto.generateKey()
        let path = root.appendingPathComponent("destination")
        let destination = try JournalStore(directory: path, key: destinationKey)
        // Matching IDs in another vault must never satisfy unavailable source relationships.
        for (index, id) in fixture.parents.enumerated() {
            try await destination.save(JournalItem(id: id, kind: "journal", title: "Existing parent \(index + 1)"))
        }
        for id in fixture.templates {
            try await destination.save(JournalItem(id: id, kind: "template", title: "Existing template"))
        }
        let oldOperations = try await destination.pending()
        try await destination.setSetting("destination-only", value: Data("retained".utf8))
        try await destination.importAsNewJournals(from: restored.store)
        try await destination.close()
        let reopened = try JournalStore(directory: path, key: destinationKey)
        let items = try await reopened.items()
        let journal = try XCTUnwrap(items.first { $0.title == "Imported Work" })
        let inherited = try XCTUnwrap(items.first { $0.title == "Inherited deletion" })
        let independent = try XCTUnwrap(items.first { $0.title == "Independent deletion" })
        let legacy = try XCTUnwrap(items.first { $0.title == "Legacy deletion" })
        let orphan = try XCTUnwrap(items.first { $0.title == "Unavailable entry" })
        let sibling = try XCTUnwrap(items.first { $0.title == "Unavailable sibling" })
        XCTAssertEqual(orphan.journalID, sibling.journalID)
        XCTAssertFalse(fixture.parents.contains(try XCTUnwrap(orphan.journalID)))
        XCTAssertFalse(fixture.templates.contains(try XCTUnwrap(journal.defaultTemplateID)))
        XCTAssertFalse(items.contains { $0.id == orphan.journalID || $0.id == journal.defaultTemplateID })
        XCTAssertEqual(inherited.journalID, journal.id)
        XCTAssertNotNil(journal.deletedAt)
        XCTAssertNil(inherited.deletedAt)
        XCTAssertNotNil(independent.deletedAt)
        XCTAssertTrue(legacy.deletedWithJournal)
        let beforeRestore = try await reopened.lifecycleSnapshot()
        XCTAssertEqual(beforeRestore.location(of: inherited), .recentlyDeleted)
        XCTAssertEqual(beforeRestore.location(of: orphan), .unavailable(.missing))
        XCTAssertEqual(beforeRestore.location(of: sibling), .unavailable(.missing))
        try await verifyHistoricalReferences(reopened, journal: journal, orphan: orphan, fixture: fixture)
        _ = try await reopened.restoreJournal(journal.id)
        let afterRestore = try await reopened.lifecycleSnapshot()
        XCTAssertEqual(afterRestore.location(of: inherited), .journal)
        XCTAssertEqual(afterRestore.location(of: independent), .recentlyDeleted)
        XCTAssertEqual(afterRestore.location(of: legacy), .recentlyDeleted)
        XCTAssertEqual(afterRestore.location(of: sibling), .unavailable(.missing))
        let importedSummary = ArchiveSummary(snapshot: afterRestore)
        XCTAssertEqual(importedSummary.entries, 1)
        XCTAssertEqual(importedSummary.recentlyDeleted, 2)
        XCTAssertEqual(importedSummary.unavailable, 3, "…and the other version the archive carried, kept as an entry")
        let pending = try await reopened.pending()
        for original in oldOperations {
            let kept = try XCTUnwrap(pending.first { $0.operationId == original.operationId })
            XCTAssertEqual(kept.payload, original.payload)
            XCTAssertEqual(kept.baseRevision, original.baseRevision)
        }
        let setting = try await reopened.setting("destination-only")
        XCTAssertEqual(setting, Data("retained".utf8))
        let sourceItems = try await source.items()
        XCTAssertEqual(sourceItems.count, 6)
        XCTAssertEqual(sourceItems.first { $0.title == "Unavailable entry" }?.journalID, fixture.parents[0])
        try await reopened.close()
        try await restored.store.close()
        try await source.close()
    }

    private struct Fixture {
        let parents: [UUID]
        let templates: [UUID]
    }
    private func seed(_ store: JournalStore, key: Data) async throws -> Fixture {
        let fixture = Fixture(parents: [UUID(), UUID(), UUID()], templates: [UUID(), UUID()])
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var journal = JournalItem(kind: "journal", title: "Imported Work")
        journal.defaultTemplateID = fixture.templates[0]
        journal.deletedAt = date
        try await store.save(journal)
        var earlierJournal = journal
        earlierJournal.title = "Earlier Work"
        earlierJournal.defaultTemplateID = fixture.templates[1]
        try await record(earlierJournal, revision: 1, store: store, key: key)
        let journalConflicts = try await store.conflicts()
        try await store.resolve(try XCTUnwrap(journalConflicts.first), choice: .local)
        var inherited = JournalItem(kind: "entry", journalID: journal.id, title: "Inherited deletion")
        inherited.archivedAt = date
        var independent = JournalItem(kind: "entry", journalID: journal.id, title: "Independent deletion")
        independent.deletedAt = date
        var legacy = JournalItem(kind: "entry", journalID: journal.id, title: "Legacy deletion")
        legacy.deletedWithJournal = true
        for item in [inherited, independent, legacy] { try await store.save(item) }
        var orphan = JournalItem(kind: "entry", journalID: fixture.parents[0], title: "Unavailable entry")
        orphan.archivedAt = date
        try await store.save(orphan)
        try await store.save(JournalItem(kind: "entry", journalID: fixture.parents[0], title: "Unavailable sibling"))
        var earlier = orphan
        earlier.journalID = fixture.parents[1]
        earlier.title = "Earlier unavailable entry"
        try await record(earlier, revision: 1, store: store, key: key)
        let entryConflicts = try await store.conflicts()
        try await store.resolve(try XCTUnwrap(entryConflicts.first), choice: .local)
        var other = orphan
        other.journalID = fixture.parents[2]
        other.title = "Other unavailable entry"
        try await record(other, revision: 2, store: store, key: key)
        return fixture
    }
    private func record(_ item: JournalItem, revision: Int64, store: JournalStore, key: Data) async throws {
        let bytes = try VaultCrypto.seal(
            JournalCoding.encoder().encode(item), key: key,
            context: VaultCrypto.recordContext(id: item.id, kind: item.kind))
        try await store.recordConflict(
            RemoteChange(
                cursor: revision, recordId: item.id, revision: revision, kind: item.kind,
                payload: bytes.base64EncodedString(), deviceId: UUID(), modifiedAt: Date()))
    }
    private func verifyHistoricalReferences(
        _ store: JournalStore, journal: JournalItem, orphan: JournalItem, fixture: Fixture
    ) async throws {
        let journalHistory = try await store.history(for: journal.id)
        let oldSettings = try XCTUnwrap(journalHistory.first { $0.title == "Earlier Work" })
        let currentSettings = try XCTUnwrap(journalHistory.first { $0.title == "Imported Work" })
        XCTAssertEqual(currentSettings.defaultTemplateID, journal.defaultTemplateID)
        XCTAssertNotEqual(oldSettings.defaultTemplateID, journal.defaultTemplateID)
        XCTAssertFalse(fixture.templates.contains(try XCTUnwrap(oldSettings.defaultTemplateID)))
        let history = try await store.history(for: orphan.id)
        let earlier = try XCTUnwrap(history.first { $0.title == "Earlier unavailable entry" })
        let previousLocal = try XCTUnwrap(history.first { $0.title == "Unavailable entry" })
        XCTAssertEqual(previousLocal.journalID, orphan.journalID)
        // The conflict the archive carried is settled by the import: its other version is an entry of its own.
        let conflicts = try await store.conflicts()
        XCTAssertTrue(conflicts.isEmpty)
        let records = try await store.items()
        let other = try XCTUnwrap(records.first { $0.title == "Other unavailable entry (other version)" })
        let references = Set([orphan.journalID, earlier.journalID, other.journalID].compactMap { $0 })
        XCTAssertEqual(references.count, 3)
        XCTAssertTrue(references.isDisjoint(with: fixture.parents))
        XCTAssertTrue(references.isDisjoint(with: records.map(\.id)))
        let pending = try await store.pending()
        XCTAssertTrue(pending.contains { $0.recordID == orphan.id }, "Settled, so it is sent")
    }
}
