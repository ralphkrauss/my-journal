import XCTest

@testable import Journal

/// Answers App Lock's requests for Face ID or the passcode as a test chooses, or holds a request until answered.
@MainActor
final class TestDeviceOwner: DeviceOwnerAuthenticating {
    var availabilityResult: DeviceOwnerAvailability = .available(.faceID)
    var outcome: DeviceOwnerOutcome = .success
    /// Keep requests showing until `answer(_:)`, as a person looking at the prompt would.
    var holdsRequests = false
    private(set) var requests = 0
    private var waiting: CheckedContinuation<DeviceOwnerOutcome, Never>?

    func availability() -> DeviceOwnerAvailability { availabilityResult }
    func authenticate(reason: String) async -> DeviceOwnerOutcome {
        requests += 1
        guard holdsRequests else { return outcome }
        return await withCheckedContinuation { waiting = $0 }
    }
    var showing: Bool { waiting != nil }
    func answer(_ outcome: DeviceOwnerOutcome) {
        waiting?.resume(returning: outcome)
        waiting = nil
    }
    /// A request the system already answered can't be withdrawn; this one keeps waiting for `answer(_:)`.
    func cancel() {}
}

extension AppModel {
    /// Turns App Lock on as if the device owner approved.
    func turnOnAppLockForTesting() async {
        deviceOwner = TestDeviceOwner()
        applicationActive = true
        let result = await setAppLock(true)
        XCTAssertEqual(result, .saved)
    }
    /// Unlocks as if the device owner approved.
    func unlockForTesting() async {
        deviceOwner = TestDeviceOwner()
        applicationActive = true
        await unlockWithDevice()
    }
}
