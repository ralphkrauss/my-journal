import Foundation
import JournalCore

/// End-to-end check of merging a device's journals into a server's library
/// (docs/design/join-with-local-journals.md), run by scripts/test-sync.sh against a disposable server as
/// `merge <address> <setup-code file>`. A first attempt stops after its images and some records reached the server,
/// as a dropped connection or a quit app would, and gives up its access. A second attempt, with new access, finishes
/// with every journal, entry and image once, a real server refusing any image sent again under its identity.
extension Probe {
    static func runMergeProbe() async throws -> Bool {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.first == "merge", arguments.count == 3 else { return false }
        let code = try String(contentsOfFile: arguments[2]).trimmingCharacters(in: .whitespacesAndNewlines)
        try await merge(address: arguments[1], code: code)
        return true
    }

    private static func merge(address: String, code: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("journal-merge-probe-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (master, _, envelope, recoverySecret) = try recoveryFixture()
        let protection = try envelope.contentProtection
        let anonymous = try ServerClient(address: address)
        let setUp = try await anonymous.initialize(
            code: code, envelope: envelope, recoverySecret: recoverySecret, deviceName: "Probe Mac")
        let macClient = try ServerClient(address: address, token: setUp.token)
        let mac = try JournalStore(directory: root.appendingPathComponent("mac"), key: master, protection: protection)
        let macSync = SyncEngine(store: mac, client: macClient)
        let macJournal = JournalItem(kind: "journal", title: "Default")
        try await mac.save(macJournal)
        try await mac.save(JournalItem(kind: "entry", journalID: macJournal.id, title: "From the Mac"))
        try await macSync.synchronize()

        // This device's own library: its own key when the server encrypts, none when it doesn't.
        let local = try JournalStore(
            directory: root.appendingPathComponent("phone"), key: try VaultCrypto.generateKey(), protection: protection)
        let journal = JournalItem(kind: "journal", title: "default")
        let travel = JournalItem(kind: "journal", title: "Travel")
        try await local.save(journal)
        try await local.save(travel)
        let image = Data(repeating: 9, count: 3000)
        let imageID = try await local.addAttachment(image)
        try await local.save(
            JournalItem(
                kind: "entry", journalID: journal.id, title: "Local thought",
                document: .init(blocks: [
                    DocumentBlock(runs: [TextRun("Written on the phone")]),
                    DocumentBlock(
                        kind: "image", attachmentID: imageID, imageDescription: "Photo", mediaType: "image/png"),
                ])))
        try await local.save(JournalItem(kind: "entry", journalID: travel.id, title: "Lisbon"))

        let first = try await pairingGrant(
            anonymous, approver: macClient, master: master, version: envelope.formatVersion)
        try await interruptedAttempt(
            local, address: address, grant: first, key: master, protection: protection, root: root)
        let second = try await pairingGrant(
            anonymous, approver: macClient, master: master, version: envelope.formatVersion)
        let staged = try await stagedMerge(
            local, address: address, grant: second, key: master, protection: protection,
            folder: root.appendingPathComponent("second"))
        let report = try await SyncEngine(store: staged, client: ServerClient(address: address, token: second.token))
            .synchronize()
        guard report.problem == nil, try await staged.pending().isEmpty, try await staged.attachmentsToVerify().isEmpty
        else { throw ProbeFailure("the merge that was tried again left records or images unsent") }

        try await macSync.synchronize()
        let items = try await mac.items()
        let defaults = items.filter { $0.kind == "journal" && $0.deletedAt == nil && $0.title == "Default" }
        let titles = items.filter { $0.kind == "entry" }.map(\.title).sorted()
        guard defaults.map(\.id) == [macJournal.id], titles == ["From the Mac", "Lisbon", "Local thought"] else {
            throw ProbeFailure("the merged library has missing or duplicated journals or entries: \(titles)")
        }
        let merged = items.first { $0.title == "Local thought" }
        guard let mergedImage = merged?.document.attachmentIDs.first, merged?.journalID == macJournal.id,
            try await mac.attachment(mergedImage) == image
        else { throw ProbeFailure("the merged entry isn't in the Mac's journal or its image doesn't open there") }
        print("PASS: an interrupted merge tried again with new access leaves every journal, entry and image once")

        let phoneSync = SyncEngine(store: staged, client: try ServerClient(address: address, token: second.token))
        try await sameNamesOnTwoDevices(mac: (mac, macSync), phone: (staged, phoneSync))
        let rejoin = RejoinContext(
            address: address, anonymous: anonymous, recoverySecret: recoverySecret, key: master, protection: protection,
            folder: root.appendingPathComponent("third"))
        try await deletedThenJoinedAgain(local, phone: (staged, phoneSync), mac: (mac, macSync), rejoin: rejoin)
    }

    /// Two devices name a journal alike before either has the other's: after syncing, both show the older one's name
    /// and the other numbered, with nothing to review (docs/design/journal-name-uniqueness.md §4.6).
    private static func sameNamesOnTwoDevices(
        mac: (JournalStore, SyncEngine), phone: (JournalStore, SyncEngine)
    ) async throws {
        let older = JournalItem(kind: "journal", title: "Work", date: Date(timeIntervalSince1970: 1_000))
        let newer = JournalItem(kind: "journal", title: "work", date: Date(timeIntervalSince1970: 2_000))
        try await mac.0.save(older)
        try await phone.0.save(newer)
        for engine in [mac.1, phone.1, mac.1] { try await engine.synchronize() }
        for store in [mac.0, phone.0] {
            let names = try await store.items().filter {
                JournalNames.isListed($0) && [older.id, newer.id].contains($0.id)
            }
            .map(\.title).sorted()
            let conflicts = try await store.conflicts()
            let pending = try await store.pending()
            guard names == ["Work", "work 2"], conflicts.isEmpty, pending.isEmpty else {
                throw ProbeFailure("journals named alike on two devices weren't numbered once: \(names)")
            }
        }
        print("PASS: journals named alike on two devices are numbered once, with nothing to review")
    }

    struct RejoinContext {
        let address: String
        let anonymous: ServerClient
        let recoverySecret: String
        let key: Data
        let protection: ContentProtection
        let folder: URL
    }
    /// The phone deletes a merged journal permanently; the Mac and the server keep it deleted. Joining again from the
    /// old library, with a recovery code as the owner's iPhone did, respects the deletion and keeps what the old library
    /// wrote since, where an offline write into that journal would go (§4.5, rule B).
    private static func deletedThenJoinedAgain(
        _ local: JournalStore, phone: (JournalStore, SyncEngine), mac: (JournalStore, SyncEngine),
        rejoin: RejoinContext
    ) async throws {
        guard let travel = try await local.items().first(where: { $0.kind == "journal" && $0.title == "Travel" })
        else { throw ProbeFailure("the phone's library has no Travel journal") }
        let items = try await phone.0.items()
        guard let merged = items.first(where: { JournalNames.isListed($0) && $0.title == "Travel" }) else {
            throw ProbeFailure("the merged Travel journal is missing")
        }
        _ = try await phone.0.deleteJournal(phone.0.prepareJournalDeletion(merged.id))
        try await phone.0.permanentlyDelete(phone.0.preparePermanentDeletion(merged.id))
        try await phone.1.synchronize()
        try await mac.1.synchronize()
        let onMac = try await mac.0.items()
        guard !onMac.contains(where: { JournalNames.isListed($0) && $0.title == "Travel" }),
            !onMac.contains(where: { $0.title == "Lisbon" })
        else { throw ProbeFailure("a journal deleted permanently on the phone is still on the Mac") }
        print("PASS: a journal deleted permanently on one device is gone on the other")

        try await local.save(JournalItem(kind: "entry", journalID: travel.id, title: "Porto"))
        let grant = try await rejoin.anonymous.recover(secret: rejoin.recoverySecret, deviceName: "Probe iPhone")
        let staged = try await stagedMerge(
            local, address: rejoin.address, grant: grant, key: rejoin.key, protection: rejoin.protection,
            folder: rejoin.folder)
        try await SyncEngine(store: staged, client: ServerClient(address: rejoin.address, token: grant.token))
            .synchronize()
        let conflicts = try await staged.conflicts()
        let pending = try await staged.pending()
        try await mac.1.synchronize()
        let after = try await mac.0.items()
        let snapshot = try await mac.0.lifecycleSnapshot()
        guard conflicts.isEmpty, pending.isEmpty,
            !after.contains(where: { JournalNames.isListed($0) && $0.title == "Travel" }),
            !after.contains(where: { $0.title == "Lisbon" }),
            let porto = after.first(where: { $0.title == "Porto" }), snapshot.location(of: porto) != .journal
        else {
            throw ProbeFailure("joining again brought back a journal deleted permanently, or lost what was written")
        }
        print("PASS: joining again with a recovery code keeps a deletion and what was written since")
    }

    /// Stops after the images and a journal were sent, then gives up its access, as the app does.
    private static func interruptedAttempt(
        _ local: JournalStore, address: String, grant: DeviceGrant, key: Data, protection: ContentProtection,
        root: URL
    ) async throws {
        let folder = root.appendingPathComponent("first")
        let staged = try await stagedMerge(
            local, address: address, grant: grant, key: key, protection: protection, folder: folder)
        let client = try ServerClient(address: address, token: grant.token)
        for image in try await staged.pendingAttachments() + staged.attachmentsToVerify() {
            try await client.upload(staged.encryptedAttachment(image), id: image)
        }
        let serverID = try await client.status().serverId
        // The journal is sent, not the entry that uses the image: the next attempt finds the image on the server
        // without any record that refers to it.
        for pending in try await staged.pending() where pending.kind == "journal" {
            guard case .accepted = try await client.push(pending, serverID: serverID) else {
                throw ProbeFailure("the first attempt's records weren't accepted")
            }
        }
        try await staged.close()
        try FileManager.default.removeItem(at: folder)
        try await client.revoke(grant.deviceId)
        do {
            _ = try await client.devices()
            throw ProbeFailure("access given up after a failed merge still works")
        } catch JournalError.unauthorized {}
    }

    /// Downloads everything the server has into a new staged store, then merges this device's library into it.
    private static func stagedMerge(
        _ local: JournalStore, address: String, grant: DeviceGrant, key: Data, protection: ContentProtection,
        folder: URL
    ) async throws -> JournalStore {
        let client = try ServerClient(address: address, token: grant.token)
        let staged = try JournalStore(directory: folder, key: key, protection: protection)
        try await SyncEngine(store: staged, client: client).synchronize()
        let server = try await client.status().serverId ?? client.address.absoluteString
        let readByAgents = try await client.journalsAgentsCanRead(vaultKey: key, protection: protection)
        try await staged.importMerging(from: local, server: server, readByAgents: readByAgents)
        return staged
    }
}
