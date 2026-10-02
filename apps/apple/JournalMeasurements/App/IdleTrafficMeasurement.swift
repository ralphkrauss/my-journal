import JournalCore
import XCTest

@testable import Journal

/// The app's idle traffic with a real, disposable server (docs/design/sync-protocol-efficiency.md §7.4): a small
/// library sets up the server given by scripts/measure-idle-traffic.sh, then automatic sync runs with My Journal the
/// active app and nothing changing. The script counts requests and bytes in a proxy in front of the server.
@MainActor final class IdleTrafficMeasurement: XCTestCase {
    func testIdleTraffic() async throws {
        let environment = ProcessInfo.processInfo.environment
        let address = try XCTUnwrap(environment["JOURNAL_MEASURE_SERVER"], "Run scripts/measure-idle-traffic.sh.")
        let code = try XCTUnwrap(environment["JOURNAL_MEASURE_SETUP_CODE"])
        let seconds = Double(environment["JOURNAL_MEASURE_IDLE_SECONDS"] ?? "") ?? 600
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "IdleTraffic-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = try VaultCrypto.generateKey()
        let (envelope, secret) = try VaultCrypto.makeRecovery(masterKey: key, phrase: VaultCrypto.recoveryPhrase())
        let grant = try await ServerClient(address: address).initialize(
            code: code, envelope: envelope, recoverySecret: secret, deviceName: "Measured iPhone")

        let model = AppModel(directory: directory)
        model.configuration = LocalConfiguration(recovery: envelope, recoveryConfirmed: true, storageFolder: "library")
        let store = try JournalStore(directory: directory.appendingPathComponent("library"), key: key)
        let journal = try await store.save(JournalItem(kind: "journal", title: "Journal"))
        for index in 0..<20 {
            try await store.save(JournalItem(kind: "entry", journalID: journal.id, document: .plain("Entry \(index)")))
        }
        model.store = store
        model.loaded = true
        model.locked = false
        model.connection = SyncConnection(address: address, deviceID: grant.deviceId, token: grant.token)
        model.configureSync()
        model.applicationActive = true
        let synchronized = await model.sync()
        XCTAssertTrue(synchronized, "The library reaches the server before measuring")
        try await mark("start", address: address)
        let loop = Task { await model.synchronizeAutomatically() }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        loop.cancel()
        await loop.value
        try await mark("end", address: address)
        print("JOURNAL-IDLE-TRAFFIC waiting=\(model.syncTiming.watcher.ownsSchedule)")
        XCTAssertNil(model.syncError)
        let lastSynced = try XCTUnwrap(model.syncActivity.lastSynced)
        XCTAssertLessThan(Date().timeIntervalSince(lastSynced), 60, "Last Synced still reads Just now")
        try await store.close()
    }

    /// Tells the counting proxy where the idle period starts and ends.
    private func mark(_ name: String, address: String) async throws {
        let url = try XCTUnwrap(URL(string: address + "/__mark/" + name))
        _ = try await URLSession.shared.data(from: url)
    }
}
