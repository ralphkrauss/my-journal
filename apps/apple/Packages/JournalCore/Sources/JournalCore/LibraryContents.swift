import Foundation

/// What a library holds, as connecting to a server sees it (docs/design/join-with-local-journals.md §2.6, §3.2).
public struct LibraryContents: Sendable, Equatable {
    /// Journals not in Recently Deleted.
    public let journals: Int
    /// Entries not in Recently Deleted, including archived ones.
    public let entries: Int
    /// Templates someone made or edited, not in Recently Deleted.
    public let templates: Int
    /// Journals, entries and templates in Recently Deleted.
    public let recentlyDeleted: Int
    /// Nothing anyone wrote: exactly one journal named "Default" as Start a Journal creates it, no entries, only
    /// unedited built-in templates and no changes to review. Joining a server may replace such a library.
    public let nothingWritten: Bool

    public init(items: [JournalItem], conflicts: Int) {
        let current = items.filter { !$0.isPermanentlyDeleted }
        let live = current.filter { $0.deletedAt == nil }
        journals = live.filter { $0.kind == "journal" }.count
        entries = live.filter { $0.kind == "entry" }.count
        templates = live.filter { $0.kind == "template" && !BuiltInTemplates.isUnedited($0) }.count
        recentlyDeleted = current.count - live.count
        let onlyJournal = current.filter { $0.kind == "journal" }
        nothingWritten =
            conflicts == 0 && recentlyDeleted == 0 && entries == 0 && templates == 0
            && current.allSatisfy { $0.kind == "journal" || $0.kind == "template" }
            && onlyJournal.count == 1 && onlyJournal.allSatisfy { $0.title == "Default" && $0.defaultTemplateID == nil }
    }
}
