import JournalCore
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

struct MoveEntryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let entryID: UUID
    @State private var creatingJournal = false
    @State private var selection: UUID?
    @State private var busy = false
    @State private var error: String?
    @State private var operation: Task<Void, Never>?

    private var actionTitle: String { "Move" }
    private var screenTitle: String { "Move Entry" }
    private var destinations: [JournalItem] {
        model.journals.filter { $0.id != model.items.first(where: { $0.id == entryID })?.journalID }
    }
    private var duplicateNames: Set<String> {
        let groups = Dictionary(grouping: destinations) {
            $0.title.folding(options: .caseInsensitive, locale: .current)
        }
        return Set(groups.filter { $0.value.count > 1 }.keys)
    }
    private func ambiguous(_ journal: JournalItem) -> Bool {
        duplicateNames.contains(journal.title.folding(options: .caseInsensitive, locale: .current))
    }
    private var selectableIDs: [UUID] { destinations.filter { !ambiguous($0) }.map(\.id) }
    // Journals are renamed with Rename… in the sidebar on the Mac and in the Journals list on iPhone and iPad.
    private var renameExplanation: String {
        #if os(macOS)
            "Journals with the same name can’t be chosen. To move this entry to one of them, rename it in the sidebar first."
        #else
            "Journals with the same name can’t be chosen. To move this entry to one of them, rename it in the Journals list first."
        #endif
    }
    private var canMove: Bool { !busy && selection.map { selectableIDs.contains($0) } == true }

    var body: some View {
        layout.interactiveDismissDisabled(busy)
            .sheet(isPresented: $creatingJournal) { RecoveryJournalView(entryID: entryID) }
            .onDisappear { operation?.cancel() }
            .onValueChange(of: model.locked) { locked in
                if locked {
                    creatingJournal = false
                    operation?.cancel()
                    dismiss()
                }
            }
            .onValueChange(of: model.draft?.id) { currentID in
                if currentID != entryID {
                    creatingJournal = false
                    operation?.cancel()
                    dismiss()
                }
            }
            .onValueChange(of: selectableIDs) { _ in
                if let selection, !selectableIDs.contains(selection) {
                    self.selection = nil
                    showError("That journal is no longer available. Choose another journal.")
                }
            }
    }
    @ViewBuilder private var layout: some View {
        #if os(macOS)
            VStack(spacing: 0) {
                Text(screenTitle).font(.title2.bold()).padding()
                content
                Divider()
                HStack {
                    Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
                    Spacer()
                    Button(actionTitle) { move() }.keyboardShortcut(.defaultAction).disabled(!canMove)
                }.padding()
            }
            .frame(minWidth: 320, idealWidth: 420, minHeight: 280, idealHeight: 360)

        #else
            NavigationStack {
                content.navigationTitle(screenTitle).navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }.disabled(busy)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(actionTitle) { move() }.disabled(!canMove)
                        }
                    }
            }
        #endif
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if destinations.isEmpty {
                VStack(spacing: 12) {
                    Text("No Other Journals").font(.headline)
                    Text("Create a journal to move this entry.").foregroundStyle(.secondary)
                    Button("New Journal…") { creatingJournal = true }.disabled(busy)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            } else {
                List(destinations) { journal in
                    Button {
                        selection = journal.id
                        error = nil
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(JournalNames.displayName(journal.title)).foregroundStyle(
                                    ambiguous(journal) ? .secondary : .primary
                                )
                                .fixedSize(horizontal: false, vertical: true)
                                if ambiguous(journal) {
                                    Text("Same name as another journal").foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if selection == journal.id { Image(systemName: "checkmark").accessibilityHidden(true) }
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || ambiguous(journal))
                    .accessibilityAddTraits(selection == journal.id ? .isSelected : [])
                }
                if destinations.contains(where: ambiguous) {
                    Text(renameExplanation).foregroundStyle(.secondary).padding()
                }
            }
            if !destinations.isEmpty { Button("New Journal…") { creatingJournal = true }.padding().disabled(busy) }
            if let error { Text(error).foregroundStyle(.red).padding().accessibilityIdentifier("Move error") }
            if busy { ProgressView("Moving Entry…").padding() }
        }
    }
    private func move() {
        guard canMove, let selection else { return }
        busy = true
        error = nil
        operation = Task {
            defer { busy = false }
            do {
                try await model.moveEntry(entryID, to: selection)
                dismiss()
            } catch JournalLifecycleError.conflict(let id) {
                try? await model.refresh()
                guard !model.locked else { return }
                // An entry's changes are combined at the next sync; what a newer version of the app must read waits for it.
                if model.heldConflictIDs.contains(id) {
                    showError(JournalLifecycleError.unsupportedJournal.shown(.saving))
                } else {
                    showError(JournalLifecycleError.conflict(id).shown(.saving))
                }
            } catch is CancellationError {} catch {
                guard !model.locked else { return }
                showError(error.shown(.saving))
            }
        }
    }
    private func showError(_ text: String) {
        error = text
        #if os(macOS)
            NSAccessibility.post(
                element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        #else
            UIAccessibility.post(notification: .announcement, argument: text)
        #endif
    }
}
