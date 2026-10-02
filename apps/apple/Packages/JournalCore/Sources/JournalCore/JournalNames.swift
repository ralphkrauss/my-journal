import Foundation
import GRDB

/// Journal names stay unique among journals that aren't in Recently Deleted
/// (docs/design/journal-name-uniqueness.md §3).
public enum JournalNames {
    /// The name a journal shows: its title, or "Untitled Journal" when it has none.
    public static func displayName(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Journal" : trimmed
    }
    /// Two names are the same when they're equal after trimming spaces and ignoring case.
    public static func key(_ title: String) -> String {
        displayName(title).folding(options: [.caseInsensitive], locale: nil)
    }
    /// `title` with the smallest number from 2 whose name isn't in `taken` (keys), always added to the whole name.
    public static func numbered(_ title: String, avoiding taken: Set<String>) -> String {
        let base = displayName(title)
        var number = 2
        while taken.contains(key("\(base) \(number)")) { number += 1 }
        return "\(base) \(number)"
    }
    /// `title`, or a numbered name when it's taken.
    public static func available(_ title: String, avoiding taken: Set<String>) -> String {
        taken.contains(key(title)) ? numbered(title, avoiding: taken) : title
    }
    /// Journals shown in the Journals list: not in Recently Deleted and not permanently deleted.
    public static func isListed(_ item: JournalItem) -> Bool {
        item.kind == "journal" && item.deletedAt == nil && !item.isPermanentlyDeleted
    }
    /// The listed journal in `items` with `title`'s name, other than `excluding`. A journal may change the case of its
    /// own name.
    public static func journal(named title: String, in items: [JournalItem], excluding: UUID?) -> JournalItem? {
        let key = key(title)
        return items.first { isListed($0) && $0.id != excluding && self.key($0.title) == key }
    }
    /// Oldest first: the order that decides which journal keeps a shared name.
    static func precedes(_ first: JournalItem, _ second: JournalItem) -> Bool {
        (first.date, first.id.uuidString) < (second.date, second.id.uuidString)
    }
}

/// A local change that would give a journal the same name as another one.
public enum JournalNameError: LocalizedError, Equatable {
    /// The name of the journal that already has it.
    case taken(String)

    public var errorDescription: String? {
        switch self {
        case .taken(let name): "A journal named “\(name)” already exists."
        }
    }
}

extension JournalStore {
    /// The listed journal that has `title`'s name, other than `excluding`.
    public func journalNamed(_ title: String, excluding: UUID? = nil) throws -> JournalItem? {
        try db.read { try journalNamed($0, title, excluding: excluding) }
    }
    func journalNamed(_ db: Database, _ title: String, excluding: UUID?) throws -> JournalItem? {
        let key = JournalNames.key(title)
        return try listedJournals(db).first { $0.id != excluding && JournalNames.key($0.title) == key }
    }
    func listedJournals(_ db: Database) throws -> [JournalItem] {
        try decodeRecords(
            storedRecords(db, sql: "SELECT id,kind,payload FROM records WHERE kind='journal'"), complete: true
        ).filter(JournalNames.isListed)
    }
    /// Refuses a local save that gives a listed journal a name another listed journal has. A journal that keeps its
    /// name, or only changes its case, is never refused, so journals named alike by an earlier version stay editable.
    func requireAvailableName(_ db: Database, for item: JournalItem) throws {
        guard JournalNames.isListed(item) else { return }
        if let stored = try storedItem(db, uuid: item.id), JournalNames.isListed(stored),
            JournalNames.key(stored.title) == JournalNames.key(item.title)
        {
            return
        }
        if let other = try journalNamed(db, item.title, excluding: item.id) {
            throw JournalNameError.taken(JournalNames.displayName(other.title))
        }
    }
    /// `journal`'s title, numbered when another listed journal has it; for journals coming back from Recently Deleted.
    func availableTitle(_ db: Database, for journal: JournalItem) throws -> String {
        let taken = Set(try listedJournals(db).filter { $0.id != journal.id }.map { JournalNames.key($0.title) })
        return JournalNames.available(journal.title, avoiding: taken)
    }
    /// Imported journals whose names are taken, by journals here or by each other, get numbered names.
    func saveImportedItems(_ items: [JournalItem]) throws {
        try db.write { db in
            var taken = Set(try listedJournals(db).map { JournalNames.key($0.title) })
            var titles: [UUID: String] = [:]
            for journal in items.filter(JournalNames.isListed).sorted(by: JournalNames.precedes) {
                let title = JournalNames.available(journal.title, avoiding: taken)
                if title != journal.title { titles[journal.id] = title }
                taken.insert(JournalNames.key(title))
            }
            for original in items {
                try Task.checkCancellation()
                var item = original
                if let title = titles[item.id] { item.title = title }
                try save(db, item: item, importingMarker: item.isPermanentlyDeleted)
            }
        }
    }
    /// The name a journal in Recently Deleted would come back with.
    public func restoredTitle(of journalID: UUID) throws -> String? {
        try db.read { db in
            guard let journal = try storedItem(db, uuid: journalID), journal.kind == "journal" else { return nil }
            return try availableTitle(db, for: journal)
        }
    }

    /// How journals that share a name are renamed (§4.6): the oldest keeps it, the others get numbers in age order.
    /// Every device computes the same result from the same journals; whether it may apply a rename is decided
    /// separately (`canRenameAutomatically`), so a journal that can't be renamed doesn't change the others' numbers.
    func duplicateJournalRenames(_ db: Database) throws -> [JournalItem] {
        let listed = try listedJournals(db).sorted(by: JournalNames.precedes)
        var taken = Set(listed.map { JournalNames.key($0.title) })
        var seen = Set<String>()
        var renames: [JournalItem] = []
        for journal in listed {
            let key = JournalNames.key(journal.title)
            guard seen.contains(key) else {
                seen.insert(key)
                continue
            }
            var renamed = journal
            renamed.title = JournalNames.numbered(journal.title, avoiding: taken)
            taken.insert(JournalNames.key(renamed.title))
            renames.append(renamed)
        }
        return renames
    }
    /// Whether this device may rename `journal` on its own: it's editable, has no change to review, and, with
    /// `skippingPending`, no change waiting to be sent.
    func canRenameAutomatically(_ db: Database, _ journal: JournalItem, skippingPending: Bool) throws -> Bool {
        guard journal.document.isEditable, journal.preservedJSON == nil else { return false }
        let recordID = id(journal.id)
        if try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM conflicts WHERE record=?)", arguments: [recordID])
            == true
        {
            return false
        }
        guard skippingPending else { return true }
        let dirty = try Bool.fetchOne(db, sql: "SELECT dirty FROM records WHERE id=?", arguments: [recordID]) ?? true
        let queued =
            try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM outbox WHERE record=?)", arguments: [recordID])
            ?? true
        return !dirty && !queued
    }
    /// Numbers journals that share a name in a library without a server, as ordinary edits. Returns how many.
    @discardableResult public func numberDuplicateJournals() throws -> Int {
        try db.write { db in
            var count = 0
            for renamed in try duplicateJournalRenames(db)
            where try canRenameAutomatically(db, renamed, skippingPending: false) {
                try keepCurrentVersion(db, recordID: renamed.id)
                var edited = renamed
                edited.modifiedAt = Date()
                _ = try saveCanonical(db, item: edited)
                count += 1
            }
            return count
        }
    }
    /// Keeps the stored version in Version History before an automatic change, so the earlier name stays there.
    private func keepCurrentVersion(_ db: Database, recordID: UUID) throws {
        try db.execute(
            sql: "INSERT INTO history(record,kind,payload,saved) SELECT id,kind,payload,? FROM records WHERE id=?",
            arguments: [JournalCoding.timestamp(Date()), id(recordID)])
    }

    /// An automatic rename to send after synchronizing: the change, and the payload it's based on. Nothing is saved
    /// until the server accepts it (`adoptAutomaticRename`), so a refused or unsent rename leaves nothing behind and
    /// can never become a change to review.
    public struct AutomaticRename: Sendable {
        public let change: PendingChange
        let basedOn: String
    }
    /// The renames this device may send now for journals that share a name, based on what it has read.
    public func automaticRenames() throws -> [AutomaticRename] {
        try db.read { db in
            var renames: [AutomaticRename] = []
            for renamed in try duplicateJournalRenames(db)
            where try canRenameAutomatically(db, renamed, skippingPending: true) {
                guard
                    let row = try Row.fetchOne(
                        db, sql: "SELECT payload,revision FROM records WHERE id=?", arguments: [id(renamed.id)])
                else { continue }
                var edited = renamed
                edited.modifiedAt = Date()
                let change = PendingChange(
                    operationId: UUID(), recordID: renamed.id, baseRevision: row["revision"], kind: "journal",
                    payload: try encode(edited))
                renames.append(AutomaticRename(change: change, basedOn: row["payload"]))
            }
            return renames
        }
    }
    /// Stores an automatic rename the server accepted, when the journal is still as it was read. Otherwise the next
    /// pull brings the rename like any change from another device.
    public func adoptAutomaticRename(_ rename: AutomaticRename, receipt: RemoteChange) throws {
        guard receipt.recordId == rename.change.recordID, receipt.payload == rename.change.payload,
            receipt.revision == rename.change.baseRevision + 1
        else { throw JournalError.invalidData }
        try db.write { db in
            let recordID = id(receipt.recordId)
            guard
                let row = try Row.fetchOne(
                    db, sql: "SELECT payload,revision,dirty FROM records WHERE id=?", arguments: [recordID]),
                row["payload"] as String == rename.basedOn, row["revision"] as Int64 == rename.change.baseRevision,
                !(row["dirty"] as Bool),
                try Bool.fetchOne(
                    db, sql: "SELECT EXISTS(SELECT 1 FROM outbox WHERE record=?)", arguments: [recordID]) == false
            else { return }
            try keepCurrentVersion(db, recordID: receipt.recordId)
            try db.execute(
                sql: "UPDATE records SET payload=?,revision=?,dirty=0 WHERE id=?",
                arguments: [receipt.payload, receipt.revision, recordID])
            receivedChanges += 1
        }
    }
}
