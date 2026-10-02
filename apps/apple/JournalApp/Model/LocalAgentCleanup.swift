#if os(macOS)
    import CryptoKit
    import Foundation
    import JournalCore

    /// Removes what the Mac's local agent connections left behind: their grants, activity, connection files, the
    /// bridge's discovery file and their Keychain keys. Agents now connect through a sync server, including this
    /// Mac's own (docs/design/agent-access-simplified.md, section 8).
    enum LocalAgentCleanup {
        static func run(dataDirectory: URL) {
            var folders = [dataDirectory.appendingPathComponent("agent-connections", isDirectory: true)]
            // The person's own library kept them in the app group container; test and custom folders kept their own.
            let library = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PrivateJournal", isDirectory: true)
            if dataDirectory.standardizedFileURL == library.standardizedFileURL, let shared = SharedContainer.url {
                folders.append(shared.appendingPathComponent("agent-connections", isDirectory: true))
            }
            for folder in folders where FileManager.default.fileExists(atPath: folder.path) {
                let digest = SHA256.hash(data: Data(folder.path.utf8)).map { String(format: "%02x", $0) }.joined()
                try? Keychain.remove("agent-" + digest)
                try? Keychain.remove("agent-revision-" + digest)
                try? FileManager.default.removeItem(at: folder)
            }
        }
    }
#endif
