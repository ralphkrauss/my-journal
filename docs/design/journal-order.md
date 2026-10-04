# Journal order

Status: current, built 2026-10-03; the prototype outcome and implementation notes are at the end. Reviewed proposal, 2026-10-03. It uses the **library record** defined in [pinned-entries.md](pinned-entries.md#proposal-one-library-record). The independent review is recorded at the end.

## Request

Owner: "I want to be able to change the order of the journals. Follow the Apple Notes convention here: you can long-press on the items to drag and drop (both on iOS and Mac), and on the phone there is an 'Edit' button that puts the journals in an edit mode." On the Mac: "there is no such thing [as Edit mode] (you just drag and drop them with the mouse)."

On the Default journal: "The default journal is called 'Default' but is not special in any way. You should be able to rename it, or delete it, or drag it to wherever you want. The only thing that should stay and can't be moved is the 'All Entries', because that is genuinely different."

**The reference screenshots arrived.** The owner sent two screenshots of the Notes Folders screen on iOS 26, one in normal mode and one in edit mode. This design follows them.

- **Normal mode:** two separate glass buttons at the top right: New Folder (round, `folder.badge.plus`) and a capsule text button, "Edit". A large "Folders" title. Rows show an icon, the name, a count and a chevron.
- **Edit mode:**
  - "Edit" becomes a round checkmark button. New Folder stays where it is.
  - The rows that can't be edited ("All iCloud", and Notes' built-in "Notes" folder) are dimmed: grey icon and text, with no count, chevron, actions or handle.
  - User folders keep their icon and name. The count and chevron are replaced by an accent-coloured `ellipsis.circle` actions button, then a reorder handle (three lines) at the trailing edge, after a thin vertical separator.

## The journals list today

From `JournalSidebarView.swift` and `CompactJournalNavigation.swift`, and confirmed against the current layout:

- **Fixed rows and order:**
  1. **All Entries**, on its own, at the top.
  2. A **Journals** section with every journal in use, **sorted by name** (`localizedStandardCompare`).
  3. A separate group with **Templates**, **Recently Deleted** and, when needed, **Unavailable Journals**.
  4. On the iPad sidebar only, a **Settings** row in its own group.
- **iPhone Journals screen:** the title is "Journals". Settings (gear) is at the top left, and New Journal (`folder.badge.plus`) is at the top right. This is the owner's uncommitted change in `CompactJournalNavigation.swift`, recorded in ios-delete-all-and-settings-2026-10-03.md. Search ("Search All Entries") and New Entry are in the bottom bar. Rows push their collection.
- **Journal rows** have a context menu, also shown as the journal's "…" (Journal Actions): Rename…, Default Template ▸, Merge Into…, Version History…, —, Delete Journal…. On the Mac the context menu also starts with New Journal….
- **"Default" today:** it is an ordinary journal. The app checks that nothing treats it differently:
  - `NewVault` creates the first journal with the title "Default".
  - Rename… and Delete Journal… are offered for every journal, with no check of name or identity. Renaming or deleting "Default" works today.
  - `LibraryContents.nothingWritten` recognizes an untouched new library (exactly one journal named "Default", no entries) so that connecting to a server may replace it. This doesn't restrict anything.
  - Settings ▸ Default Journal (default-journal.md) is a per-device choice. Without a stored choice, or while the chosen journal isn't in use, it falls back to the **oldest journal in use** by creation date, not by name.
  - The server has no special case.
  - Nothing needs to change, so the plan has no task to remove a restriction.

## Design

### Which rows move

- **Movable:** every journal in the Journals section, "Default" included.
- **Fixed:** All Entries (top). Templates, Recently Deleted and Unavailable Journals stay fixed in their own group below, because they aren't journals. On the iPad, the Settings row is fixed too.
- A journal can only be dropped inside the Journals section. It can't move above All Entries or into the lower group.

### iPhone (and iPad in compact width)

Normal mode:

```
⚙︎                              (📁+) ( Edit )
Journals
┌──────────────────────────────────────────┐
  ▤ All Entries                     84   ›
└──────────────────────────────────────────┘
  JOURNALS
┌──────────────────────────────────────────┐
  📕 Default                         40   ›
  📕 Work                            31   ›
  📕 Travel                          13   ›
└──────────────────────────────────────────┘
┌──────────────────────────────────────────┐
  ⧉ Templates                            ›
  🗑 Recently Deleted                    ›
└──────────────────────────────────────────┘
 [ Search All Entries                ] [ ✎ ]
```

Edit mode:

```
⚙︎                              (📁+) ( ✓ )
Journals
┌──────────────────────────────────────────┐
  ▤ All Entries            (dimmed)
└──────────────────────────────────────────┘
  JOURNALS
┌──────────────────────────────────────────┐
  📕 Default                    (⋯) │ ≡
  📕 Work                       (⋯) │ ≡
  📕 Travel                     (⋯) │ ≡
└──────────────────────────────────────────┘
┌──────────────────────────────────────────┐
  ⧉ Templates              (dimmed)
  🗑 Recently Deleted      (dimmed)
└──────────────────────────────────────────┘
 [ Search All Entries                ] [ ✎ ]
```

- **Toolbar:**
  - Top left: Settings (gear), unchanged.
  - Top right: New Journal and **Edit**, as two separate glass buttons in the order New Journal, then Edit, as in Notes. On iOS 26, adjacent toolbar items merge into one capsule, so a `ToolbarSpacer(.fixed)` goes between them.
  - Edit is a text button labelled **"Edit"**. In edit mode it becomes the system's round checkmark button (`Button(role: .confirm)` on iOS 26), whose accessibility label is **"Done"**. Earlier systems use the same `Label("Done", systemImage: "checkmark")` the editor's Done uses.
  - Edit is hidden when there are no journals in use. It is shown with one journal, because it also offers the ⋯ actions.
- **Entering edit mode** animates in the ⋯ buttons and handles (no animation with Reduce Motion).
  - **Fixed rows are dimmed:** secondary icon and text, no count, no chevron. Tapping them does nothing.
  - **Journal rows** keep their icon and name. The count and chevron are replaced by an accent-coloured **⋯** (`ellipsis.circle`) menu button, then a thin separator and the system reorder handle. Tapping a journal's name does nothing in edit mode. There are no delete buttons, because Delete Journal… is in ⋯ and deleting needs its confirmation.
  - **⋯ offers the journal's existing actions**, the same catalog as its context menu (`journalActions`): Rename…, Default Template ▸, Merge Into…, Version History…, —, Delete Journal…. Rename and Delete keep their alerts. After a deletion the row leaves the list and edit mode stays on.
- **Reordering in edit mode:** drag a handle. The list moves rows apart to show where the journal will land, using the system's reorder behaviour. The new order is saved when the row is dropped, not when the person taps Done, so there is nothing to lose if the app is locked or closed.
- **While editing:**
  - New Journal stays available. The new journal is added at the end of the list (see "New journals"), and edit mode stays on.
  - Search and New Entry in the bottom bar stay available. Using either one ends edit mode first. A disabled search field would be unusual on iOS, and VoiceOver would read it as dimmed with no explanation.
  - Settings stays available.
- **Leaving edit mode:** tap Done. Edit mode also ends when My Journal locks, when the library is replaced, and when the last journal is deleted.
- **Long-press drag outside edit mode:** pressing and holding a journal row shows its context menu, as now. Moving the finger while holding lifts the row and drags it, as in Notes. Dropping it inside the Journals section reorders. Dropping it elsewhere returns it to its place. All Entries and the lower group can't be lifted.
- **Prototype first.** The app has no list reordering or drag and drop today. Before implementation, a throwaway prototype on iOS 26, iPadOS 26 and macOS 26 must show two things: a SwiftUI `List` with `.onMove` and `.contextMenu` on the same rows gives Notes' "hold for the menu, move to drag" behaviour; and the Mac sidebar drag works in the AppKit-hosted sidebar. The fallback, if SwiftUI can't, is a UIKit list (`UICollectionView` list with reordering and a context menu interaction) for the iOS journals list. Edit mode with handles is the minimum that must ship on iOS either way.

### iPad (regular width, sidebar)

- The sidebar's toolbar has New Journal and **Edit**, with the same behaviour and copy as on the iPhone. Notes on the iPad offers Edit in its folder sidebar too. Long-press drag works as on the iPhone. With a pointer, a press-and-drag on a row also reorders.
- While editing, the sidebar's selection highlight stays on the current collection, but rows can't be selected. The entry list and editor are unchanged.

### Mac

- **No Edit button and no edit mode** (owner). Drag a journal row in the sidebar up or down. An insertion line shows where it will land, within the Journals section only. Escape cancels the drag (system behaviour). The selected journal stays selected after a drop.
- The context menu gains **Move Up** and **Move Down** after Rename… if the owner chooses D4 (b), the recommendation. With D4 (a) it is unchanged, as in Notes.
- **Undo (Mac and iPad):** Edit ▸ **Undo Move Journal** puts the journal back where it was, registered with the window's undo manager as Undo Delete Entry already is. Undoing is an ordinary move.
- Keyboard reordering without VoiceOver depends on D4.

### New journals, restored and deleted journals

- **Until the person moves a journal**, journals are listed by name, exactly as today, and new journals appear in name order.
- **Once any journal has been moved** (there is a custom order), a new journal is added **at the end** of the Journals section on every device. This includes journals created by Merge…, imported from an archive, or joined from another library.
- **Journals created by an older version** of the app have no position and are listed after the arranged journals, by name. The next move on a current device gives them positions where they are shown, so they stay put.
- **A journal restored from Recently Deleted** returns to its former position. If it never had one, it goes to the end.
- **Recently Deleted** lists deleted journals by name, unchanged.
- **Delete Permanently** doesn't touch the order. A permanently deleted journal's position is ignored and removed by the next change to the order.
- **Unavailable journals and journals with changes to review** aren't listed in the Journals section. Their positions are kept, so they return to their place when they become available again.

### Everywhere journals are listed

The custom order is used in every list of journals in use, so the person finds journals in the same place everywhere:

- the sidebar and the iPhone Journals screen;
- Move Entry…'s destinations;
- Merge Into…'s destinations;
- Settings ▸ Default Journal (which default-journal.md already lists "in sidebar order");
- the Journals settings sheet (`JournalSettingsView`, which uses `journalRecords`, sorted by name today);
- the journal choice in Agent Access.

Deleted journals in Recently Deleted and in the Journals sheet stay sorted by name.

### Default Journal setting (unchanged, recorded here)

- **Settings ▸ Default Journal** is separate from the order and from the name "Default", and stays as default-journal.md describes it. Its options follow the new order.
- **When the chosen journal is moved to Recently Deleted, deleted permanently or becomes unavailable:** New Entry outside a journal uses the **oldest journal in use**, which is the existing fallback. The stored choice is kept, so restoring the journal makes it the default again. Moving journals never changes where new entries go. (Open decision D3 proposes the alternative.)
- **With no journal in use:** New Entry opens New Journal, and the setting is hidden (existing behaviour).
- **Renaming, deleting or moving the journal named "Default"** works like it does for any other journal.

## Copy

| Element | Copy |
| --- | --- |
| Edit button | **Edit** |
| Done button | checkmark; accessibility label **Done** |
| ⋯ button | accessibility label **Journal Actions** (the existing label of the journal's "…") |
| Reorder handle | system ("Reorder Work") |
| VoiceOver actions (and, with D4 (b), Mac context menu items after Rename…) | **Move Up**, **Move Down** |
| VoiceOver announcement after a move | **Moved above ‹journal›.** / **Moved below ‹journal›.** |
| Undo (Mac and iPad, Edit menu) | **Undo Move Journal** |
| Save failure (existing error alert) | **Couldn’t move the journal.** |
| Server too old to sync the order (Settings ▸ Sync footer) | **Pinned entries and journal order stay on this device until the server is updated.** (shared with pinned-entries.md) |

There are no confirmations and no "Saved" message.

## Accessibility

- **VoiceOver, all platforms, in any mode:**
  - Each journal row has the custom actions **Move Up** and **Move Down**. Move Up is missing on the first journal and Move Down on the last.
  - After a move, the app announces "Moved above Travel." (or below), and focus stays on the moved row.
  - VoiceOver users don't need edit mode or drag. In edit mode, the system reorder handle's own drag also works.
- **Edit mode with VoiceOver:**
  - Fixed rows are read with the dimmed trait.
  - Each journal row reads its name, then "Journal Actions, button", then the handle.
  - The order matches what is on screen.
- **Switch Control and Full Keyboard Access (iOS):** the custom actions appear in their actions menus.
- **Mac VoiceOver:** the actions are available through VO-⌘-Space.
- **Dynamic Type:** at accessibility sizes, names wrap (existing `rowLabel`). The ⋯ button and handle stay at the trailing edge with at least 44-point targets.
- **Increase Contrast and Reduce Transparency:** system glass buttons and dimmed rows adapt. No new colors; ⋯ uses the accent color.
- **Reduce Motion:** rows move without animation when moved with the custom actions. The system drag keeps its lift.

## Empty, offline and error states

- **No journals:** Edit is hidden, and the Journals section is empty as now.
- **One journal:** Edit is shown and the handle is present. There is nowhere to move it.
- **Offline:** the order is saved on the device at once and synced later, quietly.
- **Saving fails:** the alert above appears, and the list returns to the previous order.
- **Another device reorders at the same time:** no message and no review. Moves of different journals are both kept. If the same journal was moved on both devices, the move synced last wins, even if it was made earlier offline. When the other device's order arrives, the list updates with the usual list animation. A drop always computes its rank from the neighbours shown at the moment of the drop, so an update during a drag can't put the journal somewhere other than where it was dropped. The prototype decides whether updates are held until the drop.
- **Server too old:** the order stays on this device; the Settings ▸ Sync footer above explains it.
- **Locked or replacing the library:** dragging, Edit and the custom actions are unavailable.

## Data and sync design

The order is stored in the **library record** (pinned-entries.md: identity, reading rules, per-key merge, compatibility with older apps and servers, encryption, metadata and server changes). Putting a position field on each journal record was rejected. Build 12 and earlier treat a journal record with an unknown field as unsupported, and then show **all of its entries as Unavailable** (`JournalLifecycleSnapshot.location(of:)` returns `.unavailable(.unsupported)`). A single reorder would empty the owner's journals on any device that hasn't updated.

### Representation: one rank per journal

- Key `journal-rank/‹lower-case journal id›`; the value is a **rank string**.
- **Alphabet:** the 62 ASCII characters `0-9`, `A-Z`, `a-z`, in ASCII order. A valid rank is 1–64 of these characters and doesn't end in `0` (so there is always room between two ranks). Ranks compare **byte by byte**, as plain ASCII strings. They are never compared by locale, so every device and every platform sorts them the same way.
- **The order shown:**
  1. live journals with a valid rank, by (rank, lower-case journal ID);
  2. then live journals without a valid rank, by name (`localizedStandardCompare`, as today), then by ID.

  With no ranks at all, this is today's order by name.
- **Moving one journal** writes one key: a new rank strictly between its new neighbours' ranks. Any algorithm that produces a valid rank between the two bounds is allowed (readers only compare). The reference algorithm treats ranks as base-62 fractions and takes the midpoint, appending a digit when the neighbours are adjacent. `protocol/fixtures/journal-ranks-v1.json` gives comparison vectors, invalid ranks, and `between` cases for other clients.
- **The first move, or a move with unranked journals:** before the move, the device gives a rank to every live journal shown without one, in the order shown. It uses a deterministic spacing function of each position and the count (in the fixtures), all in the same record write.
  - These automatic ranks are **set if absent** intents (pinned-entries.md, "Conflicts"). The merge drops them for any journal the server already ranks. So a device that is offline, or hasn't yet received another device's arrangement, can't replace that arrangement with an order by name.
  - Only the moved journal's rank is a **set** intent. On such a stale device, the moved journal's rank was computed against its own automatic ranks, so after the merge it may land somewhere other than intended among the other device's arrangement. Moving it again fixes it. The arrangement itself is kept.
  - When some journals already have ranks, the automatic ranks for the unranked ones come after the last valid rank. The spacing function only applies when no journal is ranked.
  - Two devices that both make a first move with the same journals *and the same name order* produce identical automatic ranks, so their merge differs only in the moved keys. Name order follows each device's language (`localizedStandardCompare`), so devices set to different languages may differ; that is harmless, because automatic ranks are only set if absent.
- **A new journal** on a device where ranks exist gets a rank after the last ranked journal, after first ranking any unranked ones as above (set if absent), so it lands at the end. Its own rank is a **set** intent; no other device can have it.
- **Rebalancing:** if a new rank would be longer than 64 characters, the device spaces all live journals evenly again, as **set** intents in one write. This needs dozens of moves into the same gap, so it is practically never needed. A move made on another device at the same moment may then land somewhere unexpected; moving it again fixes it.
- **Keys of journals** in Recently Deleted are kept (so restoring returns them to their place). Keys of journals this device doesn't have, or that are unavailable or under review, are ignored for display and never removed. Keys of journals that exist here as a permanent-deletion marker are removed by the next change to the order.

### Why ranks rather than one ordered list

An array `journalOrder: [id…]` is one value, so two devices reordering at the same time would lose one device's moves entirely under per-key last writer wins. With a rank per journal, moves of different journals merge cleanly. Only the same journal moved on two devices competes, and then the move the server accepts last wins. Neither scheme needs a review screen. Ranks need no renumbering per move, so one write stays small whatever the number of journals.

### Conflicts, worked through

| At the same time | Result on every device |
| --- | --- |
| A moves Work to the top; B moves Travel to the bottom | Both moves. |
| A moves Work to the top; B moves Work to the bottom | The move synced last. |
| A moves Work between Default and Travel; B moves Default to the bottom | Work keeps its rank, which still lies between Default's old rank and Travel's, so Work may end up next to Travel only. The order is consistent everywhere. |
| A creates a journal; B moves another | Both: different keys. |
| A (build 12) creates a journal; B moves another | A's journal has no rank and is listed after the arranged ones on B. A shows everything by name. |
| The Mac arranged all journals; the iPhone, offline since before that, moves Travel to the top | The Mac's arrangement is kept (the iPhone's automatic ranks were "set if absent"). Travel gets the iPhone's rank and may not end up exactly at the top. |

### Compatibility, encryption and server

These are the same as for pins (pinned-entries.md):

- **Older apps** list journals by name, and nothing on them becomes unavailable. They keep the record's bytes; the few cases where they upload it again or show it in Changes to Review are listed in pinned-entries.md, "Older apps and servers".
- **The server change and capability** are shared with pins: allow the kind, advertise `record-kinds`.
- **No migration.**
- **Ranks are inside the encrypted payload.** The server learns that the order changed and when, and roughly how many journals are ranked, which the number of journal records already shows. Ranks don't reveal names: they are derived only from positions.

## Tests that protect this

Sync and compatibility first:

1. **Concurrent moves of different journals** on two stores, in either push order: both moves on every replica, with no reviews.
2. **The same journal moved on two stores:** identical final order everywhere, and it is the order of the later accepted push.
3. **Simultaneous first moves** on two stores with the same journals: unmoved journals get identical ranks, and the result equals both moves applied.
4. **A stale device's first move:** store A arranges all journals and syncs; store B, which hasn't read that change, moves one journal. A's arrangement of every other journal is kept on all replicas.
5. **A journal without a rank** (written by a build-12 store) sorts after the ranked ones, and a later move ranks it without moving the other journals.
6. **Rank rules:** a fast generated test of 2,000 random insertions, including at the start, at the end, and between adjacent ranks. Every rank is valid and strictly between its bounds, and rebalancing starts only above 64 characters. Invalid ranks are ignored for display and kept byte for byte. Fixture vectors match.
7. **Lifecycle:** restoring a journal from Recently Deleted returns it to its place. A permanently deleted journal's key is ignored and removed by the next move. Importing an archive appends the imported journals after the existing ones.
8. **iOS UI test, one journey:** Edit, drag Travel above Default, Done, relaunch. The order persists, and Move Entry… lists the same order. The Mac drag is checked by hand with screenshots, because synthetic drags in the AppKit sidebar are unreliable.

No tests for the presence of the Edit button or the ⋯ menu's composition.

## Open decisions

- **D1 — Where new journals go once there is a custom order.** (a) At the end. *Recommended:* predictable, and it is where the person just looked to tap New Journal's result. (b) At the top. (c) Always by name.
- **D2 — Bottom bar in edit mode.** (a) Leave Search and New Entry active; using either ends edit mode. *Recommended (changed after review):* a disabled search field is unusual on iOS and unexplained to VoiceOver. (b) Disable them.
- **D3 — Default Journal fallback when the chosen journal is gone.** (a) The oldest journal in use, as now. *Recommended:* moving journals never changes where new entries go, and no stored setting changes on upgrade. (b) The first journal in the custom order. This is more visible, but with no custom order it would be the first by name, which may not be "Default", and that would change where new entries go when people update.
- **D4 — Keyboard reordering on the Mac without VoiceOver.** AGENTS.md asks for keyboard navigation, and Notes offers none here. (a) None, matching Notes. This option requires the owner's explicit acceptance of the gap. (b) Add **Move Up** and **Move Down** to the journal's context menu on the Mac, after Rename…. *Recommended:* it costs two menu items and closes the gap for keyboard and Full Keyboard Access users.
- **D5 — Reset.** No "Sort by Name" command is proposed. If wanted later, it removes all `journal-rank/` keys in one write.
- **D6 — Edit on the iPad sidebar.** The owner asked for Edit on the phone. (a) Also on the iPad sidebar, as Notes does. *Recommended.* (b) iPhone only; the iPad uses drag and the VoiceOver actions.

## Review outcome

This design was reviewed together with pinned-entries.md. Its data and sync design is the shared library record described there, and that file records all three reviews.

Changes made to this file after the reviews:
- **Drag prototype first.** A prototype is required before implementation, with a UIKit list as the fallback.
- **Toolbar.** A `ToolbarSpacer(.fixed)` separates New Journal and Edit; Done uses the confirm role.
- **Bottom bar in edit mode.** Search and New Entry stay active (D2 was changed to (a)).
- **Undo Move Journal** on the Mac and iPad.
- **Automatic ranks:**
  - they are "set if absent", so a device that is offline or behind can't replace another device's arrangement;
  - they come after the last valid rank;
  - the claim about identical ranks now depends on the name order matching.
- **Pruning.** Keys of journals that are only unavailable or missing are never pruned.
- **Consistency.** The Mac context menu now follows D4, the compatibility text points to the revised description, and the D4 wording is neutral.

**Verdict:**
- The UI design is approved.
- The sync design is approved once the reconciliation changes are applied, which they have been in pinned-entries.md.
- Remaining before implementation: the drag prototype, the protecting tests, and the owner's decisions D1–D6.

## Owner decisions (3 October 2026)

The owner accepted the recommendations, with two changes:
- New journals go at the end once the owner has arranged the journals.
- Search and New Entry stay usable in edit mode, and using one ends edit mode. **Change:** New Journal keeps edit
  mode on, as in Notes: the new journal appears in the list and editing continues. The owner wants fewer moving parts
  in this flow.
- If the Default Journal is deleted, new entries go to the oldest journal still in use, as now.
- **Change:** no Move Up and Move Down on the Mac. Reordering on the Mac is by drag only, as in Notes. VoiceOver's
  accessibility actions on iOS stay.
- Edit appears in the iPad sidebar as well as on iPhone.
- There is no Sort by Name command for now.
- "Default" is an ordinary journal: it can be reordered, renamed and deleted. Only All Entries is fixed.

## Drag prototype (3 October 2026)

A throwaway SwiftUI app (a `List` with `ForEach.onMove` and `.contextMenu` on the same rows) was run with UI tests:

- **iOS 26.5 (iPhone 17) and iPadOS 26.5 (iPad Pro 13-inch):** holding a row shows its context menu; moving the finger while holding lifts the row and reorders it; a tap still opens the row; in edit mode the system handles reorder. No UIKit fallback is needed.
- **macOS 26.3, in an AppKit split view's sidebar:** SwiftUI registers its list-reorder drag type (`com.apple.SwiftUI.listReorder`) on the sidebar's table. Mac XCUITest needs automation-mode approval and synthetic AppKit drags don't start a drag session, so the Mac drag is checked by hand, as this design planned.
- **Test runner:** while a context menu of a reorderable SwiftUI list is open on iOS 26, XCUITest never receives "animations complete", so each test step waits a minute (127 s for one menu choice in the prototype with `.onMove`, 7.6 s without). It isn't visible to people. UI tests that only need a journal's actions use Edit and the row's ⋯ (`NavigationTestSupport.journalAction`); one test keeps using the held row's context menu.
- Seen in both the prototype and the app: when a drag starts from an open context menu, the system centres the lifted row under the finger, so a row held near its leading edge jumps sideways. This is the system's drag preview; changing it would need a UIKit list.

## Implementation notes (3 October 2026)

- **Owner changes applied:** New Journal keeps edit mode on (the new journal is added at the end and not opened); the Mac has no Move Up and Move Down (drag only); iOS keeps the VoiceOver actions Move Up and Move Down; "Default" is an ordinary journal.
- **A dropped journal shows at once** where it was dropped while the move is stored, then the stored order replaces it, or the previous order returns with the error alert.
- **The moved journal** gets no automatic rank of its own. When its neighbours' ranks leave no room (equal ranks from two devices, or a rank longer than 64 characters), every journal is spaced again as set intents.
- **A key holding an invalid rank** is kept and the journal stays unranked (after the ranked ones, by name) until it is moved.
- **iPad sidebar:** it now has a large "Journals" title, because the sidebar's bar has no room for the title beside New Journal, Edit and the sidebar button. In its edit mode the rows show the journal's name without the book icon and a 32-point-wide (44-point-tall) ⋯ button, so names fit the 210-point sidebar. At accessibility text sizes, edit rows on iPhone also show the name without the icon, as the rows outside edit mode do.
- **Restoring a journal** without a rank, once journals are arranged, puts it at the end.
