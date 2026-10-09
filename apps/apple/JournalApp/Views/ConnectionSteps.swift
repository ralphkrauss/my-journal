import JournalCore
import SwiftUI

/// One step of Connect to a Server after the server is chosen (docs/design/connection-onboarding.md).
struct ConnectionStepView: View {
    let step: ConnectionFlow.Step
    @ObservedObject var flow: ConnectionFlow
    @EnvironmentObject private var model: AppModel
    @FocusState private var focused: ConnectionFlow.Field?
    @State private var showPassword = false
    @State private var addingDevice = false
    /// The setup code as the field shows it.
    @State private var typedCode = ""
    /// The Mac's heading row, which VoiceOver reads first when Merge Journals appears (no navigation title there
    /// before macOS 26).
    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        Form {
            #if os(macOS)
                // Sheets before macOS 26 show no navigation title.
                if #unavailable(macOS 26), step != .serverReady {
                    Section {
                        Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                            .accessibilityFocused($headingFocused)
                    }
                }
            #endif
            content
            if flow.busy && showsBusyRow {
                Section { ConnectionBusyRow(activity: flow.activityLabel, upgrade: model.encryption) }
            }
            if let error = flow.errorMessage(on: step) {
                Section { Text(error).foregroundStyle(.red).font(.callout) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(step == .serverReady ? "" : title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(!canGoBack)
        #else
            .navigationBarBackButtonHidden(!canGoBack)
        #endif
        .toolbar { toolbar }
        .onValueChange(of: flow.focusRequest) { _ in takeRequestedFocus() }
        .onAppear {
            takeRequestedFocus()
            if step == .merge { headingFocused = true }
            if step == .addThisDevice && flow.ticket == nil && !flow.busy && flow.errorMessage(on: step) == nil {
                flow.beginPairing()
            }
        }
        .sheet(isPresented: $addingDevice) { AddDeviceView() }
    }

    private var title: String {
        switch step {
        case .setUpServer: return "Set Up Server"
        case .choosePassword: return "Choose a Master Password"
        case .enterPassword: return "Enter \(flow.existingCredentialName)"
        case .serverReady: return "Server Is Ready"
        case .signIn: return "Enter \(flow.credentialName)"
        case .addThisDevice: return "Add This Device"
        case .recoveryCode: return "Use a Recovery Code"
        case .merge: return "Merge Journals"
        // The instruction below carries "Finish on Your Other Device", as on the first screen before; a title that
        // long is cut off beside Cancel and Scan Again.
        case .finish: return "Connect to a Server"
        }
    }
    @ViewBuilder private var content: some View {
        switch step {
        case .setUpServer: setUpServer
        case .choosePassword: choosePassword
        case .enterPassword: enterPassword
        case .serverReady: serverReady
        case .signIn: signIn
        case .addThisDevice: addThisDevice
        case .recoveryCode: recoveryCode
        case .merge: MergeJournalsContent(flow: flow)
        case .finish: finishOnOtherDevice
        }
    }
    /// Add This Device and Finish on Your Other Device show their progress beside their instructions.
    private var showsBusyRow: Bool { step != .addThisDevice && step != .finish }

    // MARK: Toolbar

    /// Back never reaches a choice that's already made: while working, or once a journal was created here.
    private var canGoBack: Bool {
        if flow.busy || step == .serverReady || step == .finish { return false }
        return !(flow.createdJournalHere && step == .choosePassword)
    }
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if step == .serverReady {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { flow.cancel() } }
        } else {
            #if os(macOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { flow.cancel() }.disabled(flow.installing)
                }
            #else
                if !canGoBack {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { flow.cancel() }.disabled(flow.installing)
                    }
                }
            #endif
            ToolbarItem(placement: .confirmationAction) { primary }
        }
    }
    @ViewBuilder private var primary: some View {
        switch step {
        case .setUpServer:
            Button(flow.stepAfterSetupCode == nil ? "Set Up" : "Continue") { flow.continueFromSetupCode() }
                .disabled(flow.busy || flow.setupCode.isEmpty)
        case .choosePassword:
            Button(retrying ? "Try Again" : "Set Up") { flow.setUpWithNewPassword() }
                .disabled(flow.busy || flow.newPassword.isEmpty || flow.verifyPassword.isEmpty)
        case .enterPassword:
            Button("Set Up") { flow.setUp() }.disabled(flow.busy || flow.phrase.isEmpty)
        case .signIn:
            Button(flow.mergeInterrupted && flow.errorMessage(on: step) != nil ? "Try Again" : "Sign In") {
                flow.signIn()
            }.disabled(flow.busy || flow.phrase.isEmpty)
        case .recoveryCode:
            // The one-time code was spent; Try Again continues with the access it gave.
            Button(model.retryGrant != nil && flow.errorMessage(on: step) != nil ? "Try Again" : "Connect") {
                flow.signIn()
            }.disabled(flow.busy || flow.phrase.isEmpty)
        case .addThisDevice:
            pairingAction
        case .serverReady:
            EmptyView()
        case .merge:
            // As Approve and Connect, not the Return default: merging must follow reading the server's name.
            let merge = Button("Merge") { flow.confirmMerge() }.keyboardShortcut(.return, modifiers: .command)
                .disabled(flow.busy)
            #if os(macOS)
                merge.help("Merge (⌘Return)").accessibilityHint("Press Command-Return to merge.")
            #else
                merge
            #endif
        case .finish:
            if !flow.busy && flow.errorMessage(on: step) != nil {
                if flow.received != nil {
                    Button("Try Again") { flow.resumeImport() }
                } else if flow.canRetryScannedCode {
                    Button("Try Again") { flow.retryScannedCode() }
                } else {
                    Button("Scan Again") { flow.scanAgain() }
                }
            }
        }
    }
    /// A journal was created here and only the server failed: the same choice and password are used again.
    private var retrying: Bool { flow.createdJournalHere && !flow.completed }

    // MARK: Setting up a new server

    @ViewBuilder private var setUpServer: some View {
        Section { LabeledContent("Server", value: flow.host).textSelection(.enabled) }
        Section {
            TextField("Setup Code", text: $typedCode, prompt: Text(verbatim: "XXX-XXX"))
                .font(.body.monospaced()).headedField("Setup Code").autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.characters).keyboardType(.asciiCapable)
                #endif
                .focused($focused, equals: .setupCode).errorHint(flow.fieldErrors[.setupCode])
                .disabled(flow.busy).onSubmit {
                    if !flow.setupCode.isEmpty && !flow.busy { flow.continueFromSetupCode() }
                }
            fieldError(.setupCode)
        } header: {
            Text("Setup Code")
                // The field keeps its own text while editing, so the formatted code is written back from here.
                .onValueChange(of: typedCode) { typed in
                    let formatted = CodeEntry.setupCode(typed, previous: flow.setupCode)
                    flow.setupCode = formatted
                    if formatted != typed { typedCode = formatted }
                }
                .onValueChange(of: flow.setupCode) { if $0 != typedCode { typedCode = $0 } }
                .onAppear { typedCode = flow.setupCode }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Enter the code your server shows when it starts. To see it again, run setup-code on the server.")
                if let guide = Self.setupGuide { Link("How to Set Up a Server", destination: guide) }
                if flow.stepAfterSetupCode == nil && model.store != nil && !flow.createdJournalHere {
                    Text(uploadWithoutPassword)
                }
            }
        }
    }
    static let setupGuide = URL(
        string: "https://github.com/ralphkrauss/my-journal/blob/main/docs/guide/sync.md#use-your-own-server")
    private var uploadWithoutPassword: String {
        let upload = "The journals on this device will be uploaded to \(flow.host)."
        return model.configuration?.encrypted == false
            ? upload + " They aren’t encrypted, so anyone with access to the server can read them." : upload
    }
    @ViewBuilder private var choosePassword: some View {
        intro("Your master password encrypts your journals on this device before they’re sent to \(flow.host).")
        Section {
            passwordField("Master Password", text: $flow.newPassword, field: .newPassword)
                .onSubmit { focused = .verifyPassword }
            fieldError(.newPassword)
            passwordField("Verify", text: $flow.verifyPassword, field: .verifyPassword)
                .onSubmit { if !flow.busy { flow.setUpWithNewPassword() } }
            fieldError(.verifyPassword)
            Toggle("Show Password", isOn: $showPassword)
        }
        .disabled(flow.busy || flow.createdJournalHere)
        Section {
        } footer: {
            Text(
                "You’ll use this password to sign in on your other devices, restore backups, and recover your journals if you lose your devices. It can’t be reset, so save it in your password manager."
            )
        }
    }
    @ViewBuilder private func passwordField(
        _ name: String, text: Binding<String>, field: ConnectionFlow.Field
    ) -> some View {
        Group {
            if showPassword {
                TextField(name, text: text)
            } else {
                SecureField(name, text: text)
            }
        }
        .passwordAutofill(creating: true).autocorrectionDisabled()
        #if os(iOS)
            .textInputAutocapitalization(.never)
        #endif
        .focused($focused, equals: field).errorHint(flow.fieldErrors[field])
    }
    @ViewBuilder private var enterPassword: some View {
        let credential = flow.existingCredentialName.lowercased()
        intro(
            "Enter the \(credential) for the journals on this device. Your other devices will use it to sign in to \(flow.host)."
        )
        Section {
            phraseField(flow.existingCredentialName).onSubmit { if !flow.phrase.isEmpty && !flow.busy { flow.setUp() } }
            fieldError(.phrase)
            Toggle("Show \(flow.existingCredentialName)", isOn: $showPassword)
        } footer: {
            Text("The journals on this device will be uploaded to \(flow.host).")
        }
    }
    @ViewBuilder private var serverReady: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle").font(.system(size: 48)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Server Is Ready").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text("Your journals will sync with \(flow.host).").foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 8)
            .fixedSize(horizontal: false, vertical: true)
        }.listRowBackground(Color.clear)
        Section {
            Button("Add Another Device…") { addingDevice = true }
        } footer: {
            if model.configuration?.requiresPassword == true {
                Text(
                    "You can also sign in on your other devices with your \(model.configuration?.credentialName.lowercased() ?? "master password")."
                )
            }
        }
    }

    // MARK: Adding this device to a server that's set up

    @ViewBuilder private var signIn: some View {
        let credential = flow.credentialName.lowercased()
        let rejoining = model.encryption.offersSignIn
        if rejoining {
            // True whether encryption was turned on elsewhere or the server was replaced by an encrypted library
            // (docs/design/sync-health-and-recovery.md §7.1).
            intro("The server now uses encryption. Enter its master password.")
        } else {
            intro(
                flow.envelope?.formatVersion == 1
                    ? "Enter the recovery key you saved when you set up \(flow.host)."
                    : "Enter the \(credential) you chose when you set up \(flow.host).")
        }
        Section {
            phraseField(flow.credentialName).onSubmit { if !flow.phrase.isEmpty && !flow.busy { flow.signIn() } }
            fieldError(.phrase)
            Toggle("Show \(flow.credentialName)", isOn: $showPassword)
        } footer: {
            if rejoining {
                Text("The journals on this device will be encrypted too. Changes that haven’t synced are kept.")
            } else if let footer = flow.downloadFooter {
                Text(footer)
            }
        }
        Section {
            Button("Use a Connected Device Instead…") { flow.path.append(.addThisDevice) }.disabled(flow.busy)
        }
    }
    @ViewBuilder private var recoveryCode: some View {
        Section {
            if let notice = flow.codeUsedNotice {
                Text(notice).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            phraseField("Recovery Code").onSubmit { if !flow.phrase.isEmpty && !flow.busy { flow.signIn() } }
            fieldError(.phrase)
            Toggle("Show Recovery Code", isOn: $showPassword)
        } footer: {
            Text(
                ["Ask your server administrator for a one-time recovery code.", flow.downloadFooter].compactMap { $0 }
                    .joined(separator: " "))
        }
    }
    @ViewBuilder private var addThisDevice: some View {
        Section {
            if flow.errorMessage(on: step) != nil {
                // The error below explains what happened; Get New Code or Try Again follows.
            } else if let reveal = flow.reveal {
                checkCodeView(reveal.checkCode)
            } else if let ticket = flow.ticket {
                pairingCodeView(ticket)
            } else {
                connectionStatus("Getting a code…")
            }
        } footer: {
            if let footer = flow.downloadFooter { Text(footer) }
        }
        if flow.passwordless {
            Section {
                Button("Use a Recovery Code Instead…") {
                    flow.abandon()
                    flow.path.append(.recoveryCode)
                }.disabled(flow.installing)
            }
        }
    }
    private func pairingCodeView(_ ticket: PairingTicket) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(groupedCode(ticket.code)).font(.system(.largeTitle, design: .monospaced))
                .textSelection(.enabled).accessibilityIdentifier("pairing-code").accessibilityLabel("Pairing code")
                .accessibilityValue(ticket.code.map(String.init).joined(separator: " "))
            Button("Copy Code") { copyCode(ticket.code) }
            Text("On a connected device, open Settings ▸ Sync ▸ Devices ▸ Add Device, then choose Enter Code Instead.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if flow.busy { connectionStatus(flow.installing ? flow.activityLabel : "Waiting for approval…") }
        }
    }
    private func checkCodeView(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Check Code").font(.headline)
            Text(PairingCheck.grouped(code)).font(.system(.largeTitle, design: .monospaced))
                .foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("check-code").accessibilityLabel("Check code")
                .accessibilityValue(code.map(String.init).joined(separator: " "))
            Text("Connect only if your other device shows the same code.").foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if flow.installing {
                connectionStatus(flow.activityLabel)
            } else if flow.busy && flow.confirmed {
                connectionStatus("Waiting for approval on your other device…")
            }
        }
    }
    /// As Approve on the other device, Connect isn't the Return default: connecting must follow comparing the codes.
    @ViewBuilder private var pairingAction: some View {
        if flow.awaitingConfirmation {
            // A device with journals agreed to merge them on Merge Journals, before this step.
            let button = Button("Connect") { flow.confirm() }
                .keyboardShortcut(.return, modifiers: .command)
            #if os(macOS)
                button.help("Connect (⌘Return)").accessibilityHint("Press Command-Return to connect.")
            #else
                button
            #endif
        } else if !flow.busy && flow.errorMessage(on: step) != nil {
            Button(flow.received == nil ? "Get New Code" : "Try Again") {
                flow.received == nil ? flow.beginPairing() : flow.resumeImport()
            }
        }
    }

    // MARK: Finishing with a scanned code

    @ViewBuilder private var finishOnOtherDevice: some View {
        Section { LabeledContent("Server", value: flow.host).textSelection(.enabled) }
        if flow.errorMessage(on: step) == nil {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Finish on Your Other Device").font(.headline)
                    Text("Choose Add Device on your connected device.").foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    connectionStatus(flow.installing ? flow.activityLabel : "Waiting for approval…").padding(.top, 4)
                }.padding(.vertical, 4)
            }
        }
    }

    // MARK: Parts

    /// A short explanation at the top of a step.
    private func intro(_ text: String) -> some View {
        Section {
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.listRowBackground(Color.clear)
    }
    private func phraseField(_ name: String) -> some View {
        Group {
            if showPassword {
                TextField(name, text: $flow.phrase).autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
            } else {
                SecureField(name, text: $flow.phrase)
            }
        }
        .passwordAutofill().headedField(name).focused($focused, equals: .phrase)
        .errorHint(flow.fieldErrors[.phrase]).disabled(flow.busy)
    }
    @ViewBuilder private func fieldError(_ field: ConnectionFlow.Field) -> some View {
        if let message = flow.fieldErrors[field] {
            Text(message).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
    }
    private func takeRequestedFocus() {
        guard let field = flow.focusRequest else { return }
        Task {
            // A pushed step takes focus once its transition ends.
            try? await Task.sleep(nanoseconds: 400_000_000)
            focused = field
            if flow.focusRequest == field { flow.focusRequest = nil }
        }
    }
    private func groupedCode(_ code: String) -> String {
        code.enumerated().map { $0.offset > 0 && $0.offset % 3 == 0 ? " " + String($0.element) : String($0.element) }
            .joined()
    }
    private func copyCode(_ code: String) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
        #else
            UIPasteboard.general.string = code
        #endif
    }
}

extension View {
    /// A field's error is read with the field, since moving focus to it can cut an announcement short.
    func errorHint(_ message: String?) -> some View { accessibilityHint(message ?? "") }
}
