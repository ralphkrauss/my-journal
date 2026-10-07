import Foundation
import JournalCore
import os

/// An earlier copy of the library and its Keychain items, replaced when connecting to a server or importing an
/// archive. Permanent deletion in the current library can't reach it, so it's removed once that library works.
struct SupersededLibrary: Codable, Equatable {
    /// Its folder in the app's data folder; nil for a library kept in the data folder itself.
    var storageFolder: String?
    var keyID: String?
    var connectionKeyID: String?
}

extension AppModel {
    /// The libraries a switch away from `previous` leaves to remove: that library, and any it replaced that aren't
    /// removed yet. They're saved in the same configuration write that switches to the new library.
    /// A new configuration that doesn't keep `previous`'s unfinished encryption copy leaves that copy to remove too
    /// (`includingEncryptionCopy`).
    func librariesSuperseded(
        by previous: LocalConfiguration?, includingEncryptionCopy: Bool = false
    ) -> [SupersededLibrary]? {
        guard let previous else { return nil }
        let library = SupersededLibrary(
            storageFolder: previous.storageFolder, keyID: previous.keyID ?? keyAccount,
            connectionKeyID: previous.connectionKeyID ?? keyAccount + "-connection")
        var superseded = (previous.supersededLibraries ?? []) + [library]
        if includingEncryptionCopy, let upgrade = previous.encryptionUpgrade {
            superseded.append(SupersededLibrary(storageFolder: upgrade.storageFolder, keyID: upgrade.keyID))
        }
        return superseded
    }

    /// Removes earlier copies of the library once the current one has opened and, when it's connected, synchronized
    /// (`synchronized`), so everything they held is on the server too. Call after the current library was read.
    /// Nothing the configuration refers to is removed, and what can't be removed now is tried again later, also
    /// after relaunching.
    func removeSupersededLibraries(synchronized: Bool) {
        guard synchronized || connection == nil, supersededRemoval == nil, store != nil,
            configuration?.supersededLibraries?.isEmpty == false
        else { return }
        supersededRemoval = Task {
            defer { supersededRemoval = nil }
            var removed: [SupersededLibrary] = []
            for library in configuration?.supersededLibraries ?? [] {
                if await remove(library) { removed.append(library) }
            }
            guard !removed.isEmpty else { return }
            let remaining = (configuration?.supersededLibraries ?? []).filter { !removed.contains($0) }
            configuration?.supersededLibraries = remaining.isEmpty ? nil : remaining
            do { try persistConfiguration() } catch {
                // They're removed; the next launch finds nothing left to remove.
                Logger(subsystem: "org.privatejournal", category: "configuration").error(
                    "Could not save the removal of an earlier library copy.")
            }
        }
    }

    /// Removes one earlier library's Keychain items, then its files. Returns whether nothing of it is left to remove.
    private func remove(_ library: SupersededLibrary) async -> Bool {
        guard let configuration else { return false }
        let inUse: Set<String> = [
            configuration.keyID ?? keyAccount, configuration.connectionKeyID ?? keyAccount + "-connection",
        ]
        for account in [library.keyID, library.connectionKeyID].compactMap({ $0 }) where !inUse.contains(account) {
            do { try Keychain.remove(account) } catch { return false }
        }
        let names: [String]
        if let folder = library.storageFolder {
            // Only a library folder the app created, never the current one or anything else in the data folder.
            guard folder != configuration.storageFolder, !folder.contains("/"),
                folder.hasPrefix("vault-") || folder.hasPrefix("import-")
            else { return true }
            names = [folder]
        } else {
            // Libraries from before each had its own folder kept their files in the data folder itself.
            guard configuration.storageFolder != nil else { return true }
            names = ["journal.sqlite", "journal.sqlite-wal", "journal.sqlite-shm", "attachments"]
        }
        let paths = names.map { directory.appendingPathComponent($0) }
        return await Task.detached {
            let manager = FileManager.default
            do {
                for path in paths where manager.fileExists(atPath: path.path) { try manager.removeItem(at: path) }
                return true
            } catch { return false }
        }.value
    }
}
