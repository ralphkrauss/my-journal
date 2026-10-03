import CryptoKit
import JournalCore
import XCTest

@testable import Journal

/// Every lock saves writing first, including image descriptions typed in an open sheet, and keeps what it can't save
/// (docs/design/mac-inactivity-lock-2026-10-03.md, "Locking without losing writing").
@MainActor
final class LockSavingTests: XCTestCase {
    /// A new library with App Lock on and an open entry with one image.
    private func entryWithImage() async throws -> (AppModel, JournalItem, DocumentBlock) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LockSaving-" + UUID().uuidString)
        let model = AppModel(directory: root)
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            let account =
                "master-" + SHA256.hash(data: Data(root.path.utf8)).map { String(format: "%02x", $0) }.joined()
            try? Keychain.remove(account)
            try? FileManager.default.removeItem(at: root)
        }
        await model.start()
        model.confirmRecovery()
        await model.turnOnAppLockForTesting()
        await model.newEntry()
        var entry = try XCTUnwrap(model.draft)
        let picture = DocumentBlock(kind: "image", attachmentID: UUID(), mediaType: "image/png")
        entry.document = .init(blocks: [DocumentBlock(runs: [TextRun("A walk")]), picture])
        model.updateDraft(entry)
        let saved = await model.finishPendingSave()
        XCTAssertTrue(saved)
        return (model, try XCTUnwrap(model.draft), picture)
    }

    private func storedDescription(_ model: AppModel, _ entry: JournalItem) async throws -> String? {
        let store = try XCTUnwrap(model.store)
        let stored = try await store.item(entry.id)
        return stored?.document.imageBlocks.first?.imageDescription
    }

    /// Lock My Journal (⌃⌘L, Settings, the screen locking, sleep) runs the open sheet's save before the journals
    /// lock and close it, as Image Descriptions registers one.
    func testLockMyJournalSavesTypedImageDescriptionsFirst() async throws {
        let (model, entry, picture) = try await entryWithImage()
        var lockedWhenSaving: Bool?
        model.savesBeforeLocking[UUID()] = {
            lockedWhenSaving = model.locked
            _ = try? await model.saveImageDescriptions(
                entryID: entry.id, expectedImages: [picture], descriptions: [picture.id: "Beech trees in fog"])
        }

        await model.lock()
        XCTAssertTrue(model.locked)
        XCTAssertEqual(lockedWhenSaving, false, "Saved before locking.")
        let description = try await storedDescription(model, entry)
        XCTAssertEqual(description, "Beech trees in fog")
    }

    /// A save that hangs can't keep the journals unlocked: saving before a lock waits only for a moment.
    func testHangingSaveDoesntHoldTheLock() async throws {
        let (model, _, _) = try await entryWithImage()
        let release = AsyncStream<Void>.makeStream()
        model.savesBeforeLocking[UUID()] = {
            for await _ in release.stream { break }
        }
        let started = ContinuousClock.now
        await model.saveBeforeLocking(within: .milliseconds(100))
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(1))
        XCTAssertTrue(model.lockImmediately())
        release.continuation.finish()
    }

    /// Descriptions a lock closed before they could be saved, such as when iPhone leaves the app, stay in memory and
    /// are saved once the journals are unlocked.
    func testDescriptionsKeptByALockAreSavedAfterUnlocking() async throws {
        let (model, entry, picture) = try await entryWithImage()
        model.keepUnsavedImageDescriptions(
            UnsavedImageDescriptions(
                entryID: entry.id, expectedImages: [picture], descriptions: [picture.id: "A heron by the lake"]))
        XCTAssertTrue(model.lockImmediately())
        await model.saveWhileLocked()
        let whileLocked = try await storedDescription(model, entry)
        XCTAssertNil(whileLocked)

        await model.unlockForTesting()
        XCTAssertFalse(model.locked)
        let description = try await storedDescription(model, entry)
        XCTAssertEqual(description, "A heron by the lake")
        XCTAssertNil(model.unsavedImageDescriptions)
    }
}
