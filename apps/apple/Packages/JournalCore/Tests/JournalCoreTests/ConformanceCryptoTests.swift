import CryptoKit
import XCTest

@testable import JournalCore

/// protocol/conformance/crypto/negative-v1.json: what every client must refuse. Sealed values that must not open,
/// recovery parameters outside the accepted range, and base64 that isn't canonical (protocol/README.md, Encrypted
/// content, Recovery formats and wire conventions). The values that must open are in encryption-v1.json and
/// encryption-v2.json.
final class ConformanceCryptoTests: XCTestCase {
    private static let path = "crypto/negative-v1.json"

    private struct Corpus: Decodable {
        struct Envelope: Decodable {
            let name: String
            let key: Data
            let plaintext: Data
            let context: String
            let combined: Data
        }
        let envelopes: [Envelope]
    }

    private static func flipped(_ data: Data, at index: Int) -> Data {
        var copy = data
        copy[index] ^= 0x01
        return copy
    }

    private static func openCase(
        _ name: String, _ note: String, key: Data, context: String, combined: Data, opens: Data? = nil
    ) -> [String: Any] {
        var result: [String: Any] = [
            "name": name, "note": note, "key": key.base64EncodedString(), "context": context,
            "combined": combined.base64EncodedString(), "result": opens == nil ? "authenticationFails" : "opens",
        ]
        if let opens { result["plaintext"] = opens.base64EncodedString() }
        return result
    }

    private static func openCases() throws -> [[String: Any]] {
        let corpus = try Conformance.decode(Corpus.self, "crypto/encryption-v1.json")
        let record = try XCTUnwrap(corpus.envelopes.first { $0.name == "record" })
        let key = record.key
        let context = record.context
        let combined = record.combined
        let otherKey = Data(key.map { $0 ^ 0xFF })
        return [
            openCase(
                "untouched", "The vector itself opens.", key: key, context: context, combined: combined,
                opens: record.plaintext),
            openCase("wrong-key", "Another key.", key: otherKey, context: context, combined: combined),
            openCase(
                "flipped-tag", "The last tag byte changed.", key: key, context: context,
                combined: flipped(combined, at: combined.count - 1)),
            openCase(
                "flipped-ciphertext", "The first ciphertext byte changed.", key: key, context: context,
                combined: flipped(combined, at: 12)),
            openCase(
                "flipped-nonce", "The first nonce byte changed.", key: key, context: context,
                combined: flipped(combined, at: 0)),
            openCase(
                "another-kind", "The context names another record kind.", key: key,
                context: context.replacingOccurrences(of: ":entry:", with: ":journal:"), combined: combined),
            openCase(
                "another-record", "The context names another record.", key: key,
                context: String(context.dropLast()) + "f", combined: combined),
            openCase(
                "upper-case-id", "Contexts use lower-case UUIDs, so an upper-case one is another context.", key: key,
                context: context.uppercased().replacingOccurrences(
                    of: "JOURNAL:V1:RECORD:ENTRY:", with: "journal:v1:record:entry:"), combined: combined),
            openCase(
                "attachment-context", "The same bytes under an attachment context.", key: key,
                context: context.replacingOccurrences(of: "record:entry", with: "attachment"), combined: combined),
            openCase("empty-context", "No context.", key: key, context: "", combined: combined),
            openCase(
                "truncated-tag", "One byte short of the tag.", key: key, context: context, combined: combined.dropLast()
            ),
            openCase(
                "shorter-than-nonce-and-tag", "Fewer than 28 bytes.", key: key, context: context,
                combined: combined.prefix(27)),
            openCase("nonce-only", "Only a nonce.", key: key, context: context, combined: combined.prefix(12)),
            openCase("empty", "No bytes.", key: key, context: context, combined: Data()),
        ]
    }

    private static let parameters: [(name: String, iterations: Int, saltBytes: Int, client: Bool, server: Bool)] = [
        ("current", 600_000, 16, true, true), ("lowest-client-accepts", 100_000, 16, true, false),
        ("highest-client-accepts", 2_000_000, 16, true, false), ("below-range", 99_999, 16, false, false),
        ("above-range", 2_000_001, 16, false, false), ("zero", 0, 16, false, false), ("negative", -1, 16, false, false),
        ("short-salt", 600_000, 15, false, false), ("long-salt", 600_000, 17, false, false),
        ("empty-salt", 600_000, 0, false, false),
    ]

    private static let base64: (canonical: [(String, String)], rejected: [(String, String)]) = (
        [
            ("", ""), ("00", "AA=="), ("0001", "AAE="), ("000102", "AAEC"), ("fffefd", "//79"), ("fb", "+w=="),
            ("e29c93", "4pyT"),
        ],
        [
            ("QQ", "Padding missing."), ("QQ=", "Padding missing."), ("QR==", "Padding bits aren't zero."),
            ("QUJ=", "Padding bits aren't zero."), ("QUJD\n", "A line break."), ("QU JD", "Whitespace."),
            ("QUJD ", "Trailing whitespace."), ("QUJD====", "Too much padding."), ("QUJ_", "URL-safe alphabet."),
            ("QUJ-", "URL-safe alphabet."), ("=QUJ", "Padding first."),
        ]
    )

    private static func generated() throws -> [String: Any] {
        [
            "corpusVersion": 1,
            "purpose":
                "What every client must refuse: sealed values that must not open, recovery parameters outside the accepted range and base64 that isn't canonical. The sealed values are the record vector of encryption-v1.json, changed. See README.md in this folder.",
            "open": try openCases(),
            "recoveryParameters": parameters.map {
                [
                    "name": $0.name, "iterations": $0.iterations, "saltBytes": $0.saltBytes, "clientAccepts": $0.client,
                    "serverAcceptsOnSetup": $0.server,
                ]
            },
            "base64": [
                "canonical": base64.canonical.map { ["hex": $0.0, "text": $0.1] },
                "rejected": base64.rejected.map { ["text": $0.0, "note": $0.1] },
            ],
        ]
    }

    func testSealedValuesThatMustNotOpenDoNot() throws {
        let fixture = try Conformance.fixture(Self.path, generate: Self.generated)
        let cases = try XCTUnwrap(fixture["open"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 12)
        for sample in cases {
            let name = try XCTUnwrap(sample["name"] as? String)
            let key = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(sample["key"] as? String)))
            let combined = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(sample["combined"] as? String)))
            let context = try XCTUnwrap(sample["context"] as? String)
            if sample["result"] as? String == "opens" {
                let plaintext = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(sample["plaintext"] as? String)))
                XCTAssertEqual(try VaultCrypto.open(combined, key: key, context: context), plaintext, name)
            } else {
                XCTAssertThrowsError(try VaultCrypto.open(combined, key: key, context: context), name)
            }
        }
    }

    func testRecoveryParametersOutsideTheRangeAreRefused() throws {
        let fixture = try Conformance.fixture(Self.path, generate: Self.generated)
        let cases = try XCTUnwrap(fixture["recoveryParameters"] as? [[String: Any]])
        for sample in cases {
            let name = try XCTUnwrap(sample["name"] as? String)
            let iterations = try XCTUnwrap(sample["iterations"] as? Int)
            let salt = Data(count: try XCTUnwrap(sample["saltBytes"] as? Int))
            let accepted = try XCTUnwrap(sample["clientAccepts"] as? Bool)
            let derived = Result { try VaultCrypto.derive("a password", salt: salt, iterations: iterations) }
            switch derived {
            case .success(let key): XCTAssertTrue(accepted && key.count == 32, name)
            case .failure: XCTAssertFalse(accepted, name)
            }
        }
    }

    /// Canonical base64 is what re-encoding the decoded bytes gives back; anything else is refused.
    func testOnlyCanonicalBase64IsAccepted() throws {
        let fixture = try Conformance.fixture(Self.path, generate: Self.generated)
        let section = try XCTUnwrap(fixture["base64"] as? [String: Any])
        for sample in try XCTUnwrap(section["canonical"] as? [[String: Any]]) {
            let hex = try XCTUnwrap(sample["hex"] as? String)
            let text = try XCTUnwrap(sample["text"] as? String)
            let bytes = Data(
                stride(from: 0, to: hex.count, by: 2).compactMap { offset in
                    let start = hex.index(hex.startIndex, offsetBy: offset)
                    return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)
                })
            XCTAssertEqual(bytes.base64EncodedString(), text)
            XCTAssertEqual(Data(base64Encoded: text), bytes)
        }
        for sample in try XCTUnwrap(section["rejected"] as? [[String: Any]]) {
            let text = try XCTUnwrap(sample["text"] as? String)
            let canonical = Data(base64Encoded: text).map { $0.base64EncodedString() == text } ?? false
            XCTAssertFalse(canonical, text)
        }
    }
}
