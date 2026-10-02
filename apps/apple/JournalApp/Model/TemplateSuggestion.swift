import Foundation
import JournalCore

/// “Start writing or [template symbol] use a template”: the empty body's placeholder, whose link opens the template
/// chooser (docs/design/new-entry-template-suggestion.md).
enum TemplateSuggestion: Equatable {
    case hidden
    case useTemplate

    /// Shown with the body placeholder: a body without a single character or image, whatever the title.
    static func resolve(entry: JournalItem, hasTemplates: Bool, canEdit: Bool) -> Self {
        guard entry.kind == "entry", hasTemplates, canEdit, entry.document.text.isEmpty,
            entry.document.imageBlocks.isEmpty
        else { return .hidden }
        return .useTemplate
    }

    /// A body a template can fill without losing anything: whitespace at most and no images. The title is kept.
    static func hasEmptyBody(_ entry: JournalItem) -> Bool {
        entry.kind == "entry" && entry.deletedAt == nil
            && entry.document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && entry.document.imageBlocks.isEmpty
    }

    var isShown: Bool { self != .hidden }
}

extension AppModel {
    func templateSuggestion(for item: JournalItem) -> TemplateSuggestion {
        TemplateSuggestion.resolve(
            entry: item, hasTemplates: templates.contains { $0.document.isEditable }, canEdit: canEdit)
    }

    /// Fills the open entry's body with `template` when it holds nothing to lose, here and in the store, and keeps
    /// the title. Returns false, changing nothing, otherwise; the template then goes to a new entry.
    func fillEmptyEntry(with template: JournalItem) async -> Bool {
        guard let open = draft, TemplateSuggestion.hasEmptyBody(open), let store else { return false }
        guard await flush(), !locked, !replacingVault, store === self.store, let current = draft,
            current.id == open.id, TemplateSuggestion.hasEmptyBody(current)
        else { return false }
        do {
            // A change synced from elsewhere is in the store even while the open draft looks empty.
            guard let stored = try await store.item(current.id), TemplateSuggestion.hasEmptyBody(stored),
                stored.storedVersion == current.storedVersion
            else { return false }
            var filled = stored
            filled.document = template.document
            filled.modifiedAt = Date()
            let saved = try await store.save(filled, requiringUnchanged: true)
            try? await refresh()
            // Writing that started while saving stays as it is; the next save keeps both versions for review.
            guard let now = draft, now.id == saved.id,
                TemplateSuggestion.hasEmptyBody(now) || now.document == saved.document
            else { return true }
            initialInsertion = InitialEditorInsertion(item: saved, fromTemplate: true)
            if saved.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                titleFocus = InitialTitleFocus(itemID: saved.id)
            }
            draft = saved
            return true
        } catch {
            return false
        }
    }
}

// MARK: New Entry from a template on the Templates screen

extension AppModel {
    /// The Templates screen's “New Entry from Template” item: the title names the journal when there's a choice.
    func newEntryFromTemplateTitle() -> String {
        guard journals.count > 1, let journal = newEntryJournal else { return "New Entry from Template" }
        let name = journal.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return "New Entry in “\(name.isEmpty ? "Untitled Journal" : name)”"
    }

    /// Whether a template can start an entry now: there's a journal to write in, saving works, and the template has
    /// no changes to review.
    func canStartEntry(fromTemplate template: JournalItem) -> Bool {
        newEntryJournal != nil && !saveFailure && !locked && !replacingVault
            && !conflicts.contains { $0.id == template.id }
    }

    /// Starts an entry from the template as it's written now, in the journal New Entry uses from this screen.
    func newEntry(fromTemplate id: UUID) async {
        // Edits to the open template are saved first, so the entry has them.
        guard await flush() else { return }
        try? await refresh()
        guard let template = templates.first(where: { $0.id == id }), template.document.isEditable else {
            error = "This template is no longer available."
            return
        }
        guard !conflicts.contains(where: { $0.id == id }) else {
            error = "Review the changes to this template first."
            return
        }
        await newEntry(template: template)
    }
}
