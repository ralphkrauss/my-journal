import Foundation
import JournalCore

/// End-to-end check of pins and journal order (docs/design/pinned-entries.md, journal-order.md) against a real server,
/// run by scripts/test-sync.sh as `library <address> <setup-code file>`:
/// - pins and a journal move reach the other device;
/// - changes to different pins and journals on both devices at once are all kept, with no review.
extension Probe {
    static func runLibraryProbe() async throws -> Bool {
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch arguments.first {
        case "library" where arguments.count == 3:
            let code = try String(contentsOfFile: arguments[2]).trimmingCharacters(in: .whitespacesAndNewlines)
            try await libraryRoundTrip(address: arguments[1], code: code)
        default: return false
        }
        return true
    }

    private struct LibraryDevice {
        let store: JournalStore
        let sync: SyncEngine
    }

    /// Two devices of a new library, the second added with the password.
    private static func libraryDevices(address: String, code: String, root: URL) async throws
        -> (mac: LibraryDevice, phone: LibraryDevice)
    {
        let anonymous = try ServerClient(address: address)
        let (key, phrase, envelope, secret) = try recoveryFixture()
        let macGrant = try await anonymous.initialize(
            code: code, envelope: envelope, recoverySecret: secret, deviceName: "Probe Mac")
        let phoneGrant = try await anonymous.recoverVault(
            phrase, parameters: anonymous.recoveryParameters(), deviceName: "Probe iPhone"
        ).grant
        return (
            try libraryDevice("mac", token: macGrant.token, address: address, key: key, root: root),
            try libraryDevice("phone", token: phoneGrant.token, address: address, key: key, root: root)
        )
    }
    private static func libraryDevice(_ name: String, token: String, address: String, key: Data, root: URL) throws
        -> LibraryDevice
    {
        let store = try JournalStore(directory: root.appendingPathComponent(name), key: key)
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
        let (mac, phone) = try await libraryDevices(address: address, code: code, root: root)
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
}
