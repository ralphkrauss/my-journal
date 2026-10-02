import Foundation
import JournalCore
import LocalAuthentication
import os

/// A one-time check, before the first archive export, that the master password is the one the person saved, and
/// “Forgot Password?” for journals that exist only on this device (docs/design/pre-release-ui-2026-09-27.md, item 10).
extension AppModel {
    /// A master-password library, not on a server, whose password hasn't been typed correctly since it was set.
    /// Connecting to a server needs the password, so a library on a server has already passed this check.
    var passwordCheckPending: Bool {
        guard let configuration, configuration.recovery.formatVersion == 2, connection == nil else { return false }
        return configuration.passwordChecked != true
    }
    /// A new password can be set without the current one only while the journals exist only on this device; a
    /// server keeps its own copy of the password.
    var canSetPasswordWithoutCurrent: Bool {
        configuration?.recovery.formatVersion == 2 && connection == nil && !replacingVault && !locked
    }
    /// Whether this device can ask its owner to authenticate: Face ID, Touch ID, or the device passcode or login
    /// password. Without it, a new password can't be set this way.
    static var canAuthenticateDeviceOwner: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Checks `password` against this device's copy of the password envelope; nothing leaves the device. Returns
    /// false for a wrong password.
    func checkPassword(_ password: String) async throws -> Bool {
        guard !locked, let key = masterKey, let envelope = configuration?.recovery, envelope.formatVersion == 2 else {
            throw JournalError.locked
        }
        let opened: Data
        do {
            opened = try await Task.detached { try VaultCrypto.recover(envelope, phrase: password).0 }.value
        } catch JournalError.invalidRecoveryKey { return false }
        guard opened == key, configuration?.recovery.wrappedKey == envelope.wrappedKey else { return false }
        markPasswordChecked()
        return true
    }

    /// Asks the device owner to authenticate before a new password is set without the current one.
    func authorizePasswordReset() async -> Bool {
        guard canSetPasswordWithoutCurrent else { return false }
        do {
            let context = LAContext()
            guard
                try await context.evaluatePolicy(
                    .deviceOwnerAuthentication, localizedReason: "set a new password for your journals")
            else { return false }
        } catch { return false }
        passwordResetAuthorizedAt = Date()
        return true
    }

    /// Protects the same vault key with a new master password, without the current one. The journals stay encrypted
    /// as they are and nothing is re-encrypted; archives exported earlier still need the old password. Only for
    /// journals that exist only on this device, and only just after the device owner authenticated.
    func setPasswordWithoutCurrent(_ new: String) async throws {
        guard let authorized = passwordResetAuthorizedAt, Date().timeIntervalSince(authorized) < 300 else {
            throw JournalError.locked
        }
        guard canSetPasswordWithoutCurrent, let key = masterKey else { throw PasswordChangeError.unsupported }
        guard new.count >= VaultCrypto.minimumPasswordLength else { throw PasswordChangeError.tooShort }
        let envelope = try await Task.detached {
            try VaultCrypto.makeRecovery(masterKey: key, phrase: new, formatVersion: 2).0
        }.value
        // Locking, a server connection or another library while the key was protected: set nothing.
        guard canSetPasswordWithoutCurrent, masterKey == key else { throw PasswordChangeError.unsupported }
        let previous = configuration
        configuration?.recovery = envelope
        configuration?.passwordChecked = true
        do { try persistConfiguration() } catch {
            configuration = previous
            throw error
        }
        passwordResetAuthorizedAt = nil
    }

    private func markPasswordChecked() {
        configuration?.passwordChecked = true
        do { try persistConfiguration() } catch {
            // The export continues; the next launch asks again.
            Logger(subsystem: "org.privatejournal", category: "configuration").error(
                "Could not save the password check.")
        }
    }
}
