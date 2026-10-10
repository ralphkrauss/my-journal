import Foundation
import GRDB

/// Adopting a server's version that holds the same content as a pending change, as when two devices encrypted the same
/// journals separately and one sent them first.
extension JournalStore {
    /// After the server refused `pending` because it has a newer revision `remote`: when that revision holds the same
    /// content, as when another device encrypted the same journals separately and sent them first, it's adopted as if
    /// this change had been accepted, instead of being shown for review. Returns whether it was.
    func adoptSameContent(_ pending: PendingChange, remote: RemoteChange) throws -> Bool {
        // The library record is merged instead, which also adopts the same content (`recordConflict`).
        guard remote.recordId == pending.recordID, remote.kind == pending.kind, pending.kind != LibraryRecord.kind,
            sameContent(remote.payload, pending.payload, id: pending.recordID, kind: pending.kind)
        else { return false }
        let recordID = id(pending.recordID)
        let adopted = try db.write { db -> Bool in
            guard
                let row = try Row.fetchOne(
                    db, sql: "SELECT payload, revision FROM records WHERE id=?", arguments: [recordID]),
                (row["revision"] as Int64) < remote.revision,
                try Bool.fetchOne(
                    db, sql: "SELECT EXISTS(SELECT 1 FROM outbox WHERE operation=?)",
                    arguments: [id(pending.operationId)]) == true,
                try Bool.fetchOne(
                    db, sql: "SELECT EXISTS(SELECT 1 FROM conflicts WHERE record=?)", arguments: [recordID]) == false
            else { return false }
            guard (row["payload"] as String) == pending.payload else {
                // Edited since: the edit is sent next, based on the server's revision.
                try acknowledge(db, pending: pending, revision: remote.revision)
                return true
            }
            try db.execute(sql: "DELETE FROM outbox WHERE operation=?", arguments: [id(pending.operationId)])
            try db.execute(
                sql: "UPDATE records SET payload=?, revision=?, dirty=0 WHERE id=?",
                arguments: [remote.payload, remote.revision, recordID])
            return true
        }
        if adopted { receivedChanges += 1 }
        return adopted
    }

    /// Whether two stored payloads of a record hold the same content. Encrypted payloads of the same content differ,
    /// for example between two devices that encrypted their copies separately, so they're compared decrypted.
    func sameContent(_ first: String, _ second: String?, id: UUID, kind: String) -> Bool {
        guard let second else { return false }
        if first == second { return true }
        guard let one = Data(base64Encoded: first), let other = Data(base64Encoded: second) else { return false }
        let context = VaultCrypto.recordContext(id: id, kind: kind)
        guard let opened = try? VaultCrypto.open(one, key: key, context: context),
            let otherOpened = try? VaultCrypto.open(other, key: key, context: context)
        else { return false }
        return opened == otherOpened
    }
}
