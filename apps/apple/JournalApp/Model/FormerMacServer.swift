import Foundation
import os

/// The sync server Mac builds before build 17 could run themselves ("Use This Mac"), since removed
/// (docs/design/client-only-mac-lists-markdown-2026-10-05.md §1.2). Its files stay in the data folder: they may hold
/// the only copy of changes other devices sent, so neither this nor Erase removes them.
enum FormerMacServer {
    /// Every file the server left starts with this: `local-server.json`, `local-server-process.json`,
    /// `local-server.log`, `local-server-data`, and the marker below.
    static let filePrefix = "local-server"
    /// The address libraries connected to it used.
    static let address = "http://127.0.0.1:46371"
    static let settingsName = "local-server.json"
    /// Written once the check below has run, so reconnecting to the same address later never stops syncing again.
    static let markerName = "local-server-retired"
}

#if os(macOS)
    extension AppModel {
        /// Once, when the library opens and before it first syncs: a library connected to the removed server stops
        /// syncing, as Stop Syncing does, keeping everything on this Mac. Nothing answers at that address, so its
        /// access isn't given up there.
        func retireFormerMacServer() {
            let manager = FileManager.default
            let marker = directory.appendingPathComponent(FormerMacServer.markerName)
            guard manager.fileExists(atPath: directory.appendingPathComponent(FormerMacServer.settingsName).path),
                !manager.fileExists(atPath: marker.path)
            else { return }
            if connection?.address == FormerMacServer.address {
                stopSyncing(revoking: false)
                if connection == nil {
                    configuration?.stoppedSyncingWithFormerMacServer = true
                    saveMigratedConfiguration()
                }
            }
            do { try Data().write(to: marker, options: .withoutOverwriting) } catch {
                Logger(subsystem: "org.privatejournal", category: "configuration").error(
                    "Could not record that the former server was checked.")
            }
        }

        /// Whether the old server's files are still in the data folder, which Erase leaves.
        var formerMacServerFilesExist: Bool {
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(FormerMacServer.settingsName).path)
                || FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent(FormerMacServer.filePrefix + "-data").path)
        }
    }
#endif
