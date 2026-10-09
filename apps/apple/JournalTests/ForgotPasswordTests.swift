import JournalCore
import XCTest

@testable import Journal

/// “Forgot Password?” in Change Password (docs/design/1-1-encryption-and-passwords.md §4): journals that exist only on
/// this device keep the same key under a new master password, and Check Your Password is gone.
@MainActor
final class ForgotPasswordTests: XCTestCase {
    private let password = "a long enough master password"

    private func library() async throws -> (AppModel, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Forgot-" + UUID().uuidString)
        let model = AppModel(directory: directory)
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            if let account = model.configuration?.keyID { try? Keychain.remove(account) }
            try? FileManager.default.removeItem(at: directory)
        }
        await model.start(password: password)
        XCTAssertNil(model.error)
        return (model, directory)
    }

    func testANewPasswordProtectsTheSameJournalsAndItsArchives() async throws {
        let (model, directory) = try await library()
        await model.newEntry()
        var entry = try XCTUnwrap(model.draft)
        entry.title = "Written before the new password"
        model.updateDraft(entry)
        let saved = await model.finishPendingSave()
        XCTAssertTrue(saved)
        let key = try XCTUnwrap(model.masterKey)
        let new = "a different long password"

        // Only just after the device owner authenticated.
        do {
            try await model.setPasswordWithoutCurrent(new)
            XCTFail("A new password needs the device owner first.")
        } catch {}
        model.passwordResetAuthorizedAt = Date()
        try await model.setPasswordWithoutCurrent(new)
        let envelope = try XCTUnwrap(model.configuration?.recovery)
        XCTAssertEqual(
            try VaultCrypto.recover(envelope, phrase: new).0, key, "The same key, so nothing is re-encrypted.")
        XCTAssertThrowsError(try VaultCrypto.recover(envelope, phrase: password))
        let stored = try await model.store?.item(entry.id)
        XCTAssertEqual(stored?.title, entry.title)
        do {
            try await model.setPasswordWithoutCurrent("yet another long password")
            XCTFail("One authentication sets one password.")
        } catch {}

        // An archive made now opens with the new password.
        let archive = try await model.prepareArchive()
        let restored = try await VaultArchive.restore(
            from: archive, to: directory.appendingPathComponent("restored"), phrase: new)
        XCTAssertEqual(restored.key, key)
        let restoredEntry = try await restored.store.item(entry.id)
        XCTAssertEqual(restoredEntry?.title, entry.title)
        try await restored.store.close()
    }

    /// The authorization lasts five minutes.
    func testAnAuthorizationExpiresAfterFiveMinutes() async throws {
        let (model, _) = try await library()
        let before = try XCTUnwrap(model.configuration?.recovery.wrappedKey)
        model.passwordResetAuthorizedAt = Date().addingTimeInterval(-301)
        do {
            try await model.setPasswordWithoutCurrent("a different long password")
            XCTFail("The device owner authenticated too long ago.")
        } catch {}
        XCTAssertEqual(model.configuration?.recovery.wrappedKey, before)
    }

    func testANewPasswordIsNeverSetForJournalsOnAServer() async throws {
        let (model, _) = try await library()
        XCTAssertTrue(model.canSetPasswordWithoutCurrent)
        model.connection = SyncConnection(address: "https://journal.example", deviceID: UUID(), token: "token")
        XCTAssertFalse(model.canSetPasswordWithoutCurrent)
        XCTAssertFalse(model.offersForgotPassword)
        model.passwordResetAuthorizedAt = Date()
        let before = try XCTUnwrap(model.configuration?.recovery.wrappedKey)
        do {
            try await model.setPasswordWithoutCurrent("a different long password")
            XCTFail("The server keeps its own copy of the password.")
        } catch {}
        XCTAssertEqual(model.configuration?.recovery.wrappedKey, before)
    }

    /// Nothing writes the one-time check any more, and a file an earlier version saved with it still opens.
    func testNoPasswordCheckIsWrittenAndAnEarlierFilesValueIsIgnored() async throws {
        let (model, directory) = try await library()
        let written = try String(contentsOf: model.configURL, encoding: .utf8)
        XCTAssertFalse(written.contains("passwordChecked"))
        let earlier = written.replacingOccurrences(
            of: "{", with: "{\"passwordChecked\":false,", options: [],
            range: written.startIndex..<written.index(after: written.startIndex))
        try earlier.write(to: model.configURL, atomically: true, encoding: .utf8)
        try await model.store?.close()
        let reopened = AppModel(directory: directory)
        await reopened.load()
        XCTAssertNil(reopened.libraryProblem)
        XCTAssertNotNil(reopened.store)
        try await reopened.store?.close()
    }

    /// Existing short passwords keep unlocking, signing in and opening archives: nothing raised the minimum for them.
    func testAnExistingShortPasswordStillUnlocksTheJournals() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Short-" + UUID().uuidString)
        let model = AppModel(directory: directory)
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            if let account = model.configuration?.keyID { try? Keychain.remove(account) }
            try? FileManager.default.removeItem(at: directory)
        }
        await model.start(password: "a")
        XCTAssertNil(model.error)
        let key = try XCTUnwrap(model.masterKey)
        let envelope = try XCTUnwrap(model.configuration?.recovery)
        XCTAssertEqual(try VaultCrypto.recover(envelope, phrase: "a").0, key)
        let archive = try await model.prepareArchive()
        let restored = try await VaultArchive.restore(
            from: archive, to: directory.appendingPathComponent("restored"), phrase: "a")
        XCTAssertEqual(restored.key, key)
        try await restored.store.close()
    }
}
