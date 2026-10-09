import SwiftUI

struct SaveFailureNotice: View {
    @EnvironmentObject private var model: AppModel
    let entryID: UUID
    @State private var operation: Task<Void, Never>?
    @State private var operationID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Not Saved")
                .foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            Button {
                retry()
            } label: {
                Text("Try Again").fixedSize(horizontal: false, vertical: true)
            }.disabled(operation != nil)
            if operation != nil { ProgressView("Saving…") }
        }
        .onAppear { JournalAccessibility.announce("Not Saved") }
        .onDisappear { cancel() }
        .onValueChange(of: model.locked) { if $0 { cancel() } }
        .onValueChange(of: model.replacingVault) { if $0 { cancel() } }
    }

    private func retry() {
        guard operation == nil else { return }
        let session = model.vaultSessionID
        let requestID = UUID()
        operationID = requestID
        operation = Task {
            defer {
                if operationID == requestID {
                    operation = nil
                    operationID = nil
                }
            }
            guard operationID == requestID, !Task.isCancelled, model.vaultSessionID == session,
                !model.locked, !model.replacingVault, model.draft?.id == entryID
            else { return }
            _ = await model.flush(whileEditing: entryID, announcing: .always)
        }
    }
    private func cancel() {
        operationID = nil
        operation?.cancel()
        operation = nil
    }
}

#if os(macOS)
    /// Explains, in the journal window, why writing does nothing while this Mac connects to a server from Settings.
    struct ConnectionPauseNotice: View {
        @EnvironmentObject private var model: AppModel
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @State private var shown: ServerConnectionPause?

        var body: some View {
            EncryptionNotice(upgrade: model.encryption)
            Group {
                if let shown {
                    // As the conflict notice: side by side, stacked at accessibility text sizes.
                    let layout =
                        dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout())
                    layout {
                        Text(
                            shown == .connecting
                                ? "Writing is paused while this Mac connects to your server."
                                : "This Mac couldn’t finish connecting to your server. Try again, or cancel to keep writing."
                        )
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                        // The connection sheet sits on the Settings window, over its Sync tab; this brings it forward.
                        Button("Show Connection") {
                            model.settingsTab = .sync
                            model.settingsPresented = true
                        }
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading).background(.quaternary)
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .default, value: shown)
            .task(id: model.serverConnectionPause) {
                let pause = model.serverConnectionPause
                // A quick connection finishes without the notice flashing up.
                if pause == .connecting {
                    do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                }
                shown = pause
            }
        }
    }
#endif
