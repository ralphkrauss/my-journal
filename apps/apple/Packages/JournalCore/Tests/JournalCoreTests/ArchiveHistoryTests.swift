import GRDB
import XCTest

@testable import JournalCore

final class ArchiveHistoryTests: XCTestCase {
    func testArchiveRetainsHistoryWithoutCurrentRecordsAcrossAdditiveImport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await seed(root)
        let source = try JournalStore(directory: fixture.path, key: fixture.key)
        let phrase = "orphan history recovery fixture"
        let recovery = try VaultCrypto.makeRecovery(masterKey: fixture.key, phrase: phrase).0
        let archive = root.appendingPathComponent("history.journalarchive")
        try await VaultArchive.exportFile(store: source, recovery: recovery, key: fixture.key, to: archive)
        let restored = try await VaultArchive.restore(
            from: archive, to: root.appendingPathComponent("restored"), phrase: phrase)
        let originalHistory = try await restored.store.history(for: fixture.item.id)
        XCTAssertEqual(originalHistory, [fixture.item])
        let destinationPath = root.appendingPathComponent("destination")
        let destinationKey = try VaultCrypto.generateKey()
        let destination = try JournalStore(directory: destinationPath, key: destinationKey)
        let unrelated = JournalItem(
            id: try XCTUnwrap(fixture.item.journalID), kind: "journal", title: "Existing journal")
        try await destination.save(unrelated)
        try await destination.importAsNewJournals(from: restored.store)
        try await destination.close()
        let database = try DatabaseQueue(path: destinationPath.appendingPathComponent("journal.sqlite").path)
        let historyIDs = try await database.read { try String.fetchAll($0, sql: "SELECT DISTINCT record FROM history") }
        try database.close()
        XCTAssertEqual(historyIDs.count, 1)
        let importedID = try XCTUnwrap(historyIDs.first.flatMap(UUID.init(uuidString:)))
        XCTAssertNotEqual(importedID, fixture.item.id)
        let reopened = try JournalStore(directory: destinationPath, key: destinationKey)
        let importedHistory = try await reopened.history(for: importedID)
        let imported = try XCTUnwrap(importedHistory.first)
        XCTAssertEqual(imported.title, fixture.item.title)
        XCTAssertEqual(imported.date, fixture.item.date)
        XCTAssertEqual(imported.document.blocks.first?.runs, fixture.item.document.blocks.first?.runs)
        XCTAssertNotEqual(imported.journalID, unrelated.id)
        let items = try await reopened.items()
        XCTAssertEqual(items.map(\.id), [unrelated.id])
        XCTAssertFalse(items.contains { $0.id == imported.journalID })
        let importedImageID = try XCTUnwrap(imported.document.blocks.last?.attachmentID)
        XCTAssertNotEqual(importedImageID, fixture.imageID)
        let image = try await reopened.attachment(importedImageID)
        XCTAssertEqual(image, fixture.image)
        let pending = try await reopened.pending()
        XCTAssertEqual(pending.map(\.recordID), [unrelated.id])
        try await reopened.close()
        try await restored.store.close()
        try await source.close()
    }

    func testValidationChecksImagesAndCiphertextInHistoryWithoutCurrentRecords() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await seed(root)
        let imagePath = fixture.path.appendingPathComponent("attachments/\(fixture.imageID.uuidString.lowercased())")
        let encrypted = try Data(contentsOf: imagePath)
        try FileManager.default.removeItem(at: imagePath)
        let source = try JournalStore(directory: fixture.path, key: fixture.key)
        do {
            try await source.validateSnapshot()
            XCTFail("Missing historical images must fail validation even without a current record")
        } catch {}
        try encrypted.write(to: imagePath)
        try await source.validateSnapshot()
        try await source.close()
        let database = try DatabaseQueue(path: fixture.path.appendingPathComponent("journal.sqlite").path)
        try await database.write { try $0.execute(sql: "UPDATE history SET payload='AA=='") }
        try database.close()
        let damaged = try JournalStore(directory: fixture.path, key: fixture.key)
        do {
            try await damaged.validateSnapshot()
            XCTFail("Historical ciphertext must authenticate even without a current record")
        } catch {}
        try await damaged.close()
    }

    private struct Fixture {
        let path: URL
        let key: Data
        let item: JournalItem
        let imageID: UUID
        let image: Data
    }
    private func seed(_ root: URL) async throws -> Fixture {
        let path = root.appendingPathComponent("source")
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: path, key: key)
        let image = Data("Historical image bytes".utf8)
        let imageID = try await store.addAttachment(image)
        var item = JournalItem(
            kind: "entry", journalID: UUID(), title: "Retained historical entry",
            document: .init(blocks: [
                DocumentBlock(runs: [TextRun("Keep these words", bold: true)]),
                DocumentBlock(kind: "image", attachmentID: imageID, imageDescription: "Historical sketch"),
            ]))
        item.date = Date(timeIntervalSince1970: 1_700_000_000)
        item.modifiedAt = item.date
        try await store.close()
        // The schema intentionally has no history-to-current-record foreign key. Simulate a legacy archive.
        let database = try DatabaseQueue(path: path.appendingPathComponent("journal.sqlite").path)
        let payload = try VaultCrypto.seal(
            JournalCoding.encoder().encode(item), key: key,
            context: VaultCrypto.recordContext(id: item.id, kind: item.kind)
        ).base64EncodedString()
        let historicalItem = item
        try await database.write {
            try $0.execute(
                sql: "INSERT INTO history(record,kind,payload,saved) VALUES (?,?,?,?)",
                arguments: [
                    historicalItem.id.uuidString.lowercased(), historicalItem.kind, payload, "2023-11-14T00:00:00Z",
                ])
        }
        try database.close()
        return Fixture(path: path, key: key, item: item, imageID: imageID, image: image)
    }
}
