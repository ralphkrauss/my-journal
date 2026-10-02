import GRDB
import XCTest

@testable import JournalCore

final class ConflictSafetyTests: XCTestCase {
    func testUnsupportedRemoteConflictCannotLoseFieldsOrMutateHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root, key: key)
        let entry = JournalItem(kind: "entry", journalID: UUID(), title: "Local notes")
        try await store.save(entry)
        let pending = try await store.pending()
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JournalCoding.encoder().encode(entry)) as? [String: Any])
        object["title"] = "Newer client notes"
        object["futureLayout"] = ["columns": 2]
        let original = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        let encrypted = try VaultCrypto.seal(
            original, key: key, context: VaultCrypto.recordContext(id: entry.id, kind: "entry"))
        try await store.recordConflict(
            RemoteChange(
                cursor: 1, recordId: entry.id, revision: 1, kind: "entry", payload: encrypted.base64EncodedString(),
                deviceId: UUID(), modifiedAt: Date()))
        let conflicts = try await store.conflicts()
        let conflict = try XCTUnwrap(conflicts.first)
        for choice in [ConflictChoice.local, .remote, .keepBoth] {
            do {
                try await store.resolve(conflict, choice: choice)
                XCTFail("An unsupported original must remain losslessly preserved.")
            } catch JournalError.unsupportedFormat {}
        }
        let history = try await store.history(for: entry.id)
        XCTAssertTrue(history.isEmpty)
        let remaining = try await store.conflicts()
        XCTAssertEqual(try PortableRecord.encode(XCTUnwrap(remaining.first).remote), original)
        let local = try await store.item(entry.id)
        XCTAssertEqual(local?.title, entry.title)
        // Unresolved conflicts hide pending() results; inspect the durable retry bytes directly.
        let hidden = try await store.pending()
        XCTAssertTrue(hidden.isEmpty)
        let baseline = try XCTUnwrap(pending.first)
        var configuration = Configuration()
        configuration.readonly = true
        let database = try DatabaseQueue(
            path: root.appendingPathComponent("journal.sqlite").path, configuration: configuration)
        let retry: (String, String, Int64)? = try await database.read {
            guard
                let row = try Row.fetchOne(
                    $0, sql: "SELECT operation,payload,base FROM outbox WHERE record=?",
                    arguments: [entry.id.uuidString.lowercased()])
            else { return nil }
            return (row["operation"], row["payload"], row["base"])
        }
        XCTAssertEqual(retry?.0, baseline.operationId.uuidString.lowercased())
        XCTAssertEqual(retry?.1, baseline.payload)
        XCTAssertEqual(retry?.2, baseline.baseRevision)
        try database.close()
        try await store.close()
        let reopened = try JournalStore(directory: root, key: key)
        let retained = try await reopened.conflicts()
        XCTAssertEqual(try PortableRecord.encode(XCTUnwrap(retained.first).remote), original)
        try await reopened.close()
    }

    func testJournalResolutionRejectsCopiesAndStaleVersionsWithoutReparentingEntries() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root, key: key)
        let journal = JournalItem(kind: "journal", title: "Work")
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Meeting")
        for item in [journal, entry] { try await store.save(item) }
        var other = journal
        other.title = "Projects"
        let payload = try VaultCrypto.seal(
            JournalCoding.encoder().encode(other), key: key,
            context: VaultCrypto.recordContext(id: journal.id, kind: "journal"))
        try await store.recordConflict(
            RemoteChange(
                cursor: 1, recordId: journal.id, revision: 1, kind: "journal", payload: payload.base64EncodedString(),
                deviceId: UUID(), modifiedAt: Date()))
        let conflicts = try await store.conflicts()
        let conflict = try XCTUnwrap(conflicts.first)
        do {
            try await store.resolve(conflict, choice: .keepBoth)
            XCTFail("Copying metadata must not create a misleading empty duplicate journal.")
        } catch JournalError.server {}
        var altered = conflict.remote
        altered.title = "An obsolete preview"
        let stale = ConflictVersion(
            id: conflict.id, local: conflict.local, remote: altered, remoteRevision: conflict.remoteRevision,
            deviceID: conflict.deviceID, modifiedAt: conflict.modifiedAt)
        do {
            try await store.resolve(stale, choice: .remote)
            XCTFail("The confirmed preview must match the stored remote version.")
        } catch JournalError.conflict {}
        let before = try await store.history(for: journal.id)
        XCTAssertTrue(before.isEmpty)
        var edited = conflict.local
        edited.title = "Work notes"
        try await store.save(edited)
        do {
            try await store.resolve(conflict, choice: .remote)
            XCTFail("A local edit after confirmation must be reviewed again.")
        } catch JournalError.conflict {}
        let updatedConflicts = try await store.conflicts()
        try await store.resolve(XCTUnwrap(updatedConflicts.first), choice: .remote)
        let items = try await store.items()
        XCTAssertEqual(items.filter { $0.kind == "journal" }.count, 1)
        XCTAssertEqual(items.first { $0.id == journal.id }?.title, other.title)
        XCTAssertEqual(items.first { $0.id == entry.id }?.journalID, journal.id)
        let history = try await store.history(for: journal.id)
        XCTAssertEqual(Set(history.map(\.title)), Set([edited.title, other.title]))
        let remaining = try await store.conflicts()
        XCTAssertTrue(remaining.isEmpty)
        try await store.close()
    }
}
