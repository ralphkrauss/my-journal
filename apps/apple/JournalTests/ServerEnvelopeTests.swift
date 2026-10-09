import JournalCore
import XCTest

@testable import Journal

/// Recovering from a server decides from the server's recovery envelope whether the typed text is a password,
/// which never leaves the device, or a one-time server recovery code, which is sent as is. A server must not be
/// able to change that decision, or turn encrypted journals on this device into unencrypted ones.
@MainActor
final class ServerEnvelopeTests: XCTestCase {
    private let password = "correct horse battery staple"

    /// `withEncryptedJournals`: a library with a master password. `unencryptedJournals`: one from an earlier version
    /// (format 4). Neither: a device with no library.
    private func model(withEncryptedJournals: Bool, unencryptedJournals: Bool = false) async throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Envelope-" + UUID().uuidString)
        let model = AppModel(directory: directory)
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            if let account = model.configuration?.keyID { try? Keychain.remove(account) }
            try? FileManager.default.removeItem(at: directory)
        }
        if withEncryptedJournals {
            await model.start(password: password)
            XCTAssertEqual(model.configuration?.recovery.formatVersion, 2)
        } else if unencryptedJournals {
            await model.startLegacyUnencrypted()
            XCTAssertEqual(model.configuration?.recovery.formatVersion, 4)
        }
        return model
    }

    private func server(serving envelope: RecoveryEnvelope) async throws -> FakeJournalServer {
        let encoded = try JournalCoding.encoder().encode(envelope)
        let grant = try JournalCoding.encoder().encode(DeviceGrant(deviceId: UUID(), token: "device-token"))
        return try await FakeJournalServer { request in
            switch (request.method, request.path) {
            case ("GET", "/v1/recovery"): return (200, encoded)
            case ("POST", "/v1/recovery"): return (200, grant)
            default: return (404, Data("{}".utf8))
            }
        }
    }

    private func assertPasswordNeverSent(
        _ server: FakeJournalServer, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertFalse(
            server.requests.contains { String(decoding: $0.body, as: UTF8.self).contains(password) },
            "The password must never reach the server.", file: file, line: line)
    }

    /// Recovers with `phrase` (the password by default). `shown` is the envelope as the server published it, which
    /// a server that keeps its envelope private publishes without the wrapped key (`keepsKey`).
    private func recover(
        _ model: AppModel, from server: FakeJournalServer, uploadLocal: Bool, shown: RecoveryEnvelope?,
        keepsKey: Bool = false, phrase: String? = nil
    ) async -> Error? {
        var parameters = shown.map(RecoveryParameters.init)
        if keepsKey { parameters?.wrappedKey = nil }
        do {
            try await model.recoverServer(
                address: server.address, phrase: phrase ?? password, uploadLocal: uploadLocal, shown: parameters)
            return nil
        } catch { return error }
    }

    /// A server with `private-envelope`: it publishes the envelope without its wrapped key, sends `envelope` with a
    /// new device credential for an accepted secret, and synchronizes an empty library.
    private func privateServer(
        publishing published: RecoveryEnvelope, sending envelope: RecoveryEnvelope, accepting secrets: Set<String>
    )
        async throws -> FakeJournalServer
    {
        var parameters = RecoveryParameters(published)
        parameters.wrappedKey = nil
        let publishedBody = try JournalCoding.encoder().encode(parameters)
        let status = HealthyStatus.json()
        let page = Data(#"{"changes":[],"cursor":0,"hasMore":false}"#.utf8)
        struct Recovered: Encodable {
            let deviceId: UUID
            let token: String
            let envelope: RecoveryEnvelope
        }
        let recovered = try JournalCoding.encoder().encode(
            Recovered(deviceId: UUID(), token: String(repeating: "d", count: 64), envelope: envelope))
        let refused = Data(#"{"status":401,"code":"invalid_recovery_secret"}"#.utf8)
        return try await FakeJournalServer { request in
            switch (request.method, request.path) {
            case ("GET", "/v1/status"): return (200, status)
            case ("GET", "/v1/recovery"): return (200, publishedBody)
            case ("POST", "/v1/recovery"):
                let body = try? JSONSerialization.jsonObject(with: request.body) as? [String: String]
                return secrets.contains(body?["recoverySecret"] ?? "") ? (200, recovered) : (401, refused)
            case ("GET", let path) where path.hasPrefix("/v1/sync/"): return (200, page)
            case ("DELETE", _): return (204, Data())
            default: return (404, Data("{}".utf8))
            }
        }
    }

    private func recoverySecrets(_ server: FakeJournalServer) -> [String] {
        server.requests.filter { $0.method == "POST" && $0.path == "/v1/recovery" }.compactMap {
            (try? JSONSerialization.jsonObject(with: $0.body) as? [String: String])?["recoverySecret"]
        }
    }

    private func closing(_ model: AppModel) {
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            for account in [model.configuration?.keyID, model.configuration?.connectionKeyID].compactMap({ $0 }) {
                try? Keychain.remove(account)
            }
        }
    }

    func testEncryptedJournalsAreNotSentToAnUnencryptedServer() async throws {
        let model = try await model(withEncryptedJournals: true)
        let server = try await server(serving: .unprotected)
        let error = await recover(model, from: server, uploadLocal: true, shown: .unprotected)
        XCTAssertEqual(error as? ServerConnectionError, .encryptionOff)
        XCTAssertFalse(server.requests.contains { $0.method == "POST" })
        assertPasswordNeverSent(server)
        XCTAssertNil(model.connection)
        XCTAssertEqual(model.configuration?.recovery.formatVersion, 2)
    }

    /// A device with no library never starts an unencrypted one by joining a server that holds unencrypted data, for
    /// either unencrypted format (3, with an access password; 4, with none).
    func testADeviceWithNoLibraryIsRefusedByAServerWithUnencryptedData() async throws {
        let access = try VaultCrypto.makeRecovery(
            masterKey: VaultCrypto.generateKey(), phrase: password, formatVersion: 3
        )
        .0
        for envelope in [RecoveryEnvelope.unprotected, access] {
            let model = try await model(withEncryptedJournals: false)
            let server = try await server(serving: envelope)
            let error = await recover(model, from: server, uploadLocal: false, shown: envelope)
            XCTAssertEqual(error as? ServerConnectionError, .encryptionOff)
            XCTAssertFalse(server.requests.contains { $0.method == "POST" }, "Nothing was sent to it.")
            assertPasswordNeverSent(server)
            XCTAssertNil(model.store)
            XCTAssertNil(model.configuration)
        }
    }

    /// The person was asked for a password; the server then answers with an envelope that would send it as is.
    func testServerCannotSwitchToARecoveryCodeAfterAskingForAPassword() async throws {
        let model = try await model(withEncryptedJournals: false)
        let shown = try VaultCrypto.makeRecovery(
            masterKey: VaultCrypto.generateKey(), phrase: password, formatVersion: 2
        ).0
        let server = try await server(serving: .unprotected)
        let error = await recover(model, from: server, uploadLocal: false, shown: shown)
        XCTAssertEqual(error as? ServerConnectionError, .serverChanged)
        XCTAssertFalse(server.requests.contains { $0.method == "POST" })
        assertPasswordNeverSent(server)
    }

    func testOnlyAServerRecoveryCodeIsEverSentAsTyped() async throws {
        let model = try await model(withEncryptedJournals: false, unencryptedJournals: true)
        let server = try await server(serving: .unprotected)
        let error = await recover(model, from: server, uploadLocal: true, shown: .unprotected)
        XCTAssertEqual(error as? ServerConnectionError, .invalidRecoveryCode)
        XCTAssertFalse(server.requests.contains { $0.method == "POST" })
        assertPasswordNeverSent(server)
    }

    /// The server checks the derived secret and only then sends the wrapped key, which opens with the same password.
    func testAServerThatKeepsItsEnvelopePrivateSendsTheKeyOnlyForTheDerivedSecret() async throws {
        let model = try await model(withEncryptedJournals: false)
        closing(model)
        let key = try VaultCrypto.generateKey()
        let (envelope, secret) = try VaultCrypto.makeRecovery(masterKey: key, phrase: password, formatVersion: 2)
        let server = try await privateServer(publishing: envelope, sending: envelope, accepting: [secret])
        let wrong = await recover(
            model, from: server, uploadLocal: false, shown: envelope, keepsKey: true, phrase: "not the password")
        XCTAssertEqual(wrong?.localizedDescription, JournalError.invalidRecoveryKey.localizedDescription)
        XCTAssertNil(model.connection)

        let error = await recover(model, from: server, uploadLocal: false, shown: envelope, keepsKey: true)
        XCTAssertNil(error)
        XCTAssertEqual(recoverySecrets(server).last, secret)
        assertPasswordNeverSent(server)
        XCTAssertEqual(model.masterKey, key)
        XCTAssertEqual(model.configuration?.recovery.wrappedKey, envelope.wrappedKey)
        XCTAssertNotNil(model.connection)
    }

    /// Once the secret is accepted, the envelope must be the one the server published and must open with the password;
    /// otherwise the new device credential is given up and nothing is installed.
    func testAnEnvelopeOtherThanThePublishedOneIsRefusedAfterRecovery() async throws {
        let model = try await model(withEncryptedJournals: false)
        let key = try VaultCrypto.generateKey()
        let (published, secret) = try VaultCrypto.makeRecovery(masterKey: key, phrase: password, formatVersion: 2)
        let other = try VaultCrypto.makeRecovery(masterKey: key, phrase: password, formatVersion: 2).0
        var substituted = published
        substituted.wrappedKey = other.wrappedKey
        for sent in [other, substituted] {
            let server = try await privateServer(publishing: published, sending: sent, accepting: [secret])
            let error = await recover(model, from: server, uploadLocal: false, shown: published, keepsKey: true)
            XCTAssertEqual(error as? ServerConnectionError, .serverChanged)
            XCTAssertTrue(server.requests.contains { $0.method == "DELETE" && $0.path.hasPrefix("/v1/devices/") })
            XCTAssertFalse(server.requests.contains { $0.path.hasPrefix("/v1/sync/") })
            XCTAssertNil(model.connection)
        }
    }

    /// Passwords are derived from their NFC form. One set before that rule with decomposed characters still opens:
    /// its exact text is tried next.
    func testADecomposedPasswordFromBeforeNormalizationStillRecovers() async throws {
        let model = try await model(withEncryptedJournals: false)
        closing(model)
        let typed = "cre\u{0300}me bru\u{0302}le\u{0301}e, s'il vous plai\u{0302}t"
        XCTAssertNotEqual(Array(typed.utf8), Array(typed.precomposedStringWithCanonicalMapping.utf8))
        let key = try VaultCrypto.generateKey()
        let salt = try VaultCrypto.random(16)
        let exact = try VaultCrypto.derive(typed, salt: salt, trim: false)
        let legacy = RecoveryEnvelope(
            salt: salt.base64EncodedString(),
            wrappedKey: try VaultCrypto.seal(key, key: exact, context: "journal:v2:recovery").base64EncodedString(),
            formatVersion: 2)
        let legacySecret = VaultCrypto.recoverySecret(derivedKey: exact)
        let server = try await privateServer(publishing: legacy, sending: legacy, accepting: [legacySecret])
        let error = await recover(
            model, from: server, uploadLocal: false, shown: legacy, keepsKey: true, phrase: typed)
        XCTAssertNil(error)
        let normalized = VaultCrypto.recoverySecret(
            derivedKey: try VaultCrypto.derive(typed.precomposedStringWithCanonicalMapping, salt: salt, trim: false))
        XCTAssertEqual(recoverySecrets(server), [normalized, legacySecret])
        XCTAssertEqual(model.masterKey, key)
    }

    func testAPasswordReachesTheServerOnlyAsItsDerivedSecret() async throws {
        let model = try await model(withEncryptedJournals: false)
        let (envelope, secret) = try VaultCrypto.makeRecovery(
            masterKey: VaultCrypto.generateKey(), phrase: password, formatVersion: 2)
        let server = try await server(serving: envelope)
        // The fake server can't sync, so connecting stops after recovery; only what was sent matters here.
        _ = await recover(model, from: server, uploadLocal: false, shown: envelope)
        let posts = server.requests.filter { $0.method == "POST" && $0.path == "/v1/recovery" }
        XCTAssertEqual(posts.count, 1)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(posts.first).body) as? [String: String])
        XCTAssertEqual(body["recoverySecret"], secret)
        assertPasswordNeverSent(server)
    }
}
