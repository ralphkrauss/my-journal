#if os(macOS)
    import Darwin
    import JournalCore
    import XCTest

    @testable import Journal

    /// The app's own recovery paths (docs/design/sync-health-and-recovery.md §3.2): `AppModel` sets up, joins, stops
    /// syncing and syncs against the published server at a fixed loopback port, which each test stops, wipes, restores
    /// or replaces with another library. Each ends with a new device downloading every entry, journal name and
    /// template exactly once. Run by scripts/test-server-recovery.sh.
    @MainActor
    final class SyncRecoveryServerTests: XCTestCase {
        private let password = "a disposable library password"
        private let otherPassword = "another library's password"
        private var server: DisposableServer?
        private var models: [AppModel] = []

        override func tearDown() async throws {
            server?.stop()
            if let server { try? FileManager.default.removeItem(at: server.root) }
            for model in models {
                try? await model.store?.close()
                for account in [model.configuration?.keyID, model.configuration?.connectionKeyID].compactMap({ $0 }) {
                    try? Keychain.remove(account)
                }
                try? FileManager.default.removeItem(at: model.directory)
            }
        }

        func testReconnectAfterARemovalJoinsByIdentity() async throws {
            let (server, model) = try await connectedLibrary()
            try await removeDevices(except: nil, server: server)
            try await write("After removal", model)
            await model.syncNow()
            XCTAssertEqual(model.syncHealth, .accessRemoved)
            XCTAssertEqual(model.syncStatusAction, .reconnect)

            try await model.recoverServer(address: server.address, phrase: password, uploadLocal: true)
            try expectSyncing(model)
            try await expectOnce(["Before", "After removal"], server: server, password: password)
        }

        func testReconnectAfterAReset() async throws {
            let (server, model) = try await connectedLibrary()
            try await server.wipe()
            await model.syncNow()
            XCTAssertEqual(model.syncHealth, .serverNotSetUp)
            XCTAssertEqual(model.syncStatusAction, .reconnect)
            XCTAssertTrue(model.automaticSyncStopped)

            try await model.initializeServer(
                address: server.address, code: server.setupCode(), phrase: password, uploadLocal: true)
            try expectSyncing(model)
            try await expectOnce(["Before"], server: server, password: password)
        }

        func testReconnectAfterARestoreSendsWhatTheBackupLacks() async throws {
            let (server, model) = try await connectedLibrary()
            let backup = server.root.appendingPathComponent("backup")
            try server.run("--backup", backup.path)
            try await write("After the backup", model)
            await model.syncNow()
            XCTAssertNil(model.syncHealth)
            try await server.restore(backup)
            await model.syncNow()
            XCTAssertEqual(model.syncHealth, .serverReplaced)
            XCTAssertEqual(model.syncStatusAction, .reconnect)

            try await model.recoverServer(address: server.address, phrase: password, uploadLocal: true)
            try expectSyncing(model)
            try await expectOnce(["Before", "After the backup"], server: server, password: password)
        }

        func testAServerReplacedByAnotherLibraryMergesOnlyAfterMergeJournals() async throws {
            let (server, model) = try await connectedLibrary()
            try await server.wipe()
            try await setUpAnotherLibrary(server)
            await model.syncNow()
            XCTAssertEqual(model.syncHealth, .serverReplaced)
            XCTAssertEqual(model.syncStatusAction, .reconnect)
            let connection = model.connection

            do {
                try await model.recoverServer(address: server.address, phrase: otherPassword, uploadLocal: true)
                XCTFail("Another library's journals merge only after Merge Journals")
            } catch {
                XCTAssertTrue(error is MergeConsentNeeded, "\(error)")
            }
            XCTAssertEqual(model.connection?.token, connection?.token, "Nothing changed before Merge")
            model.agreedMergeHost = ServerAddress.host(server.address)
            try await model.recoverServer(address: server.address, phrase: otherPassword, uploadLocal: true)
            try expectSyncing(model)
            try await expectOnce(["Before", "Other library's entry"], server: server, password: otherPassword)
        }

        func testStopSyncingThenJoiningAnotherLibraryMerges() async throws {
            let (server, model) = try await connectedLibrary()
            model.stopSyncing()
            XCTAssertNil(model.connection)
            try await write("While not syncing", model)
            try await server.wipe()
            try await setUpAnotherLibrary(server)

            XCTAssertTrue(model.joinsByMerging, "Merge Journals is asked before signing in")
            try await model.recoverServer(address: server.address, phrase: otherPassword, uploadLocal: true)
            try expectSyncing(model)
            try await expectOnce(
                ["Before", "While not syncing", "Other library's entry"], server: server, password: otherPassword)
        }

        func testStopSyncingThenConnectingAgainJoinsByIdentity() async throws {
            let (server, model) = try await connectedLibrary()
            model.stopSyncing()
            try await write("While not syncing", model)
            try await model.recoverServer(address: server.address, phrase: password, uploadLocal: true)
            try expectSyncing(model)
            try await expectOnce(["Before", "While not syncing"], server: server, password: password)
        }

        // MARK: Support

        /// A library as this build creates it, without templates, with one entry, set up on a new server from the app.
        private func connectedLibrary() async throws -> (DisposableServer, AppModel) {
            let server = try DisposableServer()
            self.server = server
            try await server.start()
            let model = AppModel(
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            models.append(model)
            await model.start(password: password)
            try await write("Before", model)
            try await model.initializeServer(
                address: server.address, code: server.setupCode(), phrase: password, uploadLocal: true)
            try expectSyncing(model)
            return (server, model)
        }
        private func write(_ title: String, _ model: AppModel) async throws {
            await model.newEntry()
            var entry = try XCTUnwrap(model.draft)
            entry.title = title
            model.updateDraft(entry)
            let saved = await model.finishPendingSave()
            XCTAssertTrue(saved)
        }
        private func expectSyncing(_ model: AppModel, file: StaticString = #filePath, line: UInt = #line) throws {
            XCTAssertNil(model.syncHealth, file: file, line: line)
            XCTAssertEqual(model.syncStatusAction, .syncNow, file: file, line: line)
            XCTAssertNotNil(model.syncActivity.lastSynced, "Synced with the new connection", file: file, line: line)
            XCTAssertFalse(model.automaticSyncStopped, file: file, line: line)
        }
        /// Another device signs in and removes every other device.
        private func removeDevices(except: UUID?, server: DisposableServer) async throws {
            let anonymous = try ServerClient(address: server.address)
            let other = try await anonymous.recoverVault(
                password, parameters: anonymous.recoveryParameters(), deviceName: "Other device")
            let owner = try ServerClient(address: server.address, token: other.grant.token)
            for device in try await owner.devices() where device.id != other.grant.deviceId && !device.revoked {
                try await owner.revoke(device.id)
            }
        }
        /// Another library, made by an earlier build with its built-in templates, a Default journal and an entry, sets
        /// the server up.
        private func setUpAnotherLibrary(_ server: DisposableServer) async throws {
            let key = try VaultCrypto.generateKey()
            let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: otherPassword, formatVersion: 2)
            let grant = try await ServerClient(address: server.address).initialize(
                code: server.setupCode(), envelope: recovery.0, recoverySecret: recovery.1, deviceName: "Other")
            let directory = server.root.appendingPathComponent("other-library")
            let store = try JournalStore(directory: directory, key: key)
            for template in BuiltInTemplates.asEarlierBuildsCreated() { try await store.save(template) }
            let journal = JournalItem(kind: "journal", title: "Default")
            try await store.save(journal)
            try await store.save(JournalItem(kind: "entry", journalID: journal.id, title: "Other library's entry"))
            try await SyncEngine(store: store, client: ServerClient(address: server.address, token: grant.token))
                .synchronize()
            try await store.close()
        }
        /// A new device downloads the library: each title once, and no journal or template name twice.
        private func expectOnce(_ titles: [String], server: DisposableServer, password: String) async throws {
            let anonymous = try ServerClient(address: server.address)
            let recovered = try await anonymous.recoverVault(
                password, parameters: anonymous.recoveryParameters(), deviceName: "Check")
            let directory = server.root.appendingPathComponent("check-" + UUID().uuidString)
            let store = try JournalStore(directory: directory, key: recovered.key)
            try await SyncEngine(
                store: store, client: ServerClient(address: server.address, token: recovered.grant.token)
            )
            .synchronize()
            let items = try await store.items().filter { $0.deletedAt == nil }
            try await store.close()
            let entries = items.filter { $0.kind == "entry" }.map(\.title)
            for title in titles { XCTAssertEqual(entries.filter { $0 == title }.count, 1, "“\(title)”: \(entries)") }
            for kind in ["journal", "template"] {
                let names = items.filter { $0.kind == kind }.map { $0.title.lowercased() }
                XCTAssertEqual(Set(names).count, names.count, "A \(kind) name repeats: \(names.sorted())")
            }
        }
    }

    /// The published server (JOURNAL_SERVER_EXECUTABLE) at a fixed loopback port between 18950 and 18959, so
    /// stopping, wiping and restoring it keeps the address a library knows.
    @MainActor
    final class DisposableServer {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SyncRecovery-" + UUID().uuidString)
        private(set) var data: URL
        let port: UInt16
        private let executable: URL
        private var process: Process?
        var address: String { "http://127.0.0.1:\(port)" }

        init() throws {
            executable = URL(
                fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["JOURNAL_SERVER_EXECUTABLE"]))
            data = root.appendingPathComponent("data")
            port = try XCTUnwrap((18950...18959).first(where: Self.isFree), "No free port between 18950 and 18959")
        }
        private static func isFree(_ port: UInt16) -> Bool {
            let handle = socket(AF_INET, SOCK_STREAM, 0)
            defer { close(handle) }
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            return withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(handle, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                }
            }
        }
        func start() async throws {
            let process = Process()
            process.executableURL = executable
            process.environment = [
                "Journal__DataDirectory": data.path, "ASPNETCORE_URLS": address, "DOTNET_EnableDiagnostics": "0",
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            self.process = process
            for _ in 0..<150 {
                if (try? await ServerClient(address: address).status()) != nil { return }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            XCTFail("The server didn't start")
        }
        func stop() {
            guard let process else { return }
            process.terminate()
            process.waitUntilExit()
            self.process = nil
        }
        /// Stops the server, removes its data folder and starts it again, waiting for a setup code.
        func wipe() async throws {
            stop()
            try FileManager.default.removeItem(at: data)
            try await start()
        }
        /// Restores `backup` into a new data folder, as an administrator would, and starts the server on it.
        func restore(_ backup: URL) async throws {
            stop()
            data = root.appendingPathComponent("restored-" + UUID().uuidString)
            try run("--restore", backup.path, "--Journal:DataDirectory=\(data.path)")
            try await start()
        }
        func setupCode() throws -> String {
            try String(contentsOf: data.appendingPathComponent("setup-code"), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        /// Runs a maintenance command, such as --backup, against this server's data folder.
        func run(_ arguments: String...) throws {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = ["Journal__DataDirectory": data.path, "DOTNET_EnableDiagnostics": "0"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, "\(arguments.first ?? "") failed")
        }
    }
#endif
