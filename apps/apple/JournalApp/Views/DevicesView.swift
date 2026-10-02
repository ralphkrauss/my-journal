import JournalCore
import SwiftUI

struct DevicesView: View {
    @EnvironmentObject var model: AppModel
    @State private var devices: [ServerDevice] = []
    @State private var loading = true
    @State private var busy = false
    @State private var error: String?
    @State private var unauthorized = false
    @State private var add = false
    @State private var connect = false
    @State private var revoking: ServerDevice?
    @State private var failedRevoke: ServerDevice?
    var body: some View {
        Form {
            if model.locked {
                Text("Unlock My Journal to view Devices.")
            } else if model.connection == nil {
                Text("Connect to a server to add your other devices.").foregroundStyle(.secondary)
                Button("Connect to a Server…") { connect = true }
            } else {
                if loading { ProgressView("Loading Devices…") }
                ForEach(devices.filter { !$0.revoked }) { device in
                    Section {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(device.name)
                            Group {
                                if device.id == model.connection?.deviceID { Text("This Device") }
                                Text(descriptions.added(device))
                            }.font(.subheadline).foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
                        if device.id != model.connection?.deviceID {
                            Button("Revoke Access…", role: .destructive) { revoking = device }.disabled(busy)
                                .accessibilityLabel(descriptions.revokeLabel(device))
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.secondary) }
                if unauthorized {
                    let action = model.syncStatusAction
                    Button(action.connects ? action.title : "Connect Again…") { connect = true }
                } else {
                    if error != nil {
                        Button("Try Again") {
                            Task { if let failedRevoke { await revoke(failedRevoke) } else { await load() } }
                        }.disabled(busy)
                    }
                    Button("Add Device…") { add = true }.disabled(busy || loading)
                }
            }
        }.formStyle(.grouped)
            .task { await load() }
            .sheet(isPresented: $add, onDismiss: { Task { await load() } }) { AddDeviceView() }
            .sheet(isPresented: $connect) { ConnectionView() }
            .onValueChange(of: model.locked) { locked in
                if locked {
                    devices = []
                    add = false
                    connect = false
                    revoking = nil
                }
            }
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
        error = nil
        unauthorized = false
        defer { loading = false }
        do {
            let result = try await model.connectedClient().devices()
            if !model.locked { devices = result }
        } catch JournalError.unauthorized {
            unauthorized = true
            error = await model.lostAccessHealth().message()
        } catch {
            self.error = "Couldn’t load devices. Check your connection and try again."
        }
    }
    private func revoke(_ device: ServerDevice) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await model.connectedClient().revoke(device.id)
            devices.removeAll { $0.id == device.id }
            failedRevoke = nil
        } catch {
            failedRevoke = device
            self.error = "Couldn’t revoke access. Check your connection and try again."
        }
    }
}

/// How Settings ▸ Devices says when and how each device was added, with just enough detail to tell devices with the
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
