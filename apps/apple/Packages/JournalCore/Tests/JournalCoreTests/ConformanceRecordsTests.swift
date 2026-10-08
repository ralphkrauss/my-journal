import XCTest

@testable import JournalCore

/// protocol/conformance/records/records-v1.json and timestamps-v1.json: what every client must obtain from a record's
/// plaintext, and what it must keep when it writes the record back (protocol/records.md, Reading rules).
final class ConformanceRecordsTests: XCTestCase {
    private static let path = "records/records-v1.json"

    /// What this implementation reads from one record: whether it can edit it, show it read-only or only keep it,
    /// the values it shows, and the bytes it writes back.
    static func reading(of record: ConformanceRecordCase) throws -> [String: Any] {
        let plaintext = Data(record.plaintext.utf8)
        let id = try XCTUnwrap(UUID(uuidString: record.id))
        let decoded = try? PortableRecord.decode(plaintext)
        let matching = decoded.flatMap { $0.id == id && $0.kind == record.kind ? $0 : nil }
        let item = matching ?? PortableRecord.unreadable(plaintext, id: id, kind: record.kind)
        let status = matching == nil ? "unreadable" : item.preservedJSON == nil ? "editable" : "readOnly"
        var result: [String: Any] = ["reading": status]
        func instant(_ date: Date?) -> Any { date.map { Int($0.timeIntervalSince1970) } ?? NSNull() }
        func identity(_ value: UUID?) -> Any { value?.uuidString.lowercased() ?? NSNull() }
        result["id"] = item.id.uuidString.lowercased()
        result["kind"] = item.kind
        result["title"] = item.title
        // An unreadable record has the dates that could be read; with none, the app shows the current time.
        let datesRead = matching != nil || ["date", "modifiedAt"].contains { raw(plaintext, $0) != nil }
        result["date"] = datesRead ? instant(item.date) : NSNull()
        result["modifiedAt"] = datesRead ? instant(item.modifiedAt) : NSNull()
        result["journalID"] = identity(item.journalID)
        result["deletedAt"] = instant(item.deletedAt)
        result["archivedAt"] = instant(item.archivedAt)
        result["defaultTemplateID"] = identity(item.defaultTemplateID)
        result["deletedWithJournal"] = item.deletedWithJournal
        result["permanentlyDeletedAt"] = instant(item.permanentlyDeletedAt)
        result["permanentDeletionID"] = identity(item.permanentDeletionID)
        result["restoredFromDeletionID"] = identity(item.restoredFromDeletionID)
        let editable = status == "editable"
        result["documentVersion"] = editable ? item.document.version : NSNull()
        result["markdown"] = editable && item.document.version == 2 ? item.document.markdown : NSNull()
        result["legacyBlockTexts"] =
            editable && item.document.version == 1
            ? item.document.blocks.map { $0.runs.map(\.text).joined() } : NSNull()
        let written = try PortableRecord.encode(item)
        // Records that aren't fully readable are written back byte for byte; the others are written again.
        result["rewrite"] = editable ? "rewritten" : "unchanged"
        result["appleWrites"] = editable ? String(decoding: written, as: UTF8.self) : NSNull()
        if !editable { XCTAssertEqual(written, plaintext, record.name) }
        return result
    }

    private static func raw(_ plaintext: Data, _ key: String) -> Date? {
        let object = (try? JSONSerialization.jsonObject(with: plaintext)) as? [String: Any]
        return (object?[key] as? String).flatMap { try? JournalCoding.date(from: $0) }
    }

    private static func fixture() throws -> [String: Any] {
        try Conformance.fixture(path) {
            let records = try ConformanceRecordCases.all.map { record -> [String: Any] in
                [
                    "name": record.name, "note": record.note, "id": record.id.lowercased(), "kind": record.kind,
                    "plaintext": record.plaintext, "expected": try reading(of: record),
                ]
            }
            return [
                "corpusVersion": 1,
                "purpose":
                    "Records as plaintext, with what a client must obtain from each and what it must do when it writes the record back (protocol/records.md, Reading rules). See README.md in this folder.",
                "records": records,
            ]
        }
    }

    /// Every record reads as the fixture says, and read-only and unreadable records keep their exact bytes.
    func testEveryRecordReadsAsTheFixtureSays() throws {
        let fixture = try Self.fixture()
        let records = try XCTUnwrap(fixture["records"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(records.count, 20)
        for record in records {
            let name = try XCTUnwrap(record["name"] as? String)
            let input = ConformanceRecordCase(
                name: name, note: "", id: try XCTUnwrap(record["id"] as? String),
                kind: try XCTUnwrap(record["kind"] as? String), plaintext: try XCTUnwrap(record["plaintext"] as? String)
            )
            let expected = try XCTUnwrap(record["expected"])
            XCTAssertTrue(try Conformance.same(try Self.reading(of: input), expected), name)
        }
    }

    /// The statuses and the bytes rules the fixture states, independent of the details above.
    func testReadOnlyAndUnreadableRecordsAreNeverRewritten() throws {
        let fixture = try Self.fixture()
        let records = try XCTUnwrap(fixture["records"] as? [[String: Any]])
        var statuses = Set<String>()
        for record in records {
            let expected = try XCTUnwrap(record["expected"] as? [String: Any])
            let status = try XCTUnwrap(expected["reading"] as? String)
            statuses.insert(status)
            XCTAssertEqual(expected["rewrite"] as? String, status == "editable" ? "rewritten" : "unchanged")
        }
        XCTAssertEqual(statuses, ["editable", "readOnly", "unreadable"])
    }

    func testTimestampsAcceptOffsetsAndFractionsAndRefuseTheRest() throws {
        let fixture = try Self.timestamps()
        let valid = try XCTUnwrap(fixture["valid"] as? [[String: Any]])
        for sample in valid {
            let text = try XCTUnwrap(sample["text"] as? String)
            let date = try JournalCoding.date(from: text)
            XCTAssertEqual(Int(date.timeIntervalSince1970.rounded(.down)), sample["epochSeconds"] as? Int, text)
        }
        let invalid = try XCTUnwrap(fixture["invalid"] as? [String])
        for text in invalid {
            XCTAssertThrowsError(try JournalCoding.date(from: text), text)
        }
    }

    static let validTimestamps: [(String, String)] = [
        ("2026-09-20T12:00:00Z", "UTC, whole seconds: what the Apple app writes"),
        ("2026-09-20T12:00:00+00:00", "A zero offset"),
        ("2026-05-20T09:00:00+01:00", "A positive offset"),
        ("2026-05-20T02:30:00-05:30", "A negative offset with minutes"),
        ("2026-05-20T08:00:00.1Z", "One fraction digit"),
        ("2026-05-20T08:00:00.123Z", "Milliseconds"),
        ("2026-05-20T08:00:00.1234567Z", "Seven fraction digits, the most readers accept"),
        ("2026-05-20T09:00:00.9234567+01:00", "A fraction and an offset: the instant keeps its whole second"),
        ("2026-12-31T23:59:59Z", "The last second of a year"),
        ("2028-02-29T00:00:00Z", "A leap day"),
    ]
    static let invalidTimestamps: [String] = [
        "", "not a timestamp", "2026-05-20", "2026-05-20T08:00:00", "2026-05-20 08:00:00Z", "2026-13-20T08:00:00Z",
        "1779264000",
    ]

    private static func timestamps() throws -> [String: Any] {
        try Conformance.fixture("records/timestamps-v1.json") {
            let valid = try validTimestamps.map { text, note -> [String: Any] in
                let date = try JournalCoding.date(from: text)
                return ["text": text, "epochSeconds": Int(date.timeIntervalSince1970.rounded(.down)), "note": note]
            }
            return [
                "corpusVersion": 1,
                "purpose":
                    "Timestamps (protocol/README.md, wire conventions): the instants a reader must accept, as whole epoch seconds rounded down, and texts it must refuse.",
                "valid": valid, "invalid": invalidTimestamps,
            ]
        }
    }
}
