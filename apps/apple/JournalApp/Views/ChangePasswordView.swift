import JournalCore
import SwiftUI

/// "Change Password…" for libraries protected by a master password; renders nothing otherwise. Forgot Password? is in
/// the sheet (docs/design/1-1-encryption-and-passwords.md §4).
/// Intended as a row in Settings ▸ Privacy ▸ Encryption.
struct ChangePasswordButton: View {
    @EnvironmentObject private var model: AppModel
    @State private var presented = false
    var body: some View {
        if model.configuration?.recovery.formatVersion == 2 {
            Button("Change Password…") { presented = true }
                .disabled(model.locked)
                .sheet(isPresented: $presented) { ChangePasswordView() }
        }
    }
}

struct ChangePasswordView: View {
    private enum Field { case current, new, confirmation }
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var confirmation = ""
    @State private var confirmationVisited = false
    @State private var busy = false
    @State private var failure: PasswordChangeError?
    @State private var message: String?
    /// Set when the server has the new password but saving it on this device failed.
    @State private var unsaved: RecoveryEnvelope?
    @State private var retryFailed = false
    /// The device owner authenticated: the new password is set without the current one (Forgot Password?).
    @State private var forgotten = false
    @FocusState private var focus: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        "Use your new password to recover your journals on a new device. Backups and archives made earlier still use your current password."
                    ).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if forgotten {
                    Section {
                        Text(
                            "Your journals are only on this device, so you can set a new password without the current one. Archives you exported before still need the old password."
                        ).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Section {
                        SecureField("Current Password", text: $current).passwordAutofill()
                            .focused($focus, equals: .current).submitLabel(.next)
                            .onSubmit { focus = .new }
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            if failure == .incorrectPassword {
                                errorLabel(PasswordChangeError.incorrectPassword.localizedDescription)
                            }
                            // Only journals that exist only on this device can get a new password without the old
                            // one, and only after the device owner authenticated.
                            if model.offersForgotPassword {
                                Button("Forgot Password?") { forgotPassword() }
                                    .buttonStyle(.borderless).disabled(busy)
                            }
                        }
                    }
                }
                Section {
                    SecureField("New Password", text: $new).passwordAutofill(creating: true)
                        .focused($focus, equals: .new).submitLabel(.next)
                        .onSubmit { focus = .confirmation }
                    SecureField("Confirm New Password", text: $confirmation).passwordAutofill(creating: true)
                        .focused($focus, equals: .confirmation).submitLabel(.done)
                        .onSubmit { if canChange { change() } }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if showsMismatch { errorLabel("The passwords don’t match.") }
                        if let message { errorLabel(message) }
                        if busy { ProgressView("Changing Password…").controlSize(.small) }
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(busy || unsaved != nil)
            .navigationTitle("Change Password")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }.disabled(busy || (unsaved != nil && !retryFailed))
                }
                ToolbarItem(placement: .confirmationAction) {
                    if unsaved != nil {
                        Button("Try Again") { retrySave() }.disabled(busy)
                    } else {
                        Button("Change") { change() }.disabled(!canChange)
                    }
                }
            }
            .onValueChange(of: focus) { field in
                if field != .confirmation && !confirmation.isEmpty { confirmationVisited = true }
            }
        }
        .interactiveDismissDisabled(busy || unsaved != nil)
        .onAppear { focus = .current }
        // The authorization lasts one use and is forgotten when the sheet closes.
        .onDisappear { model.passwordResetAuthorizedAt = nil }
        .onValueChange(of: model.locked) { if $0, unsaved == nil { dismiss() } }
        #if os(macOS)
            .frame(width: 440)
            .frame(minHeight: 400)
        #endif
    }

    private var showsMismatch: Bool {
        !confirmation.isEmpty && confirmation != new && (confirmationVisited || confirmation.count >= new.count)
    }
    private var canChange: Bool {
        !busy && !model.locked && (forgotten || !current.isEmpty) && new.count >= VaultCrypto.minimumPasswordLength
            && new == confirmation
    }
    private func errorLabel(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle").foregroundStyle(.red)
    }
    private func change() {
        guard canChange else { return }
        busy = true
        failure = nil
        message = nil
        let current = current
        let new = new
        Task {
            defer { busy = false }
            if forgotten {
                await setWithoutCurrent(new)
                return
            }
            do {
                let change = try await model.preparePasswordChange(current: current, new: new)
                unsaved = change.envelope
                try model.savePasswordChange(change.envelope)
                finish()
            } catch { show(error) }
        }
    }
    /// Forgot Password?: asks the device's owner to authenticate. Cancelled or failed, nothing changes and nothing is
    /// said.
    private func forgotPassword() {
        Task {
            guard await model.authorizePasswordReset() else { return }
            current = ""
            failure = nil
            message = nil
            forgotten = true
            focus = .new
            announceForAccessibility("Set a new password for your journals.")
        }
    }
    private func setWithoutCurrent(_ new: String) async {
        do {
            try await model.setPasswordWithoutCurrent(new)
            finish()
        } catch {
            message = "Couldn’t set a new password. Your current password still works."
            announceForAccessibility(message ?? "")
        }
    }
    private func retrySave() {
        guard let unsaved else { return }
        do {
            try model.savePasswordChange(unsaved)
            finish()
        } catch {
            retryFailed = true
            message =
                "Your password was changed on your server but not on this device. Free up space, then try again."
            announceForAccessibility(message ?? "")
        }
    }
    private func finish() {
        current = ""
        new = ""
        confirmation = ""
        unsaved = nil
        dismiss()
    }
    private func show(_ error: Error) {
        let known = error as? PasswordChangeError
        failure = known
        if known == .incorrectPassword {
            focus = .current
            message = nil
        } else if known == nil, !(error is JournalError), !(error is ServerRefusal) {
            message = PasswordChangeError.failed.localizedDescription
        } else {
            message = error.shown(.saving)
        }
        announceForAccessibility(message ?? error.shown(.saving))
    }
}
