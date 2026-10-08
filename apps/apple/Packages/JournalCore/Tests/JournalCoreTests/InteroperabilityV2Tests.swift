import CryptoKit
import XCTest

@testable import JournalCore

/// Checks the public corpus other clients are written against (protocol/conformance/crypto/encryption-v2.json): password
/// envelopes, the passwordless envelope, the pairing grant and a current record with its image. The expected bytes
/// are fixed in the shared file, so neither this app nor the .NET check can change the protocol and still pass.
final class InteroperabilityV2Tests: XCTestCase {
    private struct Corpus: Decodable {
        struct Envelope: Decodable {
            let salt: String
            let wrappedKey: String
            let iterations: Int
            let formatVersion: Int
            var recovery: RecoveryEnvelope {
                RecoveryEnvelope(
                    salt: salt, wrappedKey: wrappedKey, iterations: iterations, formatVersion: formatVersion)
            }
        }
        struct Recovery: Decodable {
            struct Wrapped: Decodable {
                let context: String
                let envelope: Envelope
            }
            let password: String
            let passwordUTF8: Data
            let salt: Data
            let iterations: Int
            let derivedKey: Data
            let recoverySecret: String
            let vaultKey: Data
            let envelopes: [Wrapped]
        }
        struct Passwordless: Decodable {
            let envelope: Envelope
        }
        struct Normalization: Decodable {
            struct Variant: Decodable {
                let derivedKey: Data
                let recoverySecret: String
                let envelope: Envelope
            }
            let password: String
            let typedUTF8: Data
            let normalizedUTF8: Data
            let salt: Data
            let iterations: Int
            let normalized: Variant
            let exact: Variant
        }
        struct Pairing: Decodable {
            struct Grant: Decodable {
                let masterKey: Data
                let recoveryVersion: Int
                let token: String
            }
            let id: UUID
            let devicePrivateKey: Data
            let devicePublicKey: Data
            let keyCommitment: String
            let approverPrivateKey: Data
            let approverPublicKey: Data
            let checkCode: String
            let sharedSecret: Data
            let grantKey: Data
            let context: String
            let grantPlaintext: Data
            let grant: Grant
            let encryptedGrant: Data
        }
        struct Sealed: Decodable {
            let id: UUID
            let context: String
            let plaintext: Data
            let combined: Data
        }
        struct Expected: Decodable {
            let journalID: UUID
            let title: String
            let date: String
            let modifiedAt: String
            let documentVersion: Int
            let markdown: String
            let imageTypes: [String: String]
        }
        struct Record: Decodable {
            let id: UUID
            let kind: String
            let context: String
            let plaintext: Data
            let combined: Data
            let expected: Expected
        }
        struct Content: Decodable {
            let key: Data
            let record: Record
            let attachment: Sealed
        }
        let corpusVersion: Int
        let recovery: Recovery
        let normalization: Normalization
        let passwordless: Passwordless
        let pairing: Pairing
        let content: Content
    }

    private func corpus() throws -> Corpus {
        let corpus = try Conformance.decode(Corpus.self, "crypto/encryption-v2.json")
        XCTAssertEqual(corpus.corpusVersion, 2)
        return corpus
    }

    /// Fixed nonces exist only in public fixtures; production sealing always uses a fresh nonce.
    private func seal(_ plaintext: Data, key: Data, nonceOf combined: Data, context: String) throws -> Data? {
        try AES.GCM.seal(
            plaintext, using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: combined.prefix(12)),
            authenticating: Data(context.utf8)
        ).combined
    }

    func testPasswordEnvelopesUseTheExactPasswordAndTheirFormatContext() throws {
        let recovery = try corpus().recovery
        // No trimming: the password's UTF-8 bytes, already in NFC, are the PBKDF2 input.
        XCTAssertEqual(Data(recovery.password.utf8), recovery.passwordUTF8)
        XCTAssertEqual(Data(recovery.password.precomposedStringWithCanonicalMapping.utf8), recovery.passwordUTF8)
        let derived = try VaultCrypto.derive(
            recovery.password, salt: recovery.salt, iterations: recovery.iterations, trim: false)
        XCTAssertEqual(derived, recovery.derivedKey)
        XCTAssertEqual(VaultCrypto.recoverySecret(derivedKey: derived), recovery.recoverySecret)
        XCTAssertEqual(recovery.envelopes.map(\.envelope.formatVersion), [2, 3])
        for wrapped in recovery.envelopes {
            let envelope = wrapped.envelope.recovery
            XCTAssertEqual(wrapped.context, "journal:v\(envelope.formatVersion):recovery")
            let combined = try XCTUnwrap(Data(base64Encoded: envelope.wrappedKey))
            XCTAssertEqual(
                try seal(recovery.vaultKey, key: derived, nonceOf: combined, context: wrapped.context), combined)
            let opened = try VaultCrypto.recover(envelope, phrase: recovery.password)
            XCTAssertEqual(opened.0, recovery.vaultKey)
            XCTAssertEqual(opened.1, recovery.recoverySecret)
            XCTAssertEqual(
                try envelope.contentProtection, envelope.formatVersion == 2 ? .encrypted : .plaintext)
        }
    }

    /// Passwords are derived from their NFC form; an envelope made from the exact typed text before that rule still
    /// opens, because that text is tried next.
    func testPasswordsAreNormalizedAndExactEnvelopesStillOpen() throws {
        let corpus = try corpus()
        let vector = corpus.normalization
        XCTAssertEqual(Data(vector.password.utf8), vector.typedUTF8)
        XCTAssertEqual(Data(vector.password.precomposedStringWithCanonicalMapping.utf8), vector.normalizedUTF8)
        XCTAssertNotEqual(vector.typedUTF8, vector.normalizedUTF8)
        let parameters = RecoveryParameters(vector.normalized.envelope.recovery)
        let derivations = try VaultCrypto.recoveryDerivations(vector.password, for: parameters)
        XCTAssertEqual(derivations.map(\.wrappingKey), [vector.normalized.derivedKey, vector.exact.derivedKey])
        XCTAssertEqual(derivations.map(\.secret), [vector.normalized.recoverySecret, vector.exact.recoverySecret])
        for variant in [vector.normalized, vector.exact] {
            let opened = try VaultCrypto.recover(variant.envelope.recovery, phrase: vector.password)
            XCTAssertEqual(opened.0, corpus.recovery.vaultKey)
            XCTAssertEqual(opened.1, variant.recoverySecret)
        }
        // A new envelope for the typed password opens with its normalized form alone.
        let created = try VaultCrypto.makeRecovery(
            masterKey: corpus.recovery.vaultKey, phrase: vector.password, formatVersion: 2)
        let normalized = String(decoding: vector.normalizedUTF8, as: UTF8.self)
        XCTAssertEqual(try VaultCrypto.recoveryDerivations(normalized, for: RecoveryParameters(created.0)).count, 1)
        XCTAssertEqual(try VaultCrypto.recover(created.0, phrase: normalized).1, created.1)
    }

    func testPasswordlessEnvelopeCarriesNoKeyMaterial() throws {
        let fixture = try corpus().passwordless.envelope
        // What this app sends at setup for a library without encryption or password.
        let unprotected = RecoveryEnvelope.unprotected
        XCTAssertEqual(fixture.salt, unprotected.salt)
        XCTAssertEqual(fixture.wrappedKey, unprotected.wrappedKey)
        XCTAssertEqual(fixture.iterations, unprotected.iterations)
        XCTAssertEqual(fixture.formatVersion, unprotected.formatVersion)
        XCTAssertFalse(fixture.recovery.requiresPassword)
        XCTAssertEqual(try fixture.recovery.contentProtection, .plaintext)
    }

    func testPairingGrantMatchesKeyAgreementCheckCodeAndSealing() throws {
        let pairing = try corpus().pairing
        let device = try PairingPrivateKey(rawRepresentation: pairing.devicePrivateKey)
        let approver = try PairingPrivateKey(rawRepresentation: pairing.approverPrivateKey)
        XCTAssertEqual(device.publicKey.rawRepresentation, pairing.devicePublicKey)
        XCTAssertEqual(approver.publicKey.rawRepresentation, pairing.approverPublicKey)
        XCTAssertEqual(PairingCheck.commitment(pairing.devicePublicKey), pairing.keyCommitment)
        XCTAssertEqual(
            PairingCheck.code(
                pairingID: pairing.id, devicePublicKey: pairing.devicePublicKey,
                approverPublicKey: pairing.approverPublicKey),
            pairing.checkCode)
        let shared = try device.sharedSecretFromKeyAgreement(with: approver.publicKey)
        XCTAssertEqual(shared.withUnsafeBytes { Data($0) }, pairing.sharedSecret)
        XCTAssertEqual(
            try PairingCheck.grantKey(privateKey: device, publicKey: approver.publicKey, pairingID: pairing.id),
            pairing.grantKey)
        XCTAssertEqual(
            try PairingCheck.grantKey(privateKey: approver, publicKey: device.publicKey, pairingID: pairing.id),
            pairing.grantKey)
        XCTAssertEqual(pairing.context, "journal:v1:pairing:\(pairing.id.uuidString.lowercased())")
        let sealed = pairing.encryptedGrant.dropFirst(32)
        XCTAssertEqual(pairing.encryptedGrant.prefix(32), pairing.approverPublicKey)
        XCTAssertEqual(
            try seal(pairing.grantPlaintext, key: pairing.grantKey, nonceOf: sealed, context: pairing.context),
            Data(sealed))

        // The new device opens the corpus grant through the app's own path.
        let ticket = PairingTicket(id: pairing.id, code: "123456789", pollToken: "poll", expiresAt: .distantFuture)
        let reveal = PairingReveal(checkCode: pairing.checkCode, approverKey: pairing.approverPublicKey)
        let poll = PairingPoll(
            approved: true, encryptedGrant: pairing.encryptedGrant.base64EncodedString(), deviceId: UUID(),
            approverKey: pairing.approverPublicKey.base64EncodedString())
        let opened = try ServerClient.openPairing(poll, reveal: reveal, ticket: ticket, privateKey: device)
        XCTAssertEqual(opened.masterKey, pairing.grant.masterKey)
        XCTAssertEqual(opened.token, pairing.grant.token)
        XCTAssertEqual(opened.recoveryVersion, pairing.grant.recoveryVersion)

        // The approving device seals the same contents the way the corpus describes.
        XCTAssertEqual(try JournalCoding.encoder().encode(opened), pairing.grantPlaintext)
        let grant = try ServerClient.sealGrant(
            opened, approverPrivateKey: pairing.approverPrivateKey, devicePublicKey: pairing.devicePublicKey,
            pairingID: pairing.id)
        XCTAssertEqual(grant.prefix(32), pairing.approverPublicKey)
        XCTAssertEqual(
            try VaultCrypto.open(grant.dropFirst(32), key: pairing.grantKey, context: pairing.context),
            pairing.grantPlaintext)
    }

    func testRecordAndImageOpenOnlyInTheirOwnContext() throws {
        let corpus = try corpus()
        let content = corpus.content
        // One vault key: unwrapped by the password envelopes and delivered by the pairing grant.
        XCTAssertEqual(content.key, corpus.recovery.vaultKey)
        XCTAssertEqual(content.key, corpus.pairing.grant.masterKey)
        let record = content.record
        let image = content.attachment
        XCTAssertEqual(VaultCrypto.recordContext(id: record.id, kind: record.kind), record.context)
        XCTAssertEqual(VaultCrypto.attachmentContext(id: image.id), image.context)
        for (combined, plaintext, context) in [
            (record.combined, record.plaintext, record.context), (image.combined, image.plaintext, image.context),
        ] {
            XCTAssertEqual(try VaultCrypto.open(combined, key: content.key, context: context), plaintext)
            XCTAssertEqual(try seal(plaintext, key: content.key, nonceOf: combined, context: context), combined)
        }
        XCTAssertThrowsError(try VaultCrypto.open(record.combined, key: content.key, context: image.context))
        XCTAssertThrowsError(try VaultCrypto.open(image.combined, key: content.key, context: record.context))

        let item = try PortableRecord.decode(record.plaintext)
        let expected = record.expected
        XCTAssertEqual(item.id, record.id)
        XCTAssertEqual(item.kind, record.kind)
        XCTAssertEqual(item.journalID, expected.journalID)
        XCTAssertEqual(item.title, expected.title)
        XCTAssertEqual(item.date, try JournalCoding.date(from: expected.date))
        XCTAssertEqual(item.modifiedAt, try JournalCoding.date(from: expected.modifiedAt))
        XCTAssertEqual(item.document.version, expected.documentVersion)
        XCTAssertTrue(item.document.isEditable)
        XCTAssertEqual(item.document.markdown, expected.markdown)
        XCTAssertEqual(item.document.attachmentIDs, [image.id])
        XCTAssertEqual(
            item.document.blocks.first { $0.attachmentID == image.id }?.mediaType,
            expected.imageTypes[image.id.uuidString.lowercased()])
    }
}
