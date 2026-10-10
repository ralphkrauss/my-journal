import JournalCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings ▸ Backup ▸ Markdown (docs/design/client-only-mac-lists-markdown-2026-10-05.md §3).
struct MarkdownExportSection: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Section {
            MarkdownExportControls()
        } header: {
            Text("Markdown")
        } footer: {
            Text(MarkdownExportSection.explanation(model))
        }
    }
    static func explanation(_ model: AppModel) -> String {
        let saves = "Saves your journals and their images as Markdown files that other apps can open."
        let archive = "To keep a copy you can import later, use Export Archive."
        return "\(saves) The files aren’t encrypted. \(archive)"
    }
}

/// File ▸ Export Journals as Markdown… on the Mac and iPad, as File ▸ Export Archive… opens its own sheet.
struct MarkdownExportSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MarkdownExportControls()
                } footer: {
                    Text(MarkdownExportSection.explanation(model))
                }
            }
            .formStyle(.grouped).navigationTitle("Export as Markdown")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
            .frame(minWidth: 460, minHeight: 240)
        #endif
        .onValueChange(of: model.locked) { if $0 { dismiss() } }
    }
}

struct MarkdownExportControls: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var export = MarkdownExportController()
    var body: some View {
        Group {
            // The row keeps its size while preparing: the spinner appears at its trailing end, after a short delay.
            HStack {
                Button("Export as Markdown…") { export.start(with: model) }
                    .disabled(export.showsProgress || model.store == nil)
                Spacer(minLength: 0)
                if export.showsProgress {
                    ProgressView().controlSize(.small).accessibilityLabel("Preparing Files…")
                }
            }
            if let error = export.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if let note = export.note { Text(note).foregroundStyle(.secondary).textSelection(.enabled) }
        }
        .fileExporter(
            isPresented: $export.presenting, document: export.document, contentType: .folder,
            defaultFilename: export.document?.filename ?? MarkdownExport.folderName()
        ) { result in
            export.finish(result)
        }
        .onValueChange(of: export.error) { announce($0) }
        .onValueChange(of: export.note) { announce($0) }
        .onValueChange(of: model.locked) { locked in
            if locked { export.cancel() }
        }
        // Preparing the files, not waiting in the save dialog.
        .keepsUnlockedWhile(export.busy && !export.presenting)
        .onDisappear {
            if !export.presenting { export.cancel() }
        }
    }

    private func announce(_ message: String?) {
        if let message { JournalAccessibility.announce(message) }
    }
}
