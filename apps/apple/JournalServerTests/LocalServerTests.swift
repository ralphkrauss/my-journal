#if os(macOS)
    import AppKit
    import SwiftUI
    import CryptoKit
    import JournalCore
    import Network
    import XCTest

    @testable import Journal

    @MainActor
    final class LocalServerTests: XCTestCase {
        func testSetupSyncManualStopAndAutomaticResumePreserveCredentials() async throws {
            let fixture = try await Fixture()
            do {
                let model = fixture.model
                await attachPreview(
                    LocalServerSetupView(controller: fixture.controller).environmentObject(model),
                    name: "Local server setup")
                await model.turnOnAppLockForTesting()
                let original = try XCTUnwrap(model.configuration)
                await model.newEntry()
                var entry = try XCTUnwrap(model.draft)
                entry.title = "Written before server setup"
                model.updateDraft(entry)
                try await fixture.controller.setup(phrase: fixture.phrase)
                XCTAssertTrue(fixture.controller.isConfigured)
                await attachPreview(
                    Form { LocalServerSection(controller: fixture.controller) }.formStyle(.grouped).environmentObject(
                        model), name: "Running local server")
                let connection = try XCTUnwrap(model.connection)
                let changes = try await ServerClient(address: connection.address, token: connection.token).changes(
                    after: 0)
                XCTAssertFalse(changes.changes.isEmpty, "Setup must upload local entries immediately.")
                // Retry-safe outbox operations retain their original payload until acknowledged;
                // a subsequent pass uploads edits made after an entry was first queued.
                await model.sync()
                XCTAssertFalse(model.pendingSync)
                XCTAssertEqual(model.configuration?.appLock, original.appLock)
                XCTAssertEqual(
                    try JournalCoding.encoder().encode(model.configuration?.recovery),
                    try JournalCoding.encoder().encode(original.recovery))
                await model.lock()
                XCTAssertEqual(
                    fixture.controller.phase, .running, "Lock must leave the committed encrypted server available.")
                await fixture.controller.stop()
                await model.unlockForTesting()
                await attachPreview(
                    Form { LocalServerSection(controller: fixture.controller) }.formStyle(.grouped).environmentObject(
                        model), name: "Stopped local server")
                let reopened = AppModel(directory: model.directory)
                await reopened.load()
                XCTAssertTrue(reopened.locked)
                let resumed = fixture.controllerFor(reopened)
                await resumed.resumeIfNeeded()
                XCTAssertEqual(resumed.phase, .stopped, "Manual stop must survive relaunch.")
                await reopened.unlockForTesting()
                XCTAssertEqual(reopened.connection?.token, connection.token)
                XCTAssertEqual(reopened.items.first { $0.id == entry.id }?.title, entry.title)
                await resumed.start()
                XCTAssertEqual(resumed.phase, .running)
                let stopped = await resumed.stopForQuit()
                XCTAssertTrue(stopped)
                let nextLaunch = fixture.controllerFor(reopened)
                await nextLaunch.resumeIfNeeded()
                XCTAssertEqual(nextLaunch.phase, .running, "Quit must preserve automatic restart preference.")
                let stoppedAgain = await nextLaunch.stopForQuit()
                XCTAssertTrue(stoppedAgain)
            } catch {
                await fixture.clean()
                throw error
            }
            await fixture.clean()
        }

        func testPasswordlessSetupAndRecoveryAfterLostDeviceCredential() async throws {
            let fixture = try await Fixture(encrypted: false)
            do {
                try await fixture.controller.setup(phrase: "")
                XCTAssertTrue(fixture.controller.isConfigured)
                XCTAssertEqual(fixture.model.configuration?.recovery.formatVersion, 4)
                let original = try XCTUnwrap(fixture.model.connection)
                let stopped = await fixture.controller.stopForQuit()
                XCTAssertTrue(stopped)
                try Keychain.remove(try XCTUnwrap(fixture.model.configuration?.connectionKeyID))
                let reopened = AppModel(directory: fixture.model.directory)
                await reopened.load()
                XCTAssertNil(reopened.connection)
                let controller = fixture.controllerFor(reopened)
                try await controller.setup(phrase: "")
                XCTAssertTrue(controller.isConfigured)
                XCTAssertNotEqual(reopened.connection?.token, original.token)
                XCTAssertEqual(reopened.journals.map(\.title), ["Default"])
            } catch {
                await fixture.clean()
                throw error
            }
            await fixture.clean()
        }

        func testPartialSetupRecoversExistingVaultAndPortCollisionLeavesOwnerRunning() async throws {
            let owner = try await Fixture()
            let other = try await Fixture(port: owner.port)
            do {
                try await owner.controller.setup(phrase: owner.phrase)
                let connection = try XCTUnwrap(owner.model.connection)
                let client = try ServerClient(address: connection.address, token: connection.token)
                let envelope = try await client.recoveryEnvelope()
                do {
                    try await other.controller.setup(phrase: other.phrase)
                    XCTFail("An unrelated listener must not satisfy readiness.")
                } catch {
                    XCTAssertFalse(other.controller.isConfigured)
                }
                XCTAssertEqual(owner.controller.phase, .running)
                let status = try await client.status()
                XCTAssertTrue(status.initialized)
                let stopped = await owner.controller.stopForQuit()
                XCTAssertTrue(stopped)
                // Leave initialized server data but remove the device credential, as after an interrupted setup.
                try Keychain.remove(try XCTUnwrap(owner.model.configuration?.connectionKeyID))
                let reopened = AppModel(directory: owner.model.directory)
                await reopened.load()
                XCTAssertNil(reopened.connection)
                let retry = owner.controllerFor(reopened)
                do {
                    try await retry.setup(phrase: "wrong recovery key")
                    XCTFail("Recovery must reject the wrong key.")
                } catch { XCTAssertEqual(retry.phase, .stopped) }
                try await retry.setup(phrase: owner.phrase)
                XCTAssertTrue(retry.isConfigured)
                let reconnected = try XCTUnwrap(reopened.connection)
                let recoveredEnvelope = try await ServerClient(address: retry.address, token: reconnected.token)
                    .recoveryEnvelope()
                XCTAssertEqual(
                    try JournalCoding.encoder().encode(envelope),
                    try JournalCoding.encoder().encode(recoveredEnvelope))
                let stoppedRetry = await retry.stopForQuit()
                XCTAssertTrue(stoppedRetry)
            } catch {
                await other.clean()
                await owner.clean()
                throw error
            }
            await other.clean()
            await owner.clean()
        }
        func testLockDuringSetupStopsOwnedChildAndPreservesRetryData() async throws {
            let fixture = try await Fixture()
            do {
                await fixture.model.turnOnAppLockForTesting()
                let setup = Task { try await fixture.controller.setup(phrase: fixture.phrase) }
                let deadline = Date().addingTimeInterval(5)
                while fixture.controller.phase == .stopped && Date() < deadline {
                    try await Task.sleep(nanoseconds: 1_000_000)
                }
                XCTAssertEqual(fixture.controller.phase, .starting)
                await fixture.model.lock()
                setup.cancel()
                do {
                    try await setup.value
                    XCTFail("Lock must prevent an uncommitted connection.")
                } catch {
                    XCTAssertNil(fixture.model.connection)
                }
                let stopped = await fixture.controller.stopForQuit()
                XCTAssertTrue(stopped)
                XCTAssertEqual(fixture.controller.phase, .stopped)
                XCTAssertTrue(
                    FileManager.default.fileExists(
                        atPath: fixture.model.directory.appendingPathComponent("local-server-data").path))
                await fixture.model.unlockForTesting()
                try await fixture.controller.setup(phrase: fixture.phrase)
                XCTAssertTrue(fixture.controller.isConfigured)
            } catch {
                await fixture.clean()
                throw error
            }
            await fixture.clean()
        }

        private func attachPreview<V: View>(_ view: V, name: String) async {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 500), styleMask: [.titled], backing: .buffered,
                defer: true)
            let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
            host.frame = NSRect(x: 0, y: 0, width: 480, height: 500)
            window.contentView = host
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = NSImage(size: host.bounds.size)
            image.addRepresentation(bitmap)
            let attachment = XCTAttachment(image: image)
            attachment.name = name + " (offscreen native render)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    private final class Fixture {
        let model: AppModel
        let controller: LocalServerController
        let port: UInt16
        let phrase: String
        let executable: URL
        private var models: [AppModel] = []
        private var controllers: [LocalServerController] = []

        init(port requestedPort: UInt16? = nil, encrypted: Bool = true) async throws {
            executable = URL(
                fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["JOURNAL_LOCAL_SERVER_EXECUTABLE"]))
            if let requestedPort {
                port = requestedPort
            } else {
                let listener = try NWListener(using: .tcp, on: .any)
                listener.newConnectionHandler = { $0.cancel() }
                port = try await withCheckedThrowingContinuation { continuation in
                    listener.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            if let value = listener.port?.rawValue {
                                continuation.resume(returning: value)
                            } else {
                                continuation.resume(throwing: JournalError.invalidData)
                            }
                            listener.cancel()
                        case .failed(let error): continuation.resume(throwing: error)
                        default: break
                        }
                    }
                    listener.start(queue: .main)
                }
            }
            model = AppModel(
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            await model.start(encrypted: encrypted)
            phrase = encrypted ? try XCTUnwrap(model.recoveryKey) : ""
            if encrypted { model.confirmRecovery() }
            controller = LocalServerController(model: model, executable: executable, port: port)
            model.localServer = controller
            models = [model]
            controllers = [controller]
        }
        func controllerFor(_ model: AppModel) -> LocalServerController {
            let result = LocalServerController(model: model, executable: executable, port: port)
            model.localServer = result
            models.append(model)
            controllers.append(result)
            return result
        }
        func clean() async {
            for controller in controllers { _ = await controller.stopForQuit() }
            for model in models {
                let account =
                    "master-"
                    + SHA256.hash(data: Data(model.directory.path.utf8))
                    .map { String(format: "%02x", $0) }.joined()
                try? await model.store?.close()
                for key in [account, model.configuration?.keyID, model.configuration?.connectionKeyID].compactMap({ $0 }
                ) {
                    try? Keychain.remove(key)
                }
            }
            try? FileManager.default.removeItem(at: model.directory)
        }
    }
#endif
