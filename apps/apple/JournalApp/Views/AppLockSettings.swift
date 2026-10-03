import SwiftUI

/// Settings ▸ Privacy ▸ App Lock: one switch for the device's own authentication (docs/design/app-lock-system-auth.md).
struct AppLockSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    /// Closes Settings after Lock My Journal.
    let locked: () -> Void
    /// The value the switch shows while the system asks, before the change is saved.
    @State private var requested: Bool?
    @State private var failure: AppLockFailure?

    private enum AppLockFailure: String, Identifiable {
        case turnOn = "Couldn’t Turn On App Lock"
        case turnOff = "Couldn’t Turn Off App Lock"
        var id: String { rawValue }
    }

    private var availability: DeviceOwnerAvailability { model.unlockState.availability ?? .unavailable }
    private var usable: Bool {
        if case .available = availability { return true }
        return false
    }

    var body: some View {
        Section {
            Toggle(
                "Require \(availability.method.name)",
                isOn: Binding(get: { requested ?? model.appLockOn }, set: { change($0) })
            )
            // Turning off stays possible without a passcode; turning on needs one.
            .disabled(requested != nil || (!usable && !model.appLockOn))
            #if os(macOS)
                if model.appLockOn { InactivityLockPicker() }
            #endif
            if model.appLockOn {
                Button("Lock My Journal") {
                    Task {
                        await model.lock()
                        locked()
                    }
                }
            }
        } header: {
            Text("App Lock")
        } footer: {
            Text(footer)
        }
        .onAppear { model.refreshDeviceOwnerAvailability() }
        .alert(item: $failure) { failure in
            Alert(title: Text(failure.rawValue), message: Text("Try again."))
        }
    }

    private var footer: String {
        switch availability {
        case .available(let method):
            let phrase = method.phrase
            let who = phrase.prefix(1).uppercased() + phrase.dropFirst()
            return
                "\(who) is needed to open My Journal.\(model.automaticLockSentence) App Lock doesn’t change how your journals are encrypted."
        case .noPasscode:
            #if os(macOS)
                return "To use App Lock, set a login password for your Mac user in System Settings."
            #else
                return "To use App Lock, set a passcode for this \(DeviceUnlockMethod.deviceName) in Settings."
            #endif
        case .unavailable:
            return "App Lock isn’t available on this device."
        }
    }

    private func change(_ on: Bool) {
        guard requested == nil, on != model.appLockOn else { return }
        requested = on
        Task {
            let result = await model.setAppLock(on)
            requested = nil
            if result == .notSaved { failure = on ? .turnOn : .turnOff }
        }
    }
}
