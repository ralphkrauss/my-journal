#if os(macOS)
    import Security
    import XCTest

    /// The sandboxed app keeps device keys in the data protection keychain, with the same query `Keychain` uses.
    /// macOS refuses that keychain when the signature claims an entitlement its provisioning profile doesn't
    /// authorize, such as an app group. The app would then fall back to the login keychain, which asks for the
    /// keychain password after each differently signed build.
    final class SandboxKeychainTests: XCTestCase {
        private static func query(_ account: String) -> [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "org.privatejournal.vault",
                kSecAttrAccount as String: account, kSecUseDataProtectionKeychain as String: true,
            ]
        }
        func testDataProtectionKeychainAcceptsTheSandboxedAppsSecrets() throws {
            let account = "sandbox-test-" + UUID().uuidString
            let query = Self.query(account)
            let secret = Data("sandbox".utf8)
            let added = SecItemAdd(
                query.merging([
                    kSecValueData as String: secret,
                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                ]) { _, new in new } as CFDictionary, nil)
            XCTAssertEqual(added, errSecSuccess, "errSecMissingEntitlement (-34018) means the profile doesn't cover it")
            addTeardownBlock { SecItemDelete(Self.query(account) as CFDictionary) }
            var found: CFTypeRef?
            let read = SecItemCopyMatching(
                query.merging([kSecReturnData as String: true, kSecReturnAttributes as String: true]) { _, new in new }
                    as CFDictionary, &found)
            XCTAssertEqual(read, errSecSuccess)
            let attributes = try XCTUnwrap(found as? [String: Any])
            XCTAssertEqual(attributes[kSecValueData as String] as? Data, secret)
            let group = try XCTUnwrap(attributes[kSecAttrAccessGroup as String] as? String)
            XCTAssertTrue(group.hasSuffix(".org.privatejournal.vault"), group)
        }
    }
#endif
