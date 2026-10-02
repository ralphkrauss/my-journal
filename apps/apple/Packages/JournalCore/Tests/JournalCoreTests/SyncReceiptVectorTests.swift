import XCTest

@testable import JournalCore

/// protocol/fixtures/sync-receipts-v1.json: the client completes the public short receipt into exactly the full
/// receipt, and reads the three wait answers.
final class SyncReceiptVectorTests: XCTestCase {
    func testTheShortReceiptVectorCompletesToTheFullReceipt() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("protocol/fixtures/sync-receipts-v1.json")
        let corpus = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let pending = try JournalCoding.decoder().decode(
            PendingChange.self,
            from: JSONSerialization.data(
                withJSONObject: try XCTUnwrap(corpus["pending"] as? [String: Any]).reduce(into: [String: Any]()) {
                    $0[$1.key == "recordId" ? "recordID" : $1.key] = $1.value
                }))
        let short = try ServerClient.receipt(
            JSONSerialization.data(withJSONObject: try XCTUnwrap(corpus["shortReceipt"])), for: pending)
        let full = try ServerClient.receipt(
            JSONSerialization.data(withJSONObject: try XCTUnwrap(corpus["fullReceipt"])), for: pending)
        XCTAssertEqual(short.payload, full.payload)
        XCTAssertEqual([short.cursor, short.revision], [full.cursor, full.revision])
        XCTAssertEqual(short.recordId, full.recordId)
        XCTAssertEqual(short.modifiedAt, full.modifiedAt)
        let answers = try XCTUnwrap(corpus["waitAnswers"] as? [String: Any])
        let expected: [String: WaitAnswer] = [
            "changed": .changed, "confirming": .unchanged(early: false), "early": .unchanged(early: true),
        ]
        for (name, answer) in expected {
            let body = try JSONSerialization.data(withJSONObject: try XCTUnwrap(answers[name]))
            XCTAssertEqual(ServerClient.waitAnswer(status: 200, body: body), answer, name)
        }
    }
}
