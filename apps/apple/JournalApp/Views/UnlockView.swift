import SwiftUI

/// The lock screen: one button for the device's own authentication (docs/design/app-lock-system-auth.md). The
/// recovery credential appears when the device key is unavailable, or after unlocking with the device failed.
struct UnlockView: View {
    @EnvironmentObject var model: AppModel
    @State private var credential = ""
    @State private var usingCredential = false
    @AccessibilityFocusState private var unlockFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content.padding(32).frame(maxWidth: .infinity).frame(minHeight: geometry.size.height)
            }
        }
        .task {
            model.refreshDeviceOwnerAvailability()
            await model.promptToUnlockIfPending()
        }
        .onValueChange(of: model.unlockState.authenticating) { authenticating in
            // After a cancel, VoiceOver continues from the button that asks again.
            if !authenticating && model.locked { unlockFocused = true }
        }
        .onValueChange(of: problem) { message in
            if let message { JournalAccessibility.announce(message) }
        }
    }

    /// The device key is gone: only the recovery credential can open the journals.
    private var needsCredential: Bool { model.masterKey == nil }
    private var method: DeviceUnlockMethod { (model.unlockState.availability ?? .unavailable).method }
    private var credentialName: String { model.configuration?.credentialName ?? "Password or Recovery Key" }
    private var problem: String? {
        if let error = model.error { return error }
        return model.unlockState.problem ? "My Journal couldn’t be unlocked. Try again." : nil
    }

    private var content: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock").font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("My Journal Is Locked").font(.title2).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if needsCredential || usingCredential {
                credentialForm
            } else {
                deviceUnlock
            }
        }.multilineTextAlignment(.center)
    }

    @ViewBuilder private var deviceUnlock: some View {
        if let problem { note(problem) }
        Button {
            Task { await model.unlockWithDevice() }
        } label: {
            Text("Unlock with \(method.name)").fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        .disabled(model.unlockState.authenticating).accessibilityFocused($unlockFocused)
        if model.configuration?.pinRetiredNotice == true {
            Text("App Lock now uses \(method.phrase) instead of a PIN.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        // Never a dead end: when the device can't unlock, the journals' own credential still can.
        if model.unlockState.problem && model.configuration?.requiresPassword == true {
            link("Use \(credentialName)") {
                usingCredential = true
                model.error = nil
            }
        }
    }

    @ViewBuilder private var credentialForm: some View {
        SecureField(credentialName, text: $credential).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
            .passwordAutofill().onSubmit { unlockWithCredential() }
        if let error = model.error { note(error) }
        Button {
            unlockWithCredential()
        } label: {
            Text("Unlock").fixedSize(horizontal: false, vertical: true)
        }.buttonStyle(.borderedProminent).disabled(credential.isEmpty)
        if !needsCredential {
            link("Use \(method.name)") {
                usingCredential = false
                credential = ""
                model.error = nil
            }
        }
        if model.libraryProblem == .needsKey { withoutCredential }
    }

    /// With the device key gone and the credential forgotten there is no other way on: restoring an archive, or erasing
    /// and connecting to a server again (docs/design/build-18-fixes-2026-10-06.md §2.1). One group for VoiceOver, whose
    /// label is the caption, so the buttons are read in its context.
    private var withoutCredential: some View {
        let caption = "Don’t have your \(credentialName)?"
        return VStack(spacing: 12) {
            Text(caption).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button {
                model.archiveImportRequested = true
            } label: {
                Text("Import Archive…").fixedSize(horizontal: false, vertical: true)
            }.buttonStyle(.plain).foregroundStyle(.tint)
            UnopenedEraseButton()
        }
        .accessibilityElement(children: .contain).accessibilityLabel(caption)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
    }

    private func link(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).fixedSize(horizontal: false, vertical: true)
        }.buttonStyle(.plain).foregroundStyle(.tint)
    }

    private func unlockWithCredential() {
        guard !credential.isEmpty else { return }
        Task {
            await model.unlockWithRecovery(credential)
            credential = ""
        }
    }
}

/// Says once why App Lock turned itself off.
struct AppLockTurnedOffAlert: ViewModifier {
    @ObservedObject var model: AppModel
    func body(content: Content) -> some View {
        content.alert(
            "App Lock Is Off",
            isPresented: Binding(
                get: { model.unlockState.turnedOff != nil && !model.locked },
                set: { if !$0 { model.unlockState.turnedOff = nil } })
        ) {
            Button("OK") { model.unlockState.turnedOff = nil }
        } message: {
            Text(message)
        }
    }
    private var message: String {
        #if os(macOS)
            switch model.unlockState.turnedOff {
            case .pinRetired:
                return "App Lock now uses your login password instead of a PIN. "
                    + "Your Mac user doesn’t have a login password, so App Lock is off."
            default:
                return "Your Mac user no longer has a login password. To use App Lock again, set a login password, "
                    + "then turn on App Lock in Settings ▸ Privacy."
            }
        #else
            let device = DeviceUnlockMethod.deviceName
            switch model.unlockState.turnedOff {
            case .pinRetired:
                return "App Lock now uses your \(device) passcode instead of a PIN. "
                    + "This \(device) doesn’t have a passcode, so App Lock is off."
            default:
                return "This \(device) no longer has a passcode. To use App Lock again, set a passcode, "
                    + "then turn on App Lock in Settings ▸ Privacy."
            }
        #endif
    }
}
