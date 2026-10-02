# Recently Deleted: swipe to delete permanently, and its footer — 2026-09-30

Status: bug fix, no interface change beyond the swipe behavior. Amends pre-release-ui-2026-09-27.md §1.

## Swipe, Delete, Cancel

Owner report: swiping a row in Recently Deleted, tapping Delete and then Cancel in the alert hid the row.

Cause: the trailing swipe action used the destructive role. On iOS a destructive swipe action removes its row at once, expecting the item to be gone; here it only asks with the Delete Permanently alert, so after Cancel the row stayed hidden until the list was rebuilt.

Fix: the swipe action keeps its label ("Delete"), trash symbol and red tint but no longer has the destructive role, so the row stays until the item is actually deleted. Cancel closes the alert and the swipe, and the row stays. The confirmation alert is unchanged. Swipe to delete in a journal (to Recently Deleted, no alert) keeps the destructive role and its at-once removal. The Mac (context menu, Delete and ⌘⌫) and deleted journals (Delete Permanently… in the journal's page) never removed anything before the alert.

## Footer

Owner report: the screen had two paragraphs saying items stay until deleted permanently.

The current app shows one footer, "Items stay here until you delete them permanently.", under the last section present (Journals, Templates or the last month of entries). Checked on an iPhone 17 simulator with deleted journals, templates and entries, entries across four months, after Cancel, after deleting the last month's only entry and after restoring. Build 6 contains only this sentence. The second paragraph matches the row "Deleted items stay here until you restore or permanently delete them." that pre-release-ui-2026-09-27.md removed, so the device most likely runs an older build. No copy change: the footer stays as the owner approved it (owner-decisions-2026-09-25.md).

## Tests

- iOS UI `testCancelledSwipeKeepsDeletedRowVisible`: swipe, Delete, Cancel; the row is still visible. It failed before the fix.
- The existing `EntryActionsUITests.testSwipeDeletionRemovesOnlyThatRow` still passes (swipe to delete in a journal).
