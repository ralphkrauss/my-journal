import SwiftUI

/// The generated recovery key of a library from an early build, shown until the person confirms they saved it.
struct RecoveryView: View {
    @EnvironmentObject var model: AppModel
    let key: String
    @State private var saved = false
    @State private var confirmation = ""
    @State private var copied = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Keep Your Recovery Key").font(.title2.bold())
                Text(
                    "If you lose access to all your devices and this recovery key, you won’t be able to recover your journals."
                )
                Text(key).font(.system(.body, design: .monospaced)).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled).padding().frame(maxWidth: .infinity).background(.quaternary).cornerRadius(
                        8)
                Button("Copy Recovery Key") {
                    SensitivePasteboard.copy(key)
                    if !copied { announceForAccessibility(Self.copiedNote) }
                    copied = true
                }
                SaveRecoveryKeyButton(key: key)
                if copied { Text(Self.copiedNote).font(.callout).foregroundStyle(.secondary) }
                Text("Your recovery key is not a backup. You also need your server data or an exported archive.").font(
                    .callout
                ).foregroundStyle(.secondary)
                Toggle("I’ve saved my recovery key", isOn: $saved)
                TextField("Enter the last group to confirm", text: $confirmation).textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                Button("Continue") { model.confirmRecovery() }.buttonStyle(.borderedProminent)
                    .disabled(
                        !saved
                            || confirmation.trimmingCharacters(in: .whitespacesAndNewlines)
                                != key.components(separatedBy: "-").last
                    )
            }.padding(32).frame(maxWidth: 520).frame(maxWidth: .infinity)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private static let copiedNote = "The copied key is removed from the clipboard after 2 minutes."
}
