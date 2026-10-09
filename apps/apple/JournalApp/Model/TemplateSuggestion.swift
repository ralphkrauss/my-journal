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

    /// Whether Use a Template… (File menu) and the link in the empty entry can open the chooser: the same condition.
    var canUseTemplate: Bool {
        guard let draft else { return false }
        return templateSuggestion(for: draft).isShown
    }

    /// What choosing a template did to the entry the chooser was opened for.
    enum TemplateUse: Equatable {
        /// The entry's body now holds the template.
        case filled
        /// The entry gained writing, or changed elsewhere, since the chooser opened: nothing was changed.
        case entryChanged
        /// The entry was closed or deleted, or the open entry can't be saved first: nothing was changed.
        case entryClosed
    }

    /// Fills the entry the chooser was opened for with `template`, when its body holds nothing to lose here and in the
    /// store, and keeps the title. Otherwise nothing is changed and nothing is created (docs/design/
    /// 1-1-library-simplifications.md, M): an entry that changed says so in the alert, one that is gone is just left.
    func useTemplate(_ template: JournalItem, in entryID: UUID?) async -> TemplateUse {
        guard let entryID, draft?.id == entryID, let store else { return .entryClosed }
        guard let open = draft, open.deletedAt == nil, open.kind == "entry" else { return .entryClosed }
        guard TemplateSuggestion.hasEmptyBody(open) else { return rejectTemplate() }
        guard await flush(), !locked, !replacingVault, store === self.store, let current = draft, current.id == entryID
        else { return .entryClosed }
        guard TemplateSuggestion.hasEmptyBody(current) else { return rejectTemplate() }
        do {
            // A change synced from elsewhere is in the store even while the open draft looks empty.
            guard let stored = try await store.item(current.id), TemplateSuggestion.hasEmptyBody(stored),
                stored.storedVersion == current.storedVersion
            else { return rejectTemplate() }
            var filled = stored
            filled.document = template.document
            filled.modifiedAt = Date()
            let saved = try await store.save(filled, requiringUnchanged: true)
            try? await refresh()
            // Writing that started while saving stays as it is; the next save keeps both versions for review.
            guard let now = draft, now.id == saved.id,
                TemplateSuggestion.hasEmptyBody(now) || now.document == saved.document
            else { return .filled }
            initialInsertion = InitialEditorInsertion(item: saved, fromTemplate: true)
            if saved.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                titleFocus = InitialTitleFocus(itemID: saved.id)
            }
            draft = saved
            return .filled
        } catch JournalError.conflict {
            return rejectTemplate()
        } catch {
            report(error, .saving)
            return .entryClosed
        }
    }

    private func rejectTemplate() -> TemplateUse {
        error = "This entry changed, so the template wasn’t added."
        return .entryChanged
    }
}
