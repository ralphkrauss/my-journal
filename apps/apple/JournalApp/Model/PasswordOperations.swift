import Foundation
import JournalCore

/// Master password changes and password recovery that account for a change made on another device.
extension AppModel {
    /// Verifies the current password (against the server's copy when connected) and, when connected,
    /// replaces the server's envelope. Call `savePasswordChange` next to update this device.
    func preparePasswordChange(current: String, new: String) async throws -> PasswordChange {
        guard !locked, let key = masterKey, let local = configuration?.recovery else { throw JournalError.locked }
        guard local.formatVersion == 2 else { throw PasswordChangeError.unsupported }
        let client = connection == nil ? nil : try connectedClient()
        var envelope = local
        if let client {
            do { envelope = try await client.recoveryEnvelope() } catch { throw PasswordChangeError.failed }
        }
        let verified = envelope
        let change = try await Task.detached {
            try VaultCrypto.changePassword(verified, current: current, new: new, masterKey: key)
        }.value
        try await client?.changePassword(change)
        return change
    }
    func savePasswordChange(_ envelope: RecoveryEnvelope) throws {
        let previous = configuration
        configuration?.recovery = envelope
        // The current password was verified and the new one typed twice.
        configuration?.passwordChecked = true
        do { try persistConfiguration() } catch {
            configuration = previous
            throw PasswordChangeError.notSavedLocally
        }
    }
    /// Tries the saved password envelope, then the server's copy, which is newer if the password was
    /// changed on another device. The server's copy is accepted only if it opens these same journals.
    func recoverKey(_ envelope: RecoveryEnvelope, phrase: String) async throws -> (Data, RecoveryEnvelope) {
        do {
            return (try await Task.detached { try VaultCrypto.recover(envelope, phrase: phrase) }.value.0, envelope)
        } catch JournalError.invalidRecoveryKey {
            guard envelope.formatVersion == 2,
                let data = try? Keychain.read(configuration?.connectionKeyID ?? keyAccount + "-connection"),
                let saved = try? JournalCoding.decoder().decode(SyncConnection.self, from: data),
                let server = try? await ServerClient(address: saved.address, token: saved.token).recoveryEnvelope(),
                server.formatVersion == 2
            else { throw JournalError.invalidRecoveryKey }
            let key = try await Task.detached { try VaultCrypto.recover(server, phrase: phrase) }.value.0
            if let masterKey {
                guard key == masterKey else { throw JournalError.invalidRecoveryKey }
            } else {
                let folder = configuration?.storageFolder.map { directory.appendingPathComponent($0) } ?? directory
                let candidate = try JournalStore(directory: folder, key: key, protection: .encrypted)
                let opened = (try? await candidate.items().isEmpty == false) ?? false
                try? await candidate.close()
                guard opened else { throw JournalError.invalidRecoveryKey }
            }
            return (key, server)
        }
    }
}
