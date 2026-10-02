import JournalCore
import SwiftUI

struct CreateJournalView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var verify = ""
    /// Why Create didn't continue, shown under the fields.
    @State private var problem: String?
    @State private var choosingPassword = false
    @State private var revealed = false
    @State private var busy = false
    /// The field to focus next; the password fields take it, since a pushed step has focus of its own.
    @State private var focusRequest: MasterPasswordFields.Field?

    var body: some View {
        NavigationStack {
            #if os(iOS)
                // The password step is pushed, with the system back button and swipe back, as in Connect.
                step(choosingPassword: false)
                    .navigationDestination(isPresented: $choosingPassword) {
                        step(choosingPassword: true).navigationBarBackButtonHidden(busy)
                    }
            #else
                step(choosingPassword: choosingPassword)
            #endif
        }
        .interactiveDismissDisabled(busy)
        #if os(macOS)
            .frame(width: 520, height: choosingPassword ? 580 : 420)
        #endif
    }
    private func step(choosingPassword: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: choosingPassword ? "key" : "lock.shield")
                    .font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(choosingPassword ? "Choose a Master Password" : "Protect Your Journals")
                    .font(.title2.bold())
                Text(
                    "Encryption protects your stored writing. Use your master password to restore a backup or recover your journals."
                )
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if choosingPassword {
                    MasterPasswordFields(
                        password: $password, verify: $verify, problem: $problem, revealed: $revealed,
                        focusRequest: $focusRequest
                    ) { if canCreate { createEncrypted() } }
                    Text(
                        "Save this password in your password manager. If you lose it and access to your devices, you won’t be able to restore your journals. Keep a backup, too."
                    )
                    .font(.callout).foregroundStyle(.secondary)
                } else {
                    Button("Use Encryption") {
                        self.choosingPassword = true
                        focusRequest = .password
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Continue Without Encryption") { create(encrypted: false) }
                            .buttonStyle(.plain).foregroundStyle(.tint)
                        Text("Anyone with access to your files, server, or backups can read your journals.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                if let error = model.error { Text(error).foregroundStyle(.red) }
                if busy { ProgressView("Creating…") }
            }.padding(28).frame(maxWidth: 480, alignment: .leading).frame(maxWidth: .infinity)
        }.disabled(busy)
            .navigationTitle("")
            .toolbar {
                // On iPhone and iPad the password step has the system back button in Cancel's place.
                if !choosingPassword || !Self.pushesPasswordStep {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) {
                            password = ""
                            verify = ""
                            dismiss()
                        }.disabled(busy)
                    }
                }
                if choosingPassword {
                    if !Self.pushesPasswordStep {
                        ToolbarItem { Button("Back") { self.choosingPassword = false }.disabled(busy) }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { createEncrypted() }.disabled(!canCreate)
                    }
                }
            }
    }
    #if os(iOS)
        private static let pushesPasswordStep = true
    #else
        private static let pushesPasswordStep = false
    #endif
    private var canCreate: Bool { !busy && !password.isEmpty && !verify.isEmpty }
    /// The fields are compared on Create, with the reason under them.
    private func createEncrypted() {
        guard password == verify else {
            problem = "The passwords don’t match."
            focusRequest = .verify
            announceForAccessibility("The passwords don’t match.")
            return
        }
        create(encrypted: true)
    }
    private func create(encrypted: Bool) {
        busy = true
        model.error = nil
        Task {
            await model.start(password: encrypted ? password : nil, encrypted: encrypted)
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
