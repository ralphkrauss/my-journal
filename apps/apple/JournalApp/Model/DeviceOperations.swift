import JournalCore
import SwiftUI

/// The connected server's client, the name this device has in its device list, and approving another device.
extension AppModel {
    func connectedClient() throws -> ServerClient {
        guard !locked, let connection else { throw JournalError.locked }
        return try ServerClient(address: connection.address, token: connection.token)
    }
    func approveDevice(_ approval: PairingApproval) async throws {
        guard !locked, let key = masterKey else { throw JournalError.locked }
        try await connectedClient().approvePairing(
            approval, masterKey: key, recoveryVersion: configuration?.recovery.formatVersion ?? 1)
    }
    var deviceName: String {
        #if os(macOS)
            Host.current().localizedName ?? "Mac"
        #else
            UIDevice.current.name
        #endif
    }
}
