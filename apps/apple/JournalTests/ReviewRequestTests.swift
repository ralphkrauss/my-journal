import JournalCore
import XCTest

@testable import Journal

/// The rating request (docs/design/1-1-settings-messages-editor.md §3): asking too early, during problems, too soon
/// after the last time or while the person is still writing would cost ratings and goodwill, and can't be undone.
@MainActor final class ReviewRequestTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    func testRulesAskOnlyAfterFiveWritingDaysAndNotWithin120DaysOfTheLastRequest() {
        let eligible = ReviewUsage(writingDays: 5)
        var cases: [(String, ReviewUsage?, Bool, Bool)] = [
            ("eligible", eligible, false, true),
            ("no usage recorded", nil, false, false),
            ("a problem this session", eligible, true, false),
        ]
        var fewDays = eligible
        fewDays.writingDays = 4
        cases.append(("writing on only 4 days", fewDays, false, false))
        var askedRecently = eligible
        askedRecently.lastRequest = now - 119 * day
        cases.append(("asked 119 days ago", askedRecently, false, false))
        askedRecently.lastRequest = now - 120 * day
        cases.append(("asked 120 days ago", askedRecently, false, true))
        for (name, usage, problem, expected) in cases {
            XCTAssertEqual(
                ReviewRequestRules.allow(usage, problemThisSession: problem, now: now), expected, name)
        }
    }

    /// Someone who used 1.0 keeps their count and is not asked again for 120 days after the last request, although
    /// the record also holds the first use and version that 1.1 no longer reads.
    func testARecordWrittenByVersion1StillCountsDaysAndSpacesRequests() throws {
        let lastRequest = now - 30 * day
        let stored = """
            {"firstUse": 780000000, "writingDays": 9, "lastWritingDay": "2026-10-5",
             "lastRequestVersion": "1.0", "lastRequest": \(lastRequest.timeIntervalSinceReferenceDate)}
            """
        let usage = try JSONDecoder().decode(ReviewUsage.self, from: Data(stored.utf8))
        XCTAssertEqual(usage.writingDays, 9)
        XCTAssertEqual(usage.lastRequest, lastRequest)
        XCTAssertFalse(ReviewRequestRules.allow(usage, problemThisSession: false, now: now), "asked 30 days ago")
        XCTAssertTrue(ReviewRequestRules.allow(usage, problemThisSession: false, now: now + 91 * day))
    }

    /// A problem Sync Status shows blocks the moment while it lasts; once it is gone nothing is remembered.
    func testASyncProblemBlocksTheMomentOnlyWhileSyncStatusShowsIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(directory: root)
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            try? Keychain.remove(model.keyAccount)
            try? FileManager.default.removeItem(at: root)
        }
        await model.start()
        model.confirmRecovery()
        model.applicationActive = true
        XCTAssertTrue(model.reviewStateIsClear)
        model.connection = SyncConnection(address: "https://journal.example.net", deviceID: UUID(), token: "token")
        model.recordSyncHealth(.accessRemoved, failure: nil)
        XCTAssertFalse(model.reviewStateIsClear, "the person must act on a sync problem")
        model.recordSyncHealth(.offline, failure: nil)
        XCTAssertTrue(model.reviewStateIsClear, "offline is quiet")
        model.recordSyncHealth(.accessRemoved, failure: nil)
        model.recordSyncHealth(nil, failure: nil)
        XCTAssertTrue(model.reviewStateIsClear, "a sync problem that has gone doesn't block the moment")
    }

    func testOnlyThePersonsSavedEditsCountAndEachLocalDayOnce() throws {
        let brussels = try XCTUnwrap(TimeZone(identifier: "Europe/Brussels"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = brussels
        var clock = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9)))
        var environment = ReviewRequests.Environment()
        environment.calendar = calendar
        environment.now = { clock }
        let store = ReviewUsageStore.memory()
        let requests = ReviewRequests(store: store, environment: environment)
        let entry = UUID()

        requests.noteSaved(entry: entry)
        XCTAssertNil(store.usage, "a save the person didn't type, such as a sync, doesn't start a record")
        requests.noteEdit(entry: entry)
        requests.noteSaved(entry: entry)
        clock += 14 * 60 * 60
        requests.noteSaved(entry: entry)
        XCTAssertEqual(store.usage?.writingDays, 1, "two saves on 5 October, 9:00 and 23:00")
        // 1:00 on 6 October in Brussels is still 5 October in UTC: days are the person's own calendar days.
        clock = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 1)))
        requests.noteSaved(entry: entry)
        clock = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 0, minute: 30)))
        requests.noteSaved(entry: entry)
        XCTAssertEqual(store.usage?.writingDays, 3)
    }

    func testAsksOnceAfterLeavingAnEditedEntryUnlessThePauseIsInterrupted() async {
        let store = ReviewUsageStore.memory(ReviewUsage(writingDays: 10))
        var environment = ReviewRequests.Environment()
        environment.now = { self.now }
        environment.pause = { await Task.yield() }
        environment.installedFromAppStore = { true }
        let requests = ReviewRequests(store: store, environment: environment)
        var clear = true
        var asked = 0
        requests.momentIsClear = { clear }
        requests.present = { asked += 1 }
        let (entry, next) = (UUID(), UUID())

        requests.selectionChanged(leaving: entry)
        XCTAssertNil(requests.pending, "the entry wasn't edited")

        requests.noteEdit(entry: entry)
        requests.selectionChanged(leaving: entry)
        var paused = requests.pending
        requests.selectionChanged(leaving: next)
        await paused?.value
        XCTAssertEqual(asked, 0, "the selection changed again during the pause, as when browsing with the arrow keys")

        requests.noteEdit(entry: entry)
        requests.selectionChanged(leaving: entry)
        paused = requests.pending
        requests.noteEdit(entry: next)
        await paused?.value
        XCTAssertEqual(asked, 0, "writing started again during the pause")

        requests.noteEdit(entry: entry)
        requests.noteLocked()
        requests.selectionChanged(leaving: entry)
        XCTAssertNil(requests.pending, "locking ends the session's writing, so unlocking is never the moment")

        requests.noteEdit(entry: entry)
        requests.selectionChanged(leaving: entry)
        clear = false
        await requests.pending?.value
        XCTAssertEqual(asked, 0, "a sheet, menu or focused text field at the end of the pause")
        XCTAssertNil(store.usage?.lastRequest, "nothing is recorded when nothing was asked")

        clear = true
        requests.noteEdit(entry: entry)
        requests.selectionChanged(leaving: entry)
        await requests.pending?.value
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(store.usage?.lastRequest, now)

        requests.noteEdit(entry: next)
        requests.selectionChanged(leaving: next)
        await requests.pending?.value
        XCTAssertEqual(asked, 1, "not again within 120 days")
    }

    func testTestFlightProblemsAndErrorsNeverAsk() async {
        for installedFromAppStore in [false, true] {
            let store = ReviewUsageStore.memory(ReviewUsage(writingDays: 10))
            var environment = ReviewRequests.Environment()
            environment.pause = {}
            environment.installedFromAppStore = { installedFromAppStore }
            let requests = ReviewRequests(store: store, environment: environment)
            var asked = 0
            requests.momentIsClear = { true }
            requests.present = { asked += 1 }
            let entry = UUID()
            if installedFromAppStore { requests.noteProblem() }
            requests.noteEdit(entry: entry)
            requests.selectionChanged(leaving: entry)
            await requests.pending?.value
            XCTAssertEqual(asked, 0, installedFromAppStore ? "a problem this session" : "TestFlight or development")
            XCTAssertNil(store.usage?.lastRequest)
        }
    }
}
