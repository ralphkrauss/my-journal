import Foundation
import Security
import os

/// Device secrets (vault keys, sync credentials), kept in the Keychain.
///
/// Apps entitled to the data protection keychain (every iOS app, and Mac builds signed with the team's provisioning
/// profile) keep secrets there, where access follows the signing team instead of a per-build approval. A Mac build
/// without that entitlement, such as a Developer ID release, keeps using the login keychain. A secret still in the
/// login keychain is moved the first time it is read by an entitled build (`MigratingSecretStore`). Test processes use
/// memory only, so they never touch a person's keychain.
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
    /// The names of the items the app keeps, found by listing the service, never reading a secret. Erase uses it to
    /// remove what no configuration names (docs/design/build-18-fixes-2026-10-06.md §2.1). Only the data protection
    /// keychain is listed: the login keychain can raise an unlock prompt and, on the Mac, shows other builds' items.
    /// A build without the entitlement, or a keychain with nothing in it, gives an empty list.
    public static func accounts() throws -> [String] { try store.accounts() }
}

protocol SecretStore: Sendable {
    func read(_ account: String) throws -> Data?
    func write(_ data: Data, account: String) throws
    func remove(_ account: String) throws
    /// Every account of the app's service, by name only.
    func accounts() throws -> [String]
}

public enum SecretStoreError: Error, Equatable {
    /// The app isn't entitled to this keychain, for example an unprovisioned Mac build.
    case unavailable
}

/// Prefers the current store; reads fall back to the legacy one and move what they find.
///
/// Whether the current store can be used is learned from the keychain itself, not guessed: without the entitlement,
/// a data protection keychain lookup only reports that nothing was found, while any change is refused with
/// `errSecMissingEntitlement`. From the first refusal on, this process uses the legacy store alone.
///
/// A move copies the secret, reads the copy back, and only then removes the original. If anything before the
/// removal fails, the original stays and the next read tries again. If only the removal fails (macOS lets just the
/// build that created a login keychain item delete it), an identical original stays behind; reads keep preferring
/// the current store and never look at it again, so it can't cause keychain prompts.
struct MigratingSecretStore: SecretStore {
    let current: SecretStore
    let legacy: SecretStore?
    private let currentRefused = OSAllocatedUnfairLock(initialState: false)
    private let log = Logger(subsystem: "org.privatejournal", category: "keychain")

    init(current: SecretStore, legacy: SecretStore?) {
        self.current = current
        self.legacy = legacy
    }

    func read(_ account: String) throws -> Data? {
        guard let legacy else { return try current.read(account) }
        guard currentAvailable else { return try legacy.read(account) }
        do {
            if let data = try current.read(account) { return data }
        } catch SecretStoreError.unavailable {
            markCurrentUnavailable()
            return try legacy.read(account)
        }
        guard let data = try legacy.read(account) else { return nil }
        move(data, account: account, from: legacy)
        return data
    }

    func write(_ data: Data, account: String) throws {
        if currentAvailable || legacy == nil {
            do { return try current.write(data, account: account) } catch SecretStoreError.unavailable {
                markCurrentUnavailable()
            }
        }
        guard let legacy else { throw SecretStoreError.unavailable }
        try legacy.write(data, account: account)
    }

    func remove(_ account: String) throws {
        var removed = false
        if currentAvailable || legacy == nil {
            do {
                try current.remove(account)
                removed = true
            } catch SecretStoreError.unavailable {
                markCurrentUnavailable()
            }
        }
        if let legacy {
            try legacy.remove(account)
            removed = true
        }
        if !removed { throw SecretStoreError.unavailable }
    }

    /// The current store's accounts only: items left in the login keychain are removed by name, never listed.
    func accounts() throws -> [String] {
        guard currentAvailable || legacy == nil else { return [] }
        do { return try current.accounts() } catch SecretStoreError.unavailable {
            markCurrentUnavailable()
            return []
        }
    }

    private var currentAvailable: Bool { !currentRefused.withLock { $0 } }

    private func markCurrentUnavailable() {
        let first = currentRefused.withLock { refused -> Bool in
            let first = !refused
            refused = true
            return first
        }
        if first { log.notice("The data protection keychain isn't available; using the login keychain.") }
    }

    /// Copies a legacy secret into the current store. Whatever fails, the caller still gets the secret, so a failed
    /// move never locks anyone out.
    private func move(_ data: Data, account: String, from legacy: SecretStore) {
        do {
            try current.write(data, account: account)
            guard try current.read(account) == data else {
                // The current store had nothing before this copy, so removing what it holds now loses nothing.
                try? current.remove(account)
                log.error("A secret copied to the data protection keychain didn't read back; the original stays.")
                return
            }
        } catch SecretStoreError.unavailable {
            markCurrentUnavailable()
            return
        } catch {
            log.error(
                "Couldn't copy a secret to the data protection keychain (\(Self.status(of: error), privacy: .public)).")
            return
        }
        do { try legacy.remove(account) } catch {
            log.notice(
                "A moved secret's login keychain original stays (\(Self.status(of: error), privacy: .public)).")
        }
    }

    private static func status(of error: Error) -> Int { (error as NSError).code }
}

struct SystemSecretStore: SecretStore {
    let dataProtection: Bool

    /// Always names the keychain. In an entitled Mac app, a query that leaves it out also reaches the data protection
    /// keychain: removing the login keychain original that way deleted the copy a move had just made.
    func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "org.privatejournal.vault",
            kSecAttrAccount as String: account, kSecUseDataProtectionKeychain as String: dataProtection,
        ]
    }
    static func check(_ status: OSStatus) throws {
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
        try Self.check(status)
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
        try Self.check(status)
    }
    func remove(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        if status == errSecItemNotFound { return }
        try Self.check(status)
    }
    /// Attributes only, so no secret is read and nothing prompts. A keychain the app isn't entitled to reports that
    /// nothing was found or `errSecMissingEntitlement`; both are an empty list.
    func accounts() throws -> [String] {
        var request = query("")
        request[kSecAttrAccount as String] = nil
        request[kSecReturnAttributes as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound || status == errSecMissingEntitlement { return [] }
        try Self.check(status)
        let items = result as? [[String: Any]] ?? []
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}

/// Keeps secrets for the life of the process.
struct MemorySecretStore: SecretStore {
    private let secrets = OSAllocatedUnfairLock<[String: Data]>(initialState: [:])
    func read(_ account: String) throws -> Data? { secrets.withLock { $0[account] } }
    func write(_ data: Data, account: String) throws { secrets.withLock { $0[account] = data } }
    func remove(_ account: String) throws { _ = secrets.withLock { $0.removeValue(forKey: account) } }
    func accounts() throws -> [String] { secrets.withLock { Array($0.keys) } }
}
