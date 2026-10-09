import Foundation
import JournalCore
import LocalAuthentication

/// “Forgot Password?” in Change Password, for journals that exist only on this device (docs/design/
/// 1-1-encryption-and-passwords.md §4.2). The device owner authenticates, then a new master password protects the same
/// vault key without the current one.
extension AppModel {
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
    /// Forgot Password? is offered when both hold.
    var offersForgotPassword: Bool { canSetPasswordWithoutCurrent && Self.canAuthenticateDeviceOwner }

    /// Asks the device owner to authenticate before a new password is set without the current one.
    func authorizePasswordReset() async -> Bool {
        guard canSetPasswordWithoutCurrent else { return false }
        do {
            let context = LAContext()
            guard
                try await context.evaluatePolicy(
                    .deviceOwnerAuthentication, localizedReason: Self.passwordResetReason)
            else { return false }
        } catch { return false }
        passwordResetAuthorizedAt = Date()
        return true
    }
    /// `settings.changePassword.authReason`; on the Mac it completes “My Journal is trying to …”.
    static var passwordResetReason: String {
        #if os(macOS)
            "set a new password for your journals"
        #else
            "Set a new password for your journals"
        #endif
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
        do { try persistConfiguration() } catch {
            configuration = previous
            throw error
        }
        passwordResetAuthorizedAt = nil
    }
}
