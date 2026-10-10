import JournalCore
import XCTest

@testable import Journal

/// Sync Now shows progress, then when this device last synced (docs/design/sync-now-and-done.md). A sync that
/// failed must never look completed or leave "Syncing…" behind, and the time shown belongs to one connection.
@MainActor
final class SyncNowTests: XCTestCase {
    private func connectedModel(address: String) async throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SyncNow-" + UUID().uuidString)
        let model = AppModel(directory: directory)
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            if let account = model.configuration?.keyID { try? Keychain.remove(account) }
            try? FileManager.default.removeItem(at: directory)
        }
        await model.start()
        model.connection = SyncConnection(address: address, deviceID: UUID(), token: "synthetic-token")
        model.configureSync()
        return model
    }

    func testUnreachableServerExplainsThatWritingIsSavedAndNeverShowsSynced() async throws {
        // Nothing listens on the discard port, so the connection is refused.
        let model = try await connectedModel(address: "http://127.0.0.1:9")

        await model.syncNow()

        XCTAssertFalse(model.syncActivity.syncingNow)
        XCTAssertNil(model.syncActivity.lastSynced)
        XCTAssertEqual(
            model.syncError,
            "Can’t reach the server right now. Your changes are saved on this device and will sync automatically.")
        XCTAssertEqual(model.syncHealth?.kind, .temporary)
    }

    func testSecondSyncNowWhileOneRunsDoesNotSyncAgain() async throws {
        let server = try await FakeJournalServer { _ in (503, Data("{}".utf8)) }
        let model = try await connectedModel(address: server.address)

        async let first: Void = model.syncNow()
        async let second: Void = model.syncNow()
        _ = await (first, second)
        let afterBoth = server.requests.count
        await model.syncNow()

        XCTAssertGreaterThan(afterBoth, 0)
        XCTAssertEqual(server.requests.count - afterBoth, afterBoth, "Two taps at once sync once.")
        XCTAssertFalse(model.syncActivity.syncingNow)
        XCTAssertNil(model.syncActivity.lastSynced, "A refused sync isn't shown as synced.")
    }

    func testLastSyncedIsKeptForItsConnectionOnlyAndWrittenAtMostOnceAMinute() throws {
        let suite = "SyncNowTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let directory = URL(fileURLWithPath: "/tmp/library")
        let server = SyncConnection(address: "https://journal.example", deviceID: UUID(), token: "token")
        let synced = Date(timeIntervalSince1970: 1_790_000_000)

        let activity = SyncActivity(directory: directory, defaults: defaults)
        activity.connectionChanged(server)
        activity.synced(at: synced)
        activity.synced(at: synced.addingTimeInterval(30))
        let relaunched = SyncActivity(directory: directory, defaults: defaults)
        relaunched.connectionChanged(server)
        XCTAssertEqual(relaunched.lastSynced, synced, "The second sync, within a minute, isn't written yet.")

        activity.persist()
        let afterBackground = SyncActivity(directory: directory, defaults: defaults)
        afterBackground.connectionChanged(server)
        XCTAssertEqual(afterBackground.lastSynced, synced.addingTimeInterval(30))

        let other = SyncConnection(address: "https://other.example", deviceID: UUID(), token: "token")
        afterBackground.connectionChanged(other)
        XCTAssertNil(afterBackground.lastSynced)
        let back = SyncActivity(directory: directory, defaults: defaults)
        back.connectionChanged(server)
        XCTAssertNil(back.lastSynced, "Connecting to another server forgets the time.")
    }
}
