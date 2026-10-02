import SwiftUI

/// Name Taken, after New Journal or Rename with a name another journal has (docs/design/journal-name-uniqueness.md
/// §4.1). OK returns to the name alert with the typed name kept.
struct JournalNameTakenAlert: ViewModifier {
    /// The name of the journal that has it; nil when nothing is shown.
    @Binding var takenName: String?
    let tryAgain: () -> Void

    func body(content: Content) -> some View {
        content.alert(
            "Name Taken",
            isPresented: Binding(get: { takenName != nil }, set: { if !$0 { takenName = nil } }),
            presenting: takenName
        ) { _ in
            Button("OK") {
                takenName = nil
                tryAgain()
            }
        } message: { name in
            Text("A journal named “\(name)” already exists. Choose a different name.")
        }
    }
}

extension View {
    func journalNameTakenAlert(_ takenName: Binding<String?>, tryAgain: @escaping () -> Void) -> some View {
        modifier(JournalNameTakenAlert(takenName: takenName, tryAgain: tryAgain))
    }
}

/// Shows an alert after the one that asked for it has closed: SwiftUI drops an alert presented while another
/// is still dismissing. Nothing is shown once the app has locked meanwhile.
@MainActor
func afterAlertCloses(_ model: AppModel, _ action: @escaping @MainActor () -> Void) {
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(350))
        guard !model.locked else { return }
        action()
    }
}
