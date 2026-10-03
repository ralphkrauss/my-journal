import Foundation
import JournalCore
import os

/// Image descriptions typed in a sheet that a lock closed before they could be saved. They're kept in memory, saved
/// after the next unlock if the entry is still open, and otherwise shown again when the sheet next opens for that
/// entry (docs/design/mac-inactivity-lock-2026-10-03.md, "Locking without losing writing").
struct UnsavedImageDescriptions {
    let entryID: UUID
    let expectedImages: [DocumentBlock]
    let descriptions: [UUID: String]
}

extension AppModel {
    /// Before any lock that the person or the system starts while the journals are open (Lock My Journal, the
    /// screen locking, sleep, inactivity): saves the open entry, then typed content in open sheets, waiting no longer
    /// than `limit`, so a save that hangs can't keep the journals unlocked. Saving continues after locking, and
    /// anything still unsaved stays in memory.
    func saveBeforeLocking(within limit: Duration = .seconds(2)) async {
        // Locking cancels an action being committed, or a library being replaced, at once, as it always has; the
        // open entry is then saved right after locking, and a sheet's descriptions are kept.
        guard !committingMutation, !vaultReplacement else { return }
        let saves = Array(savesBeforeLocking.values)
        let saving = Task { @MainActor in
            _ = await self.flush()
            for save in saves { await save() }
        }
        await Self.wait(for: saving, atMost: limit)
    }

    /// Waits for `task` to finish, or for `limit`, whichever comes first; the task itself continues.
    private static func wait(for task: Task<Void, Never>, atMost limit: Duration) async {
        let timeout = Task { try? await Task.sleep(for: limit) }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = ResumeOnce(continuation)
            Task {
                await task.value
                once.resume()
            }
            Task {
                await timeout.value
                once.resume()
            }
        }
        timeout.cancel()
    }

    /// Keeps descriptions a lock closed before they were saved.
    func keepUnsavedImageDescriptions(_ kept: UnsavedImageDescriptions) {
        unsavedImageDescriptions = kept
    }

    /// The kept descriptions for `entryID` whose images are still `images`, handed to the sheet that shows them again.
    func takeUnsavedImageDescriptions(for entryID: UUID, images: [DocumentBlock]) -> [UUID: String]? {
        guard let kept = unsavedImageDescriptions, kept.entryID == entryID,
            kept.expectedImages.map(\.id) == images.map(\.id)
        else { return nil }
        unsavedImageDescriptions = nil
        return kept.descriptions
    }

    /// After unlocking: saves kept descriptions while their entry is open. If that isn't possible, they stay for the
    /// sheet to show again.
    func retryUnsavedImageDescriptions() async {
        guard let kept = unsavedImageDescriptions, canDescribeImages(in: kept.entryID) else { return }
        do {
            _ = try await saveImageDescriptions(
                entryID: kept.entryID, expectedImages: kept.expectedImages, descriptions: kept.descriptions)
            if unsavedImageDescriptions?.entryID == kept.entryID { unsavedImageDescriptions = nil }
        } catch {
            Logger(subsystem: "org.privatejournal", category: "image-descriptions").error(
                "Kept image descriptions couldn’t be saved after unlocking; they stay for the sheet.")
        }
    }
}

/// Resumes a continuation once, whichever caller comes first.
private final class ResumeOnce: Sendable {
    private let continuation: OSAllocatedUnfairLock<CheckedContinuation<Void, Never>?>
    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = OSAllocatedUnfairLock(initialState: continuation)
    }
    func resume() {
        let waiting = continuation.withLock { state -> CheckedContinuation<Void, Never>? in
            let current = state
            state = nil
            return current
        }
        waiting?.resume()
    }
}
