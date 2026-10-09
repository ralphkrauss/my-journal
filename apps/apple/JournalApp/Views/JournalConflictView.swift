import JournalCore
import SwiftUI

struct JournalMetadataSummary: View {
    @EnvironmentObject var model: AppModel
    let item: JournalItem
    private var templateName: String {
        guard let id = item.defaultTemplateID else { return "Blank Entry" }
        return model.templates.first { $0.id == id }?.title ?? "Unavailable Template"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Name", item.title.isEmpty ? "Untitled Journal" : item.title)
            field("Default Template", templateName)
            field("Location", item.deletedAt == nil ? "Journals" : "Recently Deleted")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }.accessibilityElement(children: .combine)
    }
}

struct JournalMetadataConflictReview: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let journalID: UUID
    @State private var conflict: ConflictVersion?
    @State private var remote = false
    @State private var confirming: ConflictChoice?
    @State private var busy = false
    @State private var reloading = false
    @State private var completed = false
    @State private var error: String?
    @State private var operation: Task<Void, Never>?
    init(conflict: ConflictVersion) {
        journalID = conflict.id
        _conflict = State(initialValue: conflict)
    }
    private var working: Bool { busy || reloading }
    private var supported: Bool {
        conflict?.local.document.isEditable == true && conflict?.remote.document.isEditable == true
    }
    var body: some View {
        Group {
            #if os(iOS)
                NavigationStack {
                    content.navigationTitle("Review Changes").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { closeButton } }
                }
            #else
                VStack(spacing: 0) {
                    Text("Review Changes").font(.title2.bold()).padding(.top, 24)
                    content
                    Divider()
                    HStack {
                        closeButton
                        Spacer()
                    }.padding()
                }.frame(minWidth: 360, idealWidth: 460, minHeight: 400, idealHeight: 540)
            #endif
        }
        .interactiveDismissDisabled(working)
        .onDisappear { operation?.cancel() }
        .onValueChange(of: error) { message in if let message, !model.locked { JournalAccessibility.announce(message) }
        }
        .onValueChange(of: model.locked) { locked in
            if locked {
                operation?.cancel()
                conflict = nil
                confirming = nil
                dismiss()
            }
        }
        .confirmationDialog(
            confirming == .remote ? "Keep the version from Other Device?" : "Keep the version from This Device?",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            if let snapshot = conflict, let choice = confirming {
                Button("Keep Version") { resolve(snapshot, choice: choice) }
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: {
            if let conflict {
                let item = confirming == .remote ? conflict.remote : conflict.local
                Text(
                    "\(item.modifiedAt.formatted(date: .abbreviated, time: .standard)). Both versions will remain in Version History."
                )
            }
        }
    }
    private var closeButton: some View {
        Button(completed || conflict == nil ? "Done" : "Cancel") { dismiss() }.disabled(working)
    }
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.locked {
                    Text("Unlock My Journal to review changes.")
                } else if completed {
                    Text("Your choice was saved.")
                } else if let conflict {
                    Picker("Version", selection: $remote) {
                        Text("This Device").tag(false)
                        Text("Other Device").tag(true)
                    }.pickerStyle(.segmented).disabled(working || confirming != nil)
                    let item = remote ? conflict.remote : conflict.local
                    VStack(alignment: .leading, spacing: 6) {
                        Text(remote ? "Other Device" : "This Device").font(.headline)
                        Text(item.modifiedAt, format: .dateTime).foregroundStyle(.secondary)
                        if remote {
                            DisclosureGroup("Details") {
                                Text(conflict.deviceID.uuidString.lowercased()).font(.caption)
                                    .textSelection(.enabled).accessibilityLabel(
                                        "Recorded device ID \(conflict.deviceID.uuidString)")
                            }
                        }
                    }
                    JournalMetadataSummary(item: item)
                    if supported {
                        Button("Keep Version…") { confirming = remote ? .remote : .local }
                            .buttonStyle(.borderedProminent).disabled(working)
                    } else {
                        Text("Update My Journal to review these changes.").foregroundStyle(.secondary)
                        ArchiveExportControls()
                        if model.saveFailure {
                            Text(JournalError.saveRequired.shown(.saving))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("These changes have been resolved.")
                }
                if reloading { ProgressView("Loading Changes…") }
                if busy { ProgressView("Saving Changes…") }
                if let error {
                    Text(error).foregroundStyle(.secondary).textSelection(.enabled).accessibilityLabel(
                        "Error: \(error)")
                    Button(completed ? "Reload" : "Reload Changes") { operation = Task { await reload() } }.disabled(
                        busy)
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func reload() async {
        guard !model.locked, !working, let store = model.store else { return }
        reloading = true
        defer { reloading = false }
        do {
            let latest = try await store.conflicts().first { $0.id == journalID }
            try Task.checkCancellation()
            guard !model.locked else { return }
            try await model.refresh()
            guard !model.locked else { return }
            conflict = latest
            remote = false
            confirming = nil
            error = nil
        } catch { self.error = error.shown(.reading) }
    }
    private func resolve(_ snapshot: ConflictVersion, choice: ConflictChoice) {
        busy = true
        error = nil
        operation = Task {
            defer { busy = false }
            do {
                let refreshed = try await model.resolveJournalConflict(snapshot, choice: choice)
                guard !model.locked else { return }
                completed = true
                conflict = nil
                if !refreshed { error = "Your choice was saved, but the journal couldn’t be displayed." }
            } catch JournalError.conflict {
                error = "These changes have been updated. Review them again."
            } catch is CancellationError {
                return
            } catch { self.error = error.shown(.saving) }
        }
    }
}
