import JournalCore
import UIKit
import XCTest

final class DeletionConflictUITests: XCTestCase {
    @MainActor func testCancelThenKeepDeletionRemovesEditedConflictAndHistoryAcrossRelaunch() async throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("KeepDeletion-" + UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let fixture = try await seed(root)
        let destination = root.appendingPathComponent("destination")
        let app = try restoreArchive(fixture.archive, phrase: fixture.phrase, destination: destination)
        NavigationTestSupport.openSettings(app)
        app.buttons["Sync"].firstMatch.tap()
        let review = app.buttons["Review Changes for An offline reflection"]
        XCTAssertTrue(review.waitToAppear(timeout: 10))
        try reveal(review, in: app)
        review.tap()
        let keepDeletion = app.buttons["Keep Deletion…"]
        XCTAssertTrue(keepDeletion.waitToAppear(timeout: 10))
        try reveal(keepDeletion, in: app)
        capture(app, "Keep deletion is an explicit conflict choice")
        keepDeletion.tap()
        let delete = app.buttons["Delete Permanently"]
        XCTAssertTrue(delete.waitToAppear(timeout: 10))
        capture(app, "Edited entry destructive confirmation identity")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(keepDeletion.waitToAppear(timeout: 10))
        XCTAssertTrue(app.buttons["Keep Entry…"].exists)
        try reveal(keepDeletion, in: app)
        keepDeletion.tap()
        XCTAssertTrue(delete.waitToAppear(timeout: 10))
        let confirmation = app.scrollViews.containing(.button, identifier: "Delete Permanently").firstMatch
        let identity = confirmation.staticTexts["An offline reflection"]
        try reveal(identity, in: app, container: confirmation)
        capture(app, "Captured edited entry before deletion")
        let explanation = confirmation.staticTexts[
            "Removes this edited version and its earlier versions from My Journal."]
        try reveal(explanation, in: app, container: confirmation)
        capture(app, "Edited version and history deletion scope")
        for notice in [
            "This deletion will sync to your other connected devices.",
            "Copies may remain in archives, backups, and server history.", "You can’t undo this.",
        ] {
            try reveal(confirmation.staticTexts[notice], in: app, container: confirmation)
            capture(app, notice)
        }
        try reveal(delete, in: app, container: confirmation)
        capture(app, "Explicit permanent conflict deletion action")
        delete.tap()
        XCTAssertTrue(delete.waitToDisappear(timeout: 10))
        XCTAssertTrue(review.waitToDisappear(timeout: 10))
        app.terminate()
        app.launch()
        NavigationTestSupport.showJournals(app)
        NavigationTestSupport.openSettings(app)
        app.buttons["Sync"].firstMatch.tap()
        XCTAssertFalse(review.exists)
        capture(app, "Resolved deletion conflict stays resolved after relaunch")
        app.terminate()
        let config = try JournalCoding.decoder().decode(
            Configuration.self, from: Data(contentsOf: destination.appendingPathComponent("configuration.json")))
        let store = try JournalStore(
            directory: destination.appendingPathComponent(config.storageFolder), key: fixture.key)
        addTeardownBlock { try await store.close() }
        let marker = try await store.item(fixture.entry.id)
        XCTAssertEqual(marker?.isPermanentlyDeleted, true)
        XCTAssertEqual(marker?.document.text, "")
        let history = try await store.history(for: fixture.entry.id)
        let conflicts = try await store.conflicts()
        let items = try await store.items()
        XCTAssertTrue(history.isEmpty)
        XCTAssertTrue(conflicts.isEmpty)
        XCTAssertFalse(items.contains { $0.kind == "entry" && !$0.isPermanentlyDeleted })
        let image = try await store.attachment(fixture.imageID)
        XCTAssertEqual(image, fixture.image)
    }

    @MainActor func testTwoDeletionMarkersCancelThenExplicitlyPurgeHistory() async throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TwoMarkers-" + UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let fixture = try await seed(root, twoMarkers: true)
        let destination = root.appendingPathComponent("destination")
        let app = try restoreArchive(fixture.archive, phrase: fixture.phrase, destination: destination)
        defer { app.terminate() }
        for committing in [false, true] {
            NavigationTestSupport.openSettings(app)
            app.buttons["Sync"].firstMatch.tap()
            let review = app.buttons["Review Changes for Deleted Entry"]
            XCTAssertTrue(review.waitToAppear(timeout: 10))
            try reveal(review, in: app)
            review.tap()
            let explanation = app.staticTexts["Both versions show this entry as deleted."]
            XCTAssertTrue(explanation.waitToAppear(timeout: 10))
            try reveal(explanation, in: app)
            capture(app, "Both deletion versions agree")
            XCTAssertFalse(app.buttons["Keep Entry…"].exists)
            XCTAssertFalse(app.buttons["Keep Entry as Copy…"].exists)
            let keep = app.buttons["Keep Deletion…"]
            try reveal(keep, in: app)
            keep.tap()
            let identity = app.staticTexts["Deletion to Keep"]
            XCTAssertTrue(identity.waitToAppear(timeout: 10))
            try reveal(identity, in: app)
            capture(app, "Captured deletion event in second confirmation")
            let scope = app.staticTexts[
                "Any remaining earlier versions will be removed from My Journal on this device."]
            try reveal(scope, in: app)
            capture(app, "Two-marker history removal scope")
            if committing {
                let delete = app.buttons["Delete Permanently"]
                try reveal(delete, in: app)
                capture(app, "Explicit two-marker history purge")
                delete.tap()
                XCTAssertTrue(review.waitToDisappear(timeout: 10))
            } else {
                app.buttons["Cancel"].firstMatch.tap()
                XCTAssertTrue(keep.waitToAppear(timeout: 10))
            }
            app.terminate()
            let config = try JournalCoding.decoder().decode(
                Configuration.self, from: Data(contentsOf: destination.appendingPathComponent("configuration.json")))
            let store = try JournalStore(
                directory: destination.appendingPathComponent(config.storageFolder), key: fixture.key)
            let history = try await store.history(for: fixture.entry.id)
            let conflicts = try await store.conflicts()
            let marker = try await store.item(fixture.entry.id)
            XCTAssertEqual(marker?.isPermanentlyDeleted, true)
            XCTAssertEqual(history.isEmpty, committing)
            XCTAssertEqual(conflicts.isEmpty, committing)
            try await store.close()
            app.launch()
            NavigationTestSupport.showJournals(app)
        }
        NavigationTestSupport.openSettings(app)
        app.buttons["Sync"].firstMatch.tap()
        XCTAssertFalse(app.buttons["Review Changes for Deleted Entry"].exists)
        capture(app, "Two-marker resolution after relaunch")
    }

    @MainActor func testHiddenDeletionConflictKeepsCopyInChosenJournalAcrossRelaunch() async throws {
        try await recoverEntry(asCopy: true)
    }

    @MainActor func testKeepEntryPreservesIdentityInChosenJournalAcrossRelaunch() async throws {
        try await recoverEntry(asCopy: false)
    }

    @MainActor private func recoverEntry(asCopy: Bool) async throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DeletionConflict-" + UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let fixture = try await seed(root)
        let destination = root.appendingPathComponent("destination")
        let app = try restoreArchive(fixture.archive, phrase: fixture.phrase, destination: destination)
        NavigationTestSupport.openSettings(app)
        app.buttons["Sync"].firstMatch.tap()
        let review = app.buttons["Review Changes for An offline reflection"]
        XCTAssertTrue(review.waitToAppear(timeout: 10))
        try reveal(review, in: app)
        capture(app, "Hidden deletion conflict in Sync settings")
        review.tap()
        let copy = app.buttons[asCopy ? "Keep Entry as Copy…" : "Keep Entry…"]
        XCTAssertTrue(copy.waitToAppear(timeout: 10))
        capture(app, "Deletion conflict version metadata")
        let preview = app.textViews["Entry text"]
        try reveal(preview, in: app)
        XCTAssertTrue((preview.value as? String ?? "").contains("Keep every word from the offline edit."))
        capture(app, "Deletion conflict edited text")
        preview.swipeUp()
        capture(app, "Deletion conflict edited image")
        let retention = app.staticTexts[
            asCopy
                ? "Creates a new entry and keeps the original deleted. Any remaining earlier versions stay available in archive exports."
                : "Keeps the edited entry. Earlier versions already deleted aren’t restored."
        ]
        try reveal(retention, in: app)
        capture(app, "Complete recovery history-retention explanation")
        try reveal(copy, in: app)
        capture(app, "Explicit deletion conflict choices")
        copy.tap()
        let journal = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Work", "2024")
        )
        .firstMatch
        try reveal(journal, in: app)
        XCTAssertTrue(journal.isEnabled)
        capture(app, "Duplicate journal recovery destinations")
        journal.tap()
        let keep = app.buttons[asCopy ? "Keep Entry as Copy" : "Keep Entry"]
        try reveal(keep, in: app)
        capture(app, "Chosen recovery destination")
        keep.tap()
        XCTAssertTrue(copy.waitToDisappear(timeout: 10))
        app.terminate()
        app.launch()
        NavigationTestSupport.openEntry("An offline reflection", journal: "All Entries", app: app)
        let title = NavigationTestSupport.title(app)
        XCTAssertTrue(title.waitToAppear(timeout: 15))
        assertEventually(title.value as? String, equals: "An offline reflection")
        XCTAssertTrue(
            (app.textViews["Entry text"].value as? String ?? "").contains("Keep every word from the offline edit."))
        capture(app, "Recovered entry after relaunch")
        app.terminate()
        let config = try JournalCoding.decoder().decode(
            Configuration.self, from: Data(contentsOf: destination.appendingPathComponent("configuration.json")))
        let store = try JournalStore(
            directory: destination.appendingPathComponent(config.storageFolder), key: fixture.key)
        addTeardownBlock { try await store.close() }
        let original = try await store.item(fixture.entry.id)
        XCTAssertEqual(original?.isPermanentlyDeleted, asCopy)
        let items = try await store.items()
        let copies = items.filter { $0.kind == "entry" && !$0.isPermanentlyDeleted }
        XCTAssertEqual(copies.count, 1)
        let saved = try XCTUnwrap(copies.first)
        if asCopy {
            XCTAssertNotEqual(saved.id, fixture.entry.id)
        } else {
            XCTAssertEqual(saved.id, fixture.entry.id)
            XCTAssertNotNil(saved.restoredFromDeletionID)
        }
        XCTAssertEqual(saved.journalID, fixture.destination.id)
        XCTAssertEqual(saved.document, fixture.entry.document)
        XCTAssertEqual(saved.date, fixture.entry.date)
        let history = try await store.history(for: fixture.entry.id)
        XCTAssertEqual(history.count, 1)
        let conflicts = try await store.conflicts()
        XCTAssertTrue(conflicts.isEmpty)
        let image = try await store.attachment(fixture.imageID)
        XCTAssertEqual(image, fixture.image)
    }

    @MainActor func testKeepJournalPreservesSettingsWithoutRevivingDeletedChildren() async throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("KeepJournal-" + UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let fixture = try await seedJournal(root)
        let destination = root.appendingPathComponent("destination")
        let app = try restoreArchive(fixture.archive, phrase: fixture.phrase, destination: destination)
        NavigationTestSupport.openSettings(app)
        app.buttons["Sync"].firstMatch.tap()
        let review = app.buttons["Review Changes for Work reflections"]
        XCTAssertTrue(review.waitToAppear(timeout: 10))
        try reveal(review, in: app)
        review.tap()
        let keep = app.buttons["Keep Journal"]
        XCTAssertTrue(keep.waitToAppear(timeout: 10))
        let name = app.staticTexts["Work reflections"].firstMatch
        try reveal(name, in: app)
        capture(app, "Journal conflict edited name")
        let template = app.staticTexts["Daily review"].firstMatch
        try reveal(template, in: app)
        capture(app, "Journal conflict default template")
        let scope = app.staticTexts["Keeps this journal’s name and template. Deleted entries aren’t restored."]
        try reveal(scope, in: app)
        capture(app, "Keep journal does not restore deleted entries")
        try reveal(keep, in: app)
        capture(app, "Explicit Keep Journal choice")
        keep.tap()
        XCTAssertTrue(keep.waitToDisappear(timeout: 10))
        XCTAssertTrue(review.waitToDisappear(timeout: 10))
        app.terminate()
        app.launch()
        NavigationTestSupport.showJournals(app)
        NavigationTestSupport.openSettings(app)
        app.buttons["Sync"].firstMatch.tap()
        XCTAssertFalse(review.exists)
        capture(app, "Journal conflict remains resolved after relaunch")
        app.terminate()
        let config = try JournalCoding.decoder().decode(
            Configuration.self, from: Data(contentsOf: destination.appendingPathComponent("configuration.json")))
        let store = try JournalStore(
            directory: destination.appendingPathComponent(config.storageFolder), key: fixture.key)
        addTeardownBlock { try await store.close() }
        let storedJournal = try await store.item(fixture.journal.id)
        let journal = try XCTUnwrap(storedJournal)
        XCTAssertEqual(journal.id, fixture.journal.id)
        XCTAssertEqual(journal.title, fixture.journal.title)
        XCTAssertEqual(journal.defaultTemplateID, fixture.journal.defaultTemplateID)
        XCTAssertEqual(journal.restoredFromDeletionID, fixture.deletionID)
        XCTAssertFalse(journal.isPermanentlyDeleted)
        let child = try await store.item(fixture.child.id)
        XCTAssertEqual(child, fixture.child)
        let items = try await store.items()
        XCTAssertFalse(items.contains { $0.kind == "entry" && !$0.isPermanentlyDeleted })
        let conflicts = try await store.conflicts()
        XCTAssertTrue(conflicts.isEmpty)
    }

    private struct JournalFixture {
        let archive: URL
        let phrase: String
        let key: Data
        let journal: JournalItem
        let child: JournalItem
        let deletionID: UUID
    }
    @MainActor private func seedJournal(_ root: URL) async throws -> JournalFixture {
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let store = try JournalStore(directory: root.appendingPathComponent("source"), key: key)
        addTeardownBlock { try await store.close() }
        let template = JournalItem(kind: "template", title: "Daily review", document: .plain("What did I learn?"))
        var journal = JournalItem(kind: "journal", title: "Work reflections")
        journal.defaultTemplateID = template.id
        let child = JournalItem(kind: "entry", journalID: journal.id, title: "Deleted workday")
        try await store.save(template)
        try await store.save(JournalItem(kind: "journal", title: "Personal"))
        try await store.save(child)
        journal.deletedAt = Date()
        try await store.save(journal)
        let deletion = try await store.preparePermanentDeletion(journal.id)
        let marker = try await store.permanentlyDelete(deletion)
        let storedChild = try await store.item(child.id)
        let deletedChild = try XCTUnwrap(storedChild)
        journal.deletedAt = nil
        let payload = try VaultCrypto.seal(
            PortableRecord.encode(journal), key: key,
            context: VaultCrypto.recordContext(id: journal.id, kind: journal.kind))
        try await store.apply(
            [
                RemoteChange(
                    cursor: 4, recordId: journal.id, revision: 4, kind: journal.kind,
                    payload: payload.base64EncodedString(), deviceId: UUID(), modifiedAt: journal.modifiedAt)
            ], cursor: 4)
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        let archive = root.appendingPathComponent("JournalConflict.journalarchive")
        try await VaultArchive.export(store: store, recovery: recovery, key: key, to: archive)
        return JournalFixture(
            archive: archive, phrase: phrase, key: key, journal: journal,
            child: deletedChild, deletionID: try XCTUnwrap(marker.permanentDeletionID))
    }

    @MainActor private func restoreArchive(_ archive: URL, phrase: String, destination: URL) throws
        -> XCUIApplication
    {
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_DATA_DIR"] = destination.path
        app.launch()
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 15))
        app.open(archive)
        let recovery = app.secureTextFields["Password or Recovery Key"]
        XCTAssertTrue(recovery.waitToAppear(timeout: 10))
        recovery.tap()
        recovery.typeText(phrase + "\n")
        let restore = app.buttons["Restore Journals"]
        XCTAssertTrue(restore.waitToAppear(timeout: 15))
        try reveal(restore, in: app)
        restore.tap()
        XCTAssertTrue(app.staticTexts["Journals Restored"].waitToAppear(timeout: 15))
        app.buttons["Done"].tap()
        return app
    }

    private struct Configuration: Decodable { let storageFolder: String }
    private struct Fixture {
        let archive: URL
        let phrase: String
        let key: Data
        let entry: JournalItem
        let destination: JournalItem
        let imageID: UUID
        let image: Data
    }
    @MainActor private func seed(_ root: URL, twoMarkers: Bool = false) async throws -> Fixture {
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let store = try JournalStore(directory: root.appendingPathComponent("source"), key: key)
        addTeardownBlock { try await store.close() }
        let first = JournalItem(kind: "journal", title: "Work", date: Date(timeIntervalSince1970: 1_672_531_200))
        let destination = JournalItem(kind: "journal", title: "Work", date: Date(timeIntervalSince1970: 1_704_067_200))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80)).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }
        let imageID = try await store.addAttachment(image)
        var entry = JournalItem(
            kind: "entry", journalID: first.id, title: "An offline reflection",
            document: JournalDocument(blocks: [
                DocumentBlock(runs: [TextRun("Keep every word from the offline edit.", bold: true)]),
                DocumentBlock(
                    kind: "image", attachmentID: imageID, imageDescription: "Blue sketch", mediaType: "image/png"),
            ]), date: Date(timeIntervalSince1970: 1_700_000_000))
        try await store.save(first)
        // Two journals share a name only when they meet through sync, as when two devices each created "Work".
        let journalPayload = try VaultCrypto.seal(
            PortableRecord.encode(destination), key: key,
            context: VaultCrypto.recordContext(id: destination.id, kind: destination.kind))
        try await store.apply(
            [
                RemoteChange(
                    cursor: 3, recordId: destination.id, revision: 1, kind: destination.kind,
                    payload: journalPayload.base64EncodedString(), deviceId: UUID(),
                    modifiedAt: destination.modifiedAt)
            ], cursor: 3)
        entry.deletedAt = entry.date
        try await store.save(entry)
        let confirmation = try await store.preparePermanentDeletion(entry.id)
        try await store.permanentlyDelete(confirmation)
        entry.deletedAt = nil
        var earlier = entry
        earlier.title = "Earlier offline edit"
        let deviceID = UUID()
        for (item, revision) in [(earlier, Int64(4)), (entry, Int64(5))] {
            let payload = try VaultCrypto.seal(
                PortableRecord.encode(item), key: key, context: VaultCrypto.recordContext(id: item.id, kind: item.kind))
            try await store.apply(
                [
                    RemoteChange(
                        cursor: revision, recordId: item.id, revision: revision, kind: item.kind,
                        payload: payload.base64EncodedString(), deviceId: deviceID, modifiedAt: item.modifiedAt)
                ], cursor: revision)
        }
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        if twoMarkers {
            let storedMarker = try await store.item(entry.id)
            var marker = try XCTUnwrap(storedMarker)
            marker.permanentDeletionID = UUID()
            marker.permanentlyDeletedAt = Date(timeIntervalSince1970: 1_800_000_000)
            marker.modifiedAt = Date(timeIntervalSince1970: 1_800_000_000)
            marker.date = marker.modifiedAt
            marker.deletedAt = marker.modifiedAt
            let payload = try VaultCrypto.seal(
                PortableRecord.encode(marker), key: key,
                context: VaultCrypto.recordContext(id: marker.id, kind: marker.kind))
            try await store.apply(
                [
                    RemoteChange(
                        cursor: 6, recordId: marker.id, revision: 6, kind: marker.kind,
                        payload: payload.base64EncodedString(), deviceId: deviceID, modifiedAt: marker.modifiedAt)
                ], cursor: 6)
            let prepared = try await store.prepareDeletionConflict(entry.id)
            XCTAssertNil(prepared.edited)
            let history = try await store.history(for: entry.id)
            XCTAssertFalse(history.isEmpty)
        }
        let archive = root.appendingPathComponent("Conflict.journalarchive")
        try await VaultArchive.export(store: store, recovery: recovery, key: key, to: archive)
        return Fixture(
            archive: archive, phrase: phrase, key: key, entry: entry, destination: destination, imageID: imageID,
            image: image)
    }
    private enum InteractionError: Error { case unreachable }
    @MainActor private func reveal(
        _ element: XCUIElement, in app: XCUIApplication, container: XCUIElement? = nil
    ) throws {
        for _ in 0..<30 {
            let scroll =
                container ?? app.scrollViews.allElementsBoundByIndex.last
                ?? app.collectionViews.allElementsBoundByIndex.last
            guard let scroll else {
                XCTFail("The conflict screen must expose its scrollable content.")
                throw InteractionError.unreachable
            }
            var viewport = scroll.frame.intersection(app.frame)
            // With sheets stacked, only the frontmost sheet's bar can be tapped; covered bars don't limit the view.
            if let bar = app.navigationBars.allElementsBoundByIndex.last(where: \.isHittable) {
                let top = max(viewport.minY, bar.frame.maxY)
                viewport = CGRect(x: viewport.minX, y: top, width: viewport.width, height: max(0, viewport.maxY - top))
            }
            let tabBar = app.tabBars.firstMatch
            if tabBar.exists, tabBar.buttons.firstMatch.isHittable {
                viewport.size.height = max(0, min(viewport.maxY, tabBar.frame.minY) - viewport.minY)
            }
            viewport = viewport.insetBy(dx: 0, dy: 12)
            guard !viewport.isNull, !viewport.isEmpty else { throw InteractionError.unreachable }
            if element.exists, element.isHittable, viewport.contains(element.frame) { return }
            let shift =
                element.exists
                ? min(viewport.height / 4, max(-viewport.height / 4, viewport.midY - element.frame.midY))
                : -viewport.height / 4
            let origin = app.coordinate(withNormalizedOffset: .zero)
            // Start within the scrollable content; padding may be outside its hit region.
            let dragX = viewport.midX
            origin.withOffset(CGVector(dx: dragX, dy: viewport.midY)).press(
                forDuration: 0,
                thenDragTo: origin.withOffset(CGVector(dx: dragX, dy: viewport.midY + shift)),
                withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        capture(app, "Unreachable conflict control")
        XCTFail("Conflict control must be reachable: \(element.exists ? element.label : "missing target")")
        throw InteractionError.unreachable
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
