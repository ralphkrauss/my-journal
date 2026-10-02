import JournalCore
import XCTest

final class EntryParentRecoveryUITests: XCTestCase {
    @MainActor func testCancelThenRestoreEntryAndJournalPreservingSiblingStatesAcrossRelaunch() async throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ParentRecovery-" + UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let fixture = try await seed(root)
        let destination = root.appendingPathComponent("destination")
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_DATA_DIR"] = destination.path
        app.launch()
        XCTAssertTrue(app.buttons["Start a Journal"].waitForExistence(timeout: 15))
        app.open(fixture.archive)
        let recovery = app.secureTextFields["Password or Recovery Key"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 10))
        recovery.tap()
        recovery.typeText(fixture.phrase + "\n")
        let restoreArchive = app.buttons["Restore Journals"]
        XCTAssertTrue(restoreArchive.waitForExistence(timeout: 15))
        try reveal(restoreArchive, app: app)
        restoreArchive.tap()
        XCTAssertTrue(app.staticTexts["Journals Restored"].waitForExistence(timeout: 15))
        app.buttons["Done"].tap()
        NavigationTestSupport.selectCollection("Recently Deleted", app: app)
        let row = app.staticTexts["A workday worth remembering"].firstMatch
        try reveal(row, app: app)
        row.tap()
        let readOnlyTitle = NavigationTestSupport.title(app)
        XCTAssertTrue(readOnlyTitle.waitForExistence(timeout: 10))
        XCTAssertEqual(readOnlyTitle.value as? String, "A workday worth remembering")
        try reveal(readOnlyTitle, app: app)
        capture(app, "Full read-only title beside preserved body")
        let restore = app.buttons["Restore…"]
        XCTAssertTrue(restore.waitForExistence(timeout: 10))
        try reveal(restore, app: app)
        capture(app, "Entry recovery requires its deleted journal")
        restore.tap()
        let commit = app.buttons["confirm-journal-lifecycle"]
        XCTAssertTrue(commit.waitForExistence(timeout: 10))
        capture(app, "Captured entry and journal restoration identity")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(restore.waitForExistence(timeout: 10))
        try reveal(restore, app: app)
        restore.tap()
        XCTAssertTrue(commit.waitForExistence(timeout: 10))
        let parentScope = app.staticTexts["To restore this entry, its journal must also be restored."]
        try reveal(parentScope, app: app)
        capture(app, "Required parent restoration explanation")
        let siblingExplanation =
            "Entries deleted with this journal will return, including entries that sync later. Other entries you deleted separately will stay in Recently Deleted."
        let siblingScope = app.staticTexts.matching(NSPredicate(format: "label == %@", siblingExplanation)).firstMatch
        // At the largest text size this paragraph is taller than the screen. Verify every third in order.
        for part in 0..<3 {
            try reveal(siblingScope, app: app, textThird: part)
            capture(app, "Other entries restoration scope, part \(part + 1)")
        }
        try reveal(commit, app: app)
        XCTAssertEqual(commit.label, "Restore")
        capture(app, "Explicit entry and parent restore action")
        commit.tap()
        let title = NavigationTestSupport.title(app)
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.value as? String, "A workday worth remembering")
        XCTAssertFalse(restore.exists)
        app.terminate()
        app.launch()
        NavigationTestSupport.openEntry("A workday worth remembering", journal: "All Entries", app: app)
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.value as? String, "A workday worth remembering")
        XCTAssertTrue((app.textViews["Entry text"].value as? String ?? "").contains("Keep this workday intact."))
        capture(app, "Restored entry after relaunch")
        app.terminate()
        let config = try JournalCoding.decoder().decode(
            Configuration.self, from: Data(contentsOf: destination.appendingPathComponent("configuration.json")))
        let store = try JournalStore(
            directory: destination.appendingPathComponent(config.storageFolder), key: fixture.key)
        addTeardownBlock { try await store.close() }
        let restored = try await store.item(fixture.entry.id)
        let journal = try await store.item(fixture.journal.id)
        let archived = try await store.item(fixture.archived.id)
        let deleted = try await store.item(fixture.deleted.id)
        XCTAssertNil(journal?.deletedAt)
        XCTAssertNil(restored?.deletedAt)
        XCTAssertEqual(restored?.document, fixture.entry.document)
        XCTAssertEqual(archived, fixture.archived)
        XCTAssertEqual(deleted, fixture.deleted)
    }

    private struct Configuration: Decodable { let storageFolder: String }
    private struct Fixture {
        let archive: URL
        let phrase: String
        let key: Data
        let journal: JournalItem
        let entry: JournalItem
        let archived: JournalItem
        let deleted: JournalItem
    }

    @MainActor private func seed(_ root: URL) async throws -> Fixture {
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let store = try JournalStore(directory: root.appendingPathComponent("source"), key: key)
        addTeardownBlock { try await store.close() }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var journal = JournalItem(kind: "journal", title: "Work", date: date)
        journal.deletedAt = date
        var entry = JournalItem(
            kind: "entry", journalID: journal.id, title: "A workday worth remembering",
            document: .plain("Keep this workday intact."), date: date)
        entry.archivedAt = date
        entry.deletedAt = date
        var archived = JournalItem(
            kind: "entry", journalID: journal.id, title: "Archived sibling", date: date.addingTimeInterval(-86_400))
        archived.archivedAt = date
        var deleted = JournalItem(
            kind: "entry", journalID: journal.id, title: "Deleted separately", date: date.addingTimeInterval(-172_800))
        deleted.deletedAt = date
        for item in [journal, entry, archived, deleted] { try await store.save(item) }
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        let archive = root.appendingPathComponent("Work.journalarchive")
        try await VaultArchive.export(store: store, recovery: recovery, key: key, to: archive)
        return Fixture(
            archive: archive, phrase: phrase, key: key, journal: journal, entry: entry, archived: archived,
            deleted: deleted)
    }

    private enum InteractionError: Error { case unreachable }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication, textThird: Int? = nil) throws {
        for _ in 0..<18 {
            let containers =
                app.scrollViews.allElementsBoundByIndex + app.collectionViews.allElementsBoundByIndex
                + app.textViews.matching(identifier: "Entry text").allElementsBoundByIndex
            let scroll =
                containers.first { container in
                    container.descendants(matching: .any).matching(NSPredicate(format: "label == %@", element.label))
                        .firstMatch.exists
                } ?? containers.last
            var viewport = scroll?.frame.intersection(app.frame) ?? app.frame
            if app.navigationBars.firstMatch.exists {
                let top = max(viewport.minY, app.navigationBars.firstMatch.frame.maxY)
                viewport = CGRect(x: viewport.minX, y: top, width: viewport.width, height: max(0, viewport.maxY - top))
            }
            viewport = viewport.insetBy(dx: 0, dy: 8)
            guard !viewport.isEmpty, !viewport.isNull else { throw InteractionError.unreachable }
            var target = element.frame
            if let textThird {
                target.size.height /= 3
                target.origin.y += CGFloat(textThird) * target.height
            }
            if element.exists, element.isHittable, viewport.contains(target) { return }
            guard scroll != nil else { throw InteractionError.unreachable }
            let shift =
                element.exists
                ? min(viewport.height / 4, max(-viewport.height / 4, viewport.midY - target.midY))
                : -viewport.height / 4
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.midY)).press(
                forDuration: 0.1,
                thenDragTo: origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.midY + shift)),
                withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        capture(app, "Unreachable recovery control")
        XCTFail("Recovery control must be fully reachable: \(element.label)")
        throw InteractionError.unreachable
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
