import SwiftUI

/// Erase Journals and Settings… for journals that can't be opened: on the problem screen and on the lock screen of a
/// missing device key (docs/design/build-18-fixes-2026-10-06.md §2.1). It asks for the device's authentication when App
/// Lock is on or can't be known, shows what erasing removes, and doesn't ask again at Erase. Nothing is read.
struct UnopenedEraseButton: View {
    @EnvironmentObject private var model: AppModel
    @State private var warning: EraseWarning?
    @State private var checking = false
    @State private var erasing = false
    @State private var failed = false
    @State private var operation: Task<Void, Never>?

    var body: some View {
        Button("Erase Journals and Settings…", role: .destructive) { check() }
            .buttonStyle(.plain)
            // A plain button doesn't colour a destructive role itself, on the Mac or on iPhone and iPad.
            .foregroundStyle(Color.red)
            .fixedSize(horizontal: false, vertical: true)
            .disabled(checking || erasing)
            .alert(
                "Erase Journals and Settings?",
                isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil } }),
                presenting: warning
            ) { _ in
                Button("Erase", role: .destructive) { erase() }
                Button("Cancel", role: .cancel) {}
            } message: { shown in
                Text(EraseSection.message(shown))
            }
            .alert("Couldn’t Erase", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Nothing was removed from this device. Try again.")
            }
            .onDisappear {
                if !erasing { operation?.cancel() }
            }
    }

    /// Asks for authentication when it applies, then for the warning.
    private func check() {
        checking = true
        operation = Task {
            let found = await model.unopenedEraseWarning()
            checking = false
            guard !Task.isCancelled else { return }
            warning = found
        }
    }

    private func erase() {
        erasing = true
        operation = Task {
            let outcome = await model.eraseUnopenedLibrary()
            erasing = false
            if outcome == .failed {
                // The next alert can only appear once this one has gone.
                try? await Task.sleep(for: .milliseconds(350))
                failed = true
            }
        }
    }
}
