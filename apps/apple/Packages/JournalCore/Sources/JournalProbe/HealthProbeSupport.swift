import Foundation
import JournalCore

/// What the sync health probe keeps between its phases, while scripts/test-sync-health.sh stops, wipes, restores and
/// restarts the server.
struct HealthState: Codable {
    struct Device: Codable {
        var folder: String
        var key: Data
        var token: String?
        var deviceID: UUID?
        /// How this device's library is stored, when it differs from the first library's.
        var protection: String?
    }
    var phrase: String
    var envelope: RecoveryEnvelope
    var recoverySecret: String
    var protection: String
    var devices: [String: Device] = [:]
    /// Every entry title written on any device, each of which must exist exactly once everywhere.
    var written: [String] = []
    var image: UUID?

    static func load(_ directory: URL) throws -> HealthState {
        try JournalCoding.decoder().decode(
            HealthState.self, from: Data(contentsOf: directory.appendingPathComponent("state.json")))
    }
    func save(_ directory: URL) throws {
        try JournalCoding.encoder().encode(self).write(to: directory.appendingPathComponent("state.json"))
    }
}

/// One device of the probe: its library and, while it syncs, its server access.
struct HealthDevice {
    let name: String
    let store: JournalStore
    var client: ServerClient?

    func synchronize() async throws {
        guard let client else { throw ProbeFailure("\(name) has no server access") }
        let report = try await SyncEngine(store: store, client: client).synchronize()
        if let problem = report.problem { throw ProbeFailure("\(name) couldn't sync everything: \(problem)") }
    }
}

extension Probe {
    static func open(_ name: String, _ state: HealthState, root: URL) throws -> HealthDevice {
        guard let device = state.devices[name] else { throw ProbeFailure("no state for \(name)") }
        let store = try JournalStore(
            directory: root.appendingPathComponent(device.folder), key: device.key,
            protection: ContentProtection(rawValue: device.protection ?? state.protection) ?? .encrypted)
        return HealthDevice(name: name, store: store, client: nil)
    }

    /// Opens a device with access to `address`, when it has any.
    static func open(_ name: String, _ state: HealthState, root: URL, address: String) throws -> HealthDevice {
        var device = try open(name, state, root: root)
        if let token = state.devices[name]?.token { device.client = try ServerClient(address: address, token: token) }
        return device
    }

    /// A synchronization that must stop in `expected`, the state the person would see.
    static func expectState(_ expected: SyncHealth, syncing device: HealthDevice, _ situation: String) async throws {
        do {
            try await device.synchronize()
        } catch let failure as ProbeFailure {
            throw failure
        } catch {
            let health = SyncHealth(classifying: error)
            guard health == expected else {
                throw ProbeFailure("\(situation): \(device.name) is in \(health), not \(expected) (\(error))")
            }
            print("PASS: \(situation): \(device.name) shows “\(health.message())”")
            return
        }
        throw ProbeFailure("\(situation): \(device.name) synced")
    }

    /// Connect Again with the password, as the app does: access is granted, lineage finds this library on the
    /// server, and a copy of the library keeping its identities syncs (docs/design/sync-health-and-recovery.md §3.3).
    static func connectAgain(
        _ device: HealthDevice, state: inout HealthState, root: URL, address: String
    ) async throws -> HealthDevice {
        let anonymous = try ServerClient(address: address)
        let recovered = try await anonymous.recoverVault(
            state.phrase, parameters: anonymous.recoveryParameters(), deviceName: "Probe \(device.name)")
        let client = try ServerClient(address: address, token: recovered.grant.token)
        guard try await SyncLineage.serverHoldsLibrary(device.store, client: client) else {
            throw ProbeFailure("\(device.name)'s own server wasn't recognized as holding its library")
        }
        return try await rejoinByIdentity(
            device, grant: recovered.grant, key: recovered.key, client: client, state: &state, root: root)
    }

    /// The identity-keeping path: a copy of the library with every identity, revision and waiting change.
    static func rejoinByIdentity(
        _ device: HealthDevice, grant: DeviceGrant, key: Data, client: ServerClient, state: inout HealthState,
        root: URL
    ) async throws -> HealthDevice {
        guard var saved = state.devices[device.name], key == saved.key else {
            throw ProbeFailure("\(device.name) rejoined with another key")
        }
        let folder = device.name + "-" + UUID().uuidString.lowercased()
        try await device.store.snapshot(to: root.appendingPathComponent(folder))
        try await device.store.close()
        saved.folder = folder
        saved.token = grant.token
        saved.deviceID = grant.deviceId
        state.devices[device.name] = saved
        let copy = try JournalStore(
            directory: root.appendingPathComponent(folder), key: key,
            protection: ContentProtection(rawValue: state.protection) ?? .encrypted)
        let rejoined = HealthDevice(name: device.name, store: copy, client: client)
        try await rejoined.synchronize()
        return rejoined
    }

    /// Writes an entry that must end up exactly once everywhere.
    static func write(_ title: String, on device: HealthDevice, state: inout HealthState) async throws {
        let journal = try await device.store.items().first { $0.kind == "journal" && $0.deletedAt == nil }
        try await device.store.save(JournalItem(kind: "entry", journalID: journal?.id, title: title))
        state.written.append(title)
    }

    /// Every device syncs until nothing changes, then holds exactly what the server holds: every entry written
    /// anywhere once, every template and journal name once, nothing waiting, and the image.
    static func converge(_ devices: [HealthDevice], state: HealthState, _ situation: String) async throws {
        for _ in 0..<2 {
            for device in devices { try await device.synchronize() }
        }
        guard let client = devices.first?.client else { throw ProbeFailure("no device to read the server with") }
        let onServer = try await serverRecords(client)
        for device in devices {
            let items = try await device.store.items()
            guard try await device.store.syncedRecordIDs() == onServer else {
                throw ProbeFailure("\(situation): \(device.name) and the server hold different records")
            }
            guard try await device.store.pending().isEmpty else {
                throw ProbeFailure("\(situation): \(device.name) has changes left unsent")
            }
            let entries = items.filter { $0.kind == "entry" && $0.deletedAt == nil }.map(\.title)
            for title in state.written where entries.filter({ $0 == title }).count != 1 {
                throw ProbeFailure(
                    "\(situation): \(device.name) has “\(title)” \(entries.filter { $0 == title }.count) times")
            }
            try requireUniqueNames(items, kind: "template", device: device.name, situation)
            try requireUniqueNames(items, kind: "journal", device: device.name, situation)
            if let image = state.image, try await device.store.attachment(image).isEmpty {
                throw ProbeFailure("\(situation): \(device.name) lacks the image")
            }
        }
        print("PASS: \(situation): \(devices.map(\.name).joined(separator: ", ")) converge without loss or duplicates")
    }

    private static func requireUniqueNames(_ items: [JournalItem], kind: String, device: String, _ situation: String)
        throws
    {
        let names = items.filter { $0.kind == kind && $0.deletedAt == nil }.map { $0.title.lowercased() }
        guard Set(names).count == names.count else {
            throw ProbeFailure("\(situation): \(device) has a \(kind) name more than once: \(names.sorted())")
        }
    }

    /// Every record the server's log holds.
    static func serverRecords(_ client: ServerClient) async throws -> Set<UUID> {
        var records = Set<UUID>()
        var cursor: Int64 = 0
        while true {
            let page = try await client.changes(after: cursor, limit: 50)
            records.formUnion(page.changes.map(\.recordId))
            guard page.hasMore, page.cursor > cursor else { return records }
            cursor = page.cursor
        }
    }
}
