import Foundation
import JournalCore

/// What a healthy server answers at GET /v1/status, for tests that need a server this app syncs with and care about
/// something else: protocol revision 1 and the 13 capability names a 1.1 server lists. A test of a server that is too
/// old builds its own body; it must not start from this one.
enum HealthyStatus {
    static func json(
        serverId: String? = nil, initialized: Bool = true, recoveryVersions: [Int] = [1, 2, 3, 4],
        mcpUrl: String? = nil
    ) -> Data {
        var body: [String: Any] = [
            "protocolVersion": 1, "protocolRevision": 1, "initialized": initialized,
            "recoveryVersions": recoveryVersions, "features": ServerStatus.revisionOneFeatures,
        ]
        if let serverId { body["serverId"] = serverId }
        if let mcpUrl { body["mcpUrl"] = mcpUrl }
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }
    /// The same body as text, for fake servers that answer with strings.
    static func text(serverId: String? = nil, initialized: Bool = true, mcpUrl: String? = nil) -> String {
        String(decoding: json(serverId: serverId, initialized: initialized, mcpUrl: mcpUrl), as: UTF8.self)
    }
}
