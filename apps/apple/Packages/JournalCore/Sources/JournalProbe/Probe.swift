import CryptoKit
import Foundation
import JournalCore

/// A failed end-to-end check. Each check names what went wrong, so the script's output says which one failed.
struct ProbeFailure: Error, CustomStringConvertible, LocalizedError {
    let description: String
    init(_ check: String) { description = "FAIL: " + check }
    var errorDescription: String? { description }
}

@main
struct Probe {
    static func main() async throws {
        if try await runNamedCheck() { return }
        guard CommandLine.arguments.count == 3 else {
            fatalError("Usage: JournalProbe <loopback URL> <setup-code file>, or a restore phase (see RestoreProbe)")
        }
        let address = CommandLine.arguments[1]
        let code = try String(contentsOfFile: CommandLine.arguments[2]).trimmingCharacters(in: .whitespacesAndNewlines)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("journal-probe-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (master, phrase, envelope, recoverySecret) = try recoveryFixture()
        let anonymous = try ServerClient(address: address)
        let first = try await setUp(anonymous, code: code, envelope: envelope, recoverySecret: recoverySecret)
        let firstClient = try ServerClient(address: address, token: first.token)
        let firstStore = try JournalStore(directory: root.appendingPathComponent("mac"), key: master)
        let firstSync = SyncEngine(store: firstStore, client: firstClient)
        let journal = JournalItem(kind: "journal", title: "Private work")
        try await firstStore.save(journal)
        let image = Data(repeating: 42, count: 4096)
        let imageID = try await firstStore.addAttachment(image)
        var entry = entryFixture(journalID: journal.id, imageID: imageID)
        try await firstStore.save(entry)
        try await firstSync.synchronize()
        print("PASS: journal, entry and attachment uploaded")
        let (contents, phoneID) = try await pair(
            anonymous, approver: firstClient, master: master, version: envelope.formatVersion, name: "Probe iPhone")
        guard contents.masterKey == master, contents.recoveryVersion == envelope.formatVersion else {
            throw ProbeFailure("the paired device received a different key or recovery version")
        }
        print("PASS: both devices show the same check code before the key is sent")
        try await verifyDeviceOrigins(firstClient, setUp: first.deviceId, paired: phoneID)
        let phone = try ServerClient(address: address, token: contents.token)
        let phoneStore = try JournalStore(directory: root.appendingPathComponent("phone"), key: contents.masterKey)
        let phoneSync = SyncEngine(store: phoneStore, client: phone)
        try await phoneSync.synchronize()
        guard try await phoneStore.item(entry.id)?.title == entry.title,
            try await phoneStore.item(entry.id)?.document.markdown == entry.document.markdown,
            try await phoneStore.attachment(imageID) == image
        else { throw ProbeFailure("the approved device did not receive the entry text or image") }
        print("PASS: approved device reads synced content and image")
        entry.document = .plain("Mac offline edit")
        try await firstStore.save(entry)
        entry.document = .plain("Phone offline edit")
        try await phoneStore.save(entry)
        try await firstSync.synchronize()
        try await phoneSync.synchronize()
        let conflicts = try await phoneStore.conflicts()
        guard conflicts.isEmpty else {
            throw ProbeFailure("offline edits were left for review, not kept as two entries")
        }
        try await phoneSync.synchronize()
        try await firstSync.synchronize()
        let texts = Set(try await firstStore.items().filter { $0.kind == "entry" }.map(\.document.text))
        guard texts == Set(["Mac offline edit", "Phone offline edit"]) else {
            throw ProbeFailure("keeping both versions lost an edit")
        }
        print("PASS: concurrent offline edits are both kept as entries and converge")
        let (published, third, recoveredKey) = try await recoverReplacement(
            anonymous, phrase: phrase, envelope: envelope)
        let replacementStore = try JournalStore(
            directory: root.appendingPathComponent("replacement"), key: recoveredKey)
        let replacement = try ServerClient(address: address, token: third.token)
        try await SyncEngine(store: replacementStore, client: replacement).synchronize()
        guard try await replacementStore.items().count == 3 else {
            throw ProbeFailure("a recovered device lacks records")
        }
        try await firstClient.revoke(third.deviceId)
        do {
            _ = try await replacement.devices()
            throw ProbeFailure("a revoked device could still list devices")
        } catch JournalError.unauthorized {}
        print("PASS: recovery on a new client and device revocation")
        let reconnectGrant = try await anonymous.recoverVault(
            phrase, parameters: published, deviceName: "Reconnected Phone"
        ).grant
        let snapshotURL = root.appendingPathComponent("reconnected")
        try await phoneStore.snapshot(to: snapshotURL)
        let reconnectedStore = try JournalStore(directory: snapshotURL, key: recoveredKey)
        let reconnectedClient = try ServerClient(address: address, token: reconnectGrant.token)
        try await SyncEngine(store: reconnectedStore, client: reconnectedClient).synchronize()
        let reconnectedConflicts = try await reconnectedStore.conflicts()
        let reconnectedHistory = try await reconnectedStore.history(for: entry.id)
        // The version received before the phone's edit, and both versions from the review.
        let sourceHistory = try await phoneStore.history(for: entry.id)
        let copiedImage = try await reconnectedStore.encryptedAttachment(imageID)
        let sourceImage = try await phoneStore.encryptedAttachment(imageID)
        guard reconnectedConflicts.isEmpty, reconnectedHistory == sourceHistory, copiedImage == sourceImage else {
            throw ProbeFailure("the reconnected copy has conflicts, lost history or changed image bytes")
        }
        print("PASS: reconnect preserves exact image bytes and conflict history without false conflicts")
        try await verifyArchiveRecovery(
            sender: reconnectedStore, observer: phoneStore, client: reconnectedClient, observerClient: phone,
            entryID: entry.id, journalID: journal.id)
        try await verifyDeletionReceiving(
            clean: reconnectedStore, offline: phoneStore, client: reconnectedClient, offlineClient: phone,
            key: master, entryID: entry.id)
        try await verifyLocalJournalDeletion(
            sender: reconnectedStore, observer: firstStore, client: reconnectedClient, observerClient: firstClient,
            journalID: journal.id)
    }
    /// A restore phase, the agent check or the merge check, when the command line names one.
    private static func runNamedCheck() async throws -> Bool {
        if try await runRestorePhase() { return true }
        if try await runRollbackPhase() { return true }
        if try await runAgentProbe() { return true }
        if try await runAgentJournalsProbe() { return true }
        if try await runHealthCases() { return true }
        if try await runHealthProbe() { return true }
        if try await runWaitProbe() { return true }
        if try await runLibraryProbe() { return true }
        return try await runMergeProbe()
    }
    private static func verifyDeviceOrigins(_ client: ServerClient, setUp: UUID, paired: UUID) async throws {
        let devices = Dictionary(uniqueKeysWithValues: try await client.devices().map { ($0.id, $0) })
        guard devices[setUp]?.origin == .setup, devices[paired]?.origin == .pairing,
            devices[paired]?.approvedByDeviceId == setUp
        else { throw ProbeFailure("the device list doesn't say how each device was added") }
        print("PASS: the device list says how each device was added and which device approved a pairing")
    }
    /// Adds a device the way a new one recovers: anyone can read only what deriving the recovery secret needs, and
    /// the server sends the envelope once the secret is verified.
    private static func recoverReplacement(
        _ anonymous: ServerClient, phrase: String, envelope: RecoveryEnvelope
    ) async throws -> (RecoveryParameters, DeviceGrant, Data) {
        let published = try await anonymous.recoveryParameters()
        guard published.wrappedKey == nil, published.describes(envelope) else {
            throw ProbeFailure("anyone can read the wrapped vault key, or the published parameters differ")
        }
        let recovered = try await anonymous.recoverVault(phrase, parameters: published, deviceName: "Replacement Mac")
        guard RecoveryParameters(recovered.envelope) == RecoveryParameters(envelope) else {
            throw ProbeFailure("recovery returned a different envelope")
        }
        return (published, recovered.grant, recovered.key)
    }
    /// Sets up the server, checking that a wrong setup code or recovery secret is refused as such rather than as a
    /// device that lost access.
    private static func setUp(
        _ anonymous: ServerClient, code: String, envelope: RecoveryEnvelope, recoverySecret: String
    ) async throws -> DeviceGrant {
        let wrong = String(repeating: "0", count: 64)
        do {
            _ = try await anonymous.initialize(
                code: wrong, envelope: envelope, recoverySecret: recoverySecret, deviceName: "Probe Mac")
            throw ProbeFailure("the server accepted a wrong setup code")
        } catch JournalError.invalidSetupCode {}
        let grant = try await anonymous.initialize(
            code: code, envelope: envelope, recoverySecret: recoverySecret, deviceName: "Probe Mac")
        do {
            _ = try await anonymous.recover(secret: wrong, deviceName: "Probe Mac")
            throw ProbeFailure("the server accepted a wrong recovery secret")
        } catch JournalError.invalidRecoveryKey {}
        print("PASS: a wrong setup code or recovery secret is refused as such, not as lost device access")
        return grant
    }
    private static func entryFixture(journalID: UUID, imageID: UUID) -> JournalItem {
        JournalItem(
            kind: "entry", journalID: journalID, title: "Daily log",
            document: .init(blocks: [
                DocumentBlock(runs: [TextRun("Private cross-client sentinel")]),
                DocumentBlock(
                    kind: "image", attachmentID: imageID, imageDescription: "Test image", mediaType: "image/png"),
            ]))
    }

}
