import Combine
import Foundation
import JournalCore

/// Sends the decline of agent requests (Don't Allow) for as long as the app runs. The Agent Access pane's own
/// controller ends when Settings closes, and a decline the person has made must still be sent then, so its task is
/// owned here. Erase Journals and Settings and Stop Syncing cancel them; locking and closing Settings don't
/// (docs/design/1-1-settings-messages-editor.md §7.2).
@MainActor
final class AgentRequestDeclines: ObservableObject {
    enum Outcome: Equatable {
        /// The server recorded the decline, or no longer has the request (ended, replaced or answered elsewhere).
        case declined
        /// The server could not be reached or refused: the request is still there.
        case failed
    }
    struct Finish {
        let request: AgentRequest
        let outcome: Outcome
    }
    typealias Send = @Sendable (AgentRequest) async throws -> Void

    /// The requests being declined. The Requests list leaves them out meanwhile.
    @Published private(set) var inFlight: Set<UUID> = []
    /// How each decline ended, once, unless it was cancelled. Nothing listens once Settings has closed.
    let finished = PassthroughSubject<Finish, Never>()
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private let announce: (String) -> Void

    init(announce: @escaping (String) -> Void = { JournalAccessibility.announce($0) }) {
        self.announce = announce
    }

    /// Sends the decline in the background. A request already being declined is left alone.
    func decline(_ request: AgentRequest, using send: @escaping Send) {
        guard tasks[request.id] == nil else { return }
        inFlight.insert(request.id)
        tasks[request.id] = Task { [weak self] in
            var outcome: Outcome?
            do {
                try await send(request)
                outcome = .declined
            } catch {
                outcome = Self.outcome(of: error)
            }
            self?.finish(request, outcome: outcome)
        }
    }
    /// What a failed send means: a cancelled one shows nothing; every other failure, whatever the answer, is a failure.
    nonisolated static func outcome(of error: Error) -> Outcome? {
        if error is CancellationError { return nil }
        if let failure = error as? URLError, failure.code == .cancelled { return nil }
        return .failed
    }
    /// Stops every decline in flight, without a message: the connection they belong to is gone.
    func cancelAll() {
        let running = tasks.values
        tasks = [:]
        for task in running { task.cancel() }
        if !inFlight.isEmpty { inFlight = [] }
    }

    private func finish(_ request: AgentRequest, outcome: Outcome?) {
        // Cancelled by Erase or Stop Syncing in the meantime: nothing to report.
        guard tasks.removeValue(forKey: request.id) != nil else { return }
        if let outcome {
            finished.send(Finish(request: request, outcome: outcome))
            if outcome == .declined { announce("Request declined.") }
        }
        inFlight.remove(request.id)
    }
}
