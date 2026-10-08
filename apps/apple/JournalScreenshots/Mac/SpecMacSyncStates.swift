import AppKit
import JournalCore
import Network
import XCTest

@testable import Journal

/// The Mac spec states that need a server: connecting, the connected Settings panes, Add Device and an agent. The
/// server is the disposable one design/spec-screenshots/capture.sh starts; `JOURNAL_SPEC_SERVER` is its loopback
/// address, `JOURNAL_SPEC_SETUP_CODE` its setup code and `JOURNAL_SPEC_PUBLIC_URL` the public address it announces.
extension SpecMacCapture {
    func syncStates(_ model: AppModel) async throws {
        guard let address = environment["JOURNAL_SPEC_SERVER"], address.hasPrefix("http://127.0.0.1:"),
            let code = environment["JOURNAL_SPEC_SETUP_CODE"], !code.isEmpty
        else { throw CaptureError("Run design/spec-screenshots/capture.sh, which starts the server.") }
        await state("connect sheet") { try await connectSheet(model, address: address) }
        try await connect(model, to: address, code: code)
        await state("connected") { try await connectedPanes(model) }
        await state("sync status") { try await syncStatusStates(model) }
        await state("agent") { try await agentStates(model) }
    }

    // MARK: - Connecting

    /// The first steps of Connect to a Server… in Settings ▸ Sync. The address step lists servers found on the
    /// network, so it is only captured when none is found.
    private func connectSheet(_ model: AppModel, address: String) async throws {
        let settings = try await openSettings(.sync, model: model)
        tap(settings, at: 107, fromTop: 156)
        try await settle(2)
        if try await nothingFoundOnTheNetwork() {
            try await captureSheet(settings, "connect-to-server-address")
        } else {
            try note("connect-to-server-address: servers on this network are listed, so it was not captured.")
        }
        try await closeSheets(of: settings)
        model.settingsPresented = false
        try await settle(0.5)
    }

    /// Looks for My Journal servers for a few seconds, as the sheet does.
    private func nothingFoundOnTheNetwork() async throws -> Bool {
        let browser = ServerBrowser()
        browser.start()
        try await settle(4)
        let none = browser.servers.isEmpty
        browser.stop()
        return none
    }

    private func note(_ line: String) throws {
        let file = try outputFolder().appendingPathComponent("skipped.txt")
        let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        try (existing + line + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    /// Sets the server up with the library as the device "MacBook Pro", so the Mac's own name never appears.
    private func connect(_ model: AppModel, to address: String, code: String) async throws {
        guard let envelope = model.configuration?.recovery else { throw CaptureError("No library.") }
        let secret = try VaultCrypto.recover(envelope, phrase: try password()).1
        let grant = try await ServerClient(address: address).initialize(
            code: code, envelope: envelope, recoverySecret: secret, deviceName: "MacBook Pro")
        model.connection = SyncConnection(address: address, deviceID: grant.deviceId, token: grant.token)
        model.configureSync()
        let synchronized = await model.sync()
        XCTAssertTrue(synchronized, "The library didn't synchronize with the server.")
    }

    private func connectedPanes(_ model: AppModel) async throws {
        let sync = try await openSettings(.sync, model: model)
        try await capture(sync, "settings-sync-connected")
        tap(sync, at: 85, fromTop: 282)
        try await settle(1.5)
        try await captureSheet(sync, "stop-syncing-default")
        try await closeSheets(of: sync)
        let devices = try await openSettings(.devices, model: model)
        try await capture(devices, "settings-devices-connected")
        tap(devices, at: 70, fromTop: 205)
        try await settle(4)
        try await captureSheet(devices, "add-device-default")
        try await closeSheets(of: devices)
    }

    // MARK: - A server that was replaced

    /// Sync Status in the toolbar and Settings ▸ Sync when the server holds another library: the state that asks the
    /// person to connect again. It is recorded on the model, as a failed synchronization would, and cleared after.
    private func syncStatusStates(_ model: AppModel) async throws {
        let window = try XCTUnwrap(journalWindow())
        defer { model.resetSyncHealth() }
        model.syncFailed = true
        model.recordSyncHealth(.serverReplaced, failure: nil)
        model.syncError = SyncHealth.serverReplaced.message(host: "127.0.0.1:18765")
        try await settle(2)
        try await capture(window, "sync-status-default")
        try await capture(try await openSettings(.sync, model: model), "settings-sync-connect-again")
    }

    // MARK: - An agent

    /// "Writing Assistant" asks for access to Personal and Work (the request in Settings ▸ Agent Access and its Allow
    /// Access sheet), is allowed, and is used once, so its page has Recent Activity.
    private func agentStates(_ model: AppModel) async throws {
        guard let address = environment["JOURNAL_SPEC_SERVER"], let publicURL = environment["JOURNAL_SPEC_PUBLIC_URL"]
        else { throw CaptureError("No server address.") }
        let controller = ServerAgentsController()
        await controller.load(model)
        guard controller.phase == .ready else { throw CaptureError("Agent Access isn't ready: \(controller.phase)") }
        var agent = ScreenshotAgent(server: try PublicHostConnection(loopbackAddress: address, publicURL: publicURL))
        try await agent.register()
        let page = try await agent.openAuthorizationPage()
        try await settle(1)
        let settings = try await openSettings(.agents, model: model)
        try await settle(4)
        try await capture(settings, "settings-agent-access-request")
        click(settings, at: try firstRow(of: settings))
        try await settle(3)
        if settings.attachedSheet != nil { try await captureSheet(settings, "allow-agent-default") }
        try await allow(controller, model: model, number: page.number)
        try await closeSheets(of: settings)
        try await agent.redeem(handle: page.handle)
        try await use(agent, model: model)
        try await waitForAgent(controller, model: model)
        // Settings loads the agents when it opens.
        _ = try await openSettings(.sync, model: model)
        let allowed = try await openSettings(.agents, model: model)
        try await settle(3)
        try await capture(allowed, "settings-agent-access-connected")
        click(allowed, at: try firstRow(of: allowed))
        try await settle(3)
        if allowed.attachedSheet != nil { try await captureSheet(allowed, "agent-detail-default") }
        try await closeSheets(of: allowed)
    }

    private func allow(_ controller: ServerAgentsController, model: AppModel, number: Int) async throws {
        var summary: AgentRequest?
        for _ in 0..<40 where summary == nil {
            await controller.refreshRequests(model)
            summary = controller.requests.first { $0.clientName == ScreenshotAgent.clientName }
            if summary == nil { try await settle(0.5) }
        }
        guard let summary else { throw CaptureError("The agent's request didn't arrive.") }
        let request = try await controller.request(model, id: summary.id)
        let journals = Set(model.journals.filter { ["Personal", "Work"].contains($0.title) }.map(\.id))
        guard journals.count == 2 else { throw CaptureError("Personal and Work aren't both in the library.") }
        try await controller.approve(model, request: request, number: number, allJournals: false, journalIDs: journals)
    }

    private func use(_ agent: ScreenshotAgent, model: AppModel) async throws {
        let read = try XCTUnwrap(model.items.first { $0.kind == "entry" && $0.title == "Slow Sunday" }?.id)
        _ = try await agent.callTool("list_journals", [:])
        _ = try await agent.callTool("search_entries", ["query": "walk"])
        _ = try await agent.callTool("read_entry", ["entry_id": read.uuidString])
    }

    private func waitForAgent(_ controller: ServerAgentsController, model: AppModel) async throws {
        for _ in 0..<20 {
            await controller.load(model)
            if controller.agents.contains(where: { $0.name == ScreenshotAgent.clientName }) { return }
            try await settle(0.5)
        }
        throw CaptureError("The server doesn't list \(ScreenshotAgent.clientName).")
    }

    /// Where the first row of a grouped Settings pane is, in window coordinates: the pane's content isn't exposed to
    /// accessibility in the app's own process, so the row is found by its place.
    private func firstRow(of window: NSWindow) throws -> NSPoint {
        let content = window.contentLayoutRect
        guard content.height > 120 else { throw CaptureError("The Settings pane is too small.") }
        return NSPoint(x: content.midX, y: content.maxY - 60)
    }

    /// A click, queued like one from the mouse, so the window handles it as it would a person's.
    private func click(_ window: NSWindow, at point: NSPoint) {
        for (type, pressure) in [(NSEvent.EventType.leftMouseDown, Float(1)), (.leftMouseUp, Float(0))] {
            let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: pressure)
            if let event { NSApp.postEvent(event, atStart: false) }
        }
    }
}
