import JournalCore
import SwiftUI
import UniformTypeIdentifiers

struct ArchiveControls: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Section {
            ArchiveExportControls()
            ArchiveImportButton()
        } header: {
            Text("Archive")
        } footer: {
            ArchiveFooter()
        }
    }
    static func explanation(_ model: AppModel) -> String {
        model.configuration?.encrypted == false
            ? "An archive includes readable entries, images and earlier versions. Keep it private."
            : "An archive is an encrypted copy of your journals, including images and earlier versions. It opens only with your \(model.configuration?.credentialName.lowercased() ?? "password")."
    }
}

/// Under Export Archive: what an archive is and, for a master password, the way to make sure of the password
/// (Change Password asks for the current one, which checks it; docs/design/1-1-encryption-and-passwords.md §4.2).
struct ArchiveFooter: View {
    @EnvironmentObject private var model: AppModel
    @State private var changingPassword = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ArchiveControls.explanation(model))
            if model.configuration?.recovery.formatVersion == 2 {
                Button("Not sure of your password? Change Password…") { changingPassword = true }
                    .buttonStyle(.borderless).disabled(model.locked)
                    .sheet(isPresented: $changingPassword) { ChangePasswordView() }
            }
        }
    }
}

/// File ▸ Export Archive… on the Mac and iPad.
struct ArchiveExportSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ArchiveExportControls()
                } footer: {
                    ArchiveFooter()
                }
            }
            .formStyle(.grouped).navigationTitle("Export Archive")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
            .frame(minWidth: 460, minHeight: 220)
        #endif
        .onValueChange(of: model.locked) { if $0 { dismiss() } }
    }
}

struct ArchiveExportControls: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var export = ArchiveExport()
    var body: some View {
        Group {
            // The row keeps its size while preparing: the spinner appears at its trailing end, after a short delay.
            HStack {
                Button("Export Archive…") { export.start(with: model) }.disabled(export.showsProgress)
                Spacer(minLength: 0)
                if export.showsProgress {
                    ProgressView().controlSize(.small).accessibilityLabel("Preparing Archive…")
                }
            }
            if let error = export.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            // After the save dialog saved the archive, until the next export.
            if export.saved, let message = model.archiveSavedMessage {
                Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onValueChange(of: export.saved) { saved in
            if saved, let message = model.archiveSavedMessage { announceForAccessibility(message) }
        }
        .fileExporter(
            isPresented: $export.presenting, document: export.document, contentType: ArchiveFileType.journalArchive,
            defaultFilename: export.document?.filename ?? ArchiveFileType.filename()
        ) { result in
            export.finish(result)
        }
        .onValueChange(of: model.locked) { locked in
            if locked { export.cancel() }
        }
        // Preparing the archive, not waiting in the save dialog.
        .keepsUnlockedWhile(export.busy && !export.presenting)
        .onDisappear {
            if !export.presenting { export.cancel() }
        }
    }
}

struct ArchiveImportButton: View {
    @EnvironmentObject private var model: AppModel
    @State private var choosing = false
    @State private var archive: URL?
    @State private var error: String?
    var body: some View {
        Button("Import Archive…") { choosing = true }
            .disabled(model.writingPausedForEncryption)
            .fileImporter(isPresented: $choosing, allowedContentTypes: ArchiveFileType.importTypes) { result in
                do {
                    archive = try result.get()
                } catch { self.error = ArchiveImportView.couldntOpen }
            }
            .sheet(isPresented: Binding(get: { archive != nil }, set: { if !$0 { archive = nil } })) {
                if let archive { ArchiveImportView(source: archive) }
            }
            .alert(
                "Couldn’t Open Archive", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
    }
}

struct ArchiveImportView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let source: URL
    @State private var phrase = ""
    @State private var requiresPassword = true
    @FocusState private var recoveryKeyFocused: Bool
    @State private var prepared: VaultArchive.Restored?
    @State private var preview: ArchiveSummary?
    /// Whether an imported journal will get a number because its name is already used (journal-name-uniqueness.md §4.4).
    @State private var namesUsed = false
    @State private var busy = false
    @State private var committing = false
    @State private var completed = false
    @State private var wasAdditive = false
    @State private var error: String?
    @State private var operation: Task<Void, Never>?
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView { content }
                .onValueChange(of: error) { message in
                    // At large text sizes a new error can appear below the visible area, behind the keyboard.
                    if message != nil { proxy.scrollTo(Self.errorAnchor, anchor: .top) }
                }
        }.frame(minWidth: 320, idealWidth: 480, minHeight: 280, idealHeight: 420)
            .onAppear {
                let granted = source.startAccessingSecurityScopedResource()
                defer { if granted { source.stopAccessingSecurityScopedResource() } }
                do { requiresPassword = try VaultArchive.requiresPassword(at: source) } catch {
                    showInspectionError(error)
                }
            }
            .interactiveDismissDisabled(committing)
            .keepsUnlockedWhile(busy || committing)
            .onValueChange(of: model.locked) { locked in
                if locked {
                    operation?.cancel()
                    preview = nil
                    phrase = ""
                    dismiss()
                }
            }
            .onDisappear {
                operation?.cancel()
                if let prepared { Task { await model.discardImportedCopy(prepared) } }
            }
    }
    private static let errorAnchor = "archive-import-error"
    /// Whether any imported journal has the name of a journal here or of another imported journal.
    private static func namesUsed(importing imported: [JournalItem], into current: [JournalItem]) -> Bool {
        var keys = Set(current.filter(JournalNames.isListed).map { JournalNames.key($0.title) })
        for journal in imported.filter(JournalNames.isListed) {
            guard keys.insert(JournalNames.key(journal.title)).inserted else { return true }
        }
        return false
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.lockBlocksImport {
                Text("Import Archive").font(.title2.bold())
                Text("Unlock My Journal to import an archive.").foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                }
            } else if completed {
                Text(wasAdditive ? "Journals Imported" : "Journals Restored").font(.title2.bold())
                if !wasAdditive { Text("You can set up sync in Settings.").foregroundStyle(.secondary) }
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            } else {
                Text("Import Archive").font(.title2.bold())
                if prepared == nil && requiresPassword {
                    SecureField("Password or Recovery Key", text: $phrase).passwordAutofill().textFieldStyle(
                        .roundedBorder
                    )
                    .focused($recoveryKeyFocused).onSubmit {
                        if !busy { inspect() }
                    }
                    Text("Use the password or recovery key for this archive.").foregroundStyle(.secondary)
                } else {
                    if let preview { ArchivePreviewSummary(summary: preview) }
                    if model.store == nil && model.libraryProblem?.offersImport == true {
                        // Replacing journals that can't be opened removes them, so the sheet says so.
                        Text(
                            "The journals on this device can’t be opened, but they may still be fine. Restoring removes them from this device and ends any syncing with a server."
                        ).foregroundStyle(.secondary)
                    }
                    if model.store != nil {
                        Text(
                            namesUsed
                                ? "Your current journals will be kept. Imported journals will be added as separate journals. If a name is already used, a number is added, such as “Default 2”."
                                : "Your current journals will be kept. Imported journals will be added as separate journals."
                        ).foregroundStyle(.secondary)
                        if model.connection != nil {
                            Text("Imported journals will also sync to your server.").foregroundStyle(.secondary)
                        }
                    }
                }
                // A readable archive from an earlier version restores as it is; the window then asks for a master
                // password to encrypt it (docs/design/1-1-encryption-and-passwords.md §3.5).
                if model.store == nil, let prepared, (try? prepared.recovery.contentProtection) == .plaintext {
                    Text("This archive isn’t encrypted. You’ll choose a master password next.")
                        .foregroundStyle(.secondary)
                }
                if let error {
                    // Scrolled to with the same margin above it as at the top of the sheet, clear of the corners.
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                        .padding(.top, 24).id(Self.errorAnchor).padding(.top, -24)
                }
                ArchiveImportActions(
                    title: prepared == nil
                        ? "Continue" : model.store == nil ? "Restore Journals" : "Import as New Journals",
                    busy: busy, committing: committing,
                    enabled: !busy && (prepared != nil || !requiresPassword || !phrase.isEmpty),
                    cancel: {
                        operation?.cancel()
                        dismiss()
                    },
                    proceed: { prepared == nil ? inspect() : install() })
            }
        }.padding(24)
    }
    private func inspect() {
        busy = true
        error = nil
        let session = model.vaultSessionID
        operation = Task {
            defer { busy = false }
            let granted = source.startAccessingSecurityScopedResource()
            defer { if granted { source.stopAccessingSecurityScopedResource() } }
            do {
                try model.validateVaultSession(session)
                let result = try await model.inspectArchive(source, phrase: phrase)
                do {
                    let snapshot = try await result.store.lifecycleSnapshot()
                    try model.validateVaultSession(session)
                    preview = ArchiveSummary(snapshot: snapshot)
                    namesUsed = Self.namesUsed(importing: snapshot.items, into: model.items)
                    prepared = result
                    phrase = ""
                } catch {
                    await model.discardImportedCopy(result)
                    throw error
                }
            } catch {
                do { try model.validateVaultSession(session) } catch { return }
                guard !(error is CancellationError) else { return }
                showInspectionError(error)
            }
        }
    }
    private func showInspectionError(_ failure: Error) {
        switch failure {
        case JournalError.invalidRecoveryKey:
            error = "This archive couldn’t be opened. Check the password or recovery key and try again."
            recoveryKeyFocused = true
        case JournalError.unsupportedFormat, JournalError.newerVersion:
            error = "Update My Journal to open this archive."
        case JournalError.invalidData:
            error = "This archive is incomplete or damaged. Try another copy."
        default:
            error = Self.couldntOpen
        }
    }
    static let couldntOpen =
        "Couldn’t open this archive. Check that the file is available and your device has enough space, then try again."

    private func install() {
        guard let prepared else { return }
        wasAdditive = model.store != nil
        busy = true
        committing = true
        error = nil
        operation = Task {
            defer {
                busy = false
                committing = false
            }
            do {
                try await model.installArchive(prepared)
                guard !model.locked else { return }
                completed = true
                preview = nil
            } catch is CancellationError {
                // The device's authentication was cancelled: nothing was replaced, and Restore Journals asks again.
            } catch { self.error = error.shown(.saving) }
        }
    }
}

struct ArchivePreviewSummary: View {
    let summary: ArchiveSummary

    var body: some View {
        ForEach(summary.journals) { journal in
            Text(journal.title.isEmpty ? "Untitled Journal" : journal.title).font(.headline)
        }
        Text(summary.entries == 1 ? "1 entry in journals" : "\(summary.entries) entries in journals")
        Text("\(summary.recentlyDeleted) in Recently Deleted").foregroundStyle(.secondary)
        if summary.unavailable > 0 {
            Text("\(summary.unavailable) in Unavailable").foregroundStyle(.secondary)
            Text("These entries are preserved. You can review them in Unavailable after importing.")
                .foregroundStyle(.secondary)
        }
    }
}

struct ArchiveImportActions: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let title: String
    let busy: Bool
    let committing: Bool
    let enabled: Bool
    let cancel: () -> Void
    let proceed: () -> Void

    var body: some View {
        if textSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 16) {
                progress
                primary
                cancellation
            }
        } else {
            HStack {
                cancellation
                Spacer()
                progress
                primary
            }
        }
    }
    private var primary: some View {
        Button(action: proceed) {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: textSize.isAccessibilitySize ? .infinity : nil)
        }.buttonStyle(.borderedProminent).disabled(!enabled)
    }
    private var cancellation: some View {
        Button("Cancel", role: .cancel, action: cancel).disabled(committing)
    }
    @ViewBuilder private var progress: some View {
        if busy { ProgressView(committing ? "Importing Journals…" : "Opening Archive…") }
    }
}
