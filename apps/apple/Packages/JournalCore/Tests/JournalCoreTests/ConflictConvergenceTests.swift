import XCTest

@testable import JournalCore

/// Devices that change one entry meet at an in-memory server: every text written survives somewhere, the copies stay
/// bounded, three devices converge, and a version 1.0 device that still asks the person keeps syncing with them
/// (protocol/conflicts.md, Orchestration and Mixed clients). The scripted conversations other clients replay are in
/// ConflictScenarioTests.
final class ConflictConvergenceTests: ConflictTestCase {
    private struct Device {
        let store: JournalStore
        let engine: SyncEngine
        let id: UUID
    }

    private var server = MemoryServer()

    private func device(_ name: String) async throws -> Device {
        let store = try await openStore(name)
        let id = UUID()
        return Device(
            store: store, engine: SyncEngine(store: store, server: DeviceServer(server: server, device: id)), id: id)
    }
    private func sync(_ device: Device) async throws {
        time.withLock { $0 = $0.addingTimeInterval(3) }
        try await device.engine.synchronize()
    }
    private func write(_ text: String, on device: Device, record: UUID) async throws {
        var item = try await stored(device.store, record)
        item.document = .plain(text)
        try await device.store.save(item)
    }
    /// Every text of the entry's records on a device, in records and in the Version History of any of them.
    private func texts(on device: Device) async throws -> Set<String> {
        var all = Set<String>()
        for item in try await device.store.items() where item.kind == "entry" {
            all.insert(item.document.text)
            for old in try await device.store.history(for: item.id) { all.insert(old.document.text) }
        }
        return all
    }
    private func entries(on device: Device) async throws -> [JournalItem] {
        try await device.store.items().filter { $0.kind == "entry" && !$0.isPermanentlyDeleted }
    }
    private func start(_ devices: [Device]) async throws -> JournalItem {
        let home = journal("Home")
        let page = entry("Page", text: "t", journal: home.id)
        try await devices[0].store.save(home)
        try await devices[0].store.save(page)
        for device in devices { try await sync(device) }
        return page
    }

    // MARK: Three devices converge

    func testThreeDevicesEditingOneEntryConvergeInEverySyncOrderAndLoseNoText() async throws {
        let orders: [[Int]] = [[0, 1, 2], [2, 1, 0], [1, 0, 2], [1, 2, 0]]
        for (index, order) in orders.enumerated() {
            server = MemoryServer()
            let names = ["a", "b", "c"].map { "\($0)-\(index)" }
            let devices = [try await device(names[0]), try await device(names[1]), try await device(names[2])]
            let page = try await start(devices)
            let written = ["a", "b", "c"]
            for (position, device) in devices.enumerated() {
                try await write(written[position], on: device, record: page.id)
            }
            for position in order { try await sync(devices[position]) }
            for _ in 0..<3 { for device in devices { try await sync(device) } }

            let reference = try await entries(on: devices[0]).map { "\($0.title)|\($0.document.text)" }.sorted()
            for device in devices.dropFirst() {
                let other = try await entries(on: device).map { "\($0.title)|\($0.document.text)" }.sorted()
                XCTAssertEqual(other, reference, "order \(order): every device holds the same entries")
            }
            let last = written[try XCTUnwrap(order.last)]
            XCTAssertEqual(
                Set(reference.map { $0.split(separator: "|").last.map(String.init) ?? "" }), Set(written),
                "order \(order): every text exists")
            XCTAssertEqual(reference.count, 3, "order \(order): once each")
            let record = try await stored(devices[0].store, page.id)
            XCTAssertEqual(record.document.text, last, "order \(order): the version that reached the server last")
            let again = try await devices[0].store.pending()
            XCTAssertTrue(again.isEmpty, "order \(order): nothing more to send after two more rounds")
            for device in devices {
                let rows = try await device.store.conflicts()
                XCTAssertTrue(rows.isEmpty)
            }
        }
    }

    // MARK: Co-editing cannot storm

    func testTwoDevicesTypingInOneEntryKeepAtMostOneCopyEachAndEveryTextSomewhere() async throws {
        let first = try await device("first")
        let second = try await device("second")
        let page = try await start([first, second])
        var written = Set<String>()
        for round in 1...20 {
            try await write("first \(round)", on: first, record: page.id)
            written.insert("first \(round)")
            try await sync(first)
            try await write("second \(round)", on: second, record: page.id)
            written.insert("second \(round)")
            try await sync(second)
        }
        for _ in 0..<3 {
            try await sync(first)
            try await sync(second)
        }
        for device in [first, second] {
            let all = try await entries(on: device)
            XCTAssertLessThanOrEqual(all.count - 1, 2, "One copy per other device, not one per exchange")
        }
        let held = try await texts(on: first).union(texts(on: second))
        XCTAssertTrue(written.isSubset(of: held), "Every text written is a record, a copy or in Version History")
        let theirs = try await entries(on: first).map(\.document.text).sorted()
        let ours = try await entries(on: second).map(\.document.text).sorted()
        XCTAssertEqual(theirs, ours)
    }

    /// Two devices meet the same other version while one of them replaces an earlier copy: that content then exists
    /// under two identities, once each. Never more, and never a lost text.
    func testTwoDevicesMeetingOneVersionWhileOneReplacesACopyLeaveExactlyOneIdenticalExtra() async throws {
        let holder = try await openStore("holder")
        let fresh = try await openStore("fresh")
        let home = journal("Home")
        let page = entry("Page", text: "t", journal: home.id)
        let other = UUID()
        for store in [holder, fresh] {
            try await settle(home, in: store)
            try await settle(page, in: store)
        }
        func diverge(_ store: JournalStore, revision: Int64, _ theirs: String, mine: String) async throws {
            let current = try await stored(store, page.id)
            var typed = current
            typed.document = .plain(mine)
            try await store.save(typed)
            var version = page
            version.document = .plain(theirs)
            try await deliver(version, revision: revision, to: store, device: other)
            _ = try await settleAfterPause(store)
        }
        try await diverge(holder, revision: 2, "theirs 1", mine: "holder 1")
        // The holder sent its copy and the record; the other device wrote a second version.
        for change in try await holder.pending() {
            let receipt = RemoteChange(
                cursor: 50, recordId: change.recordID, revision: change.baseRevision + 1, kind: change.kind,
                payload: change.payload, deviceId: UUID(), modifiedAt: Date())
            try await holder.acknowledge(change, receipt: receipt)
        }
        try await diverge(holder, revision: 4, "theirs 2", mine: "holder 2")
        try await diverge(fresh, revision: 4, "theirs 2", mine: "fresh 1")

        let replaced = try await holder.items().filter { $0.title.hasSuffix("(other version)") }
        XCTAssertEqual(replaced.map(\.document.text), ["theirs 2"], "The holder's copy took the later version")
        let derived = try await fresh.items().filter { $0.title.hasSuffix("(other version)") }
        XCTAssertEqual(derived.map(\.document.text), ["theirs 2"])
        XCTAssertNotEqual(replaced.first?.id, derived.first?.id, "…under the identity it was first made with")
        // They meet: the copy the other device made arrives at the holder as a new record.
        let arriving = try XCTUnwrap(derived.first)
        try await deliver(arriving, revision: 1, to: holder, device: UUID())
        let all = try await holder.items().filter { $0.title.hasSuffix("(other version)") }
        XCTAssertEqual(all.map(\.document.text), ["theirs 2", "theirs 2"], "Exactly one identical extra, lossless")
    }

    // MARK: Version 1.0 devices

    /// A 1.0 device pushes and reads as it always did and keeps what conflicts for the person to review. Its person
    /// resolves with Keep Both: a random identity and the title as it was.
    private func syncAsVersion10(_ store: JournalStore, id: UUID) async throws {
        for pending in try await store.pending() {
            switch try await server.push(pending, from: id, shortReceipt: false) {
            case .accepted(let receipt): try await store.acknowledge(pending, receipt: receipt)
            case .conflict(let current): try await store.recordConflict(current)
            default: XCTFail("The base revision is ahead of the server")
            }
        }
        let cursor = try await store.cursor()
        let page = try await server.changes(after: cursor, limit: 1_000, applied: nil)
        try await store.apply(page.changes, cursor: page.cursor)
    }

    func testAVersion10DeviceThatKeepsBothAndAVersion11DeviceThatSettlesConvergeWithoutLoss() async throws {
        let modern = try await device("modern")
        let legacy = try await openStore("legacy")
        let legacyID = UUID()
        let page = try await start([modern])
        try await syncAsVersion10(legacy, id: legacyID)

        // Each edits offline; the modern device reaches the server first.
        try await write("written on 1.1", on: modern, record: page.id)
        let legacyItem = try await stored(legacy, page.id)
        var typed = legacyItem
        typed.document = .plain("written on 1.0")
        try await legacy.save(typed)
        try await sync(modern)
        try await syncAsVersion10(legacy, id: legacyID)
        let reviews = try await legacy.conflicts()
        XCTAssertEqual(reviews.count, 1, "1.0 shows its own review, with the 1.1 version as the other device's")
        try await legacy.resolve(try XCTUnwrap(reviews.first), choice: .keepBoth)
        try await syncAsVersion10(legacy, id: legacyID)
        try await sync(modern)
        try await syncAsVersion10(legacy, id: legacyID)

        for store in [modern.store, legacy] {
            let texts = try await store.items().filter { $0.kind == "entry" }.map(\.document.text).sorted()
            XCTAssertEqual(texts, ["written on 1.0", "written on 1.1"])
            let rows = try await store.conflicts()
            XCTAssertTrue(rows.isEmpty)
        }
    }

    func testAVersion11CopyReachesAVersion10DeviceAsAnOrdinaryNewEntry()
        async throws
    {
        let modern = try await device("modern-first")
        let legacy = try await openStore("legacy-second")
        let legacyID = UUID()
        let page = try await start([modern])
        try await syncAsVersion10(legacy, id: legacyID)

        // The 1.0 device reaches the server first; the 1.1 device settles on top of it and sends a copy.
        let legacyItem = try await stored(legacy, page.id)
        var typed = legacyItem
        typed.document = .plain("written on 1.0")
        try await legacy.save(typed)
        try await write("written on 1.1", on: modern, record: page.id)
        try await syncAsVersion10(legacy, id: legacyID)
        try await sync(modern)
        try await syncAsVersion10(legacy, id: legacyID)
        let after = try await legacy.items().filter { $0.kind == "entry" }
        let record = try XCTUnwrap(after.first { $0.id == page.id })
        XCTAssertEqual(record.document.text, "written on 1.1", "1.0 receives an ordinary revision…")
        let copy = try XCTUnwrap(after.first { $0.id != page.id })
        XCTAssertEqual(copy.document.text, "written on 1.0", "…and the copy as an ordinary new entry")
        XCTAssertEqual(copy.title, "Page (other version)")
        let rows = try await legacy.conflicts()
        XCTAssertTrue(rows.isEmpty, "Nothing to review")
    }

    // MARK: The pass over rows an earlier version left

    func testEntryRowsAVersionBeforeStepTwoLeftAreSettledWhenTheLibraryNextOpens() async throws {
        let store = try await openStore("upgrade", runPass: false)
        let home = journal("Home")
        let page = entry("Page", text: "t", journal: home.id)
        try await settle(home, in: store)
        try await settle(page, in: store)
        let current = try await stored(store, page.id)
        var typed = current
        typed.document = .plain("mine")
        try await store.save(typed)
        var theirs = page
        theirs.document = .plain("theirs")
        try await deliver(theirs, revision: 2, to: store, device: UUID())
        // This library finished the pass for journals and permanent deletions in an earlier build.
        let notes = await store.keptNotesStore
        try await store.db.write { db in
            var state = try notes.state(db)
            state.passStep = 1
            try notes.save(db, state)
        }
        let opening = try await store.resolveConflicts(at: .opening(serverConfigured: true))
        XCTAssertEqual(opening.resolved.count, 1, "A row the person left for review is answered by keeping both")
        let texts = try await store.items().filter { $0.kind == "entry" }.map(\.document.text).sorted()
        XCTAssertEqual(texts, ["mine", "theirs"])
        let again = try await store.resolveConflicts(at: .opening(serverConfigured: true))
        XCTAssertTrue(again.resolved.isEmpty, "Once")
    }
}
