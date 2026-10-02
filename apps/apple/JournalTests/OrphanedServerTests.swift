#if os(macOS)
    import Darwin
    import JournalCore
    import XCTest

    @testable import Journal

    /// A server left running when My Journal crashed or was force quit is stopped at the next launch. A process that
    /// merely reuses the server's process ID, or a server whose app is still open, must never be stopped.
    @MainActor
    final class OrphanedServerTests: XCTestCase {
        func testOnlyAServerWhoseAppEndedIsStopped() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "OrphanedServer-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let record = directory.appendingPathComponent("local-server-process.json")
            let model = AppModel(directory: directory)
            addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
            func spawn() throws -> Process {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sleep")
                process.arguments = ["60"]
                try process.run()
                let pid = process.processIdentifier
                addTeardownBlock { kill(pid, SIGKILL) }
                return process
            }
            func identity(_ process: Process) throws -> ProcessIdentity {
                try XCTUnwrap(ProcessIdentity(running: process.processIdentifier))
            }
            func launch(with server: ProcessIdentity, owner: ProcessIdentity) async throws {
                try ServerProcessRecord(server: server, owner: owner).write(to: record)
                await LocalServerController(model: model).resumeIfNeeded()
            }
            let thisApp = try XCTUnwrap(ProcessIdentity(running: getpid()))
            var endedApp = thisApp
            endedApp.startSeconds -= 1

            let unrelated = try spawn()
            var reusedID = try identity(unrelated)
            reusedID.startSeconds -= 1
            try await launch(with: reusedID, owner: endedApp)
            XCTAssertTrue(unrelated.isRunning, "A process that reuses the server's ID isn't the server.")
            XCTAssertFalse(FileManager.default.fileExists(atPath: record.path))

            let owned = try spawn()
            try await launch(with: identity(owned), owner: thisApp)
            XCTAssertTrue(owned.isRunning, "The app that started this server is still open.")

            let orphan = try spawn()
            try await launch(with: identity(orphan), owner: endedApp)
            for _ in 0..<50 where orphan.isRunning { try await Task.sleep(nanoseconds: 20_000_000) }
            XCTAssertFalse(orphan.isRunning)
            XCTAssertFalse(FileManager.default.fileExists(atPath: record.path))
        }
    }
#endif
