import JournalCore
import SwiftUI

/// The Devices section of Settings ▸ Sync (docs/design/1-1-settings-messages-editor.md §1.4): Add Device… first, then one
/// row for each device with a trailing Revoke Access…. It is shown only while the server accepts this device; when
/// access is refused, the Server section says why and offers Reconnect…. `reload` changes when a sheet opened from
/// the pane closes, so the list is read again.
struct DevicesSection: View {
    @EnvironmentObject var model: AppModel
    let reload: Int
    @State private var devices: [ServerDevice] = []
    @State private var loading = true
    @State private var busy = false
    @State private var error: String?
    @State private var refused = false
    @State private var add = false
    @State private var revoking: ServerDevice?
    @State private var failedRevoke: ServerDevice?

    var body: some View {
        Group {
            if !refused { section }
        }
        .task(id: reload) { await load() }
        .onValueChange(of: model.locked) { locked in
            if locked {
                devices = []
                add = false
                revoking = nil
            }
        }
    }

    private var section: some View {
        Section {
            Button("Add Device…") { add = true }.disabled(busy || loading)
            if loading && error == nil { ProgressView("Loading Devices…") }
            ForEach(devices.filter { !$0.revoked }) { device in
                let isThisDevice = device.id == model.connection?.deviceID
                DeviceRow(
                    name: device.name, added: descriptions.added(device), isThisDevice: isThisDevice,
                    revokeLabel: isThisDevice ? nil : descriptions.revokeLabel(device), busy: busy
                ) { revoking = device }
            }
            if let error {
                Text(error).foregroundStyle(.secondary)
                Button("Try Again") {
                    Task { if let failedRevoke { await revoke(failedRevoke) } else { await load() } }
                }.disabled(busy || loading)
            }
        } header: {
            Text("Devices")
        }
        .onValueChange(of: error) { message in
            if let message { JournalAccessibility.announce(message) }
        }
        .sheet(isPresented: $add, onDismiss: { Task { await load() } }) { AddDeviceView() }
        .confirmationDialog(
            revoking.map { "Revoke access for \($0.name)?" } ?? "Revoke access?",
            isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
            titleVisibility: .visible
        ) {
            Button("Revoke Access", role: .destructive) {
                if let device = revoking { Task { await revoke(device) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let consequence =
                "This stops future sync. Journals already downloaded to that device can’t be erased remotely."
            // Another device with the same name: say which one this is.
            if let revoking, descriptions.hasNamesake(revoking) {
                Text(descriptions.added(revoking) + ". " + consequence)
            } else {
                Text(consequence)
            }
        }
    }

    private var descriptions: DeviceDescriptions {
        DeviceDescriptions(devices: devices, recoveryVersion: model.configuration?.recovery.formatVersion)
    }

    private func load() async {
        guard model.connection != nil, !model.locked else {
            loading = false
            return
        }
        loading = true
        defer { loading = false }
        do {
            let result = try await model.connectedClient().devices()
            guard !model.locked else { return }
            devices = result
            refused = false
            error = nil
            failedRevoke = nil
        } catch JournalError.unauthorized {
            // The Server section explains why, once a sync has learned it.
            refused = true
            await model.learnWhyAccessWasRefused()
        } catch {
            self.error = "Couldn’t load devices. Check your connection and try again."
        }
    }

    private func revoke(_ device: ServerDevice) async {
        busy = true
        defer { busy = false }
        do {
            try await model.connectedClient().revoke(device.id)
            // Kept in the list as revoked, so devices it approved still name it.
            if let index = devices.firstIndex(where: { $0.id == device.id }) { devices[index].revoked = true }
            failedRevoke = nil
            error = nil
        } catch {
            failedRevoke = device
            self.error = "Couldn’t revoke access. Check your connection and try again."
        }
    }
}

/// One device in the list: its name, "This Device" when it is, and how it was added, read as one element, with a
/// trailing Revoke Access… for every other device (under the text at accessibility sizes).
private struct DeviceRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let name: String
    let added: String
    let isThisDevice: Bool
    /// The accessibility label of Revoke Access…, or nil for this device, which has none.
    let revokeLabel: String?
    let busy: Bool
    let revoke: () -> Void

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
        layout {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                Group {
                    if isThisDevice { Text("This Device") }
                    Text(added)
                }.font(.subheadline).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
            if !stacked { Spacer() }
            if let revokeLabel {
                Button("Revoke Access…", role: .destructive, action: revoke).disabled(busy)
                    #if os(iOS)
                        // Only the button is tappable, not the whole row.
                        .buttonStyle(.borderless)
                    #endif
                    .accessibilityLabel(revokeLabel)
            }
        }
    }
}

/// How Settings ▸ Sync ▸ Devices says when and how each device was added, with just enough detail to tell devices with the
/// same name apart: iOS reports only “iPhone” or “iPad” as a device’s name.
struct DeviceDescriptions {
    private enum Detail: Int { case date, time, identifier }
    private let devices: [ServerDevice]
    private let recoveryVersion: Int?
    private var details: [UUID: Detail] = [:]

    /// `devices` includes revoked devices, which can still be named as the device that approved another.
    init(devices: [ServerDevice], recoveryVersion: Int?) {
        self.devices = devices
        self.recoveryVersion = recoveryVersion
        let listed = devices.filter { !$0.revoked }
        for device in listed { details[device.id] = .date }
        // Devices that would read the same get the time, and only if that isn't enough, part of their identifier.
        for detail in [Detail.date, .time] {
            let same = Dictionary(grouping: listed.filter { details[$0.id] == detail }) {
                $0.name + "\n" + sentence($0, detail: detail)
            }
            for group in same.values where group.count > 1 {
                for device in group { details[device.id] = Detail(rawValue: detail.rawValue + 1) }
            }
        }
    }
    /// For example “Added by Alex’s MacBook Pro on 28 Sep 2026”.
    func added(_ device: ServerDevice) -> String { sentence(device, detail: details[device.id] ?? .date) }
    func hasNamesake(_ device: ServerDevice) -> Bool {
        devices.contains { !$0.revoked && $0.id != device.id && $0.name == device.name }
    }
    func revokeLabel(_ device: ServerDevice) -> String {
        "Revoke access for \(device.name)" + (hasNamesake(device) ? ", " + added(device) : "")
    }
    private func sentence(_ device: ServerDevice, detail: Detail) -> String {
        var when = device.createdAt.formatted(date: .abbreviated, time: .omitted)
        if detail != .date { when += " at " + device.createdAt.formatted(date: .omitted, time: .shortened) }
        if detail == .identifier { when += " · " + device.id.uuidString.lowercased().prefix(8) }
        switch device.origin {
        case .pairing:
            if let approver = devices.first(where: { $0.id == device.approvedByDeviceId }) {
                return "Added by \(approver.name) on \(when)"
            }
            return "Added with a pairing code on \(when)"
        case .setup: return "Added during server setup on \(when)"
        case .recovery:
            switch recoveryVersion {
            case 1: return "Added with your recovery key on \(when)"
            case 3: return "Added with your access password on \(when)"
            case 4: return "Added with a recovery code on \(when)"
            default: return "Added with your master password on \(when)"
            }
        case .unknown: return "Added on \(when)"
        }
    }
}
