import CryptoKit
import XCTest

@testable import JournalCore

/// Erasing a device's journals warns with how many items exist only on that device
/// (docs/design/erase-device-2026-10-04.md). The count must not leave out a change waiting for a conflict review,
/// which the count for Settings ▸ Sync leaves out.
final class UnsentItemsTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
    private func device(_ name: String) throws -> JournalStore {
        let store = try JournalStore(directory: root.appendingPathComponent(name), key: key)
        addTeardownBlock { try? await store.close() }
        return store
    }

    func testTheUnsentCountIncludesChangesWaitingForAReview() async throws {
        let server = MemoryServer()
        let phone = try device("phone")
        let mac = try device("mac")
        let phoneSync = SyncEngine(store: phone, server: server)
        let macSync = SyncEngine(store: mac, server: server)
        let entry = JournalItem(kind: "entry", journalID: UUID(), document: .plain("Shared"))
        try await phone.save(entry)
        try await phoneSync.synchronize()
        try await macSync.synchronize()
        let synced = try await mac.unsentItemCount()
        XCTAssertEqual(synced, 0)

        let phoneCopy = try await phone.item(entry.id)
        var fromPhone = try XCTUnwrap(phoneCopy)
        fromPhone.document = .plain("Edited on the phone")
        try await phone.save(fromPhone)
        try await phoneSync.synchronize()
        let macCopy = try await mac.item(entry.id)
        var fromMac = try XCTUnwrap(macCopy)
        fromMac.document = .plain("Edited on the Mac, offline")
        try await mac.save(fromMac)
        try await mac.save(JournalItem(kind: "entry", journalID: UUID(), document: .plain("Only on the Mac")))
        try await macSync.synchronize()

        let reviews = try await mac.conflicts()
        XCTAssertEqual(reviews.count, 1)
        let pending = try await mac.pendingItemCount()
        let unsent = try await mac.unsentItemCount()
        XCTAssertEqual(pending, 0, "the new entry was sent; the edit waits for its review")
        XCTAssertEqual(unsent, 1, "the Mac's edit exists only on the Mac")
    }
}
