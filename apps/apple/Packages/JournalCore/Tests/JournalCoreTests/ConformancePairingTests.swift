import CryptoKit
import XCTest

@testable import JournalCore

/// protocol/conformance/pairing/pairing-v1.json: the invite proof, the invite code's text, server origins and the
/// check code that both devices show (protocol/README.md, Pairing and Invite pairing). The key agreement and the
/// sealed grant are in crypto/encryption-v2.json.
final class ConformancePairingTests: XCTestCase {
    private static let path = "pairing/pairing-v1.json"

    private static func bytes(_ value: UInt8, _ count: Int) -> Data { Data(repeating: value, count: count) }

    private struct ProofInput {
        let name: String
        let server: String
        let deviceName: String
        let handle: Data
        let approverKey: Data
        let commitment: Data
        let secret: Data
    }

    private static let proofInputs: [ProofInput] = [
        ProofInput(
            name: "protocol-readme", server: "https://journal.example.ts.net", deviceName: "iPad",
            handle: bytes(1, 16), approverKey: bytes(2, 32), commitment: bytes(3, 32), secret: bytes(4, 32)),
        ProofInput(
            name: "non-ascii-name-and-port", server: "https://Journal.Example.ts.net:8443/ignored/path",
            deviceName: "Ralph’s Café 📱", handle: bytes(0xA1, 16), approverKey: bytes(0xB2, 32),
            commitment: bytes(0xC3, 32), secret: bytes(0xD4, 32)),
        ProofInput(
            name: "upper-case-scheme-and-default-port", server: "HTTPS://journal.example.ts.net:443", deviceName: "X",
            handle: bytes(0, 16), approverKey: bytes(0xFF, 32), commitment: bytes(0x80, 32), secret: bytes(0x7F, 32)),
    ]

    private static func proofCase(_ input: ProofInput) throws -> [String: Any] {
        let invite = PairingInvite(
            server: input.server, handle: input.handle, approverKey: input.approverKey, secret: input.secret)
        let origin = try XCTUnwrap(PairingInvite.origin(of: input.server))
        let message = PairingInvite.proofMessage(
            handle: input.handle, approverKey: input.approverKey, commitment: input.commitment, origin: origin,
            deviceName: input.deviceName)
        return [
            "name": input.name, "server": input.server, "deviceName": input.deviceName,
            "handle": input.handle.base64EncodedString(), "approverKey": input.approverKey.base64EncodedString(),
            "commitment": input.commitment.base64EncodedString(), "secret": input.secret.base64EncodedString(),
            "origin": origin, "handleHex": invite.code, "message": message.base64EncodedString(),
            "proof": try invite.proof(commitment: input.commitment.base64EncodedString(), deviceName: input.deviceName),
            "text": invite.text,
        ]
    }

    private static let addresses = [
        "https://journal.example.ts.net", "HTTPS://Journal.Example.ts.net:443/", "https://journal.example.ts.net:8443",
        "https://journal.example.ts.net/path?query=1#fragment", "http://journal.example.ts.net",
        "https://user:password@journal.example.ts.net", "ftp://journal.example.ts.net", "journal.example.ts.net",
        "https://", "",
    ]

    private static func originCases(_ addresses: [String]) -> [[String: Any]] {
        addresses.map { ["address": $0, "origin": PairingInvite.origin(of: $0) as Any? ?? NSNull()] }
    }

    /// A well-formed code whose server address another device can't use.
    private static let insecureCode = PairingInvite(
        server: "http://journal.example.ts.net", handle: bytes(1, 16), approverKey: bytes(2, 32), secret: bytes(4, 32)
    ).text

    private static var readTexts: [String] {
        [
            "https://example.com", "MYJOURNAL2.AAAA", "MYJOURNAL1.", "MYJOURNAL1.!!!!", "MYJOURNAL.AAAA",
            "MYJOURNAL1.AQEBAQEBAQEBAQEBAQEBAQ", insecureCode,
        ]
    }

    /// The text a scan can give, what reading it concludes.
    private static func readCases(_ texts: [String], valid: String) -> [[String: Any]] {
        (texts + [valid]).map { text in
            do {
                let invite = try PairingInvite(text: text)
                return ["text": text, "result": "invite", "server": invite.server]
            } catch let error as PairingInvite.ReadError {
                let name = [PairingInvite.ReadError.notInvite: "notInvite", .newerVersion: "newerVersion"][error]
                return ["text": text, "result": name ?? "unreachableServer"]
            } catch {
                return ["text": text, "result": "other"]
            }
        }
    }

    /// Check codes, including the first device key found whose code starts with zeros.
    private static func codeCases(from identifiers: [String]) throws -> [[String: Any]] {
        var cases: [[String: Any]] = []
        for text in identifiers {
            let identifier = try XCTUnwrap(UUID(uuidString: text))
            for (device, approver) in [(UInt8(7), UInt8(9)), (0, 0), (0xFF, 0x01)] {
                cases.append(
                    codeCase(identifier: text, id: identifier, device: bytes(device, 32), approver: bytes(approver, 32))
                )
            }
        }
        var key: UInt8 = 0
        while let identifier = UUID(uuidString: identifiers[0]), key < 255 {
            let device = bytes(key, 32)
            let sample = codeCase(identifier: identifiers[0], id: identifier, device: device, approver: bytes(9, 32))
            if (sample["checkCode"] as? String)?.hasPrefix("0") == true {
                var leading = sample
                leading["note"] = "A code that starts with zeros keeps them."
                cases.append(leading)
                break
            }
            key += 1
        }
        return cases
    }

    private static func codeCase(identifier: String, id: UUID, device: Data, approver: Data) -> [String: Any] {
        let code = PairingCheck.code(pairingID: id, devicePublicKey: device, approverPublicKey: approver)
        return [
            "pairingID": identifier, "devicePublicKey": device.base64EncodedString(),
            "approverPublicKey": approver.base64EncodedString(),
            "commitment": PairingCheck.commitment(device), "checkCode": code, "shown": PairingCheck.grouped(code),
        ]
    }

    private static let identifiers = ["3f2504e0-4f89-41d3-9a0c-0305e82c3301", "3F2504E0-4F89-41D3-9A0C-0305E82C3301"]

    private static func generated() throws -> [String: Any] {
        let inviteText = try XCTUnwrap(
            (try proofCase(proofInputs[0])["text"] as? String))
        return [
            "corpusVersion": 1,
            "purpose":
                "Pairing (protocol/README.md): the invite proof and the text of an invite code, server origins as the proof binds them, and the six-digit check code. Keys of 0x07 and 0x09 are the protocol README's vector. All values are synthetic and public.",
            "inviteProofs": try proofInputs.map(proofCase),
            "origins": originCases(addresses),
            "scannedTexts": readCases(readTexts, valid: inviteText),
            "checkCodes": try codeCases(from: identifiers),
        ]
    }

    func testPairingValuesMatchTheFixture() throws {
        let fixture = try Conformance.fixture(Self.path, generate: Self.generated)
        let proofs = try XCTUnwrap(fixture["inviteProofs"] as? [[String: Any]])
        let recomputed = try proofs.map { sample -> ProofInput in
            func data(_ key: String) throws -> Data {
                try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(sample[key] as? String)))
            }
            return ProofInput(
                name: try XCTUnwrap(sample["name"] as? String), server: try XCTUnwrap(sample["server"] as? String),
                deviceName: try XCTUnwrap(sample["deviceName"] as? String), handle: try data("handle"),
                approverKey: try data("approverKey"), commitment: try data("commitment"), secret: try data("secret"))
        }
        XCTAssertTrue(try Conformance.same(try recomputed.map(Self.proofCase), proofs))
        let addresses = try XCTUnwrap(fixture["origins"] as? [[String: Any]]).compactMap { $0["address"] as? String }
        XCTAssertTrue(try Conformance.same(Self.originCases(addresses), try XCTUnwrap(fixture["origins"])))
        let scanned = try XCTUnwrap(fixture["scannedTexts"] as? [[String: Any]]).compactMap { $0["text"] as? String }
        let valid = try XCTUnwrap(scanned.last)
        XCTAssertTrue(
            try Conformance.same(
                Self.readCases(Array(scanned.dropLast()), valid: valid), try XCTUnwrap(fixture["scannedTexts"])))
        let codes = try XCTUnwrap(fixture["checkCodes"] as? [[String: Any]])
        let ids = Array(NSOrderedSet(array: codes.compactMap { $0["pairingID"] as? String })) as? [String] ?? []
        XCTAssertTrue(try Conformance.same(try Self.codeCases(from: ids), codes))
    }

    /// The protocol README's own vectors, stated independently of the fixture's computed values.
    func testTheProtocolReadmeVectors() throws {
        let fixture = try Conformance.fixture(Self.path, generate: Self.generated)
        let proofs = try XCTUnwrap(fixture["inviteProofs"] as? [[String: Any]])
        XCTAssertEqual(proofs.first?["proof"] as? String, "xVcRQajP8P9JRb9Q527FO/+5SpxXKy3XXhgAxdoRgvY=")
        let codes = try XCTUnwrap(fixture["checkCodes"] as? [[String: Any]])
        let readme = try XCTUnwrap(
            codes.first { ($0["commitment"] as? String) == "2kHrWMfI9jssNr6LMzi1CnMfO8j59ftEu0NEGULOHFY=" })
        XCTAssertEqual(readme["checkCode"] as? String, "479111")
        XCTAssertEqual(readme["shown"] as? String, "479 111")
    }
}
