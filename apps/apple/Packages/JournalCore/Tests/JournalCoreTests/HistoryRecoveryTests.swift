import XCTest

@testable import JournalCore

final class HistoryRecoveryTests: XCTestCase {
    func testHistoricalCopyRecoversUnavailableEntryWithoutChangingOriginalHistoryOrRetryBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root, key: key)
        let image = try await store.addAttachment(Data("Original image bytes".utf8))
        let destination = JournalItem(kind: "journal", title: "Recovered")
        try await store.save(destination)
        var original = JournalItem(kind: "entry", journalID: UUID(), title: "Current unavailable entry")
        original.deletedAt = Date()
        original.deletedWithJournal = true
        var older = original
        older.title = "Historical reflection"
        older.archivedAt = Date(timeIntervalSince1970: 1_700_000_000)
        older.document = JournalDocument(blocks: [
            DocumentBlock(runs: [TextRun("Earlier styled text", bold: true, link: "https://example.com")]),
            DocumentBlock(kind: "image", attachmentID: image, imageDescription: "A memory", mediaType: "image/png"),
        ])
        let version = try await makeHistory(store, current: original, earlier: older, key: key)
        let current = try await store.item(original.id)
        let history = try await store.history(for: original.id)
        let pending = try await store.pending()
        let bytes = try await store.encryptedAttachment(image)
        let copy = try await store.restoreHistoryCopy(version, to: destination.id)
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.kind, "entry")
        XCTAssertEqual(copy.journalID, destination.id)
        XCTAssertNil(copy.deletedAt)
        XCTAssertNil(copy.archivedAt)
        XCTAssertFalse(copy.deletedWithJournal)
        XCTAssertEqual(copy.title, version.title)
        XCTAssertEqual(copy.document, version.document)
        XCTAssertEqual(copy.date, version.date)
        let afterOriginal = try await store.item(original.id)
        let afterHistory = try await store.history(for: original.id)
        let afterPending = try await store.pending()
        XCTAssertEqual(afterOriginal, current)
        XCTAssertEqual(afterHistory, history)
        XCTAssertTrue(afterHistory.contains { $0.archivedAt == older.archivedAt })
        for retry in pending {
            let unchanged = try XCTUnwrap(afterPending.first { $0.operationId == retry.operationId })
            XCTAssertEqual(unchanged.payload, retry.payload)
            XCTAssertEqual(unchanged.baseRevision, retry.baseRevision)
        }
        XCTAssertEqual(afterPending.count, pending.count + 1)
        let reopened = try JournalStore(directory: root, key: key)
        let reopenedCopy = try await reopened.item(copy.id)
        let reopenedImage = try await reopened.encryptedAttachment(image)
        XCTAssertEqual(reopenedCopy, copy)
        XCTAssertEqual(reopenedImage, bytes)
        var forged = version
        forged.title = "Not a stored version"
        do {
            _ = try await store.restoreHistoryCopy(forged, to: destination.id)
            XCTFail("A modified preview must not impersonate a historical version.")
        } catch HistoryRecoveryError.unavailableVersion {}
        var deletedDestination = destination
        deletedDestination.deletedAt = Date()
        try await store.save(deletedDestination)
        do {
            _ = try await store.restoreHistoryCopy(version, to: destination.id)
            XCTFail("A destination deleted after the picker opened must be refused.")
        } catch HistoryRecoveryError.destinationUnavailable {}
        let items = try await store.items()
        XCTAssertEqual(items.count, 3)
    }

    func testTemplateRecoveryRetainsKindAndDestinationConflictRefusesEntryCopy() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root, key: key)
        let template = JournalItem(kind: "template", title: "Current template")
        var earlier = template
        earlier.title = "Earlier template"
        earlier.document = .plain("Daily prompt")
        earlier.deletedAt = Date()
        let version = try await makeHistory(store, current: template, earlier: earlier, key: key)
        let copy = try await store.restoreHistoryCopy(version)
        XCTAssertEqual(copy.kind, "template")
        XCTAssertNil(copy.journalID)
        XCTAssertNil(copy.deletedAt)
        XCTAssertNotEqual(copy.id, template.id)
        XCTAssertEqual(copy.document, version.document)
        let journal = JournalItem(kind: "journal", title: "Work")
        try await store.save(journal)
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Current entry")
        var oldEntry = entry
        oldEntry.title = "Old entry"
        let entryVersion = try await makeHistory(store, current: entry, earlier: oldEntry, key: key)
        var otherJournal = journal
        otherJournal.title = "Changed elsewhere"
        try await conflict(store, remote: otherJournal, key: key)
        let before = try await store.items()
        do {
            _ = try await store.restoreHistoryCopy(entryVersion, to: journal.id)
            XCTFail("An unresolved destination conflict must not accept the copy.")
        } catch JournalLifecycleError.conflict(let id) { XCTAssertEqual(id, journal.id) }
        do {
            _ = try await store.restoreHistoryCopy(version, to: journal.id)
            XCTFail("Templates must not acquire a parent through recovery.")
        } catch JournalError.invalidData {}
        var unsupported = entryVersion
        unsupported.document.version = 999
        do {
            _ = try await store.restoreHistoryCopy(unsupported, to: journal.id)
            XCTFail("Unknown historical content must stay lossless and read-only.")
        } catch JournalError.unsupportedFormat {}
        let after = try await store.items()
        XCTAssertEqual(after, before)
        let destinationConflicts = try await store.conflicts()
        try await store.resolve(try XCTUnwrap(destinationConflicts.first), choice: .local)
        var unknownSource = entry
        unknownSource.document.version = 999
        try await conflict(store, remote: unknownSource, key: key, revision: 2)
        let sourceConflicts = try await store.conflicts()
        let preservedSource = try PortableRecord.encode(try XCTUnwrap(sourceConflicts.first).remote)
        let recovered = try await store.restoreHistoryCopy(entryVersion, to: journal.id)
        XCTAssertEqual(recovered.document, entryVersion.document)
        let remainingConflicts = try await store.conflicts()
        XCTAssertEqual(remainingConflicts.count, 1)
        XCTAssertEqual(try PortableRecord.encode(try XCTUnwrap(remainingConflicts.first).remote), preservedSource)
    }

    func testJournalSettingsRestoreIsMetadataOnlyRecoverableAndRejectsStaleConfirmation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root, key: key)
        var journal = JournalItem(kind: "journal", title: "Current name")
        journal.deletedAt = Date()
        var earlier = journal
        earlier.title = "Earlier name"
        earlier.defaultTemplateID = UUID()  // A missing historical template reference must not be silently cleared.
        earlier.deletedAt = nil
        let version = try await makeHistory(store, current: journal, earlier: earlier, key: key)
        let storedJournal = try await store.item(journal.id)
        let expected = try XCTUnwrap(storedJournal)
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Kept in Recently Deleted")
        try await store.save(entry)
        let storedEntry = try await store.item(entry.id)
        let beforeHistory = try await store.history(for: journal.id)
        let beforePending = try await store.pending()
        let restored = try await store.restoreJournalSettings(version, expectedJournal: expected)
        XCTAssertEqual(restored.id, expected.id)
        XCTAssertEqual(restored.title, version.title)
        XCTAssertEqual(restored.defaultTemplateID, version.defaultTemplateID)
        XCTAssertEqual(restored.deletedAt, expected.deletedAt)
        XCTAssertEqual(restored.date, expected.date)
        XCTAssertEqual(restored.document, expected.document)
        let afterEntry = try await store.item(entry.id)
        let afterHistory = try await store.history(for: journal.id)
        let afterPending = try await store.pending()
        XCTAssertEqual(afterEntry, storedEntry)
        XCTAssertEqual(afterHistory, [expected] + beforeHistory)
        XCTAssertEqual(afterPending.map(\.operationId), beforePending.map(\.operationId))
        XCTAssertEqual(afterPending.map(\.payload), beforePending.map(\.payload))
        do {
            _ = try await store.restoreJournalSettings(version, expectedJournal: restored)
            XCTFail("Already-applied settings must have an explicit no-write outcome.")
        } catch HistoryRecoveryError.settingsAlreadyApplied {}
        do {
            _ = try await store.restoreJournalSettings(version, expectedJournal: expected)
            XCTFail("An older confirmation must not silently replace newer settings.")
        } catch HistoryRecoveryError.changedJournal {}
        let unchangedHistory = try await store.history(for: journal.id)
        XCTAssertEqual(unchangedHistory, afterHistory)
        let reopened = try JournalStore(directory: root, key: key)
        let reopenedJournal = try await reopened.item(journal.id)
        XCTAssertEqual(reopenedJournal, restored)
    }

    private func makeHistory(_ store: JournalStore, current: JournalItem, earlier: JournalItem, key: Data) async throws
        -> JournalItem
    {
        try await store.save(current)
        try await conflict(store, remote: earlier, key: key)
        let conflicts = try await store.conflicts()
        try await store.resolve(try XCTUnwrap(conflicts.first { $0.id == current.id }), choice: .local)
        let versions = try await store.history(for: current.id)
        return try XCTUnwrap(versions.first { $0.title == earlier.title })
    }
    private func conflict(_ store: JournalStore, remote: JournalItem, key: Data, revision: Int64 = 1) async throws {
        let payload = try VaultCrypto.seal(
            JournalCoding.encoder().encode(remote), key: key,
            context: VaultCrypto.recordContext(id: remote.id, kind: remote.kind))
        try await store.recordConflict(
            RemoteChange(
                cursor: revision, recordId: remote.id, revision: revision, kind: remote.kind,
                payload: payload.base64EncodedString(), deviceId: UUID(), modifiedAt: Date()))
    }
}
