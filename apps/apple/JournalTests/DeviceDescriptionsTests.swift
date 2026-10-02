import JournalCore
import XCTest

@testable import Journal

/// iOS reports every iPhone as “iPhone”, so Settings ▸ Devices must still let the person tell apart the device they
/// revoke from the one they keep.
@MainActor
final class DeviceDescriptionsTests: XCTestCase {
    func testDevicesWithTheSameNameGetJustEnoughDetailToTellThemApart() {
        let mac = ServerDevice(
            id: UUID(), name: "Ralph’s MacBook Pro", createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            revoked: true, createdVia: "setup")
        let morning = Date(timeIntervalSince1970: 1_800_086_400)
        let first = ServerDevice(
            id: UUID(), name: "iPhone", createdAt: morning, revoked: false, createdVia: "pairing",
            approvedByDeviceId: mac.id)
        let later = ServerDevice(
            id: UUID(), name: "iPhone", createdAt: morning.addingTimeInterval(3_600), revoked: false,
            createdVia: "pairing", approvedByDeviceId: mac.id)
        let sameMinute = ServerDevice(
            id: UUID(), name: "iPhone", createdAt: morning.addingTimeInterval(3_610), revoked: false,
            createdVia: "pairing", approvedByDeviceId: mac.id)
        let iPad = ServerDevice(id: UUID(), name: "iPad", createdAt: morning, revoked: false)
        let descriptions = DeviceDescriptions(devices: [mac, first, later, sameMinute, iPad], recoveryVersion: 2)
        let day = morning.formatted(date: .abbreviated, time: .omitted)
        // A revoked device is still named as the one that approved the others.
        XCTAssertEqual(
            descriptions.added(first),
            "Added by Ralph’s MacBook Pro on \(day) at \(morning.formatted(date: .omitted, time: .shortened))")
        XCTAssertTrue(descriptions.added(later).hasSuffix(" · " + later.id.uuidString.lowercased().prefix(8)))
        XCTAssertTrue(descriptions.added(sameMinute).hasSuffix(" · " + sameMinute.id.uuidString.lowercased().prefix(8)))
        XCTAssertNotEqual(descriptions.added(later), descriptions.added(sameMinute))
        // A name nobody else has keeps the short form, and an older server's device says only when.
        XCTAssertEqual(descriptions.added(iPad), "Added on \(day)")
        XCTAssertFalse(descriptions.hasNamesake(iPad))
        XCTAssertTrue(descriptions.hasNamesake(first))
        XCTAssertEqual(descriptions.revokeLabel(first), "Revoke access for iPhone, " + descriptions.added(first))
        XCTAssertEqual(descriptions.revokeLabel(iPad), "Revoke access for iPad")
    }
}
