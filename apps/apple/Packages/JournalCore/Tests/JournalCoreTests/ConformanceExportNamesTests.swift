import XCTest

@testable import JournalCore

/// protocol/conformance/markdown-export/names-v1.json: the rules that make export names, file contents and dates
/// the same on every client (protocol/markdown-export.md).
final class ConformanceExportNamesTests: XCTestCase {
    private static let path = "markdown-export/names-v1.json"

    private static func zone(_ minutes: Int) -> TimeZone {
        TimeZone(secondsFromGMT: minutes * 60) ?? .gmt
    }

    private static func claimed(_ names: [String]) -> [String] {
        var used = UniqueNames()
        return names.map { used.claim($0) }
    }

    private static func safeCases(_ inputs: [(input: String, fallback: String, note: String)]) -> [[String: Any]] {
        inputs.map { sample in
            [
                "input": sample.input, "fallback": sample.fallback, "note": sample.note,
                "expected": ExportName.safe(sample.input, fallback: sample.fallback),
            ]
        }
    }

    private static func dateCases(_ inputs: [(instant: String, offsetMinutes: Int)]) -> [[String: Any]] {
        inputs.compactMap { sample in
            guard let date = try? JournalCoding.date(from: sample.instant) else { return nil }
            let zone = zone(sample.offsetMinutes)
            return [
                "instant": sample.instant, "offsetMinutes": sample.offsetMinutes,
                "timestamp": MarkdownExport.timestamp(date, timeZone: zone),
                "day": MarkdownExport.day(date, timeZone: zone),
                "folderName": MarkdownExport.folderName(date: date, timeZone: zone),
            ]
        }
    }

    private static func generated() -> [String: Any] {
        [
            "corpusVersion": 1,
            "purpose":
                "Export as Markdown names and text escapes (protocol/markdown-export.md): safe names, numbering of names that compare equal, YAML strings, heading text, dates in the exporting device's offset. See README.md in this folder.",
            "safeNames": safeCases(ConformanceExportNames.safe),
            "uniqueNames": ConformanceExportNames.unique.map {
                ["note": $0.note, "claimed": $0.names, "expected": claimed($0.names)]
            },
            "yamlStrings": ConformanceExportNames.yaml.map {
                ["input": $0.input, "note": $0.note, "expected": MarkdownExport.yamlString($0.input)]
            },
            "headingText": ConformanceExportNames.headings.map {
                ["input": $0.input, "note": $0.note, "expected": MarkdownExport.headingText($0.input)]
            },
            "dates": dateCases(ConformanceExportNames.dates),
        ]
    }

    /// The same cases, recomputed from the fixture's own inputs.
    private static func recomputed(from fixture: [String: Any]) throws -> [String: Any] {
        func list(_ key: String) throws -> [[String: Any]] { try XCTUnwrap(fixture[key] as? [[String: Any]]) }
        func text(_ item: [String: Any], _ key: String) throws -> String { try XCTUnwrap(item[key] as? String) }
        var result = fixture
        result["safeNames"] = try list("safeNames").map { sample in
            var sample = sample
            sample["expected"] = ExportName.safe(try text(sample, "input"), fallback: try text(sample, "fallback"))
            return sample
        }
        result["uniqueNames"] = try list("uniqueNames").map { sample in
            var sample = sample
            sample["expected"] = Self.claimed(try XCTUnwrap(sample["claimed"] as? [String]))
            return sample
        }
        result["yamlStrings"] = try list("yamlStrings").map { sample in
            var sample = sample
            sample["expected"] = MarkdownExport.yamlString(try text(sample, "input"))
            return sample
        }
        result["headingText"] = try list("headingText").map { sample in
            var sample = sample
            sample["expected"] = MarkdownExport.headingText(try text(sample, "input"))
            return sample
        }
        result["dates"] = Self.dateCases(
            try list("dates").map { (try text($0, "instant"), try XCTUnwrap($0["offsetMinutes"] as? Int)) })
        return result
    }

    func testNamesEscapesAndDatesMatchTheFixture() throws {
        let fixture = try Conformance.fixture(Self.path, generate: Self.generated)
        XCTAssertTrue(try Conformance.same(try Self.recomputed(from: fixture), fixture))
    }

    /// The rules the fixture's examples illustrate, stated directly: every name is safe on every system.
    func testSafeNamesHaveNoUnsafeCharactersAndStayWithinTheLimits() throws {
        let fixture = try Conformance.fixture(Self.path, generate: Self.generated)
        let samples = try XCTUnwrap(fixture["safeNames"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(samples.count, 25)
        let unsafe = Set("/\\:*?\"<>|#^[]")
        for sample in samples {
            let name = try XCTUnwrap(sample["expected"] as? String)
            XCTAssertFalse(name.isEmpty)
            XCTAssertTrue(name.allSatisfy { !unsafe.contains($0) && !$0.isNewline && $0 != "\t" }, name)
            XCTAssertLessThanOrEqual(name.count, 60)
            XCTAssertLessThanOrEqual(name.utf8.count, 120)
            XCTAssertFalse(name.hasPrefix(".") || name.hasSuffix(".") || name.hasSuffix(" "), name)
        }
    }
}
