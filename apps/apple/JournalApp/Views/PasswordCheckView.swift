import JournalCore
import SwiftUI

/// Before the first archive export: checks that the master password is the one the person saved, since the archive
/// can't be opened without it. Never required: Not Now continues the export and asks again next time.
struct PasswordCheckView: View {
    private enum Field { case password }
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    /// Called when the export should continue: the password was right, a new one was set, or the person chose
    /// Not Now.
    let proceed: () -> Void
    @State private var password = ""
    @State private var wrong = false
    @State private var checking = false
    @State private var setting = false
    @FocusState private var focus: Field?

    var body: some View {
        NavigationStack {
            Group {
                if setting { NewPasswordForm(cancel: returnToCheck, done: finish) } else { check }
            }
            .formStyle(.grouped)
            #if os(iOS)
                // Both titles are too long for the bar between two buttons on iPhone.
                .navigationBarTitleDisplayMode(.large)
            #endif
        }
        .interactiveDismissDisabled(checking)
        .onValueChange(of: model.locked) { if $0 { dismiss() } }
        #if os(macOS)
            .frame(width: 440)
            .frame(minHeight: setting ? 380 : 280)
        #endif
    }

    private var check: some View {
        Form {
            Section {
                Text(
                    "Enter your master password to make sure it’s the one you saved. You’ll need it to open this archive."
                ).fixedSize(horizontal: false, vertical: true)
            }
            Section {
                SecureField("Master Password", text: $password).passwordAutofill()
                    .focused($focus, equals: .password).submitLabel(.done)
                    .onSubmit { if canCheck { runCheck() } }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if wrong { errorLabel("Wrong password. Try again.") }
                    if checking { ProgressView().controlSize(.small) }
                    // Only journals that exist only on this device can get a new password without the old one.
                    if wrong, model.canSetPasswordWithoutCurrent, AppModel.canAuthenticateDeviceOwner {
                        Button("Forgot Password?") { forgotPassword() }
                            .buttonStyle(.borderless).disabled(checking)
                    }
                }
            }
        }
        .disabled(checking)
        .navigationTitle("Check Your Password")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Not Now") { finish() }.disabled(checking).keyboardShortcut(.cancelAction)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Check") { runCheck() }.disabled(!canCheck).keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { focus = .password }
    }

    private var canCheck: Bool { !checking && !password.isEmpty && !model.locked }
    private func errorLabel(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle").foregroundStyle(.red)
    }
    private func runCheck() {
        guard canCheck else { return }
        checking = true
        let typed = password
        Task {
            defer { checking = false }
            do {
                if try await model.checkPassword(typed) {
                    finish()
                } else {
                    wrong = true
                    password = ""
                    focus = .password
                    announceForAccessibility("Wrong password. Try again.")
                }
            } catch {
                // Locked meanwhile: the sheet closes with the lock.
                dismiss()
            }
        }
    }
    private func forgotPassword() {
        Task {
            guard await model.authorizePasswordReset() else { return }
            password = ""
            setting = true
        }
    }
    private func returnToCheck() {
        model.passwordResetAuthorizedAt = nil
        setting = false
        focus = .password
    }
    private func finish() {
        password = ""
        proceed()
        dismiss()
    }
}

/// Forgot Password?: a new master password for journals that exist only on this device, after the device owner
/// authenticated.
struct NewPasswordForm: View {
    private enum Field { case new, confirmation }
    @EnvironmentObject private var model: AppModel
    /// Back to the password check.
    let cancel: () -> Void
    /// The new password is set; the export continues.
    let done: () -> Void
    @State private var new = ""
    @State private var confirmation = ""
    @State private var confirmationVisited = false
    @State private var busy = false
    @State private var message: String?
    @FocusState private var focus: Field?

    var body: some View {
        Form {
            Section {
                Text(
                    "Your journals are only on this device, so you can set a new password without the old one. Archives you exported before still need the old password."
                ).fixedSize(horizontal: false, vertical: true)
            }
            Section {
                SecureField("New Password", text: $new).passwordAutofill(creating: true)
                    .focused($focus, equals: .new).submitLabel(.next)
                    .onSubmit { focus = .confirmation }
                SecureField("Confirm New Password", text: $confirmation).passwordAutofill(creating: true)
                    .focused($focus, equals: .confirmation).submitLabel(.done)
                    .onSubmit { if canSet { set() } }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if showsMismatch { errorLabel("The passwords don’t match.") }
                    if let message { errorLabel(message) }
                    if busy { ProgressView().controlSize(.small) }
                }
            }
        }
        .disabled(busy)
        .interactiveDismissDisabled(busy)
        .navigationTitle("Set New Password")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { cancel() }.disabled(busy).keyboardShortcut(.cancelAction)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Set Password") { set() }.disabled(!canSet).keyboardShortcut(.defaultAction)
            }
        }
        .onValueChange(of: focus) { field in
            if field != .confirmation && !confirmation.isEmpty { confirmationVisited = true }
        }
        .onAppear { focus = .new }
    }

    private var showsMismatch: Bool {
        !confirmation.isEmpty && confirmation != new && (confirmationVisited || confirmation.count >= new.count)
    }
    private var canSet: Bool {
        !busy && !model.locked && new.count >= VaultCrypto.minimumPasswordLength && new == confirmation
    }
    private func errorLabel(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle").foregroundStyle(.red)
    }
    private func set() {
        guard canSet else { return }
        busy = true
        message = nil
        let new = new
        Task {
            defer { busy = false }
            do {
                try await model.setPasswordWithoutCurrent(new)
                self.new = ""
                confirmation = ""
                done()
            } catch {
                message = "Couldn’t set a new password. Your current password still works."
                announceForAccessibility(message ?? "")
            }
        }
    }
}
