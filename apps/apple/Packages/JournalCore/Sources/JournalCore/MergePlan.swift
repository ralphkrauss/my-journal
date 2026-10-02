import CryptoKit
import Foundation

/// Where each of a device's items goes when its library is merged into a server's
/// (docs/design/join-with-local-journals.md §2). Identities are derived from the server and the original identity,
/// so a merge that is tried again, with any device grant, produces the same records instead of copies.
struct MergePlan {
    /// The server identity the derived identities belong to: its `serverId`, or its address for older servers.
    let server: String
    /// Where each identity the device's items use ends up: a server record or a derived identity. An unedited
    /// built-in template with no server template of its name, and no versions of its own, has none.
    private(set) var identities: [UUID: UUID] = [:]
    /// Device items whose current version isn't imported: journals combined with a server journal, and templates the
    /// server already has. Their earlier versions are still kept under the server's record.
    private(set) var skipped = Set<UUID>()
    /// Device templates kept for review against the server's template of the same name.
    private(set) var reviewed = Set<UUID>()
    /// New names for device journals added next to a server journal of the same name, or next to another device
    /// journal of that name (docs/design/journal-name-uniqueness.md §4.5).
    private(set) var titles: [UUID: String] = [:]
    /// Server versions, by server identity, of what an earlier attempt sent and the server has deleted since: moved to
    /// Recently Deleted or deleted permanently. Merging again respects the deletion (§4.5, rule B).
    private(set) var deletedOnServer: [UUID: JournalItem] = [:]
    /// Device items the server deleted permanently: neither they nor their earlier versions are imported.
    private var purged = Set<UUID>()

    /// `readByAgents` lists server journals an agent was given one by one, which are never combined; nil combines no
    /// journal, because it isn't known which ones agents read. `versioned` lists device items with earlier versions or
    /// a change awaiting review: those are never left out.
    init(
        local: [JournalItem], server items: [JournalItem], server identity: String, readByAgents: Set<UUID>?,
        versioned: Set<UUID> = []
    ) {
        server = identity
        let onServer = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let serverItems = items.filter { !$0.isPermanentlyDeleted && $0.deletedAt == nil }
        let combinable = serverItems.filter { item in
            item.kind == "journal" && readByAgents.map { !$0.contains(item.id) } == true
        }
        for item in local {
            // What an earlier attempt already sent keeps its identity: an edit since is an ordinary change to it.
            let earlier = derived(item.id)
            guard let sent = onServer[earlier] else { continue }
            identities[item.id] = earlier
            guard sent.deletedAt != nil || sent.isPermanentlyDeleted else { continue }
            deletedOnServer[earlier] = sent
            // In Recently Deleted on the server, it stays there, with this device's content if it changed.
            guard let deletedAt = sent.permanentlyDeletedAt else { continue }
            if item.kind != "journal", item.modifiedAt > deletedAt {
                // Changed on this device after the deletion: kept as a copy, as Keep Entry as Copy would.
                identities[item.id] = Self.derived(item.id, server: identity + "\u{0}copy")
            } else {
                skipped.insert(item.id)
                purged.insert(item.id)
            }
        }
        planJournals(local, server: serverItems.filter { $0.kind == "journal" }, combinable: combinable)
        planTemplates(local, server: serverItems.filter { $0.kind == "template" }, versioned: versioned)
        for item in local where item.kind != "journal" && item.kind != "template" && identities[item.id] == nil {
            identities[item.id] = derived(item.id)
        }
        // Relationships to records that aren't in this library keep a consistent derived identity.
        for item in local {
            if let journal = item.journalID, identities[journal] == nil { identities[journal] = derived(journal) }
        }
    }

    func derived(_ original: UUID) -> UUID { Self.derived(original, server: server) }
    static func derived(_ original: UUID, server: String) -> UUID {
        let name = "myjournal-merge-1\u{0}\(server)\u{0}\(original.uuidString.lowercased())"
        var bytes = Array(SHA256.hash(data: Data(name.utf8)).prefix(16))
        // RFC 9562 version 8 (custom) and variant bits.
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9],
                bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }
    /// Names match ignoring case and surrounding spaces.
    static func nameKey(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive], locale: nil)
    }
    private static func oldest(_ items: [JournalItem]) -> JournalItem? {
        items.min { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
    }

    /// A device journal not in Recently Deleted is combined with the oldest server journal of the same name that it may
    /// be combined with. Any other device journal is added, numbered when a listed server journal or a device journal
    /// added before it has its name.
    private mutating func planJournals(_ local: [JournalItem], server: [JournalItem], combinable: [JournalItem]) {
        let byName = Dictionary(grouping: combinable) { JournalNames.key($0.title) }
        var taken = Set(server.map { JournalNames.key($0.title) })
        let journals = local.filter { $0.kind == "journal" && identities[$0.id] == nil }
        for journal in journals.sorted(by: JournalNames.precedes) {
            let listed = JournalNames.isListed(journal)
            if listed, let target = byName[JournalNames.key(journal.title)].flatMap(Self.oldest) {
                identities[journal.id] = target.id
                skipped.insert(journal.id)
                continue
            }
            identities[journal.id] = derived(journal.id)
            guard listed else { continue }
            let title = JournalNames.available(journal.title, avoiding: taken)
            if title != journal.title { titles[journal.id] = title }
            taken.insert(JournalNames.key(title))
        }
    }
    /// Unedited built-ins and templates the server has with the same name and content aren't imported. A template
    /// that differs from the only server template of its name, being the only one of that name here, is reviewed;
    /// with more than one of that name on either side, each is added.
    private mutating func planTemplates(_ local: [JournalItem], server: [JournalItem], versioned: Set<UUID>) {
        let byName = Dictionary(grouping: server) { Self.nameKey($0.title) }
        let candidates = local.filter {
            $0.kind == "template" && $0.deletedAt == nil && !$0.isPermanentlyDeleted
                && !BuiltInTemplates.isUnedited($0)
        }
        let localCount = Dictionary(grouping: candidates) { Self.nameKey($0.title) }.mapValues(\.count)
        for template in local where template.kind == "template" && identities[template.id] == nil {
            let key = Self.nameKey(template.title)
            let sameName = byName[key] ?? []
            let identical = sameName.first { $0.document.sameText(as: template.document) }
            if template.deletedAt != nil || template.isPermanentlyDeleted {
                identities[template.id] = derived(template.id)
            } else if BuiltInTemplates.isUnedited(template), !versioned.contains(template.id) {
                // The person didn't write it: it points at the server's template of its name, if any.
                skipped.insert(template.id)
                identities[template.id] = identical?.id ?? Self.oldest(sameName)?.id
            } else if let identical {
                skipped.insert(template.id)
                identities[template.id] = identical.id
            } else if sameName.count == 1, localCount[key] == 1, let target = sameName.first {
                reviewed.insert(template.id)
                identities[template.id] = target.id
            } else {
                identities[template.id] = derived(template.id)
            }
        }
    }

    /// `item` with the identities it has on the server, and for a current journal its new name. Nil for an item that
    /// has none.
    func remap(_ item: JournalItem, images: [UUID: UUID], current: Bool = false) throws -> JournalItem? {
        guard let identity = identities[item.id], !purged.contains(item.id) else { return nil }
        var merged = item
        if current, let title = titles[item.id] { merged.title = title }
        // A new record here: nothing was read from this store.
        merged.storedVersion = nil
        merged.id = identity
        merged.journalID = item.journalID.map { identities[$0] ?? derived($0) }
        // A default template the server doesn't have, such as an unmatched built-in, is left unset.
        merged.defaultTemplateID = item.defaultTemplateID.flatMap { identities[$0] }
        try merged.document.remapAttachments(images)
        return merged
    }
}

extension JournalDocument {
    /// The writing as Markdown lines without blank ones: the same text stored as blocks or as Markdown compares equal.
    var comparableText: String {
        markdown.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }
    /// The same writing, whether stored as blocks or as Markdown: the whole Markdown, ignoring only surrounding space.
    func sameText(as other: JournalDocument) -> Bool {
        self == other
            || markdown.trimmingCharacters(in: .whitespacesAndNewlines)
                == other.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
