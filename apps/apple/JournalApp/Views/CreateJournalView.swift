import JournalCore
import SwiftUI

/// Start a Journal: one sheet, Choose a Master Password (docs/design/1-1-encryption-and-passwords.md §3.3). A new
/// library is always encrypted.
struct CreateJournalView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var verify = ""
    /// Why Create didn't continue, shown under the fields.
    @State private var problem: String?
    @State private var revealed = false
    @State private var busy = false
    /// The field to focus next; the first field takes it when the sheet appears.
    @State private var focusRequest: MasterPasswordFields.Field?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "key")
                        .font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
                    Text("Choose a Master Password").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text(
                        "Encryption protects your stored writing. Use your master password to restore a backup or recover your journals."
                    )
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    MasterPasswordFields(
                        password: $password, verify: $verify, problem: $problem, revealed: $revealed,
                        focusRequest: $focusRequest
                    ) { if canCreate { create() } }
                    Text(
                        "Save this password in your password manager. If you lose it and access to your devices, you won’t be able to restore your journals. Keep a backup, too."
                    )
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let error = model.error { Text(error).foregroundStyle(.red) }
                    if busy { ProgressView("Creating…") }
                }.padding(28).frame(maxWidth: 480, alignment: .leading).frame(maxWidth: .infinity)
            }.disabled(busy)
                .navigationTitle("")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) {
                            password = ""
                            verify = ""
                            dismiss()
                        }.disabled(busy)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { create() }.disabled(!canCreate)
                    }
                }
        }
        .interactiveDismissDisabled(busy)
        .onAppear { focusRequest = .password }
        #if os(macOS)
            .frame(width: 520, height: 580)
        #endif
    }
    private var canCreate: Bool { !busy && !password.isEmpty && !verify.isEmpty }
    /// The fields are compared on Create, with the reason under them.
    private func create() {
        guard password == verify else {
            problem = "The passwords don’t match."
            focusRequest = .verify
            announceForAccessibility("The passwords don’t match.")
            return
        }
        busy = true
        model.error = nil
        let chosen = password
        Task {
            await model.start(password: chosen)
            busy = false
            if model.error == nil, model.store != nil {
                password = ""
                verify = ""
                dismiss()
            }
        }
    }
}

/// The master password and its confirmation. They keep their own focus: a step pushed on iPhone and iPad is outside
/// the sheet's first view, and takes focus once its transition ends, as in Connect.
struct MasterPasswordFields: View {
    enum Field { case password, verify }
    @Binding var password: String
    @Binding var verify: String
    @Binding var problem: String?
    @Binding var revealed: Bool
    @Binding var focusRequest: Field?
    let submit: () -> Void
    @FocusState private var focused: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("Master Password", text: $password).focused($focused, equals: .password)
                .onSubmit { focused = .verify }
            field("Verify", text: $verify).focused($focused, equals: .verify).onSubmit(submit)
            if let problem { Text(problem).font(.callout).foregroundStyle(.red) }
            Toggle("Show Password", isOn: $revealed)
        }
        .task(id: focusRequest) {
            guard let request = focusRequest else { return }
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            focused = request
            focusRequest = nil
        }
    }
    @ViewBuilder private func field(_ name: String, text: Binding<String>) -> some View {
        Group {
            if revealed {
                TextField(name, text: text)
            } else {
                SecureField(name, text: text)
            }
        }
        .passwordAutofill(creating: true).autocorrectionDisabled().textFieldStyle(.roundedBorder)
        #if os(iOS)
            .textInputAutocapitalization(.never)
        #endif
        .onValueChange(of: text.wrappedValue) { _ in problem = nil }
    }
}
