import JournalCore
import SwiftUI

/// Settings ▸ Privacy ▸ Encryption (docs/design/1-1-encryption-and-passwords.md §3.7). For a library that isn't
/// encrypted, Turn On Encryption… opens the form as a sheet with Cancel; this is reachable only after Not Now.
struct EncryptionSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var upgrade: EncryptionUpgrade
    /// Opens Reconnect, which signs in to this device's server.
    let signIn: () -> Void

    var body: some View {
        Section {
            Text(encrypted ? "Your Journals Are Encrypted" : "Encryption Is Off")
                .sheet(isPresented: $upgrade.formPresented, onDismiss: signInIfRequested) {
                    EncryptJournalsView(upgrade: upgrade, presentation: .sheet)
                }
            if encrypted {
                ChangePasswordButton()
            } else if upgrade.offersSignIn {
                Button("Reconnect…", action: signIn).disabled(model.locked)
            } else {
                Button("Turn On Encryption…") { upgrade.present() }
                    .disabled(model.locked || model.replacingVault || upgrade.inProgress)
            }
        } header: {
            Text("Encryption")
        } footer: {
            if encrypted {
                Text(
                    "Keep your \(model.configuration?.credentialName.lowercased() ?? "password") somewhere safe. It can’t be recovered."
                )
            } else if upgrade.offersSignIn {
                Text(EncryptionUpgrade.turnedOnElsewhereMessage)
            } else {
                Text("Anyone with access to your files, server, or backups can read your journals.")
            }
        }
    }
    private var encrypted: Bool { model.configuration?.encrypted != false }
    private func signInIfRequested() {
        if upgrade.takeSignInRequest() { signIn() }
    }
}

/// Encrypt Your Journals: one decision, a password pair and Encrypt (docs/design/1-1-encryption-and-passwords.md
/// §3.4). The window's root screen at launch; a sheet with Cancel from Settings.
struct EncryptJournalsView: View {
    enum Presentation { case root, sheet }

    @EnvironmentObject private var model: AppModel
    @ObservedObject var upgrade: EncryptionUpgrade
    let presentation: Presentation
    @FocusState private var focused: EncryptionUpgrade.Field?
    @AccessibilityFocusState private var headingFocused: Bool
    @State private var showPassword = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            switch presentation {
            case .root: column
            case .sheet:
                NavigationStack {
                    column.navigationTitle("")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel", role: .cancel) { upgrade.dismissSheet() }
                                    .disabled(upgrade.busy).keyboardShortcut(.cancelAction)
                            }
                        }
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: presentation == .sheet ? 520 : nil, minHeight: presentation == .sheet ? 600 : nil)
        #endif
        .interactiveDismissDisabled(upgrade.busy)
        .onAppear {
            upgrade.formAppeared()
            headingFocused = true
            focusFirstFieldOnTheMac()
        }
        .onDisappear { upgrade.formDisappeared() }
        .onValueChange(of: upgrade.focusRequest) { _ in takeRequestedFocus() }
        .onValueChange(of: upgrade.showsChecking) { checking in
            if !checking { focusFirstFieldOnTheMac() }
        }
        .confirmationDialog(
            "Stop syncing with \(upgrade.host)?", isPresented: $upgrade.confirmingStopSyncing,
            titleVisibility: .visible
        ) {
            Button("Stop Syncing") { upgrade.stopSyncing() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(EncryptionStopSyncing.message(model: model, host: upgrade.host, adopting: false))
        }
    }

    // MARK: Content

    private var column: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Encrypt Your Journals").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingFocused)
                Text(paragraph).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if upgrade.showsChecking {
                    ProgressView("Checking \(upgrade.host)…").accessibilityElement(children: .combine)
                } else {
                    if upgrade.variant == .synced { otherDevices }
                    if showsFields { fields }
                }
                if let error = upgrade.formError {
                    Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if upgrade.preparing { ProgressView() }
                actions
            }
            .padding(28).frame(maxWidth: 480, alignment: .leading).frame(maxWidth: .infinity)
        }
        .disabled(upgrade.preparing)
    }

    private var paragraph: String {
        if upgrade.variant == .signIn { return EncryptionUpgrade.signInMessage(host: upgrade.host) }
        return upgrade.synced
            ? EncryptionUpgrade.syncedMessage(host: upgrade.host) : EncryptionUpgrade.localMessage
    }

    /// Variant B: what happens to the other devices before the person chooses.
    @ViewBuilder private var otherDevices: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Other Devices").font(.headline).accessibilityAddTraits(.isHeader)
            note("Before you encrypt, let your other devices sync.")
            note(
                "Your other devices will stop syncing until you sign in on each one with your master password. Changes they haven’t synced are kept. Any that conflict are shown for review."
            )
            note(
                "Agents with access to your journals on \(upgrade.host) lose it. Give them access again afterward.")
        }
    }
    private func note(_ text: String) -> some View {
        Text(text).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Fields

    private var showsFields: Bool { upgrade.variant == .local || upgrade.variant == .synced }
    @ViewBuilder private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            if upgrade.needsCurrentPassword {
                field("Current Access Password", text: $upgrade.currentPassword, field: .current, creating: false)
                    .onSubmit { focused = .password }
                fieldError(.current)
            }
            field("Master Password", text: $upgrade.password, field: .password, creating: true)
                .onSubmit { focused = .verify }
            fieldError(.password)
            field("Verify", text: $upgrade.verify, field: .verify, creating: true)
                .onSubmit { if canEncrypt { upgrade.encrypt() } }
            fieldError(.verify)
            Toggle(upgrade.needsCurrentPassword ? "Show Passwords" : "Show Password", isOn: $showPassword)
        }
        .disabled(upgrade.preparing)
        Text(
            upgrade.variant == .synced
                ? "You’ll use this password to sign in on your other devices, restore backups, and recover your journals if you lose your devices. It can’t be reset, so save it in your password manager."
                : "Save this password in your password manager. If you lose it and access to your devices, you won’t be able to restore your journals. Keep a backup, too."
        )
        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        #if os(macOS)
            Text("This can take a few minutes if you have many images.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        #else
            Text("This can take a few minutes if you have many images. Keep My Journal open.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        #endif
    }
    @ViewBuilder private func field(
        _ name: String, text: Binding<String>, field: EncryptionUpgrade.Field, creating: Bool
    ) -> some View {
        Group {
            if showPassword {
                TextField(name, text: text)
            } else {
                SecureField(name, text: text)
            }
        }
        .passwordAutofill(creating: creating).autocorrectionDisabled().textFieldStyle(.roundedBorder)
        #if os(iOS)
            .textInputAutocapitalization(.never)
        #endif
        .focused($focused, equals: field).errorHint(upgrade.fieldErrors[field])
    }
    @ViewBuilder private func fieldError(_ field: EncryptionUpgrade.Field) -> some View {
        if let message = upgrade.fieldErrors[field] {
            Text(message).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
    }

    // MARK: Buttons

    private var canEncrypt: Bool {
        !upgrade.busy && !upgrade.password.isEmpty && !upgrade.verify.isEmpty
            && (!upgrade.needsCurrentPassword || !upgrade.currentPassword.isEmpty)
    }
    @ViewBuilder private var actions: some View {
        VStack(alignment: .center, spacing: 12) {
            primary
            if showsNotNow {
                Button("Not Now") { upgrade.notNow() }.buttonStyle(.plain).foregroundStyle(.tint)
                    .frame(minHeight: 44).disabled(upgrade.busy)
            }
            if upgrade.offersStopSyncing {
                Button("Stop Syncing…") { upgrade.confirmingStopSyncing = true }
                    .buttonStyle(.plain).foregroundStyle(.tint).frame(minHeight: 44).disabled(upgrade.busy)
            }
        }
        .frame(maxWidth: .infinity)
    }
    /// The sheet has Cancel in its bar; the root form offers Not Now where the form can't succeed.
    private var showsNotNow: Bool { presentation == .root && upgrade.offersNotNow && !upgrade.showsChecking }
    @ViewBuilder private var primary: some View {
        if upgrade.showsChecking {
            // The check offers Not Now as soon as it fails or takes a few seconds.
            if presentation == .root && upgrade.offersNotNow {
                Button("Not Now") { upgrade.notNow() }.buttonStyle(.plain).foregroundStyle(.tint).frame(minHeight: 44)
            }
        } else {
            switch upgrade.variant {
            case .signIn:
                Button("Reconnect…") { upgrade.signIn() }.prominent().accessibilityLabel("Reconnect")
            case .unavailable:
                Button("Try Again") { upgrade.tryAgain() }.prominent()
            case .local, .synced:
                Button(upgrade.formError == nil ? "Encrypt" : "Try Again") {
                    if upgrade.formError == nil { upgrade.encrypt() } else { upgrade.tryAgain() }
                }
                .prominent().disabled(!canEncrypt)
                .accessibilityLabel(upgrade.formError == nil ? "Encrypt journals" : "Try Again")
            }
        }
    }

    // MARK: Focus

    private func takeRequestedFocus() {
        guard let field = upgrade.focusRequest else { return }
        focused = field
        upgrade.focusRequest = nil
    }
    /// On the Mac the first field takes focus; on iPhone and iPad it doesn't, so the keyboard and the strong-password
    /// bar never cover the note under the fields, and VoiceOver starts at the heading.
    private func focusFirstFieldOnTheMac() {
        #if os(macOS)
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard upgrade.variant == .local || upgrade.variant == .synced, !upgrade.showsChecking else { return }
                focused = upgrade.needsCurrentPassword ? .current : .password
            }
        #endif
    }
}

private extension View {
    /// The form's one primary button: large and prominent, and the default action.
    func prominent() -> some View {
        buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
    }
}

/// The text of the Stop Syncing confirmation for Encrypt Your Journals.
@MainActor enum EncryptionStopSyncing {
    /// `adopting` is the unfinished notice's wording, which fits both answers of the server.
    static func message(model: AppModel, host: String, adopting: Bool) -> String {
        let consequence =
            adopting
            ? "Your journals are already encrypted on this device. This device won’t be able to sync with \(host) again."
            : "This device won’t be able to sync with \(host) again. Your other devices keep using \(host) and won’t receive changes made here. Your journals stay on this device and are encrypted next."
        let waiting = model.syncActivity.pendingItems
        guard waiting > 0 else { return consequence }
        let items = waiting == 1 ? "1 item that isn’t" : "\(waiting) items that aren’t"
        return consequence + " \(items) on the server yet will stay only on this device until then."
    }
}

/// Your Journals Are Encrypted, over the journals once the work is done.
struct EncryptionDoneView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var upgrade: EncryptionUpgrade
    @State private var addingDevice = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Your Journals Are Encrypted").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text("Only your devices can read your journals.").foregroundStyle(.secondary)
                Text(
                    "Keep your master password somewhere safe. It is the only way to open your journals on a new device."
                )
                .fixedSize(horizontal: false, vertical: true)
                if upgrade.synced {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Other Devices").font(.headline).accessibilityAddTraits(.isHeader)
                        Text(
                            "On each of your other devices, choose Reconnect and enter your master password, or add it from this device."
                        ).fixedSize(horizontal: false, vertical: true)
                        Button("Add Another Device…") { addingDevice = true }
                    }
                }
                Text("Archives and backups made before now aren’t encrypted. Anyone who has them can still read them.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Done") { upgrade.dismissDone() }
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                    .frame(maxWidth: .infinity)
            }
            .padding(28).frame(maxWidth: 480, alignment: .leading).frame(maxWidth: .infinity)
        }
        #if os(macOS)
            .frame(width: 520, height: 520)
        #endif
        .sheet(isPresented: $addingDevice) { AddDeviceView().environmentObject(model) }
        .onValueChange(of: model.locked) { if $0 { upgrade.dismissDone() } }
    }
}

/// Encrypting, with how far it has come.
struct EncryptionProgressRow: View {
    let fraction: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Encrypting your journals…").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ProgressView(value: fraction)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Encrypting your journals")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

/// The busy row of Connect to a Server, which shows encrypting progress while a device signs in again after
/// encryption was turned on from another device.
struct ConnectionBusyRow: View {
    let activity: String
    @ObservedObject var upgrade: EncryptionUpgrade
    var body: some View {
        if let fraction = upgrade.rejoinProgress {
            EncryptionProgressRow(fraction: fraction)
        } else {
            connectionStatus(activity)
        }
    }
}

/// What sits over the whole app for encryption: Your Journals Are Encrypted, and Reconnect from a sync message or
/// from the form's sign-in variant.
struct EncryptionPresentation: ViewModifier {
    @ObservedObject var model: AppModel
    @ObservedObject var upgrade: EncryptionUpgrade
    func body(content: Content) -> some View {
        content
            .sheet(
                isPresented: Binding(
                    get: { upgrade.donePresented && !model.locked }, set: { upgrade.donePresented = $0 })
            ) {
                EncryptionDoneView(upgrade: upgrade).environmentObject(model)
            }
            .sheet(
                isPresented: Binding(
                    get: { upgrade.signInRequested && !model.locked }, set: { upgrade.signInRequested = $0 })
            ) {
                ConnectionView().environmentObject(model)
            }
    }
}
