import Foundation

struct ContentImport: Sendable {
    let items: [JournalItem]
    let history: [JournalItem]
    let conflicts: [ConflictVersion]
    let recordIDs: [UUID: UUID]
    let imageIDs: [UUID: UUID]

    /// What the content is imported for, which decides how refusing it is explained.
    enum Purpose: Sendable { case archive, merge }

    init(items: [JournalItem], history: [JournalItem], conflicts: [ConflictVersion], for purpose: Purpose = .archive)
        throws
    {
        let everyVersion = items + history + conflicts.map(\.remote)
        guard everyVersion.allSatisfy({ $0.document.isEditable && $0.preservedJSON == nil }) else {
            switch purpose {
            case .archive:
                throw JournalError.server(
                    "Update My Journal to import this archive as new journals. You can still restore it on a device with no journals."
                )
            case .merge:
                throw JournalError.server(
                    "Update My Journal to merge the journals on this device. Some of them were saved by a newer version."
                )
            }
        }
        self.items = items
        self.history = history
        self.conflicts = conflicts
        // Missing relationships remain missing, with a consistent fresh identity across every version.
        // Keeping their source IDs could accidentally connect imported content to another vault's records.
        let identities = Set(everyVersion.flatMap { [$0.id, $0.journalID, $0.defaultTemplateID].compactMap { $0 } })
        recordIDs = Dictionary(uniqueKeysWithValues: identities.map { ($0, UUID()) })
        let images = Set(everyVersion.flatMap { $0.document.attachmentIDs })
        imageIDs = Dictionary(uniqueKeysWithValues: images.map { ($0, UUID()) })
    }
    func remap(_ original: JournalItem) throws -> JournalItem {
        guard let identifier = recordIDs[original.id] else { throw JournalError.invalidData }
        var item = original
        item.id = identifier
        if let journal = original.journalID {
            guard let mapped = recordIDs[journal] else { throw JournalError.invalidData }
            item.journalID = mapped
        }
        if let template = original.defaultTemplateID {
            guard let mapped = recordIDs[template] else { throw JournalError.invalidData }
            item.defaultTemplateID = mapped
        }
        try item.document.remapAttachments(imageIDs)
        // Every image must refer to an attachment copied with it.
        guard Set(item.document.attachmentIDs).isSubset(of: Set(imageIDs.values)) else {
            throw JournalError.invalidData
        }
        return item
    }
}
