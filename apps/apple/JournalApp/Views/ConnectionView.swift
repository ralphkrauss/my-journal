import JournalCore
import SwiftUI

/// One request to show Connect to a Server. Each tap makes a new one, so a sheet that couldn't be presented, for
/// example during another transition, never leaves later taps without effect.
struct ConnectionRequest: Identifiable {
    let id = UUID()
}

/// Connect to a Server (docs/design/connection-onboarding.md): choose a server by scanning a connected device's code,
/// from the servers on this network or by address, then set it up or add this device, one step at a time.
struct ConnectionView: View {
    @EnvironmentObject var model: AppModel
    var body: some View { ConnectionSheet(model: model) }
}

private struct ConnectionSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @StateObject private var flow: ConnectionFlow
    @StateObject private var browser = ServerBrowser()
    @State private var scanning = false
    @State private var searchedLong = false

    init(model: AppModel) { _flow = StateObject(wrappedValue: ConnectionFlow(model: model)) }

    var body: some View {
        NavigationStack(path: $flow.path) {
            Form {
                if model.locked {
                    Text("Unlock My Journal to connect to a server.")
                } else if let invite = flow.invite {
                    scannedServer(invite)
                } else {
                    chooseServer
                }
                if let error = flow.errorMessage(on: nil) {
                    Section { Text(error).foregroundStyle(.red).font(.callout) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Connect to a Server")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { flow.cancel() }.disabled(flow.installing)
                }
                ToolbarItem(placement: .confirmationAction) { primaryAction }
            }
            .navigationDestination(for: ConnectionFlow.Step.self) { ConnectionStepView(step: $0, flow: flow) }
        }
        #if os(macOS)
            // Fits the Settings window it's shown over; the steps scroll.
            .frame(minWidth: 440, idealWidth: 480, minHeight: 300, idealHeight: 340)
        #else
            .fullScreenCover(isPresented: $scanning) { ScanCodeView { flow.join($0) } }
        #endif
        .interactiveDismissDisabled(flow.installing)
        .keepsUnlockedWhile(flow.busy)
        .onDisappear {
            browser.stop()
            flow.close()
        }
        .onValueChange(of: model.locked) { locked in
            if locked { flow.cancel() }
        }
        .onValueChange(of: flow.finished) { if $0 { dismiss() } }
        .onValueChange(of: flow.scanRequested) { requested in
            guard requested else { return }
            flow.scanRequested = false
            #if os(iOS)
                scanning = true
            #endif
        }
        .onValueChange(of: choosing) { browse($0) }
        .onAppear {
            if flow.address.isEmpty { flow.address = model.connection?.address ?? "" }
            browse(choosing)
            // Reconnecting this device's server (set up again, connect again, or sign in after encryption was turned on
            // elsewhere) goes to its next step straight away.
            if model.reconnectsOnConnect, flow.path.isEmpty, !flow.address.isEmpty { flow.check() }
        }
    }

    // MARK: Choosing a server

    /// Browsing for servers runs only while the person is choosing one.
    private var choosing: Bool { !model.locked && flow.invite == nil && flow.path.isEmpty }
    private func browse(_ active: Bool) {
        if active {
            browser.start()
            searchedLong = false
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                searchedLong = true
            }
        } else {
            browser.stop()
        }
    }
    /// Scanning is offered whatever this device holds: a device with journals asks to merge them, naming the
    /// server, before anything is sent (docs/design/join-with-local-journals.md).
    private var canScan: Bool {
        #if os(iOS)
            ScanCodeView.available
        #else
            false
        #endif
    }
    @ViewBuilder private var chooseServer: some View {
        if canScan {
            Section {
                Button {
                    flow.error = nil
                    scanning = true
                } label: {
                    Label("Scan Code", systemImage: "qrcode.viewfinder")
                }
            } footer: {
                Text("On a connected device, open Settings > Devices > Add Device, then scan the code it shows.")
            }
        }
        Section("Servers on This Network") {
            ForEach(browser.servers) { server in
                Button {
                    flow.address = server.address
                    flow.chosenServer = server.address
                    flow.check()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.host).foregroundStyle(.primary)
                            if !server.name.isEmpty {
                                Text(server.name).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if flow.busy && flow.chosenServer == server.address {
                            ProgressView().controlSize(.small)
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(flow.busy)
                    .accessibilityLabel(server.name.isEmpty ? server.host : "\(server.host), \(server.name)")
            }
            if browser.state == .denied {
                Text(localNetworkDenied).foregroundStyle(.secondary).font(.callout)
            } else if browser.servers.isEmpty {
                if searchedLong {
                    Text("No servers found on this network.").foregroundStyle(.secondary)
                } else {
                    connectionStatus("Looking for servers…")
                }
            }
        }
        Section {
            // The section header names these fields; Mac forms would repeat it beside them.
            TextField("Server Address", text: $flow.address, prompt: Text(verbatim: "https://journal.example.ts.net"))
                .headedField("Server Address").autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never).keyboardType(.URL)
                #endif
                .disabled(flow.busy).onSubmit { checkAddress() }
            if flow.busy && flow.chosenServer == nil { connectionStatus("Checking…") }
        } header: {
            Text("Server Address")
        } footer: {
            Text("For Tailscale, use your server’s HTTPS address while connected to your tailnet.")
        }
    }
    private func checkAddress() {
        guard !flow.address.isEmpty, !flow.busy else { return }
        flow.chosenServer = nil
        flow.check()
    }
    private var localNetworkDenied: String {
        #if os(macOS)
            "To find servers automatically, allow My Journal in System Settings > Privacy & Security > Local Network."
        #else
            "To find servers automatically, turn on Local Network for My Journal in Settings."
        #endif
    }

    // MARK: Joining with a scanned code

    /// The server a scanned code names, while it's checked or when checking it failed. Merge Journals or Finish on
    /// Your Other Device follows.
    @ViewBuilder private func scannedServer(_ invite: PairingInvite) -> some View {
        Section { LabeledContent("Server", value: ServerAddress.host(invite.server)).textSelection(.enabled) }
        if flow.busy && flow.path.isEmpty { Section { connectionStatus("Checking…") } }
    }

    @ViewBuilder private var primaryAction: some View {
        if model.locked {
            EmptyView()
        } else if flow.invite != nil {
            if flow.error != nil && !flow.busy {
                Button(flow.canRetryScannedCode ? "Try Again" : "Scan Again") {
                    if flow.canRetryScannedCode {
                        flow.retryScannedCode()
                    } else {
                        flow.scanAgain()
                    }
                }
            }
        } else {
            Button("Continue") { checkAddress() }.disabled(flow.busy || flow.address.isEmpty)
        }
    }
}

/// Progress while waiting on the server or another device, beside its label as in Settings.
func connectionStatus(_ label: String) -> some View {
    HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text(label).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }.accessibilityElement(children: .combine)
}

/// Speaks a status change that appears while the person may be looking at another device.
@MainActor func announceForAccessibility(_ message: String) {
    #if os(macOS)
        NSAccessibility.post(
            element: NSApplication.shared, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    #else
        UIAccessibility.post(notification: .announcement, argument: message)
    #endif
}

extension View {
    /// A field whose section header already names it. Mac forms would repeat the name beside the field, so it's
    /// hidden there; VoiceOver still reads it.
    func headedField(_ name: String) -> some View {
        #if os(macOS)
            labelsHidden().accessibilityLabel(name)
        #else
            accessibilityLabel(name)
        #endif
    }
}
