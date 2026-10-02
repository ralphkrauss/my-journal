import XCTest

@testable import JournalCore

/// When a device waits for changes instead of polling, and what each answer leads to
/// (docs/design/sync-protocol-efficiency.md §4.6).
final class ChangeWatcherTests: XCTestCase {
    private let start = ContinuousClock.now
    private let mark = QuietMark(store: UUID(), generation: 2, writes: 5)
    private let position = QuietPosition(cursor: 7, applied: nil, serverID: "server")
    private let sentDate = Date(timeIntervalSince1970: 2_000_000_000)
    private var watcher: ChangeWatcher!
    private var time: Duration = .zero

    override func setUp() {
        watcher = ChangeWatcher(now: start)
        time = .zero
    }
    private var now: ContinuousClock.Instant { start + time }
    @discardableResult private func send(_ event: ChangeWatcher.Event, after seconds: Double = 0) -> [ChangeWatcher
        .Action]
    {
        time += .milliseconds(Int(seconds * 1000))
        return watcher.handle(event, at: now)
    }
    private func finished(
        _ outcome: ChangeWatcher.Outcome = .settled, position: QuietPosition? = nil, retry: Duration? = nil,
        supported: Bool = true
    ) -> ChangeWatcher.Event {
        .syncFinished(
            .init(
                outcome: outcome, startedAt: now, finishedAt: now, mark: outcome == .settled ? mark : nil,
                position: position ?? self.position, earliestRetry: retry, waitingSupported: supported))
    }
    /// A settled synchronization, then the floor: the watcher starts a wait. Returns its ID.
    @discardableResult private func settleAndWait() -> Int {
        send(.conditions(allowWaiting: true))
        send(finished())
        let actions = send(.tick, after: 3)
        guard case .startWait(let id, let waitMark) = actions.first else {
            XCTFail("No wait: \(actions)")
            return -1
        }
        XCTAssertEqual(waitMark, mark)
        send(.waitSent(id: id, position: position, at: sentDate))
        return id
    }

    func testWaitsOnlyAfterASettledSyncWithTheCapabilityWhileAllowed() {
        send(.conditions(allowWaiting: true))
        send(finished(.unsettled))
        XCTAssertEqual(send(.tick, after: 3), [])
        XCTAssertFalse(watcher.ownsSchedule, "Something left to do: the app polls")
        send(finished(supported: false))
        XCTAssertEqual(send(.tick, after: 3), [])
        send(.conditions(allowWaiting: false))
        send(finished())
        XCTAssertEqual(send(.tick, after: 3), [], "Locked, stopped or a save failure")
        guard case .startWait = send(.conditions(allowWaiting: true), after: 3).first else {
            return XCTFail("Settled and allowed")
        }
    }

    func testAConfirmingAnswerMarksLastSyncedAndWaitsAgain() {
        let id = settleAndWait()
        XCTAssertEqual(
            send(.waitEnded(id: id, answer: .unchanged(early: false)), after: 20).prefix(2),
            [.markSynced(at: sentDate), .publishAgentCopies])
        XCTAssertTrue(watcher.waiting, "The next wait starts at once: the last one started 20 s ago")
    }

    func testAnEarlyOrTooFastFalseProvesNothingAndCountsAsAStrike() {
        var id = settleAndWait()
        let afterEarly = send(.waitEnded(id: id, answer: .unchanged(early: true)), after: 20)
        XCTAssertFalse(afterEarly.contains(.markSynced(at: sentDate)))
        id = waitIn(afterEarly) ?? waitAfterFloor()
        XCTAssertEqual(send(.waitEnded(id: id, answer: .unchanged(early: false)), after: 1), [], "Too fast")
        id = waitAfterFloor()
        send(.waitEnded(id: id, answer: .unchanged(early: false)), after: 1)
        XCTAssertFalse(watcher.ownsSchedule, "Three strikes: polling for an hour")
        XCTAssertFalse(watcher.allowsRequest(at: now), "The first poll keeps the floor after the last wait")
        XCTAssertTrue(watcher.allowsRequest(at: now + .seconds(2)))
        send(.tick, after: 3600)
        XCTAssertTrue(watcher.ownsSchedule, "Waiting again after the hour")
    }
    private func waitIn(_ actions: [ChangeWatcher.Action]) -> Int? {
        guard case .startWait(let id, _) = actions.last else { return nil }
        send(.waitSent(id: id, position: position, at: sentDate))
        return id
    }
    private func waitAfterFloor() -> Int {
        guard case .startWait(let id, _) = send(.tick, after: 3).first else {
            XCTFail("No wait")
            return -1
        }
        send(.waitSent(id: id, position: position, at: sentDate))
        return id
    }

    func testRequestsKeepTheFloorAgainstAServerThatAnswersAtOnce() {
        var id = settleAndWait()
        var requests: [Duration] = []
        for _ in 0..<20 {
            send(.waitEnded(id: id, answer: .changed), after: 0.1)
            for _ in 0..<40 {
                let actions = send(.tick, after: 0.1)
                if actions.contains(.syncNow) {
                    requests.append(time)
                    send(finished(position: QuietPosition(cursor: position.cursor + Int64(requests.count))))
                }
                if case .startWait(let next, _) = actions.first {
                    requests.append(time)
                    id = next
                    send(.waitSent(id: next, position: position, at: sentDate))
                }
            }
        }
        let gaps = zip(requests.dropFirst(), requests).map { $0 - $1 }
        XCTAssertFalse(gaps.isEmpty)
        XCTAssertTrue(gaps.allSatisfy { $0 >= .seconds(3) }, "\(gaps)")
    }

    func testATrueWhoseSyncReadNothingIsAStrikeAndOneThatReadSomethingIsNot() {
        for _ in 0..<5 {
            let id = settleAndWait()
            send(.waitEnded(id: id, answer: .changed), after: 1)
            XCTAssertEqual(send(.tick, after: 3), [.syncNow])
            send(finished(position: QuietPosition(cursor: 8, applied: nil, serverID: "server")))
        }
        XCTAssertTrue(watcher.ownsSchedule, "Progress every time")
        for _ in 0..<3 {
            let id = waitAfterFloorOrNil() ?? settleAndWait()
            send(.waitEnded(id: id, answer: .changed), after: 1)
            send(.tick, after: 3)
            send(finished())
        }
        XCTAssertFalse(watcher.ownsSchedule, "A server answering true with nothing to read")
    }
    private func waitAfterFloorOrNil() -> Int? {
        guard case .startWait(let id, _) = send(.tick, after: 3).first else { return nil }
        send(.waitSent(id: id, position: position, at: sentDate))
        return id
    }

    func testAFailedWaitIsAStrikeOnlyWhenTheFollowingSyncSucceeds() {
        for _ in 0..<5 {
            let id = settleAndWait()
            XCTAssertEqual(send(.waitEnded(id: id, answer: .failed), after: 1), [.forgetStatus])
            XCTAssertEqual(send(.tick, after: 3), [.syncNow])
            send(finished(.failed))
        }
        XCTAssertFalse(watcher.ownsSchedule, "Failed syncs end the verdict")
        send(finished())
        XCTAssertTrue(watcher.ownsSchedule, "...and none of them was a strike")
    }

    func testAWaitWithNoAnswerIsTreatedAsFailedAtItsDeadline() {
        settleAndWait()
        XCTAssertEqual(send(.tick, after: 39), [])
        XCTAssertEqual(send(.tick, after: 2), [.cancelWait, .forgetStatus, .syncNow])
    }

    func testAnUnrequestedCancellationSyncsWithoutAStrike() {
        let id = settleAndWait()
        send(.waitEnded(id: id, answer: nil), after: 1)
        XCTAssertEqual(send(.tick, after: 3), [.syncNow])
    }

    func testAnswersToAnOldWaitAreIgnored() {
        let id = settleAndWait()
        send(.quietBroken())
        XCTAssertEqual(send(.waitEnded(id: id, answer: .unchanged(early: false)), after: 20), [])
        XCTAssertFalse(watcher.ownsSchedule, "Not quiet: polling until a sync settles again")
        send(finished())
        XCTAssertTrue(watcher.ownsSchedule)
    }

    func testStoppingConditionsCancelAWaitInFlight() {
        settleAndWait()
        XCTAssertEqual(send(.conditions(allowWaiting: false)), [.cancelWait])
        send(.conditions(allowWaiting: true))
        settleAndWait()
        XCTAssertEqual(send(.sleep), [.cancelWait])
        XCTAssertEqual(send(.wake, after: 60), [.syncNow])
    }

    func testDeclinedSyncsAreNeitherFailuresNorStrikes() {
        let id = settleAndWait()
        send(.waitEnded(id: id, answer: .changed), after: 1)
        send(.tick, after: 3)
        send(finished(.declined))
        XCTAssertTrue(watcher.ownsSchedule)
    }

    func testTheSafetySyncRunsEveryTenMinutesAndRetryTimesAreKept() {
        send(.conditions(allowWaiting: true))
        send(finished(retry: .seconds(30)))
        let id = waitAfterFloor()
        send(.waitEnded(id: id, answer: .unchanged(early: false)), after: 20)
        XCTAssertEqual(send(.tick, after: 10), [.cancelWait, .syncNow], "The retry time ends the wait")
        send(finished())
        var synced = false
        guard var id = waitAfterFloorOrNil() else { return XCTFail("No wait after the sync") }
        for _ in 0..<40 {
            let actions = send(.waitEnded(id: id, answer: .unchanged(early: false)), after: 20)
            if actions.contains(.syncNow) {
                synced = true
                break
            }
            guard let next = waitIn(actions) else { return XCTFail("No next wait: \(actions)") }
            id = next
        }
        XCTAssertTrue(synced, "A full sync within about ten minutes and one wait")
    }

    func testLoopRestartsAndPathChangesDropAStaleWaitAndResetTheFallback() {
        var id = settleAndWait()
        XCTAssertEqual(send(.loopStarted), [])
        XCTAssertEqual(send(.tick, after: 3), [.syncNow], "The restarted loop syncs at once")
        send(finished())
        for _ in 0..<2 {
            id = waitAfterFloor()
            send(.waitEnded(id: id, answer: .unchanged(early: true)), after: 1)
        }
        id = waitAfterFloor()
        XCTAssertEqual(send(.networkPathChanged), [.cancelWait])
        send(.tick, after: 3)
        send(finished())
        id = waitAfterFloor()
        send(.waitEnded(id: id, answer: .unchanged(early: true)), after: 1)
        XCTAssertTrue(watcher.ownsSchedule, "The path change reset the strikes")
    }

    func testAnotherSynchronizationStartingKeepsTheFloor() {
        let id = settleAndWait()
        // An early answer: the next wait waits for the floor, so none is running.
        send(.waitEnded(id: id, answer: .unchanged(early: true)), after: 1)
        XCTAssertFalse(watcher.waiting)
        // Sync Now starts, then the network path changes while it runs.
        send(.syncStarted, after: 0.5)
        send(.networkPathChanged, after: 0.5)
        XCTAssertFalse(send(.tick, after: 1).contains(.syncNow), "Only 1.5 s after Sync Now started")
        XCTAssertTrue(send(.tick, after: 1.6).contains(.syncNow), "3 s after it")
    }

    func testAStaleWaitCannotEndTheCurrentOne() {
        let first = settleAndWait()
        send(.waitEnded(id: first, answer: .unchanged(early: false)), after: 20)
        let current = watcher.waitID
        XCTAssertNotNil(current)
        XCTAssertEqual(send(.quietBroken(waitID: first)), [], "The replaced wait's task reports late")
        XCTAssertEqual(watcher.waitID, current)
        XCTAssertTrue(watcher.ownsSchedule)
    }

    func testTheDeadlineCountsFromWhenTheWaitWasSent() {
        send(.conditions(allowWaiting: true))
        send(finished())
        guard case .startWait(let id, _) = send(.tick, after: 3).first else { return XCTFail("No wait") }
        // Reading the position took 10 seconds; the request was only sent then.
        send(.waitSent(id: id, position: position, at: sentDate), after: 10)
        XCTAssertEqual(send(.tick, after: 35), [], "Not yet 40 s since sending")
        XCTAssertEqual(send(.tick, after: 6), [.cancelWait, .forgetStatus, .syncNow])
    }

    func testSynchronizationsFromBeforeAResetAreIgnored() {
        let earlier = now
        time += .seconds(1)
        watcher = ChangeWatcher(now: now)
        send(.conditions(allowWaiting: true))
        send(
            .syncFinished(
                .init(
                    outcome: .settled, startedAt: earlier, finishedAt: now, mark: mark, position: position,
                    waitingSupported: true)))
        XCTAssertFalse(watcher.ownsSchedule, "A sync of the previous library or connection doesn't arm waiting")
    }
}
