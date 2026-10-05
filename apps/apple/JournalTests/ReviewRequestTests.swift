import XCTest

@testable import Journal

/// The rating request (docs/design/about-and-ratings-2026-10-05.md §3): asking too early, during problems, twice in
/// one version or while the person is still writing would cost ratings and goodwill, and can't be undone.
@MainActor final class ReviewRequestTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    func testRulesAskOnlyAfterAWeekOfUseOnFourDaysAndOncePerVersion() {
        let eligible = ReviewUsage(firstUse: now - 8 * day, writingDays: 4)
        var cases: [(String, ReviewUsage?, Bool, Bool)] = [
            ("eligible", eligible, false, true),
            ("no usage recorded", nil, false, false),
            ("a problem this session", eligible, true, false),
        ]
        var young = eligible
        young.firstUse = now - 7 * day + 60
        cases.append(("first use less than 7 days ago", young, false, false))
        young.firstUse = now - 7 * day
        cases.append(("first use exactly 7 days ago", young, false, true))
        var fewDays = eligible
        fewDays.writingDays = 3
        cases.append(("writing on only 3 days", fewDays, false, false))
        var askedThisVersion = eligible
        askedThisVersion.lastRequestVersion = "1.0"
        askedThisVersion.lastRequest = now - 200 * day
        cases.append(("asked in this version", askedThisVersion, false, false))
        var askedRecently = eligible
        askedRecently.lastRequestVersion = "0.9"
        askedRecently.lastRequest = now - 119 * day
        cases.append(("asked 119 days ago", askedRecently, false, false))
        askedRecently.lastRequest = now - 120 * day
        cases.append(("asked 120 days ago in another version", askedRecently, false, true))
        for (name, usage, problem, expected) in cases {
            XCTAssertEqual(
                ReviewRequestRules.allow(usage, version: "1.0", problemThisSession: problem, now: now), expected, name)
        }
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

        requests.noteLaunch()
        requests.noteSaved(entry: entry)
        XCTAssertEqual(store.usage?.writingDays, 0, "a save the person didn't type, such as a sync, doesn't count")
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
        XCTAssertEqual(
            store.usage?.firstUse, calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9)))
    }

    func testAsksOnceAfterLeavingAnEditedEntryUnlessThePauseIsInterrupted() async {
        let store = ReviewUsageStore.memory(ReviewUsage(firstUse: now - 30 * day, writingDays: 10))
        var environment = ReviewRequests.Environment()
        environment.now = { self.now }
        environment.version = "1.0"
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
        XCTAssertNil(store.usage?.lastRequestVersion, "nothing is recorded when nothing was asked")

        clear = true
        requests.noteEdit(entry: entry)
        requests.selectionChanged(leaving: entry)
        await requests.pending?.value
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(store.usage?.lastRequestVersion, "1.0")

        requests.noteEdit(entry: next)
        requests.selectionChanged(leaving: next)
        await requests.pending?.value
        XCTAssertEqual(asked, 1, "once per version")
    }

    func testTestFlightProblemsAndErrorsNeverAsk() async {
        for installedFromAppStore in [false, true] {
            let store = ReviewUsageStore.memory(ReviewUsage(firstUse: now - 30 * day, writingDays: 10))
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
