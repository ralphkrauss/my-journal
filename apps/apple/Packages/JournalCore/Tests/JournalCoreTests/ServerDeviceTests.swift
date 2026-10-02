import XCTest

@testable import JournalCore

/// Settings ▸ Devices must keep working with servers from before and after the fields that say how a device joined.
final class ServerDeviceTests: XCTestCase {
    func testDevicesFromOlderAndNewerServersAllDecode() throws {
        let approver = UUID()
        let json = """
            [
              {"id":"\(UUID())","name":"Ralph’s MacBook Pro","createdAt":"2026-09-27T10:00:00Z","revoked":false,
               "createdVia":"setup","approvedByDeviceId":null},
              {"id":"\(UUID())","name":"iPhone","createdAt":"2026-09-28T12:05:00.123Z","revoked":false,
               "createdVia":"pairing","approvedByDeviceId":"\(approver)"},
              {"id":"\(UUID())","name":"iPad","createdAt":"2026-09-28T12:06:00Z","revoked":true},
              {"id":"\(UUID())","name":"iPhone","createdAt":"2026-09-29T08:00:00Z","revoked":false,
               "createdVia":"migration","approvedByDeviceId":"not an identifier"}
            ]
            """
        let devices = try JournalCoding.decoder().decode([ServerDevice].self, from: Data(json.utf8))
        XCTAssertEqual(devices.map(\.origin), [.setup, .pairing, .unknown, .unknown])
        XCTAssertEqual(devices[1].approvedByDeviceId, approver)
        XCTAssertNil(devices[0].approvedByDeviceId)
        XCTAssertNil(devices[2].createdVia)
        XCTAssertNil(devices[3].approvedByDeviceId)
        XCTAssertTrue(devices[2].revoked)
    }
}
