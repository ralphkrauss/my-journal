import XCTest

@testable import JournalCore

/// The JSON rules both archive kinds share (protocol/archive.md, Rules for both kinds): two readers must see the same
/// members, so names are bytes, nesting is counted the same way, and the cost of reading is bounded.
final class ArchiveJSONTests: XCTestCase {
    private func parse(_ text: String, keeping: Set<ArchiveJSONKey>? = nil, values: Int = 1_000) throws
        -> ArchiveJSONValue
    {
        try StrictJSON.parse(Data(text.utf8), keeping: keeping, maximumValues: values)
    }

    private func requireDamaged(_ text: String, keeping: Set<ArchiveJSONKey>? = nil, values: Int = 1_000) {
        XCTAssertThrowsError(try parse(text, keeping: keeping, values: values), String(text.prefix(80))) {
            XCTAssertEqual(ConformanceContainerTests.outcome(of: $0), "damaged")
        }
    }

    // MARK: Names are bytes

    /// Swift's `==` on strings follows canonical equivalence, so the Kelvin sign U+212A is `K` and a lookup for `K` found
    /// it. Other readers compare bytes and would not.
    func testAKelvinSignIsNotTheLetterK() throws {
        let members = try XCTUnwrap(try parse("{\"\\u212Aey\":1}").object)
        XCTAssertNil(members["Key"])
        XCTAssertNotNil(members[ArchiveJSONKey(bytes: Array("\u{212A}ey".utf8))])
    }

    func testNamesThatOnlyCanonicalEquivalenceJoinsAreDistinctMembers() throws {
        for (first, second) in [("Key", "\\u212Aey"), ("\\u00E9", "e\\u0301"), ("\\u00C5", "\\u212B")] {
            let members = try XCTUnwrap(try parse("{\"\(first)\":1,\"\(second)\":2}").object)
            XCTAssertEqual(members.count, 2, "\(first) and \(second)")
        }
    }

    func testTheSameBytesWrittenTwoWaysAreTheSameMember() {
        requireDamaged("{\"\\u00e9\":1,\"é\":2}")
        requireDamaged("{\"a\":1,\"\\u0061\":2}")
    }

    /// A header whose key member is spelled with a Kelvin sign has no `wrappedKey`.
    func testAHeaderWithALookalikeMemberNameLacksTheMember() throws {
        let container = try ArchiveContainer(at: Conformance.url("archive/v2/container/header-valid.zip"))
        let valid = String(decoding: try container.headerData(), as: UTF8.self)
        XCTAssertNoThrow(try FileArchiveHeader.parse(Data(valid.utf8)))
        let lookalike = valid.replacingOccurrences(of: "\"wrappedKey\"", with: "\"wrapped\\u212Aey\"")
        XCTAssertNotEqual(lookalike, valid)
        XCTAssertThrowsError(try FileArchiveHeader.parse(Data(lookalike.utf8))) {
            XCTAssertEqual(ConformanceContainerTests.outcome(of: $0), "damaged")
        }
    }

    // MARK: Depth

    private func nested(_ levels: Int) -> String {
        String(repeating: "[", count: levels) + "1" + String(repeating: "]", count: levels)
    }

    func testThirtyTwoLevelsAreReadAndThirtyThreeAreNot() throws {
        XCTAssertNoThrow(try parse(nested(32)))
        requireDamaged(nested(33))
        let objects = { (levels: Int) in
            String(repeating: "{\"a\":", count: levels) + "1" + String(repeating: "}", count: levels)
        }
        XCTAssertNoThrow(try parse(objects(32)))
        requireDamaged(objects(33))
    }

    // MARK: Cost

    func testMoreValuesThanTheLimitAreRefused() throws {
        let items = { (count: Int) in "[" + Array(repeating: "0", count: count).joined(separator: ",") + "]" }
        XCTAssertNoThrow(try parse(items(999)), "the array is a value too: 1,000 in all")
        requireDamaged(items(1_000))
    }

    func testMembersThatAreNotKeptAreCheckedAndNotBuilt() throws {
        let text = "{\"keep\":{\"a\":1},\"drop\":[1,2,{\"b\":[]}],\"also\":\"text\"}"
        let kept = try XCTUnwrap(try parse(text, keeping: ["keep"]).object)
        XCTAssertEqual(Set(kept.keys), ["keep"])
        XCTAssertEqual(kept["keep"], .object(["a": .number("1")]))
        XCTAssertEqual(try XCTUnwrap(try parse(text).object).count, 3)
        // Not kept does not mean not checked.
        requireDamaged("{\"drop\":[1,,2]}", keeping: ["keep"])
        requireDamaged("{\"drop\":{\"x\":1,\"x\":2}}", keeping: ["keep"])
        requireDamaged("{\"drop\":1,\"drop\":2}", keeping: ["keep"])
        requireDamaged("{\"drop\":\"\\ud800\"}", keeping: ["keep"])
        requireDamaged("{\"drop\":" + nested(33) + "}", keeping: ["keep"])
    }

    func testValuesThatAreNotKeptCountTowardTheLimit() {
        let flood = "{\"drop\":[" + Array(repeating: "0", count: 5_000).joined(separator: ",") + "]}"
        requireDamaged(flood, keeping: ["keep"])
    }

    /// The case that cost about 470 MB: 16 MiB of a header that is one unknown member holding millions of numbers. It
    /// is refused after the first thousand values, whatever its size.
    func testAHeaderThatIsOneHugeUnknownMemberIsRefusedEarly() {
        let flood = "{\"archiveVersion\":2,\"x\":[" + String(repeating: "0,", count: 8_388_608) + "0]}"
        XCTAssertGreaterThan(flood.utf8.count, 16 * 1024 * 1024 - 1)
        XCTAssertThrowsError(try FileArchiveHeader.parse(Data(flood.utf8))) {
            XCTAssertEqual(ConformanceContainerTests.outcome(of: $0), "damaged")
        }
    }

    /// A manifest may hold as many values as 100,000 images need and no more.
    func testTheManifestValueLimit() throws {
        let database = "\"database\":{\"bytes\":1,\"sha256\":\"" + String(repeating: "0", count: 64) + "\"}"
        let text = { (padding: Int) in
            "{\(database),\"attachments\":{},\"x\":[" + Array(repeating: "0", count: padding).joined(separator: ",")
                + "]}"
        }
        // The root, database, its two members, attachments and the padding array are 6 values.
        XCTAssertNoThrow(try ArchiveManifest.parse(Data(text(ArchiveLimits.manifestJSONValues - 6).utf8)))
        XCTAssertThrowsError(try ArchiveManifest.parse(Data(text(ArchiveLimits.manifestJSONValues - 5).utf8))) {
            XCTAssertEqual(ConformanceContainerTests.outcome(of: $0), "damaged")
        }
    }
}
