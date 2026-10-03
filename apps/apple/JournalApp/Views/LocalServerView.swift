#if os(macOS)
    import AppKit
    import JournalCore
    import SwiftUI

    struct LocalServerSection: View {
        @EnvironmentObject var model: AppModel
        @ObservedObject var controller: LocalServerController
        @State private var settingUp = false
        @State private var connecting: ConnectionRequest?
        var body: some View {
            Section("Server") {
                if controller.isConfigured {
                    Text("This Mac").font(.headline)
                    Text(controller.phase.rawValue).foregroundStyle(.secondary)
                    if controller.busy { ProgressView(controller.phase.rawValue) }
                    if controller.phase == .running {
                        SyncNowRows(activity: model.syncActivity) { connecting = ConnectionRequest() }
                        Button("Stop Server") { Task { await controller.stop() } }
                    } else {
                        Button("Start Server") { Task { await controller.start() } }.disabled(controller.busy)
                        Text("Other devices can sync when this server is running.").foregroundStyle(.secondary)
                    }
                    if model.saveFailure {
                        Text(SyncPauseNotice.saveFailed).foregroundStyle(.secondary)
                    } else if let error = model.syncError {
                        // Only when the sync itself failed; a problem with one entry or image explains itself.
                        if controller.phase == .running && model.syncFailed {
                            Text("The server is running, but couldn’t sync. Choose Sync Now to try again.")
                                .foregroundStyle(.secondary)
                        }
                        Text(error).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Connection Details") {
                        Text("Local Address").font(.headline)
                        Text(controller.address).textSelection(.enabled)
                        Button("Copy Local Address") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(controller.address, forType: .string)
                        }
                        Text(
                            "Other devices need a private HTTPS address. With Tailscale installed on this Mac, use Tailscale Serve for this local address, then connect using the HTTPS address it provides."
                        ).foregroundStyle(.secondary)
                        Text("tailscale serve --bg \(controller.address)").font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                        Text("Keep this Mac awake. The server runs until you quit My Journal.").foregroundStyle(
                            .secondary)
                    }
                } else if let connection = model.connection {
                    Text(connection.address).textSelection(.enabled)
                    SyncNowRows(activity: model.syncActivity) { connecting = ConnectionRequest() }
                    if model.saveFailure {
                        Text(SyncPauseNotice.saveFailed).foregroundStyle(.secondary)
                    } else if let error = model.syncError {
                        Text(error).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Your journals are saved on this device.")
                    if controller.hasSetup {
                        Text(
                            model.configuration?.requiresPassword == false
                                ? "Setup couldn’t finish. Try again."
                                : "Setup couldn’t finish. Use the same password or recovery key to try again."
                        )
                        .foregroundStyle(
                            .secondary)
                    }
                    if #available(macOS 14, *) {
                        Button(controller.hasSetup ? "Try Again…" : "Use This Mac…") { settingUp = true }
                            .disabled(model.configuration?.recoveryConfirmed != true)
                    } else {
                        Text("Running a server on this Mac requires macOS 14 or later.").foregroundStyle(.secondary)
                    }
                    Button("Connect to a Server…") { connecting = ConnectionRequest() }
                }
                if let error = controller.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }
            .onValueChange(of: controller.phase) { phase in
                NSAccessibility.post(
                    element: NSApp as Any,
                    notification: .announcementRequested,
                    userInfo: [
                        .announcement: phase.rawValue,
                        .priority: NSAccessibilityPriorityLevel.medium.rawValue,
                    ])
            }
            .sheet(isPresented: $settingUp) { LocalServerSetupView(controller: controller) }
            .sheet(item: $connecting) { _ in ConnectionView() }
            .onValueChange(of: model.locked) { locked in
                if locked {
                    settingUp = false
                    connecting = nil
                }
            }
        }
    }

    struct LocalServerSetupView: View {
        @EnvironmentObject var model: AppModel
        @Environment(\.dismiss) var dismiss
        @ObservedObject var controller: LocalServerController
        @State private var phrase = ""
        @State private var busy = false
        @State private var error: String?
        @State private var operation: Task<Void, Never>?
        @FocusState private var recoveryFocused: Bool
        var body: some View {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Use This Mac as Your Server").font(.title2.bold())
                        Text(
                            "Your journals will stay on this Mac. The server runs until you quit My Journal. To connect another device, keep this Mac awake and use a private connection such as Tailscale."
                        )
                        if model.configuration?.requiresPassword != false {
                            Text(
                                "Your \(model.configuration?.credentialName.lowercased() ?? "password") is needed to set up sync."
                            ).foregroundStyle(.secondary)
                            SecureField(
                                model.configuration?.credentialName ?? "Password or Recovery Key", text: $phrase
                            )
                            .passwordAutofill().textFieldStyle(.roundedBorder).focused(
                                $recoveryFocused
                            )
                            .disabled(busy).onSubmit { if !busy && !phrase.isEmpty { start() } }
                        }
                        if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                        if busy { ProgressView("Starting Server…") }
                    }.padding(24)
                }
                Divider()
                HStack {
                    Button("Cancel", role: .cancel) {
                        operation?.cancel()
                        controller.requestSetupCancellation()
                        dismiss()
                    }
                    Spacer()
                    Button("Start Server") { start() }.buttonStyle(.borderedProminent).disabled(
                        busy || (model.configuration?.requiresPassword != false && phrase.isEmpty))
                }.padding(24)
            }.frame(minWidth: 320, idealWidth: 480, minHeight: 320, idealHeight: 430)
                .onAppear { recoveryFocused = true }
                .keepsUnlockedWhile(busy)
                .onDisappear {
                    operation?.cancel()
                    controller.requestSetupCancellation()
                }
                .onValueChange(of: model.locked) { locked in
                    if locked {
                        phrase = ""
                        operation?.cancel()
                        controller.requestSetupCancellation()
                        dismiss()
                    }
                }
        }
        private func start() {
            busy = true
            error = nil
            operation = Task {
                defer { busy = false }
                do {
                    try await controller.setup(phrase: phrase)
                    phrase = ""
                    dismiss()
                } catch JournalError.invalidRecoveryKey {
                    error = "That password or recovery key isn’t correct. Try again."
                    recoveryFocused = true
                } catch is CancellationError {} catch JournalError.server(let message) {
                    error = message
                } catch { self.error = "Setup couldn’t finish. Your journals are still on this device. Try again." }
            }
        }
    }
#endif
