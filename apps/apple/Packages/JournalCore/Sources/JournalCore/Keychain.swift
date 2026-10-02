import Foundation
import Security
import os

/// Device secrets (vault keys, sync credentials), kept in the Keychain.
///
/// Apps entitled to the data protection keychain (every iOS app, and Mac builds signed with the team's provisioning
/// profile) keep secrets there, where access follows the signing team instead of a per-build approval. A Mac build
/// without that entitlement, such as a Developer ID release, keeps using the login keychain. A secret still in the
/// login keychain is moved the first time it is read by an entitled build. Test processes use memory only, so they
/// never touch a person's keychain.
public enum Keychain {
    static let store: SecretStore =
        NSClassFromString("XCTestCase") != nil
        ? MemorySecretStore()
        : MigratingSecretStore(current: SystemSecretStore(dataProtection: true), legacy: legacyStore)
    private static var legacyStore: SecretStore? {
        #if os(macOS)
            SystemSecretStore(dataProtection: false)
        #else
            nil
        #endif
    }
    public static func read(_ account: String) throws -> Data? { try store.read(account) }
    public static func write(_ data: Data, account: String) throws { try store.write(data, account: account) }
    public static func remove(_ account: String) throws { try store.remove(account) }
}

protocol SecretStore: Sendable {
    func read(_ account: String) throws -> Data?
    func write(_ data: Data, account: String) throws
    func remove(_ account: String) throws
}

enum SecretStoreError: Error, Equatable {
    /// The app isn't entitled to this keychain, for example an unprovisioned Mac build.
    case unavailable
}

/// Prefers the current store; reads fall back to the legacy one and move what they find.
struct MigratingSecretStore: SecretStore {
    let current: SecretStore
    let legacy: SecretStore?

    func read(_ account: String) throws -> Data? {
        let currentAvailable: Bool
        do {
            if let data = try current.read(account) { return data }
            currentAvailable = true
        } catch SecretStoreError.unavailable {
            currentAvailable = false
        }
        guard let legacy, let data = try legacy.read(account) else { return nil }
        if currentAvailable {
            // Copy first and remove the old item only once the copy exists, so the secret is never lost.
            try current.write(data, account: account)
            try? legacy.remove(account)
        }
        return data
    }
    func write(_ data: Data, account: String) throws {
        do { try current.write(data, account: account) } catch SecretStoreError.unavailable {
            guard let legacy else { throw SecretStoreError.unavailable }
            try legacy.write(data, account: account)
        }
    }
    func remove(_ account: String) throws {
        var removed = false
        do {
            try current.remove(account)
            removed = true
        } catch SecretStoreError.unavailable {}
        if let legacy {
            try legacy.remove(account)
            removed = true
        }
        if !removed { throw SecretStoreError.unavailable }
    }
}

struct SystemSecretStore: SecretStore {
    let dataProtection: Bool

    private func query(_ account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "org.privatejournal.vault",
            kSecAttrAccount as String: account,
        ]
        if dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
        return query
    }
    private func check(_ status: OSStatus) throws {
        if status == errSecMissingEntitlement { throw SecretStoreError.unavailable }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
    func read(_ account: String) throws -> Data? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        return result as? Data
    }
    func write(_ data: Data, account: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        var status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query(account).merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        try check(status)
    }
    func remove(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        if status == errSecItemNotFound { return }
        try check(status)
    }
}

/// Keeps secrets for the life of the process.
struct MemorySecretStore: SecretStore {
    private let secrets = OSAllocatedUnfairLock<[String: Data]>(initialState: [:])
    func read(_ account: String) throws -> Data? { secrets.withLock { $0[account] } }
    func write(_ data: Data, account: String) throws { secrets.withLock { $0[account] = data } }
    func remove(_ account: String) throws { _ = secrets.withLock { $0.removeValue(forKey: account) } }
}
