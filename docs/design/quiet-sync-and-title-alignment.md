# Quiet Sync Status and title alignment

Status: **reviewed by an independent design reviewer (approve with required changes, all applied; see
[quiet-sync-and-title-alignment-review.md](quiet-sync-and-title-alignment-review.md)). Implemented on 2026-10-02.**

Amends [sync-health-and-recovery.md](sync-health-and-recovery.md) §4.2 ("Toolbar and Sync Status") and its "Quiet" and
"Problems" rules.

## Owner requests (2026-10-02)

1. "while I'm typing I don't want this cloud icon to appear, it's distracting and it causes a layout shift. Sync should
   simply work in the background."
2. "the title and the body of an entry don't seem perfectly aligned (the letter starts on a different horizontal
   position). It's such a small difference that you can barely see it. but it seems that the title is slightly more to
   the left than the start of the body. They should simply align properly"

## 1. Sync Status shows only when the person must act

### Before

- Mac: Sync Status was a toolbar item between the trailing flexible space and Editor Only. It was inserted whenever a
  change waited to sync, which is after every pause in typing, and removed once the change was sent. Formatting and
  Insert Image sit between two flexible spaces, so each insertion moved them sideways by half the cloud's width.
- iPhone and iPad: Sync Status is a submenu at the end of the entry's … menu. The same rule decided when it was there;
  no toolbar button moved.

### Rule (owner decision 2026-10-02)

| Situation | Sync Status |
|---|---|
| Syncing normally, with or without changes waiting | not shown |
| Temporary (offline, can't reach, server busy), retrying by itself | not shown |
| Temporary, and changes have waited more than 24 hours while sync fails | shown |
| Server not set up, restored or replaced; device removed; sign-in needed; update or fix needed; unexpected; this device's data unreadable | shown |
| A record or image the server refused (its message says what to do: "Edit it to try again.") | shown |
| No server (this library doesn't sync) | not shown |

- When it shows, the symbol is always `exclamationmark.icloud`. The plain `icloud` symbol is no longer used.
- The menu is unchanged: the state's message, the state's single action, and Sync Settings….
- **Long wait** counts only while sync fails (the last sync failed), measured from Last Synced, or from the first
  failure when this connection hasn't synced yet. At launch, changes left from days ago therefore don't flash the mark
  before the first sync finishes. It's checked after every sync, which includes each automatic retry and the sync when
  the app becomes active.
- **No flicker.** Whether it shows changes only when a sync finishes. A Try Again that runs keeps it until the sync
  succeeds or the state changes.
- **Settings > Sync** is unchanged and is where pending state shows: Last Synced, Not on Server Yet ("3 items"), the
  action and the message.

### No layout shift

**Mac.** While the library syncs with a server, the toolbar keeps Sync Status's place, whether or not it shows:
`… Insert Image · flexible space · [Sync Status] · fixed space · Editor Only · View Source · Entry Actions · Search`.

- The place is as wide as the button. While nothing needs attention it's empty: no glass is drawn, it isn't in the
  keyboard loop or the accessibility tree, it has no help tag, and it's hidden in the overflow menu (»).
- When Sync Status appears, the button appears in its place with its own glass, kept apart from Editor Only's group by
  the fixed space, as a status of its own. Nothing else moves. It fades in over 0.2 seconds; with Reduce Motion, it
  appears at once.
- It has the lowest visibility priority, so in a narrow window it's the first to move into the overflow menu, where it
  shows "Sync Status" with the same submenu while it has something to say. The empty place costs about 50 points of
  toolbar width; that's accepted.
- Connecting to a server or stopping syncing adds or removes the place. Both are deliberate actions in Settings, so a
  change then is expected; a library without a server has no gap.
- While the app is locked, the journal toolbar is removed entirely, as before.
- Help tag and accessibility label "Sync Status"; it's a menu button, opened by a click, Space or VoiceOver's press.

**iPhone and iPad.** Unchanged placement: the Sync Status submenu at the end of the entry's … menu, shown by the new
rule. Sync never adds or removes a toolbar button there. Noted for the owner: on these devices an attention state is
only visible inside the … menu and in Settings > Sync (as before).

## 2. The title starts where the body does

### Measured before (hosted windows)

- Mac: the title's first letter started at x = 612 and the body's at 617, for text and for the placeholders "Title"
  and "Start writing…": 5 points apart. The body starts at the editor's edge + text container inset (4) + line fragment
  padding (5); the title at its own padding, 4 points less than the editor's.
- iPhone and iPad: the title started at the header's 4-point padding, the body at its 5-point line fragment padding: 1
  point apart.

### Rule

- The first letter of the title and of the body, and of their placeholders ("Title", "Start writing…" and "Start
  writing or use a template"), start at the same x within 0.5 point, on iPhone, iPad and Mac, at the usual and the
  largest text size, while editing or not, and in View Source.
- Measured at the letter's origin (its pen position), as text alignment is measured in Apple's apps. The letters' own
  side bearings differ by letter, weight and size (under a point) and aren't compensated.
- The body's geometry doesn't change, so paragraphs, lists, headings, quotes, tables, images and their decorations keep
  their places. The title moves to the body's text edge, and the editing note under it moves with it; the right edge
  follows the same inset.
- Notices above the title (save failure, recovery, conflict) keep their own padding, about 5 points from the text edge.

### How

- `EntryTextInset` holds the body's text container inset (Mac 4, iOS 0) and line fragment padding (5); the editor sets
  both from it.
- Mac: the title's padding is the editor's margin (24) + `EntryTextInset.text`. The text field draws and edits its text
  at its layout edge (its alignment insets cancel its 2-point text inset), so no other correction is needed; the test
  guards this.
- iPhone and iPad: the header's horizontal padding is `EntryTextInset.text`, for the editable and the read-only title.

## Tests

- `SyncRecoveryTests`: every state shows or hides Sync Status as in the table, with changes waiting; changes waiting
  while syncing normally don't show it; a refused record does; no server doesn't. The long wait: 1 hour vs 24 hours of
  failing without a successful sync, 23:59 vs 24:01 since Last Synced, nothing waiting, and old changes at launch without
  a failure.
- `JournalWindowLayoutTests.testSyncStatusAppearsWithoutMovingOtherItems` (Mac): Formatting, Editor Only and Search
  keep their frames when Sync Status appears and leaves; the empty place has no glass, isn't in the keyboard loop and is
  hidden in the overflow menu.
- `TitleAlignmentTests` (Mac and iOS): the real title and body, with text and with the placeholders, at the usual and
  the largest text size (Mac: also View Source), start within 0.5 point of each other. It fails by 5 points without
  the Mac change.
