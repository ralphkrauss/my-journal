import JournalCore
import SwiftUI

/// Erase Journals and Settings…, a standalone section at the end of Settings on iPhone and iPad and of General on the
/// Mac (docs/design/erase-device-2026-10-04.md): removes
/// this device's journals, settings and server connection, and returns to the first-launch screen. The server and
/// other devices aren't changed.
struct EraseSection: View {
    @EnvironmentObject private var model: AppModel
    /// Closes Settings once the journals are erased.
    let erased: () -> Void
    @State private var warning: EraseWarning?
    @State private var checking = false
    @State private var erasing = false
    @State private var exporting = false
    @State private var failed = false
    @State private var operation: Task<Void, Never>?

    var body: some View {
        Section {
            Button("Erase Journals and Settings…", role: .destructive) { check() }
                #if os(macOS)
                    // As Delete Journal…: a Mac form doesn't colour a destructive button itself.
                    .foregroundStyle(enabled ? Color.red : Color.secondary)
                #endif
                .disabled(!enabled)
        } footer: {
            Text(footer)
        }
        .alert(
            "Erase Journals and Settings?",
            isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil } }),
            presenting: warning
        ) { shown in
            if shown.losesJournals {
                // The sheet can only appear once the alert has gone.
                Button("Export Archive…") { afterAlertCloses(model) { exporting = true } }
            }
            Button("Erase", role: .destructive) { erase(shown) }
            Button("Cancel", role: .cancel) {}
        } message: { shown in
            Text(Self.message(shown))
        }
        .alert("Couldn’t Erase", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing was removed from this device. Try again.")
        }
        .sheet(isPresented: $exporting) { ArchiveExportSheet() }
        .onValueChange(of: model.locked) { locked in
            guard locked else { return }
            if !erasing { operation?.cancel() }
            warning = nil
            exporting = false
        }
        .onDisappear {
            if !erasing { operation?.cancel() }
        }
    }

    private var enabled: Bool { model.store != nil && model.eraseBlock == nil && !checking && !erasing }

    private var footer: String {
        if model.eraseBlock == .serverOnThisMac {
            return "Your other devices sync through this Mac, so its journals can’t be erased here."
        }
        return model.connection != nil
            ? "Removes your journals, settings and server connection from this device, as if My Journal had just been installed. Journals already on your server stay there."
            : "Removes your journals and settings from this device, as if My Journal had just been installed. This device isn’t syncing, so export an archive first to keep them."
    }

    /// Whenever something isn't safely on a server, the message starts with what to do about it.
    static func message(_ warning: EraseWarning) -> String {
        let undo = "You can’t undo this."
        switch warning {
        case .onServer(let host):
            return
                "Your journals stay on \(host) and come back when you connect this device again. This device will be signed out of \(host)."
        case .unsent(let count, let host):
            let items =
                count == 1 ? "1 item hasn’t reached \(host) yet" : "\(count) items haven’t reached \(host) yet"
            return "Export an archive first to keep everything. \(items) and will be lost. " + undo
        case .unconfirmed(let host):
            return
                "Export an archive first to keep everything. Your journals may not all be on \(host), and anything that isn’t will be lost. "
                + undo
        case .notSyncing:
            return
                "Export an archive first to keep your journals. This device isn’t syncing with a server, so they’ll be lost. "
                + undo
        case .nothingWritten:
            return "This removes your settings and any empty journals from this device."
        }
    }

    /// Saves the open writing and counts what erasing would lose, then asks.
    private func check() {
        checking = true
        operation = Task {
            let found = await model.eraseWarning()
            checking = false
            guard !Task.isCancelled, !model.locked else { return }
            warning = found
        }
    }

    private func erase(_ shown: EraseWarning) {
        erasing = true
        operation = Task {
            let outcome = await model.eraseLibrary(shown: shown)
            erasing = false
            switch outcome {
            case .erased:
                erased()
            case .changed(let current):
                // More would be lost than the alert said: it's shown again with what is there now.
                afterAlertCloses(model) { warning = current }
            case .failed:
                afterAlertCloses(model) { failed = true }
            case .cancelled:
                break
            }
        }
    }
}
