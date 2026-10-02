# Review fixes: 29 September 2026

This responds to the owner's full review (`artifacts/full-review-2026-09-29/review.md`). Each finding was checked independently with a regression test written to assert the correct behaviour. Every test failed on the unchanged code before the fix.

| # | Finding | Verified by | Fix |
|---|---|---|---|
| 1 | App Lock shown as on although not saved | `AppLockTests.testUnsavedAppLockChangesLeaveTheSavedSettingInForce`: an unwritable configuration | Changes are published only after they're saved, and restored if saving fails. The sheet stays open with the error. |
| 2 | Recovering a missing device key left sync inactive | `MissingDeviceKeyTests.testRecoveryResumesTheSavedServerConnection` | Loading and recovery share one step that opens the library, which also restores the saved connection. |
| 3 | Quit could wait behind another sync | `SynchronizationGateTests` (JournalCore) | Waiting for the sync gate can now be cancelled. A cancelled waiter leaves the queue at once, and a gate released while a waiter is being cancelled passes to the next one. |
| 4 | Version History kept no ordinary edits | `VersionCheckpointTests` (JournalCore) | Automatic local checkpoints: see [version-checkpoints.md](version-checkpoints.md). |
| 5 | Relaunch forgot the entry open in All Entries | `JournalNavigationTests.testAllEntriesSelectionReopensTheEntryInItsJournal` | The open entry's own journal and the entry are remembered. |
| 6 | Long or multiline Mac titles were clipped | `MacTitleSizingTests`, and checked by hand on the Mac | The title wraps and grows to fit its text. The fixed 32 pt height is gone. |
| 7 | Zooming cleared the selection | `EditorChangeTests.testZoomKeepsTheSelectionAndUndo`, and checked by hand on the Mac | The selection is reset only when a different entry opens, on both platforms. |
| 8 | Add Link with an uppercase scheme inserted nothing | `LinkInsertionTests.testAddLinkInsertsAddressesWhoseSchemeIsNotLowercase` | One shared check, `LinkAddress.url`, for the sheet, both editors and table cells. |
| 9 | No Redo after undoing a deletion | `DeletionFlowTests.testUndoAndRedoDeleteKeepTheSameEntryAndContent` | Undo and redo register each other. A failed step removes that entry's remaining steps. |
| 10 | Change Password didn't explain its minimum | — | Obsolete: the owner removed the 12-character minimum. Change is disabled only while a field is empty or the passwords don't match, and a mismatch is explained. |
| — | Empty `if model.saveFailure { }` branches | — | Removed. They were leftovers from the removed Export Entry feature. |
| — | Image Descriptions disabled for an unselected row | `ImageDescriptionLifecycleTests.testRowOffersImageDescriptionsWithoutBeingTheOpenEntry` | Availability now depends on the clicked row's own entry. |
| — | Weak empty-journal state | Checked by hand on the Mac and iPhone | See below. |

## Empty journal state (design gate)

**Proposal.** The list shows "No Entries" with a New Entry action, and the editor column is blank while the list is empty. The independent design review approved it with these required changes, all of which were adopted:

- **Button:** a default-style "New Entry" button, with no ellipsis and no shortcut in the copy.
- **Availability:** the button appears only when `canCreateEntry` is true, the same condition that enables ⌘N.
- **Templates:** no "New Template" button, because the app has no such command.
- **Editor column:** "Select an Entry" appears only when the visible list has entries and none is selected.

## App Lock sheet

The sheet now keeps a failed save on screen. The error goes in the existing note (Mac) or footer (iOS), and VoiceOver announces it. It isn't shown as a main-window alert, which can't appear over Settings on iOS. The design review outcome is recorded below.

**Design review:** approved with required changes, all adopted:

- **Copy for each action instead of the raw file error:**
  - "App Lock couldn’t be turned on. Try again."
  - "Your PIN couldn’t be changed. Your current PIN still works."
  - "App Lock couldn’t be turned off. Try again."
- **No silent failure:** a failure always shows its message.
- **iOS:** errors are red, as on the Mac.
- **Clearing:** the message clears when any field changes.
- **No main-window alert:** the sheet's actions no longer set it. The Unlock with Face ID / Touch ID switch in Settings reports its own failure in the same plain words.
