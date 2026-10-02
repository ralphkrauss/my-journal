import XCTest

@testable import JournalCore

final class TimestampInteropTests: XCTestCase {
    /// Other clients may write offsets and fractions. Items hold the whole seconds a save stores, so an item read
    /// from any client equals its stored copy after this client saves it.
    func testPortableRecordTimestampsAcceptOffsetsAndFractionsAsStoredWholeSeconds() throws {
        let entry = JournalItem(kind: "entry", document: .plain("Timestamp interoperability"))
        var record = try XCTUnwrap(
            JSONSerialization.jsonObject(with: PortableRecord.encode(entry)) as? [String: Any])
        let wholeSecond = 1_779_264_000.0
        let samples = [
            "2026-05-20T08:00:00Z", "2026-05-20T09:00:00+01:00", "2026-05-20T02:30:00-05:30",
            "2026-05-20T08:00:00.1Z", "2026-05-20T08:00:00.1234567Z", "2026-05-20T09:00:00.9234567+01:00",
        ]
        for timestamp in samples {
            record["date"] = timestamp
            record["modifiedAt"] = timestamp
            let decoded = try PortableRecord.decode(JSONSerialization.data(withJSONObject: record))
            XCTAssertEqual(decoded.date.timeIntervalSince1970, wholeSecond, timestamp)
            XCTAssertEqual(decoded.modifiedAt, decoded.date)
            XCTAssertEqual(try PortableRecord.decode(PortableRecord.encode(decoded)), decoded, timestamp)
        }
        var created = JournalItem(kind: "entry", date: Date(timeIntervalSince1970: wholeSecond + 0.75))
        created.modifiedAt = Date(timeIntervalSince1970: wholeSecond + 0.25)
        XCTAssertEqual(try PortableRecord.decode(PortableRecord.encode(created)), created)
        record["date"] = "not a timestamp"
        XCTAssertThrowsError(try PortableRecord.decode(JSONSerialization.data(withJSONObject: record)))
    }
}
