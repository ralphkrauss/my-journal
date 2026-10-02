import JournalCore
import XCTest

@testable import Journal

/// Sync can store another device's version while an entry is open here. Leaving, typing or locking must never
/// write the older open copy over it, and must never discard it.
@MainActor
final class StaleDraftTests: XCTestCase {
    private var revision: Int64 = 100
    private func startedModel() async throws -> (AppModel, JournalStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(directory: root)
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            try? Keychain.remove(model.keyAccount)
            try? FileManager.default.removeItem(at: root)
        }
        await model.start()
        model.confirmRecovery()
        let store = try XCTUnwrap(model.store)
        return (model, store)
    }
    /// Stores a record as sync does when it arrives from another device, without refreshing the view.
    private func arrive(_ plaintext: Data, id: UUID, model: AppModel, store: JournalStore) async throws {
        // Everything written here was sent first, so the arriving version is the newer one.
        while let pending = try await store.pending().first(where: { $0.recordID == id }) {
            try await store.acknowledge(
                pending,
                receipt: RemoteChange(
                    cursor: 1, recordId: id, revision: pending.baseRevision + 1, kind: pending.kind,
                    payload: pending.payload, deviceId: UUID(), modifiedAt: Date()))
        }
        revision += 1
        let sealed = try VaultCrypto.seal(
            plaintext, key: XCTUnwrap(model.masterKey), context: VaultCrypto.recordContext(id: id, kind: "entry"))
        let change = RemoteChange(
            cursor: revision, recordId: id, revision: revision, kind: "entry", payload: sealed.base64EncodedString(),
            deviceId: UUID(), modifiedAt: Date())
        try await store.apply([change], cursor: revision)
    }
    private func arrive(_ text: String, in id: UUID, model: AppModel, store: JournalStore) async throws {
        let current = try await store.item(id)
        var edited = try XCTUnwrap(current)
        edited.document = .plain(text)
        try await arrive(PortableRecord.encode(edited), id: id, model: model, store: store)
    }
    private func type(_ text: String, into model: AppModel) async throws {
        var draft = try XCTUnwrap(model.draft)
        draft.document = .plain(text)
        model.updateDraft(draft)
        let saved = await model.finishPendingSave()
        XCTAssertTrue(saved)
    }

    func testAnEmptyNewEntryWrittenOnAnotherDeviceIsNotOverwrittenWhenLeft() async throws {
        let (model, store) = try await startedModel()
        await model.newEntry()
        let entry = try XCTUnwrap(model.draft)
        try await arrive("Written on the iPhone", in: entry.id, model: model, store: store)

        await model.select(nil)
        let stored = try await store.item(entry.id)
        XCTAssertEqual(stored?.document.text, "Written on the iPhone")
        XCTAssertNil(stored?.deletedAt)
        XCTAssertEqual(stored?.isPermanentlyDeleted, false)
        let conflicts = try await store.conflicts()
        XCTAssertTrue(conflicts.isEmpty, "Nothing was typed here, so there is nothing to review")
    }

    func testAnOpenEntryFollowsOtherDevicesAndTypingOverAnUnseenChangeKeepsBoth() async throws {
        let (model, store) = try await startedModel()
        await model.newEntry()
        try await type("Started on the Mac", into: model)
        let id = try XCTUnwrap(model.draft?.id)
        try await arrive("Continued on the iPhone", in: id, model: model, store: store)
        try await model.refresh()
        XCTAssertEqual(model.draft?.document.text, "Continued on the iPhone")

        try await arrive("Rewritten on the iPad", in: id, model: model, store: store)
        try await type("Continued on the iPhone, then on the Mac", into: model)
        let conflicts = try await store.conflicts()
        XCTAssertEqual(conflicts.first?.remote.document.text, "Rewritten on the iPad")
        XCTAssertEqual(conflicts.first?.local.document.text, "Continued on the iPhone, then on the Mac")
        try await model.refresh()
        XCTAssertEqual(model.conflicts.map(\.id), [id])
    }

    func testLockingSavesOnlyUnsavedWritingAndLeavesReadOnlyEntriesAlone() async throws {
        let (model, store) = try await startedModel()
        await model.turnOnAppLockForTesting()
        await model.newEntry()
        try await type("Saved before locking", into: model)
        let id = try XCTUnwrap(model.draft?.id)
        try await arrive("Saved before locking", in: id, model: model, store: store)
        try await model.refresh()
        await model.lock()
        let pending = try await store.pending()
        XCTAssertFalse(pending.contains { $0.recordID == id }, "An unchanged entry isn't saved again")

        await model.unlockForTesting()
        let journalID = try XCTUnwrap(model.selectedJournalID)
        let newer = UUID()
        let record: [String: Any] = [
            "id": newer.uuidString, "kind": "entry", "journalID": journalID.uuidString, "title": "From a newer app",
            "document": ["version": 2, "markdown": "Kept as written"], "date": "2026-09-01T08:00:00Z",
            "modifiedAt": "2026-09-01T08:00:00Z", "deletedWithJournal": false, "futureLayout": ["columns": 2],
        ]
        try await arrive(JSONSerialization.data(withJSONObject: record), id: newer, model: model, store: store)
        try await model.refresh()
        await model.select(newer)
        XCTAssertEqual(model.draft?.document.isEditable, false)
        await model.lock()
        XCTAssertFalse(model.saveFailure)
        XCTAssertNil(model.error)
        let stillPending = try await store.pending()
        XCTAssertFalse(stillPending.contains { $0.recordID == id || $0.recordID == newer })
    }
}
