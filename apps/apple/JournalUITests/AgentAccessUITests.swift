import XCTest

/// Settings ▸ Agent Access (docs/design/agent-access-simplified.md): an MCP client asks for access and its request
/// appears on its own. A wrong number declines it and sends the page back. The owner allows the next request with its
/// page's number and All Journals, changes it to one journal afterwards, and revokes it; the page then says access
/// wasn't allowed. The test plays the MCP client (which never redeems its code) against the disposable server
/// scripts/test-native-pairing.sh starts.
final class AgentAccessUITests: XCTestCase {
    @MainActor func testAllowAgentByNumberThenChangeJournalsAndRevoke() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let address = environment["JOURNAL_TEST_AGENT_SERVER"], address.hasPrefix("http://127.0.0.1:"),
            let setupCode = environment["JOURNAL_TEST_AGENT_CODE"], !setupCode.isEmpty
        else {
            throw XCTSkip("Run scripts/test-native-pairing.sh for the disposable-server agent check.")
        }
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        setUpServerWithoutEncryption(address: address, code: setupCode, app: app)

        NavigationTestSupport.openSettings(app)
        app.buttons["Agent Access"].tap()
        let mcpAddress = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "\(address)/mcp")).firstMatch
        XCTAssertTrue(mcpAddress.waitToAppear(timeout: 15))
        attachScreen(app, name: "Agent Access, no agents")

        // The request appears without the owner doing anything; a wrong number declines it.
        let declined = try await AuthorizationClient.start(server: address)
        let request = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "UI Test Agent, returns to 127.0.0.1")
        )
        .firstMatch
        XCTAssertTrue(request.waitToAppear(timeout: 10))
        attachScreen(app, name: "Request appears")
        request.tap()
        let sheet = app.navigationBars["Allow Access"]
        XCTAssertTrue(sheet.waitToAppear(timeout: 5))
        let number = app.textFields["Number Shown on the Page"]
        XCTAssertTrue(number.waitToAppear(timeout: 5))
        XCTAssertFalse(sheet.buttons["Allow"].isEnabled, "The number and journals come first.")
        number.typeText(declined.number == 99 ? "10" : String(declined.number + 1))
        app.buttons["All Journals"].tap()
        attachScreen(app, name: "Allow Access, wrong number")
        sheet.buttons["Allow"].tap()
        XCTAssertTrue(app.alerts["Numbers Don’t Match"].waitToAppear(timeout: 10))
        attachScreen(app, name: "Numbers don't match")
        app.alerts.buttons["OK"].tap()
        let declinedStatus = try await declined.status()
        XCTAssertEqual(declinedStatus, "declined")

        // The next request, with the right number and every journal.
        let client = try await AuthorizationClient.start(server: address)
        XCTAssertTrue(request.waitToAppear(timeout: 10))
        request.tap()
        XCTAssertTrue(number.waitToAppear(timeout: 5))
        number.typeText(String(client.number))
        app.buttons["All Journals"].tap()
        attachScreen(app, name: "Allow Access, All Journals")
        sheet.buttons["Allow"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "UI Test Agent, All Journals"))
            .firstMatch
        XCTAssertTrue(row.waitToAppear(timeout: 15))
        XCTAssertFalse(sheet.exists)
        attachScreen(app, name: "Agent connecting")
        let pageStatus = try await client.status()
        XCTAssertTrue(["approved", "allowed"].contains(pageStatus), pageStatus)

        // Afterwards, the agent reads one chosen journal instead; the change stays.
        row.tap()
        let selected = app.buttons["Selected Journals"]
        XCTAssertTrue(selected.waitToAppear(timeout: 5))
        attachScreen(app, name: "Agent detail, All Journals")
        selected.tap()
        let journal = app.switches.firstMatch
        for _ in 0..<5 where !journal.isHittable { app.swipeUp() }
        // The switch fills its row; its control is at the trailing end.
        journal.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        attachScreen(app, name: "Agent detail, one journal")
        let saved = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "UI Test Agent, All Journals"))
            .firstMatch
        app.navigationBars["UI Test Agent"].buttons.firstMatch.tap()
        XCTAssertTrue(
            saved.waitToDisappear(timeout: 10), "The list shows the journal it reads now instead of All Journals.")
        attachScreen(app, name: "Agent Access with an agent")

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "UI Test Agent")).firstMatch.tap()
        let revoke = app.buttons["Revoke Access"]
        for _ in 0..<6 where !revoke.isHittable { app.swipeUp() }
        let revokeFrame = revoke.frame
        revoke.tap()
        XCTAssertTrue(app.staticTexts["Revoke access for UI Test Agent?"].waitToAppear(timeout: 5))
        attachScreen(app, name: "Revoke confirmation")
        // The dialog's button, not the one that opened it.
        let confirm = try XCTUnwrap(
            app.buttons.matching(NSPredicate(format: "label == %@", "Revoke Access"))
                .allElementsBoundByIndex.first { $0.isHittable && $0.frame != revokeFrame })
        if UIDevice.current.userInterfaceIdiom == .pad {
            // The popover points at the button that opened it, not at a row scrolled out of view above it.
            let gap = max(revokeFrame.minY - confirm.frame.maxY, confirm.frame.minY - revokeFrame.maxY)
            XCTAssertLessThan(gap, 150, "The confirmation is \(Int(gap)) pt from Revoke Access.")
        }
        confirm.tap()
        XCTAssertTrue(row.waitToDisappear(timeout: 15))
        // The row goes as the app sends the revocation, so the server can answer a moment later.
        let revoked = try await client.status(becoming: "declined", within: 10)
        XCTAssertEqual(revoked, "declined")
    }

    @MainActor private func setUpServerWithoutEncryption(address: String, code: String, app: XCUIApplication) {
        let connect = app.buttons["Connect to a Server…"]
        XCTAssertTrue(connect.waitToAppear(timeout: 15))
        connect.tap()
        let field = app.textFields["Server Address"]
        XCTAssertTrue(field.waitToAppear(timeout: 5))
        field.tap()
        field.typeText(address)
        app.navigationBars["Connect to a Server"].buttons["Continue"].tap()
        let setUp = app.navigationBars["Set Up Server"]
        XCTAssertTrue(setUp.waitToAppear(timeout: 10))
        app.textFields["Setup Code"].tap()
        app.textFields["Setup Code"].typeText(code)
        setUp.buttons["Continue"].tap()
        let protect = app.navigationBars["Protect Your Journals"]
        XCTAssertTrue(protect.waitToAppear(timeout: 10))
        let plain = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Don’t Encrypt")).firstMatch
        for _ in 0..<5 where !plain.isHittable { app.swipeUp() }
        plain.tap()
        protect.buttons["Set Up"].tap()
        XCTAssertTrue(app.staticTexts["Server Is Ready"].waitToAppear(timeout: 30))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["New Entry"].firstMatch.waitToAppear(timeout: 10))
    }

    @MainActor private func attachScreen(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// The MCP client's side of authorization: registration and the page that shows the number.
private struct AuthorizationClient {
    let server: String
    let number: Int
    let handle: String

    static func start(server: String) async throws -> Self {
        let registration = try XCTUnwrap(URL(string: server + "/oauth/register"))
        var request = URLRequest(url: registration)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_name": "UI Test Agent", "redirect_uris": ["http://127.0.0.1:45679/callback"],
            "token_endpoint_auth_method": "none",
        ])
        let (data, _) = try await URLSession.shared.data(for: request)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let clientID = try XCTUnwrap(body["client_id"] as? String)
        var components = try XCTUnwrap(URLComponents(string: server + "/oauth/authorize"))
        components.queryItems = [
            .init(name: "response_type", value: "code"), .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: "http://127.0.0.1:45679/callback"),
            .init(name: "code_challenge", value: String(repeating: "A", count: 43)),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "state", value: "ui"),
        ]
        let (pageData, _) = try await URLSession.shared.data(from: try XCTUnwrap(components.url))
        let page = String(decoding: pageData, as: UTF8.self)
        let number = try XCTUnwrap(
            page.range(of: #"class="number">[0-9]{2}<"#, options: .regularExpression)
                .flatMap { Int(page[$0].dropLast().suffix(2)) })
        let handle = try XCTUnwrap(
            page.range(of: #"data-handle="[0-9a-f]{64}""#, options: .regularExpression)
                .map { String(page[$0].dropLast().suffix(64)) })
        return Self(server: server, number: number, handle: handle)
    }

    /// What the authorization page shows now: waiting, approved, allowed, declined, replaced or expired.
    func status() async throws -> String {
        let url = try XCTUnwrap(URL(string: server + "/oauth/authorize/status?handle=" + handle))
        let (data, _) = try await URLSession.shared.data(from: url)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(body["status"] as? String)
    }

    /// The status once it is `expected`, or the last one seen when `seconds` pass first.
    func status(becoming expected: String, within seconds: TimeInterval) async throws -> String {
        let deadline = Date().addingTimeInterval(seconds)
        var current = try await status()
        while current != expected, Date() < deadline {
            try await Task.sleep(for: .milliseconds(200))
            current = try await status()
        }
        return current
    }
}
