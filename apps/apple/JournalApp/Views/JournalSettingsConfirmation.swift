import JournalCore
import SwiftUI

struct JournalSettingsComparison: Identifiable {
    let id = UUID()
    let current: JournalItem
    let historical: JournalItem
    let currentTemplate: String
    let historicalTemplate: String

    init(current: JournalItem, historical: JournalItem, templates: [JournalItem]) {
        self.current = current
        self.historical = historical
        let references = [current.defaultTemplateID, historical.defaultTemplateID].compactMap { $0 }
        let ordered = Array(Set(references)).sorted { $0.uuidString < $1.uuidString }
        func name(_ id: UUID?) -> String {
            guard let id else { return "Blank Entry" }
            guard let template = templates.first(where: { $0.id == id }) else {
                let missing = ordered.filter { reference in !templates.contains { $0.id == reference } }
                guard missing.count > 1, let index = missing.firstIndex(of: id) else { return "Unavailable Template" }
                return "Unavailable Template \(index + 1)"
            }
            let title = template.title.isEmpty ? "Untitled Template" : template.title
            let duplicates = templates.filter { ($0.title.isEmpty ? "Untitled Template" : $0.title) == title }
                .sorted { $0.id.uuidString < $1.id.uuidString }
            guard duplicates.count > 1, let index = duplicates.firstIndex(where: { $0.id == id }) else { return title }
            return "\(title) · \(template.date.formatted(date: .abbreviated, time: .shortened)) · \(index + 1)"
        }
        currentTemplate = name(current.defaultTemplateID)
        historicalTemplate = name(historical.defaultTemplateID)
    }
}

struct JournalSettingsConfirmation: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    let comparison: JournalSettingsComparison
    @Binding var busy: Bool
    /// A listed journal that has the earlier name: that name isn't restored (docs/design/journal-name-uniqueness.md
    /// §4.3).
    var takenName: String?
    let restore: () -> Void
    var body: some View {
        Group {
            #if os(iOS)
                NavigationStack {
                    content.navigationTitle("Restore Settings").navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { cancelButton }
                            ToolbarItem(placement: .confirmationAction) { restoreButton }
                        }
                }
            #else
                VStack(spacing: 0) {
                    Text("Restore Settings").font(.title2.bold()).padding(.top, 24)
                    content
                    Divider()
                    HStack {
                        cancelButton
                        Spacer()
                        restoreButton
                    }.padding()
                }.frame(minWidth: 360, idealWidth: 460, minHeight: 420, idealHeight: 560)
            #endif
        }.interactiveDismissDisabled(busy)
    }
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                #if os(iOS)
                    if textSize.isAccessibilitySize {
                        Text("Restore Settings").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    }
                #endif
                Text("Restore this name and default template. Entries and Recently Deleted status stay unchanged.")
                    .foregroundStyle(.secondary)
                summary("Current", item: comparison.current, template: comparison.currentTemplate)
                summary("Restore", item: comparison.historical, template: comparison.historicalTemplate)
                if let takenName {
                    Text("Another journal is named “\(takenName)”. Rename that journal first to restore this name.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                if busy { ProgressView("Restoring Settings…") }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityIdentifier("journal-settings-comparison")
    }
    private func summary(_ title: String, item: JournalItem, template: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            field("Name", value: item.title.isEmpty ? "Untitled Journal" : item.title)
            field("Default Template", value: template)
        }.accessibilityElement(children: .contain)
    }
    private func field(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }.accessibilityElement(children: .combine)
    }
    private var cancelButton: some View {
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
    }
    private var restoreButton: some View {
        #if os(iOS)
            Button("Restore", action: restore).disabled(busy || takenName != nil)
        #else
            Button("Restore Settings", action: restore).disabled(busy || takenName != nil)
        #endif
    }
}
