#if os(macOS)
    import Foundation
    import JournalCore
    import SwiftUI
    import os

    @MainActor
    final class LocalServerController: ObservableObject {
        enum Phase: String {
            case stopped = "Stopped", starting = "Starting Server…", running = "Running", stopping = "Stopping Server…"
        }
        private struct Configuration: Codable {
            var version = 1
            var port: UInt16 = 46371
            var enabled = true
        }
        private struct Readiness: Decodable {
            let status: String
            let instanceId: String?
        }
        @Published private(set) var phase: Phase = .stopped
        @Published private(set) var hasSetup = false
        @Published var error: String?
        private weak var model: AppModel?
        private var configuration: Configuration?
        private var invalidConfiguration = false
        private var process: Process?
        private var log: FileHandle?
        private var runID: UUID?
        private var autoAttempted = false
        private var settingUp = false
        private var stoppingOrphan = false
        private var shutdownTask: Task<Bool, Never>?
        private let root: URL
        private let executableOverride: URL?
        private let initialPort: UInt16
        private var settingsFile: URL { root.appendingPathComponent("local-server.json") }
        private var processFile: URL { root.appendingPathComponent("local-server-process.json") }
        private var dataDirectory: URL { root.appendingPathComponent("local-server-data", isDirectory: true) }
        var address: String { "http://127.0.0.1:\(configuration?.port ?? initialPort)" }
        var busy: Bool { settingUp || stoppingOrphan || phase == .starting || phase == .stopping }
        var isConfigured: Bool { model?.connection?.address == address }

        init(model: AppModel, executable: URL? = nil, port: UInt16 = 46371) {
            self.model = model
            root = model.directory
            executableOverride = executable
            initialPort = port
            if FileManager.default.fileExists(atPath: settingsFile.path) {
                do {
                    let saved = try JournalCoding.decoder().decode(
                        Configuration.self, from: Data(contentsOf: settingsFile))
                    guard saved.version == 1, saved.port > 1024 else { throw JournalError.invalidData }
                    configuration = saved
                    hasSetup = true
                } catch {
                    invalidConfiguration = true
                    self.error =
                        "The server settings couldn’t be opened. You can keep writing and export your journals from Settings."
                }
            }
        }
        func resumeIfNeeded() async {
            await stopOrphanedServer()
            guard !autoAttempted, configuration?.enabled == true, isConfigured else { return }
            autoAttempted = true
            await start()
        }
        /// Stops a server this app started that was left running when the app ended without stopping it.
        private func stopOrphanedServer() async {
            guard process == nil, !stoppingOrphan, let record = ServerProcessRecord.read(from: processFile) else {
                return
            }
            stoppingOrphan = true
            defer { stoppingOrphan = false }
            if record.isOrphaned {
                let stopped = await ProcessStopping.stop(record.server.pid, grace: 10) { record.server.isRunning }
                guard stopped else { return }
            } else if record.server.isRunning {
                // Its app is still open; that copy of My Journal stops it.
                return
            }
            try? FileManager.default.removeItem(at: processFile)
        }
        func setup(phrase: String) async throws {
            guard !busy, !invalidConfiguration, let model, !model.locked,
                model.configuration?.recoveryConfirmed == true, model.connection == nil || isConfigured
            else { throw JournalError.locked }
            settingUp = true
            defer { settingUp = false }
            guard await model.finishPendingSave() else {
                throw JournalError.server("Save your changes before starting the server.")
            }
            try Task.checkCancellation()
            guard !model.locked else { throw JournalError.locked }
            if configuration == nil { try save(Configuration(port: initialPort)) }
            error = nil
            do {
                try await startProcess()
                try Task.checkCancellation()
                guard !model.locked else { throw JournalError.locked }
                let client = try ServerClient(address: address)
                if !isConfigured {
                    if try await client.status().initialized {
                        let credential =
                            model.configuration?.requiresPassword == false
                            ? try await LocalRecoveryCode.create(executable: executable(), directory: dataDirectory)
                            : phrase
                        try Task.checkCancellation()
                        try await model.recoverServer(
                            address: address, phrase: credential, uploadLocal: true, recoveringOwnedServer: true)
                    } else {
                        let code = try String(
                            contentsOf: dataDirectory.appendingPathComponent("setup-code"), encoding: .utf8)
                        try await model.initializeServer(
                            address: address, code: code, phrase: phrase, uploadLocal: true)
                    }
                }
                // The durable device connection is the setup commit. Later UI failures cannot undo it.
                guard isConfigured else { throw JournalError.invalidData }
            } catch {
                if !isConfigured {
                    _ = await stopProcess()
                    // Nothing here can retry the same connection, so editing must not stay paused for it.
                    await model.discardStagedVault()
                }
                throw error
            }
        }
        func requestSetupCancellation() {
            guard !isConfigured, phase != .stopping, let identifier = runID else { return }
            shutdownTask = Task {
                guard runID == identifier else { return true }
                return await stopProcess()
            }
        }
        func cancelUncommittedSetup() async {
            if !isConfigured { _ = await stopProcess() }
        }
        func start() async {
            guard !busy, !invalidConfiguration, isConfigured else { return }
            do {
                var next = configuration ?? Configuration(port: initialPort)
                next.enabled = true
                try save(next)
                error = nil
                try await startProcess()
            } catch { self.error = message(error) }
        }
        func stop() async {
            guard !busy else { return }
            do {
                if var next = configuration {
                    next.enabled = false
                    try save(next)
                }
                _ = await stopProcess()
            } catch { self.error = "Couldn’t save the server settings. Try again." }
        }
        @discardableResult func stopForQuit() async -> Bool { await stopProcess(grace: 5) }
        private func executable() throws -> URL {
            if let executableOverride { return executableOverride }
            let bundled = Bundle.main.bundleURL.appendingPathComponent(
                "Contents/Helpers/JournalServer.app/Contents/MacOS/Journal.Api")
            // The sandbox lets the app start only a server inside its own bundle.
            if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
            throw JournalError.server(
                "The server is missing from this copy of My Journal. Reinstall My Journal and try again.")
        }
        private func startProcess() async throws {
            if phase == .running, process?.isRunning == true { return }
            guard process?.isRunning != true else {
                throw JournalError.server("The server is still stopping. Try again in a moment.")
            }
            guard #available(macOS 14, *) else {
                throw JournalError.server(
                    "Running a server on this Mac requires macOS 14 or later. You can still connect to a server.")
            }
            let binary = try executable()
            try FileManager.default.createDirectory(
                at: dataDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let logFile = root.appendingPathComponent("local-server.log")
            try Data().write(to: logFile, options: .atomic)
            let output = try FileHandle(forWritingTo: logFile)
            let child = Process()
            let identifier = UUID()
            child.executableURL = binary
            var environment = ProcessInfo.processInfo.environment
            environment["Journal__DataDirectory"] = dataDirectory.path
            environment["Journal__InstanceId"] = identifier.uuidString
            environment["ASPNETCORE_URLS"] = address
            environment["DOTNET_EnableDiagnostics"] = "0"
            environment["Logging__LogLevel__Default"] = "Warning"
            // Security events (devices added or revoked, refused setup and recovery attempts) are kept in the log.
            environment["Logging__LogLevel__Journal.Api.Security.AuditLog"] = "Information"
            // The server exits when this app is gone, even if the app couldn't stop it.
            environment["Journal__ParentProcessId"] = String(ProcessInfo.processInfo.processIdentifier)
            child.environment = environment
            child.standardOutput = output
            child.standardError = output
            child.terminationHandler = { [weak self] _ in
                Task { @MainActor in self?.exited(identifier) }
            }
            phase = .starting
            process = child
            log = output
            runID = identifier
            do {
                try child.run()
                recordProcess(child)
                let ready = try await waitForReadiness(child, identifier: identifier)
                guard ready, child.isRunning, runID == identifier, phase == .starting else {
                    throw JournalError.server(
                        "Couldn’t start the server. This server address may be in use. Quit another copy of My Journal if one is open, then try again."
                    )
                }
                phase = .running
            } catch {
                _ = await stopProcess()
                throw error
            }
        }
        private func waitForReadiness(_ child: Process, identifier: UUID) async throws -> Bool {
            guard let url = URL(string: address + "/ready") else { throw JournalError.invalidData }
            for _ in 0..<60 {
                try Task.checkCancellation()
                guard child.isRunning, runID == identifier else { return false }
                var request = URLRequest(url: url)
                request.timeoutInterval = 0.5
                if let (data, response) = try? await URLSession.shared.data(for: request),
                    (response as? HTTPURLResponse)?.statusCode == 200,
                    let status = try? JournalCoding.decoder().decode(Readiness.self, from: data),
                    status.status == "ready", status.instanceId == identifier.uuidString
                {
                    return true
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            return false
        }
        /// Stops the server, forcing it if it hasn't stopped after `grace` seconds.
        private func stopProcess(grace: TimeInterval = 10) async -> Bool {
            guard let child = process, child.isRunning else {
                phase = .stopped
                process = nil
                runID = nil
                try? log?.close()
                log = nil
                return true
            }
            let stoppingID = runID
            phase = .stopping
            // Cancellation must not skip owned-child shutdown.
            if await ProcessStopping.stop(child.processIdentifier, grace: grace, isRunning: { child.isRunning }) {
                if let identifier = stoppingID { exited(identifier) }
                return true
            }
            error = "The server is taking longer to stop. Quit My Journal to try stopping it again."
            return false
        }
        private func recordProcess(_ child: Process) {
            guard let server = ProcessIdentity(running: child.processIdentifier),
                let owner = ProcessIdentity(running: getpid())
            else { return }
            do { try ServerProcessRecord(server: server, owner: owner).write(to: processFile) } catch {
                Logger(subsystem: "org.privatejournal", category: "local-server").error(
                    "Couldn’t record the server process.")
            }
        }
        private func exited(_ identifier: UUID) {
            guard runID == identifier else { return }
            let unexpected = phase == .running
            try? FileManager.default.removeItem(at: processFile)
            phase = .stopped
            process = nil
            runID = nil
            try? log?.close()
            log = nil
            if unexpected { error = "The server stopped. Start it again to continue syncing." }
        }
        private func save(_ value: Configuration) throws {
            try FileManager.default.createDirectory(
                at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JournalCoding.encoder().encode(value).write(to: settingsFile, options: .atomic)
            configuration = value
            hasSetup = true
        }
        private func message(_ error: Error) -> String {
            if case JournalError.server(let text) = error { return text }
            return "Couldn’t start the server. Try again."
        }
    }
#endif
