import Foundation
import JournalCore
import os

struct LocalConfiguration: Codable {
    var recovery: RecoveryEnvelope
    var recoveryConfirmed = false
    var storageFolder: String?
    var keyID: String?
    var connectionKeyID: String?
    /// App Lock: the device's own authentication is needed to open the journals (AppLockOperations.swift).
    var appLock: Bool?
    /// Lock when inactive (Mac), in minutes: absent is 30, 0 is Never (InactivityLock.swift).
    var inactivityLockMinutes: Int?
    /// App Lock used a PIN of its own until this device moved to its authentication; cleared at the first unlock.
    var pinRetiredNotice: Bool?
    /// The earlier App Lock PIN. Only read to move App Lock to the device's authentication, then removed.
    var pinSalt: Data?
    var pinHash: Data?
    var useBiometrics: Bool?
    var failedUnlocks: Int?
    var unlockRetryAfter: Date?
    var lastJournalID: UUID?
    var lastEntryID: UUID?
    /// Settings ▸ Default Journal on this device. Nil until chosen, which means the oldest journal in use.
    var defaultJournalID: UUID?
    /// Earlier copies of the library, replaced when connecting to a server or importing an archive. They're removed
    /// once this library has opened (and, when connected, synchronized); an interrupted removal is tried again.
    var supersededLibraries: [SupersededLibrary]?
    // Build 16 to 19 saved `passwordChecked` here; it is no longer used or written, and an old file's value is ignored.
    /// Turning on encryption that hasn't finished (EncryptionOperations.swift).
    var encryptionUpgrade: EncryptionUpgradeMarker?
    /// This Mac stopped syncing with the server earlier Mac builds ran (FormerMacServer.swift); Sync explains it
    /// until the library connects to a server.
    var stoppedSyncingWithFormerMacServer: Bool?
}

extension LocalConfiguration {
    var credentialName: String {
        switch recovery.formatVersion {
        case 1: return "Recovery Key"
        case 3: return "Access Password"
        case 4: return "Recovery Code"
        default: return "Master Password"
        }
    }
    var encrypted: Bool { ![3, 4].contains(recovery.formatVersion) }
    var requiresPassword: Bool { recovery.requiresPassword }
}

extension AppModel {
    /// Libraries created before the key's name was saved found their key by the library's path. Save the name
    /// while the path still finds it, so a later change of path (an iOS update) can't make the key unreachable.
    func rememberKeyAccount(_ account: String) {
        guard configuration?.keyID == nil else { return }
        configuration?.keyID = account
        saveMigratedConfiguration()
    }
    func saveMigratedConfiguration() {
        do { try persistConfiguration() } catch {
            // Opening still works; the next launch tries again.
            Logger(subsystem: "org.privatejournal", category: "configuration").error(
                "Could not save the device key name.")
        }
    }
}
