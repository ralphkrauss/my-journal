import Foundation
import GRDB

// Earlier versions kept from ordinary changes, so Version History has more than versions kept for review or recovery.
// The rules are in docs/design/version-checkpoints.md. These versions stay on this device: they aren't synchronized.
extension JournalStore {
    /// A change after this long without one starts a new editing session, and while changes continue, a version is
    /// kept at most this often.
    static let checkpointInterval: TimeInterval = 10 * 60
    /// Versions kept from ordinary changes per item. The oldest go first; no other earlier version is removed this way.
    static let checkpointLimit = 50

    /// Uses `clock` instead of the system time to decide when to keep versions and to date them.
    func useClock(_ clock: @escaping @Sendable () -> Date) { self.clock = clock }

    /// Keeps `payload`, the stored version `item` replaces in this write, in Version History when a checkpoint is
    /// due: when this change starts an editing session or the session has gone on for `checkpointInterval`, no version
    /// was kept from ordinary changes in that time, and the item's title or text actually changes. A nil `payload`
    /// means there is nothing to keep: the record is new, or its stored version was kept for review instead.
    /// `fromElsewhere` is a version received from another device; the next change made here starts a session.
    func keepCheckpointIfDue(
        _ db: Database, replacing payload: String?, with item: JournalItem, fromElsewhere: Bool
    ) throws {
        let now = clock()
        let lastStored = versionsStoredAt[item.id]
        versionsStoredAt[item.id] = fromElsewhere ? nil : now
        guard let payload, item.kind == "entry" || item.kind == "template" else {
            if checkpointPeriods[item.id] == nil { checkpointPeriods[item.id] = now }
            return
        }
        let startsSession = fromElsewhere || lastStored.map { Self.hasElapsed(since: $0, at: now) } ?? true
        if !startsSession, let period = checkpointPeriods[item.id], !Self.hasElapsed(since: period, at: now) { return }
        if let kept = try lastCheckpoint(db, recordID: item.id), !Self.hasElapsed(since: kept, at: now) {
            checkpointPeriods[item.id] = kept
            return
        }
        let current = try decode(payload, id: item.id, kind: item.kind)
        guard current.isSupported, !current.isPermanentlyDeleted else { return }
        guard current.hasContent else {
            // Nothing worth keeping yet, such as a new blank entry: the first period starts with its first words.
            checkpointPeriods[item.id] = now
            return
        }
        // A change that leaves the title and text alone, such as a new date, keeps a checkpoint due for the next one.
        guard current.title != item.title || current.document != item.document else { return }
        try db.execute(
            sql: "INSERT INTO history(record,kind,payload,saved,checkpoint) VALUES (?,?,?,?,1)",
            arguments: [id(item.id), item.kind, payload, JournalCoding.timestamp(now)])
        try db.execute(
            sql: """
                DELETE FROM history WHERE id IN (
                    SELECT id FROM history WHERE record=? AND checkpoint=1 ORDER BY id DESC LIMIT -1 OFFSET ?)
                """,
            arguments: [id(item.id), Self.checkpointLimit])
        checkpointPeriods[item.id] = now
    }
    private func lastCheckpoint(_ db: Database, recordID: UUID) throws -> Date? {
        let saved = try String.fetchOne(
            db, sql: "SELECT saved FROM history WHERE record=? AND checkpoint=1 ORDER BY id DESC LIMIT 1",
            arguments: [id(recordID)])
        return try saved.map(JournalCoding.date(from:))
    }
    /// Whether `checkpointInterval` has passed since `start`. A start later than `now`, from a clock that was changed,
    /// counts as passed, so a wrong time can't stop versions from being kept.
    private static func hasElapsed(since start: Date, at now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(start)
        return elapsed < 0 || elapsed >= checkpointInterval
    }
}

extension JournalItem {
    /// Whether this version has a title, text or images: an untouched blank item has nothing to keep.
    var hasContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !document.attachmentIDs.isEmpty
    }
}
