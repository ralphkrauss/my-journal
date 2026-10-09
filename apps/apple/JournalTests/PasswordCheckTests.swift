import JournalCore
import SwiftUI
import XCTest

@testable import Journal

/// An archive is useless if the master password it needs was mistyped when the library was created. The one-time
/// check must recognize the right password, and “Forgot Password?” must keep the same journals readable with a new
/// one, never lose them.
@MainActor
final class PasswordCheckTests: XCTestCase {
    private let password = "a long enough master password"

    private func library() async throws -> (AppModel, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Check-" + UUID().uuidString)
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

    func testOnlyTheRightPasswordEndsTheCheckAndItIsRemembered() async throws {
        let (model, directory) = try await library()
        XCTAssertTrue(model.passwordCheckPending)
        if ProcessInfo.processInfo.environment["JOURNAL_CAPTURE_DESIGN"] == "1" {
            for (view, name) in [
                (AnyView(PasswordCheckView {}), "Check Your Password"),
                (
                    AnyView(
                        NavigationStack {
                            NewPasswordForm(cancel: {}, done: {})
                                #if os(iOS)
                                    .navigationBarTitleDisplayMode(.large)
                                #endif
                        }), "Set New Password"
                ),
                (AnyView(TemplateChooserView(entryID: nil)), "Use a Template sheet"),
            ] {
                if let preview = await NativeTestPreview.capture(
                    view.environmentObject(model), name: name, width: 440, height: 360)
                {
                    add(preview)
                }
            }
        }
        let wrong = try await model.checkPassword(password + " ")
        XCTAssertFalse(wrong)
        XCTAssertTrue(model.passwordCheckPending)
        let right = try await model.checkPassword(password)
        XCTAssertTrue(right)
        XCTAssertFalse(model.passwordCheckPending)
        try await model.store?.close()
        let reopened = AppModel(directory: directory)
        await reopened.load()
        XCTAssertFalse(reopened.passwordCheckPending, "The check is asked for only until it succeeds once.")
        try await reopened.store?.close()
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
        XCTAssertFalse(model.passwordCheckPending)
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

    func testANewPasswordIsNeverSetForJournalsOnAServer() async throws {
        let (model, _) = try await library()
        model.connection = SyncConnection(address: "https://journal.example", deviceID: UUID(), token: "token")
        XCTAssertFalse(model.passwordCheckPending, "Connecting needed the password.")
        XCTAssertFalse(model.canSetPasswordWithoutCurrent)
        model.passwordResetAuthorizedAt = Date()
        let before = try XCTUnwrap(model.configuration?.recovery.wrappedKey)
        do {
            try await model.setPasswordWithoutCurrent("a different long password")
            XCTFail("The server keeps its own copy of the password.")
        } catch {}
        XCTAssertEqual(model.configuration?.recovery.wrappedKey, before)
    }
}
