import Foundation
import JournalCore
import os

/// What erasing this device's journals removes, by exact name, fixed while writing is paused and before the erase
/// commits (docs/design/erase-device-2026-10-04.md §3, §5). It is saved in the erase's own folder, so an interrupted
/// erase is finished from it alone, and nothing is ever chosen by a name prefix afterwards.
struct ErasureList: Codable, Equatable {
    /// Folders and files in the data folder.
    var names: [String] = []
    /// Keychain accounts, by their exact names.
    var accounts: [String] = []
    /// Export Archive's temporary copies, outside the data folder.
    var temporaryFiles: [URL] = []
    /// Launches that couldn't remove every Keychain item; after `LocalErasure.maximumAttempts` the rest is left.
    var attempts = 0
}

/// The files of Erase Journals and Settings. The configuration is the commit point, as for importing and connecting:
/// a library exists for the app exactly when `configuration.json` names it. Moving it into a new `erased-` folder
/// commits the erase; everything else follows from the list saved beside it.
enum LocalErasure {
    static let prefix = "erased-"
    static let configurationName = "configuration.json"
    static let listName = "erasure.json"
    static let maximumAttempts = 3
    private static let log = Logger(subsystem: "org.privatejournal", category: "erase")

    /// Commits the erase: a new erased folder holding the list, then the configuration moved into it with one rename.
    /// Throws, leaving nothing behind and the library as it was, when any of it fails.
    static func commit(_ list: ErasureList, in directory: URL) throws -> URL {
        let manager = FileManager.default
        let folder = directory.appendingPathComponent(prefix + UUID().uuidString.lowercased(), isDirectory: true)
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: false)
            try JournalCoding.encoder().encode(list).write(
                to: folder.appendingPathComponent(listName), options: .atomic)
            try manager.moveItem(
                at: directory.appendingPathComponent(configurationName),
                to: folder.appendingPathComponent(configurationName))
        } catch {
            try? manager.removeItem(at: folder)
            throw error
        }
        return folder
    }

    /// Removes the listed Keychain items, except `protected` ones. Returns whether none is left.
    static func removeAccounts(_ list: ErasureList, protected: Set<String>) -> Bool {
        var removed = true
        for account in Set(list.accounts).subtracting(protected).sorted() {
            do { try Keychain.remove(account) } catch { removed = false }
        }
        if !removed { log.error("A Keychain item of an erased library couldn't be removed.") }
        return removed
    }

    /// Moves what the list names, and is still in the data folder, into the erased folder; `protected` names (the
    /// current library's) never move.
    static func moveListed(_ list: ErasureList, from directory: URL, into folder: URL, protected: Set<String>) {
        let manager = FileManager.default
        for name in Set(list.names).subtracting(protected).sorted() where isMovable(name) {
            let source = directory.appendingPathComponent(name)
            guard manager.fileExists(atPath: source.path) else { continue }
            do { try manager.moveItem(at: source, to: folder.appendingPathComponent(name)) } catch {
                log.error("A file of an erased library couldn't be moved.")
            }
        }
    }

    /// A name the app gives a library's files in its data folder. Never a path, the configuration, an erase's own
    /// folder, or what the server earlier Mac builds ran left behind, which may hold the only copy of changes from
    /// other devices (docs/design/client-only-mac-lists-markdown-2026-10-05.md §1.2).
    static func isMovable(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.hasPrefix(".") && !name.hasPrefix(prefix)
            && !name.hasPrefix(FormerMacServer.filePrefix) && name != configurationName
    }

    /// Deletes what the erased folder holds and the temporary copies; the folder itself, with the configuration and
    /// the list, goes only once its Keychain items are gone (`keysRemoved`), so a later launch can try them again.
    /// Runs off the main actor.
    static func delete(_ folder: URL, list: ErasureList, keysRemoved: Bool) {
        let manager = FileManager.default
        for file in list.temporaryFiles { try? manager.removeItem(at: file) }
        if keysRemoved || list.attempts >= maximumAttempts {
            do { try manager.removeItem(at: folder) } catch { log.error("An erased library couldn't be deleted.") }
            return
        }
        let kept: Set<String> = [configurationName, listName]
        let contents = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in contents where !kept.contains(name) {
            do { try manager.removeItem(at: folder.appendingPathComponent(name)) } catch {
                log.error("A file of an erased library couldn't be deleted.")
            }
        }
    }

    /// Finishes erases an earlier run left (§5, step 7), before anything is loaded: an erase that didn't commit
    /// leaves only its folder; one that did is finished from its list. `protectedAccounts` and `protectedNames` are
    /// the current library's, which are never removed. Returns the folders to delete off the main actor, with their
    /// lists and whether their Keychain items are gone.
    static func leftovers(in directory: URL, protectedAccounts: Set<String>, protectedNames: Set<String>)
        -> [(folder: URL, list: ErasureList, keysRemoved: Bool)]
    {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
        var result: [(folder: URL, list: ErasureList, keysRemoved: Bool)] = []
        for name in names.sorted() where name.hasPrefix(prefix) {
            let folder = directory.appendingPathComponent(name, isDirectory: true)
            guard manager.fileExists(atPath: folder.appendingPathComponent(configurationName).path),
                let data = try? Data(contentsOf: folder.appendingPathComponent(listName)),
                var list = try? JournalCoding.decoder().decode(ErasureList.self, from: data)
            else {
                // Never committed, or nothing left to finish: the library it was for is as it was.
                result.append((folder, ErasureList(attempts: maximumAttempts), true))
                continue
            }
            list.attempts += 1
            let keysRemoved = removeAccounts(list, protected: protectedAccounts)
            if !keysRemoved, list.attempts < maximumAttempts,
                let updated = try? JournalCoding.encoder().encode(list)
            {
                try? updated.write(to: folder.appendingPathComponent(listName), options: .atomic)
            }
            moveListed(list, from: directory, into: folder, protected: protectedNames)
            result.append((folder, list, keysRemoved))
        }
        return result
    }
}
