import Foundation
import JournalCore

/// Single failure cases of the inventory (docs/design/sync-health-and-recovery.md §1) that a real server, network or
/// device can produce, each checked for the state the person would see: `health-cases <URL> <setup-code file>
/// <state directory>` on a new server, and `health-addresses <certificate URL> <other web server URL>`.
extension Probe {
    static func runHealthCases() async throws -> Bool {
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch arguments.first {
        case "health-cases" where arguments.count == 4:
            let code = try String(contentsOfFile: arguments[2]).trimmingCharacters(in: .whitespacesAndNewlines)
            try await cases(address: arguments[1], code: code, root: URL(fileURLWithPath: arguments[3]))
        case "health-addresses" where arguments.count == 3:
            try await addresses(certificate: arguments[1], otherServer: arguments[2])
        default: return false
        }
        return true
    }

    /// Case 4: a certificate that isn't valid. Case 5: an address that doesn't resolve. Case 6: another web server.
    private static func addresses(certificate: String, otherServer: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("journal-addresses-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        let cases: [(String, SyncHealth, String)] = [
            (certificate, .certificateInvalid, "a self-signed certificate"),
            ("https://journal.invalid", .unreachable, "an address that doesn't resolve"),
            (otherServer, .notJournalServer, "another web server at the address"),
        ]
        for (address, expected, situation) in cases {
            let device = HealthDevice(name: "a", store: store, client: try ServerClient(address: address, token: "t"))
            try await expectState(expected, syncing: device, situation)
            guard !expected.stopsAutomaticSync else { throw ProbeFailure("\(situation) stops automatic sync") }
        }
        try await store.close()
    }

    private static func cases(address: String, code: String, root: URL) async throws {
        try await healthSetUp(address: address, code: code, root: root)
        var state = try HealthState.load(root)
        try await passwordChangedElsewhere(address: address, state: &state, root: root)
        try await credentialNotAccepted(address: address, state: state, root: root)
        try await rateLimited(address: address, state: state, root: root)
        try await localDataUnreadable(address: address, state: &state, root: root)
        try await entryTooLarge(address: address, state: &state, root: root)
        try state.save(root)
    }

    /// Case 13: the password is changed on another device. This one keeps syncing, and a new device signs in with the
    /// new password.
    private static func passwordChangedElsewhere(address: String, state: inout HealthState, root: URL) async throws {
        let deviceA = try open("a", state, root: root, address: address)
        let deviceB = try open("b", state, root: root, address: address)
        guard let key = state.devices["b"]?.key, let client = deviceB.client else { throw ProbeFailure("no b") }
        let newPassword = "a new disposable password"
        let envelope = try await client.recoveryEnvelope()
        let change = try VaultCrypto.changePassword(envelope, current: state.phrase, new: newPassword, masterKey: key)
        try await client.changePassword(change)
        state.phrase = newPassword
        state.envelope = change.envelope
        state.recoverySecret = change.newRecoverySecret
        try await write("A after the password changed", on: deviceA, state: &state)
        try await converge([deviceA, deviceB], state: state, "password changed on another device")
        let anonymous = try ServerClient(address: address)
        _ = try await anonymous.recoverVault(
            newPassword, parameters: anonymous.recoveryParameters(), deviceName: "Probe new device")
        print("PASS: password changed on another device: a new device signs in with the new password")
    }

    /// Case 12: a credential the server no longer accepts on the same server.
    private static func credentialNotAccepted(address: String, state: HealthState, root: URL) async throws {
        var deviceA = try open("a", state, root: root, address: address)
        deviceA.client = try ServerClient(address: address, token: String(repeating: "0", count: 64))
        try await expectState(.accessRemoved, syncing: deviceA, "a credential the server doesn't accept")
        try await deviceA.store.close()
    }

    /// Case 17: the server limits requests; the state is temporary and the server's wait is kept.
    private static func rateLimited(address: String, state: HealthState, root: URL) async throws {
        guard let token = state.devices["a"]?.token, let key = state.devices["a"]?.key else {
            throw ProbeFailure("no a")
        }
        // The server counts this device's requests for what deriving the password needs.
        let client = try ServerClient(address: address, token: token)
        var limited = false
        for _ in 0..<200 where !limited {
            do { _ = try await client.recoveryParameters() } catch is ServerRateLimited { limited = true }
        }
        guard limited else { throw ProbeFailure("the server never limited requests") }
        // A copy of the library that hasn't synced with this server yet reads how it stores journals first.
        let store = try JournalStore(
            directory: root.appendingPathComponent("rate-limited"), key: key)
        do {
            try await SyncEngine(store: store, client: client).synchronize()
            throw ProbeFailure("a rate-limited sync succeeded")
        } catch let failure as ServerRateLimited {
            guard SyncHealth(classifying: failure) == .unavailable, !SyncHealth.unavailable.stopsAutomaticSync,
                (failure.retryAfter ?? 0) > 0
            else { throw ProbeFailure("rate limiting isn't temporary with the server's wait") }
            print(
                "PASS: rate limited: “\(SyncHealth.unavailable.message())”, retrying after \(failure.retryAfter ?? 0) s"
            )
        }
        try await store.close()
    }

    /// Case 18: this device's own store can't be read. The database is damaged where records are kept.
    private static func localDataUnreadable(address: String, state: inout HealthState, root: URL) async throws {
        let deviceA = try open("a", state, root: root, address: address)
        try await write("A before b's copy is damaged", on: deviceA, state: &state)
        try await deviceA.synchronize()
        let copy = root.appendingPathComponent("b-damaged")
        let original = try open("b", state, root: root)
        try await original.store.snapshot(to: copy)
        try await original.store.close()
        let file = copy.appendingPathComponent("journal.sqlite")
        // The page where the records table starts is overwritten, as a failing disk would.
        let page = try Int(sqlite(file, "PRAGMA page_size")) ?? 4096
        guard let root = try Int(sqlite(file, "SELECT rootpage FROM sqlite_master WHERE name = 'records'")) else {
            throw ProbeFailure("the records table wasn't found")
        }
        var bytes = try Data(contentsOf: file)
        bytes.replaceSubrange(((root - 1) * page)..<(root * page), with: Data(repeating: 0x5A, count: page))
        try bytes.write(to: file)
        let damaged: JournalStore
        do {
            damaged = try JournalStore(directory: copy, key: state.devices["b"]?.key ?? Data())
        } catch {
            throw ProbeFailure("the damaged copy didn't open far enough to sync: \(error)")
        }
        let device = HealthDevice(
            name: "b (damaged)", store: damaged,
            client: try ServerClient(address: address, token: state.devices["b"]?.token ?? ""))
        try await expectState(.localDataUnreadable, syncing: device, "this device's data is damaged")
        try await damaged.close()
    }

    /// Case 16: an entry too large to sync is kept on this device with an explanation, and the rest syncs. (This app
    /// never sends an image larger than the server takes; the server's own refusals are SyncEngineTests' and
    /// SyncHealthTests'.)
    private static func entryTooLarge(address: String, state: inout HealthState, root: URL) async throws {
        let deviceA = try open("a", state, root: root, address: address)
        let deviceB = try open("b", state, root: root, address: address)
        try await deviceA.store.save(
            JournalItem(
                kind: "entry", journalID: nil, title: "A pasted log",
                document: .plain(String(repeating: "A long pasted log line. ", count: 220_000))))
        try await write("Sent beside the pasted log", on: deviceA, state: &state)
        guard let client = deviceA.client else { throw ProbeFailure("no a") }
        let report = try await SyncEngine(store: deviceA.store, client: client).synchronize()
        let expected =
            "“A pasted log” is too large to sync. It’s saved on this device. Shorten it or split it into separate entries."
        guard report.problem == expected else {
            throw ProbeFailure("a refused entry isn't explained: \(report.problem ?? "nothing")")
        }
        try await deviceB.synchronize()
        let titles = try await deviceB.store.items().map(\.title)
        guard titles.contains("Sent beside the pasted log"), !titles.contains("A pasted log") else {
            throw ProbeFailure("the rest didn't sync around the refused entry")
        }
        print("PASS: an entry too large to sync: “\(expected)”, and the rest syncs")
    }

    /// One value from the sqlite3 tool, which reads the file without the app's code.
    private static func sqlite(_ file: URL, _ query: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [file.path, query]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
