#if os(macOS)
    import JournalCore
    import XCTest

    @testable import Journal

    /// A Mac library connected to the server earlier builds ran stops syncing once, keeps everything, and explains why;
    /// it never stops a connection again, and no other server is affected
    /// (docs/design/client-only-mac-lists-markdown-2026-10-05.md §1.2).
    @MainActor final class FormerMacServerTests: XCTestCase {
        private func library(connectedTo address: String) async throws -> URL {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Former-" + UUID().uuidString)
            let model = AppModel(directory: directory)
            await model.start()
            let account = try XCTUnwrap(model.configuration?.connectionKeyID)
            let keyAccount = model.configuration?.keyID
            addTeardownBlock {
                for name in [account, keyAccount].compactMap({ $0 }) { try? Keychain.remove(name) }
                try? FileManager.default.removeItem(at: directory)
            }
            try connect(model, to: address)
            try await model.store?.close()
            try Data("{\"version\":1,\"port\":46371,\"enabled\":true}".utf8).write(
                to: directory.appendingPathComponent(FormerMacServer.settingsName))
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("local-server-data"), withIntermediateDirectories: true)
            return directory
        }

        private func connect(_ model: AppModel, to address: String) throws {
            let connection = SyncConnection(address: address, deviceID: UUID(), token: "synthetic-token")
            let account = try XCTUnwrap(model.configuration?.connectionKeyID)
            try Keychain.write(JournalCoding.encoder().encode(connection), account: account)
            model.configuration?.stoppedSyncingWithFormerMacServer = nil
            try model.persistConfiguration()
        }

        private func open(_ directory: URL) async -> AppModel {
            let model = AppModel(directory: directory)
            await model.load()
            addTeardownBlock { @MainActor in try? await model.store?.close() }
            return model
        }

        func testALibraryOnTheFormerServerStopsSyncingOnceAndKeepsItsFiles() async throws {
            let directory = try await library(connectedTo: FormerMacServer.address)

            let first = await open(directory)
            XCTAssertNotNil(first.store, "The library opens")
            XCTAssertNil(first.connection)
            XCTAssertEqual(first.configuration?.stoppedSyncingWithFormerMacServer, true)
            for name in [FormerMacServer.settingsName, "local-server-data", FormerMacServer.markerName] {
                XCTAssertTrue(
                    FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path), name)
            }

            // Reconnecting to the same address, as the recovery steps allow, is never undone.
            try connect(first, to: FormerMacServer.address)
            try await first.store?.close()
            let second = await open(directory)
            XCTAssertEqual(second.connection?.address, FormerMacServer.address)
            XCTAssertNil(second.configuration?.stoppedSyncingWithFormerMacServer)
        }

        func testAnotherServerOnThisMacIsLeftAlone() async throws {
            let directory = try await library(connectedTo: "http://127.0.0.1:8080")
            let model = await open(directory)
            XCTAssertEqual(model.connection?.address, "http://127.0.0.1:8080")
            XCTAssertNil(model.configuration?.stoppedSyncingWithFormerMacServer)
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent(FormerMacServer.markerName).path),
                "Checked once, so a later connection to the former address isn't stopped either")
        }
    }
#endif
