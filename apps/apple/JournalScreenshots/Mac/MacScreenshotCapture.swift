import AppKit
import JournalCore
import SwiftUI
import XCTest

@testable import Journal

/// Captures the Mac App Store screenshots from the seeded sample library (docs/app-store/screenshots-plan.md).
/// Hosted in the app, it opens the library in the app's own journal window and Settings window, arranges them as each
/// frame needs and renders the windows at 2x. design/app-store/capture-mac.sh seeds the library and names it with
/// `JOURNAL_DATA_DIR`; `JOURNAL_SCREENSHOT_PASSWORD_FILE` and `JOURNAL_SCREENSHOT_OUTPUT` come from the same script.
/// For frames 4 and 3 it also starts a disposable server and passes `JOURNAL_SCREENSHOT_SERVER` (its loopback
/// address), `JOURNAL_SCREENSHOT_SETUP_CODE` and `JOURNAL_SCREENSHOT_PUBLIC_URL` (the public address the server is
/// configured with, which Agent Access and Settings > Sync show).
@MainActor
final class MacScreenshotCapture: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    func testCaptureMacFrames() async throws {
        let (model, window) = try await openLibrary()
        window.setFrame(NSRect(x: 40, y: 120, width: 1280, height: 800), display: true)
        NSApp.appearance = NSAppearance(named: .aqua)
        try await show("Slow Sunday", in: "Personal", model: model, window: window)
        try await capture(window, "01-main-light")

        // Shown on without asking: the capture runs unattended. Not saved.
        model.configuration?.appLock = true
        try await capture(try await openSettings(.privacy, model: model), "02-settings-privacy-light")
        // Off again, so no later frame is captured with App Lock on or behind its cover.
        model.configuration?.appLock = false
        try await capture(try await openSettings(.backup, model: model), "07-settings-backup-light")

        try await show("Offsite ideas", in: "Work", model: model, window: window)
        try await capture(window, "05-main-light")
        model.templateChooserPresented = true
        try await settle(2)
        try await capture(try XCTUnwrap(window.attachedSheet, "No template sheet."), "05-sheet-light")
        model.templateChooserPresented = false
        try await settle()

        NSApp.appearance = NSAppearance(named: .darkAqua)
        try await show("Slow Sunday", in: "Personal", model: model, window: window)
        try await capture(window, "04-main-dark")
        let read = try XCTUnwrap(model.items.first { $0.kind == "entry" && $0.title == "Slow Sunday" }?.id)
        try await show("Porto, day two", in: "Travel", model: model, window: window)
        try await capture(window, "06-main-dark")
        // Last, since they connect the library to a server.
        let agentPage = try await captureAgentAccess(model: model, reading: read)
        try await close(agentPage)
        NSApp.appearance = NSAppearance(named: .aqua)
        try await captureConnectedSync(model: model)
    }

    // MARK: - Arranging

    private func openLibrary() async throws -> (AppModel, NSWindow) {
        let phrase = try password()
        let window = try XCTUnwrap(journalWindow(), "The journal window isn't open.")
        let delegate = NSApp.delegate.flatMap { Self.find(ApplicationDelegate.self, in: $0, depth: 0) }
        if delegate == nil, let appDelegate = NSApp.delegate { Self.dump(appDelegate, depth: 0) }
        let model = try XCTUnwrap(delegate?.model ?? Self.find(AppModel.self, in: window.contentView as Any, depth: 0))
        await model.load()
        await model.unlockWithRecovery(phrase)
        XCTAssertFalse(model.locked, model.error ?? "")
        return (model, window)
    }

    private func password() throws -> String {
        guard let passwordFile = environment["JOURNAL_SCREENSHOT_PASSWORD_FILE"] else {
            throw CaptureError("Run design/app-store/capture-mac.sh, which seeds the library.")
        }
        return try String(contentsOfFile: passwordFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func journalWindow() -> NSWindow? {
        // The WindowGroup's windows are identified by its ID, "journal".
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(JournalApp.windowID) == true }
            ?? NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) }
    }

    private func show(_ title: String, in journal: String, model: AppModel, window: NSWindow) async throws {
        let journalID = try XCTUnwrap(model.journals.first { $0.title == journal }?.id)
        await model.switchJournal(journalID)
        let entry = try XCTUnwrap(model.items.first { $0.kind == "entry" && $0.title == title })
        await model.select(entry.id)
        try await settle()
        // No insertion point in the editor, as after clicking in the list.
        window.makeFirstResponder(nil)
        try await settle(0.5)
    }

    private func openSettings(_ tab: AppSettingsTab, model: AppModel) async throws -> NSWindow {
        model.settingsTab = tab
        model.settingsPresented = true
        try await settle(2)
        let journal = journalWindow()
        return try XCTUnwrap(
            NSApp.windows.first {
                $0.isVisible && $0 !== journal && $0.styleMask.contains(.titled) && $0.sheetParent == nil
            })
    }

    private func settle(_ seconds: Double = 1.5) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: - Agent Access

    /// Frame 4: the library on a disposable server set up by "MacBook Pro", "Writing Assistant" allowed to read
    /// Personal and Work and used once, then Settings > Agent Access and the agent's page. Returns the agent's page,
    /// still open.
    private func captureAgentAccess(model: AppModel, reading entryID: UUID) async throws -> NSWindow {
        guard let address = environment["JOURNAL_SCREENSHOT_SERVER"], address.hasPrefix("http://127.0.0.1:"),
            let publicURL = environment["JOURNAL_SCREENSHOT_PUBLIC_URL"]
        else { throw CaptureError("Run design/app-store/capture-mac.sh, which starts the server.") }
        try await connect(model, to: address)
        let controller = ServerAgentsController()
        await controller.load(model)
        guard controller.phase == .ready, let mcpURL = controller.mcpURL else {
            throw CaptureError("Agent Access isn't ready: \(controller.phase)")
        }
        // Agent Access shows the server's public address, without the note about agents on this Mac.
        guard mcpURL == publicURL + "/mcp", ServerAgentText.reachability(mcpURL) == nil else {
            throw CaptureError("Agent Access shows \(mcpURL) instead of \(publicURL)/mcp.")
        }
        var agent = ScreenshotAgent(
            server: try PublicHostConnection(loopbackAddress: address, publicURL: publicURL))
        try await agent.register()
        let page = try await agent.openAuthorizationPage()
        try await allow(controller, model: model, number: page.number)
        try await agent.redeem(handle: page.handle)
        try await use(agent, reading: entryID)
        try await waitForAgent(controller, model: model)
        let settings = try await openSettings(.agents, model: model)
        // The pane loads the same list for itself.
        try await settle(3)
        try await capture(settings, "04-settings-agents-dark")
        // The first row of the pane's first section, Agents, with nothing waiting under Requests.
        click(settings, at: try firstRow(of: settings))
        for _ in 0..<20 where settings.attachedSheet == nil {
            try await settle(0.25)
        }
        let agentPage = try XCTUnwrap(settings.attachedSheet, "The agent's page didn't open.")
        // No insertion point in the Name field.
        agentPage.makeFirstResponder(nil)
        try await settle()
        try await capture(agentPage, "04-agent-detail-dark")
        return agentPage
    }

    /// Closes the agent's page with Return, which presses its default button, Done.
    private func close(_ agentPage: NSWindow) async throws {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: agentPage.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                isARepeat: false, keyCode: 36)
            if let event { NSApp.postEvent(event, atStart: false) }
        }
        for _ in 0..<20 where agentPage.isVisible {
            try await settle(0.25)
        }
        XCTAssertFalse(agentPage.isVisible, "Return didn't close the agent's page.")
    }

    /// Frame 3: Settings > Sync connected to the server that frame 4 set up. The server's public address is
    /// https://journal.example.net, as Agent Access shows, but that name doesn't lead to the disposable server, so the
    /// library keeps syncing with it on its loopback port while the connection names the public address. Then it
    /// syncs once more, so Last Synced is a real synchronization with that server.
    private func captureConnectedSync(model: AppModel) async throws {
        guard let connection = model.connection, let publicURL = environment["JOURNAL_SCREENSHOT_PUBLIC_URL"] else {
            throw CaptureError("The library isn't connected to the server.")
        }
        // Not configureSync(): the sync engine keeps its client for the loopback port.
        model.connection = SyncConnection(address: publicURL, deviceID: connection.deviceID, token: connection.token)
        let synchronized = await model.sync()
        XCTAssertTrue(synchronized, "The library didn't synchronize with the server.")
        XCTAssertNil(model.syncError)
        try await capture(try await openSettings(.sync, model: model), "03-settings-sync-light")
    }

    /// Sets up the server with the library as the device "MacBook Pro", as the iPhone and iPad captures do, so the
    /// Mac's own name never appears, and synchronizes the library to it. The connection isn't saved.
    private func connect(_ model: AppModel, to address: String) async throws {
        guard let code = environment["JOURNAL_SCREENSHOT_SETUP_CODE"], let envelope = model.configuration?.recovery
        else { throw CaptureError("No setup code for the server.") }
        let secret = try VaultCrypto.recover(envelope, phrase: try password()).1
        let grant = try await ServerClient(address: address).initialize(
            code: code, envelope: envelope, recoverySecret: secret, deviceName: "MacBook Pro")
        model.connection = SyncConnection(address: address, deviceID: grant.deviceId, token: grant.token)
        model.configureSync()
        let synchronized = await model.sync()
        XCTAssertTrue(synchronized, "The library didn't synchronize with the server.")
    }

    /// Allows the agent's request for Personal and Work as Allow in the Allow Access sheet does
    /// (AllowAgentView.allow): the request's details, then the controller's approval with the page's number.
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

    /// Lists the journals, searches and reads an entry, so the agent's Recent Activity has real requests.
    private func use(_ agent: ScreenshotAgent, reading entryID: UUID) async throws {
        let journals = try await agent.callTool("list_journals", [:])
        guard journals.contains("Personal"), journals.contains("Work"), !journals.contains("Travel") else {
            throw CaptureError("The agent lists other journals than Personal and Work: \(journals)")
        }
        guard try await agent.callTool("search_entries", ["query": "walk"]).contains("Rainy walk") else {
            throw CaptureError("The agent's search didn't find \"Rainy walk\".")
        }
        let entry = try await agent.callTool("read_entry", ["entry_id": entryID.uuidString])
        guard entry.contains("Woke up before the alarm") else {
            throw CaptureError("The agent couldn't read \"Slow Sunday\".")
        }
    }

    /// Waits until the server lists the agent as allowed.
    private func waitForAgent(_ controller: ServerAgentsController, model: AppModel) async throws {
        for _ in 0..<20 {
            await controller.load(model)
            if controller.agents.contains(where: { $0.name == ScreenshotAgent.clientName }) { return }
            try await settle(0.5)
        }
        throw CaptureError("The server doesn't list \(ScreenshotAgent.clientName).")
    }

    /// Where the first row of a grouped Settings pane is, in window coordinates: the pane's content isn't exposed to
    /// accessibility in the app's own process while no assistive app is running, so the row is found by its place.
    private func firstRow(of window: NSWindow) throws -> NSPoint {
        let content = window.contentLayoutRect
        guard content.height > 120 else { throw CaptureError("The Settings pane is too small.") }
        return NSPoint(x: content.midX, y: content.maxY - Self.firstRowCenter)
    }

    /// Points from the top of the pane's content to the middle of its first row, below the first section header.
    private static let firstRowCenter: CGFloat = 60

    /// A click, queued like one from the mouse, so the window handles it as it would a person's.
    private func click(_ window: NSWindow, at point: NSPoint) {
        for (type, pressure) in [(NSEvent.EventType.leftMouseDown, Float(1)), (.leftMouseUp, Float(0))] {
            let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: pressure)
            if let event { NSApp.postEvent(event, atStart: false) }
        }
    }

    // MARK: - Capturing

    /// Writes the window twice: as the window server composes it, and as its views draw themselves, so the script
    /// can use whichever the environment allows.
    private func capture(_ window: NSWindow, _ name: String) async throws {
        window.makeKeyAndOrderFront(nil)
        try await settle()
        let folder = try outputFolder()
        if let image = Self.windowImage(window) {
            try png(image).write(to: folder.appendingPathComponent(name + "-server.png"))
        }
        if let frame = window.contentView?.superview {
            let scale: CGFloat = 2
            let size = frame.bounds.size
            guard
                let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
            else { throw CaptureError("No bitmap for \(name)") }
            rep.size = size
            frame.cacheDisplay(in: frame.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try data.write(to: folder.appendingPathComponent(name + "-views.png"))
            }
        }
        print("captured", name, window.backingScaleFactor, window.frame)
    }

    private func outputFolder() throws -> URL {
        guard let output = environment["JOURNAL_SCREENSHOT_OUTPUT"] else {
            throw CaptureError("Run design/app-store/capture-mac.sh, which names the output folder.")
        }
        let folder = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func png(_ image: CGImage) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CaptureError("No PNG") }
        return data
    }

    /// `CGWindowListCreateImage` for the app's own window, which needs no screen recording permission. It is
    /// looked up at run time because the macOS 15 SDK no longer declares it.
    private static func windowImage(_ window: NSWindow) -> CGImage? {
        typealias Create = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
            let symbol = dlsym(handle, "CGWindowListCreateImage")
        else { return nil }
        let create = unsafeBitCast(symbol, to: Create.self)
        // Only this window, at its own bounds without the shadow, at the display's full resolution.
        let includingWindow: UInt32 = 1 << 3
        let options: UInt32 = (1 << 0) | (1 << 3)
        return create(.null, includingWindow, UInt32(window.windowNumber), options)?.takeRetainedValue()
    }

    private static func dump(_ value: Any, depth: Int) {
        guard depth < 5 else { return }
        for child in Mirror(reflecting: value).children {
            print(String(repeating: "  ", count: depth), child.label ?? "-", type(of: child.value))
            dump(child.value, depth: depth + 1)
        }
    }

    /// Finds an object of the given type in a view's stored properties, such as the model a SwiftUI hosting view
    /// passes to its content as an environment object.
    private static func find<T: AnyObject>(_ type: T.Type, in value: Any, depth: Int) -> T? {
        if let found = value as? T { return found }
        guard depth < 14 else { return nil }
        for child in Mirror(reflecting: value).children {
            if let found = find(type, in: child.value, depth: depth + 1) { return found }
        }
        return nil
    }
}

struct CaptureError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
