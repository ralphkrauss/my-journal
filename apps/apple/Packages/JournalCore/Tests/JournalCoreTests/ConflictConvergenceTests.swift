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

    /// Every title and text of the entries a device holds, to compare devices.
    private func catalog(of device: Device) async throws -> [String] {
        try await entries(on: device).map { "\($0.title)|\($0.document.text)" }.sorted()
    }
    private func quiet(_ devices: [Device], rounds: Int = 3) async throws {
        for _ in 0..<rounds { for device in devices { try await sync(device) } }
    }

    /// A copy that someone edits on every device is itself a conflict: the copy of a copy reads twice in its title and
    /// is bounded like any other. Three rounds, three devices, three orders. Each round's texts are checked before the
    /// next round types over them, because typing over one's own text is an ordinary edit.
    func testACopyEditedOnThreeDevicesThroughThreeRoundsKeepsEveryTextAndConverges() async throws {
        let devices = [try await device("a"), try await device("b"), try await device("c")]
        let page = try await start(devices)
        func writeRound(_ round: Int, to record: UUID, order: [Int]) async throws {
            var written = Set<String>()
            for (position, device) in devices.enumerated() {
                let text = "round \(round) \(position)"
                try await write(text, on: device, record: record)
                written.insert(text)
            }
            for position in order { try await sync(devices[position]) }
            try await quiet(devices)
            for device in devices {
                let held = try await texts(on: device)
                XCTAssertTrue(written.isSubset(of: held), "Round \(round): missing \(written.subtracting(held))")
            }
        }
        try await writeRound(1, to: page.id, order: [0, 1, 2])
        let firstCopy = try await entries(on: devices[0]).first { $0.id != page.id }
        let copyID = try XCTUnwrap(firstCopy).id
        try await writeRound(2, to: copyID, order: [0, 1, 2])
        try await writeRound(3, to: copyID, order: [2, 0, 1])
        try await writeRound(4, to: copyID, order: [1, 2, 0])

        let reference = try await catalog(of: devices[0])
        for device in devices.dropFirst() {
            let other = try await catalog(of: device)
            XCTAssertEqual(other, reference, "Every device holds the same entries")
        }
        XCTAssertLessThanOrEqual(reference.count, 3 + 3 * 2, "Two other versions of the copy per round at most")
        XCTAssertTrue(reference.contains { $0.contains("(other version) (other version)|") }, "A copy of a copy")
        for device in devices {
            let queued = try await device.store.pending()
            XCTAssertTrue(queued.isEmpty, "Nothing is left to send")
            let rows = try await device.store.conflicts()
            XCTAssertTrue(rows.isEmpty)
        }
    }

    /// X replaces a copy it has not sent yet while Z edits that copy: X's push is refused, both are kept, and the
    /// devices settle without making copies forever.
    func testACopyAnotherDeviceEditedBeforeThePushOfItsReplacementKeepsBothAndDoesNotLoop() async throws {
        let x = try await device("x")
        let y = try await device("y")
        let z = try await device("z")
        let page = try await start([x, y, z])
        try await write("x 1", on: x, record: page.id)
        try await write("y 1", on: y, record: page.id)
        try await sync(y)
        try await sync(x)
        try await sync(z)
        let made = try await entries(on: x).first { $0.id != page.id }
        let copy = try XCTUnwrap(made)
        XCTAssertEqual(copy.document.text, "y 1")

        // Z edits the copy, and Y writes again. X holds its own conflict, not yet settled.
        try await write("z edit of the copy", on: z, record: copy.id)
        let zChange = try await z.store.pending().first { $0.recordID == copy.id }
        let editedByZ = try XCTUnwrap(zChange)
        try await write("y 2", on: y, record: page.id)
        try await sync(y)
        try await write("x 2", on: x, record: page.id)
        time.withLock { $0 = $0.addingTimeInterval(3) }
        _ = try await x.engine.synchronize(SyncEngine.Request(holdingConflicts: [page.id]))
        let rows = try await x.store.conflicts()
        XCTAssertEqual(rows.map(\.id), [page.id], "The record waits")

        // Z's edit reaches the server just before X sends its replacement of the copy.
        let zDevice = z.id
        let sentByZ = server
        await server.whileSendingNext { _ = try? await sentByZ.push(editedByZ, from: zDevice, shortReceipt: false) }
        try await sync(x)
        let copyPushes = await server.pushes.filter { $0.recordID == copy.id && $0.baseRevision == 1 }
        XCTAssertEqual(copyPushes.count, 2, "Z's edit and X's replacement were both sent on the same revision")
        try await quiet([x, y, z], rounds: 4)

        let reference = try await catalog(of: x)
        for device in [y, z] {
            let other = try await catalog(of: device)
            XCTAssertEqual(other, reference, "Every device holds the same entries")
        }
        let held = try await texts(on: x)
        for text in ["x 2", "y 2", "z edit of the copy"] {
            XCTAssertTrue(held.contains(text), "\(text) is kept")
        }
        let before = reference.count
        try await quiet([x, y, z], rounds: 3)
        let after = try await catalog(of: x)
        XCTAssertEqual(after.count, before, "No further copies: it does not loop")
        for device in [x, y, z] {
            let queued = try await device.store.pending()
            XCTAssertTrue(queued.isEmpty)
            let open = try await device.store.conflicts()
            XCTAssertTrue(open.isEmpty)
        }
    }

    // MARK: A conflict that can't be settled does not keep a synchronization from being settled

    func testAConflictThatKeepsFailingToSettleDoesNotKeepASynchronizationFromBeingSettled() async throws {
        let first = try await device("first")
        let second = try await device("second")
        let page = try await start([first, second])
        try await write("first", on: first, record: page.id)
        try await write("second", on: second, record: page.id)
        try await sync(first)
        // The copy can't be written on this device.
        try await second.store.db.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER fail_copy BEFORE INSERT ON records WHEN NEW.kind='entry'
                    BEGIN SELECT RAISE(ABORT, 'Injected failure'); END
                    """)
        }
        time.withLock { $0 = $0.addingTimeInterval(3) }
        let report = try await second.engine.synchronize()
        let rows = try await second.store.conflicts()
        XCTAssertEqual(rows.count, 1, "The row stays")
        XCTAssertTrue(report.settled, "…and counts as held, so the device may wait for changes")

        try await second.store.db.write { try $0.execute(sql: "DROP TRIGGER fail_copy") }
        let retry = try await second.engine.synchronize()
        let remaining = try await second.store.conflicts()
        XCTAssertTrue(remaining.isEmpty, "The next completed pull settles it")
        XCTAssertEqual(retry.resolvedConflicts.count, 1)
    }

    // MARK: Opening inside a synchronization

    func testTheOpeningPassOfASynchronizationLeavesARecordTheCallerHolds() async throws {
        let seeded = try await device("seeded")
        let page = try await start([seeded])
        // A library an earlier version left a conflict in: its pass has not run.
        let store = try await openStore("holding", runPass: false)
        let engine = SyncEngine(store: store, server: DeviceServer(server: server, device: UUID()))
        let reader = Device(store: store, engine: engine, id: UUID())
        try await sync(reader)
        try await write("mine", on: reader, record: page.id)
        // Another device's version, as the server holds it; this library has read it but not yet settled it.
        try await write("theirs", on: seeded, record: page.id)
        try await sync(seeded)
        let log = await server.state.log
        try await store.recordConflict(try XCTUnwrap(log.last))
        try await store.forgetThatThePassRan(throughStep: 0)

        time.withLock { $0 = $0.addingTimeInterval(3) }
        _ = try await engine.synchronize(SyncEngine.Request(holdingConflicts: [page.id]))
        let rows = try await store.conflicts()
        XCTAssertEqual(rows.map(\.id), [page.id], "The open entry's conflict is not settled under the person")
        _ = try await engine.synchronize()
        let settled = try await store.conflicts()
        XCTAssertTrue(settled.isEmpty, "…and is settled by the next one")
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
