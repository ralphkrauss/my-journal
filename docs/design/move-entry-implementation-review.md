# Move Entry implementation source review

Date: 2026-09-20. Independent review of `MoveEntryView.swift`, `AppModel.moveEntry`, `JournalStore.moveEntry`, and RootView/SettingsView routing against the approved proposal/review. No implementation edits or independent test execution. No renders were supplied for this pass; interactive Mac/iOS inspection remains pending.

## Findings

1. **P2 — Duplicate detection includes the source journal.** `duplicateNames` groups all `model.journals`, although the selectable list contains only other destinations. This disables a unique destination solely because it shares the source's name, contrary to the explicitly approved fallback. Compute ambiguity among displayed destinations only. Continue disabling truly indistinguishable destination rows with the existing explanation.
2. **P2 — Failed-save recovery is not directly reachable in the move sheet.** When flushing fails, the sheet shows “Save your changes before moving this entry” and leaves Move as a retry, but offers no Export Entry action. The root's global save alert cannot be assumed to present over an active sheet. Add the existing lossless Export Entry recovery route within this failure state or demonstrate a reliably presented equivalent on both platforms. Preserve Cancel returning to the unchanged pinned draft. Avoid making the user infer that a failed save requires closing this sheet to locate their recovery action.

## Source matches

The sheet captures entry identity and closes if selection changes; native destination buttons expose the selected trait, unavailable selection is cleared with an announced error, and long names wrap. macOS uses a separate footer; iOS uses a native navigation toolbar. Core move validates live entry/destination and rejects unresolved conflicts within the database write, preserves identity/content, updates modification time, and queues the changed journal membership through the existing revision-aware save path. Model flushes first, freezes mutations during the move, switches to the destination with the moved entry selected, and does not throw a post-commit refresh failure back as a failed move. Manage Journals selects the Journals tab, while ordinary Settings preserves its current tab.

These are source observations, not proof of all timing and accessibility behavior. Verify lock racing the actor write, a destination disappearing while the sheet is open, keyboard focus after an error, a failed local save/export, and the actual iOS move/reopen path.

## Related iOS Settings refinement

**Approved before implementation:** wrap iOS Settings content in a native NavigationStack, use the inline title “Settings,” and place Done in the native confirmation-action toolbar. Keep the four existing tabs and macOS layout. A modal Settings sheet needs a reliably visible dismissal action; the existing unhosted toolbar does not establish that. This is a conventional navigation repair, not a new feature or consent change. Verify Done remains visible on each tab and returns to the same journal/entry; nested connection/archive/device sheets should retain their own dismissal scope.

## Failed-save refinement approval — 2026-09-20

Approved showing Export Entry… beside the inline local-save error, opening the existing EntryExportView as a nested native sheet. Move may retry the flush/move; Cancel returns to the retained draft. Export must neither clear saveFailure nor automatically continue the move. This reuses the already reviewed lossless recovery flow and resolves finding 2 once implemented and verified. Grouping ambiguity only among displayed destinations resolves finding 1 once implemented. No further design round is required for these changes.

## Offscreen Mac render inspection — 2026-09-20

Viewed `artifacts/move-entry-mac-previews/AC5B071A-7042-48EC-BD50-780E0BCA44CB.png`, an **offscreen native render** at 420×360 logical points, normal-size light mode, with one destination and no selection. The title, uncluttered destination list, separate native footer, Cancel, and disabled Move fit without clipping or overlap. The unselected state correctly avoids implying a destination has already been chosen. No additional explanatory copy or visual decoration is needed in this ordinary state.

This provides limited layout evidence only. The render does not establish that the row responds to input, that selected styling/checkmark appears, or that keyboard/VoiceOver interaction works. The desktop was not interactively inspected.

Source recheck confirms duplicate detection now groups `destinations`, resolving finding 1. The approved iOS Settings NavigationStack and confirmation-toolbar Done are present in source. Nested Export Entry recovery was still being added at this checkpoint, so finding 2 remains implementation-pending here. No new material issue was identified from this single Mac render. Empty/duplicate/error/selected states, enlarged text, dark mode, and iOS interaction remain outside its evidence.

## Actual iOS screenshot and final-source review — 2026-09-20

Viewed `artifacts/move-entry-ios-previews/AA1080E8-39A7-4F43-A08B-109DA884B2A9.png`, an actual iPhone simulator screenshot in normal-size light mode with Personal selected. Native Cancel/Move toolbar actions, inline title, readable destination row, and visible selection checkmark fit without clipping. **This selected-destination state is visually approved.** The parent reports passing interactive E2E through Settings > Journals > Create Work > Done, writing in Work, terminate/reopen, selecting Personal in Move Entry, move, another terminate/reopen of the exact entry, and export-picker launch. This reviewer inspected the screenshot and source, but did not independently run that E2E.

The nested Export Entry action is now present when the move has a local-save error; it uses the existing export sheet and dismisses on lock/entry change. This resolves original finding 2 in source. UUID-only writing-position persistence is present, ignores Templates/Recently Deleted, restores a matching live entry with fallback, and avoids replacing a retained draft during unlock. The ordinary relaunch/move path has the reported E2E evidence.

**P1 — Remaining lock/commit race can undo a committed move.** In `AppModel.moveEntry`, `store.moveEntry` can commit before the MainActor continuation resumes. If lock occurs then, `lock()` clears items and calls `flush()` on the retained old draft, whose journalID still points to the source. `flush` has no replacement-operation guard and can write that old membership back. The move continuation also exits at `guard !locked` before updating the retained draft, so unlock preserves the stale draft and a later flush can likewise undo the committed move. This contradicts the approved “a move committed before lock remains committed.” Serialize lock flushing with the move transaction and update retained, hidden draft metadata for a successful commit without exposing content. Do not discard a genuine unsaved draft as the repair. Add a targeted test pausing immediately around store commit, locking, unlocking, and reopening; the destination and same entry must persist.

No other new material issue was found in the pictured ordinary state. The Mac remains limited to the prior offscreen render; interactive Mac/VoiceOver, large text, duplicate/empty/error destinations, failed-save export, and the lock/commit race were not visually verified here. The newly identified race must be addressed before calling the move lifecycle complete.

## Lock/commit correction and regression review — 2026-09-20

Independently re-read `AppModel.flush`, `lock`, `moveEntry`, and the new owned `commitEntryMove` operation, together with `MoveLifecycleTests.testLockAfterMoveCommitCannotSaveOldJournalMembership`. No UI layout changed and this reviewer did not execute the test.

**The P1 lock/commit finding is resolved in source.** Lifecycle flush now awaits the owned move task before capturing the draft to save. Lock cancels that task, while a completed database operation still reconciles its moved entry into the retained draft and remembered selection before the task finishes. Reconciliation occurs even while the content is hidden by lock. The outer caller propagates cancellation to the owned task; a precommit cancellation can prevent the store write, while post-commit cancellation cannot leave stale source-journal metadata to be saved back. The mutation guard remains active through reconciliation/display refresh, and display failure still does not become a retryable move failure.

The deterministic regression exercises the actual SQLite move, signals that it committed, holds before returning its result for model reconciliation, and locks the model at that boundary. It then checks hidden-state retention, database membership, unlock, another flush, and a fresh model reopen with the same moved entry. This targets the identified failure mode rather than merely checking a mock call order. Cancellation may release the AsyncStream wait itself, but only after lock has set its state/canceled the operation, so the relevant post-commit boundary is still exercised.

No remaining demonstrated data-loss or reentrancy blocker was found in this correction. This closes the source finding; passing test execution remains the implementation task's validation responsibility. Previous rendered/interactive evidence limits remain unchanged, including interactive Mac, VoiceOver, large text, and failed-save export inspection.
