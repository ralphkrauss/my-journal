import Foundation

@testable import JournalCore

/// The records of protocol/conformance/records/records-v1.json: what each client must read from a record's
/// plaintext, and what it must do with the bytes when it writes the record back.
struct ConformanceRecordCase {
    let name: String
    let note: String
    /// The ID and kind the record is stored under: the sync path and kind, and the encryption context.
    let id: String
    let kind: String
    let plaintext: String
}

enum ConformanceRecordCases {
    static let journalID = "6A0B3C1D-2E4F-4A5B-8C6D-7E8F9A0B1C2D"
    static let entryID = "3F2504E0-4F89-41D3-9A0C-0305E82C3301"
    static let templateID = "A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D"
    static let imageID = "01234567-89AB-4CDE-8FAB-0123456789AB"
    static let deletionID = "C0FFEE00-1111-4222-8333-444455556666"

    private static func utc(_ text: String) -> Date {
        (try? JournalCoding.date(from: text)) ?? Date(timeIntervalSince1970: 0)
    }
    private static func uuid(_ text: String) -> UUID { UUID(uuidString: text) ?? UUID() }

    /// A record as this app writes it, so the fixture shows the current writer's bytes.
    private static func written(_ item: JournalItem) -> String {
        String(decoding: (try? PortableRecord.encode(item)) ?? Data(), as: UTF8.self)
    }
    private static func document(_ markdown: String, images: [String: String] = [:]) -> JournalDocument {
        JournalDocument(
            markdown: markdown,
            metadata: MarkdownMetadata(blockIDs: [], segmentLengths: nil, imageTypes: images), freshIdentities: false)
    }

    private static func appleWritten() -> [ConformanceRecordCase] {
        let image = imageID.lowercased()
        var entry = JournalItem(
            id: uuid(entryID), kind: "entry", journalID: uuid(journalID), title: "Morning pages",
            document: document(
                "Morning *walk* with ![the bay](attachments/\(image)).\n\n- [ ] Call the bank\n",
                images: [image: "image/png"]),
            date: utc("2026-09-20T12:00:00Z"))
        entry.modifiedAt = utc("2026-09-20T12:30:00Z")
        var deleted = JournalItem(
            id: uuid(entryID), kind: "entry", journalID: uuid(journalID), title: "",
            document: document("Crème brûlée, 日記 and 🌿.\nSecond line."), date: utc("2026-09-21T07:00:00Z"))
        deleted.deletedAt = utc("2026-09-22T09:00:00Z")
        deleted.archivedAt = utc("2026-09-21T20:00:00Z")
        var journal = JournalItem(
            id: uuid(journalID), kind: "journal", title: "Personal", document: document(""),
            date: utc("2026-01-02T03:04:05Z"))
        journal.defaultTemplateID = uuid(templateID)
        let template = JournalItem(
            id: uuid(templateID), kind: "template", title: "Weekly review",
            document: document("## What went well?\n\n## What next?\n"), date: utc("2026-02-03T04:05:06Z"))
        return [
            ConformanceRecordCase(
                name: "entry-markdown",
                note: "A current entry as the Apple app writes it: Markdown, block metadata, an image.",
                id: entryID, kind: "entry", plaintext: written(entry)),
            ConformanceRecordCase(
                name: "entry-deleted-and-archived",
                note: "In Recently Deleted, with the compatibility archive timestamp and an empty title.", id: entryID,
                kind: "entry", plaintext: written(deleted)),
            ConformanceRecordCase(
                name: "journal-with-default-template", note: "A journal: an empty document and a template reference.",
                id: journalID, kind: "journal", plaintext: written(journal)),
            ConformanceRecordCase(
                name: "template", note: "A template: no parent journal.", id: templateID, kind: "template",
                plaintext: written(template)),
        ] + markers()
    }

    private static func markers() -> [ConformanceRecordCase] {
        let at = utc("2026-10-02T10:00:00Z")
        func marker(_ id: String, _ kind: String) -> JournalItem {
            var item = JournalItem(id: uuid(id), kind: kind, date: at)
            item.deletedAt = at
            item.permanentlyDeletedAt = at
            item.permanentDeletionID = uuid(deletionID)
            return item
        }
        var restored = JournalItem(
            id: uuid(entryID), kind: "entry", journalID: uuid(journalID), title: "Kept after review",
            document: document("Restored under its own identity.\n"), date: utc("2026-09-20T12:00:00Z"))
        restored.restoredFromDeletionID = uuid(deletionID)
        return [
            ConformanceRecordCase(
                name: "marker-entry", note: "A canonical permanent-deletion marker: content-free, all dates equal.",
                id: entryID, kind: "entry", plaintext: written(marker(entryID, "entry"))),
            ConformanceRecordCase(
                name: "marker-journal", note: "The same marker for a journal.", id: journalID, kind: "journal",
                plaintext: written(marker(journalID, "journal"))),
            ConformanceRecordCase(
                name: "entry-restored-from-deletion",
                note: "An entry restored under its identity after a reviewed permanent deletion.", id: entryID,
                kind: "entry", plaintext: written(restored)),
        ]
    }

    /// Records other clients write, with the variations a reader must accept.
    private static func otherClients() -> [ConformanceRecordCase] {
        [
            ConformanceRecordCase(
                name: "entry-lowercase-ids-and-offsets",
                note:
                    "Another client: lower-case UUIDs, numeric offsets, fractional seconds, key order of its own, no metadata, optional fields null, an escaped slash and surrounding whitespace.",
                id: entryID, kind: "entry",
                plaintext:
                    #"{ "kind": "entry", "id": "3f2504e0-4f89-41d3-9a0c-0305e82c3301", "journalID": "6a0b3c1d-2e4f-4a5b-8c6d-7e8f9a0b1c2d", "title": "Café \/ plans", "date": "2026-05-20T09:00:00.9234567+01:00", "modifiedAt": "2026-05-20T08:00:00.5Z", "deletedWithJournal": false, "deletedAt": null, "archivedAt": null, "document": {"version": 2, "markdown": "Line one\r\nLine two\r\n"} }"#
            ),
            ConformanceRecordCase(
                name: "entry-legacy-blocks",
                note: "A version 1 document. It stays version 1 until its body is edited.", id: entryID, kind: "entry",
                plaintext:
                    #"{"date":"2026-09-20T12:00:00Z","deletedWithJournal":false,"document":{"blocks":[{"id":"99999999-8888-4777-8666-555555555555","kind":"heading","runs":[{"bold":false,"italic":false,"text":"A quiet day","underline":false}]},{"id":"11111111-2222-4333-8444-555555555555","kind":"paragraph","runs":[{"bold":true,"italic":false,"text":"Bold","underline":false},{"bold":false,"italic":false,"link":"https:\/\/example.com","text":" and linked","underline":false}]}],"version":1},"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","journalID":"6A0B3C1D-2E4F-4A5B-8C6D-7E8F9A0B1C2D","kind":"entry","modifiedAt":"2026-09-20T12:00:00Z","title":"Legacy"}"#
            ),
            ConformanceRecordCase(
                name: "entry-legacy-deleted-with-journal",
                note: "The legacy marker of an entry deleted together with its journal: kept as it is.", id: entryID,
                kind: "entry",
                plaintext:
                    #"{"date":"2026-09-20T12:00:00Z","deletedWithJournal":true,"document":{"markdown":"Old.\n","version":2},"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","journalID":"6A0B3C1D-2E4F-4A5B-8C6D-7E8F9A0B1C2D","kind":"entry","modifiedAt":"2026-09-20T12:00:00Z","title":"Old"}"#
            ),
        ]
    }

    /// Records this version can show but never rewrites.
    private static func readOnly() -> [ConformanceRecordCase] {
        let head =
            #"{"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","kind":"entry","journalID":"6A0B3C1D-2E4F-4A5B-8C6D-7E8F9A0B1C2D","title":"Newer client","date":"2026-10-01T08:00:00Z","modifiedAt":"2026-10-01T08:05:00Z","deletedWithJournal":false"#
        let body = #""document":{"version":2,"markdown":"Written by a newer client.\n"}"#
        return [
            ConformanceRecordCase(
                name: "future-field-in-record", note: "An unknown member of the record: shown, never rewritten.",
                id: entryID, kind: "entry", plaintext: head + #","mood":{"score":4,"tags":["calm"]},"# + body + "}"),
            ConformanceRecordCase(
                name: "future-field-in-document", note: "An unknown member of the document.", id: entryID,
                kind: "entry",
                plaintext: head
                    + #","document":{"version":2,"markdown":"Text.\n","layout":"columns"}}"#),
            ConformanceRecordCase(
                name: "future-field-in-metadata", note: "An unknown member of the document's metadata.", id: entryID,
                kind: "entry",
                plaintext: head
                    + #","document":{"version":2,"markdown":"Text.\n","metadata":{"blockIDs":[],"spellcheck":"nl"}}}"#),
            ConformanceRecordCase(
                name: "future-document-version", note: "A document version this client doesn't know.", id: entryID,
                kind: "entry",
                plaintext: head + #","document":{"version":3,"markdown":"Text.\n","tree":[]}}"#),
            ConformanceRecordCase(
                name: "markdown-document-without-markdown", note: "Version 2 without its Markdown.", id: entryID,
                kind: "entry", plaintext: head + #","document":{"version":2}}"#),
            ConformanceRecordCase(
                name: "unknown-block-kind", note: "A version 1 block of a kind this client doesn't know.", id: entryID,
                kind: "entry",
                plaintext: head
                    + #","document":{"version":1,"blocks":[{"id":"99999999-8888-4777-8666-555555555555","kind":"callout","runs":[{"text":"x"}]}]}}"#
            ),
            ConformanceRecordCase(
                name: "unknown-kind", note: "A kind this client doesn't know, such as a later record type.",
                id: entryID, kind: "habit",
                plaintext:
                    #"{"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","kind":"habit","title":"Walk","date":"2026-10-01T08:00:00Z","modifiedAt":"2026-10-01T08:05:00Z","deletedWithJournal":false,"document":{"version":2,"markdown":""}}"#
            ),
        ]
    }

    /// Records that authenticate but can't be read: kept byte for byte as unreadable, read-only records.
    private static func unreadable() -> [ConformanceRecordCase] {
        let rest =
            #""title":"Broken","date":"2026-10-01T08:00:00Z","modifiedAt":"2026-10-01T08:05:00Z","deletedWithJournal":false,"document":{"version":2,"markdown":"x"}"#
        return [
            ConformanceRecordCase(
                name: "missing-required-field", note: "No date.", id: entryID, kind: "entry",
                plaintext:
                    #"{"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","kind":"entry","title":"No date","modifiedAt":"2026-10-01T08:05:00Z","deletedWithJournal":false,"document":{"version":2,"markdown":"x"}}"#
            ),
            ConformanceRecordCase(
                name: "wrong-field-type", note: "A title that isn't a string.", id: entryID, kind: "entry",
                plaintext:
                    #"{"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","kind":"entry","title":7,"date":"2026-10-01T08:00:00Z","modifiedAt":"2026-10-01T08:05:00Z","deletedWithJournal":false,"document":{"version":2,"markdown":"x"}}"#
            ),
            ConformanceRecordCase(
                name: "id-differs-from-context", note: "The stored ID isn't the ID it is synced and sealed under.",
                id: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE", kind: "entry",
                plaintext: #"{"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","kind":"entry","#
                    + #""journalID":"6A0B3C1D-2E4F-4A5B-8C6D-7E8F9A0B1C2D","# + rest + "}"),
            ConformanceRecordCase(
                name: "kind-differs-from-context",
                note: "The stored kind isn't the kind it is synced and sealed under.",
                id: entryID, kind: "template",
                plaintext: #"{"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","kind":"entry","# + rest + "}"),
            ConformanceRecordCase(
                name: "archive-timestamp-on-journal", note: "Only entries may carry archivedAt.", id: journalID,
                kind: "journal",
                plaintext:
                    #"{"id":"6A0B3C1D-2E4F-4A5B-8C6D-7E8F9A0B1C2D","kind":"journal","title":"Broken","date":"2026-10-01T08:00:00Z","modifiedAt":"2026-10-01T08:05:00Z","deletedWithJournal":false,"archivedAt":"2026-10-01T08:00:00Z","document":{"version":2,"markdown":""}}"#
            ),
            ConformanceRecordCase(
                name: "marker-that-is-not-canonical",
                note: "Marker fields on a record that still has content: never treated as a deletion.", id: entryID,
                kind: "entry",
                plaintext:
                    #"{"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","kind":"entry","journalID":"6A0B3C1D-2E4F-4A5B-8C6D-7E8F9A0B1C2D","title":"Still here","date":"2026-10-02T10:00:00Z","modifiedAt":"2026-10-02T10:00:00Z","deletedAt":"2026-10-02T10:00:00Z","permanentlyDeletedAt":"2026-10-02T10:00:00Z","permanentDeletionID":"C0FFEE00-1111-4222-8333-444455556666","deletedWithJournal":false,"document":{"version":2,"markdown":"Text that a marker must not keep.\n"}}"#
            ),
            ConformanceRecordCase(
                name: "deletion-id-on-ordinary-record", note: "permanentDeletionID without permanentlyDeletedAt.",
                id: entryID, kind: "entry",
                plaintext: #"{"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","kind":"entry","# + rest
                    + #","permanentDeletionID":"C0FFEE00-1111-4222-8333-444455556666"}"#),
            ConformanceRecordCase(
                name: "not-json", note: "Authenticated bytes that aren't a JSON object.", id: entryID, kind: "entry",
                plaintext: "just some text"),
        ]
    }

    static let all: [ConformanceRecordCase] = appleWritten() + otherClients() + readOnly() + unreadable()
}
