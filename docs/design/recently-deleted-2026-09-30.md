# Recently Deleted: swipe to delete permanently, and its footer — 2026-09-30

Status: bug fix, no interface change beyond the swipe behavior. Amends pre-release-ui-2026-09-27.md §1. The swipe part is amended by ios-delete-all-and-settings-2026-10-03.md §1: the swipe action is destructive again, and the row comes back explicitly on Cancel.

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

## Delete Permanently: the row leaves as a deleted entry's row does — 2026-10-03

Owner report: deleting an item permanently from Recently Deleted “kind of freezes and then poof it's gone without the animation”, unlike deleting an entry from a journal.

Cause: the row stayed until the deletion was stored and the whole library read again, then the list was rebuilt outside any animation. A deleted entry's row instead leaves the list in the same update as the Delete action, with the list's own removal animation, while the deletion is stored afterwards.

Intended behavior, the same mechanism as deleting an entry (`removeFromLists`/`hideInLists`): when Delete is chosen in the Delete Permanently alert, the entry's, template's or journal's row leaves Recently Deleted at once with the system list's removal animation. With Reduce Motion it is removed without animation, as other list changes are. If the deletion can't be stored (it changed meanwhile, or needs review), the row comes back and the existing message explains why. This covers the trailing swipe, the context menu and Delete Permanently… in the Entry Actions menu. From an open entry or deleted journal on iPhone, the page goes back to the list at once, as after Delete Entry, and the list shows without the row; it never appears there first. The alert and its copy are unchanged.

Review: an independent design reviewer approved with changes. Checked: the store work runs off the main thread (a 3,000-entry library spends about 70 ms on the main thread updating the list as the row leaves, in a Debug build on the simulator), and a refused deletion after the iPhone page has gone back leaves the person in the list with the alert, never reopening the page. Not adopted: animating a returning row and moving the Mac selection to the next row; rows restored after a failed deletion, and the Mac selection, behave as for Delete Entry today.
