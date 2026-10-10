import XCTest

@testable import JournalCore

/// Two devices that sealed the same journal separately hold different ciphertext for the same content. The server's
/// version is adopted as if this device's change had been accepted, instead of being shown for review.
final class StoreSameContentTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("same-content-\(UUID())")
    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func store(_ name: String, key: Data) throws -> JournalStore {
        let store = try JournalStore(directory: root.appendingPathComponent(name), key: key)
        addTeardownBlock { try? await store.close() }
        return store
    }
    private func remoteChange(_ pending: PendingChange, from store: JournalStore) -> RemoteChange {
        RemoteChange(
            cursor: 1, recordId: pending.recordID, revision: 1, kind: pending.kind, payload: pending.payload,
            deviceId: UUID(), modifiedAt: Date())
    }

    func testTheSameContentSealedSeparatelyIsAdoptedWithoutAReview() async throws {
        let key = try VaultCrypto.generateKey()
        let first = try store("first", key: key)
        let second = try store("second", key: key)
        let journal = JournalItem(kind: "journal", title: "Shared")
        try await first.save(journal)
        try await second.save(journal)
        let sent = try await first.pending()[0]
        let waiting = try await second.pending()[0]
        XCTAssertNotEqual(sent.payload, waiting.payload, "Each device sealed its own copy")

        let adopted = try await second.adoptSameContent(waiting, remote: remoteChange(sent, from: first))
        XCTAssertTrue(adopted)
        let pending = try await second.pending()
        XCTAssertTrue(pending.isEmpty)
        let conflicts = try await second.conflicts()
        XCTAssertTrue(conflicts.isEmpty)
    }

    func testDifferentContentIsNotAdopted() async throws {
        let key = try VaultCrypto.generateKey()
        let first = try store("first", key: key)
        let second = try store("second", key: key)
        var journal = JournalItem(kind: "journal", title: "Shared")
        try await first.save(journal)
        journal.title = "Renamed here"
        try await second.save(journal)
        let sent = try await first.pending()[0]
        let waiting = try await second.pending()[0]

        let adopted = try await second.adoptSameContent(waiting, remote: remoteChange(sent, from: first))
        XCTAssertFalse(adopted)
        let pending = try await second.pending()
        XCTAssertEqual(pending.count, 1, "The change stays queued for the normal conflict rules")
    }
}
