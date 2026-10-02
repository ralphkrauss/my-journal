import Foundation
import JournalCore

/// End-to-end check of turning on encryption for a synced library without it (docs/design/enable-encryption.md), run
/// by scripts/test-sync.sh against a disposable server as `encryption-switch <address> <setup-code file>`.
/// - A synchronization of the unencrypted library that runs after the server switched, as one already running when
///   the switch was asked would continue, stops instead of sending readable journals to the encrypted server.
/// - Another device that signs in again before the switching device uploaded its copy sends the same journals. The
///   switching device matches them rather than showing them for review, and its image and later edits still sync.
extension Probe {
    static func runEncryptionSwitchProbe() async throws -> Bool {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.first == "encryption-switch", arguments.count == 3 else { return false }
        let code = try String(contentsOfFile: arguments[2]).trimmingCharacters(in: .whitespacesAndNewlines)
        try await encryptionSwitch(address: arguments[1], code: code)
        return true
    }

    private static let readableCanary = "Readable only before encryption"

    private struct SwitchDevice {
        let store: JournalStore
        let client: ServerClient
        let sync: SyncEngine
        init(store: JournalStore, client: ServerClient) {
            self.store = store
            self.client = client
            sync = SyncEngine(store: store, client: client)
        }
    }

    private static func encryptionSwitch(address: String, code: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("journal-switch-probe-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let anonymous = try ServerClient(address: address)
        let secret = try VaultCrypto.random(32).map { String(format: "%02x", $0) }.joined()
        let macGrant = try await anonymous.initialize(
            code: code, envelope: .unprotected, recoverySecret: secret, deviceName: "Probe Mac")
        let mac = SwitchDevice(
            store: try JournalStore(
                directory: root.appendingPathComponent("mac"), key: VaultCrypto.generateKey(), protection: .plaintext),
            client: try ServerClient(address: address, token: macGrant.token))
        let journal = JournalItem(kind: "journal", title: "Home")
        try await mac.store.save(journal)
        let image = Data((0..<5000).map { UInt8($0 % 251) })
        let imageID = try await mac.store.addAttachment(image)
        let pictured = JournalItem(
            kind: "entry", journalID: journal.id, title: "Picture",
            document: .init(blocks: [
                DocumentBlock(runs: [TextRun(readableCanary)]),
                DocumentBlock(kind: "image", attachmentID: imageID, imageDescription: "Photo", mediaType: "image/png"),
            ]))
        try await mac.store.save(pictured)
        try await mac.store.save(
            JournalItem(kind: "entry", journalID: journal.id, title: "Plain", document: .plain(readableCanary)))
        try await mac.sync.synchronize()
        let phoneGrant = try await anonymous.recover(secret: secret, deviceName: "Probe iPhone")
        let phone = SwitchDevice(
            store: try JournalStore(
                directory: root.appendingPathComponent("phone"), key: VaultCrypto.generateKey(), protection: .plaintext),
            client: try ServerClient(address: address, token: phoneGrant.token))
        try await phone.sync.synchronize()
        guard try await phone.store.attachment(imageID) == image else {
            throw ProbeFailure("the iPhone didn't receive the image before encryption was turned on")
        }

        // The Mac turns on encryption as the app does: an encrypted copy, then the server switches.
        let key = try VaultCrypto.generateKey()
        let password = "probe master password"
        let (envelope, recoverySecret) = try VaultCrypto.makeRecovery(
            masterKey: key, phrase: password, formatVersion: 2)
        let macCopy = try await mac.store.reencryptedCopy(
            to: root.appendingPathComponent("mac-encrypted"), key: key, baseline: .restart)
        _ = try await mac.client.turnOnEncryption(
            envelope, recoverySecret: recoverySecret, currentRecoverySecret: nil, after: mac.store.syncedPosition())
        try await unencryptedSyncStops(mac)

        // The iPhone signs in again with the master password before the Mac uploaded its copy.
        do {
            try await phone.sync.synchronize()
            throw ProbeFailure("the iPhone kept its access after encryption was turned on")
        } catch let failure as SyncFailure where failure.health == .signInNeeded {}
        let recovered = try await anonymous.recoverVault(
            password, parameters: anonymous.recoveryParameters(), deviceName: "Probe iPhone")
        let rejoined = SwitchDevice(
            store: try await phone.store.reencryptedCopy(
                to: root.appendingPathComponent("phone-encrypted"), key: recovered.key, baseline: .reconcile),
            client: try ServerClient(address: address, token: recovered.grant.token))
        guard try await rejoined.sync.synchronize().problem == nil else {
            throw ProbeFailure("the iPhone couldn't send its journals after signing in again")
        }
        try await switchingDeviceMatches(SwitchDevice(store: macCopy, client: mac.client), other: rejoined, pictured)
        guard try await readableRecords(mac.client) == 0 else {
            throw ProbeFailure("the encrypted server holds readable journals")
        }
        print("PASS: the device that turned on encryption matches journals another device sent first, and they sync")
        for store in [mac.store, phone.store, macCopy, rejoined.store] { try await store.close() }
    }

    /// A synchronization of the unencrypted library after the switch is refused before it sends anything.
    private static func unencryptedSyncStops(_ mac: SwitchDevice) async throws {
        do {
            try await mac.sync.synchronize()
            throw ProbeFailure("the unencrypted library synchronized with the encrypted server")
        } catch let failure as SyncFailure where failure.health == .signInNeeded {}
        guard try await readableRecords(mac.client) == 0 else {
            throw ProbeFailure("the unencrypted library sent readable journals to the encrypted server")
        }
        print("PASS: a sync of the unencrypted library after the switch stops without sending readable journals")
    }

    /// The device that turned on encryption uploads its copy after `other` sent the same journals: nothing is shown
    /// for review, no image is refused, and a later edit reaches `other`.
    private static func switchingDeviceMatches(_ device: SwitchDevice, other: SwitchDevice, _ pictured: JournalItem)
        async throws
    {
        let report = try await device.sync.synchronize()
        guard report.problem == nil, try await device.store.pending().isEmpty,
            try await device.store.attachmentsToVerify().isEmpty
        else {
            throw ProbeFailure("the device that turned on encryption couldn't send its copy: \(report.problem ?? "")")
        }
        guard try await device.store.conflicts().isEmpty else {
            throw ProbeFailure("journals another device sent first are shown for review")
        }
        guard var edited = try await device.store.item(pictured.id) else {
            throw ProbeFailure("the device that turned on encryption lost an entry")
        }
        edited.title = "Edited after encryption"
        try await device.store.save(edited)
        guard try await device.sync.synchronize().problem == nil else {
            throw ProbeFailure("an edit after encryption couldn't sync")
        }
        try await other.sync.synchronize()
        guard try await other.store.item(pictured.id)?.title == "Edited after encryption" else {
            throw ProbeFailure("an edit after encryption didn't reach the other device")
        }
    }

    /// How many records on the server hold the canary in readable form.
    private static func readableRecords(_ client: ServerClient) async throws -> Int {
        var count = 0
        var cursor: Int64 = 0
        var more = true
        while more {
            let page = try await client.changes(after: cursor)
            for change in page.changes {
                guard let bytes = Data(base64Encoded: change.payload) else { continue }
                if bytes.range(of: Data(readableCanary.utf8)) != nil { count += 1 }
            }
            cursor = page.cursor
            more = page.hasMore
        }
        return count
    }
}
