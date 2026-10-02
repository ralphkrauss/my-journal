import Foundation

public enum PortableRecord {
    public static func decode(_ data: Data) throws -> JournalItem {
        var item = try JournalCoding.decoder().decode(JournalItem.self, from: data)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JournalError.invalidData
        }
        if !["journal", "entry", "template"].contains(item.kind) || !item.document.isEditable || !knownRecord(object) {
            item.preservedJSON = data
            item.document.version = Int.max
        } else {
            try validateDeletionMetadata(item)
        }
        item.normalizeTimestamps()
        return item
    }
    /// Authenticated content this version can't read, such as a record from a newer or faulty client. The original
    /// bytes are kept and the item is read-only; a later version reads the stored record again.
    static func unreadable(_ data: Data, id: UUID, kind: String) -> JournalItem {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        func timestamp(_ key: String) -> Date? {
            (object[key] as? String).flatMap { try? JournalCoding.date(from: $0) }
        }
        var item = JournalItem(id: id, kind: kind, title: object["title"] as? String ?? "")
        item.journalID = (object["journalID"] as? String).flatMap(UUID.init(uuidString:))
        if let date = timestamp("date") ?? timestamp("modifiedAt") { item.date = date }
        item.modifiedAt = timestamp("modifiedAt") ?? item.date
        item.deletedAt = timestamp("deletedAt")
        item.deletedWithJournal = object["deletedWithJournal"] as? Bool ?? false
        item.preservedJSON = data
        item.document.version = Int.max
        return item
    }
    public static func encode(_ item: JournalItem) throws -> Data {
        if let preserved = item.preservedJSON { return preserved }
        try validateDeletionMetadata(item)
        return try JournalCoding.encoder().encode(item)
    }
    private static func validateDeletionMetadata(_ item: JournalItem) throws {
        guard item.archivedAt == nil || item.kind == "entry" else { throw JournalError.invalidData }
        if item.isPermanentlyDeleted {
            guard item.isCanonicalDeletionMarker else { throw JournalError.invalidData }
        } else {
            guard item.permanentDeletionID == nil,
                item.restoredFromDeletionID == nil || ["entry", "journal", "template"].contains(item.kind)
            else { throw JournalError.invalidData }
        }
    }
    private static func knownRecord(_ object: [String: Any]) -> Bool {
        let known: Set<String> = [
            "id", "kind", "journalID", "title", "document", "date", "modifiedAt", "deletedAt", "deletedWithJournal",
            "defaultTemplateID", "permanentlyDeletedAt", "permanentDeletionID", "restoredFromDeletionID", "archivedAt",
        ]
        guard Set(object.keys).isSubset(of: known), let document = object["document"] as? [String: Any],
            Set(document.keys).isSubset(of: ["version", "blocks", "markdown", "metadata"])
        else { return false }
        if document["version"] as? Int == 2 {
            guard Set(document.keys).isSubset(of: ["version", "markdown", "metadata"]), document["markdown"] is String
            else { return false }
            if let metadata = document["metadata"] as? [String: Any] {
                return Set(metadata.keys).isSubset(of: ["blockIDs", "imageTypes", "segmentLengths"])
            }
            return document["metadata"] == nil
        }
        guard Set(document.keys).isSubset(of: ["version", "blocks"]),
            let blocks = document["blocks"] as? [[String: Any]]
        else { return false }
        return blocks.allSatisfy { block in
            let blockKeys: Set<String> = ["id", "kind", "runs", "attachmentID", "imageDescription", "mediaType"]
            guard Set(block.keys).isSubset(of: blockKeys), let runs = block["runs"] as? [[String: Any]] else {
                return false
            }
            return runs.allSatisfy { Set($0.keys).isSubset(of: ["text", "bold", "italic", "underline", "link"]) }
        }
    }
}
