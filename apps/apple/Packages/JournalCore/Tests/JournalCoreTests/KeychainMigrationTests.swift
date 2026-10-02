import XCTest

@testable import JournalCore

/// The vault key lives only on the device; moving it between keychains must never lose it.
final class KeychainMigrationTests: XCTestCase {
    private struct Unavailable: SecretStore {
        func read(_ account: String) throws -> Data? { throw SecretStoreError.unavailable }
        func write(_ data: Data, account: String) throws { throw SecretStoreError.unavailable }
        func remove(_ account: String) throws { throw SecretStoreError.unavailable }
    }
    private struct FailingWrites: SecretStore {
        func read(_ account: String) throws -> Data? { nil }
        func write(_ data: Data, account: String) throws { throw CocoaError(.fileWriteUnknown) }
        func remove(_ account: String) throws {}
    }

    func testReadingMovesALegacySecretOnceAndPrefersTheCurrentKeychain() throws {
        let current = MemorySecretStore()
        let legacy = MemorySecretStore()
        let key = Data("vault key".utf8)
        try legacy.write(key, account: "vault")
        let store = MigratingSecretStore(current: current, legacy: legacy)
        XCTAssertEqual(try store.read("vault"), key)
        XCTAssertEqual(try current.read("vault"), key)
        XCTAssertNil(try legacy.read("vault"), "The moved secret doesn't stay behind in the login keychain.")
        try legacy.write(Data("stale".utf8), account: "vault")
        XCTAssertEqual(try store.read("vault"), key)
    }

    func testAFailedCopyKeepsTheLegacySecret() throws {
        let legacy = MemorySecretStore()
        let key = Data("vault key".utf8)
        try legacy.write(key, account: "vault")
        let store = MigratingSecretStore(current: FailingWrites(), legacy: legacy)
        XCTAssertThrowsError(try store.read("vault"))
        XCTAssertEqual(try legacy.read("vault"), key)
    }

    func testWithoutTheEntitlementSecretsStayInTheLoginKeychain() throws {
        let legacy = MemorySecretStore()
        let store = MigratingSecretStore(current: Unavailable(), legacy: legacy)
        let key = Data("vault key".utf8)
        try store.write(key, account: "vault")
        XCTAssertEqual(try legacy.read("vault"), key)
        XCTAssertEqual(try store.read("vault"), key)
        try store.remove("vault")
        XCTAssertNil(try store.read("vault"))
    }

    func testRemovingClearsBothKeychains() throws {
        let current = MemorySecretStore()
        let legacy = MemorySecretStore()
        try current.write(Data("new".utf8), account: "vault")
        try legacy.write(Data("old".utf8), account: "vault")
        try MigratingSecretStore(current: current, legacy: legacy).remove("vault")
        XCTAssertNil(try current.read("vault"))
        XCTAssertNil(try legacy.read("vault"))
    }
}
