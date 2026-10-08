import CryptoKit
import XCTest

@testable import JournalCore

final class InteroperabilityTests: XCTestCase {
    private struct Corpus: Decodable {
        struct Recovery: Decodable {
            let phrase: String
            let salt: Data
            let iterations: Int
            let derivedKey: Data
            let authenticationSecret: String
        }
        struct Envelope: Decodable {
            let name: String
            let key: Data
            let plaintext: Data
            let context: String
            let combined: Data
        }
        let formatVersion: Int
        let recovery: Recovery
        let envelopes: [Envelope]
    }
    private func corpus() throws -> Corpus {
        try Conformance.decode(Corpus.self, "crypto/encryption-v1.json")
    }
    func testIndependentEnvelopesAuthenticateAndPreservePortableContent() throws {
        let corpus = try corpus()
        XCTAssertEqual(corpus.formatVersion, 1)
        for vector in corpus.envelopes {
            let opened = try VaultCrypto.open(vector.combined, key: vector.key, context: vector.context)
            XCTAssertEqual(opened, vector.plaintext, vector.name)
            // Fixed nonces exist only in public fixtures; production seal always generates a fresh nonce.
            let nonce = try AES.GCM.Nonce(data: vector.combined.prefix(12))
            let sealed = try AES.GCM.seal(
                vector.plaintext, using: SymmetricKey(data: vector.key), nonce: nonce,
                authenticating: Data(vector.context.utf8))
            XCTAssertEqual(sealed.combined, vector.combined, vector.name)
            XCTAssertThrowsError(try VaultCrypto.open(vector.combined, key: vector.key, context: vector.context + "x"))
            var damaged = vector.combined
            damaged[damaged.count - 1] ^= 1
            XCTAssertThrowsError(try VaultCrypto.open(damaged, key: vector.key, context: vector.context))
        }
        let record = try XCTUnwrap(corpus.envelopes.first { $0.name == "record" })
        let item = try PortableRecord.decode(record.plaintext)
        XCTAssertEqual(VaultCrypto.recordContext(id: item.id, kind: item.kind), record.context)
        XCTAssertEqual(item.title, "Café — 日記")
        XCTAssertEqual(item.document.text, "A quiet day. 🌿")
        XCTAssertEqual(item.document.blocks.first?.runs.first?.bold, true)
        let attachment = try XCTUnwrap(corpus.envelopes.first { $0.name == "attachment" })
        let attachmentID = try XCTUnwrap(UUID(uuidString: "01234567-89AB-4CDE-8FAB-0123456789AB"))
        XCTAssertEqual(VaultCrypto.attachmentContext(id: attachmentID), attachment.context)
    }
    func testIndependentRecoveryDerivationAndEnvelope() throws {
        let corpus = try corpus()
        let recovery = corpus.recovery
        let derived = try VaultCrypto.derive(recovery.phrase, salt: recovery.salt, iterations: recovery.iterations)
        XCTAssertEqual(derived, recovery.derivedKey)
        XCTAssertEqual(VaultCrypto.recoverySecret(derivedKey: derived), recovery.authenticationSecret)
        let wrapped = try XCTUnwrap(corpus.envelopes.first { $0.name == "recovery" })
        let result = try VaultCrypto.recover(
            RecoveryEnvelope(
                salt: recovery.salt.base64EncodedString(), wrappedKey: wrapped.combined.base64EncodedString()),
            phrase: recovery.phrase)
        XCTAssertEqual(result.0, wrapped.plaintext)
        XCTAssertEqual(result.1, recovery.authenticationSecret)
    }
}
