import JournalCore
import XCTest

final class PopulatedJournalMeasurement: XCTestCase {
    @MainActor func testPopulatedLaunchAndBodySearch() async throws {
        continueAfterFailure = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Measure-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let phrase = try await seed(directory)
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_DATA_DIR"] = directory.path
        defer { app.terminate() }
        app.launch()
        XCTAssertTrue(app.secureTextFields["Recovery Key"].waitForExistence(timeout: 30))
        let recovery = app.secureTextFields["Recovery Key"]
        recovery.tap()
        recovery.typeText(phrase)
        app.buttons["Unlock"].tap()
        let title = app.textViews["Entry title"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        var observations: [[String: Double]] = []
        for iteration in 0..<3 {
            app.terminate()
            let launchStart = ContinuousClock.now
            app.launch()
            XCTAssertTrue(title.waitForExistence(timeout: 30))
            XCTAssertEqual(title.value as? String, "Day 3649")
            let launchSeconds = seconds(since: launchStart)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            let search = app.searchFields.firstMatch
            if !search.isHittable { app.swipeDown() }
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            search.tap()
            let searchStart = ContinuousClock.now
            search.typeText("Orchid")
            let result = app.staticTexts["Milestone"].firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 30))
            let searchSeconds = seconds(since: searchStart)
            XCTAssertFalse(app.staticTexts["Day 3649"].exists)
            result.tap()
            XCTAssertTrue(title.waitForExistence(timeout: 10))
            XCTAssertEqual(title.value as? String, "Milestone")
            XCTAssertTrue((app.textViews["Entry text"].value as? String ?? "").contains("Orchid"))
            observations.append(["launch_to_title_seconds": launchSeconds, "query_to_result_seconds": searchSeconds])
            if iteration == 0 {
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "Populated journal body search result"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }
            app.terminate()
            // Restore the same initial entry for comparable launches without changing stored content.
            let configURL = directory.appendingPathComponent("configuration.json")
            var config = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any])
            config["lastEntryID"] = initialEntryID.uuidString
            try JSONSerialization.data(withJSONObject: config).write(to: configURL, options: .atomic)
        }
        let report: [String: Any] = [
            "entries": 3650, "text_bytes_per_entry_approximate": 4200, "attachments": 0,
            "observations": observations,
            "limits":
                "Release iOS simulator on development Mac; warm filesystem; durations include XCTest launch, typing and accessibility synchronization. No memory, minimum-hardware or physical-device guarantee.",
        ]
        let attachment = XCTAttachment(
            data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
            uniformTypeIdentifier: "public.json")
        attachment.name = "native-populated-measurement.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private let initialEntryID = UUID()

    private func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now).components
        return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }

    @MainActor private func seed(_ directory: URL) async throws -> String {
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let envelope = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        let store = try JournalStore(directory: directory, key: key)
        let journal = JournalItem(kind: "journal", title: "Daily notes")
        try await store.save(journal)
        let body = String(repeating: "A synthetic daily reflection for a populated journal. ", count: 80)
        for index in 0..<3650 {
            var item = JournalItem(
                kind: "entry", journalID: journal.id, title: index == 1800 ? "Milestone" : "Day \(index)",
                document: .plain(body + (index == 1800 ? "Orchid" : "")))
            if index == 3649 { item.id = initialEntryID }
            item.date = Date(timeIntervalSince1970: 1_500_000_000 + Double(index) * 86400)
            try await store.save(item)
        }
        try await store.close()
        let configuration = Configuration(
            recovery: envelope, lastJournalID: journal.id, lastEntryID: initialEntryID)
        try JournalCoding.encoder().encode(configuration).write(
            to: directory.appendingPathComponent("configuration.json"))
        return phrase
    }

    private struct Configuration: Encodable {
        let recovery: RecoveryEnvelope
        let recoveryConfirmed = true
        let useBiometrics = false
        let lastJournalID: UUID
        let lastEntryID: UUID
    }
}
