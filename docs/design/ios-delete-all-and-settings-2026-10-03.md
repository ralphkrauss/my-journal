# iOS: deletion motion, Delete All in Recently Deleted, Settings at the top left — 2026-10-03

Owner requests after build 12:

1. “On iOS both the delete animations for the main entries as well as the deleted entries is still not smooth. It doesn't feel native.”
2. “I want an extra action button to be able to permanently delete all deleted entries (clear it).”
3. “I want to split (again, on iOS) the New Journal button and the Settings button. The settings should be put in the top left corner, and the New Journal button staying in the top right corner.”

Amends `recently-deleted-2026-09-30.md` (swipe in Recently Deleted) and `owner-decisions-2026-09-25.md` §1 (Recently Deleted actions). The single-item Delete Permanently alert and its copy are unchanged.

## 1. Deletion motion

### What was measured

Build 12 (HEAD 3bd25c8) on the “Journal Test iPhone 17” simulator (iOS 26.5), recorded with `simctl io recordVideo`, converted to 60 fps and stepped frame by frame, with a per-frame difference timeline to find every separate movement. Compared with Reminders on the same simulator (Notes and Mail aren't installed on simulators): swipe ▸ Delete on a list, which also asks before deleting.

**Entries list in a journal** (swipe then Delete, full swipe, context menu ▸ Delete Entry, Delete Entry from inside the entry):

- Swipe and full swipe: one movement. The red action widens over the row, the row closes and the rows below move up together, about 0.4 s, no cross-fade, no second movement, no header or count change. Row identities are stable (`ForEach` over entry IDs, month sections keyed by month).
- Context menu: the lifted row and the menu leave together and the rows below close the gap in the same movement.
- From inside the entry: the menu closes and the page goes back at once; the list underneath is already without the row (recorded decision, `recently-deleted-2026-09-30.md`).
- Main thread (Release build, 600-entry library, run-loop timing and `sample`): the update that starts the row's removal keeps the main thread busy about 30 ms, almost all inside SwiftUI's own destructive swipe handling and the collection view's batch update; the app's own list work is about 1.5 ms and doesn't grow noticeably with the library. Storing the deletion and reading the library back follows about 40 ms later and costs about 10–15 ms. Visible as one to three frames without movement just after the finger lifts; the same pause exists for any SwiftUI list. No app-side double update, navigation pop or redraw was found to interrupt the movement.

So the entries list already follows the standard motion on the simulator. The one thing the app controls during it is the read-back: the update after the deletion is stored lands about 40 ms into a 0.4 s movement and costs 10–15 ms on the main thread, more on a 120 Hz phone, and on a phone connected to a server the sync it starts adds further updates. The simulator recordings can't show a device-only hitch.

**Recently Deleted** (swipe ▸ Delete ▸ alert ▸ Delete, full swipe, context menu, from inside the entry):

1. The swipe's Delete has no destructive role (`recently-deleted-2026-09-30.md`), so tapping it first slides the row back closed;
2. then the alert appears;
3. after Delete, the row stays fully visible while the alert fades (about 0.35 s): SwiftUI runs an alert button's action only once the alert has closed;
4. only then does the row close.

The person sees the row come back, sit there, and then vanish: three separate steps instead of the row going. In Reminders, Delete widens over the row and stays there while the alert asks, and the row goes after the answer (step 3's wait after the alert also happens there). SwiftUI's `swipeActions` can't keep a swipe open behind an alert.

### Proposed behaviour

**Read-back after the movement (all deletions).** The deletion is still stored at once. Reading the library back, updating the counts and lists, and the sync that follows wait until the row's removal animation has finished (0.45 s; no wait with Reduce Motion). This applies to Delete Entry and Delete Template in any list, swipe and context menu, Delete Permanently and Delete All. When several rows are deleted in quick succession, the wait restarts with each one, so the library is read once the last row has finished moving. The row is listed again only by the read-back, or when the deletion fails, so it never flashes back while waiting; a sync from elsewhere during the wait can't bring it back either, because the item is already stored as deleted. Locking during the wait leaves the stored deletion as it is.

**Recently Deleted swipe.** The trailing swipe action becomes destructive, as in a journal's list: **Delete** (trash, red) and a full swipe take the row away at once, in the same single movement as deleting an entry in a journal. Then the unchanged alert asks:

- **Delete** stores the deletion; nothing else moves.
- **Cancel** brings the row back to its place with the list's insertion animation.

*Trade-off, chosen knowingly:* Apple's own order (Reminders; Mail with Ask Before Deleting) keeps the swiped row open while the alert asks. SwiftUI can't do that, so the choice is between the row sliding back closed before the alert (today) and the row leaving before the alert with Cancel bringing it back. The second gives the single movement the owner asked for; the alert names the item, so it stays clear what is being deleted.

**When the row leaves and returns** (protects against the build-6 bug, a row left hidden after Cancel):

- The swipe action hides the row (`hideInLists`) synchronously inside its own closure, in the same update as the swipe, before anything is awaited, and asks for the deletion with a note that its row was removed.
- The row returns (`showInLists`, animated unless Reduce Motion) on every path that doesn't delete it: Cancel; a failed check (the open entry can't be saved, changes need review, a newer format, it changed, it's missing); locking while checking or while the alert is open; and a second swipe on another row before the first row's alert appeared, which first returns the first row.
- After Delete, the row stays out while the deletion is stored and comes back only if storing fails, with the existing message.

**Between the swipe and the alert** the row is gone and nothing else shows; the check normally takes a few milliseconds (it first finishes saving an open entry, which is already saved in Recently Deleted). No progress indicator.

**VoiceOver:** the row's custom actions are unchanged (“Delete”, “Restore”). After Cancel, VoiceOver focus moves to the returned row.

The context menu, Entry Actions ▸ Delete Permanently… inside an entry, deleted journals and the Mac are unchanged: their rows leave after the alert, as in Reminders.

**Reduce Motion:** the row leaves and returns without animation, as other list changes do.

**Device check:** the phone itself isn't used in this work. If deleting in a journal still doesn't feel right on the phone after this build, a screen recording from the phone is needed to find what the simulator doesn't show.

## 2. Delete All in Recently Deleted (iPhone and iPad)

Notes, Photos, Files and Voice Memos put the bulk action on the Recently Deleted screen itself, behind a confirmation that states it can't be undone. Photos and Files reach it through Select; this app's Recently Deleted has no selection mode, and adding one only for this would be a larger change than requested. A single toolbar button fits the existing screen.

### Layout

- **iPhone:** Recently Deleted's navigation bar gets a text button **Delete All** at the top right (primary action placement). The back button stays at the top left; the bottom bar (search, New Entry) is unchanged.
- **iPad:** the same button in the entries column's navigation bar when Recently Deleted is shown (shared toolbar code).
- **Mac:** see §4.

The button is shown only while Recently Deleted contains something and no search is active (with a search, “All” would be ambiguous between the results and everything). It isn't disabled-but-visible: the empty state already reads “No Deleted Items”.

### Interaction and copy

Tapping **Delete All** first checks what can be deleted, as Delete Permanently does before its alert: it finishes saving an open entry, then checks each journal, template and entry against the stored library (changes that need review, a newer format). The button can't be tapped again while this runs.

What the alert covers is exactly what was checked and can be deleted: those journals (each with its entries), templates and entries. Anything that arrives in Recently Deleted while the alert is open or while deleting runs (from sync, another device or Undo) is not deleted. A deleted journal that can't be deleted keeps all its entries too, so restoring it never leaves it with entries missing.

**Alert** (standard alert):

- Exactly one item, or one journal with its entries: the single-item alert unchanged: “Delete “Title” Permanently?” / “You can’t undo this. Copies may remain in archives, backups, and server history.” (journal with entries: “Delete “Work” and Its Entries Permanently?” / “Its 3 entries are deleted too. You can’t undo this. …”).
- One kind of item: title “Delete 3 Entries Permanently?”, “Delete 2 Templates Permanently?”, “Delete 2 Journals Permanently?”; message “You can’t undo this. Copies may remain in archives, backups, and server history.”
- Mixed kinds: title “Delete 17 Items Permanently?”; message “Includes 2 journals, 1 template, and 14 entries. You can’t undo this. Copies may remain in archives, backups, and server history.” Counts that are zero are left out; the list uses the system list format. Entries are every entry Recently Deleted lists that is deleted, including a deleted journal's entries, which the screen lists as rows.
- When some items can't be deleted, a sentence goes after “Includes …” (when present) and before “You can’t undo this.”, for example “Includes 2 journals, 1 template, and 11 entries. 3 items have changes that need review and will stay in Recently Deleted. You can’t undo this. Copies may remain in archives, backups, and server history.”:
  - “1 item has changes that need review and will stay in Recently Deleted.” / “3 items have changes that need review and will stay in Recently Deleted.”
  - “1 item needs a newer version of My Journal and will stay in Recently Deleted.” / “3 items need a newer version of My Journal and will stay in Recently Deleted.”
  - Mixed reasons: “3 items can’t be deleted yet and will stay in Recently Deleted.”
  - The counted items in the title are only those that will be deleted.
- **Buttons:** **Delete** (destructive), **Cancel** (cancel role), as in the single-item alert.

When nothing can be deleted, no confirmation: an alert titled “Items Can’t Be Deleted” (one item: “Item Can’t Be Deleted”), button **OK**, says “These items have changes that need review before they can be deleted.”, “Update My Journal to delete these items.” or, for mixed reasons, “These items can’t be deleted yet.” (one item: the single-item messages, “This has changes that need review before it can be deleted.” / “Update My Journal to delete this.”).

After **Delete**, every row being deleted leaves at once with the list's removal animation (none with Reduce Motion); rows that stay remain. With nothing left, “No Deleted Items” shows and the button disappears. Entries deleted with their journal aren't deleted again and never count as failures. Each checked item is then deleted with the existing permanent-deletion operation (checked again inside its own transaction, marked deleted and queued for sync, so the server and other devices receive the same deletions as for single items), journals first. Saving the open entry and the check happen once; the library is read once at the end, after the removal animation. The work runs in the store, off the main thread. If My Journal is quit part way, the items not yet deleted are still in Recently Deleted on the next launch; nothing is lost. The open entry or template, if it was among them (iPad), closes as after Delete Permanently.

### States

- **Empty:** no button.
- **Searching:** no button.
- **Checking:** the button is disabled until the alert appears.
- **Offline / not connected:** deleting works the same; the deletions are stored and sync when the connection returns. Nothing extra is shown.
- **Some items changed between the alert and deleting** (from another device): the others are deleted; those rows come back and an alert says, title “1 Item Couldn’t Be Deleted” / “3 Items Couldn’t Be Deleted”, message “It changed since you chose to delete it. It’s still in Recently Deleted.” / “They changed since you chose to delete them. They’re still in Recently Deleted.”, button **OK**.
- **Open entry can't be saved first:** the existing message (“Save your entry before reviewing these changes.”) and no alert.
- **Locked while checking or while the alert is open:** the alert closes; nothing is deleted. Locked while deleting: what was already deleted stays deleted, the rest comes back; no message over the lock screen.
- **Deleted but couldn't be shown:** “The items were deleted, but My Journal couldn’t update the view. Reopen My Journal to continue.”

### Accessibility

- The button is a text button in the default tint (not red, as in Notes and Photos), primary-action placement (not the prominent confirmation style); its label is its title, “Delete All”, and it scales with Dynamic Type like other bar buttons and stays reachable at accessibility sizes (stacked navigation is used there).
- After Delete All empties the list, VoiceOver finds “No Deleted Items”; no extra announcement.
- The alert is a standard alert: VoiceOver reads the title and message; the destructive button is marked destructive.
- No colour-only meaning; Increase Contrast and Reduce Transparency follow the system bar.

## 3. Settings at the top left of Journals (iPhone)

The iPhone journals screen (root of the stack) currently has New Journal and Settings side by side at the top right in one group (on iOS 26, one shared glass capsule).

### Layout

- **Top left:** Settings, icon only, symbol `gearshape`, accessibility label “Settings”.
- **Top right:** New Journal, icon only, symbol `folder.badge.plus`, accessibility label “New Journal”.
- Large title “Journals”, the list and the bottom bar (search, New Entry and its options) are unchanged.
- The same applies wherever the stacked layout is used: iPhone in any orientation, and iPad at accessibility text sizes.

### iPad (regular width, split view)

Unchanged: Settings stays the last row of the sidebar and New Journal stays in the sidebar's toolbar, matching the Mac (owner decision: Settings at the bottom of the sidebar). The sidebar's leading edge already holds the system's sidebar toggle, so a gear there would crowd it. With many journals the Settings row scrolls with the list, as on the Mac; that is expected.

### Accessibility

Two separate toolbar items (`.topBarLeading` for Settings, `.primaryAction` for New Journal), so iOS 26 draws two glass buttons rather than one shared capsule. Both have labels and show their names in the large-content viewer when held at accessibility sizes (standard bar buttons). VoiceOver reads the bar first, then the large title: Settings, New Journal, Journals (heading), the list, the bottom bar.

## Tests

- Unit (real isolated store):
  - Delete All deletes every journal (with its entries), template and entry it checked, the rows leave at once, each deletion is queued for sync, and entries deleted with their journal aren't reported as failures;
  - two quick deletions: neither row is listed while waiting for the read-back, both are in Recently Deleted after it;
  - an item that can't be deleted (changes to review) is left out of the confirmation and stays listed;
  - a deleted journal that can't be deleted keeps its entries;
  - an item that arrives in Recently Deleted after the check isn't deleted;
  - the alert's counting and wording rules (one item, one kind, mixed kinds, zero counts left out, items that stay).
- UI: Delete All is shown with items and hidden when empty; Cancel keeps everything; Delete empties the list and the button goes; swipe ▸ Cancel in Recently Deleted brings the row back (existing test, now with the destructive role); Settings is at the top left and New Journal at the top right of Journals, and both open.
- The second-swipe-before-the-alert path depends on timing a UI test can't control (the check takes milliseconds); it is covered by the same return-the-row code as Cancel and checked by reading the code.

## Review

First review (independent design reviewer, before implementation): **revise and re-review** sections 1 and 2; section 3 approved with optional notes.

Adopted: read-back and sync after the removal animation (1.1); the trade-off recorded and every path that returns a swiped row listed (1.2, 1.3); VoiceOver focus back on a returned row (1.4); the gap before the alert stated (1.5); Delete All checks before its alert, covers exactly what it checked, keeps a journal's entries with it, names the reason items stay, uses its own alert for items that changed meanwhile, and states what happens on quit (2.1–2.5); default tint and primary-action placement (2.6); **Delete** in every alert and the single-item alert for one item (2.7); “Includes …” wording (2.8); disabled while checking (2.9); VoiceOver after emptying (2.10); separate toolbar items and the corrected VoiceOver order (3.1, 3.2); the iPad Settings row scrolling with the list (3.3); added tests (T1).

Re-review (same reviewer, revised sections 1 and 2): **approve with changes**, no further review needed. Adopted: one read-back after the last of several quick deletions (1.1); rows listed again only by the read-back (1.2) with a unit test (1.3); entries deleted with their journal aren't deleted again or reported (2.1); the order of the alert's sentences (2.2); a title for the nothing-can-be-deleted alert (2.3). Not adopted: moving the return-the-row logic into the model for a unit test (1.4), and a progress indicator during the check (2.4); the button is disabled while checking. Reported to the owner as the reviewer asked (1.5): the entries-list change was checked only on the simulator.

Not adopted in the first review: a test for the second swipe before the alert (timing a UI test can't control; see Tests). Raised for the owner, not changed: New Entry stays in Recently Deleted's bottom bar (2.11), which an earlier decision chose so New Entry works from every screen.

## Implementation record

Checked on the “Journal Test iPhone 17” simulator (iOS 26.5), Debug build, with recordings stepped at 60 fps and screenshots in light and dark appearance at the default and largest accessibility text size.

- **Recently Deleted swipe:** Delete widens over the row and the row closes in one movement while the alert appears; after Delete in the alert nothing else moves. After Cancel, the alert fades and the row is inserted back in its place with the list's insertion animation (it starts once the alert has closed, because the alert's buttons act only then).
- **Entries list:** unchanged movement; the read-back after storing now happens after the movement (about 0.45 s), and two quick full swipes read back once, after the second.
- **Context menu and inside an entry in Recently Deleted:** unchanged; the row leaves after the alert closes, as in Reminders.
- **Delete All:** the button sits at the top right of Recently Deleted's bar in the default tint; the alert reads, for example, “Delete 3 Items Permanently?” / “Includes 1 journal and 2 entries. You can’t undo this. Copies may remain in archives, backups, and server history.” After Delete, the rows fade out together and “No Deleted Items” appears; the button goes. At the largest text size the system alert scrolls and stacks its buttons; the bar buttons keep the bar's size, as system bar buttons do.
- **Journals (iPhone):** Settings (gear) at the top left and New Journal at the top right, each its own glass button, in light and dark appearance and at the largest text size.
- **Back swipe during a push:** with Settings at the top left, `MobileParityUITests` failed in 5 of 6 runs (6 of 6 passed with the old toolbar): its back swipe arrived while the entry's page was still sliding in, and iOS ignores a back swipe until a push has finished. Recorded push and pop movements from Journals showed no more stalled frames with the new toolbar than with the old one. The test now waits until the page has stopped moving before it swipes (4 of 4 passed).
- The deletion prompts are attached outside the lock screen switch, so locking with the alert open still returns a swiped row.

Not checked here: iPad (only the iPhone test simulator was used in this work; the iPad's Delete All uses the same toolbar code in the entries column, and its Settings row is unchanged), VoiceOver focus after Cancel and after Delete All, and the phone itself. The Mac has no Delete All yet: its list toolbar is AppKit and needs its own layout.

## 4. Delete All on the Mac

Owner, after approving the iOS behaviour: “add delete all to the mac too.” Same check, alert, copy and deletion as §2 (`DeleteAllPrompt`, `AppModel.reviewDeleteAll` / `permanentlyDeleteAll`); this section decides only where the command lives on the Mac and how its states look there.

### Native references

- **Finder.** The Trash window has an **Empty** button at the trailing end of a header above the files, and *Finder ▸ Empty Trash…* (⇧⌘⌫, with a confirmation; ⌥ skips it). The button is the location's own action, shown only in the Trash; the menu item names its object because it works from anywhere.
- **Mail.** *Mailbox ▸ Erase Deleted Items* (a submenu per account), also in the Trash mailbox's context menu; it confirms with a sheet that says it can't be undone.
- **Photos (Mac).** Recently Deleted shows a text button **Delete All** in the toolbar while that album is shown; it confirms with a sheet.
- **Notes (Mac).** Recently Deleted has no bulk button; items are selected and deleted.
- **This window.** An `NSSplitViewController` with an app-owned `NSToolbar` whose sections follow the column dividers (mac-window-appkit.md §3): over the list, the two-line title (“Recently Deleted” / “5 items”), a flexible space and Journal Actions (“…”, which in Recently Deleted holds only New Journal…). Mac toolbars here are icon-only, and the toolbar isn't customizable.

### Placement

1. **A header at the top of Recently Deleted's list**, as the header of Finder's Trash, shown only while Recently Deleted is the collection in the list:
   - Leading: “Items stay here until you delete them permanently.” in the secondary text colour, subheadline size, wrapping (two lines at the list's 360-pt minimum), never truncated. On the Mac this sentence moves here from the list's footer, so it appears once; iOS keeps its footer.
   - Trailing: a standard small push button **Delete All…** (default tint, no icon), never truncated, centred on the text.
   - Horizontal padding matching the rows' text, about 7 pt above and below. The rows scroll under it: on macOS 26 a safe-area bar with the system's scroll-edge effect; on earlier versions an inset with the bar material and a hairline below.
   - It is in the list, not the toolbar, so the toolbar stays as designed (title, flexible space, ⋯) and it fits at every window width and with the sidebar hidden. In Editor Only it is hidden with the list.
   - Tooltip: “Permanently delete all items in Recently Deleted”; while a search keeps it disabled, “Clear the search to delete all items.” Accessibility label: its title (“Delete All, button”).
2. **Menu bar: File ▸ Delete All in Recently Deleted…**, ⇧⌘⌫, in its own group after Export Archive…. ⇧⌘⌫ is the shortcut Finder's Empty Trash… and Mail's Erase Deleted Items use for emptying deleted items, and no other command in the app uses it.
   - The title names its object because a menu item has no list beside it to give “All” a meaning, and the item stays in the File menu in every collection, disabled outside Recently Deleted. It is enabled only while Recently Deleted is the collection shown, so the person sees what they delete; unlike Finder's Empty Trash… it doesn't act from anywhere.
   - Not in the Edit menu: there it would sit beside Delete and Select All and read as “delete everything in this list” in every collection.
3. **Not added:** a toolbar button (it doesn't fit with the sidebar hidden, see Review), Delete All… in Journal Actions (a menu named for journals, and hard to find), and a context menu on the Recently Deleted sidebar row (it would act while another collection is shown, where the rows that leave aren't visible).

**Exceptions to existing rules, for the owner:**

- The owner's label is “Delete All…”. The header button uses it; the menu bar item says “Delete All in Recently Deleted…” for the reason above.
- iOS keeps “Delete All” without an ellipsis (§2): iOS bar buttons don't use one, and the Mac's ellipsis follows the Mac convention for a command that asks before acting (Finder's Empty Trash…). The two are different on purpose.
- On the Mac the footer sentence moves into the header; iOS is unchanged.

### States

| Situation | Header and its button | File menu item |
| --- | --- | --- |
| Another collection (a journal, All Entries, Templates, Unavailable Journals) | No header | Disabled |
| Recently Deleted with items, no search | Button enabled | Enabled |
| Recently Deleted empty (“No Deleted Items”) | Header shown, button disabled | Disabled |
| Recently Deleted while searching | Header shown, button disabled, search tooltip | Disabled |
| Checking after a click, until the alert appears | Disabled | Disabled |
| Alert open | Covered by the sheet (window-modal) | Disabled |
| Deleting, after Delete in the alert | Disabled | Disabled |
| Editor Only with Recently Deleted shown | Hidden with the list | Enabled when the rules above allow |
| Library opening or journals being replaced (connecting, turning on encryption) | Disabled | Disabled |
| Locked | Nothing shown | Disabled |
| Sidebar hidden, any window width | Unchanged | Unchanged |

Mac convention: an action that belongs to the place stays put and dims when it can't act (Finder's Empty), rather than appearing and disappearing as the list changes. This differs on purpose from iOS, where the bar button is hidden when empty or searching. While searching, “All” would be ambiguous between the results and everything, so it is disabled; clearing the search enables it.

The button and the menu item read the same state (one model property, also used by iOS), and both update in the same SwiftUI update that changes the selection, the search, or Recently Deleted's contents (a sync, Restore, Delete Permanently, Undo). Delete All's progress (idle, checking, asking, deleting) is kept in the model, not in the window, so the button, the menu item and every window see it: a second request while one is checking, asking or deleting is ignored, and never cancels a deletion that is running. Rows that are leaving don't count, so the button dims in the same update as the rows leave. Switching collections shows or hides the header with the list's content, without a separate animation.

### Interaction and copy

Clicking the button, choosing the menu item, or pressing ⇧⌘⌫ starts exactly the §2 flow: save the open entry, check every item, then the alert. The alert is SwiftUI's standard alert, which the Mac shows as a sheet on the window that asked (not app-modal), with §2's title and message unchanged, for example:

- “Delete 3 Entries Permanently?” / “You can’t undo this. Copies may remain in archives, backups, and server history.”
- “Delete 17 Items Permanently?” / “Includes 2 journals, 1 template, and 14 entries. You can’t undo this. Copies may remain in archives, backups, and server history.”
- One item: the single-item Delete Permanently alert.
- Nothing deletable: “Items Can’t Be Deleted” with **OK**; items that changed meanwhile: “3 Items Couldn’t Be Deleted” with **OK**.

Buttons **Cancel** and **Delete** (destructive, red). The alert has no default button, as the existing Delete Permanently alert: Return does nothing, so ⇧⌘⌫ followed by Return can't delete everything; Escape and ⌘. cancel. Kept on purpose for an irreversible bulk delete.

After **Delete**, every row being deleted leaves the list together with the list's own removal animation (none with Reduce Motion); the subtitle's count leaves out the rows that are leaving, so it becomes “No Items” in the same update, and the list shows “No Deleted Items” under the header, whose button is now disabled. If the open entry, template or deleted journal was among them, the editor shows its empty state, as after Delete Permanently. Rows that stay (changes to review, a newer format) remain listed.

### Keyboard and VoiceOver

- ⇧⌘⌫ from anywhere in the window (list, editor, search field) while the command is enabled.
- Where it is disabled (outside Recently Deleted), the key isn't taken by the menu, and in an entry's text it does what the text system does with it: delete to the start of the line, as ⌘⌫ does, undone with ⌘Z (the same in TextEdit and Notes). The app doesn't intercept a system text binding.
- With Full Keyboard Access, Tab reaches the header button before the list and Space presses it; without it, the button isn't in the Tab loop (standard Mac behaviour), and ⇧⌘⌫ and the File menu cover keyboard use.
- VoiceOver: in the list column, the header text, then “Delete All, button” (dimmed when disabled), then the rows; the text and the button stay separate elements. The sheet is read as an alert; the destructive button is marked destructive. After Delete, VoiceOver finds “No Deleted Items”; nothing is announced, as on iOS.
- Increase Contrast and Reduce Transparency follow the system bar material and divider.

### Tests

- Unit: the shared condition (one model property used by the header button, the menu item and iOS) is true for a non-empty Recently Deleted without a search and false for another collection, while searching, and once Delete All has emptied it; a second request while one is checking or deleting is ignored, and the running deletion still completes.
- Existing: the menu shortcut test fails on any duplicate key equivalent, so ⇧⌘⌫ must stay unique.
- The header's composition is routine UI and is checked by inspecting screenshots, not a unit test. The flow itself (check, alert copy, deleting exactly what was counted, sync queueing) is §2's and already covered by its unit tests.

### Review

First review (independent design reviewer, before implementation): **approve with changes**, re-review only if the narrow-window check moved Delete All out of the toolbar.

Agreed by the reviewer: present only in Recently Deleted and dimmed rather than hidden inside it (Finder's Empty), File ▸ Delete All in Recently Deleted… with ⇧⌘⌫ (Finder, Mail), no ⌥ variant without confirmation, not in the Edit menu.

Adopted from the first review: the exceptions to existing rules stated for the owner; Delete All's progress kept in the model, requests ignored while one is checking, asking or deleting, a Deleting state, and a unit test for it; the menu item's rule stated as it is; a narrow-window acceptance criterion; the default button checked and recorded; the count and the button follow the rows as they leave; the search tooltip; VoiceOver, list focus and ⇧⌘⌫ in the editor checked; no test of a click calling its closure. Not adopted: enabling the menu item whenever Recently Deleted has items, from any collection, with the Recently Deleted row's context menu. Deleting everything permanently should happen where the person sees the rows that go. Left for the owner if wanted.

The first proposal was a text button “Delete All…” in the toolbar over the list. Built and measured, it failed the narrow-window criterion: with the sidebar hidden, the list keeps its 360-pt minimum, and AppKit neither truncated the title nor used the overflow menu but pushed the list's toolbar section about 97 pt past the divider, over the editor. A trash symbol would still overrun by about 45 pt.

Re-review (same reviewer) of three alternatives: **approved, the list header** (this section), with no further review needed. Rejected: Delete All… only in Journal Actions (hard to find, in a menu named for journals) and a toolbar button that moves into a menu when the sidebar is hidden (the command would change place with the layout). The reviewer also corrected the editor ⇧⌘⌫ statement (it deletes to the start of the line where the command is disabled; accepted as standard text behaviour) and asked to keep the alert without a default button.

### Implementation record (Mac)

Checked in a team-signed Debug build of the Mac app with its own bundle identifier and a new library in a scratch data folder, driven from a test bundle hosted in the app (real window, toolbar, File menu and alert sheet; window images from the window server), in light and dark appearance, switching light → dark → light with the header showing.

- **Header:** in Recently Deleted, the sentence on the left and a small Delete All… on the right, aligned with the rows' text; the rows scroll under it with the macOS 26 scroll-edge effect. At the narrowest window (801 pt, sidebar hidden, list 360 pt) the sentence wraps to two lines and the button stays whole; the toolbar's list section keeps to its divider (title, ⋯). Not shown in a journal, All Entries or Templates. Empty: the header stays with the button dimmed above “No Deleted Items”, subtitle “No Items”. Searching: the button is dimmed.
- **Flow:** a real mouse click on the button checks, then shows the alert as a sheet on the window: “Delete 8 Items Permanently?” / “Includes 1 journal, 1 template, and 6 entries. You can’t undo this. Copies may remain in archives, backups, and server history.” Buttons Cancel (Escape) and Delete (destructive, red); no default button, so Return does nothing. Cancel keeps every item; Delete empties the list and the subtitle reads “No Items”.
- **Menu:** File ▸ Delete All in Recently Deleted… shows ⇧⌘⌫ and is enabled only in Recently Deleted with items and no search; disabled in other collections, while searching, while the alert is open and after Delete All. Choosing it opens the same sheet, and Delete there deletes everything. The menu follows the key window, as Show Editor Only does.
- **Editor:** in a journal, where the command is disabled, ⇧⌘⌫ deletes to the start of the line and ⌘Z restores it (standard text behaviour, as decided above).

Not checked here: the rows' removal movement (the screen was locked during these runs, and in that state even an ordinary Delete Entry showed no intermediate frames, so the captures can't show movement either way), ⇧⌘⌫ with the list focused and Escape from the keyboard (they need the app in front, which a locked screen prevents), VoiceOver order and Full Keyboard Access (the app's own accessibility tree doesn't include SwiftUI's elements without an assistive client), Increase Contrast and Reduce Transparency (system settings weren't changed), and two windows at once.

## Owner decisions (3 October 2026)

- The swiped row leaves before the confirmation alert and returns on Cancel. Accepted.
- On the Mac, File ▸ Delete All in Recently Deleted… works only while Recently Deleted is shown.
