import XCTest

@testable import JournalCore

final class ImportTests: XCTestCase {
    func testAdditiveImportRemapsRelationshipsAndPreservesHistoryImagesAndDestinationData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let source = try JournalStore(directory: root.appendingPathComponent("source"), key: key)
        let remote = try JournalStore(directory: root.appendingPathComponent("remote"), key: key)
        let template = JournalItem(kind: "template", title: "Questions")
        var journal = JournalItem(kind: "journal", title: "Imported")
        journal.defaultTemplateID = template.id
        let imageID = try await source.addAttachment(Data("history-only image".utf8))
        var entry = JournalItem(
            kind: "entry", journalID: journal.id, title: "Source entry",
            document: .init(blocks: [DocumentBlock(kind: "image", attachmentID: imageID)]))
        try await source.save(template)
        try await source.save(journal)
        try await source.save(entry)
        let initial = try await source.pending().first { $0.recordID == entry.id }
        let first = try XCTUnwrap(initial)
        let receipt = RemoteChange(
            cursor: 1, recordId: entry.id, revision: 1, kind: "entry", payload: first.payload, deviceId: UUID(),
            modifiedAt: Date())
        try await source.acknowledge(first, receipt: receipt)
        try await remote.apply([receipt], cursor: 1)
        entry.title = "Local"
        try await source.save(entry)
        entry.title = "Remote"
        entry.document = .plain("Remote version")
        try await remote.save(entry)
        let remotePending = try await remote.pending()[0]
        try await source.recordConflict(
            RemoteChange(
                cursor: 2, recordId: entry.id, revision: 2, kind: "entry", payload: remotePending.payload,
                deviceId: UUID(), modifiedAt: Date()))
        let conflict = try await source.conflicts()[0]
        try await source.resolve(conflict, choice: .local)
        entry.title = "Source entry"
        entry.document = .plain("Current version")
        try await source.save(entry)
        let destination = try JournalStore(
            directory: root.appendingPathComponent("destination"), key: VaultCrypto.generateKey())
        let existing = JournalItem(kind: "journal", title: "Keep this journal")
        try await destination.save(existing)
        try await destination.importAsNewJournals(from: source)
        let items = try await destination.items()
        XCTAssertEqual(items.first { $0.id == existing.id }?.title, existing.title)
        let copiedJournal = try XCTUnwrap(items.first { $0.title == journal.title })
        let copiedTemplate = try XCTUnwrap(items.first { $0.kind == "template" })
        let copiedEntry = try XCTUnwrap(items.first { $0.kind == "entry" })
        XCTAssertNotEqual(copiedJournal.id, journal.id)
        XCTAssertNotEqual(copiedEntry.id, entry.id)
        XCTAssertEqual(copiedJournal.defaultTemplateID, copiedTemplate.id)
        XCTAssertEqual(copiedEntry.journalID, copiedJournal.id)
        let history = try await destination.history(for: copiedEntry.id)
        XCTAssertEqual(history.count, 2)
        let copiedImageID = try XCTUnwrap(history.flatMap { $0.document.blocks.compactMap(\.attachmentID) }.first)
        XCTAssertNotEqual(copiedImageID, imageID)
        let image = try await destination.attachment(copiedImageID)
        XCTAssertEqual(image, Data("history-only image".utf8))
        let pending = try await destination.pending()
        XCTAssertTrue(pending.allSatisfy { $0.baseRevision == 0 })
    }
    func testImportedConflictStillRequiresResolutionAndKeepsBothVersions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let source = try JournalStore(directory: root.appendingPathComponent("source"), key: key)
        let remote = try JournalStore(directory: root.appendingPathComponent("remote"), key: key)
        let local = JournalItem(kind: "entry", title: "Local version")
        try await source.save(local)
        var other = local
        other.title = "Other device version"
        try await remote.save(other)
        let operation = try await remote.pending()[0]
        try await source.recordConflict(
            RemoteChange(
                cursor: 1, recordId: local.id, revision: 1, kind: local.kind,
                payload: operation.payload, deviceId: UUID(), modifiedAt: Date()))
        let destination = try JournalStore(
            directory: root.appendingPathComponent("destination"), key: VaultCrypto.generateKey())
        try await destination.importAsNewJournals(from: source)
        let conflicts = try await destination.conflicts()
        let conflict = try XCTUnwrap(conflicts.first)
        XCTAssertEqual(conflict.local.title, local.title)
        XCTAssertEqual(conflict.remote.title, other.title)
        XCTAssertEqual(conflict.remoteRevision, 0)
        XCTAssertNotEqual(conflict.id, local.id)
        let pendingBeforeResolution = try await destination.pending()
        XCTAssertTrue(pendingBeforeResolution.isEmpty)
        try await destination.resolve(conflict, choice: .keepBoth)
        let items = try await destination.items()
        XCTAssertEqual(Set(items.map(\.title)), [local.title, other.title])
        let pendingAfterResolution = try await destination.pending()
        XCTAssertEqual(pendingAfterResolution.count, 2)
        XCTAssertTrue(pendingAfterResolution.allSatisfy { $0.baseRevision == 0 })
    }

}
