import XCTest

@testable import JournalCore

/// Templates go through Recently Deleted like entries: they can be restored, deleted permanently, and a deletion
/// from another device never silently removes a template edited here.
final class TemplateDeletionTests: XCTestCase {
    func testDeletedTemplateRestoresThenDeletesPermanentlyOnEveryDevice() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root.appendingPathComponent("mine"), key: key)
        let template = JournalItem(kind: "template", title: "Daily Reflection")
        try await store.save(template)
        do {
            _ = try await store.preparePermanentDeletion(template.id)
            XCTFail("A template must be in Recently Deleted before it can be deleted permanently.")
        } catch PermanentDeletionError.notDeleted {}
        let stored = try await store.item(template.id)
        var deleted = try XCTUnwrap(stored)
        deleted.deletedAt = Date()
        try await store.save(deleted)
        let restored = try await store.restoreTemplate(template.id)
        XCTAssertNil(restored.deletedAt)
        XCTAssertEqual(restored.title, template.title)
        XCTAssertEqual(restored.document, template.document)
        deleted = restored
        deleted.deletedAt = Date()
        try await store.save(deleted)
        let confirmation = try await store.preparePermanentDeletion(template.id)
        XCTAssertEqual(confirmation.plan.kind, "template")
        let marker = try await store.permanentlyDelete(confirmation)
        XCTAssertTrue(marker.isCanonicalDeletionMarker)
        XCTAssertEqual(marker.kind, "template")
        let history = try await store.history(for: template.id)
        XCTAssertTrue(history.isEmpty)
        let visible = try await store.viewSnapshot()
        XCTAssertFalse(visible.items.contains { $0.id == template.id && !$0.isPermanentlyDeleted })
        do {
            _ = try await store.restoreTemplate(template.id)
            XCTFail("A permanently deleted template can't come back through Restore.")
        } catch JournalError.invalidData {}
        // Another device with an unchanged copy applies the marker like an entry's.
        let peer = try JournalStore(directory: root.appendingPathComponent("peer"), key: key)
        try await peer.apply([try remote(template, revision: 1, key: key)], cursor: 1)
        try await peer.apply([try remote(marker, revision: 2, key: key)], cursor: 2)
        let received = try await peer.item(template.id)
        XCTAssertEqual(received, marker)
        let peerConflicts = try await peer.conflicts()
        XCTAssertTrue(peerConflicts.isEmpty)
        try await peer.close()
        try await store.close()
    }

    func testDeletionFromElsewhereKeepsAnEditedTemplateUntilReviewed() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root, key: key)
        let template = JournalItem(kind: "template", title: "Weekly Reflection")
        try await store.apply([try remote(template, revision: 1, key: key)], cursor: 1)
        var edited = template
        edited.title = "Weekly Reflection, edited here"
        try await store.save(edited)
        let marker = JournalItem.permanentDeletionMarker(for: template, at: Date(timeIntervalSince1970: 1_800_000_000))
        try await store.apply([try remote(marker, revision: 2, key: key)], cursor: 2)
        let kept = try await store.item(template.id)
        XCTAssertEqual(kept?.title, edited.title)
        let review = try await store.prepareDeletionConflict(template.id)
        XCTAssertEqual(review.edited?.title, edited.title)
        let revived = try await store.resolveDeletionConflict(review, choice: .keepTemplate)
        XCTAssertEqual(revived.id, template.id)
        XCTAssertEqual(revived.title, edited.title)
        XCTAssertEqual(revived.restoredFromDeletionID, marker.permanentDeletionID)
        XCTAssertEqual(try PortableRecord.decode(PortableRecord.encode(revived)), revived)
        let conflicts = try await store.conflicts()
        XCTAssertTrue(conflicts.isEmpty)
        try await store.close()
    }

    private func remote(_ item: JournalItem, revision: Int64, key: Data) throws -> RemoteChange {
        RemoteChange(
            cursor: revision, recordId: item.id, revision: revision, kind: item.kind,
            payload: try VaultCrypto.seal(
                PortableRecord.encode(item), key: key,
                context: VaultCrypto.recordContext(id: item.id, kind: item.kind)
            ).base64EncodedString(),
            deviceId: UUID(), modifiedAt: item.modifiedAt)
    }
}
