import Foundation

@testable import JournalCore

/// What a healthy server answers at GET /v1/status, for tests that need a server this app syncs with and care about
/// something else: protocol revision 1 and the 13 capability names, as a 1.1 server lists them. A test of a server
/// that is too old builds its own status; it must not start from this one.
extension ServerStatus {
    static func healthy(
        serverId: String? = "test-server", initialized: Bool = true, mcpUrl: String? = nil
    ) -> ServerStatus {
        ServerStatus(
            protocolVersion: 1, protocolRevision: 1, initialized: initialized, recoveryVersions: [1, 2, 3, 4],
            features: ServerStatus.revisionOneFeatures, serverId: serverId, mcpUrl: mcpUrl)
    }
}
