import SwiftUI

/// Add Link, and Edit Link with the link's own text and address and a way to remove it
/// (docs/design/build-18-fixes-2026-10-06.md §2.4).
struct LinkEditorView: View {
    @EnvironmentObject private var editor: EditorActions
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    /// The link being edited, captured when the sheet opened; nil when adding.
    @State private var link: EditableLink?
    @FocusState private var focused: Bool
    private var valid: Bool { LinkAddress.url(address) != nil }
    private var title: String { link == nil ? "Add Link" : "Edit Link" }
    /// Only plain one-line text can be changed, so an edit never drops an image or flattens paragraphs.
    private var showsText: Bool { link?.editsText ?? true }
    var body: some View {
        NavigationStack {
            Form {
                if showsText { TextField("Text", text: $editor.linkText) }
                TextField("Link", text: $address).autocorrectionDisabled().focused($focused)
                    #if os(iOS)
                        .keyboardType(.URL).textInputAutocapitalization(.never).submitLabel(.done)
                        // Return adds a valid link, as in Notes on iPhone and iPad; otherwise the address stays
                        // ready to correct.
                        .onSubmit {
                            if valid {
                                apply()
                            } else {
                                focused = true
                                if !address.isEmpty { announceForAccessibility("Enter a valid web or email address.") }
                            }
                        }
                    #endif
                if !address.isEmpty && !valid {
                    Text("Enter a valid web or email address.").font(.callout).foregroundStyle(.secondary)
                }
                if let link {
                    Section {
                        Button("Remove Link", role: .destructive) { remove(link) }
                            #if os(macOS)
                                .foregroundStyle(.red)
                            #endif
                    }
                }
            }.formStyle(.grouped)
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { close() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(link == nil ? "Add Link" : "Done") { apply() }.disabled(!valid)
                    }
                }
        }
        .onPresented {
            link = editor.editingLink
            address = link?.address ?? ""
            focused = true
        }
        .onDisappear { editor.performFormatting(.focus) }
        #if os(macOS)
            .frame(width: 420, height: link == nil ? 220 : 270)
        #endif
    }
    private func apply() {
        guard let url = LinkAddress.url(address) else { return }
        if let link {
            // The text is compared as strings when Done is pressed, not by whether the field was touched.
            let changed = editor.linkText != link.text
            editor.performFormatting(
                .editLink(link, address: url.absoluteString, text: changed ? editor.linkText : nil))
        } else {
            editor.performFormatting(.link(url.absoluteString, text: editor.linkText))
        }
        close()
    }
    private func remove(_ link: EditableLink) {
        editor.performFormatting(.removeLink(link.range))
        close()
    }
    /// Closes at once, without the sheet's animation, as the formatting controls do.
    private func close() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { dismiss() }
    }
}
