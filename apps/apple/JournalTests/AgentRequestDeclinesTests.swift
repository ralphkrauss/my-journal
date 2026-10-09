import JournalCore
import XCTest
import os

@testable import Journal

/// Don't Allow when the server can't be reached: the Agent Access page says so and keeps the request, and a decline
/// outlives the pane that started it (docs/design/1-1-settings-messages-editor.md §7).
@MainActor
final class AgentRequestDeclinesTests: XCTestCase {
    private func request(_ name: String = "Claude Code") throws -> AgentRequest {
        let json = """
            {"id":"\(UUID().uuidString)","clientName":"\(name)","clientId":"client","identifiedAs":null,\
            "redirectHost":"127.0.0.1","redirectKind":"loopback","requestedAt":"2026-10-09T10:00:00Z",\
            "expiresAt":"2026-10-09T10:10:00Z","reconnectCandidate":null}
            """
        return try JournalCoding.decoder().decode(AgentRequest.self, from: Data(json.utf8))
    }
    private func problem(_ status: Int, _ code: String) -> Data {
        Data(#"{"status":\#(status),"code":"\#(code)","error":"\#(code)"}"#.utf8)
    }
    /// How a decline ends for the app, as the server's answer is read: `declined` for a recorded decline or a
    /// request the server no longer has, nil for a cancelled one, and `failed` for everything else.
    private func outcome(answering status: Int, _ body: Data) async throws -> AgentRequestDeclines.Outcome? {
        let server = try await FakeJournalServer { _ in (status, body) }
        let client = try ServerClient(address: server.address, token: "t")
        do {
            try await client.declineAgentRequest(UUID())
            return .declined
        } catch { return AgentRequestDeclines.outcome(of: error) }
    }

    /// The server's answer decides: recorded and "no longer there" are done; a refusal of any kind, an unknown route,
    /// a lost sign-in and an unreachable server are failures; a cancelled request shows nothing.
    func testTheServersAnswerIsMappedToDoneFailedOrNothing() async throws {
        let done = AgentRequestDeclines.Outcome.declined
        let failed = AgentRequestDeclines.Outcome.failed
        let answers: [(String, Int, Data, AgentRequestDeclines.Outcome)] = [
            ("recorded", 200, Data("{}".utf8), done),
            ("no content", 204, Data(), done),
            ("expired, replaced or answered elsewhere", 404, problem(404, "agent_request_not_found"), done),
            ("a server without agent access", 404, Data(), failed),
            ("a different 404", 404, problem(404, "agent_not_found"), failed),
            ("not authorised", 401, problem(401, "unauthorized"), failed),
            ("a conflict", 409, problem(409, "agent_limit"), failed),
            ("a server error", 500, Data(), failed),
        ]
        for (label, status, body, expected) in answers {
            let result = try await outcome(answering: status, body)
            XCTAssertEqual(result, expected, label)
        }
        // A server that can't be reached: nothing listens on port 1.
        let unreachable = try ServerClient(address: "http://127.0.0.1:1", token: "t")
        do {
            try await unreachable.declineAgentRequest(UUID())
            XCTFail("A request to nothing can't succeed.")
        } catch {
            XCTAssertEqual(AgentRequestDeclines.outcome(of: error), failed, "A network error is a failure.")
        }
        XCTAssertNil(AgentRequestDeclines.outcome(of: CancellationError()))
        XCTAssertNil(AgentRequestDeclines.outcome(of: URLError(.cancelled)))
        XCTAssertEqual(AgentRequestDeclines.outcome(of: URLError(.notConnectedToInternet)), .failed)
        XCTAssertEqual(AgentRequestDeclines.outcome(of: JournalError.unauthorized), .failed)
        XCTAssertEqual(AgentRequestDeclines.outcome(of: AgentCopyError.failed), .failed)
    }

    /// Lets an asynchronous send wait until the test releases it.
    private actor Gate {
        private var open = false
        private var waiting: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            if open { return }
            await withCheckedContinuation { waiting.append($0) }
        }
        func release() {
            open = true
            for continuation in waiting { continuation.resume() }
            waiting = []
        }
    }
    private func settle(_ declines: AgentRequestDeclines) async {
        for _ in 0..<200 where !declines.inFlight.isEmpty { try? await Task.sleep(nanoseconds: 5_000_000) }
        await Task.yield()
    }

    func testAFailedDeclineBringsTheRowBackWithTheMessageAndASuccessRemovesItAndAnnouncesOnce() async throws {
        var announced: [String] = []
        let declines = AgentRequestDeclines { announced.append($0) }
        let controller = ServerAgentsController()
        let first = try request("Claude Code")
        let second = try request("Codex")
        controller.receive(waiting: [first, second])
        let gate = Gate()
        controller.decline(first, declines: declines) { _ in
            await gate.wait()
            throw URLError(.notConnectedToInternet)
        }
        XCTAssertEqual(controller.requests.map(\.id), [second.id], "The request leaves the list while it is declined.")
        controller.receive(waiting: [first, second])
        XCTAssertEqual(controller.requests.map(\.id), [second.id], "A refresh that still lists it doesn't show it.")
        await gate.release()
        await settle(declines)
        XCTAssertEqual(controller.requests.map(\.id), [first.id, second.id], "It comes back.")
        XCTAssertEqual(
            controller.declineFailure,
            "Couldn’t decline the request from Claude Code. Open it and choose Don’t Allow to try again.")
        XCTAssertEqual(announced.count, 0, "\"Request declined.\" is only announced on success.")

        // A second try that works removes the row, clears the message and announces once.
        controller.decline(first, declines: declines) { _ in }
        await settle(declines)
        XCTAssertEqual(controller.requests.map(\.id), [second.id])
        XCTAssertNil(controller.declineFailure)
        XCTAssertEqual(announced, ["Request declined."])
    }
    func testTheMessageGoesWhenTheRequestIsGoneOrOpenedAgainOrTheAppLocks() async throws {
        let declines = AgentRequestDeclines { _ in }
        let controller = ServerAgentsController()
        let waiting = try request()
        controller.receive(waiting: [waiting])
        func fail() async {
            controller.decline(waiting, declines: declines) { _ in throw URLError(.timedOut) }
            await settle(declines)
        }
        await fail()
        XCTAssertNotNil(controller.declineFailure)
        controller.receive(waiting: [])
        XCTAssertNil(controller.declineFailure, "A reload that no longer lists the request clears it.")
        controller.receive(waiting: [waiting])
        await fail()
        XCTAssertNotNil(controller.declineFailure)
        controller.clear()
        XCTAssertNil(controller.declineFailure, "Locking clears it.")
    }

    /// The decline belongs to the app session: closing Settings (the controller going away) neither stops it nor
    /// shows anything, and the request is listed again when the pane opens.
    func testClosingSettingsDoesntCancelADeclineAndShowsNothing() async throws {
        let declines = AgentRequestDeclines { _ in }
        let waiting = try request()
        let gate = Gate()
        let ran = OSAllocatedUnfairLock(initialState: false)
        var controller: ServerAgentsController? = ServerAgentsController()
        controller?.receive(waiting: [waiting])
        controller?.decline(waiting, declines: declines) { _ in
            await gate.wait()
            ran.withLock { $0 = true }
            throw URLError(.cannotConnectToHost)
        }
        controller = nil
        XCTAssertEqual(declines.inFlight, [waiting.id])
        await gate.release()
        await settle(declines)
        XCTAssertTrue(ran.withLock { $0 }, "The decline carried on after the pane was gone.")
        let reopened = ServerAgentsController()
        reopened.receive(waiting: [waiting])
        XCTAssertEqual(reopened.requests.map(\.id), [waiting.id])
        XCTAssertNil(reopened.declineFailure, "Nothing was shown for a failure that arrived with Settings closed.")
    }
    func testEraseAndStopSyncingCancelDeclinesWithoutAMessageButLockingDoesNot() async throws {
        let declines = AgentRequestDeclines { _ in }
        let controller = ServerAgentsController()
        let waiting = try request()
        controller.receive(waiting: [waiting])
        let gate = Gate()
        controller.decline(waiting, declines: declines) { _ in await gate.wait() }
        // Locking clears the controller's list and message; the task goes on.
        controller.clear()
        XCTAssertEqual(declines.inFlight, [waiting.id])
        declines.cancelAll()
        XCTAssertTrue(declines.inFlight.isEmpty)
        await gate.release()
        try await Task.sleep(nanoseconds: 50_000_000)
        controller.receive(waiting: [waiting])
        XCTAssertNil(controller.declineFailure, "A cancelled decline says nothing.")
        XCTAssertEqual(controller.requests.map(\.id), [waiting.id])
    }
}
