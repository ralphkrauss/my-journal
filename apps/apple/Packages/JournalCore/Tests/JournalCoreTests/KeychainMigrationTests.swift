import Security
import XCTest
import os

@testable import JournalCore

/// The vault key lives only on the device; moving it between keychains must never lose it or lock anyone out.
final class KeychainMigrationTests: XCTestCase {
    /// A keychain in memory that answers with the system's status codes, mapped to errors as the real store maps them.
    private final class FakeKeychain: SecretStore {
        enum Operation: Hashable { case read, write, remove }
        private struct State {
            var items: [String: Data] = [:]
            var failures: [Operation: OSStatus] = [:]
            var attempts: [Operation: Int] = [:]
        }
        private let state = OSAllocatedUnfairLock(initialState: State())

        /// What macOS answers a build without the data protection keychain entitlement: lookups find nothing, and
        /// every change is refused (measured with an Apple Development-signed process without entitlements).
        static func withoutEntitlement() -> FakeKeychain {
            let keychain = FakeKeychain()
            keychain.fail(.read, with: errSecItemNotFound)
            keychain.fail(.write, with: errSecMissingEntitlement)
            keychain.fail(.remove, with: errSecMissingEntitlement)
            return keychain
        }

        func attempts(_ operation: Operation) -> Int { state.withLock { $0.attempts[operation] ?? 0 } }

        func fail(_ operation: Operation, with status: OSStatus?) {
            state.withLock { $0.failures[operation] = status }
        }

        func read(_ account: String) throws -> Data? {
            let (status, data) = state.withLock { state in
                state.attempts[.read, default: 0] += 1
                return (state.failures[.read] ?? errSecSuccess, state.items[account])
            }
            if status == errSecItemNotFound { return nil }
            try SystemSecretStore.check(status)
            return data
        }

        func write(_ data: Data, account: String) throws {
            let status = state.withLock { state -> OSStatus in
                state.attempts[.write, default: 0] += 1
                guard let failure = state.failures[.write] else {
                    state.items[account] = data
                    return errSecSuccess
                }
                return failure
            }
            try SystemSecretStore.check(status)
        }

        func remove(_ account: String) throws {
            let status = state.withLock { state -> OSStatus in
                state.attempts[.remove, default: 0] += 1
                guard let failure = state.failures[.remove] else {
                    state.items[account] = nil
                    return errSecSuccess
                }
                return failure
            }
            try SystemSecretStore.check(status)
        }
    }

    private let key = Data("vault key".utf8)

    func testWithoutTheEntitlementSecretsStayInTheLoginKeychainAcrossLaunches() throws {
        let current = FakeKeychain.withoutEntitlement()
        let legacy = MemorySecretStore()
        try legacy.write(key, account: "vault")
        for _ in 1...2 {
            let launch = MigratingSecretStore(current: current, legacy: legacy)
            XCTAssertEqual(try launch.read("vault"), key, "A key in the login keychain still opens the journals.")
            XCTAssertEqual(try launch.read("vault"), key)
        }
        XCTAssertEqual(current.attempts(.write), 2, "Each launch learns from one refusal, then stops trying.")
        XCTAssertEqual(try legacy.read("vault"), key)

        let launch = MigratingSecretStore(current: current, legacy: legacy)
        let connection = Data("connection".utf8)
        try launch.write(connection, account: "connection")
        XCTAssertEqual(try MigratingSecretStore(current: current, legacy: legacy).read("connection"), connection)
        try launch.remove("connection")
        XCTAssertNil(try launch.read("connection"))
        XCTAssertEqual(try launch.read("vault"), key)
    }

    func testReadingMovesALegacySecretOnceAndPrefersTheCurrentKeychain() throws {
        let current = FakeKeychain()
        let legacy = MemorySecretStore()
        try legacy.write(key, account: "vault")
        let store = MigratingSecretStore(current: current, legacy: legacy)
        XCTAssertEqual(try store.read("vault"), key)
        XCTAssertEqual(try current.read("vault"), key)
        XCTAssertNil(try legacy.read("vault"), "The moved secret doesn't stay behind in the login keychain.")

        let other = Data("other key".utf8)
        try legacy.write(other, account: "vault")
        XCTAssertEqual(try MigratingSecretStore(current: current, legacy: legacy).read("vault"), key)
        XCTAssertEqual(try legacy.read("vault"), other, "A login keychain secret that differs is never removed.")
    }

    func testAFailedCopyKeepsTheLegacySecretAndTheNextLaunchMovesIt() throws {
        let current = FakeKeychain()
        current.fail(.write, with: errSecInteractionNotAllowed)
        let legacy = MemorySecretStore()
        try legacy.write(key, account: "vault")
        XCTAssertEqual(try MigratingSecretStore(current: current, legacy: legacy).read("vault"), key)
        XCTAssertEqual(try legacy.read("vault"), key)
        XCTAssertNil(try current.read("vault"))

        current.fail(.write, with: nil)
        XCTAssertEqual(try MigratingSecretStore(current: current, legacy: legacy).read("vault"), key)
        XCTAssertEqual(try current.read("vault"), key)
        XCTAssertNil(try legacy.read("vault"))
    }

    func testAnOriginalThatCantBeRemovedLeavesTheMovedSecretInUse() throws {
        let current = FakeKeychain()
        let legacy = FakeKeychain()
        try legacy.write(key, account: "vault")
        // macOS lets only the build that created a login keychain item delete it.
        legacy.fail(.remove, with: errSecInvalidOwnerEdit)
        XCTAssertEqual(try MigratingSecretStore(current: current, legacy: legacy).read("vault"), key)
        XCTAssertEqual(try MigratingSecretStore(current: current, legacy: legacy).read("vault"), key)
        XCTAssertEqual(legacy.attempts(.read), 1, "Later launches use the moved copy and leave the original alone.")
        XCTAssertEqual(try current.read("vault"), key)
        XCTAssertEqual(try legacy.read("vault"), key)
    }

    /// In an entitled Mac app, a query without the keychain named also reaches the data protection keychain, so
    /// removing the login keychain original deleted the copy just moved (seen in a team-signed build).
    func testTheLoginKeychainQueryNeverReachesTheDataProtectionKeychain() {
        let query = SystemSecretStore(dataProtection: false).query("vault")
        XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, false)
        XCTAssertEqual(
            SystemSecretStore(dataProtection: true).query("vault")[kSecUseDataProtectionKeychain as String] as? Bool,
            true)
    }

    func testRemovingClearsBothKeychains() throws {
        let current = FakeKeychain()
        let legacy = MemorySecretStore()
        try current.write(Data("new".utf8), account: "vault")
        try legacy.write(Data("old".utf8), account: "vault")
        try MigratingSecretStore(current: current, legacy: legacy).remove("vault")
        XCTAssertNil(try current.read("vault"))
        XCTAssertNil(try legacy.read("vault"))
    }
}
