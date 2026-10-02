import Foundation

/// Counts current entries by their restored location, excluding history and conflict copies.
public struct ArchiveSummary: Sendable {
    public let journals: [JournalItem]
    public let entries: Int
    public let recentlyDeleted: Int
    public let unavailable: Int

    public init(snapshot: JournalLifecycleSnapshot) {
        journals = snapshot.items.filter { $0.kind == "journal" }
        var entries = 0
        var recentlyDeleted = 0
        var unavailable = 0
        for item in snapshot.items where item.kind == "entry" {
            switch snapshot.location(of: item) {
            case .journal: entries += 1
            case .recentlyDeleted: recentlyDeleted += 1
            case .unavailable: unavailable += 1
            }
        }
        self.entries = entries
        self.recentlyDeleted = recentlyDeleted
        self.unavailable = unavailable
    }
}
