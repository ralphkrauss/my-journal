import Foundation
import JournalCore

/// The lists views show, derived from the library once per change of what they depend on. Views read them on every
/// update, and every update used to recompute them: for each keystroke and each row, across thousands of entries.
@MainActor final class DerivedLists {
    /// Changes whenever items or conflicts change in a way that can move an entry between lists.
    private(set) var revision = 0
    /// Changes whenever an item's text changes in the lists (`patch`).
    private(set) var contentRevision = 0
    var lifecycle: JournalLifecycleSnapshot?
    var journals: [JournalItem]?
    var templates: [JournalItem]?
    var counts: (all: Int, journals: [UUID: Int], unavailable: Bool)?
    var entries: (key: EntriesKey, items: [JournalItem])?
    var groups: (key: EntriesKey, groups: [(String, [JournalItem])])?
    /// Set while `draft` changes in a way no view needs to show at once, and while only its text changes, which
    /// leaves its images as they are; see `AppModel.changeDraftQuietly`.
    var quietDraft = false
    var textOnlyDraft = false
    var quietRefresh: Task<Void, Never>?
    /// Entries, templates and journals being deleted: their rows leave the lists at once, before the deletion is
    /// stored (`AppModel.removeFromLists`).
    private(set) var deleting: Set<UUID> = []
    /// Changes whenever `deleting` does.
    private(set) var deletingRevision = 0
    /// Each entry's list preview, for the version of it shown.
    private var previews: [UUID: (version: StoredVersion?, text: String)] = [:]

    /// Search results for the query, and the query they are for. While a newer query is being searched, its
    /// results replace these once they are ready.
    private(set) var matches: (query: String, ids: Set<UUID>)?
    private(set) var matchesRevision = 0
    let index = EntrySearchIndex()
    /// Index updates and searches run in order, each after the previous one.
    private var indexing: Task<Void, Never>?
    private var searching: Task<Void, Never>?

    func invalidate() {
        revision += 1
        lifecycle = nil
        journals = nil
        templates = nil
        counts = nil
        entries = nil
        groups = nil
    }

    func hide(_ id: UUID) {
        guard deleting.insert(id).inserted else { return }
        deletingChanged()
    }

    func show(_ id: UUID) {
        guard deleting.remove(id) != nil else { return }
        deletingChanged()
    }

    private func deletingChanged() {
        deletingRevision += 1
        counts = nil
        entries = nil
        groups = nil
    }

    /// Shows an item's new text in the lists it is already in. The lists are changed in place: copying lists of
    /// thousands of entries after every save took most of the time a keystroke took.
    func patch(_ item: JournalItem) {
        contentRevision += 1
        // New entries from a template use the template as it is now.
        if let position = templates?.firstIndex(where: { $0.id == item.id }) { templates?[position] = item }
        if let position = entries?.items.firstIndex(where: { $0.id == item.id }) { entries?.items[position] = item }
        guard let groupCount = groups?.groups.count else { return }
        for group in 0..<groupCount {
            if let position = groups?.groups[group].1.firstIndex(where: { $0.id == item.id }) {
                groups?.groups[group].1[position] = item
                return
            }
        }
    }

    func preview(of item: JournalItem) -> String {
        if let version = item.storedVersion, let known = previews[item.id], known.version == version {
            return known.text
        }
        let text = item.listPreview
        previews[item.id] = (item.storedVersion, text)
        return text
    }

    func setMatches(_ value: (query: String, ids: Set<UUID>)?) {
        matches = value
        matchesRevision += 1
        entries = nil
        groups = nil
    }

    /// Brings the search index up to date, after any earlier update.
    func index(_ items: [JournalItem], complete: Bool) {
        let previous = indexing
        let index = index
        indexing = Task {
            await previous?.value
            await index.update(items, complete: complete)
        }
    }

    /// Searches once the index is up to date, and hands over the results unless a newer search started.
    func search(_ query: String, deliver: @escaping @MainActor (Set<UUID>) -> Void) {
        searching?.cancel()
        let pending = indexing
        let index = index
        searching = Task {
            await pending?.value
            guard !Task.isCancelled else { return }
            let found = await index.matches(query)
            guard !Task.isCancelled else { return }
            deliver(found)
        }
    }

    /// Waits for index updates requested so far.
    func indexed() async { await indexing?.value }
    /// Waits until the list's latest search has finished.
    func searched() async { await searching?.value }

    /// Forgets all text, when the journals lock.
    func clear() {
        searching?.cancel()
        quietRefresh?.cancel()
        let previous = indexing
        let index = index
        indexing = Task {
            await previous?.value
            await index.clear()
        }
        matches = nil
        matchesRevision += 1
        previews = [:]
        invalidate()
    }
}

/// What one row of the entries list shows, apart from the entry itself: when none of it changed, the row stays.
struct EntryRowKey: Equatable, Sendable {
    let id: UUID
    let version: StoredVersion?
    let title: String
    let modifiedAt: Date
    /// Journals, conflicts and lifecycle, which decide the row's label and actions.
    let revision: Int
    let showsJournal: Bool
    let accessibilitySize: Bool
    /// Whether the row offers Image Descriptions.
    let describable: Bool
}

extension AppModel {
    func rowKey(_ entry: JournalItem, accessibilitySize: Bool) -> EntryRowKey {
        EntryRowKey(
            id: entry.id, version: entry.storedVersion, title: entry.title, modifiedAt: entry.modifiedAt,
            revision: lists.revision, showsJournal: showingAllEntries, accessibilitySize: accessibilitySize,
            describable: offersImageDescriptions(for: entry))
    }
    func listPreview(of entry: JournalItem) -> String { lists.preview(of: entry) }
}

/// Everything the list of entries shows: when none of it changed, the list stays as it is.
struct EntryListKey: Equatable, Sendable {
    let revision: Int
    let contentRevision: Int
    let matchesRevision: Int
    let deletingRevision: Int
    /// The query, where the list filters by it itself (Recently Deleted); elsewhere only whether there is one.
    let query: String
    let selectedID: UUID?
    let openID: UUID?
    let describable: Bool
    let journalID: UUID?
    let all: Bool
    let trash: Bool
    let templates: Bool
    let unavailable: Bool
    let accessibilitySize: Bool
    let stacked: Bool
    let searchPresented: Bool
}

extension AppModel {
    func listKey(accessibilitySize: Bool, stacked: Bool, searchPresented: Bool) -> EntryListKey {
        EntryListKey(
            revision: lists.revision, contentRevision: lists.contentRevision, matchesRevision: lists.matchesRevision,
            deletingRevision: lists.deletingRevision, query: showingTrash ? query : query.isEmpty ? "" : " ",
            selectedID: selectedID, openID: draft?.id,
            describable: draft.map { canDescribeImages(in: $0.id) } ?? false, journalID: selectedJournalID,
            all: showingAllEntries, trash: showingTrash, templates: showingTemplates, unavailable: showingUnavailable,
            accessibilitySize: accessibilitySize, stacked: stacked, searchPresented: searchPresented)
    }
}

/// What the entries list shows: every input of `AppModel.entries`.
struct EntriesKey: Equatable {
    let revision: Int
    let templates: Bool
    let unavailable: Bool
    let trash: Bool
    let all: Bool
    let journalID: UUID?
    /// The search results in use, or nil without a query.
    let matches: Int?
}

extension JournalDocument {
    /// Whether this is `other` with only the text of some blocks changed: none added, removed or restyled, and no
    /// image or table among them. Such a change keeps what the document can be edited as, and its images. Checking
    /// this is much quicker than reading either document whole, as those questions otherwise need.
    func changesOnlyText(from other: JournalDocument) -> Bool {
        guard blocks.count == other.blocks.count, version == other.version,
            requiresMarkdownSource == other.requiresMarkdownSource
        else { return false }
        for index in blocks.indices where blocks[index] != other.blocks[index] {
            let new = blocks[index]
            let old = other.blocks[index]
            guard new.id == old.id, new.kind == old.kind, new.attachmentID == nil, old.attachmentID == nil,
                new.table == nil, old.table == nil, !["image", "table"].contains(new.kind),
                !new.runs.contains(where: { $0.imageSource != nil }),
                !old.runs.contains(where: { $0.imageSource != nil })
            else { return false }
        }
        return true
    }
}

extension JournalItem {
    /// The start of the text on one line, as a list row shows it; a long entry isn't read whole for one line.
    var listPreview: String {
        document.text(prefix: 1_000).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    /// Everything that decides which lists show an item and where. Saving an entry's writing leaves it unchanged.
    var listPlacement: ListPlacement { listPlacement(editable: document.isEditable) }
    func listPlacement(editable: Bool) -> ListPlacement {
        ListPlacement(
            kind: kind, journalID: journalID, date: date, deletedAt: deletedAt, deletedWithJournal: deletedWithJournal,
            archivedAt: archivedAt, permanentlyDeletedAt: permanentlyDeletedAt, editable: editable,
            // Journals and templates are listed by title.
            title: kind == "entry" ? nil : title, defaultTemplateID: defaultTemplateID)
    }
    /// Whether this is `other` with nothing changed that places it in a list. With only text changed, what the
    /// document can be edited as stays the same and isn't worked out again.
    func sameListPlacement(as other: JournalItem, textOnly: Bool) -> Bool {
        textOnly
            ? listPlacement(editable: true) == other.listPlacement(editable: true)
            : listPlacement == other.listPlacement
    }
}

struct ListPlacement: Equatable {
    let kind: String
    let journalID: UUID?
    let date: Date
    let deletedAt: Date?
    let deletedWithJournal: Bool
    let archivedAt: Date?
    let permanentlyDeletedAt: Date?
    let editable: Bool
    let title: String?
    let defaultTemplateID: UUID?
}

/// What views show of the open entry apart from its writing, which the editor shows itself.
struct DraftAppearance: Equatable {
    let id: UUID
    let placement: ListPlacement
    let requiresSource: Bool
    let hasImages: Bool

    init(_ item: JournalItem) {
        id = item.id
        placement = item.listPlacement
        requiresSource = item.document.requiresMarkdownSource
        hasImages = !item.document.imageBlocks.isEmpty
    }
}

extension AppModel {
    /// Replaces the stored copy of an item after saving it. When only its writing changed, the lists keep their
    /// order and contents, and views show the new text once writing pauses rather than after every keystroke.
    func replaceStoredItem(_ item: JournalItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            items.append(item)
            return
        }
        let stored = items[index]
        guard item.sameListPlacement(as: stored, textOnly: item.document.changesOnlyText(from: stored.document)) else {
            items[index] = item
            return
        }
        replaceQuietly(at: index, with: item)
        lists.patch(item)
        lists.index([item], complete: false)
        if !query.isEmpty { searchQuery() }
        refreshViewsWhenWritingPauses()
    }

    /// Changes the open draft without updating views when they show nothing of the change (the editor already shows
    /// the writing); they update once writing pauses.
    func changeDraftQuietly(_ item: JournalItem, textOnly: Bool) {
        let quiet =
            textOnly
            ? draft.map { $0.id == item.id && $0.sameListPlacement(as: item, textOnly: true) } == true
            : draft.map(DraftAppearance.init) == DraftAppearance(item)
        lists.quietDraft = quiet
        lists.textOnlyDraft = textOnly
        keepingDraftBase { draft = item }
        lists.quietDraft = false
        lists.textOnlyDraft = false
        if quiet { refreshViewsWhenWritingPauses() }
    }

    func refreshViewsWhenWritingPauses() {
        lists.quietRefresh?.cancel()
        lists.quietRefresh = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            objectWillChange.send()
        }
    }

    /// Called when `items` changed as a whole.
    func itemsChanged() {
        lists.invalidate()
        lists.index(items, complete: true)
        if !query.isEmpty { searchQuery() }
    }

    /// Searches for the current query; the entries list follows once the results are ready.
    func searchQuery() {
        let query = query
        guard !query.isEmpty, !locked else {
            if lists.matches != nil { lists.setMatches(nil) }
            return
        }
        lists.search(query) { [weak self] found in
            guard let self, self.query == query, !self.locked else { return }
            // Typing in an entry searches again after each save; the list changes only when the results do.
            if let shown = self.lists.matches, shown.query == query, shown.ids == found { return }
            self.objectWillChange.send()
            self.lists.setMatches((query, found))
        }
    }

    /// Entries and templates containing `query`, once the index has everything the list shows.
    func matchingEntries(_ query: String) async -> Set<UUID> {
        await lists.indexed()
        return await lists.index.matches(query)
    }
}
