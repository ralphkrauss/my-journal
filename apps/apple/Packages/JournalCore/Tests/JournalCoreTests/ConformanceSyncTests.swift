import XCTest

@testable import JournalCore

/// protocol/conformance/sync/exchanges-v1.json: every response the server's tests record is read by this client's own
/// decoders, so a change to what the server writes, or to how the client reads it, fails here. The server's tests
/// replay the same requests against a real server.
final class ConformanceSyncTests: XCTestCase {
    private struct Step {
        let name: String
        let method: String
        let request: [String: Any]
        let status: Int
        let body: [String: Any]?
        let client: String
        let bodyData: Data
    }

    private func steps() throws -> [Step] {
        let fixture = try Conformance.object("sync/exchanges-v1.json")
        let raw = try XCTUnwrap(fixture["steps"] as? [[String: Any]])
        return try raw.map { step in
            let request = try XCTUnwrap(step["request"] as? [String: Any])
            let response = try XCTUnwrap(step["response"] as? [String: Any])
            let body = response["body"] as? [String: Any]
            return Step(
                name: try XCTUnwrap(step["name"] as? String), method: try XCTUnwrap(request["method"] as? String),
                request: request.mapValues { $0 }, status: try XCTUnwrap(response["status"] as? Int), body: body,
                client: try XCTUnwrap(step["client"] as? String),
                bodyData: try JSONSerialization.data(withJSONObject: body ?? [:]))
        }
    }

    private func pending(_ step: Step) throws -> PendingChange {
        let path = try XCTUnwrap(step.request["path"] as? String)
        let body = try XCTUnwrap(step.request["body"] as? [String: Any])
        return PendingChange(
            operationId: try XCTUnwrap(UUID(uuidString: try XCTUnwrap(body["operationId"] as? String))),
            recordID: try XCTUnwrap(UUID(uuidString: String(path.split(separator: "/").last ?? ""))),
            baseRevision: try XCTUnwrap(body["baseRevision"] as? Int64), kind: try XCTUnwrap(body["kind"] as? String),
            payload: try XCTUnwrap(body["payload"] as? String))
    }

    private func checkReceipt(_ step: Step) throws {
        let body = try XCTUnwrap(step.body)
        let change = try ServerClient.receipt(step.bodyData, for: try pending(step))
        XCTAssertEqual(change.cursor, body["cursor"] as? Int64, step.name)
        XCTAssertEqual(change.revision, body["revision"] as? Int64, step.name)
        XCTAssertEqual(change.recordId.uuidString.lowercased(), body["recordId"] as? String, step.name)
        XCTAssertEqual(change.kind, body["kind"] as? String, step.name)
        XCTAssertEqual(change.deviceId.uuidString.lowercased(), body["deviceId"] as? String, step.name)
        XCTAssertEqual(change.modifiedAt, try JournalCoding.date(from: try XCTUnwrap(body["modifiedAt"] as? String)))
        // A short receipt is completed with the payload that was sent; a full one carries it.
        XCTAssertEqual(change.payload, try pending(step).payload, step.name)
        if let digest = body["payloadDigest"] as? String {
            XCTAssertEqual(digest, JournalStore.payloadDigest(change.payload), step.name)
        }
    }

    private func checkConflict(_ step: Step) throws {
        let result = try ServerClient.pushConflict(step.bodyData, pending: try pending(step))
        let name = step.name
        switch (step.client, result) {
        case ("conflict", .conflict(let current)):
            let expected = try XCTUnwrap(step.body?["current"] as? [String: Any])
            XCTAssertEqual(current.revision, expected["revision"] as? Int64, name)
            XCTAssertEqual(current.payload, expected["payload"] as? String, name)
            XCTAssertEqual(current.kind, expected["kind"] as? String, name)
        case ("serverBehind", .serverBehind), ("serverChanged", .serverChanged): break
        default: XCTFail("\(name): the client read \(result) as \(step.client)")
        }
    }

    private func checkPage(_ step: Step) throws {
        let body = try XCTUnwrap(step.body)
        let page = try JournalCoding.decoder().decode(SyncPage.self, from: step.bodyData)
        XCTAssertEqual(page.cursor, body["cursor"] as? Int64, step.name)
        XCTAssertEqual(page.hasMore, body["hasMore"] as? Bool, step.name)
        XCTAssertEqual(page.serverId, body["serverId"] as? String, step.name)
        XCTAssertEqual(page.serverIdCursor, body["serverIdCursor"] as? Int64, step.name)
        let expected = try XCTUnwrap(body["changes"] as? [[String: Any]])
        XCTAssertEqual(page.changes.map(\.cursor), expected.compactMap { $0["cursor"] as? Int64 }, step.name)
        XCTAssertEqual(page.changes.map(\.payload), expected.compactMap { $0["payload"] as? String }, step.name)
        XCTAssertEqual(page.changes.map(\.kind), expected.compactMap { $0["kind"] as? String }, step.name)
        // The pages the client reads must advance, as the contract requires.
        if page.hasMore { XCTAssertGreaterThan(page.cursor, try XCTUnwrap(afterCursor(step)), step.name) }
    }

    private func afterCursor(_ step: Step) -> Int64? {
        let path = step.request["path"] as? String ?? ""
        let query = URLComponents(string: path)?.queryItems ?? []
        return query.first { $0.name == "after" }?.value.flatMap { Int64($0) }
    }

    func testTheClientReadsEveryRecordedResponse() throws {
        let steps = try steps()
        XCTAssertGreaterThanOrEqual(steps.count, 25)
        var kinds = Set<String>()
        for step in steps {
            kinds.insert(step.client)
            let code = step.body?["code"] as? String
            switch step.client {
            case "receipt": try checkReceipt(step)
            case "conflict", "serverBehind": try checkConflict(step)
            case "serverChanged" where step.method == "PUT": try checkConflict(step)
            case "serverChanged": XCTAssertEqual(ServerClient.problemCode(step.bodyData), "server_changed", step.name)
            case "rejected" where step.status == 409:
                XCTAssertThrowsError(try ServerClient.pushConflict(step.bodyData, pending: try pending(step))) {
                    XCTAssertEqual(($0 as? SyncRejection)?.reason, .invalid, step.name)
                }
            case "rejected", "problem": XCTAssertEqual(ServerClient.problemCode(step.bodyData), code, step.name)
            case "page": try checkPage(step)
            case "wait": XCTAssertEqual(ServerClient.waitAnswer(status: step.status, body: step.bodyData), .changed)
            case "status": try checkStatus(step)
            case "capabilities": XCTAssertEqual(step.body?["protocolVersions"] as? [Int], [1])
            default: XCTFail("\(step.name): unknown client check \(step.client)")
            }
        }
        XCTAssertTrue(kinds.isSuperset(of: ["receipt", "conflict", "serverBehind", "page", "problem", "wait"]))
    }

    private func checkStatus(_ step: Step) throws {
        let status = try JSONDecoder().decode(ServerStatus.self, from: step.bodyData)
        XCTAssertEqual(status.protocolVersion, 1)
        XCTAssertTrue(status.initialized)
        XCTAssertTrue(status.supports(ServerClient.shortReceiptFeature))
    }
}
