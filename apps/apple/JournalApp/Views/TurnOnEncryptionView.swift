import JournalCore
import SwiftUI

/// Settings > Privacy > Encryption (docs/design/enable-encryption.md).
struct EncryptionSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var upgrade: EncryptionUpgrade
    /// Opens Connect to a Server, which signs in to this device's server.
    let signIn: () -> Void

    var body: some View {
        Section {
            Text(encrypted ? "Your Journals Are Encrypted" : "Encryption Is Off")
                .sheet(isPresented: $upgrade.presented, onDismiss: signInIfRequested) {
                    TurnOnEncryptionView(upgrade: upgrade)
                }
            if encrypted {
                ChangePasswordButton()
            } else if upgrade.offersSignIn {
                Button("Sign In…", action: signIn).disabled(model.locked)
            } else {
                Button("Turn On Encryption…") { upgrade.present() }
                    .disabled(model.locked || (model.replacingVault && !upgrade.pausesWriting))
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

/// The Turn On Encryption sheet: what happens, Choose a Master Password, and Your Journals Are Encrypted.
struct TurnOnEncryptionView: View {
    @ObservedObject var upgrade: EncryptionUpgrade

    var body: some View {
        NavigationStack(path: $upgrade.path) {
            EncryptionStepView(step: nil, upgrade: upgrade)
                .navigationDestination(for: EncryptionUpgrade.Step.self) {
                    EncryptionStepView(step: $0, upgrade: upgrade)
                }
        }
        #if os(macOS)
            .frame(minWidth: 440, idealWidth: 480, minHeight: 460, idealHeight: 560)
        #endif
        .interactiveDismissDisabled(upgrade.busy || upgrade.unfinished)
    }
}

private struct EncryptionStepView: View {
    /// The step, or nil for the first one.
    let step: EncryptionUpgrade.Step?
    @ObservedObject var upgrade: EncryptionUpgrade
    @FocusState private var focused: EncryptionUpgrade.Field?
    @State private var showPassword = false
    @State private var addingDevice = false

    var body: some View {
        Form {
            #if os(macOS)
                // Sheets before macOS 26 show no navigation title.
                if #unavailable(macOS 26), step != .done { Section { Text(title).font(.headline) } }
            #endif
            content
            if showsStatus { Section { status } }
            if let error = upgrade.errorMessage(on: step) {
                Section {
                    Text(error).foregroundStyle(.red).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(step == .done ? "" : title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationBarBackButtonHidden(!canGoBack)
        .toolbar { toolbar }
        .onValueChange(of: upgrade.focusRequest) { _ in takeRequestedFocus() }
        .onAppear { takeRequestedFocus() }
        .sheet(isPresented: $addingDevice) { AddDeviceView() }
    }

    private var title: String {
        switch step {
        case nil: return "Turn On Encryption"
        case .password: return "Choose a Master Password"
        case .done: return "Your Journals Are Encrypted"
        }
    }
    @ViewBuilder private var content: some View {
        switch step {
        case nil: about
        case .password: choosePassword
        case .done: done
        }
    }
    private var namesServer: Bool { upgrade.synced }

    // MARK: Steps

    @ViewBuilder private var about: some View {
        intro(
            namesServer
                ? "Encryption protects your journals on this device and on \(upgrade.host). Only your devices can read them. You can’t turn encryption off later."
                : "Encryption protects your journals on this device. Only your devices can read them. You can’t turn encryption off later."
        )
        if upgrade.synced {
            Section {
                wrapped("Before you continue, update My Journal on your other devices and let them sync.")
                wrapped(
                    "Your other devices will stop syncing until you sign in on each one with your master password. Changes they haven’t synced are kept. Any that conflict are shown for review."
                )
                wrapped(
                    "Agents with access to your journals on \(upgrade.host) lose it. Give them access again afterward.")
            } header: {
                Text("Your Other Devices")
            }
        }
        Section {
        } footer: {
            Text(
                "You can’t write while your journals are being encrypted. This can take a few minutes if you have many images."
            )
        }
    }
    @ViewBuilder private var choosePassword: some View {
        intro(
            namesServer
                ? "Your master password encrypts your journals on this device before they’re sent to \(upgrade.host)."
                : "Your master password encrypts your journals on this device.")
        if upgrade.needsCurrentPassword {
            Section {
                passwordField("Current Access Password", text: $upgrade.currentPassword, field: .current)
                    .headedField("Current Access Password").onSubmit { focused = .password }
                fieldError(.current)
            } header: {
                Text("Current Access Password")
            }
            .disabled(fieldsLocked)
        }
        Section {
            passwordField("Master Password", text: $upgrade.password, field: .password, creating: true)
                .onSubmit { focused = .verify }
            fieldError(.password)
            passwordField("Verify", text: $upgrade.verify, field: .verify, creating: true)
                .onSubmit { if canTurnOn { upgrade.turnOn() } }
            fieldError(.verify)
            Toggle(upgrade.needsCurrentPassword ? "Show Passwords" : "Show Password", isOn: $showPassword)
        }
        .disabled(fieldsLocked)
        Section {
        } footer: {
            Text(
                "You’ll use this password to sign in on your other devices, restore backups, and recover your journals if you lose your devices. It can’t be reset, so save it in your password manager."
            )
        }
    }
    @ViewBuilder private var done: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "lock.shield").font(.system(size: 48)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Your Journals Are Encrypted").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text("Only your devices can read your journals.").foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 8)
            .fixedSize(horizontal: false, vertical: true)
        }.listRowBackground(Color.clear)
        if upgrade.synced {
            Section {
                wrapped(
                    "On each of your other devices, choose Sign In and enter your master password, or add it from this device."
                )
                Button("Add Another Device…") { addingDevice = true }
            } header: {
                Text("Your Other Devices")
            } footer: {
                Text(archivesFooter)
            }
        } else {
            Section {
            } footer: {
                Text(archivesFooter)
            }
        }
    }
    private let archivesFooter =
        "Archives and backups made before now aren’t encrypted. Anyone who has them can still read them."

    // MARK: Progress

    /// Whether this step shows what's under way.
    private var showsStatus: Bool {
        switch upgrade.phase {
        case .checking?: return step == nil && upgrade.synced
        case .syncing?, .encrypting?, .updatingServer?: return step == .password
        case nil: return false
        }
    }
    @ViewBuilder private var status: some View {
        switch upgrade.phase {
        case .checking?: connectionStatus("Checking \(upgrade.host)…")
        case .syncing?: connectionStatus("Syncing…")
        case .encrypting(let fraction)?: EncryptionProgressRow(fraction: fraction)
        case .updatingServer?: connectionStatus("Updating \(upgrade.host)…")
        case nil: EmptyView()
        }
    }

    // MARK: Toolbar

    private var fieldsLocked: Bool { upgrade.busy || upgrade.unfinished }
    private var canGoBack: Bool { step == .password && !fieldsLocked }
    private var canTurnOn: Bool {
        !upgrade.busy && !upgrade.password.isEmpty && !upgrade.verify.isEmpty
            && (!upgrade.needsCurrentPassword || !upgrade.currentPassword.isEmpty)
    }
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if step == .done {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { upgrade.done() } }
        } else {
            if !upgrade.unfinished && showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { upgrade.cancel() }.disabled(!upgrade.canCancel)
                }
            }
            ToolbarItem(placement: .confirmationAction) { primary }
        }
    }
    /// The Mac always shows Cancel; iOS shows it where Back isn't available, as in Connect to a Server.
    private var showsCancel: Bool {
        #if os(macOS)
            true
        #else
            !canGoBack
        #endif
    }
    @ViewBuilder private var primary: some View {
        switch step {
        case nil:
            if upgrade.errorOffersSignIn && upgrade.errorMessage(on: nil) != nil {
                Button("Sign In…") { upgrade.signIn() }
            } else {
                Button(upgrade.errorMessage(on: nil) == nil ? "Continue" : "Try Again") { upgrade.continueFromAbout() }
                    .disabled(upgrade.busy)
            }
        case .password:
            if upgrade.unfinished {
                Button("Try Again") { upgrade.finish() }.disabled(upgrade.busy)
            } else {
                Button(upgrade.errorMessage(on: .password) == nil ? "Turn On" : "Try Again") { upgrade.turnOn() }
                    .disabled(!canTurnOn)
            }
        case .done:
            EmptyView()
        }
    }

    // MARK: Parts

    private func intro(_ text: String) -> some View {
        Section {
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.listRowBackground(Color.clear)
    }
    private func wrapped(_ text: String) -> some View { Text(text).fixedSize(horizontal: false, vertical: true) }
    @ViewBuilder private func passwordField(
        _ name: String, text: Binding<String>, field: EncryptionUpgrade.Field, creating: Bool = false
    ) -> some View {
        Group {
            if showPassword {
                TextField(name, text: text)
            } else {
                SecureField(name, text: text)
            }
        }
        .passwordAutofill(creating: creating).autocorrectionDisabled()
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
    private func takeRequestedFocus() {
        guard let field = upgrade.focusRequest else { return }
        Task {
            // A pushed step takes focus once its transition ends.
            try? await Task.sleep(nanoseconds: 400_000_000)
            focused = field
            if upgrade.focusRequest == field { upgrade.focusRequest = nil }
        }
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

/// The encryption sheet over the app after a relaunch couldn't finish (iPhone and iPad), and Sign In from a sync
/// message.
struct EncryptionPresentation: ViewModifier {
    @ObservedObject var model: AppModel
    @ObservedObject var upgrade: EncryptionUpgrade
    func body(content: Content) -> some View {
        content
            #if os(iOS)
                .sheet(
                    isPresented: Binding(
                        get: { upgrade.presentedOverApp && !model.locked },
                        set: { if !$0 { upgrade.presentedOverApp = false } })
                ) {
                    TurnOnEncryptionView(upgrade: upgrade).environmentObject(model)
                }
            #endif
            .sheet(
                isPresented: Binding(
                    get: { upgrade.signInRequested && !model.locked }, set: { upgrade.signInRequested = $0 })
            ) {
                ConnectionView().environmentObject(model)
            }
    }
}

#if os(macOS)
    /// Explains, in the journal window, why writing does nothing while this Mac encrypts its journals from Settings.
    struct EncryptionPauseNotice: View {
        @ObservedObject var upgrade: EncryptionUpgrade
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        var body: some View {
            if upgrade.pausesWriting {
                let layout =
                    dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout())
                layout {
                    Text(
                        upgrade.unfinished
                            ? "Your journals are encrypted on \(upgrade.host), but this Mac couldn’t finish. Free up space, then try again."
                            : "Writing is paused while this Mac encrypts your journals."
                    )
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    Button("Show Progress") { upgrade.showProgress() }
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading).background(.quaternary)
            }
        }
    }
#endif
