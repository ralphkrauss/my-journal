import Foundation
import LocalAuthentication

#if os(iOS)
    import UIKit
#endif

/// What the device asks for to authenticate its owner (docs/design/app-lock-system-auth.md).
enum DeviceUnlockMethod: Equatable {
    case faceID, touchID, opticID, passcode, loginPassword

    /// "Face ID", or "Passcode" and "Login Password" when the device has no biometrics My Journal can use.
    var name: String {
        switch self {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .passcode: return "Passcode"
        case .loginPassword: return "Login Password"
        }
    }
    /// The words for what the person is asked for, in a sentence: "Face ID or your iPhone passcode".
    @MainActor var phrase: String {
        switch self {
        case .passcode: return "your \(DeviceUnlockMethod.deviceName) passcode"
        case .loginPassword: return "your login password"
        case .touchID:
            #if os(macOS)
                return "Touch ID or your login password"
            #else
                return "Touch ID or your \(DeviceUnlockMethod.deviceName) passcode"
            #endif
        default: return "\(name) or your \(DeviceUnlockMethod.deviceName) passcode"
        }
    }
    /// "iPhone", "iPad" or "Mac".
    @MainActor static var deviceName: String {
        #if os(macOS)
            return "Mac"
        #else
            return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }
}

enum DeviceOwnerAvailability: Equatable {
    case available(DeviceUnlockMethod)
    /// The device has no passcode, or the Mac user no login password.
    case noPasscode
    case unavailable
}

enum DeviceOwnerOutcome: Equatable {
    case success
    /// The person, the system or a lock cancelled the request. Nothing is said.
    case cancelled
    case noPasscode
    case failed
}

/// Face ID, Touch ID or Optic ID with the device passcode or Mac login password as the fallback, and Apple Watch on
/// the Mac when the system offers it: `LAPolicy.deviceOwnerAuthentication`, nothing of the app's own.
@MainActor
protocol DeviceOwnerAuthenticating: AnyObject {
    func availability() -> DeviceOwnerAvailability
    /// Asks the system; `reason` completes "My Journal is trying to …" on the Mac and is shown as is on iOS.
    func authenticate(reason: String) async -> DeviceOwnerOutcome
    /// Ends a request that is showing, which then reports `.cancelled`.
    func cancel()
}

@MainActor
final class SystemDeviceOwner: DeviceOwnerAuthenticating {
    /// The request that is showing, kept so that locking can end it.
    private var context: LAContext?

    /// The system's authentication, or in a debug build a scripted one that UI tests choose.
    static func make() -> DeviceOwnerAuthenticating {
        #if DEBUG
            if let script = ProcessInfo.processInfo.environment["JOURNAL_UI_TEST_DEVICE_AUTH"] {
                return ScriptedDeviceOwner(script: script)
            }
        #endif
        return SystemDeviceOwner()
    }

    func availability() -> DeviceOwnerAvailability {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return error?.code == LAError.passcodeNotSet.rawValue ? .noPasscode : .unavailable
        }
        return .available(Self.method(context))
    }

    func authenticate(reason: String) async -> DeviceOwnerOutcome {
        context?.invalidate()
        let context = LAContext()
        self.context = context
        defer { if self.context === context { self.context = nil } }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
                ? .success : .failed
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .systemCancel, .appCancel, .userFallback, .invalidContext, .notInteractive:
                return .cancelled
            case .passcodeNotSet:
                return .noPasscode
            default:
                return .failed
            }
        } catch {
            return .failed
        }
    }

    func cancel() {
        context?.invalidate()
        context = nil
    }

    /// Named from `biometryType`, so a Touch ID that is only out of reach (lid closed, keyboard unplugged) keeps its
    /// name. Only no enrolment, or Face ID denied to My Journal, falls back to the passcode or login password.
    private static func method(_ context: LAContext) -> DeviceUnlockMethod {
        var error: NSError?
        let usable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        #if os(macOS)
            let fallback = DeviceUnlockMethod.loginPassword
            let unusable: Set<Int> = [LAError.biometryNotEnrolled.rawValue, LAError.biometryNotPaired.rawValue]
        #else
            let fallback = DeviceUnlockMethod.passcode
            // On iOS, "not available" is how Face ID denied to this app is reported.
            let unusable: Set<Int> = [LAError.biometryNotEnrolled.rawValue, LAError.biometryNotAvailable.rawValue]
        #endif
        if !usable, let error, unusable.contains(error.code) { return fallback }
        if #available(iOS 17.0, macOS 14.0, *), context.biometryType == .opticID { return .opticID }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return fallback
        }
    }
}

#if DEBUG
    /// A stand-in for UI tests that can't answer a system prompt. The script lists answers in order, separated by
    /// commas, and the last one repeats: `success`, `cancel`, `failed`, `noPasscode` or `unavailable`.
    @MainActor
    final class ScriptedDeviceOwner: DeviceOwnerAuthenticating {
        private var answers: [String]
        init(script: String) { answers = script.split(separator: ",").map(String.init) }
        private var next: String { answers.first ?? "cancel" }
        func availability() -> DeviceOwnerAvailability {
            switch next {
            case "noPasscode": return .noPasscode
            case "unavailable": return .unavailable
            default: return .available(.faceID)
            }
        }
        func authenticate(reason: String) async -> DeviceOwnerOutcome {
            let answer = next
            if answers.count > 1 { answers.removeFirst() }
            switch answer {
            case "success": return .success
            case "noPasscode": return .noPasscode
            case "failed": return .failed
            default: return .cancelled
            }
        }
        func cancel() {}
    }
#endif
