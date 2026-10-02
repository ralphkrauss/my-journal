import XCTest

@testable import JournalCore

/// Reading the library again reuses records decoded before, so these check that what is read is always what is
/// stored now, and that nothing decoded is kept while the journals are locked.
final class DecodedRecordTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func testReadingAgainShowsWhatChangedHereAndElsewhere() async throws {
        let key = try VaultCrypto.generateKey()
        let mac = try JournalStore(directory: root.appendingPathComponent("mac"), key: key)
        let phone = try JournalStore(directory: root.appendingPathComponent("phone"), key: key)
        let journal = JournalItem(kind: "journal", title: "Work")
        let entry = try await mac.save(JournalItem(kind: "entry", journalID: journal.id, document: .plain("First")))
        try await mac.save(journal)
        for (offset, pending) in try await mac.pending().enumerated() {
            try await mac.acknowledge(
                pending,
                receipt: RemoteChange(
                    cursor: Int64(offset + 1), recordId: pending.recordID, revision: pending.baseRevision + 1,
                    kind: pending.kind, payload: pending.payload, deviceId: UUID(), modifiedAt: Date()))
        }
        _ = try await mac.viewSnapshot()

        var remote = entry
        remote.document = .plain("Written on the phone")
        try await phone.save(remote)
        let incoming = try await phone.pending().first { $0.recordID == entry.id }
        let payload = try XCTUnwrap(incoming).payload
        try await mac.apply(
            [
                RemoteChange(
                    cursor: 3, recordId: entry.id, revision: 2, kind: "entry", payload: payload, deviceId: UUID(),
                    modifiedAt: Date())
            ], cursor: 3)
        var read = try await mac.viewSnapshot().items.first { $0.id == entry.id }
        XCTAssertEqual(read?.document.text, "Written on the phone")

        var local = try XCTUnwrap(read)
        local.document = .plain("Edited here")
        try await mac.save(local)
        read = try await mac.viewSnapshot().items.first { $0.id == entry.id }
        XCTAssertEqual(read?.document.text, "Edited here")
        let stored = try await mac.item(entry.id)
        XCTAssertEqual(stored, read)

        await mac.forgetDecodedRecords()
        _ = try await mac.viewSnapshot()
        let kept = await mac.decodedRecords
        XCTAssertTrue(kept.isEmpty, "Nothing decoded is kept while the journals are locked")
        try await mac.close()
        try await phone.close()
    }
}
