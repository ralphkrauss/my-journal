import JournalCore
import XCTest

@testable import Journal

/// After a connection fails, Try Again reuses the copy of the library it made. Writing done in the meantime would
/// be missing from that copy and disappear once it's connected, so nothing may change the library until the copy
/// is used or discarded.
@MainActor
final class ConnectionRetryTests: XCTestCase {
    func testLibraryCannotChangeWhileAFailedConnectionWaitsForTryAgain() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Retry-" + UUID().uuidString)
        let model = AppModel(directory: directory)
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            if let account = model.configuration?.keyID { try? Keychain.remove(account) }
            try? FileManager.default.removeItem(at: directory)
        }
        await model.start(password: "a long enough master password")
        await model.newEntry()
        let entry = try XCTUnwrap(model.draft)
        let envelope = try XCTUnwrap(model.configuration?.recovery)
        let key = try XCTUnwrap(model.masterKey)
        let encoded = try JournalCoding.encoder().encode(envelope)
        let status = Data(#"{"protocolVersion":1,"initialized":true}"#.utf8)
        // The server hands out the envelope but can't sync, so connecting fails after the copy is made.
        let server = try await FakeJournalServer { request in
            switch request.path {
            case "/v1/recovery": return (200, encoded)
            case "/v1/status": return (200, status)
            default: return (503, Data("{}".utf8))
            }
        }
        func folders() throws -> Set<String> {
            Set(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("vault-") })
        }
        let before = try folders()

        do {
            try await model.installPairedVault(
                address: server.address, key: key, token: "token", deviceID: UUID(), uploadLocal: true,
                recoveryVersion: envelope.formatVersion, shown: RecoveryParameters(envelope))
            XCTFail("The fake server can't sync.")
        } catch {}
        XCTAssertEqual(try folders().count, before.count + 1, "The copy is kept for Try Again.")
        XCTAssertFalse(model.canEdit)
        // The Mac window explains the pause, which only Try Again or Cancel ends.
        XCTAssertEqual(model.serverConnectionPause, .waitingForRetry)
        #if os(macOS)
            if ProcessInfo.processInfo.environment["JOURNAL_CAPTURE_DESIGN"] == "1",
                let preview = await NativeTestPreview.capture(
                    ConnectionPauseNotice().environmentObject(model), name: "Writing paused", width: 640, height: 80)
            {
                add(preview)
            }
        #endif
        var edited = entry
        edited.title = "Written after the failed attempt"
        model.updateDraft(edited)
        XCTAssertEqual(model.draft?.title, entry.title)
        let saved = await model.finishPendingSave()
        XCTAssertTrue(saved)
        let stored = try await model.store?.item(entry.id)
        XCTAssertEqual(stored?.title, entry.title)

        // Cancelling discards the copy, and writing continues in the library itself.
        await model.discardStagedVault()
        XCTAssertEqual(try folders(), before)
        XCTAssertTrue(model.canEdit)
        XCTAssertNil(model.serverConnectionPause)
        model.updateDraft(edited)
        XCTAssertEqual(model.draft?.title, edited.title)
    }
}
