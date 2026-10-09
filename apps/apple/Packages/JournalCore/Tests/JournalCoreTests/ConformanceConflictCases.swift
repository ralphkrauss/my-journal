import CryptoKit
import Foundation

@testable import JournalCore

/// The cases of protocol/conformance/records/conflict-resolution-v1.json and conflict-copy-ids-v1.json: two versions of
/// one record as exact plaintext, and what settling them produces (protocol/conflicts.md).
struct ConformanceConflictCase {
    let name: String
    let note: String
    let kind: String
    let recordID: UUID
    let local: String
    let other: String
}

enum ConformanceConflictCases {
    static let journalID = UUID(uuidString: "6A0B3C1D-2E4F-4A5B-8C6D-7E8F9A0B1C2D") ?? UUID()
    static let otherJournalID = UUID(uuidString: "9B8A7C6D-5E4F-4A3B-8C2D-1E0F9A8B7C6D") ?? UUID()
    static let entryID = UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301") ?? UUID()
    static let templateID = UUID(uuidString: "A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D") ?? UUID()
    static let templateRefID = UUID(uuidString: "D4C3B2A1-F6E5-4B7A-9D8C-5C4B3A2F1E0D") ?? UUID()
    static let imageID = "01234567-89ab-4cde-8fab-0123456789ab"
    static let deletionID = UUID(uuidString: "C0FFEE00-1111-4222-8333-444455556666") ?? UUID()
    static let otherDeletionID = UUID(uuidString: "C0FFEE00-7777-4888-9999-AAAABBBBCCCC") ?? UUID()

    static func utc(_ text: String) -> Date {
        (try? JournalCoding.date(from: text)) ?? Date(timeIntervalSince1970: 0)
    }
    private static func document(_ markdown: String) -> JournalDocument {
        JournalDocument(
            markdown: markdown,
            metadata: MarkdownMetadata(blockIDs: [], segmentLengths: nil, imageTypes: [:]), freshIdentities: false)
    }
    static func text(_ item: JournalItem) -> String {
        String(decoding: (try? PortableRecord.encode(item)) ?? Data(), as: UTF8.self)
    }
    private static func entry(
        title: String = "Morning pages", markdown: String = "Morning walk.\n",
        at modified: String = "2026-09-20T12:30:00Z"
    ) -> JournalItem {
        var item = JournalItem(
            id: entryID, kind: "entry", journalID: journalID, title: title, document: document(markdown),
            date: utc("2026-09-20T12:00:00Z"))
        item.modifiedAt = utc(modified)
        return item
    }
    private static func template(title: String = "Weekly review", markdown: String = "## What went well?\n")
        -> JournalItem
    {
        var item = JournalItem(
            id: templateID, kind: "template", title: title, document: document(markdown),
            date: utc("2026-02-03T04:05:06Z"))
        item.modifiedAt = utc("2026-02-03T04:05:06Z")
        return item
    }
    private static func journal(title: String = "Personal", at modified: String = "2026-01-02T03:04:05Z") -> JournalItem
    {
        var item = JournalItem(
            id: journalID, kind: "journal", title: title, document: document(""), date: utc("2026-01-02T03:04:05Z"))
        item.modifiedAt = utc(modified)
        return item
    }
    /// A permanent-deletion marker as the Apple app writes it, with a fixed deletion identity.
    private static func marker(of item: JournalItem, at time: String, identity: UUID = deletionID) -> JournalItem {
        var marker = JournalItem(id: item.id, kind: item.kind, date: utc(time))
        marker.deletedAt = utc(time)
        marker.permanentlyDeletedAt = utc(time)
        marker.permanentDeletionID = identity
        return marker
    }
    private static func deleted(_ item: JournalItem, at time: String, withJournal: Bool = false) -> JournalItem {
        var copy = item
        copy.deletedAt = utc(time)
        copy.deletedWithJournal = withJournal
        copy.modifiedAt = utc(time)
        return copy
    }
    /// The record's plaintext with one member of its document changed, as another client could have written it.
    private static func changingDocument(of item: JournalItem, _ change: (inout [String: Any]) -> Void) -> String {
        guard var object = (try? JSONSerialization.jsonObject(with: PortableRecord.encode(item))) as? [String: Any],
            var document = object["document"] as? [String: Any]
        else { return "" }
        change(&document)
        object["document"] = document
        let data =
            (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]))
        return String(decoding: data ?? Data(), as: UTF8.self)
    }
    private static func withMetadata(_ item: JournalItem, _ member: String, _ value: Any) -> String {
        changingDocument(of: item) { document in
            var metadata = document["metadata"] as? [String: Any] ?? [:]
            metadata[member] = value
            document["metadata"] = metadata
        }
    }
    /// The same record with its members in another order and with white space, as another client could write it.
    private static func reformatted(_ item: JournalItem) -> String {
        guard let object = (try? JSONSerialization.jsonObject(with: PortableRecord.encode(item))) as? [String: Any],
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
        else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    private static func withUnknownMember(_ item: JournalItem) -> String {
        guard var object = (try? JSONSerialization.jsonObject(with: PortableRecord.encode(item))) as? [String: Any]
        else { return "" }
        object["futureLayout"] = ["columns": 2]
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data ?? Data(), as: UTF8.self)
    }

    static var all: [ConformanceConflictCase] {
        let base = entry()
        let baseJournal = journal()
        var cases: [ConformanceConflictCase] = []
        func add(_ name: String, _ note: String, _ item: JournalItem, _ local: String, _ other: String) {
            cases.append(
                ConformanceConflictCase(
                    name: name, note: note, kind: item.kind, recordID: item.id, local: local, other: other))
        }
        // Row 1: a version this app cannot read.
        add(
            "held-unknown-member",
            "Row 1: a member this version does not know. The other version is held, nothing is made.",
            base, text(base), withUnknownMember(base))
        add(
            "held-local-unknown-member", "Row 1 is symmetric: this device's version cannot be read either.", base,
            withUnknownMember(base), text(base))
        let newerText = changingDocument(of: base) { $0["version"] = 3 }
        add(
            "held-unsupported-document", "Row 1: a document version this app does not know.", base, text(base),
            newerText)

        // Row 2: the same content, with the deletion state merged as one unit.
        let removed = deleted(base, at: "2026-09-25T08:00:00Z")
        add(
            "same-deleted-here-untouched-there",
            "Row 2: deleted here, untouched there. The item ends up in Recently Deleted once; this version is sent on top.",
            base, text(removed), text(base))
        add(
            "same-untouched-here-deleted-there",
            "Row 2: the other version is the record as it is (adoptsOther), and nothing is sent.", base, text(base),
            text(removed))
        var restored = removed
        restored.deletedAt = nil
        restored.modifiedAt = utc("2026-09-30T08:00:00Z")
        add(
            "same-restored-here-deleted-there",
            "Row 2: restored on one device and deleted on the other: it stays deleted.", base, text(restored),
            text(removed))
        let legacy = deleted(base, at: "2026-09-27T08:00:00Z", withJournal: true)
        add(
            "same-live-here-legacy-deleted-there",
            "Row 2: (deletedAt, deletedWithJournal) is one unit. An entry an earlier version deleted with its journal, against a live one, is deleted with its journal.",
            base, text(base), text(legacy))
        add(
            "same-deleted-here-legacy-deleted-there",
            "Row 2: both deleted: the pair that is deleted with its journal wins, whichever is later.", base,
            text(deleted(base, at: "2026-10-01T08:00:00Z")), text(legacy))
        add(
            "same-legacy-here-deleted-there", "Row 2: the same, the other way round.", base, text(legacy),
            text(deleted(base, at: "2026-10-01T08:00:00Z")))
        add(
            "same-both-deleted", "Row 2: both deleted the ordinary way: the other version's pair, whatever the times.",
            base, text(deleted(base, at: "2026-10-01T08:00:00Z")), text(deleted(base, at: "2026-09-25T08:00:00Z")))
        add(
            "same-written-differently",
            "Row 2 compares decoded values, never bytes: the same members in another order and with white space.", base,
            text(base), reformatted(base))
        var touched = base
        touched.modifiedAt = utc("2026-09-28T09:00:00Z")
        add(
            "same-modified-time-only", "The modified time is informational and is not content.", base, text(touched),
            text(base))

        // Content that differs: strict, so a false "different" only keeps a version.
        func differs(_ name: String, _ note: String, _ other: JournalItem) {
            add(name, note, base, text(base), text(other))
        }
        var titled = base
        titled.title = "Another title"
        differs("differs-title", "Row 3 (entries and templates that differ): the title.", titled)
        var dated = base
        dated.date = utc("2026-09-21T12:00:00Z")
        var composed = base
        composed.title = "Caf\u{E9}"
        var decomposed = base
        decomposed.title = "Cafe\u{301}"
        add(
            "differs-title-normalization-only",
            "Titles that are canonically equivalent but not the same code points are different: strings are compared by code points, never normalized.",
            base, text(composed), text(decomposed))
        differs("differs-date", "The entry date.", dated)
        var moved = base
        moved.journalID = otherJournalID
        differs("differs-journal", "The journal.", moved)
        var archived = base
        archived.archivedAt = utc("2026-09-22T12:00:00Z")
        differs("differs-archived", "archivedAt.", archived)
        differs("differs-text", "The text.", entry(markdown: "Morning walk, and more.\n"))
        add(
            "differs-block-identities-only",
            "A version that differs only in metadata.blockIDs is different, strictly: every client agrees.", base,
            text(base), withMetadata(base, "blockIDs", ["11111111-2222-4333-8444-555555555555"]))
        add(
            "differs-segment-lengths-only", "Only metadata.segmentLengths differs: different.", base, text(base),
            withMetadata(base, "segmentLengths", [1, 13]))
        add(
            "differs-image-types-only", "Only metadata.imageTypes differs: different.", base, text(base),
            withMetadata(base, "imageTypes", [imageID: "image/png"]))
        let weekly = template()
        add(
            "differs-template", "A template that differs is kept for review like an entry.", weekly, text(weekly),
            text(template(title: "Weekly review, edited")))

        // Rows 4 and 5: permanent deletion.
        let theirs = marker(of: base, at: "2026-09-26T10:00:00Z")
        add(
            "entry-edited-here-deleted-for-good-there",
            "Row 4: the marker is the record; the edited version is parked as a new entry in Recently Deleted.", base,
            text(entry(title: "Morning pages", markdown: "Words written after the deletion.\n")), text(theirs))
        add(
            "entry-deleted-for-good-here-edited-there",
            "Row 4: this device's marker stays the record (sent on top); the other version is parked.", base,
            text(theirs),
            text(entry(title: "Morning pages", markdown: "Words written elsewhere.\n")))
        add(
            "untitled-entry-parked", "Row 4: the title is unchanged, even when empty.", base,
            text(entry(title: "", markdown: "No title here.\n")), text(theirs))
        add(
            "entry-in-recently-deleted-edited-there",
            "Row 4: an edited version that was in Recently Deleted is parked deleted at the marker's time.", base,
            text(deleted(entry(markdown: "Edited while deleted.\n"), at: "2026-09-23T10:00:00Z", withJournal: true)),
            text(theirs))
        let weeklyMarker = marker(of: weekly, at: "2026-09-26T10:00:00Z")
        add(
            "template-edited-here-deleted-for-good-there", "Row 4 for a template.", weekly,
            text(template(title: "Weekly review", markdown: "## Edited here\n")), text(weeklyMarker))
        add(
            "two-markers", "Row 5: two permanent deletions. The other device's marker is the record.", base,
            text(theirs),
            text(marker(of: base, at: "2026-09-27T11:00:00Z", identity: otherDeletionID)))

        // Rows 6 and 7: journals.
        add(
            "journal-renamed-on-both",
            "Row 6: this device's name stays and the other name is noted; the other version is kept in history.",
            baseJournal, text(journal(title: "Alpha")), text(journal(title: "Beta")))
        var withTemplate = baseJournal
        withTemplate.defaultTemplateID = templateRefID
        add(
            "journal-renamed-normalization-only",
            "Row 6: names that differ only in normalization are different names: the other name is noted.", baseJournal,
            text(journal(title: "Caf\u{E9}")), text(journal(title: "Cafe\u{301}")))
        add(
            "journal-template-only", "Row 6: equal names, different default template: this device's, without a note.",
            baseJournal, text(baseJournal), text(withTemplate))
        add(
            "journal-same-content", "Row 2 for a journal: the same name and template are not a conflict.", baseJournal,
            text(baseJournal), text(journal(at: "2026-02-01T00:00:00Z")))
        add(
            "journal-renamed-here-deleted-there",
            "Row 6: deleted wins (the deletion state is merged) and this device's name stays.", baseJournal,
            text(journal(title: "Alpha")), text(deleted(journal(title: "Beta"), at: "2026-09-25T08:00:00Z")))
        add(
            "journal-edited-here-deleted-for-good-there",
            "Row 7: the marker is the record; no journal is made, because a copy would not carry entries.", baseJournal,
            text(journal(title: "Alpha")), text(marker(of: baseJournal, at: "2026-09-26T10:00:00Z")))
        add(
            "journal-deleted-for-good-here-edited-there", "Row 7: the other way round.", baseJournal,
            text(marker(of: baseJournal, at: "2026-09-26T10:00:00Z")), text(journal(title: "Beta")))
        return cases
    }

    // MARK: Expected

    /// What settling `testCase` produces, as the fixture states it.
    static func expected(for testCase: ConformanceConflictCase, ids: ConflictCopyIdentity) throws -> [String: Any] {
        let local = ConflictSide(plaintext: Data(testCase.local.utf8), id: testCase.recordID, kind: testCase.kind)
        let other = ConflictSide(plaintext: Data(testCase.other.utf8), id: testCase.recordID, kind: testCase.kind)
        func instant(_ date: Date?) -> Any { date.map { Int($0.timeIntervalSince1970) } ?? NSNull() }
        func identity(_ value: UUID?) -> Any { value?.uuidString.lowercased() ?? NSNull() }
        switch ConflictResolution.resolve(local: local, other: other, ids: ids) {
        case .held: return ["row": 1, "outcome": "held"]
        case .review: return ["row": 3, "outcome": "review"]
        case .sameContent(let record, let adoptsOther):
            return [
                "row": 2, "outcome": "sameContent", "adoptsOther": adoptsOther, "deletedAt": instant(record.deletedAt),
                "deletedWithJournal": record.deletedWithJournal,
            ]
        case .parked(let parked, let markerIsLocal):
            return [
                "row": 4, "outcome": "parked", "markerIsLocal": markerIsLocal,
                "parked": [
                    "id": identity(parked.id), "kind": parked.kind, "title": parked.title,
                    "date": instant(parked.date), "modifiedAt": instant(parked.modifiedAt),
                    "journalID": identity(parked.journalID), "archivedAt": instant(parked.archivedAt),
                    "deletedAt": instant(parked.deletedAt), "deletedWithJournal": parked.deletedWithJournal,
                    "restoredFromDeletionID": identity(parked.restoredFromDeletionID),
                    "markdown": parked.document.version == 2 ? parked.document.markdown : NSNull(),
                ] as [String: Any],
            ]
        case .twoMarkers: return ["row": 5, "outcome": "twoMarkers"]
        case .journal(let record, let otherName):
            return [
                "row": 6, "outcome": "journal", "title": record.title, "deletedAt": instant(record.deletedAt),
                "deletedWithJournal": record.deletedWithJournal,
                "defaultTemplateID": identity(record.defaultTemplateID), "otherName": otherName ?? NSNull(),
            ]
        case .journalMarker(let markerIsLocal, let name):
            return ["row": 7, "outcome": "journalMarker", "markerIsLocal": markerIsLocal, "name": name]
        }
    }

    // MARK: Identities

    struct IdentityCase {
        let name: String
        let note: String
        let protection: String
        let label: ConflictCopyIdentity.Label
        let recordID: String
        let text: String
    }
    static let identityCases: [IdentityCase] = [
        IdentityCase(
            name: "copy-ascii", note: "A copy of the other version (row 3).", protection: "encrypted", label: .copy,
            recordID: "3f2504e0-4f89-41d3-9a0c-0305e82c3301", text: "{\"title\":\"Morning pages\"}"),
        IdentityCase(
            name: "park-same-text", note: "A parked entry and a copy of the same version never share an identity.",
            protection: "encrypted", label: .park, recordID: "3f2504e0-4f89-41d3-9a0c-0305e82c3301",
            text: "{\"title\":\"Morning pages\"}"),
        IdentityCase(
            name: "copy-other-record", note: "Another record with the same text derives another identity.",
            protection: "encrypted", label: .copy, recordID: "6a0b3c1d-2e4f-4a5b-8c6d-7e8f9a0b1c2d",
            text: "{\"title\":\"Morning pages\"}"),
        IdentityCase(
            name: "park-unicode", note: "The text is hashed as UTF-8, whatever it holds.", protection: "encrypted",
            label: .park, recordID: "3f2504e0-4f89-41d3-9a0c-0305e82c3301",
            text: "{\"title\":\"Crème brûlée, 日記 and 🌿\",\"line\":\"a\\nb\"}"),
        IdentityCase(
            name: "copy-trailing-newline", note: "One more byte is another identity.", protection: "encrypted",
            label: .copy, recordID: "3f2504e0-4f89-41d3-9a0c-0305e82c3301", text: "{\"title\":\"Morning pages\"}\n"),
        IdentityCase(
            name: "copy-plaintext-library",
            note:
                "A library without encryption has no vault key: the derivation key is the SHA-256 of the info string.",
            protection: "plaintext", label: .copy, recordID: "3f2504e0-4f89-41d3-9a0c-0305e82c3301",
            text: "{\"title\":\"Morning pages\"}"),
        IdentityCase(
            name: "park-plaintext-library", note: "The same for a parked entry.", protection: "plaintext", label: .park,
            recordID: "3f2504e0-4f89-41d3-9a0c-0305e82c3301", text: "{\"title\":\"Morning pages\"}"),
    ]
}
