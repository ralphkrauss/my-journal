import CryptoKit
import Foundation
import JournalCore
import Security
import os

/// End-to-end checks of short push receipts and waiting for changes (docs/design/sync-protocol-efficiency.md §7.3),
/// run by scripts/test-sync-efficiency.sh against disposable servers:
///
/// - `wait <address> <setup-code file>`: short receipts, a held wait woken by another device, a confirming answer,
///   and revocation while waiting.
/// - `wait-fault <address> <setup-code file> <mode>`: through scripts/sync-fault-proxy.py in that mode.
/// - `wait-many <address> <setup-code file> <devices>`: many devices waiting while one writes.
/// - `wait-caddy <address> <setup-code file> <caddy https address> <root certificate PEM> <h2|h3>`: waits held
///   through a Caddy reverse proxy with its internal certificate authority, which only this probe trusts.
/// - `wait-push-bytes <address> <setup-code file> <words>`: 60 revisions of an entry of that many words, for the
///   counting proxy to measure what pushes download.
extension Probe {
    static func runWaitProbe() async throws -> Bool {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let name = arguments.first, name.hasPrefix("wait"), arguments.count >= 3 else { return false }
        let code = try String(contentsOfFile: arguments[2]).trimmingCharacters(in: .whitespacesAndNewlines)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("journal-wait-probe-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await WaitLibrary(address: arguments[1], code: code, root: root)
        switch name {
        case "wait": try await waitChecks(library)
        case "wait-fault" where arguments.count == 4: try await faultChecks(library, mode: arguments[3])
        case "wait-many" where arguments.count == 4: try await manyDevices(library, count: Int(arguments[3]) ?? 20)
        case "wait-caddy" where arguments.count == 6:
            try await throughCaddy(library, caddy: arguments[3], root: arguments[4], http3: arguments[5] == "h3")
        case "wait-push-bytes" where arguments.count == 4:
            try await writingSession(library.first, words: Int(arguments[3]) ?? 500)
        default: return false
        }
        return true
    }

    private static func waitChecks(_ library: WaitLibrary) async throws {
        let phone = try await library.device("Phone")
        let mac = library.first
        try await mac.write("Before waiting")
        let settled = try await phone.engine.synchronize()
        guard settled.settled, let mark = settled.quietMark,
            let position = try await phone.store.quietPosition(since: mark)
        else { throw ProbeFailure("a device that synchronized everything can't wait") }
        let waiting = Task { try await phone.engine.waitForChange(from: position) }
        try await Task.sleep(nanoseconds: 500_000_000)
        let written = ContinuousClock.now
        try await mac.write("Written while the phone waited")
        let answer = try await waiting.value
        let woke = ContinuousClock.now - written
        guard answer == .changed, woke < .seconds(1) else {
            throw ProbeFailure(
                "a held wait didn't wake within a second of another device's change (\(answer), \(woke))")
        }
        try await phone.engine.synchronize()
        guard try await phone.store.items().contains(where: { $0.document.text == "Written while the phone waited" })
        else { throw ProbeFailure("the woken device didn't receive the change") }
        print("PASS: a held wait wakes at once when another device writes, and the change arrives")

        let report = try await phone.engine.synchronize()
        guard let quiet = report.quietMark, let from = try await phone.store.quietPosition(since: quiet) else {
            throw ProbeFailure("no quiet position after an idle sync")
        }
        let started = ContinuousClock.now
        let confirming = try await phone.client.waitForChange(from, digest: true, timeout: 2)
        guard confirming == .unchanged(early: false), ContinuousClock.now - started >= .seconds(1.9) else {
            throw ProbeFailure("a wait with nothing to report didn't confirm at its timeout (\(confirming))")
        }
        print("PASS: a wait with nothing to report is held until its timeout and confirms")

        let revoked = Task { try await phone.engine.waitForChange(from: from) }
        try await Task.sleep(nanoseconds: 500_000_000)
        let revoking = ContinuousClock.now
        try await mac.client.revoke(phone.id)
        let refused = try await revoked.value
        guard refused == .failed, ContinuousClock.now - revoking < .seconds(1) else {
            throw ProbeFailure("a revoked device kept waiting (\(refused))")
        }
        do {
            try await phone.engine.synchronize()
            throw ProbeFailure("a revoked device still synchronized")
        } catch let failure as SyncFailure where failure.health == .accessRemoved {}
        print("PASS: revoking a device ends its wait at once, and its sync reports that access was removed")
        // Last: the payload sent is not a sealed record, which no device could read.
        try await shortReceiptOnTheWire(library)
    }

    /// The server's answer to a push that asks for a short receipt carries the digest and no payload.
    private static func shortReceiptOnTheWire(_ library: WaitLibrary) async throws {
        let payload = Data((0..<60).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        let body: [String: Any] = [
            "operationId": UUID().uuidString, "baseRevision": 0, "kind": "entry", "payload": payload,
            "shortReceipt": true,
        ]
        let receipt = try await library.raw(
            "PUT", "/v1/sync/\(UUID().uuidString.lowercased())", body: JSONSerialization.data(withJSONObject: body))
        guard receipt["payload"] == nil, receipt["payloadDigest"] as? String == digest(payload)
        else { throw ProbeFailure("a short receipt repeated the payload or lacked its digest") }
        print("PASS: a short receipt carries the payload's digest instead of the payload")
    }

    private static func faultChecks(_ library: WaitLibrary, mode: String) async throws {
        let device = library.first
        // With drop-push, the first push is the one whose answer is lost.
        if mode != "drop-push" { try await device.write("Synchronized before the fault") }
        switch mode {
        case "cut":
            let driver = await WaitDriver(device)
            await driver.run(seconds: 40)
            guard await !driver.ownsSchedule, await driver.waits >= 3 else {
                throw ProbeFailure("waits cut by a proxy didn't turn waiting off")
            }
            print("PASS: waits a proxy cuts turn waiting off; the device polls")
        case "halfopen", "reset":
            let position = try await device.settledPosition()
            let started = ContinuousClock.now
            let answer = try await device.engine.waitForChange(from: position)
            let took = ContinuousClock.now - started
            let expected: ClosedRange<Duration> =
                mode == "reset" ? .zero ... .seconds(5) : .seconds(25) ... .seconds(40)
            guard answer == .failed, expected.contains(took) else {
                throw ProbeFailure("a \(mode) wait answered \(answer) after \(took)")
            }
            try await device.write("Synchronized after the fault")
            print("PASS: a \(mode) wait fails within \(took) and synchronizing continues")
        case "buffer":
            let position = try await device.settledPosition()
            let answer = try await device.client.waitForChange(position, digest: true, timeout: 3)
            guard answer == .unchanged(early: false) else { throw ProbeFailure("a buffered wait answered \(answer)") }
            print("PASS: a proxy that buffers whole responses holds and answers waits")
        case "instant-true", "cached-false":
            let driver = await WaitDriver(device)
            await driver.run(seconds: 25)
            let requests = await driver.requests
            let gaps = zip(requests.dropFirst(), requests).map { $0 - $1 }
            guard gaps.allSatisfy({ $0 >= .seconds(2.9) }), await !driver.ownsSchedule, await driver.marked == 0
            else {
                throw ProbeFailure("\(mode): requests \(gaps), still waiting or Last Synced claimed a check")
            }
            print("PASS: answers that come at once (\(mode)) keep 3 s between requests and turn waiting off")
        case "drop-push":
            try await device.write("Sent while the answer is lost", expectingFailure: true)
            try await device.engine.synchronize()
            let changes = try await library.allChanges()
            let written = changes.filter { ($0["revision"] as? Int) == 1 }.count
            guard try await device.store.pending().isEmpty,
                written == Set(changes.compactMap { $0["recordId"] as? String }).count
            else { throw ProbeFailure("a push whose answer was lost was applied twice or left queued") }
            print("PASS: a push whose answer was lost is acknowledged once by its retry")
        default: throw ProbeFailure("unknown fault mode \(mode)")
        }
    }

    private static func manyDevices(_ library: WaitLibrary, count: Int) async throws {
        var devices: [WaitDevice] = []
        for index in 0..<count { devices.append(try await library.device("Device \(index)")) }
        let started = ContinuousClock.now
        let drivers = try await withThrowingTaskGroup(of: WaitDriver.self) { group in
            for device in devices {
                group.addTask {
                    let driver = await WaitDriver(device)
                    await driver.run(seconds: 45)
                    return driver
                }
            }
            try await Task.sleep(nanoseconds: 8_000_000_000)
            for index in 0..<100 { try await library.first.write("Change \(index)") }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        for device in devices {
            let received = try await device.store.items().filter { $0.document.text.hasPrefix("Change ") }.count
            guard received == 100 else { throw ProbeFailure("a waiting device has \(received) of 100 changes") }
        }
        var waits = 0
        for driver in drivers { waits += await driver.waits }
        print(
            "PASS: \(count) waiting devices received 100 changes in \(ContinuousClock.now - started) (\(waits) waits)")
    }

    private static func throughCaddy(_ library: WaitLibrary, caddy: String, root: String, http3: Bool) async throws {
        let phone = try await library.device("Phone")
        let proxy = try CaddyClient(address: caddy, root: root, http3: http3)
        let position = try await phone.settledPosition()
        var query = "after=\(position.cursor)&timeout=20"
        if let serverID = position.serverID { query += "&serverId=\(serverID)" }
        if position.cursor > 0, let applied = position.applied {
            query += "&afterRecord=\(applied.recordId.uuidString.lowercased())&afterRevision=\(applied.revision)"
        }

        var started = ContinuousClock.now
        let held = try await proxy.wait(query, token: phone.token)
        let heldFor = ContinuousClock.now - started
        guard held.body == #"{"changed":false}"#, heldFor >= .seconds(19.5) else {
            throw ProbeFailure("through Caddy (\(held.protocolName)), a wait answered \(held.body) after \(heldFor)")
        }
        print("PASS: through Caddy over \(held.protocolName), a wait is held for \(heldFor) and confirms")

        let woken = Task { try await proxy.wait(query, token: phone.token) }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let writing = ContinuousClock.now
        try await library.first.write("Written while the phone waited through Caddy")
        let wake = try await woken.value
        let latency = ContinuousClock.now - writing
        guard wake.body == #"{"changed":true}"#, latency < .seconds(1) else {
            throw ProbeFailure("through Caddy, a wait woke after \(latency) with \(wake.body)")
        }
        print(
            "PASS: through Caddy over \(wake.protocolName), a held wait wakes \(latency) after another device's write")

        // The server holds one wait at a time (Journal:SyncWaitCapacity=1): once the phone's wait through Caddy is
        // cancelled, the Mac's wait is held instead of answered early only if Caddy passed the cancellation on.
        try await phone.engine.synchronize()
        let next = try await phone.settledPosition()
        let cancelled = Task { try await proxy.wait("after=\(next.cursor)&timeout=20", token: phone.token) }
        try await Task.sleep(nanoseconds: 2_000_000_000)
        cancelled.cancel()
        _ = try? await cancelled.value
        try await Task.sleep(nanoseconds: 500_000_000)
        started = ContinuousClock.now
        let macPosition = try await library.first.settledPosition()
        let mac = try await library.first.client.waitForChange(macPosition, digest: true, timeout: 3)
        guard mac == .unchanged(early: false), ContinuousClock.now - started >= .seconds(2.5) else {
            throw ProbeFailure("a wait cancelled through Caddy still held its slot (\(mac))")
        }
        print("PASS: cancelling a wait through Caddy frees its slot on the server")
    }

    private static func writingSession(_ device: WaitDevice, words: Int) async throws {
        let text = (0..<words).map { "word\($0 % 997)" }.joined(separator: " ")
        var entry = try await device.store.save(
            JournalItem(kind: "entry", journalID: UUID(), document: .plain(text)))
        try await device.engine.synchronize()
        for revision in 1...60 {
            entry.document = .plain(text + " revision \(revision)")
            entry = try await device.store.save(entry)
            try await device.engine.synchronize()
        }
        guard try await device.store.pending().isEmpty else { throw ProbeFailure("revisions left unsent") }
        print("PASS: 61 revisions of a \(words)-word entry sent")
    }
}

private func digest(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

/// A library set up on a disposable server, whose devices join with the recovery secret.
struct WaitLibrary: Sendable {
    let address: String
    let first: WaitDevice
    private let master: Data
    private let recoverySecret: String
    private let root: URL
    private let token: String

    init(address: String, code: String, root: URL) async throws {
        let (master, _, envelope, recoverySecret) = try Probe.recoveryFixture()
        let grant = try await ServerClient(address: address).initialize(
            code: code, envelope: envelope, recoverySecret: recoverySecret, deviceName: "Probe Mac")
        self.address = address
        self.master = master
        self.recoverySecret = recoverySecret
        self.root = root
        token = grant.token
        first = try WaitDevice(
            address: address, grant: grant, key: master,
            directory: root.appendingPathComponent("mac"))
        _ = try await first.store.save(JournalItem(kind: "journal", title: "Shared"))
    }

    func device(_ name: String) async throws -> WaitDevice {
        let grant = try await ServerClient(address: address).recover(secret: recoverySecret, deviceName: name)
        let device = try WaitDevice(
            address: address, grant: grant, key: master,
            directory: root.appendingPathComponent(UUID().uuidString))
        try await device.engine.synchronize()
        return device
    }

    /// One request as the first device, for checks of the wire format; returns its JSON object.
    func raw(_ method: String, _ path: String, body: Data? = nil) async throws -> [String: Any] {
        guard let url = URL(string: address + path) else { throw ProbeFailure("bad address") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ProbeFailure("\(method) \(path) failed") }
        return object
    }

    /// Every change in the server's log, without payloads.
    func allChanges() async throws -> [[String: Any]] {
        var changes: [[String: Any]] = []
        var after = 0
        while true {
            let page = try await raw("GET", "/v1/sync/?after=\(after)&limit=200")
            let batch = page["changes"] as? [[String: Any]] ?? []
            changes += batch.map { $0.filter { $0.key != "payload" } }
            after = page["cursor"] as? Int ?? after
            guard page["hasMore"] as? Bool == true else { return changes }
        }
    }
}

/// One device: its store, client and synchronization.
struct WaitDevice: Sendable {
    let id: UUID
    let token: String
    let store: JournalStore
    let client: ServerClient
    let engine: SyncEngine
    private let journal = UUID()

    init(address: String, grant: DeviceGrant, key: Data, directory: URL) throws {
        id = grant.deviceId
        token = grant.token
        store = try JournalStore(directory: directory, key: key)
        client = try ServerClient(address: address, token: grant.token)
        engine = SyncEngine(store: store, client: client)
    }

    /// Saves an entry and synchronizes it.
    func write(_ text: String, expectingFailure: Bool = false) async throws {
        try await store.save(JournalItem(kind: "entry", journalID: journal, document: .plain(text)))
        do {
            try await engine.synchronize()
            if expectingFailure { throw ProbeFailure("the synchronization was expected to fail") }
        } catch  where expectingFailure && !(error is ProbeFailure) {}
    }

    /// The position to wait from after a settled synchronization.
    func settledPosition() async throws -> QuietPosition {
        let report = try await engine.synchronize()
        guard report.settled, let mark = report.quietMark, let position = try await store.quietPosition(since: mark)
        else { throw ProbeFailure("the device didn't settle") }
        return position
    }
}

/// The app's automatic sync loop as far as waiting goes (AppModel.synchronizeAutomatically): polls every 3 s while
/// the change watcher doesn't own the schedule, and carries out its actions while it does.
@MainActor final class WaitDriver {
    private let device: WaitDevice
    private var watcher = ChangeWatcher(now: .now)
    private var waitTask: Task<Void, Never>?
    private var syncDue = true
    private var nextPoll = ContinuousClock.now
    private(set) var waits = 0
    private(set) var marked = 0
    /// When each request the loop started began: waits and synchronizations.
    private(set) var requests: [ContinuousClock.Instant] = []
    var ownsSchedule: Bool { watcher.ownsSchedule }

    init(_ device: WaitDevice) { self.device = device }

    func run(seconds: Int) async {
        handle(.conditions(allowWaiting: true))
        let end = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < end {
            handle(.tick)
            let due =
                watcher.ownsSchedule ? syncDue : ContinuousClock.now >= nextPoll && watcher.allowsRequest(at: .now)
            if due {
                syncDue = false
                await synchronize()
                nextPoll = .now + .seconds(3)
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        waitTask?.cancel()
    }

    private func handle(_ event: ChangeWatcher.Event) {
        for action in watcher.handle(event, at: .now) {
            switch action {
            case .startWait(let id, let mark): startWait(id: id, mark: mark)
            case .cancelWait: waitTask?.cancel()
            case .syncNow: syncDue = true
            case .markSynced: marked += 1
            case .publishAgentCopies: break
            case .forgetStatus: Task { await device.engine.forgetStatus() }
            }
        }
    }

    private func synchronize() async {
        let started = ContinuousClock.now
        requests.append(started)
        handle(.syncStarted)
        do {
            let report = try await device.engine.synchronize()
            handle(
                .syncFinished(
                    .init(
                        outcome: report.settled ? .settled : .unsettled, startedAt: started, finishedAt: .now,
                        mark: report.quietMark, position: report.position,
                        earliestRetry: report.earliestRetry.map { .milliseconds(Int64($0 * 1000)) })))
        } catch {
            handle(.syncFinished(.init(outcome: .failed, startedAt: started, finishedAt: .now)))
        }
    }

    private func startWait(id: Int, mark: QuietMark) {
        waits += 1
        requests.append(.now)
        let device = device
        waitTask = Task {
            guard let position = try? await device.store.quietPosition(since: mark), !Task.isCancelled else {
                return handle(.quietBroken(waitID: id))
            }
            handle(.waitSent(id: id, position: position, at: Date()))
            let answer: WaitAnswer?
            do { answer = try await device.engine.waitForChange(from: position) } catch {
                guard !Task.isCancelled else { return }
                answer = nil
            }
            guard !Task.isCancelled else { return }
            guard await device.store.isQuiet(mark) else { return handle(.quietBroken(waitID: id)) }
            handle(.waitEnded(id: id, answer: answer))
        }
    }
}

/// Requests through a reverse proxy whose certificate comes from its own authority: only that root is trusted, by
/// this session alone; nothing in the system's trust changes.
final class CaddyClient: NSObject, URLSessionTaskDelegate, Sendable {
    private let address: String
    private let anchor: SecCertificate
    private let http3: Bool
    private let protocols = ProtocolLog()

    init(address: String, root: String, http3: Bool) throws {
        let pem = try String(contentsOfFile: root, encoding: .utf8)
        let base64 = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
        guard let der = Data(base64Encoded: base64), let certificate = SecCertificateCreateWithData(nil, der as CFData)
        else { throw ProbeFailure("unreadable root certificate") }
        self.address = address
        anchor = certificate
        self.http3 = http3
    }

    /// A wait's body and the protocol it used.
    func wait(_ query: String, token: String) async throws -> (body: String, protocolName: String) {
        guard let url = URL(string: address + "/v1/sync/wait?" + query) else { throw ProbeFailure("bad address") }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.assumesHTTP3Capable = http3
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 35
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request, delegate: self)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ProbeFailure("a wait through Caddy answered \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return (String(decoding: data, as: UTF8.self), protocols.last)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard let trust = challenge.protectionSpace.serverTrust else { return (.cancelAuthenticationChallenge, nil) }
        SecTrustSetAnchorCertificates(trust, [anchor] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        guard SecTrustEvaluateWithError(trust, nil) else { return (.cancelAuthenticationChallenge, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        protocols.record(metrics.transactionMetrics.last?.networkProtocolName ?? "unknown")
    }
}

/// The protocol of the latest request, written by URLSession's delegate queue.
final class ProtocolLog: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: "unknown")
    var last: String { value.withLock { $0 } }
    func record(_ name: String) { value.withLock { $0 = name } }
}
