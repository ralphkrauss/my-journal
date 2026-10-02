import JournalCore
import UIKit
import XCTest

final class JournalUITests: XCTestCase {
    @MainActor func testWriteAndReopenEntry() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        completeLocalSetup(app)
        let newEntry = app.buttons["New Entry"].firstMatch
        XCTAssertTrue(newEntry.waitForExistence(timeout: 10))
        NavigationTestSupport.showJournals(app)
        app.buttons["New Journal"].tap()
        let createJournal = app.alerts["New Journal"]
        createJournal.textFields["Name"].tap()
        createJournal.textFields["Name"].typeText("Work")
        createJournal.buttons["Create"].tap()
        NavigationTestSupport.selectCollection("Work", app: app)
        newEntry.tap()
        let title = NavigationTestSupport.title(app)
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText("A useful day")
        let editor = app.textViews["Entry text"]
        editor.tap()
        editor.typeText("Finished the prototype.\nA note for tomorrow.")
        XCTAssertTrue((editor.value as? String ?? "").contains("Finished the prototype."))
        // Termination immediately after typing checks durable local autosave.
        app.terminate()
        app.launch()
        NavigationTestSupport.openEntry("A useful day", journal: "All Entries", app: app)
        XCTAssertEqual(NavigationTestSupport.title(app).value as? String, "A useful day")
        XCTAssertEqual(app.textViews["Entry text"].value as? String, "Finished the prototype.\nA note for tomorrow.")
        app.buttons["Entry Actions"].firstMatch.tap()
        app.buttons["Move Entry…"].tap()
        XCTAssertTrue(app.navigationBars["Move Entry"].waitForExistence(timeout: 5))
        app.buttons["Default"].tap()
        let moveScreen = XCTAttachment(screenshot: app.screenshot())
        moveScreen.name = "Move entry destination"
        moveScreen.lifetime = .keepAlways
        add(moveScreen)
        app.buttons["Move"].tap()
        XCTAssertTrue(NavigationTestSupport.title(app).waitForExistence(timeout: 5))
        XCTAssertEqual(NavigationTestSupport.title(app).value as? String, "A useful day")
        app.terminate()
        app.launch()
        NavigationTestSupport.openEntry("A useful day", journal: "All Entries", app: app)
        XCTAssertEqual(NavigationTestSupport.title(app).value as? String, "A useful day")
        XCTAssertEqual(app.textViews["Entry text"].value as? String, "Finished the prototype.\nA note for tomorrow.")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Reopened entry"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    @MainActor func testDeleteLastJournalAndRestoreWithoutLosingEntry() {
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        completeLocalSetup(app)
        app.buttons["New Entry"].firstMatch.tap()
        let title = NavigationTestSupport.title(app)
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText("Keep this reflection")
        NavigationTestSupport.showJournals(app)
        app.staticTexts["Default"].firstMatch.press(forDuration: 1)
        app.buttons["Delete Journal…"].tap()
        let alert = app.alerts["Delete “Default”?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(alert.staticTexts["Its entry moves to Recently Deleted."].exists)
        attachScreen(app, name: "Delete last journal confirmation")
        alert.buttons["Delete"].tap()
        NavigationTestSupport.selectCollection("Recently Deleted", app: app)
        XCTAssertTrue(app.staticTexts["Keep this reflection"].waitForExistence(timeout: 5))
        attachScreen(app, name: "Deleted journal and entry")
        let trash = app.collectionViews.firstMatch
        scrollTo(app.staticTexts["Items stay here until you delete them permanently."], in: trash)
        attachScreen(app, name: "Scrolled trash retention note")
        scrollTo(app.staticTexts["Default"].firstMatch, in: trash, upwards: false)
        app.staticTexts["Default"].firstMatch.tap()
        let restore = app.buttons["Restore Journal…"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        XCTAssertTrue(app.buttons["Restore Journal"].waitForExistence(timeout: 5))
        attachScreen(app, name: "Restore journal confirmation")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        XCTAssertTrue(app.buttons["Restore Journal"].waitForExistence(timeout: 5))
        tapAfterScrolling(app.buttons["Restore Journal"], in: app.scrollViews.firstMatch)
        app.terminate()
        app.launch()
        NavigationTestSupport.openEntry("Keep this reflection", journal: "Default", app: app)
        XCTAssertEqual(title.value as? String, "Keep this reflection")
    }
    @MainActor private func tapAfterScrolling(_ element: XCUIElement, in container: XCUIElement) {
        scrollTo(element, in: container)
        attachScreen(XCUIApplication(), name: "Reachable \(element.label)")
        element.tap()
    }
    @MainActor private func scrollTo(_ element: XCUIElement, in container: XCUIElement, upwards: Bool = true) {
        // Large accessibility text can put native menu/form actions below the viewport.
        for _ in 0..<8 {
            if element.exists && element.isHittable { break }
            if upwards { container.swipeUp() } else { container.swipeDown() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "The content must be reachable by scrolling.")
    }
    @MainActor private func attachScreen(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    /// At the largest text sizes a button can be below the fold, where a list hasn't created it yet.
    @MainActor private func scrollToButton(_ label: String, below title: String, app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[label]
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
        for _ in 0..<4 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        return button
    }
    @MainActor private func completeLocalSetup(_ app: XCUIApplication) {
        let start = app.buttons["Start a Journal"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        NavigationTestSupport.createPasswordJournal(app)
    }
    @MainActor func testPairDeviceAndDownloadEncryptedEntry() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let address = environment["JOURNAL_TEST_SERVER"], address.hasPrefix("http://127.0.0.1:"),
            let setupCode = environment["JOURNAL_TEST_SETUP_CODE"], !setupCode.isEmpty
        else {
            throw XCTSkip("Run scripts/test-native-pairing.sh for the disposable-server pairing check.")
        }
        let key = try VaultCrypto.generateKey()
        let envelope = try VaultCrypto.makeRecovery(masterKey: key, phrase: "Synthetic UI fixture recovery only")
        let grant = try await ServerClient(address: address).initialize(
            code: setupCode, envelope: envelope.0, recoverySecret: envelope.1, deviceName: "Fixture Mac")
        let owner = try ServerClient(address: address, token: grant.token)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try JournalStore(directory: directory, key: key)
        let journal = JournalItem(kind: "journal", title: "Work")
        let pixel = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80)).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }
        let attachment = try await store.addAttachment(pixel)
        let entry = JournalItem(
            kind: "entry", journalID: journal.id, title: "Synced reflection",
            document: JournalDocument(blocks: [
                DocumentBlock(runs: [TextRun("Arrived privately from the other device.")]),
                DocumentBlock(
                    kind: "image", attachmentID: attachment, imageDescription: "Original image", mediaType: "image/png"),
            ]))
        try await store.save(journal)
        try await store.save(entry)
        try await SyncEngine(store: store, client: owner).synchronize()
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["Connect to a Server…"].waitForExistence(timeout: 10))
        app.buttons["Connect to a Server…"].tap()
        let field = app.textFields["Server Address"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(address)
        app.buttons["Continue"].tap()
        // Signing in with the password is the default; a code from a connected device is the alternative.
        // The fixture library uses a recovery key, so the step asks for it by that name.
        scrollToButton("Use a Connected Device Instead…", below: "Enter Recovery Key", app: app).tap()
        let codeView = app.staticTexts["pairing-code"]
        XCTAssertTrue(codeView.waitForExistence(timeout: 10))
        let code = (codeView.value as? String ?? codeView.label).filter(\.isNumber)
        XCTAssertEqual(code.count, 9)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Pairing code"

        screenshot.lifetime = .keepAlways
        add(screenshot)
        let candidate = try await owner.pairingCandidate(code: code)
        let approval = try await owner.preparePairingApproval(PairingChallenge(candidate))
        // As a person would, compare the new device's check code with the approving device's before sending the key.
        let shown = app.staticTexts["check-code"]
        XCTAssertTrue(shown.waitForExistence(timeout: 10))
        XCTAssertEqual((shown.value as? String ?? "").filter(\.isNumber), approval.checkCode)
        let check = XCTAttachment(screenshot: app.screenshot())
        check.name = "Check code on the new device"
        check.lifetime = .keepAlways
        add(check)
        try await owner.approvePairing(approval, masterKey: key)
        // Approved on the other device, but nothing is accepted here until the person confirms the codes match.
        let connect = app.buttons["Connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Connect only if your other device shows the same code."].exists)
        try await Task.sleep(nanoseconds: 3_000_000_000)
        XCTAssertTrue(shown.exists, "Nothing is installed before Connect.")
        let confirm = XCTAttachment(screenshot: app.screenshot())
        confirm.name = "Confirm the check code on the new device"
        confirm.lifetime = .keepAlways
        add(confirm)
        connect.tap()
        let title = NavigationTestSupport.title(app)
        NavigationTestSupport.openEntry("Synced reflection", journal: "All Entries", app: app)
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.value as? String, "Synced reflection")
        XCTAssertTrue(
            (app.textViews["Entry text"].value as? String ?? "").contains("Arrived privately from the other device."))
        let devices = try await owner.devices()
        XCTAssertEqual(devices.filter { !$0.revoked }.count, 2)
        // Settings ▸ Devices says how each device was added, without identifiers.
        NavigationTestSupport.openSettings(app)
        app.buttons["Devices"].tap()
        func row(_ text: String) -> XCUIElement {
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        }
        XCTAssertTrue(row("Fixture Mac").waitForExistence(timeout: 10))
        XCTAssertTrue(row("This Device").exists)
        XCTAssertFalse(row(" · ").exists, "Device identifiers appear only to tell identical rows apart.")
        let list = XCTAttachment(screenshot: app.screenshot())
        list.name = "Devices"
        list.lifetime = .keepAlways
        add(list)
        NavigationTestSupport.closeSettings(app)
        app.terminate()
        app.launch()
        NavigationTestSupport.openEntry("Synced reflection", journal: "All Entries", app: app)
        XCTAssertTrue(
            (app.textViews["Entry text"].value as? String ?? "").contains("Arrived privately from the other device."))
        try editImageDescriptionAndReopen(app)
        app.terminate()
        try await joinWithScannedCode(address: address, owner: owner, key: key)
    }
    /// A new device that scans a connected device's code joins without typing an address or comparing codes; the
    /// connected device (here the test) accepts only a request that proves it read that code.
    @MainActor private func joinWithScannedCode(address: String, owner: ServerClient, key: Data) async throws {
        let host = try XCTUnwrap(PairingInviteHost(server: address))
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["JOURNAL_TEST_SCANNED_CODE"] = host.invite.text
        app.launch()
        XCTAssertTrue(app.buttons["Connect to a Server…"].waitForExistence(timeout: 10))
        app.buttons["Connect to a Server…"].tap()
        let scan = app.buttons["Scan Code"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        scan.tap()
        XCTAssertTrue(app.staticTexts["Finish on Your Other Device"].waitForExistence(timeout: 10))
        attachScreen(app, name: "Scanned code waiting for the connected device")
        var candidate: PairingCandidate?
        for _ in 0..<30 where candidate == nil {
            candidate = try? await owner.pairingCandidate(code: host.invite.code)
            if candidate == nil { try await Task.sleep(nanoseconds: 500_000_000) }
        }
        let request = try XCTUnwrap(candidate)
        XCTAssertTrue(host.verifies(request))
        let approval = try await owner.preparePairingApproval(host.challenge(request))
        try await owner.approvePairing(approval, masterKey: key)
        NavigationTestSupport.openEntry("Synced reflection", journal: "All Entries", app: app)
        XCTAssertTrue(
            (app.textViews["Entry text"].value as? String ?? "").contains("Arrived privately from the other device."))
        XCTAssertFalse(app.staticTexts["check-code"].exists, "A scanned code needs no check code.")
        app.terminate()
    }
    @MainActor private func editImageDescriptionAndReopen(_ app: XCUIApplication) throws {
        app.buttons["Entry Actions"].firstMatch.tap()
        tapAfterScrolling(app.buttons["Image Descriptions…"], in: app.collectionViews.firstMatch)
        let field = app.descendants(matching: .any).matching(identifier: "Image 1 description").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        scrollTo(field, in: app.scrollViews.firstMatch)
        XCTAssertEqual(field.value as? String, "Original image")
        field.tap()
        field.typeText(" viewed from home")
        // Keep the gesture above the keyboard; a full-height swipe can hit predictive text.
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let input = app.otherElements["inputView"].firstMatch
        XCTAssertTrue(input.exists)
        let start = origin.withOffset(CGVector(dx: 10, dy: input.frame.minY - 30))
        let end = origin.withOffset(CGVector(dx: 10, dy: app.navigationBars.firstMatch.frame.maxY + 30))
        start.press(forDuration: 0.1, thenDragTo: end)
        field.typeText(" today")
        XCTAssertLessThan(field.frame.maxY, input.frame.minY, "The full editing field must be above the keyboard.")
        let editedDescription = try XCTUnwrap(field.value as? String)
        XCTAssertTrue(editedDescription.contains("viewed from home today"))
        attachScreen(app, name: "Edit image description")
        let layout = XCTAttachment(string: app.debugDescription)
        layout.name = "Image description keyboard layout"
        layout.lifetime = .keepAlways
        add(layout)
        app.navigationBars["Image Descriptions"].buttons["Done"].tap()
        XCTAssertTrue(NavigationTestSupport.title(app).waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        NavigationTestSupport.openEntry("Synced reflection", journal: "All Entries", app: app)
        app.buttons["Entry Actions"].firstMatch.tap()
        tapAfterScrolling(app.buttons["Image Descriptions…"], in: app.collectionViews.firstMatch)
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        scrollTo(field, in: app.scrollViews.firstMatch)
        XCTAssertEqual(field.value as? String, editedDescription)
        attachScreen(app, name: "Reopened image description")
        scrollTo(app.buttons["Copy Descriptions"], in: app.scrollViews.firstMatch)
        attachScreen(app, name: "Reachable Copy Descriptions")
        verifyDescriptionCancel(app, field: field, savedDescription: editedDescription)
    }
    @MainActor private func verifyDescriptionCancel(
        _ app: XCUIApplication, field: XCUIElement, savedDescription: String
    ) {
        scrollTo(field, in: app.scrollViews.firstMatch, upwards: false)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1)).tap()
        field.typeText("Note ")
        XCTAssertTrue((field.value as? String ?? "").contains("Note"))
        XCTAssertNotEqual(field.value as? String, savedDescription)
        attachScreen(app, name: "Edit earlier description text")
        app.buttons["Cancel"].tap()
        app.buttons["Entry Actions"].firstMatch.tap()
        tapAfterScrolling(app.buttons["Image Descriptions…"], in: app.collectionViews.firstMatch)
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String, savedDescription)
        app.buttons["Cancel"].tap()
    }

}
