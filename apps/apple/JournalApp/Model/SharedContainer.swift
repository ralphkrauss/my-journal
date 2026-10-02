#if os(macOS)
    import Foundation
    import Security

    /// The app group container, where earlier versions kept local agent connections (LocalAgentCleanup removes
    /// them). The group comes from this process's own entitlements; a build without it (an unsandboxed development
    /// copy) has none.
    enum SharedContainer {
        static let url: URL? = {
            guard let task = SecTaskCreateFromSelf(nil),
                let value = SecTaskCopyValueForEntitlement(
                    task, "com.apple.security.application-groups" as CFString, nil),
                let group = (value as? [String])?.first
            else { return nil }
            return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        }()
    }
#endif
