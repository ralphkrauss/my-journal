import Foundation

public enum PermanentDeletionError: Error, Equatable, Sendable {
    case missing, notDeleted, unsupported, changed, permanentlyDeleted
    case conflict(UUID)
}

/// Captures the current content a destructive confirmation describes. It does not delete data.
public struct PermanentDeletionPlan: Sendable {
    public let recordID: UUID
    public let kind: String
    public let title: String
    public let entryCount: Int
    public let date: Date
    public let includesIndependentlyDeletedEntries: Bool
    let records: [JournalItem]

    public static func prepare(recordID: UUID, snapshot: JournalLifecycleSnapshot) throws -> Self {
        guard let selected = snapshot.items.first(where: { $0.id == recordID }) else {
            throw PermanentDeletionError.missing
        }
        guard selected.document.isEditable, selected.preservedJSON == nil else {
            throw PermanentDeletionError.unsupported
        }
        let affected: [JournalItem]
        switch selected.kind {
        case "journal":
            guard selected.deletedAt != nil else { throw PermanentDeletionError.notDeleted }
            affected = [selected] + snapshot.items.filter { $0.kind == "entry" && $0.journalID == selected.id }
        case "entry":
            switch snapshot.location(of: selected) {
            case .journal: throw PermanentDeletionError.notDeleted
            case .unavailable(.missing): throw PermanentDeletionError.missing
            case .unavailable(.unsupported): throw PermanentDeletionError.unsupported
            case .recentlyDeleted: break
            }
            affected = [selected]
        case "template":
            guard selected.deletedAt != nil else { throw PermanentDeletionError.notDeleted }
            affected = [selected]
        default: throw PermanentDeletionError.unsupported
        }
        let ordered = affected.sorted { $0.id.uuidString < $1.id.uuidString }
        for item in ordered {
            guard item.document.isEditable, item.preservedJSON == nil else {
                throw PermanentDeletionError.unsupported
            }
            // A conflict this version can read is settled at the next pull; one it can't waits for a newer version.
            guard !snapshot.conflictedIDs.contains(item.id) else {
                throw snapshot.settlingIDs.contains(item.id) ? PermanentDeletionError.conflict(item.id) : .unsupported
            }
        }
        return Self(
            recordID: recordID, kind: selected.kind, title: selected.title,
            entryCount: affected.filter { $0.kind == "entry" }.count, date: selected.date,
            includesIndependentlyDeletedEntries: affected.contains {
                $0.kind == "entry" && $0.deletedAt != nil && !$0.deletedWithJournal
            }, records: ordered)
    }

    /// Must be called inside the eventual deletion transaction; unrelated content does not invalidate consent.
    public func validate(snapshot: JournalLifecycleSnapshot) throws {
        let latest = try Self.prepare(recordID: recordID, snapshot: snapshot)
        guard latest.records == records else { throw PermanentDeletionError.changed }
    }
}

extension JournalItem {
    /// Content-free marker. Only explicit deletion/import operations may persist it.
    static func permanentDeletionMarker(for item: JournalItem, at date: Date) -> JournalItem {
        var marker = JournalItem(id: item.id, kind: item.kind, date: date)
        marker.deletedAt = date
        marker.permanentlyDeletedAt = date
        marker.permanentDeletionID = UUID()
        return marker
    }
    var isCanonicalDeletionMarker: Bool {
        guard let permanentlyDeletedAt, permanentDeletionID != nil, restoredFromDeletionID == nil else { return false }
        return ["journal", "entry", "template"].contains(kind) && title.isEmpty && document == JournalDocument()
            && journalID == nil && defaultTemplateID == nil && archivedAt == nil && !deletedWithJournal
            && date == permanentlyDeletedAt && modifiedAt == permanentlyDeletedAt
            && deletedAt == permanentlyDeletedAt && preservedJSON == nil
    }
}

/// Store-bound consent for current records, recovery versions, and excluded history-only identities.
public struct PermanentDeletionConfirmation: Sendable {
    public let plan: PermanentDeletionPlan
    public var historicalOnlyEntryCount: Int { historicalOnlyIDs.count }
    let storeID: UUID
    let history: [DeletionHistoryState]
    let historicalOnlyIDs: Set<UUID>
}

struct DeletionHistoryState: Equatable, Sendable {
    let rowID: Int64
    let recordID: String
    let kind: String
    let payload: String
}
