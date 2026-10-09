import CryptoKit
import XCTest

@testable import JournalCore

/// A server below protocol revision 1 is a gate and nothing else (docs/design/1-1-server-cleanup.md §3.5): a device
/// with unsent changes and images loses nothing and syncs by itself once the server is updated.
final class ServerRevisionGateTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
    private func device(_ name: String) throws -> JournalStore {
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let store = try JournalStore(directory: root.appendingPathComponent(name), key: key)
        addTeardownBlock { try? await store.close() }
        return store
    }

    func testADeviceWithUnsentWorkLosesNothingToAServerThatNeedsAnUpdateAndSyncsOnceItIsUpdated() async throws {
        let server = MemoryServer()
        let phone = try device("phone")
        let sync = SyncEngine(store: phone, server: server)
        let first = JournalItem(kind: "entry", journalID: UUID(), document: .plain("Synced before"))
        try await phone.save(first)
        try await sync.synchronize()
        let identity = try await phone.syncedServerID()
        let cursor = try await phone.cursor()

        let photoID = try await phone.addAttachment(Data("a photo not uploaded yet".utf8))
        let edited = JournalItem(
            kind: "entry", journalID: UUID(),
            document: .init(blocks: [DocumentBlock(kind: "image", attachmentID: photoID, imageDescription: "")]))
        try await phone.save(edited)
        let queued = try await phone.pending().map(\.operationId)
        XCTAssertFalse(queued.isEmpty)
        let sentBefore = await server.pushes.count

        // The server reports 12 of the 13 names and no revision, as one from before the last was added.
        await server.report(
            ServerStatus(
                protocolVersion: 1, initialized: true, features: Array(ServerStatus.revisionOneFeatures.dropLast()),
                serverId: "memory-server"))
        for retrying in [false, true] {
            do {
                try await sync.synchronize(retryingRefused: retrying)
                XCTFail("A server below revision 1 isn't synced with")
            } catch let failure as SyncFailure {
                XCTAssertEqual(failure.health, .serverUpdateNeeded)
            }
        }
        let after = await (server.pushes.count, server.record(edited.id), server.hasAttachment(photoID))
        XCTAssertEqual(after.0, sentBefore, "Nothing was sent")
        XCTAssertNil(after.1)
        XCTAssertEqual(after.2, false, "No image was uploaded")
        let kept = try await (
            phone.pending().map(\.operationId), phone.attachmentsToUpload(), phone.syncedServerID(), phone.cursor()
        )
        XCTAssertEqual(kept.0, queued, "Queued changes are as they were")
        XCTAssertEqual(kept.1, [photoID], "The image still waits to be uploaded")
        XCTAssertEqual(kept.2, identity)
        XCTAssertEqual(kept.3, cursor)
        let stored = try await phone.item(edited.id)
        XCTAssertNotNil(stored)

        // Updated: the next status read passes, with no other action.
        await server.report(nil)
        let report = try await sync.synchronize()
        XCTAssertNil(report.problem)
        XCTAssertTrue(report.settled)
        let sent = await (server.record(edited.id), server.hasAttachment(photoID))
        XCTAssertNotNil(sent.0)
        XCTAssertEqual(sent.1, true)
        let remaining = try await phone.pending()
        XCTAssertTrue(remaining.isEmpty)
    }
}
