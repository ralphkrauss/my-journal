import Foundation
import JournalCore
import os

extension AppModel {
    var lifecycle: JournalLifecycleSnapshot {
        if let cached = lists.lifecycle { return cached }
        let snapshot = JournalLifecycleSnapshot(items: items, conflictedIDs: Set(conflicts.map(\.id)))
        lists.lifecycle = snapshot
        return snapshot
    }
    /// Journals not in Recently Deleted, in the order the sidebar lists them (journal-order.md).
    var journalRecords: [JournalItem] {
        JournalRanks.arranged(items.filter { $0.kind == "journal" && $0.deletedAt == nil }, ranks: library.ranks)
    }
    /// Journals in use, in the person's order: by rank, then the others by name.
    var journals: [JournalItem] {
        if let cached = lists.journals { return cached }
        var sorted = JournalRanks.arranged(lifecycle.liveJournals, ranks: library.ranks)
        if let order = lists.journalOrder {
            let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
            sorted = sorted.enumerated().sorted { first, second in
                (position[first.element.id] ?? order.count + first.offset)
                    < (position[second.element.id] ?? order.count + second.offset)
            }.map(\.element)
        }
        lists.journals = sorted
        return sorted
    }
    var deletedJournals: [JournalItem] {
        items.filter { $0.kind == "journal" && $0.deletedAt != nil }.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
    var filteredDeletedJournals: [JournalItem] {
        deletedJournals.filter {
            (query.isEmpty || $0.title.localizedStandardContains(query)) && !lists.deleting.contains($0.id)
        }
    }
    func restorableEntryCount(_ journalID: UUID) -> Int {
        items.filter {
            $0.kind == "entry" && $0.journalID == journalID && $0.deletedAt == nil && !$0.deletedWithJournal
        }.count
    }
    func legacyEntryCount(_ journalID: UUID) -> Int {
        items.filter { $0.kind == "entry" && $0.journalID == journalID && $0.deletedWithJournal }.count
    }
    var templates: [JournalItem] {
        if let cached = lists.templates { return cached }
        let sorted = items.filter { $0.kind == "template" && $0.deletedAt == nil }.sorted { $0.title < $1.title }
        lists.templates = sorted
        return sorted
    }
    /// Templates in Recently Deleted, newest first like the Templates list, filtered by the search.
    var filteredDeletedTemplates: [JournalItem] {
        items.filter { item in
            item.kind == "template" && item.deletedAt != nil && !item.isPermanentlyDeleted
                && !lists.deleting.contains(item.id)
                && (query.isEmpty || item.title.localizedStandardContains(query)
                    || item.document.text.localizedStandardContains(query))
        }.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }
    }
    /// Whether the item is listed in Recently Deleted: an entry deleted on its own or with its journal, or a template.
    func isRecentlyDeleted(_ item: JournalItem) -> Bool {
        switch item.kind {
        case "entry": return lifecycle.location(of: item) == .recentlyDeleted
        case "template": return item.deletedAt != nil && !item.isPermanentlyDeleted
        default: return false
        }
    }
    /// The template New Entry uses in a journal. While its default template is in Recently Deleted, that's none.
    func defaultTemplateID(of journal: JournalItem) -> UUID? {
        journal.defaultTemplateID.flatMap { id in templates.contains { $0.id == id } ? id : nil }
    }
    var selectedJournal: JournalItem? { journals.first { $0.id == selectedJournalID } }
    /// The journal chosen in Settings. Until one is chosen, or while it isn't in use (in Recently Deleted,
    /// unavailable), the oldest journal in use: the one created with the library unless it was deleted.
    var defaultJournal: JournalItem? {
        let live = lifecycle.liveJournals
        if let chosen = configuration?.defaultJournalID, let journal = live.first(where: { $0.id == chosen }) {
            return journal
        }
        return live.min { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
    }
    /// New Entry works from every screen, Recently Deleted included, as long as there's a journal to write in.
    var canCreateEntry: Bool {
        isReady && !locked && !replacingVault && newEntryJournal != nil
    }
    /// Where New Entry files an entry: the journal whose entries are shown, otherwise the default journal (from All
    /// Entries, Templates, Recently Deleted, Unavailable Journals, or with nothing selected). The journal shown
    /// before one of those screens doesn't count.
    var newEntryJournal: JournalItem? {
        if case .journal = destination, let journal = selectedJournal { return journal }
        return defaultJournal
    }
    /// Settings ▸ Default Journal. A choice that can't be saved is undone and reported.
    func chooseDefaultJournal(_ id: UUID) {
        guard var next = configuration, next.defaultJournalID != id else { return }
        let previous = configuration
        next.defaultJournalID = id
        configuration = next
        do { try persistConfiguration() } catch {
            configuration = previous
            self.error = "Couldn’t save the default journal."
        }
    }
    var entries: [JournalItem] {
        let key = EntriesKey(
            revision: lists.revision, templates: showingTemplates, unavailable: showingUnavailable,
            trash: showingTrash, all: showingAllEntries, journalID: selectedJournalID,
            matches: query.isEmpty ? nil : lists.matchesRevision)
        if let cached = lists.entries, cached.key == key { return cached.items }
        let computed = listedEntries()
        lists.entries = (key, computed)
        return computed
    }
    /// Entries grouped by the month of their date, newest first, as the list shows them. In a journal and in All
    /// Entries, pinned entries come first, in a Pinned section (pinned-entries.md).
    var entryGroups: [(String, [JournalItem])] {
        let listed = entries
        if let cached = lists.groups, cached.key == lists.entries?.key { return cached.groups }
        var groups: [(String, [JournalItem])] = []
        let pinned = showsPinnedSection ? listed.filter(isPinned) : []
        if !pinned.isEmpty { groups.append((Self.pinnedSection, pinned)) }
        for entry in listed[pinned.count...] {
            let name = Self.monthFormatter.string(from: entry.date)
            if groups.last?.0 == name {
                groups[groups.count - 1].1.append(entry)
            } else {
                groups.append((name, [entry]))
            }
        }
        if let key = lists.entries?.key { lists.groups = (key, groups) }
        return groups
    }
    /// The Pinned section's title, which no month can have.
    static let pinnedSection = "Pinned"
    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()
    /// Live entries in a journal, or in all journals.
    func entryCount(in destination: JournalDestination) -> Int? {
        switch destination {
        case .all: return liveEntryCounts.all
        case .journal(let id): return liveEntryCounts.journals[id] ?? 0
        default: return nil
        }
    }
    var hasUnavailableEntries: Bool { liveEntryCounts.unavailable }
    private var liveEntryCounts: (all: Int, journals: [UUID: Int], unavailable: Bool) {
        if let cached = lists.counts { return cached }
        let snapshot = lifecycle
        var counts = (all: 0, journals: [UUID: Int](), unavailable: false)
        for item in items where item.kind == "entry" && !lists.deleting.contains(item.id) {
            switch snapshot.location(of: item) {
            case .journal:
                counts.all += 1
                if let journal = item.journalID { counts.journals[journal, default: 0] += 1 }
            case .unavailable: counts.unavailable = true
            case .recentlyDeleted: break
            }
        }
        lists.counts = counts
        return counts
    }
    private func listedEntries() -> [JournalItem] {
        let snapshot = lifecycle
        // While a new query is searched, the results of the previous one stay; before any, nothing is filtered.
        let matches = query.isEmpty ? nil : lists.matches?.ids
        let listed = items.filter { item in
            let included: Bool
            if showingTemplates {
                included = item.kind == "template" && item.deletedAt == nil
            } else if item.kind != "entry" {
                included = false
            } else if showingUnavailable {
                if case .unavailable = snapshot.location(of: item) { included = true } else { included = false }
            } else if showingTrash {
                included = snapshot.location(of: item) == .recentlyDeleted
            } else {
                included =
                    (showingAllEntries || item.journalID == selectedJournalID)
                    && snapshot.location(of: item) == .journal
            }
            return included && matches.map { $0.contains(item.id) } != false && !lists.deleting.contains(item.id)
        }.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }
        // Pinned entries come first, in the same order: Previous Entry and Next Entry follow what's on screen.
        guard showsPinnedSection, !library.pinned.isEmpty else { return listed }
        return listed.filter(isPinned) + listed.filter { !isPinned($0) }
    }
    @discardableResult func select(_ id: UUID?) async -> Bool {
        endEntryCreation()
        guard !replacingVault, await flush() else { return false }
        applySelection(id)
        return true
    }
    /// Selects in the same update when nothing needs saving; returns false when a save must finish first.
    @discardableResult func selectImmediately(_ id: UUID?) -> Bool {
        guard draftIsSaved else { return false }
        endEntryCreation()
        applySelection(id)
        return true
    }
    private func applySelection(_ id: UUID?) {
        let left = draft.flatMap { $0.id != id && isListedEntry($0.id) ? $0.id : nil }
        selectedID = id
        draft = items.first { $0.id == id }
        rememberSelection()
        // Leaving an edited entry this way is a pause in writing; deleting or moving it is not.
        reviewRequests.selectionChanged(leaving: left)
    }
    private func isListedEntry(_ id: UUID) -> Bool {
        guard let item = items.first(where: { $0.id == id }), item.kind == "entry" else { return false }
        return lifecycle.location(of: item).isInLiveJournal
    }
    @discardableResult func switchJournal(_ id: UUID) async -> Bool {
        endEntryCreation()
        guard !replacingVault, await flush() else { return false }
        applyJournal(id)
        return true
    }
    @discardableResult func switchJournalImmediately(_ id: UUID) -> Bool {
        guard draftIsSaved else { return false }
        endEntryCreation()
        applyJournal(id)
        return true
    }
    private func applyJournal(_ id: UUID) {
        selectedJournalID = id
        showingAllEntries = false
        showingTemplates = false
        showingTrash = false
        showingUnavailable = false
        query = ""
        selectedID = nil
        draft = nil
        selectInitialEntry()
    }
    @discardableResult func showCollection(
        trash: Bool = false, templates: Bool = false, unavailable: Bool = false, all: Bool = false
    ) async -> Bool {
        endEntryCreation()
        guard !replacingVault, await flush() else { return false }
        applyCollection(trash: trash, templates: templates, unavailable: unavailable, all: all)
        return true
    }
    @discardableResult func showCollectionImmediately(
        trash: Bool = false, templates: Bool = false, unavailable: Bool = false, all: Bool = false
    ) -> Bool {
        guard draftIsSaved else { return false }
        endEntryCreation()
        applyCollection(trash: trash, templates: templates, unavailable: unavailable, all: all)
        return true
    }
    private func applyCollection(trash: Bool, templates: Bool, unavailable: Bool, all: Bool) {
        showingAllEntries = all
        showingTrash = trash
        showingUnavailable = unavailable
        showingTemplates = templates
        selectedID = nil
        draft = nil
        query = ""
    }
    /// The collection the entries list currently shows.
    var destination: JournalDestination? {
        if showingAllEntries { return .all }
        if showingTemplates { return .templates }
        if showingTrash { return .deleted }
        if showingUnavailable { return .unavailable }
        return selectedJournalID.map { .journal($0) }
    }
    @discardableResult func show(_ destination: JournalDestination) async -> Bool {
        switch destination {
        case .journal(let id): return await switchJournal(id)
        case .all: return await showCollection(all: true)
        case .templates: return await showCollection(templates: true)
        case .deleted: return await showCollection(trash: true)
        case .unavailable: return await showCollection(unavailable: true)
        }
    }
    /// Shows the collection in the same update when nothing needs saving first.
    func showImmediately(_ destination: JournalDestination) -> Bool {
        switch destination {
        case .journal(let id): return switchJournalImmediately(id)
        case .all: return showCollectionImmediately(all: true)
        case .templates: return showCollectionImmediately(templates: true)
        case .deleted: return showCollectionImmediately(trash: true)
        case .unavailable: return showCollectionImmediately(unavailable: true)
        }
    }
    var isReady: Bool { store != nil && configuration?.recoveryConfirmed == true }
    var canEdit: Bool {
        guard !locked, !replacingVault, let draft, draft.deletedAt == nil, draft.document.isEditable else {
            return false
        }
        return draft.kind == "template" || (draft.kind == "entry" && lifecycle.location(of: draft).isInLiveJournal)
    }
    /// Shows the open entry where it now is; for flows that exist to show it, such as reviewing a restoration.
    func showDraftWhereItIs() {
        guard let draft, draft.kind == "entry" else { return }
        showingTemplates = false
        switch lifecycle.location(of: draft) {
        case .recentlyDeleted:
            showingAllEntries = false
            showingUnavailable = false
            showingTrash = true
        case .unavailable:
            showingAllEntries = false
            showingTrash = false
            showingUnavailable = true
        case .journal:
            showingTrash = false
            showingUnavailable = false
            if !showingAllEntries { selectedJournalID = draft.journalID }
        }
    }
    func reconcileDraftLocation() {
        if let draft, draft.kind == "journal" {
            self.draft = items.first { $0.id == draft.id }
            if self.draft == nil { selectedID = nil }
            return
        }
        guard let draft, draft.kind == "entry" else { return }
        // As in Notes, an open entry that no longer belongs in the list being shown (deleted, restored,
        // moved or made unavailable, here or by a sync) closes; the list stays where it is.
        let stored = items.first { $0.id == draft.id }
        let shown: Bool
        switch stored.map({ lifecycle.location(of: $0) }) {
        case .journal:
            shown =
                !showingTrash && !showingUnavailable && !showingTemplates
                && (showingAllEntries || stored?.journalID == selectedJournalID)
        case .recentlyDeleted: shown = showingTrash
        case .unavailable: shown = showingUnavailable
        case nil: shown = false
        }
        // An unavailable entry whose journal has arrived is recovered, not removed: follow it into the journal.
        if !shown, showingUnavailable, let stored, lifecycle.location(of: stored) == .journal {
            showingUnavailable = false
            selectedJournalID = stored.journalID
            self.draft = stored
            return
        }
        // Unsaved writing is never dropped: the entry stays open until it's saved or reviewed.
        if !shown, !draftHasUnsavedEdits {
            selectedID = nil
            self.draft = nil
        }
    }

}

// The selection remembered between launches.
extension AppModel {
    func rememberSelection() {
        guard !locked, !showingTrash, !showingTemplates, !showingUnavailable else { return }
        let entry = draft.flatMap { $0.kind == "entry" && $0.deletedAt == nil ? $0 : nil }
        // All Entries shows every journal's entries: remember the open entry's own journal, so relaunching
        // reopens that entry rather than the journal selected before.
        if showingAllEntries, let entry, let journal = journals.first(where: { $0.id == entry.journalID }) {
            persistSelection(journalID: journal.id, entryID: entry.id)
            return
        }
        guard let journal = selectedJournal else { return }
        persistSelection(journalID: journal.id, entryID: entry?.journalID == journal.id ? entry?.id : nil)
    }
    func persistSelection(journalID: UUID, entryID: UUID?) {
        guard var next = configuration else { return }
        guard next.lastJournalID != journalID || next.lastEntryID != entryID else { return }
        let previous = configuration
        next.lastJournalID = journalID
        next.lastEntryID = entryID
        configuration = next
        do { try persistConfiguration() } catch {
            // A preference failure must not turn an already saved entry into a save-failure state.
            configuration = previous
            Logger(subsystem: "org.privatejournal", category: "navigation").error("Could not save the selected view.")
        }
    }
    func selectInitialEntry(reveal: Bool = false) {
        let remembered = entries.first { $0.id == configuration?.lastEntryID }
        let initial = remembered ?? entries.first { Calendar.current.isDateInToday($0.date) }
        selectedID = initial?.id
        draft = initial
        rememberSelection()
        revealsSelection = reveal && remembered?.document.isEditable == true
    }
}

/// View ▸ Previous Entry and Next Entry.
enum ListStep {
    case previous, next
}

// Moving through the list from the editor, even while the list is hidden.
extension AppModel {
    /// Everything the list shows, in its order. Recently Deleted lists journals and templates before entries.
    var listedIDs: [UUID] {
        guard showingTrash else { return entries.map(\.id) }
        return filteredDeletedJournals.map(\.id) + filteredDeletedTemplates.map(\.id) + entries.map(\.id)
    }
    /// The item above or below the open one in the list, or nil at either end. With nothing open, Next Entry opens
    /// the first item and Previous Entry the last.
    func listedID(_ step: ListStep) -> UUID? {
        guard isReady, !locked, !replacingVault else { return nil }
        let listed = listedIDs
        guard let index = selectedID.flatMap({ listed.firstIndex(of: $0) }) else {
            return step == .next ? listed.first : listed.last
        }
        let target = step == .next ? index + 1 : index - 1
        return listed.indices.contains(target) ? listed[target] : nil
    }
    /// Opens the neighbouring item, saving the open one first as choosing it in the list does.
    func selectListed(_ step: ListStep) async {
        guard let id = listedID(step) else { return }
        await select(id)
    }
}
