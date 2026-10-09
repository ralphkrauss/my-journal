import XCTest
import os

@testable import JournalCore

/// Replays protocol/conformance/sync/conflict-scenarios-v1.json: devices that change the same records offline meet at
/// a server, and every device must end with the same records. Real stores and real synchronization against a server
/// in memory.
final class ConflictScenarioTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let time = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_800_000_000))

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    /// One device: its library and its synchronization.
    private struct Device {
        let store: JournalStore
        let engine: SyncEngine
    }

    private struct Library {
        var devices: [String: Device] = [:]
        var order: [String] = []
        var identities: [String: UUID] = [:]
        var backups: [String: MemoryServer.State] = [:]
        func device(_ name: String) throws -> Device { try XCTUnwrap(devices[name], name) }
        mutating func identity(_ record: String) -> UUID {
            if let known = identities[record] { return known }
            let created = UUID()
            identities[record] = created
            return created
        }
    }

    func testEveryScenarioEndsWithTheSameRecordsOnEveryDevice() async throws {
        let fixture = try Conformance.object("sync/conflict-scenarios-v1.json")
        let crypto = try Conformance.object("crypto/encryption-v2.json")
        let recovery = try XCTUnwrap(crypto["recovery"] as? [String: Any])
        let key = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(recovery["vaultKey"] as? String)))
        let scenarios = try XCTUnwrap(fixture["scenarios"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(scenarios.count, 14)
        for scenario in scenarios {
            try await run(scenario, key: key)
        }
    }

    private func run(_ scenario: [String: Any], key: Data) async throws {
        let name = try XCTUnwrap(scenario["name"] as? String)
        let server = MemoryServer()
        var library = Library()
        let time = time
        for device in try XCTUnwrap(scenario["devices"] as? [String]) {
            let store = try JournalStore(directory: root.appendingPathComponent("\(name)-\(device)"), key: key)
            await store.useClock { time.withLock { $0 } }
            let engine = SyncEngine(store: store, server: DeviceServer(server: server, device: UUID()))
            if let size = scenario["pageSize"] as? Int { await engine.usePageSize(size) }
            library.devices[device] = Device(store: store, engine: engine)
            library.order.append(device)
        }
        for step in try XCTUnwrap(scenario["steps"] as? [[String: Any]]) {
            try await perform(step, in: &library, scenario: name, server: server)
        }
        try await check(try XCTUnwrap(scenario["expect"] as? [String: Any]), in: library, scenario: name)
        for device in library.devices.values { try await device.store.close() }
    }

    // MARK: Steps

    private func perform(
        _ step: [String: Any], in library: inout Library, scenario: String, server: MemoryServer, round: Int? = nil
    ) async throws {
        let action = try XCTUnwrap(step["do"] as? String)
        if action == "repeat" {
            for round in 1...(try XCTUnwrap(step["times"] as? Int)) {
                for inner in try XCTUnwrap(step["steps"] as? [[String: Any]]) {
                    try await perform(inner, in: &library, scenario: scenario, server: server, round: round)
                }
            }
            return
        }
        if action == "backupServer" {
            library.backups[try XCTUnwrap(step["label"] as? String)] = await server.state
            return
        }
        if action == "restoreServer" {
            let backup = try XCTUnwrap(library.backups[try XCTUnwrap(step["label"] as? String)])
            await server.restore(backup, identity: "restored-\(UUID().uuidString)")
            return
        }
        if action == "settleAll" {
            for _ in 0..<4 {
                for name in library.order { try await synchronize(try library.device(name)) }
            }
            return
        }
        let device = try library.device(try XCTUnwrap(step["device"] as? String))
        if action == "sync" { return try await synchronize(device) }
        let record = try XCTUnwrap(step["record"] as? String)
        let id = library.identity(record)
        switch action {
        case "createJournal":
            try await device.store.save(
                JournalItem(id: id, kind: "journal", title: try XCTUnwrap(step["title"] as? String)))
        case "createEntry":
            let journal = library.identity(try XCTUnwrap(step["journal"] as? String))
            try await device.store.save(
                JournalItem(
                    id: id, kind: "entry", journalID: journal, title: try XCTUnwrap(step["title"] as? String),
                    document: .plain(try XCTUnwrap(step["text"] as? String))))
        case "editEntry":
            var item = try await stored(device, id)
            item.document = .plain(Self.filled(try XCTUnwrap(step["text"] as? String), round))
            item.modifiedAt = time.withLock { $0 }
            try await device.store.save(item)
        case "renameJournal":
            var item = try await stored(device, id)
            item.title = try XCTUnwrap(step["title"] as? String)
            item.modifiedAt = time.withLock { $0 }
            try await device.store.save(item)
        case "deleteJournal":
            _ = try await device.store.deleteJournal(try await device.store.prepareJournalDeletion(id))
        case "deleteEntry":
            try await delete(entry: id, on: device)
        case "deleteForGood":
            let item = try await stored(device, id)
            if item.kind == "journal" {
                if item.deletedAt == nil {
                    _ = try await device.store.deleteJournal(try await device.store.prepareJournalDeletion(id))
                }
            } else if item.deletedAt == nil {
                try await delete(entry: id, on: device)
            }
            _ = try await device.store.permanentlyDelete(try await device.store.preparePermanentDeletion(id))
        default: XCTFail("\(scenario): unknown step \(action)")
        }
    }

    /// `{n}` stands for the number of the round of the `repeat` step that holds the step.
    private static func filled(_ text: String, _ round: Int?) -> String {
        text.replacingOccurrences(of: "{n}", with: round.map(String.init) ?? "")
    }

    private func delete(entry id: UUID, on device: Device) async throws {
        var item = try await stored(device, id)
        item.deletedAt = time.withLock { $0 }
        try await device.store.save(item)
    }
    private func stored(_ device: Device, _ id: UUID) async throws -> JournalItem {
        let item = try await device.store.item(id)
        return try XCTUnwrap(item)
    }
    /// A round after the person paused writing.
    private func synchronize(_ device: Device) async throws {
        time.withLock { $0 = $0.addingTimeInterval(3) }
        try await device.engine.synchronize()
    }

    // MARK: What every device holds

    private struct Held: Hashable {
        let id: UUID
        let kind: String
        let title: String
        let text: String
        let state: String
    }

    private func held(by device: Device) async throws -> Set<Held> {
        let snapshot = try await device.store.lifecycleSnapshot()
        let all = try await device.store.items()
        var result = Set<Held>()
        for item in all where ["journal", "entry"].contains(item.kind) {
            let state: String
            if item.isPermanentlyDeleted {
                state = "permanentlyDeleted"
            } else if item.kind == "journal" {
                state = item.deletedAt == nil ? "live" : "recentlyDeleted"
            } else {
                switch snapshot.location(of: item) {
                case .journal: state = "live"
                case .recentlyDeleted: state = "recentlyDeleted"
                case .unavailable: state = "unavailable"
                }
            }
            result.insert(
                Held(
                    id: item.id, kind: item.kind, title: item.title,
                    text: item.isPermanentlyDeleted ? "" : item.document.text,
                    state: state))
        }
        // A permanent deletion hides the record from the snapshot's items; count it from the stored records.
        return result
    }

    private func check(_ expect: [String: Any], in library: Library, scenario: String) async throws {
        let reference = try await held(by: try library.device(library.order[0]))
        for name in library.order.dropFirst() {
            let other = try await held(by: try library.device(name))
            XCTAssertEqual(other, reference, "\(scenario): \(name) holds the same records as \(library.order[0])")
        }
        if let total = expect["total"] as? Int {
            XCTAssertEqual(reference.count, total, "\(scenario): the records")
        }
        if let atMost = expect["totalAtMost"] as? Int {
            XCTAssertLessThanOrEqual(reference.count, atMost, "\(scenario): the records")
        }
        for expectation in try XCTUnwrap(expect["records"] as? [[String: Any]]) {
            let matches = reference.filter { held in
                if let record = expectation["record"] as? String, library.identities[record] != held.id { return false }
                if let kind = expectation["kind"] as? String, kind != held.kind { return false }
                if let title = expectation["title"] as? String, title != held.title { return false }
                if let suffix = expectation["titleSuffix"] as? String, !held.title.hasSuffix(suffix) { return false }
                if let text = expectation["text"] as? String, text != held.text { return false }
                return expectation["state"] as? String == held.state
            }
            if let atMost = expectation["countAtMost"] as? Int {
                XCTAssertLessThanOrEqual(matches.count, atMost, "\(scenario): \(expectation)")
            } else {
                XCTAssertEqual(matches.count, expectation["count"] as? Int ?? 1, "\(scenario): \(expectation)")
            }
        }
        let notes = expect["notes"] as? [String: [String]] ?? [:]
        for name in library.order {
            let device = try library.device(name)
            let kinds = try await device.store.keptNotes().map(\.kind.rawValue).sorted()
            XCTAssertEqual(kinds, (notes[name] ?? []).sorted(), "\(scenario): the notes on \(name)")
            let rows = try await device.store.conflicts()
            XCTAssertEqual(rows.count, expect["reviewRows"] as? Int ?? 0, "\(scenario): rows to review on \(name)")
            let pending = try await device.store.pending()
            XCTAssertTrue(pending.isEmpty, "\(scenario): \(name) has nothing left to send")
        }
    }
}
