# Sync Now feedback and the Done checkmark

Proposal for independent review before implementation. Owner reports, 2026-09-30:

1. "The 'Sync Now' button doesn't do anything. Maybe in the background, but it should indicate that it actually did something when I press it (in the Sync tab in Settings)."
2. On iPhone the Done checkmark stays visible after writing ends. Title and body should work the same way: the checkmark closes the keyboard and returns to reading. The owner later reproduced it on an iPhone 16 Pro (iOS 26, Release build): "when I am typing with the keyboard open, and then I press the checkmark in the corner, the keyboard disappears properly but the checkmark stays in place".

## 1. Sync Now

### What happens today

Sync Now (iPhone/iPad: Settings > Sync > Server; Mac: Settings > Sync, both for a remote server and for "This Mac") calls `AppModel.sync(retryingRefused: true)` in a detached task. It does sync. Nothing changes on screen because:

- there is no in-progress state: the button stays enabled and looks the same;
- there is no completion state: nothing records when the last sync succeeded, and automatic sync runs every 3 seconds, so a manual sync almost never has anything new to show;
- `sync()` returns early and silently while a save has failed, while the library is being replaced (connecting, turning on encryption) or while locked;
- a connection failure shows the system's text (for example "The Internet connection appears to be offline."), which doesn't say that writing is safe on this device.

### Design

Follows the pattern of Settings > iCloud Backup and Mail's "Updated Just Now": a quiet status value next to the action, no alert on success.

**iPhone and iPad** (Settings > Sync, section "Server"), rows in order:

1. Server address (unchanged).
2. "Sign In…" when encryption was turned on elsewhere (unchanged).
3. **Last Synced** row (`LabeledContent`), value in secondary text:
   - while a sync started with Sync Now runs: "Syncing…" with a small system spinner after it;
   - after a successful sync less than a minute ago: "Just now";
   - within the last day: the system's relative date, starting with a capital: "5 minutes ago", "2 hours ago";
   - older: the date and time: "Yesterday at 21:14", "12 Sept at 08:03" (with the year when it isn't this year). It refreshes every minute while shown.
   - The time is stored on this device for the current connection (UserDefaults, keyed to the library folder and the connection), so it survives relaunching; connecting to another server clears it. It's written at most once a minute and when the app goes to the background. The row is hidden until the first successful sync with this connection.
4. **Sync Now** button. Label never changes. Disabled while a sync started with Sync Now runs, while the library is being replaced, and while a save has failed.

Footer (existing position, one message at a time, in this priority):

- Save failed: "Syncing is paused until your changes are saved. Choose Try Again in the entry." (The entry's own notice says "Not Saved" with Try Again.)
- Sync failed because the server can't be reached (`URLError` notConnectedToInternet, networkConnectionLost, cannotFindHost, cannotConnectToHost, dnsLookupFailed or timedOut; not cancelled, and TLS/certificate errors keep their text): "Couldn’t connect to the server. Your changes are saved on this device." For a `.ts.net` address: "Couldn’t connect to the server. If it uses Tailscale, turn on Tailscale on this device. Your changes are saved on this device." (Same wording and rule as ConnectionFlow.) This text replaces the system text everywhere `syncError` is shown, including the toolbar's Sync Status menu.
- Any other existing `syncError` text, unchanged (refused entry or image, encryption turned on elsewhere, etc.).
- No server: "Your journals are saved on this device." (unchanged).

**Mac** (Settings > Sync, section "Server"): the same Last Synced row and rules, placed directly above Sync Now in both the "This Mac" (Running) and the remote-server layouts. The error remains secondary text below the buttons, as today; "The server is running, but couldn’t sync. Choose Sync Now to try again." stays.

### States

| Situation | Last Synced | Sync Now | Footer / message |
| --- | --- | --- | --- |
| Tap, nothing new to sync | "Syncing…" + spinner, then "Just now" | disabled, then enabled | none |
| Tap while an automatic sync runs | "Syncing…" until the requested sync finishes (the engine runs it after the current one) | disabled | none |
| Tap while offline | "Syncing…", then the previous value (or hidden) | enabled again | "Couldn’t connect to the server…" |
| One entry or image refused, rest synced | "Just now" | enabled | the existing item message |
| Save failed | unchanged | disabled | "Syncing is paused until your changes are saved…" |
| Connecting / turning on encryption | unchanged | disabled | unchanged |
| Settings closed during a sync | sync continues; reopening shows the current state | | |

The spinner stays at least 0.5 seconds so a fast sync reads as a completed action rather than a flicker. Automatic syncs never show "Syncing…" (they would flicker every 3 seconds); they only update Last Synced.

### Accessibility

- Last Synced reads as one element: "Last Synced, Just now" / "Last Synced, Syncing…". The spinner is hidden from VoiceOver.
- When a sync started with Sync Now finishes, VoiceOver announces "Synced" or the footer message (UIAccessibility / NSAccessibility announcement, medium priority, as LocalServerSection already does for server phases). Automatic syncs announce nothing.
- The disabled Sync Now is announced as dimmed; keyboard and Full Keyboard Access reach it as today. Dynamic Type: the value wraps below the label at accessibility sizes (standard `LabeledContent`). Reduce Motion: system spinner only, no other animation.

### Implementation notes

- A small `SyncActivity` observable object on AppModel holds `lastSynced` and `syncingNow`, so the per-3-second timestamp update refreshes only the Sync settings, not every view observing AppModel.
- `AppModel.syncNow()` guards against a second run, sets `syncingNow`, awaits `sync(retryingRefused: true)`, keeps the 0.5 s minimum, clears `syncingNow` in every path (including early returns and cancellation), then announces. Both Settings panes and the toolbar Sync Status "Try Again" use it.
- `sync()` sets `lastSynced` only when it ran and `failure == nil` (a refused entry or image still counts as synced; its message shows). Its silent guard returns (locked, library being replaced, save failed, no engine) count as "not run" and never show "Just now".

## 2. The Done checkmark (iPhone and iPad)

### Intended behavior

The checkmark (accessibility label "Done") shows only while the title, the body or a table cell has keyboard focus. Tapping it from any of them ends editing: the keyboard closes, the checkmark disappears, and the entry is in reading mode with the bottom bar (Formatting, Insert Image, View Source) shown. Title and body behave identically. Writing is saved as now (quietly). VoiceOver focus moves to the entry's text. With a hardware keyboard the same applies (there is no on-screen keyboard to close).

### What goes wrong (reproduced on an iPhone 17 simulator, iOS 26.5, Debug build)

The checkmark and the bottom bar are both driven by `EditorActions.editing`, which is true while a set of registered editors (title coordinator, body coordinator, table cells) is non-empty. Registrations are added in `textViewDidBeginEditing` and removed in `textViewDidEndEditing`.

1. **Done from the title moves the keyboard to the body.** The title view is hosted inside the body's text view (the header scrolls with the text). When the title resigns, UIKit hands first responder to the enclosing text view: lldb shows `-[UIResponder resignFirstResponder]` calling `-[UITextView becomeFirstResponder]` on the body from the Done action. Result: the caret jumps to the body, the keyboard stays (or the accessory stays with a hardware keyboard) and the checkmark remains. Reproduced every time, with on-screen and hardware keyboards. Tapping Done a second time works.
2. **A registration outlives its editor, so the checkmark sticks.** Focus the title, tap Back, open the entry again: the checkmark is already shown with no keyboard, the bottom bar is missing, and tapping the checkmark does nothing. Tapping the body, typing and tapping Done then closes the keyboard but leaves the checkmark: exactly the owner's report. The editor that was removed while focused never delivered `textViewDidEndEditing` (its coordinator was gone by the time UIKit resigned it), and `EditorActions` lives for the whole window, so the stale entry keeps `editing` true until the app is relaunched. That explains why it came and went for the owner. The same should happen whenever a focused title or body is removed: Back, choosing another entry on iPad, deleting or moving the open entry, locking, the editor being replaced by rotation or a size change.

### Design

- **Focus tracking follows the views.** `EditorActions` registers the focused view itself (weakly), not the coordinator. A registration ends on `didEndEditing`, when the title or body editor is dismantled or leaves its window, and on every Done; a deallocated view drops out. A lost `didEndEditing` can no longer leave the checkmark behind.
- **Done doesn't hand focus to the body.** Done sets a flag for the duration of its action; while it's set the body refuses to become first responder. Tapping from the title to the body and Return (Next) in the title still move focus.
- **Done ends editing explicitly.** It resigns whichever registered view is focused (title, body or table cell), then forgets every registration, so it always ends in reading mode even if UIKit reported nothing. It still waits for the pending save in the background, as now. VoiceOver: `.layoutChanged` is posted with the view that was being edited.
- Table cells register their grid view the same way.
- No copy changes. Mac is unaffected (no checkmark there).

### Tests

UI tests (iPhone 17, the CI device), in the writing workflow class, each asserting that the "Finish Editing" button no longer exists, no keyboard is shown and the bottom bar's "Insert Image" button is hittable:

1. Type in the title, tap Done; the body must not have focus afterwards.
2. Focus the title, go Back, reopen the entry: no checkmark and the bottom bar is shown; then type in the body and tap Done.

Both fail on the current build as shown above. Manual verification on my own simulator in Debug and a Release build, with the on-screen and a hardware keyboard, plus iPad: title focused, then select another entry. No unit test for EditorActions: the UI tests cover the behavior, and the pruning depends on UIKit's responder state.

Sync Now: extend MergeUITests (which already reaches Sync Now against a local test server) to tap Sync Now and wait for "Last Synced" to read "Just now". One model test with the existing fake sync server: a failing Sync Now clears the in-progress state and doesn't update Last Synced; a second tap while the first runs doesn't start another sync. Screenshots on iPhone, iPad and Mac, light and dark, largest text, for Syncing…, Just now and the offline message.

## Review outcome (2026-09-30)

An independent review approved the design with changes; no further round was required. Applied above:

1. The body refuses focus only while Done's action runs; tapping and Return (Next) still move focus from the title.
2. Last Synced is stored per device and connection (answers the open question), written at most once a minute or on backgrounding, cleared when connecting to another server.
3. Relative dates only within a day, then date and time.
4. The offline error codes are listed; `.cancelled` is excluded, TLS errors keep their text, wording matches ConnectionFlow.
5. Success is `failure == nil`; the silent guard returns count as not run.
6. VoiceOver `.layoutChanged` after Done.
7. Manual regression checks: Done during marked text and dictation, title to body by tapping, View Source while not editing (NativeEditor and NativeTableIntegration read `actions.editing`; the keyboard must not come up), the Format panel and popover, Add Link and the image picker (checkmark and bottom bar return with focus), rotation through `interruptedWriting`, iPad with a hardware keyboard and Full Keyboard Access.
8. Table cells use view-based registration too.

Adopted optional suggestions: weak references with forgetting on dismantle and Done rather than first-responder checks; UI test 1 merged into test 3; the save-failure footer says what to do; LabeledContent with a small ProgressView on the Mac; check that nothing on the Mac depends on `EditorActions.editing` in a changed way.

## Implementation verification (2026-09-30)

On a dedicated iPhone 17 simulator (iOS 26.5), Debug and Release builds: the new WritingWorkflowUITests test (Done from the title; Back with the title focused, reopen, type in the body, Done) and MobileParityUITests pass. A temporary check (removed afterwards) confirmed: tapping from title to body and Return (Next) still move focus; View Source and View Preview while reading bring up neither the keyboard nor the checkmark; the checkmark stays while the Format panel shows and focus returns after Close; after Add Link and the photo picker are cancelled, the checkmark matches focus and the reading bar shows; rotating while writing keeps writing, and Done then reads. MergeUITests (disposable server) shows "Syncing…" with the spinner, then "Last Synced: Just now". Mac unit tests, including SyncNowTests, pass team-signed; strict swift-format, SwiftLint and the hygiene lane pass.

Not verified: Done during Japanese marked text and during dictation (the simulator's XCUITest typing didn't produce a composition, and dictation isn't available), iPad with a hardware keyboard and Full Keyboard Access, and the offline footer and Mac Settings on screen (the offline message is covered by SyncNowTests).
