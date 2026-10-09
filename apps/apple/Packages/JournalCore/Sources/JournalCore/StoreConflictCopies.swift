import Foundation
import GRDB

// The other version of an entry or template that differs becomes a separate entry or template (row 3 of
// protocol/conflicts.md, and 3.3 of docs/design/1-1-conflicts-and-reconnect.md). This device's version stays the record
// with the bytes it has, so an open editor sees nothing.

extension JournalStore {
    /// Makes, replaces or leaves alone the copy of the other version, in this order:
    /// 1. A record with the derived identity exists in any state: nothing is written, noted, revived or duplicated.
    /// 2. An earlier copy of the same record from the same device, which nothing has touched, takes the later
    ///    version's content under its own identity.
    /// 3. Otherwise the copy is made with the derived identity.
    /// Returns the identity of the copy that was made or replaced, nil when nothing was written.
    func keepOtherVersionAsCopy(_ db: Database, copy: JournalItem, state: ConflictState) throws -> UUID? {
        let exists = try Bool.fetchOne(
            db, sql: "SELECT EXISTS(SELECT 1 FROM records WHERE id=?)", arguments: [id(copy.id)])
        guard exists != true else { return nil }
        var notes = try keptNotesStore.state(db)
        let copyID: UUID
        if let earlier = try replaceableCopy(db, notes: notes, state: state) {
            try replaceCopy(db, earlier: earlier, with: copy)
            copyID = earlier.copyID
            notes.remember(try keptCopy(earlier.copyID, copy: copy, state: state))
        } else {
            copyID = copy.id
            try insertCopy(db, copy)
            notes.copies = try copiesThatStillExist(db, notes.copies)
            notes.remember(try keptCopy(copy.id, copy: copy, state: state))
        }
        notes.noteKeptBoth(
            KeptNote(
                kind: .keptBoth, recordID: state.recordID, otherID: copyID, name: copy.title,
                otherIsNewer: state.other.item.modifiedAt > state.local.item.modifiedAt, created: clock()))
        try keptNotesStore.save(db, notes)
        return copyID
    }

    /// What this device remembers about a copy: where it came from and the digest of the plaintext it wrote, so a
    /// later conflict knows whether anyone has changed it since.
    private func keptCopy(_ copyID: UUID, copy: JournalItem, state: ConflictState) throws -> KeptCopy {
        var written = copy
        written.id = copyID
        return KeptCopy(
            copyID: copyID, recordID: state.recordID, originDevice: state.otherDevice,
            originRevision: state.otherRevision, digest: KeptNotesState.digest(of: try PortableRecord.encode(written)))
    }

    private func insertCopy(_ db: Database, _ copy: JournalItem) throws {
        let payload = try encode(copy)
        try db.execute(
            sql: "INSERT INTO records(id,kind,payload) VALUES (?,?,?)",
            arguments: [id(copy.id), copy.kind, payload])
        try enqueue(db, recordID: id(copy.id), kind: copy.kind, payload: payload, revision: 0)
    }

    // MARK: Replacing an earlier copy

    /// The latest earlier copy of this record that came from the same device as the later other version, which that
    /// version descends from (a higher revision). A nil or unknown device never matches: a version kept by a save on
    /// this device doesn't record which device wrote it, and two devices must not replace each other's copies. Only
    /// the latest candidate counts, and only while nobody has touched it.
    private func replaceableCopy(_ db: Database, notes: KeptNotesState, state: ConflictState) throws -> KeptCopy? {
        guard state.otherIsFromServer, let origin = state.otherDevice else { return nil }
        let latest =
            notes.copies
            .filter {
                $0.recordID == state.recordID && $0.originDevice == origin && $0.originRevision < state.otherRevision
            }
            .max { $0.originRevision < $1.originRevision }
        guard let latest, try isUntouched(db, latest) else { return nil }
        return latest
    }

    /// Whether a copy is exactly what this device wrote: its stored plaintext has the recorded digest, no review is
    /// waiting on it, nothing queued differs from it and it is not being written. A change from elsewhere would have
    /// been pulled and would differ; a deletion, a move or an edit differs too.
    private func isUntouched(_ db: Database, _ copy: KeptCopy) throws -> Bool {
        guard
            let row = try Row.fetchOne(
                db, sql: "SELECT kind,payload FROM records WHERE id=?", arguments: [id(copy.copyID)])
        else { return false }
        let stored: String = row["payload"]
        guard let digest = try? plaintextDigest(stored, id: copy.copyID, kind: row["kind"]), digest == copy.digest,
            !isBeingWritten(copy.copyID)
        else { return false }
        let reviewed = try Bool.fetchOne(
            db, sql: "SELECT EXISTS(SELECT 1 FROM conflicts WHERE record=?)", arguments: [id(copy.copyID)])
        let queued = try String.fetchAll(
            db, sql: "SELECT payload FROM outbox WHERE record=?", arguments: [id(copy.copyID)])
        return reviewed != true && queued.allSatisfy { $0 == stored }
    }

    /// The later version's content goes under the earlier copy's identity. What it replaces goes to the copy's
    /// Version History, and the change is queued on the revision the copy has, replacing an unsent one.
    private func replaceCopy(_ db: Database, earlier: KeptCopy, with copy: JournalItem) throws {
        var replacement = copy
        replacement.id = earlier.copyID
        let recordID = id(earlier.copyID)
        guard
            let row = try Row.fetchOne(
                db, sql: "SELECT kind,payload,revision FROM records WHERE id=?", arguments: [recordID])
        else { throw JournalError.invalidData }
        try keepInHistory(db, recordID: earlier.copyID, kind: row["kind"], payload: row["payload"], saved: clock())
        let payload = try encode(replacement)
        try removeQueuedChanges(db, recordID: recordID)
        try db.execute(sql: "UPDATE records SET payload=?,dirty=1 WHERE id=?", arguments: [payload, recordID])
        try enqueue(db, recordID: recordID, kind: copy.kind, payload: payload, revision: row["revision"])
        forgetCachedPayload(earlier.copyID)
    }
}
