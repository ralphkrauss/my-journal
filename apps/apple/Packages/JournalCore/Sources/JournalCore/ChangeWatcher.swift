import Foundation

/// Decides when a device waits for the server's changes instead of polling, and what each answer leads to
/// (docs/design/sync-protocol-efficiency.md §4.6). A pure state machine: the app reports events and carries out the
/// actions; it decides nothing itself. While the watcher doesn't own the schedule (`ownsSchedule`), the app polls as
/// it always did.
public struct ChangeWatcher: Sendable {
    public typealias Instant = ContinuousClock.Instant

    /// How a synchronization ended, for `syncFinished`.
    public enum Outcome: Sendable, Equatable {
        /// It succeeded and left nothing to do but wait (`SyncReport.settled`).
        case settled
        /// It succeeded but left something to send, download or retry soon.
        case unsettled
        case failed
        /// It didn't run: locked, replacing the library or a save failure.
        case declined
    }
    public struct Finished: Sendable {
        public var outcome: Outcome
        public var startedAt: Instant
        public var finishedAt: Instant
        /// The store's quiet mark when the synchronization ended; nil when it didn't settle.
        public var mark: QuietMark?
        /// The position afterwards, to tell whether a synchronization after `changed` read anything.
        public var position: QuietPosition?
        /// The soonest an item waiting for a retry time may be sent, after `finishedAt`.
        public var earliestRetry: Duration?
        public init(
            outcome: Outcome, startedAt: Instant, finishedAt: Instant, mark: QuietMark? = nil,
            position: QuietPosition? = nil, earliestRetry: Duration? = nil
        ) {
            self.outcome = outcome
            self.startedAt = startedAt
            self.finishedAt = finishedAt
            self.mark = mark
            self.position = position
            self.earliestRetry = earliestRetry
        }
    }
    public enum Event: Sendable {
        case syncFinished(Finished)
        /// A wait the watcher asked for was sent from this position, at this time (for Last Synced).
        case waitSent(id: Int, position: QuietPosition, at: Date)
        /// A synchronization is starting, whoever started it: the floor counts from it.
        case syncStarted
        /// A wait ended, whatever ended it. `nil` answer: cancelled without the watcher asking.
        case waitEnded(id: Int, answer: WaitAnswer?)
        /// Whether the app may wait at all: unlocked, no save failure, not replacing the library, sync not stopped.
        case conditions(allowWaiting: Bool)
        /// The store is no longer quiet since the settled synchronization: another sync ran or something was written.
        /// With a wait ID, it applies only while that is still the current wait.
        case quietBroken(waitID: Int? = nil)
        case clientReplaced
        case loopStarted
        case networkPathChanged
        case sleep
        case wake
        case becameActive
        /// The loop's regular tick, for timers.
        case tick
    }
    public enum Action: Sendable, Equatable {
        /// Read the position for `mark` and wait from it; report `waitSent`, or `quietBroken` when it isn't quiet.
        case startWait(id: Int, mark: QuietMark)
        case cancelWait
        /// Run an ordinary synchronization, as the loop's own.
        case syncNow
        /// Last Synced: the time the confirmed wait was sent.
        case markSynced(at: Date)
        case publishAgentCopies
        /// Forget the status a synchronization may reuse, so the next one reads it.
        case forgetStatus
    }

    /// The longest a wait is asked to be held, and how much earlier than that a `false` proves nothing.
    public static let waitDuration = Duration.seconds(ServerClient.waitSeconds)
    static let confirmingMargin = Duration.seconds(2)
    /// A wait without any event this long after it was sent is treated as failed: the wait session's resource
    /// timeout plus a margin.
    static let waitDeadline = Duration.seconds(ServerClient.waitSeconds + 20)
    /// The least time between any two requests the watcher starts, waits and synchronizations together.
    public static let floor = Duration.seconds(3)
    /// An ordinary synchronization at least this often while waiting.
    static let safetyInterval = Duration.seconds(10 * 60)
    /// Strikes in a row that turn waiting off, and for how long.
    static let strikesBeforeFallback = 3
    static let fallbackPeriod = Duration.seconds(60 * 60)

    private struct Wait: Sendable {
        var id: Int
        var mark: QuietMark
        var startedAt: Instant
        var position: QuietPosition?
        /// When the request was sent; timing and the deadline count from it once known.
        var sentAt: Instant?
        var sentDate: Date?
        var since: Instant { sentAt ?? startedAt }
    }
    /// What the synchronization requested after an answer is judged by.
    private enum FollowUp: Sendable {
        case afterChanged(QuietPosition?)
        case afterFailure
    }
    private var mark: QuietMark?
    private var retryAt: Instant?
    private var allowWaiting = false
    private var wait: Wait?
    private var nextWaitID = 0
    private var lastRequestAt: Instant?
    private var lastWaitAt: Instant?
    private var lastSyncAt: Instant?
    private var syncDue = false
    private var syncRunning = false
    private var followUp: FollowUp?
    private var strikes = 0
    private var fallbackUntil: Instant?
    private var now: Instant
    /// When this watcher began: synchronizations that started before it (for a previous library or connection)
    /// are ignored.
    private let createdAt: Instant

    public init(now: Instant) {
        self.now = now
        createdAt = now
    }

    /// While true, the app doesn't poll: synchronizations run when the watcher asks.
    public var ownsSchedule: Bool { mark != nil && allowWaiting && !inFallback }
    /// A wait is running.
    public var waiting: Bool { wait != nil }
    /// The wait running, if any.
    public var waitID: Int? { wait?.id }
    /// The quiet mark of the settled synchronization the watcher waits from.
    public var quietMark: QuietMark? { mark }
    private var inFallback: Bool { fallbackUntil.map { now < $0 } ?? false }

    public mutating func handle(_ event: Event, at instant: Instant) -> [Action] {
        now = instant
        var actions: [Action] = []
        switch event {
        case .syncFinished(let finished): finish(finished)
        case .waitSent(let id, let position, let date):
            if wait?.id == id {
                wait?.position = position
                wait?.sentAt = now
                wait?.sentDate = date
            }
        case .syncStarted: lastRequestAt = now
        case .waitEnded(let id, let answer): actions += end(id: id, answer: answer)
        case .conditions(let allow):
            allowWaiting = allow
            if !allow { actions += cancel() }
        case .quietBroken(let waitID):
            // A wait that was replaced or cancelled meanwhile can't end the current one.
            guard waitID == nil || waitID == wait?.id else { break }
            mark = nil
            actions += cancel()
        case .clientReplaced, .networkPathChanged:
            if case .networkPathChanged = event {
                strikes = 0
                fallbackUntil = nil
            }
            actions += cancel()
            syncDue = true
        case .loopStarted:
            // The old loop's wait task ended with it and may never report.
            wait = nil
            syncRunning = false
            syncDue = true
        case .sleep: actions += cancel()
        case .wake, .becameActive:
            actions += cancel()
            syncDue = true
        case .tick: break
        }
        return actions + decide()
    }

    private mutating func finish(_ finished: Finished) {
        // Started for a previous library or connection.
        guard finished.startedAt >= createdAt else { return }
        syncRunning = false
        lastRequestAt = max(lastRequestAt ?? finished.startedAt, finished.startedAt)
        guard finished.outcome != .declined else { return }
        // Any synchronization does what a due one would.
        syncDue = false
        let judged = followUp
        followUp = nil
        guard finished.outcome != .failed else {
            // Today's backoff handles failures; they are never strikes.
            mark = nil
            return
        }
        lastSyncAt = finished.startedAt
        switch judged {
        case .afterChanged(let sent): sent == finished.position ? strike() : (strikes = 0)
        case .afterFailure: strike()
        case nil: break
        }
        mark = finished.outcome == .settled ? finished.mark : nil
        retryAt = finished.earliestRetry.map { finished.finishedAt + $0 }
    }

    private mutating func end(id: Int, answer: WaitAnswer?) -> [Action] {
        guard let ended = wait, ended.id == id else { return [] }
        wait = nil
        switch answer {
        case .unchanged(let early):
            let confirming = !early && now - ended.since >= Self.waitDuration - Self.confirmingMargin
            guard confirming, let sent = ended.sentDate else {
                strike()
                return []
            }
            strikes = 0
            return [.markSynced(at: sent), .publishAgentCopies]
        case .changed:
            followUp = .afterChanged(ended.position)
            syncDue = true
            return []
        case .failed:
            followUp = .afterFailure
            syncDue = true
            return [.forgetStatus]
        case nil:
            syncDue = true
            return []
        }
    }

    private mutating func cancel() -> [Action] {
        guard wait != nil else { return [] }
        wait = nil
        return [.cancelWait]
    }

    private mutating func strike() {
        strikes += 1
        guard strikes >= Self.strikesBeforeFallback else { return }
        strikes = 0
        fallbackUntil = now + Self.fallbackPeriod
    }

    private var floorPassed: Bool { lastRequestAt.map { now - $0 >= Self.floor } ?? true }
    /// Whether the loop may start a poll now: at least `floor` after the last wait, also when waiting just turned
    /// off. Polls after a synchronization keep the loop's own pace, so the network returning still syncs at once.
    public func allowsRequest(at instant: Instant) -> Bool { lastWaitAt.map { instant - $0 >= Self.floor } ?? true }

    private mutating func decide() -> [Action] {
        if let current = wait {
            if now - current.since >= Self.waitDeadline {
                wait = nil
                followUp = .afterFailure
                syncDue = true
                return [.cancelWait, .forgetStatus] + decide()
            }
            // An item waiting for a retry time is sent then: the wait ends for it.
            guard let retryAt, now >= retryAt else { return [] }
            wait = nil
            return [.cancelWait] + decide()
        }
        guard ownsSchedule, !syncRunning, let mark else { return [] }
        let safetyDue = lastSyncAt.map { now - $0 >= Self.safetyInterval } ?? true
        let retryDue = retryAt.map { now >= $0 } ?? false
        guard floorPassed else { return [] }
        lastRequestAt = now
        if syncDue || safetyDue || retryDue {
            syncDue = false
            retryAt = nil
            syncRunning = true
            return [.syncNow]
        }
        nextWaitID += 1
        lastWaitAt = now
        wait = Wait(id: nextWaitID, mark: mark, startedAt: now)
        return [.startWait(id: nextWaitID, mark: mark)]
    }
}
