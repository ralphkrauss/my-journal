import XCTest

@testable import JournalCore

/// protocol/conformance/sync/status-v2.json: every client computes the same effective protocol revision from a
/// status, and a status the app refuses says so the same way everywhere.
final class ServerRevisionTests: XCTestCase {
    private func cases() throws -> [[String: Any]] {
        let corpus = try Conformance.object("sync/status-v2.json")
        let rule = try XCTUnwrap(corpus["effectiveRevision"] as? [String: Any])
        return try XCTUnwrap(rule["cases"] as? [[String: Any]])
    }

    func testTheRevisionIsComputedFromEveryRecordedStatus() throws {
        let recorded = try cases()
        XCTAssertGreaterThan(recorded.count, 20)
        for entry in recorded {
            let name = try XCTUnwrap(entry["name"] as? String)
            let body = try JSONSerialization.data(withJSONObject: try XCTUnwrap(entry["status"]))
            let status = try JSONDecoder().decode(ServerStatus.self, from: body)
            switch entry["expect"] {
            case let revision as Int: XCTAssertEqual(status.compatibility, .revision(revision), name)
            case let marker as String:
                XCTAssertEqual(marker, "newerMajor", name)
                XCTAssertEqual(status.compatibility, .newerMajor, name)
            default: XCTFail("\(name): unknown expectation")
            }
        }
    }

    func testTheCapabilityListThatMakesRevisionOneIsTheFrozenOne() throws {
        let corpus = try Conformance.object("sync/status-v2.json")
        XCTAssertEqual(corpus["revisionOneFeatures"] as? [String], ServerStatus.revisionOneFeatures)
        XCTAssertEqual(ServerStatus.revisionOneFeatures.count, 13)
    }

    func testOnlyAServerBelowRevisionOneIsRefusedAsNeedingAnUpdate() throws {
        func refusal(_ status: ServerStatus) -> ServerRefusal? {
            do { try status.requireCompatible() } catch { return error as? ServerRefusal }
            return nil
        }
        XCTAssertNil(refusal(.healthy()))
        XCTAssertNil(refusal(ServerStatus(protocolVersion: 1, protocolRevision: 5, initialized: true)))
        XCTAssertEqual(refusal(ServerStatus(protocolVersion: 1, initialized: true)), .serverNeedsUpdate)
        XCTAssertEqual(
            refusal(ServerStatus(protocolVersion: 2, protocolRevision: 1, initialized: true)), .appNeedsUpdate)
        XCTAssertTrue(ServerStatus.healthy().supports(revision: 1))
        XCTAssertFalse(ServerStatus.healthy().supports(revision: 2))
    }
}
