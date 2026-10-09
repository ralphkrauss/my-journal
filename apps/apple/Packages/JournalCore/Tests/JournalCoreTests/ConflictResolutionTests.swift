import XCTest

@testable import JournalCore

/// The rules that settle a record changed on two devices (protocol/conflicts.md): the function from two versions to an
/// outcome, with nothing read from a clock or a database.
final class ConflictResolutionTests: ConflictTestCase {
    private let ids = ConflictCopyIdentity(vaultKey: Data((0..<32).map { UInt8($0) }))

    private func resolve(_ local: JournalItem, _ other: JournalItem) throws -> ConflictOutcome {
        ConflictResolution.resolve(local: try side(local), other: try side(other), ids: ids)
    }

    // MARK: Row 1 and equality

    func testAVersionThisAppCannotReadIsHeld() throws {
        let readable = journal("Work")
        var newer = readable
        newer.document.version = 999
        newer.preservedJSON = Data("{}".utf8)
        XCTAssertEqual(try resolve(readable, newer), .held)
        XCTAssertEqual(try resolve(newer, readable), .held)
        var unsupported = entry("Notes", text: "a")
        unsupported.document.version = 999
        XCTAssertEqual(try resolve(entry("Notes", text: "a"), unsupported), .held)
    }

    func testEveryFieldOfTheContentAloneMakesVersionsDifferent() throws {
        let base = entry("Notes", text: "same", journal: UUID())
        func differs(_ change: (inout JournalItem) -> Void) throws -> Bool {
            var other = base
            change(&other)
            if case .sameContent = try resolve(base, other) { return false }
            return true
        }
        XCTAssertTrue(try differs { $0.title = "Other" })
        XCTAssertTrue(try differs { $0.document = .plain("changed") })
        XCTAssertTrue(try differs { $0.date = Date(timeIntervalSince1970: 1_700_000_100) })
        XCTAssertTrue(try differs { $0.journalID = UUID() })
        XCTAssertTrue(try differs { $0.archivedAt = Date(timeIntervalSince1970: 1_700_000_200) })
        // The modified time is informational, and the restoration marker is bookkeeping.
        XCTAssertFalse(try differs { $0.modifiedAt = Date(timeIntervalSince1970: 1_700_000_300) })
        XCTAssertFalse(try differs { $0.restoredFromDeletionID = UUID() })
        var template = JournalItem(kind: "template", title: "Weekly", document: .plain("a"))
        template.modifiedAt = template.date
        var changed = template
        changed.title = "Weekly, edited"
        XCTAssertEqual(try resolve(template, changed), .review)
        var journals = journal("Work")
        var withTemplate = journals
        withTemplate.defaultTemplateID = UUID()
        guard case .journal = try resolve(journals, withTemplate) else { return XCTFail("The template is content") }
        journals.defaultTemplateID = withTemplate.defaultTemplateID
        XCTAssertEqual(try resolve(journals, withTemplate), .sameContent(record: journals, adoptsOther: true))
    }

    /// The identity of a block, the length of a segment and the type of an image are in the stored document. A false
    /// "same" would lose an edit and a false "different" only makes a copy, so each of them alone is different.
    func testDocumentsThatDifferOnlyInTheirMetadataAreDifferent() throws {
        let base = entry("Notes", text: "same")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: PortableRecord.encode(base)) as? [String: Any])
        let document = try XCTUnwrap(object["document"] as? [String: Any])
        let metadata = try XCTUnwrap(document["metadata"] as? [String: Any])
        let alterations: [String: Any] = [
            "blockIDs": [UUID().uuidString.lowercased()], "segmentLengths": [999],
            "imageTypes": ["01234567-89ab-4cde-8fab-0123456789ab": "image/png"],
        ]
        for (member, value) in alterations {
            var alteredMetadata = metadata
            alteredMetadata[member] = value
            var alteredDocument = document
            alteredDocument["metadata"] = alteredMetadata
            var alteredRecord = object
            alteredRecord["document"] = alteredDocument
            let changed = try JSONSerialization.data(withJSONObject: alteredRecord, options: .sortedKeys)
            let other = ConflictSide(plaintext: changed, id: base.id, kind: "entry")
            let outcome = ConflictResolution.resolve(local: try side(base), other: other, ids: ids)
            XCTAssertEqual(outcome, .review, "\(member) alone is a difference")
        }
    }

    func testContentIsComparedAsDecodedValuesNotBytes() throws {
        let base = entry("Notes", text: "same")
        let plaintext = try PortableRecord.encode(base)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: plaintext) as? [String: Any])
        // Another client writes the same members in another order, with white space.
        let reordered = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
        XCTAssertNotEqual(reordered, plaintext)
        let other = ConflictSide(plaintext: reordered, id: base.id, kind: "entry")
        let outcome = ConflictResolution.resolve(local: try side(base), other: other, ids: ids)
        guard case .sameContent(_, let adoptsOther) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(adoptsOther)
    }

    // MARK: Deletion state (row 2)

    func testDeletedOnOneDeviceAndUntouchedOnTheOtherIsNotAConflict() throws {
        let live = entry("Notes", text: "same")
        var deleted = live
        deleted.deletedAt = Date(timeIntervalSince1970: 1_750_000_000)
        deleted.modifiedAt = Date(timeIntervalSince1970: 1_750_000_000)
        // This device deleted it: the other device's untouched version is replaced, and this one is sent.
        guard case .sameContent(let record, let adopts) = try resolve(deleted, live) else { return XCTFail() }
        XCTAssertEqual(record.deletedAt, deleted.deletedAt)
        XCTAssertFalse(adopts)
        // The other device deleted it: its bytes are the record and nothing is sent.
        guard case .sameContent(let theirs, let adoptsTheirs) = try resolve(live, deleted) else { return XCTFail() }
        XCTAssertEqual(theirs.deletedAt, deleted.deletedAt)
        XCTAssertTrue(adoptsTheirs)
    }

    func testRestoreAgainstDeleteStaysDeleted() throws {
        let live = entry("Notes", text: "same")
        var deleted = live
        deleted.deletedAt = Date(timeIntervalSince1970: 1_750_000_000)
        var restored = deleted
        restored.deletedAt = nil
        restored.modifiedAt = Date(timeIntervalSince1970: 1_760_000_000)
        guard case .sameContent(let record, _) = try resolve(restored, deleted) else { return XCTFail() }
        XCTAssertEqual(record.deletedAt, deleted.deletedAt)
    }

    func testDeletionStateIsOneUnitAndIsNeverChosenByAClock() throws {
        let live = entry("Notes", text: "same")
        var legacy = live
        legacy.deletedAt = Date(timeIntervalSince1970: 1_900_000_000)
        legacy.deletedWithJournal = true
        // Live against deleted with its journal gives a deleted-with-journal entry, not a live flag with a date.
        guard case .sameContent(let record, _) = try resolve(live, legacy) else { return XCTFail() }
        XCTAssertEqual(record.deletedAt, legacy.deletedAt)
        XCTAssertTrue(record.deletedWithJournal)
        // Both deleted: the one deleted with its journal wins whichever is later; otherwise the other version's.
        var independent = live
        independent.deletedAt = Date(timeIntervalSince1970: 1_600_000_000)
        guard case .sameContent(let first, _) = try resolve(independent, legacy) else { return XCTFail() }
        XCTAssertTrue(first.deletedWithJournal)
        guard case .sameContent(let second, _) = try resolve(legacy, independent) else { return XCTFail() }
        XCTAssertTrue(second.deletedWithJournal)
        var later = independent
        later.deletedAt = Date(timeIntervalSince1970: 1_800_000_000)
        guard case .sameContent(let third, _) = try resolve(independent, later) else { return XCTFail() }
        XCTAssertEqual(third.deletedAt, later.deletedAt, "The other version's pair, whatever the times")
    }

    // MARK: Permanent deletion (rows 4, 5 and 7)

    func testAnEditAgainstAPermanentDeletionIsParkedAndTheMarkerIsTheRecord() throws {
        let edited = entry("Draft", text: "kept words", journal: UUID())
        let marker = marker(for: edited)
        for markerIsLocal in [true, false] {
            let outcome =
                markerIsLocal ? try resolve(marker, edited) : try resolve(edited, marker)
            guard case .parked(let parked, let local) = outcome else { return XCTFail("\(outcome)") }
            XCTAssertEqual(local, markerIsLocal)
            XCTAssertNotEqual(parked.id, edited.id)
            XCTAssertEqual(parked.title, "Draft", "Not a version of anything: the title is unchanged")
            XCTAssertEqual(parked.document.text, "kept words")
            XCTAssertEqual(parked.date, edited.date)
            XCTAssertEqual(parked.journalID, edited.journalID)
            XCTAssertEqual(parked.deletedAt, marker.permanentlyDeletedAt)
            XCTAssertFalse(parked.deletedWithJournal)
            XCTAssertNil(parked.restoredFromDeletionID)
            XCTAssertFalse(parked.isPermanentlyDeleted)
        }
    }

    func testEveryDeviceMakesTheSameParkedEntryFromTheSameEditedVersion() throws {
        let edited = entry("Draft", text: "kept words")
        let marker = marker(for: edited)
        guard case .parked(let here, _) = try resolve(edited, marker),
            case .parked(let there, _) = ConflictResolution.resolve(
                local: try side(marker), other: try side(edited), ids: ids)
        else { return XCTFail() }
        XCTAssertEqual(here.id, there.id, "From this device's version or from the server's, the same record")
        var changed = edited
        changed.document = .plain("kept words, and more")
        guard case .parked(let another, _) = try resolve(changed, marker) else { return XCTFail() }
        XCTAssertNotEqual(another.id, here.id)
        // A key from another library gives other identities, so a server can't link a parked entry to its source.
        let foreign = ConflictCopyIdentity(vaultKey: Data(repeating: 9, count: 32))
        guard
            case .parked(let foreignParked, _) = ConflictResolution.resolve(
                local: try side(edited), other: try side(marker), ids: foreign)
        else { return XCTFail() }
        XCTAssertNotEqual(foreignParked.id, here.id)
    }

    func testAParkedEntryAndACopyOfTheSameVersionNeverShareAnIdentity() throws {
        let text = try PortableRecord.encode(entry("Draft", text: "kept words"))
        let record = UUID()
        XCTAssertNotEqual(
            ids.copyID(.park, record: record, plaintext: text), ids.copyID(.copy, record: record, plaintext: text))
    }

    func testTwoPermanentDeletionsKeepTheOtherOne() throws {
        let item = entry("Draft", text: "x")
        let first = marker(for: item)
        let second = JournalItem.permanentDeletionMarker(for: item, at: first.date)
        XCTAssertEqual(try resolve(first, second), .twoMarkers)
    }

    func testAJournalAgainstAPermanentDeletionCreatesNothing() throws {
        let named = journal("Work")
        let marker = marker(for: named)
        XCTAssertEqual(try resolve(named, marker), .journalMarker(markerIsLocal: false, name: "Work"))
        XCTAssertEqual(try resolve(marker, named), .journalMarker(markerIsLocal: true, name: "Work"))
    }

    // MARK: Journals (row 6) and entries that differ (row 3)

    func testAJournalRenamedOnTwoDevicesKeepsThisDevicesNameAndNotesTheOther() throws {
        let local = journal("Alpha")
        var other = local
        other.title = "Beta"
        guard case .journal(let record, let otherName) = try resolve(local, other) else { return XCTFail() }
        XCTAssertEqual(record, local)
        XCTAssertEqual(otherName, "Beta")
        // Equal names with different templates: this device's template, without a note.
        var withTemplate = local
        withTemplate.defaultTemplateID = UUID()
        guard case .journal(let kept, let note) = try resolve(local, withTemplate) else { return XCTFail() }
        XCTAssertNil(kept.defaultTemplateID)
        XCTAssertNil(note)
    }

    func testRenamedOnOneDeviceAndDeletedOnTheOtherIsDeletedWithThisDevicesName() throws {
        let local = journal("Alpha")
        var deleted = local
        deleted.title = "Beta"
        deleted.deletedAt = Date(timeIntervalSince1970: 1_750_000_000)
        guard case .journal(let record, _) = try resolve(local, deleted) else { return XCTFail() }
        XCTAssertEqual(record.title, "Alpha")
        XCTAssertEqual(record.deletedAt, deleted.deletedAt)
    }

    func testEntriesAndTemplatesThatDifferStayForReviewUntilTheyAreSettledToo() throws {
        XCTAssertEqual(try resolve(entry("A", text: "one"), entry("A", text: "two")), .review)
    }
}
