import Foundation
import GRDB

/// Merging a device's library into a server's (docs/design/join-with-local-journals.md §2).
extension JournalStore {
    /// Imports the journals of `source` into this staged store, which already holds everything the server has
    /// (pulled first). Same-name journals are combined, templates the server has aren't imported again, and a
    /// template that differs from the server's of the same name is kept for review. Identities are derived from
    /// `server`, so importing again after a failed or repeated attempt never duplicates what the server already
    /// has. Saving queues everything for the next synchronization; images are checked with the server before any
    /// upload, because the server never replaces an image. An image whose file is gone from this device is left out,
    /// as synchronizing does, and the entries that use it are still merged.
    ///
    /// `readByAgents` lists server journals an agent can read (`ServerClient.journalsAgentsCanRead`), which are never
    /// combined; nil combines no journal.
    ///
    /// What the server already has under a derived identity is replaced as an ordinary edit only when `source`
    /// queued that very version in an earlier attempt; any other version, such as one sent by another device with a
    /// copy of this library, is kept for review. Before anything is sent, `source` remembers what this attempt queued.
    public func importMerging(from source: JournalStore, server: String, readByAgents: Set<UUID>?) async throws {
        let transfer = try await source.contentForImport(for: .merge)
        let arrangement = try await source.arrangementForImport()
        let queuedBefore = try await source.mergeQueued()
        let versioned = Set(transfer.history.map(\.id) + transfer.conflicts.map(\.id))
        let plan = MergePlan(
            local: transfer.items, server: try items(), server: server, readByAgents: readByAgents,
            versioned: versioned)
        // Only images that something imported uses are staged.
        let imported =
            transfer.items.filter { !plan.skipped.contains($0.id) && plan.identities[$0.id] != nil }
            + transfer.history.filter { plan.identities[$0.id] != nil }
            + transfer.conflicts.map(\.remote).filter { plan.identities[$0.id] != nil }
        var images: [UUID: UUID] = [:]
        for version in transfer.items + transfer.history + transfer.conflicts.map(\.remote) {
            for image in version.document.attachmentIDs { images[image] = plan.derived(image) }
        }
        for original in Set(imported.flatMap { $0.document.attachmentIDs }).sorted(by: { $0.uuidString < $1.uuidString }
        ) {
            try Task.checkCancellation()
            guard let merged = images[original], try !hasAttachment(merged) else { continue }
            // Only an image whose file is gone is left out; one that can't be read fails the merge, which can be tried
            // again, because the old library is removed once the merged one has synchronized.
            guard await source.hasAttachmentFile(original) else { continue }
            try addAttachmentToVerify(try await source.attachment(original), id: merged)
        }
        try Task.checkCancellation()
        try writeMerged(transfer, plan: plan, images: images, queuedBefore: queuedBefore)
        // Pins of merged entries, and journals added here after the server's; combined journals don't move.
        let identities = plan.mergedIdentities.filter { !plan.skipped.contains($0.key) }
        try importArrangement(arrangement, identities: identities)
        try await source.rememberMergeQueued(try queuedPayloadDigests())
    }
    private func writeMerged(
        _ transfer: ContentImport, plan: MergePlan, images: [UUID: UUID], queuedBefore: [UUID: Set<String>]
    ) throws {
        try db.write { db in
            var added = Set<UUID>()
            for item in transfer.items where !plan.skipped.contains(item.id) {
                try Task.checkCancellation()
                // Written after the server deleted its journal, it arrives as any change written offline into that
                // journal would: in Recently Deleted with it, or under Unavailable Journals when it was deleted
                // permanently. Changed after the server deleted it permanently, it's kept as a copy.
                guard let merged = try plan.remap(item, images: images, current: true) else { continue }
                if let sent = plan.deletedOnServer[merged.id] {
                    try keepDeleted(db, merged, server: sent, queuedBefore: queuedBefore[merged.id] ?? [])
                    continue
                }
                if plan.reviewed.contains(item.id) {
                    try keepForReview(db, reviewingTemplate: merged)
                } else if try importMerged(db, merged, queuedBefore: queuedBefore[merged.id] ?? []) {
                    added.insert(merged.id)
                }
            }
            try importMergedVersions(db, transfer: transfer, plan: plan, images: images, added: added)
        }
    }
    /// Something an earlier attempt sent that the server has moved to Recently Deleted since stays there. When this
    /// device's content differs, it's kept as an ordinary change if the server's content, apart from being deleted, is
    /// what this library queued (`queuedBefore`); otherwise, such as when another device with a copy of this library
    /// sent it, both are kept for review.
    private func keepDeleted(
        _ db: Database, _ merged: JournalItem, server sent: JournalItem, queuedBefore: Set<String>
    ) throws {
        var kept = merged
        kept.deletedAt = sent.deletedAt
        kept.deletedWithJournal = sent.deletedWithJournal
        var unchanged = kept
        unchanged.modifiedAt = sent.modifiedAt
        guard unchanged != sent, sent.document.isEditable, sent.preservedJSON == nil, try !hasConflict(db, sent.id)
        else { return }
        let row = try Row.fetchOne(
            db, sql: "SELECT kind,payload,revision FROM records WHERE id=?", arguments: [id(sent.id)])
        if let row, !queuedBefore.contains(Self.payloadDigest(row["payload"])),
            !queuedBefore.contains(try Self.contentDigest(sent))
        {
            try keepForReview(db, local: kept, server: row)
        } else {
            try save(db, item: kept)
        }
    }
    /// Whether this store has an image's file.
    func hasAttachmentFile(_ uuid: UUID) -> Bool { FileManager.default.fileExists(atPath: attachmentURL(uuid).path) }
    /// Whether this store has an image, uploaded or not.
    func hasAttachment(_ uuid: UUID) throws -> Bool {
        try db.read {
            try Bool.fetchOne($0, sql: "SELECT EXISTS(SELECT 1 FROM attachments WHERE id=?)", arguments: [id(uuid)])
                == true
        }
    }
    /// Adds an image that the server may already have from an earlier attempt: synchronization asks the server
    /// first and uploads it only when it's missing.
    private func addAttachmentToVerify(_ bytes: Data, id uuid: UUID) throws {
        _ = try addAttachment(bytes, id: uuid)
        try db.write {
            try $0.execute(sql: "UPDATE attachments SET uploaded=2 WHERE id=?", arguments: [id(uuid)])
        }
    }
    /// Saves a merged item. One the server already has is left alone when it's the same, replaced as an ordinary
    /// edit when the server's version is one an earlier attempt from the same library queued (`queuedBefore`), and
    /// otherwise kept for review. Returns whether the record is new here.
    private func importMerged(_ db: Database, _ item: JournalItem, queuedBefore: Set<String>) throws -> Bool {
        guard
            let row = try Row.fetchOne(
                db, sql: "SELECT kind,payload,revision FROM records WHERE id=?", arguments: [id(item.id)])
        else {
            try save(db, item: item, importingMarker: item.isPermanentlyDeleted)
            return true
        }
        let current = try decode(row["payload"], id: item.id, kind: row["kind"])
        guard current != item else { return false }
        if queuedBefore.contains(Self.payloadDigest(row["payload"])), !item.isPermanentlyDeleted,
            !current.isPermanentlyDeleted, current.isSupported, try !hasConflict(db, item.id)
        {
            try save(db, item: item)
        } else {
            try keepForReview(db, local: item, server: row)
        }
        return false
    }
    /// A device template that differs from the server's template of the same name: this device's content on the
    /// server's record, for review against the server's version.
    private func keepForReview(_ db: Database, reviewingTemplate local: JournalItem) throws {
        guard
            let row = try Row.fetchOne(
                db, sql: "SELECT kind,payload,revision FROM records WHERE id=?", arguments: [id(local.id)])
        else { throw JournalError.invalidData }
        var reviewed = try decode(row["payload"], id: local.id, kind: row["kind"])
        reviewed.title = local.title
        reviewed.document = local.document
        reviewed.modifiedAt = local.modifiedAt
        try keepForReview(db, local: reviewed, server: row)
    }
    /// Records the same state as a pulled change meeting a local edit: this device's version is the record, waiting
    /// to be sent, and the server's version is the other side of a review. Nothing is sent until it's resolved.
    private func keepForReview(_ db: Database, local: JournalItem, server row: Row) throws {
        let recordID = id(local.id)
        let serverPayload: String = row["payload"]
        let server = try decode(serverPayload, id: local.id, kind: row["kind"])
        if try hasConflict(db, local.id) {
            // Already under review: this version is kept in Version History instead.
            try db.execute(
                sql: "INSERT INTO history(record,kind,payload,saved) VALUES (?,?,?,?)",
                arguments: [recordID, local.kind, try encode(local), JournalCoding.timestamp(local.modifiedAt)])
            return
        }
        try db.execute(
            sql: "UPDATE records SET payload=?,dirty=1 WHERE id=?", arguments: [try encode(local), recordID])
        try db.execute(sql: "DELETE FROM outbox WHERE record=?", arguments: [recordID])
        try db.execute(
            sql: "INSERT INTO conflicts(record,payload,revision,device,modified) VALUES (?,?,?,?,?)",
            arguments: [
                recordID, serverPayload, row["revision"] as Int64, "00000000-0000-0000-0000-000000000000",
                JournalCoding.timestamp(server.modifiedAt),
            ])
        receivedChanges += 1
    }
    /// Digests of the payloads queued for sending, and of their content apart from deletion, by record.
    private func queuedPayloadDigests() throws -> [UUID: Set<String>] {
        let rows = try db.read { try Row.fetchAll($0, sql: "SELECT record,kind,payload FROM outbox") }
        var digests: [UUID: Set<String>] = [:]
        for row in rows {
            guard let record = UUID(uuidString: row["record"]) else { throw JournalError.invalidData }
            let payload: String = row["payload"]
            let item = try decode(payload, id: record, kind: row["kind"])
            digests[record, default: []].formUnion([Self.payloadDigest(payload), try Self.contentDigest(item)])
        }
        return digests
    }
    /// Identifies an item's content apart from whether it's in Recently Deleted and when it was last changed, so a
    /// version another device only moved to Recently Deleted is recognized.
    static func contentDigest(_ item: JournalItem) throws -> String {
        var content = item
        content.deletedAt = nil
        content.deletedWithJournal = false
        content.modifiedAt = Date(timeIntervalSince1970: 0)
        content.storedVersion = nil
        return payloadDigest(String(decoding: try JournalCoding.encoder().encode(content), as: UTF8.self))
    }
    /// What merging this library into a server queued for sending: digests of the payloads, by derived identity.
    /// Kept until the library is removed, so an attempt after one that stopped part way recognizes what it sent.
    func mergeQueued() throws -> [UUID: Set<String>] {
        guard let stored = try setting(Self.mergeQueuedSetting) else { return [:] }
        let decoded = try JournalCoding.decoder().decode([String: [String]].self, from: stored)
        var queued: [UUID: Set<String>] = [:]
        for (record, digests) in decoded {
            guard let id = UUID(uuidString: record) else { throw JournalError.invalidData }
            queued[id] = Set(digests)
        }
        return queued
    }
    func rememberMergeQueued(_ digests: [UUID: Set<String>]) throws {
        guard !digests.isEmpty else { return }
        var queued = try mergeQueued()
        for (record, added) in digests { queued[record, default: []].formUnion(added) }
        let stored = Dictionary(uniqueKeysWithValues: queued.map { (id($0.key), $0.value.sorted()) })
        try setSetting(Self.mergeQueuedSetting, value: try JournalCoding.encoder().encode(stored))
    }
    static let mergeQueuedSetting = "merge-queued"
    private func hasConflict(_ db: Database, _ uuid: UUID) throws -> Bool {
        try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM conflicts WHERE record=?)", arguments: [id(uuid)])
            == true
    }
    /// Earlier versions follow the records they belong to. A change awaiting review stays under review on a record
    /// that is new here; otherwise it's kept in Version History, so no version is lost.
    private func importMergedVersions(
        _ db: Database, transfer: ContentImport, plan: MergePlan, images: [UUID: UUID], added: Set<UUID>
    ) throws {
        // Versions of a combined journal or a template the server has go to the server's record.
        for version in transfer.history.reversed() {
            guard let merged = try plan.remap(version, images: images) else { continue }
            try db.execute(
                sql: "INSERT INTO history(record,kind,payload,saved) VALUES (?,?,?,?)",
                arguments: [
                    id(merged.id), merged.kind, try encode(merged), JournalCoding.timestamp(merged.modifiedAt),
                ])
        }
        for conflict in transfer.conflicts {
            guard let remote = try plan.remap(conflict.remote, images: images) else { continue }
            if added.contains(remote.id), try !hasConflict(db, remote.id) {
                try db.execute(
                    sql: "INSERT INTO conflicts(record,payload,revision,device,modified) VALUES (?,?,?,?,?)",
                    arguments: [
                        id(remote.id), try encode(remote), 0, id(conflict.deviceID),
                        JournalCoding.timestamp(conflict.modifiedAt),
                    ])
            } else {
                try db.execute(
                    sql: "INSERT INTO history(record,kind,payload,saved) VALUES (?,?,?,?)",
                    arguments: [
                        id(remote.id), remote.kind, try encode(remote), JournalCoding.timestamp(conflict.modifiedAt),
                    ])
            }
        }
    }
}
