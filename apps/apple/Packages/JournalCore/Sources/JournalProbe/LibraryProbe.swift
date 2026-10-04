import Foundation
import JournalCore

/// End-to-end check of pins and journal order (docs/design/pinned-entries.md, journal-order.md) against a real server,
/// run by scripts/test-sync.sh as `library <address> <setup-code file>`:
/// - the server takes the library record and lists `record-kinds`;
/// - pins and a journal move reach the other device;
/// - changes to different pins and journals on both devices at once are all kept, with no review.
///
/// With `library-held <address> <setup-code file> <state folder>` against a server without `record-kinds` (an older
/// build), pins stay on the device without an error; `library-released <address> <state folder>` then runs against
/// the updated server, and the pins arrive on the other device.
extension Probe {
    static func runLibraryProbe() async throws -> Bool {
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch arguments.first {
        case "library" where arguments.count == 3:
            let code = try String(contentsOfFile: arguments[2]).trimmingCharacters(in: .whitespacesAndNewlines)
            try await libraryRoundTrip(address: arguments[1], code: code)
        case "library-held" where arguments.count == 4:
            let code = try String(contentsOfFile: arguments[2]).trimmingCharacters(in: .whitespacesAndNewlines)
            try await libraryHeld(address: arguments[1], code: code, state: URL(fileURLWithPath: arguments[3]))
        case "library-released" where arguments.count == 3:
            try await libraryReleased(address: arguments[1], state: URL(fileURLWithPath: arguments[2]))
        default: return false
        }
        return true
    }

    private struct LibraryDevice {
        let store: JournalStore
        let sync: SyncEngine
    }
    private struct LibraryState: Codable {
        var macToken: String
        var phoneToken: String
        var key: Data
        var pinned: [UUID]
    }

    /// Two devices of a new library without encryption, the second added with the recovery code.
    private static func libraryDevices(address: String, code: String, root: URL) async throws
        -> (mac: LibraryDevice, phone: LibraryDevice, state: LibraryState)
    {
        let anonymous = try ServerClient(address: address)
        let secret = try VaultCrypto.random(32).map { String(format: "%02x", $0) }.joined()
        let macGrant = try await anonymous.initialize(
            code: code, envelope: .unprotected, recoverySecret: secret, deviceName: "Probe Mac")
        let phoneGrant = try await anonymous.recover(secret: secret, deviceName: "Probe iPhone")
        let key = try VaultCrypto.generateKey()
        let state = LibraryState(macToken: macGrant.token, phoneToken: phoneGrant.token, key: key, pinned: [])
        return (
            try libraryDevice("mac", token: state.macToken, address: address, key: key, root: root),
            try libraryDevice("phone", token: state.phoneToken, address: address, key: key, root: root), state
        )
    }
    private static func libraryDevice(_ name: String, token: String, address: String, key: Data, root: URL) throws
        -> LibraryDevice
    {
        let store = try JournalStore(directory: root.appendingPathComponent(name), key: key, protection: .plaintext)
        return LibraryDevice(
            store: store, sync: SyncEngine(store: store, client: try ServerClient(address: address, token: token)))
    }
    /// Journals Home and Work with two entries each, synchronized to both devices.
    private static func libraryContent(_ mac: LibraryDevice, _ phone: LibraryDevice) async throws -> [JournalItem] {
        var entries: [JournalItem] = []
        for title in ["Home", "Work"] {
            let journal = JournalItem(kind: "journal", title: title)
            try await mac.store.save(journal)
            for index in 0..<2 {
                let entry = JournalItem(
                    kind: "entry", journalID: journal.id, title: "\(title) \(index)", document: .plain("Text"))
                try await mac.store.save(entry)
                entries.append(entry)
            }
        }
        try await mac.sync.synchronize()
        try await phone.sync.synchronize()
        return entries
    }

    private static func libraryRoundTrip(address: String, code: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("journal-library-probe-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        guard try await ServerClient(address: address).status().supports("record-kinds") else {
            throw ProbeFailure("the server doesn't list record-kinds")
        }
        let (mac, phone, _) = try await libraryDevices(address: address, code: code, root: root)
        let entries = try await libraryContent(mac, phone)
        try await mac.store.setPinned(true, entry: entries[0].id)
        let shown = try await mac.store.arrangedJournals().map(\.id)
        try await mac.store.moveJournal(shown[1], shown: shown, to: 0)
        try await mac.sync.synchronize()
        try await phone.sync.synchronize()
        guard try await phone.store.libraryArrangement().pinned == [entries[0].id],
            try await phone.store.arrangedJournals().map(\.title) == ["Work", "Home"]
        else { throw ProbeFailure("the phone didn't receive the pin and the journal order") }
        print("PASS: a pin and a journal move reach the other device through the server")

        // At the same time: the Mac pins one entry and moves Home back to the top; the phone pins another and unpins
        // the first.
        try await mac.store.setPinned(true, entry: entries[1].id)
        let macShown = try await mac.store.arrangedJournals().map(\.id)
        try await mac.store.moveJournal(macShown[1], shown: macShown, to: 0)
        try await phone.store.setPinned(true, entry: entries[2].id)
        try await phone.store.setPinned(false, entry: entries[0].id)
        for device in [mac, phone, mac, phone, mac] { try await device.sync.synchronize() }
        let expected: Set<UUID> = [entries[1].id, entries[2].id]
        for device in [mac, phone] {
            guard try await device.store.libraryArrangement().pinned == expected,
                try await device.store.arrangedJournals().map(\.title) == ["Home", "Work"],
                try await device.store.conflicts().isEmpty
            else { throw ProbeFailure("changes made at the same time didn't all arrive, or became a review") }
        }
        print("PASS: pins and moves made on two devices at once are all kept, without a review")
    }

    private static func libraryHeld(address: String, code: String, state folder: URL) async throws {
        guard try await !ServerClient(address: address).status().supports("record-kinds") else {
            throw ProbeFailure("this check needs a server without record-kinds")
        }
        let (mac, phone, initial) = try await libraryDevices(address: address, code: code, root: folder)
        let entries = try await libraryContent(mac, phone)
        try await mac.store.setPinned(true, entry: entries[3].id)
        let report = try await mac.sync.synchronize(retryingRefused: true)
        guard report.problem == nil, report.settled, try await mac.store.pendingItemCount() == 0,
            try await mac.store.librarySyncState().waitingForServer
        else { throw ProbeFailure("a pin the server can't take was reported, counted or sent") }
        var state = initial
        state.pinned = [entries[3].id]
        try JSONEncoder().encode(state).write(to: folder.appendingPathComponent("state.json"))
        print("PASS: a server without record-kinds leaves pins on the device, with no error and nothing waiting")
    }

    private static func libraryReleased(address: String, state folder: URL) async throws {
        let state = try JSONDecoder().decode(
            LibraryState.self, from: Data(contentsOf: folder.appendingPathComponent("state.json")))
        defer { try? FileManager.default.removeItem(at: folder) }
        let mac = try libraryDevice("mac", token: state.macToken, address: address, key: state.key, root: folder)
        let phone = try libraryDevice("phone", token: state.phoneToken, address: address, key: state.key, root: folder)
        try await mac.sync.synchronize(retryingRefused: true)
        try await phone.sync.synchronize(retryingRefused: true)
        guard try await phone.store.libraryArrangement().pinned == Set(state.pinned),
            try await !mac.store.librarySyncState().waitingForServer
        else { throw ProbeFailure("pins held for an older server didn't arrive once it was updated") }
        print("PASS: once the server is updated, pins held on the device reach the other device")
    }
}
