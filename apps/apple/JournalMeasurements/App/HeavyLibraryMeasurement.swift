import JournalCore
import SwiftUI
import XCTest

@testable import Journal

/// Measures the app with the real views, model, editor and store on a library shaped like ten years of heavy use
/// (seeded by scripts/measure-app.sh). It asserts only that each step did what it measures; the numbers go to the
/// report, which docs/performance.md compares with the budgets.
@MainActor final class HeavyLibraryMeasurement: XCTestCase {
    func testHeavyLibrary() async throws {
        continueAfterFailure = false
        let fixture = try MeasurementFixture()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            "JournalMeasure-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let run = try HeavyLibraryRun(fixture: fixture, directory: temporary)
        // Whatever was measured is reported, also when a later step fails.
        defer {
            run.window.activity.stop()
            try? run.report.emit()
        }
        try await run.window.settle()
        run.report["footprintLockedMB"] = physicalFootprintMegabytes()
        let steps: [(String, () async throws -> Void)] = [
            ("unlock", run.measureUnlock), ("opening", run.measureOpening), ("typing", run.measureTyping),
            ("search", run.measureSearch), ("idle sync", run.measureIdleSync),
            ("typing session", run.measureTypingSessionPushes), ("photos", run.measurePhotos),
            ("new device", { try await run.measureNewDevice(in: temporary) }),
        ]
        let chosen = ProcessInfo.processInfo.environment["JOURNAL_MEASURE_STEPS"].map {
            Set($0.split(separator: ",").map(String.init))
        }
        for (name, step) in steps where chosen?.isEmpty != false || chosen?.contains(name) == true {
            let start = MainThreadActivity.now()
            print("JOURNAL-MEASUREMENT-STEP \(name)")
            try await step()
            run.report["stepSeconds." + name] = Double(MainThreadActivity.now() - start) / 1e9
        }
    }
}

/// One measurement run: the model and window on a fresh copy of the seeded library.
@MainActor final class HeavyLibraryRun {
    let fixture: MeasurementFixture
    let model: AppModel
    let window: MeasuredWindow
    let report = MeasurementReport()
    var manifest: MeasurementFixture.Manifest { fixture.manifest }

    init(fixture: MeasurementFixture, directory: URL) throws {
        self.fixture = fixture
        let library = try fixture.copyLibrary(to: directory)
        model = AppModel(directory: directory)
        let envelope = try VaultCrypto.makeRecovery(masterKey: fixture.key, phrase: VaultCrypto.recoveryPhrase()).0
        model.configuration = LocalConfiguration(
            recovery: envelope, recoveryConfirmed: true, storageFolder: "library",
            lastJournalID: fixture.manifest.journalID)
        model.store = try JournalStore(directory: library, key: fixture.key)
        model.locked = true
        model.loaded = true
        window = MeasuredWindow(model: model, size: Self.windowSize)
    }

    static var windowSize: CGSize {
        #if os(macOS)
            CGSize(width: 1_100, height: 720)
        #else
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen.bounds.size
                ?? CGSize(width: 402, height: 874)
        #endif
    }

    private func seconds(_ start: UInt64, _ end: UInt64) -> Double { Double(end - start) / 1e9 }

    /// From a verified credential to the list of entries on screen: what unlocking and launching wait for.
    func measureUnlock() async throws {
        let start = MainThreadActivity.now()
        model.locked = false
        try await model.refresh()
        model.selectInitialEntry(reveal: true)
        let finished = try await window.settle(after: start)
        XCTAssertFalse(model.entries.isEmpty)
        report["unlockToListSeconds"] = seconds(start, finished)
        report["unlockMainThreadMilliseconds"] = window.activity.busyMilliseconds(from: start, to: finished)
        report["footprintUnlockedMB"] = physicalFootprintMegabytes()
        // Locking forgets everything decoded; unlocking again reads the library while the system still caches it.
        model.configuration?.appLock = true
        XCTAssertTrue(model.lockImmediately())
        await model.saveWhileLocked()
        try await window.settle()
        let again = MainThreadActivity.now()
        model.locked = false
        try await model.refresh()
        model.selectInitialEntry(reveal: true)
        let shown = try await window.settle(after: again)
        report["unlockAgainToListSeconds"] = seconds(again, shown)
        report["unlockAgainMainThreadMilliseconds"] = window.activity.busyMilliseconds(from: again, to: shown)
        model.configuration?.appLock = nil
    }

    private func open(_ id: UUID) async throws -> Double {
        let start = MainThreadActivity.now()
        let selected = await model.select(id)
        XCTAssertTrue(selected)
        #if os(iOS)
            // Stacked navigation shows the entry the way launching reveals a remembered one.
            model.revealsSelection = true
        #endif
        let finished = try await window.settle(after: start)
        XCTAssertNotNil(window.textView())
        return seconds(start, finished)
    }

    func measureOpening() async throws {
        report["openNormalEntrySeconds"] = try await open(manifest.normalEntryID)
        report["openLongEntrySeconds"] = try await open(manifest.longEntryID)
        report["reopenNormalEntrySeconds"] = try await open(manifest.normalEntryID)
        // Any change the model publishes updates every view that observes it, whatever changed.
        var updates: [Double] = []
        var updateCPU: [Double] = []
        for _ in 0..<10 {
            let start = MainThreadActivity.now()
            let cpu = threadCPUMilliseconds()
            model.objectWillChange.send()
            let finished = try await window.settle()
            updateCPU.append(threadCPUMilliseconds() - cpu)
            updates.append(window.activity.busyMilliseconds(from: start, to: finished))
        }
        report.distribution("wholeModelUpdateMilliseconds", updates)
        report.distribution("wholeModelUpdateCPUMilliseconds", updateCPU)
    }

    /// Main-thread time each keystroke causes, typed at a steady pace in the middle of the entry, including the
    /// autosave that follows it and every view update the model's changes cause.
    private func keystrokes(_ count: Int, pace: Double = 0.15) async throws
        -> (direct: [Double], busy: [Double], cpu: [Double])
    {
        guard let view = window.textView() else { throw MeasurementFailure("No editor.") }
        window.placeCaretNearMiddle(of: view)
        try await window.settle()
        let letters = Array("the quick brown fox jumps over the lazy dog ")
        var starts: [UInt64] = []
        var direct: [Double] = []
        var cpu: [Double] = [threadCPUMilliseconds()]
        for index in 0..<count {
            let start = MainThreadActivity.now()
            window.type(String(letters[index % letters.count]), in: view)
            direct.append(Double(MainThreadActivity.now() - start) / 1e6)
            starts.append(start)
            try await Task.sleep(nanoseconds: UInt64(pace * 1e9))
            cpu.append(threadCPUMilliseconds())
        }
        let finished = try await window.settle()
        let busy = starts.indices.map { index in
            window.activity.busyMilliseconds(
                from: starts[index], to: index + 1 < starts.count ? starts[index + 1] : finished)
        }
        let saved = await model.finishPendingSave()
        XCTAssertTrue(saved)
        return (direct, busy, zip(cpu.dropFirst(), cpu).map { $0 - $1 })
    }

    func measureTyping() async throws {
        _ = try await open(manifest.normalEntryID)
        var result = try await keystrokes(60)
        report.distribution("keystrokeNormalBusyMilliseconds", result.busy)
        report.distribution("keystrokeNormalCPUMilliseconds", result.cpu)
        report.distribution("keystrokeNormalDirectMilliseconds", result.direct)
        _ = try await open(manifest.longEntryID)
        result = try await keystrokes(40)
        report.distribution("keystrokeLongBusyMilliseconds", result.busy)
        report.distribution("keystrokeLongCPUMilliseconds", result.cpu)
        report.distribution("keystrokeLongDirectMilliseconds", result.direct)
        // A search left in the list while writing.
        _ = try await open(manifest.normalEntryID)
        model.query = "lighthouse"
        try await window.settle()
        result = try await keystrokes(40)
        report.distribution("keystrokeWithSearchBusyMilliseconds", result.busy)
        report.distribution("keystrokeWithSearchCPUMilliseconds", result.cpu)
        model.query = ""
        try await window.settle()
    }

    /// Typing a query into the search of All Entries, one character at a time.
    func measureSearch() async throws {
        let shown = await model.showCollection(all: true)
        XCTAssertTrue(shown)
        try await window.settle()
        for term in ["lighthouse", "orchid"] {
            var starts: [UInt64] = []
            var cpu: [Double] = [threadCPUMilliseconds()]
            for length in 1...term.count {
                starts.append(MainThreadActivity.now())
                model.query = String(term.prefix(length))
                try await Task.sleep(nanoseconds: 150_000_000)
                cpu.append(threadCPUMilliseconds())
            }
            report.distribution("searchKeystrokeCPUMilliseconds." + term, zip(cpu.dropFirst(), cpu).map { $0 - $1 })
            let finished = try await waitForResults(count: manifest.searchTerms[term] ?? 0)
            let busy = starts.indices.map { index in
                window.activity.busyMilliseconds(
                    from: starts[index], to: index + 1 < starts.count ? starts[index + 1] : finished)
            }
            report.distribution("searchKeystrokeBusyMilliseconds." + term, busy)
            if let last = starts.last {
                report["searchResultsAfterLastKeystrokeSeconds." + term] = seconds(last, finished)
            }
            model.query = ""
            try await window.settle()
        }
    }

    private func waitForResults(count: Int) async throws -> UInt64 {
        for _ in 0..<600 {
            let finished = try await window.settle()
            if model.entries.count == count { return finished }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw MeasurementFailure("Search results didn't appear.")
    }

    /// A connected library with nothing new on either side, as it is most of the time.
    func measureIdleSync() async throws {
        let server = SyncFixtureServer(
            log: [], cursor: manifest.cursor, serverID: manifest.serverID, attachments: fixture.attachments)
        let http = try await FakeJournalServer { server.respond($0) }
        model.connection = SyncConnection(address: http.address, deviceID: UUID(), token: "measurement")
        model.configureSync()
        var start = MainThreadActivity.now()
        var synchronized = await model.sync()
        XCTAssertTrue(synchronized)
        var finished = try await window.settle()
        report["firstSyncAfterUnlockSeconds"] = seconds(start, finished)
        var durations: [Double] = []
        var busy: [Double] = []
        for _ in 0..<10 {
            start = MainThreadActivity.now()
            synchronized = await model.sync()
            XCTAssertTrue(synchronized)
            finished = try await window.settle()
            durations.append(seconds(start, finished) * 1_000)
            busy.append(window.activity.busyMilliseconds(from: start, to: finished))
        }
        XCTAssertNil(model.syncError)
        report.distribution("idleSyncMilliseconds", durations)
        report.distribution("idleSyncMainThreadMilliseconds", busy)
        report["idleSyncRequestsPerPass"] = Double(server.current.requests - 2) / 10
        report["idleSyncRequests"] = server.current.kinds
        model.connection = nil
        model.configureSync()
    }

    /// How many revisions of an entry reach the server during a writing session with short pauses.
    func measureTypingSessionPushes() async throws {
        let server = SyncFixtureServer(
            log: [], cursor: manifest.cursor, serverID: manifest.serverID, attachments: fixture.attachments)
        let http = try await FakeJournalServer { server.respond($0) }
        model.connection = SyncConnection(address: http.address, deviceID: UUID(), token: "measurement")
        model.configureSync()
        _ = try await open(manifest.normalEntryID)
        let loop = Task { await model.synchronizeAutomatically() }
        var typed = 0
        for _ in 0..<4 {
            typed += try await keystrokes(20).busy.count
            try await Task.sleep(nanoseconds: 2_500_000_000)
        }
        try await Task.sleep(nanoseconds: 5_000_000_000)
        loop.cancel()
        await loop.value
        report["typingSessionKeystrokes"] = typed
        report["typingSessionPushes"] = server.current.pushes[manifest.normalEntryID] ?? 0
        model.connection = nil
        model.configureSync()
    }

    /// Opening and scrolling through an entry with camera-sized photos.
    func measurePhotos() async throws {
        let before = physicalFootprintMegabytes()
        let start = MainThreadActivity.now()
        _ = try await open(manifest.photoEntryID)
        for _ in 0..<3_000 where !model.imageLoader.loading.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(model.imageLoader.loading.isEmpty)
        let loaded = try await window.settle()
        report["photoEntryImagesLoadedSeconds"] = seconds(start, loaded)
        var peak = physicalFootprintMegabytes()
        guard let view = window.textView() else { throw MeasurementFailure("No editor.") }
        for step in 0...20 {
            window.scroll(view, to: CGFloat(step) / 20)
            try await window.settle()
            peak = max(peak, physicalFootprintMegabytes())
        }
        report["photoEntryFootprintBeforeMB"] = before
        report["photoEntryFootprintPeakMB"] = peak
        _ = try await open(manifest.normalEntryID)
        report["photoEntryFootprintAfterLeavingMB"] = physicalFootprintMegabytes()
    }

    /// A new device connecting to the server of this library: when its synchronization returns (the app shows the
    /// entries then), and how many of the library's images it waited for.
    func measureNewDevice(in temporary: URL) async throws {
        let server = SyncFixtureServer(
            log: try fixture.log(), serverID: manifest.serverID, attachments: fixture.attachments,
            imageLatency: 0.004, bytesPerSecond: 25_000_000)
        let http = try await FakeJournalServer { server.respond($0) }
        let store = try JournalStore(directory: temporary.appendingPathComponent("new-device"), key: fixture.key)
        let engine = SyncEngine(store: store, client: try ServerClient(address: http.address, token: "measurement"))
        let start = MainThreadActivity.now()
        try await engine.synchronize()
        report["newDeviceFirstSyncSeconds"] = seconds(start, MainThreadActivity.now())
        report["newDeviceImagesBeforeFirstSyncReturned"] = server.current.imagesServed
        let entries = try await store.viewSnapshot().items.filter { $0.kind == "entry" }
        XCTAssertEqual(entries.count, manifest.shape.entries)
        try await store.close()
    }
}
