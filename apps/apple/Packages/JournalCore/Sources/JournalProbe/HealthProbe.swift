import Foundation
import JournalCore

/// The sync health fault matrix (docs/design/sync-health-and-recovery.md §6.1), run by scripts/test-sync-health.sh
/// against the published server on a fixed loopback port as `health-<phase> <URL> [<code file>] <state directory>`.
/// Between phases the script stops the server, wipes its data folder, restores a backup or restarts it at the same
/// address. Each row checks the state the person would see, recovers the way the app does, and ends with every device
/// converging without loss or duplicates.
extension Probe {
    static func runHealthProbe() async throws -> Bool {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let phase = arguments.first, phase.hasPrefix("health-"), [3, 4].contains(arguments.count) else {
            return false
        }
        let address = arguments[1]
        let root = URL(fileURLWithPath: arguments[arguments.count - 1])
        let code =
            arguments.count == 4
            ? try String(contentsOfFile: arguments[2]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if phase == "health-setup" || phase == "health-plain-setup" {
            try await healthSetUp(address: address, code: code, root: root)
            return true
        }
        var state = try HealthState.load(root)
        switch phase {
        case "health-offline": try await serverStopped(address: address, state: &state, root: root)
        case "health-online": try await serverBack(address: address, state: state, root: root)
        case "health-revoke": try await deviceRemoved(address: address, state: &state, root: root)
        case "health-stop-syncing": try await stopSyncingAndReconnect(address: address, state: &state, root: root)
        case "health-after-backup": try await writeAfterBackup(address: address, state: &state, root: root)
        case "health-restored": try await restoredServer(address: address, state: &state, root: root)
        case "health-reset": try await resetServer(address: address, code: code, state: &state, root: root)
        case "health-stop-before-reset": try await stopSyncing(address: address, state: &state, root: root)
        case "health-stop-reset": try await setUpAfterStopping(address: address, code: code, state: &state, root: root)
        case "health-replaced":
            try await replacedByAnotherLibrary(address: address, code: code, state: &state, root: root, encrypted: nil)
        case "health-plain-reconnect":
            try await plainReconnect(address: address, recoveryCode: code, state: &state, root: root)
        case "health-plain-replaced":
            try await replacedByAnotherLibrary(address: address, code: code, state: &state, root: root, encrypted: true)
        default: throw ProbeFailure("unknown phase \(phase)")
        }
        try state.save(root)
        return true
    }

    /// A, a library an earlier build made with its built-in templates, sets up the server with a journal, an entry and
    /// an image; B joins (with the password, or by pairing on a server without one). Both sync.
    static func healthSetUp(address: String, code: String, root: URL) async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let (master, phrase, envelope, secret) = try recoveryFixture()
        var state = HealthState(
            phrase: phrase, envelope: envelope, recoverySecret: secret,
            protection: try envelope.contentProtection.rawValue)
        let anonymous = try ServerClient(address: address)
        let grant = try await anonymous.initialize(
            code: code, envelope: envelope, recoverySecret: secret, deviceName: "Probe a")
        state.devices["a"] = .init(folder: "a", key: master, token: grant.token, deviceID: grant.deviceId)
        let deviceA = try open("a", state, root: root, address: address)
        for template in BuiltInTemplates.asEarlierBuildsCreated() { try await deviceA.store.save(template) }
        let journal = JournalItem(kind: "journal", title: "Default")
        try await deviceA.store.save(journal)
        let image = try await deviceA.store.addAttachment(Data(repeating: 7, count: 2048))
        state.image = image
        try await deviceA.store.save(
            JournalItem(
                kind: "entry", journalID: journal.id, title: "A1 with an image",
                document: .init(blocks: [
                    DocumentBlock(runs: [TextRun("Written before anything broke")]),
                    DocumentBlock(
                        kind: "image", attachmentID: image, imageDescription: "Photo", mediaType: "image/png"),
                ])))
        state.written.append("A1 with an image")
        try await deviceA.synchronize()
        let joined: DeviceGrant
        let key: Data
        if envelope.requiresPassword {
            let recovered = try await anonymous.recoverVault(
                phrase, parameters: anonymous.recoveryParameters(), deviceName: "Probe b")
            (joined, key) = (recovered.grant, recovered.key)
        } else {
            guard let client = deviceA.client else { throw ProbeFailure("a has no access") }
            joined = try await pairingGrant(anonymous, approver: client, master: master, version: 4)
            key = master
        }
        state.devices["b"] = .init(folder: "b", key: key, token: joined.token, deviceID: joined.deviceId)
        let deviceB = try open("b", state, root: root, address: address)
        try await converge([deviceA, deviceB], state: state, "set up")
        try state.save(root)
    }

    /// Row 1: the server is down while A writes. Sync waits by itself, with nothing for the person to do.
    private static func serverStopped(address: String, state: inout HealthState, root: URL) async throws {
        let deviceA = try open("a", state, root: root, address: address)
        try await write("A2 while the server was down", on: deviceA, state: &state)
        try await expectState(.unreachable, syncing: deviceA, "server stopped")
        guard !SyncHealth.unreachable.stopsAutomaticSync else {
            throw ProbeFailure("automatic sync stops for a server that's only down")
        }
    }
    private static func serverBack(address: String, state: HealthState, root: URL) async throws {
        let devices = try ["a", "b"].map { try open($0, state, root: root, address: address) }
        try await converge(devices, state: state, "server back")
    }

    /// Row 7: B removes A from Devices. A is told it has no access, not that the server changed, and connecting
    /// again sends what it wrote without merging.
    private static func deviceRemoved(address: String, state: inout HealthState, root: URL) async throws {
        let deviceA = try open("a", state, root: root, address: address)
        let deviceB = try open("b", state, root: root, address: address)
        guard let removed = state.devices["a"]?.deviceID else { throw ProbeFailure("a has no device") }
        try await deviceB.client?.revoke(removed)
        try await write("A3 after removal", on: deviceA, state: &state)
        try await expectState(.accessRemoved, syncing: deviceA, "device removed")
        let rejoined = try await connectAgain(deviceA, state: &state, root: root, address: address)
        try await converge([rejoined, deviceB], state: state, "connected again after removal")
    }

    /// Row 10 (with a password): Stop Syncing on A, writing, then connecting to the same server again joins by
    /// identity: nothing is copied again.
    private static func stopSyncingAndReconnect(address: String, state: inout HealthState, root: URL) async throws {
        try await stopSyncing(address: address, state: &state, root: root)
        let deviceA = try open("a", state, root: root, address: address)
        try await write("A4 while not syncing", on: deviceA, state: &state)
        let rejoined = try await connectAgain(deviceA, state: &state, root: root, address: address)
        let deviceB = try open("b", state, root: root, address: address)
        try await converge([rejoined, deviceB], state: state, "stopped syncing, then connected again")
    }

    /// Stop Syncing: A gives up its own access and keeps its library as it is.
    private static func stopSyncing(address: String, state: inout HealthState, root: URL) async throws {
        let deviceA = try open("a", state, root: root, address: address)
        if let id = state.devices["a"]?.deviceID { try? await deviceA.client?.revoke(id) }
        state.devices["a"]?.token = nil
        state.devices["a"]?.deviceID = nil
    }

    private static func writeAfterBackup(address: String, state: inout HealthState, root: URL) async throws {
        let deviceA = try open("a", state, root: root, address: address)
        let deviceB = try open("b", state, root: root, address: address)
        try await write("A5 after the backup", on: deviceA, state: &state)
        try await write("B1 after the backup", on: deviceB, state: &state)
        try await converge([deviceA, deviceB], state: state, "written after the backup")
    }

    /// Row 5: the server was restored from an older backup, which signs every device out. Both are told the server
    /// was restored or replaced; connecting again sends back what the backup lacks, without a merge.
    private static func restoredServer(address: String, state: inout HealthState, root: URL) async throws {
        var devices: [HealthDevice] = []
        for name in ["a", "b"] {
            let device = try open(name, state, root: root, address: address)
            try await expectState(.serverReplaced, syncing: device, "restored from an older backup")
            devices.append(try await connectAgain(device, state: &state, root: root, address: address))
        }
        try await converge(devices, state: state, "restored from an older backup")
        // Written before the reset of row 3, and never sent.
        try await write("B2 offline before the reset", on: devices[1], state: &state)
    }

    /// Row 3: the server is wiped and waits for a setup code. A sets it up again with its library; B is then told
    /// the server changed and connects again without merging, sending what it wrote offline; C joins.
    private static func resetServer(address: String, code: String, state: inout HealthState, root: URL) async throws {
        let deviceA = try open("a", state, root: root, address: address)
        let deviceB = try open("b", state, root: root, address: address)
        try await expectState(.serverNotSetUp, syncing: deviceA, "server reset")
        try await expectState(.serverNotSetUp, syncing: deviceB, "server reset")
        let grant = try await ServerClient(address: address).initialize(
            code: code, envelope: state.envelope, recoverySecret: state.recoverySecret, deviceName: "Probe a")
        state.devices["a"]?.token = grant.token
        state.devices["a"]?.deviceID = grant.deviceId
        let setUpAgain = try open("a", state, root: root, address: address)
        try await setUpAgain.synchronize()
        guard let client = setUpAgain.client,
            try await serverRecords(client) == setUpAgain.store.syncedRecordIDs(),
            try await setUpAgain.store.pending().isEmpty
        else { throw ProbeFailure("server reset: Set Up Server Again didn't send a's whole library") }
        print("PASS: server reset: Set Up Server Again sent a's whole library")
        try await expectState(.serverReplaced, syncing: deviceB, "set up again by another device")
        let rejoinedB = try await connectAgain(deviceB, state: &state, root: root, address: address)
        let anonymous = try ServerClient(address: address)
        let recovered = try await anonymous.recoverVault(
            state.phrase, parameters: anonymous.recoveryParameters(), deviceName: "Probe c")
        state.devices["c"] = .init(
            folder: "c", key: recovered.key, token: recovered.grant.token, deviceID: recovered.grant.deviceId)
        let deviceC = try open("c", state, root: root, address: address)
        try await converge([setUpAgain, rejoinedB, deviceC], state: state, "server reset and set up again")
    }

    /// Row 11: after Stop Syncing, the server is reset; connecting sets it up with everything.
    private static func setUpAfterStopping(
        address: String, code: String, state: inout HealthState, root: URL
    ) async throws {
        let deviceA = try open("a", state, root: root, address: address)
        try await write("A6 not syncing", on: deviceA, state: &state)
        guard try await !ServerClient(address: address).status().initialized else {
            throw ProbeFailure("the wiped server is still set up")
        }
        let grant = try await ServerClient(address: address).initialize(
            code: code, envelope: state.envelope, recoverySecret: state.recoverySecret, deviceName: "Probe a")
        state.devices["a"]?.token = grant.token
        state.devices["a"]?.deviceID = grant.deviceId
        // b and c belong to the server that was wiped; this row is about a alone.
        try await converge([try open("a", state, root: root, address: address)], state: state, "set up after stopping")
    }
}
