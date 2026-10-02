import SwiftUI

struct LinkEditorView: View {
    @EnvironmentObject private var editor: EditorActions
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @FocusState private var focused: Bool
    private var valid: Bool { LinkAddress.url(address) != nil }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Text", text: $editor.linkText)
                TextField("Link", text: $address).autocorrectionDisabled().focused($focused)
                    #if os(iOS)
                        .keyboardType(.URL).textInputAutocapitalization(.never).submitLabel(.done)
                        // Return adds a valid link, as in Notes on iPhone and iPad; otherwise the address stays
                        // ready to correct.
                        .onSubmit {
                            if valid {
                                addLink()
                            } else {
                                focused = true
                                if !address.isEmpty { announceForAccessibility("Enter a valid web or email address.") }
                            }
                        }
                    #endif
                if !address.isEmpty && !valid {
                    Text("Enter a valid web or email address.").font(.callout).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
                .navigationTitle("Add Link")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { close() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add Link") { addLink() }.disabled(!valid)
                    }
                }
        }
        .onPresented { focused = true }
        .onDisappear { editor.performFormatting(.focus) }
        #if os(macOS)
            .frame(width: 420, height: 220)
        #endif
    }
    private func addLink() {
        guard let url = LinkAddress.url(address) else { return }
        editor.performFormatting(.link(url.absoluteString, text: editor.linkText))
        close()
    }
    /// Closes at once, without the sheet's animation, as the formatting controls do.
    private func close() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { dismiss() }
    }
}
