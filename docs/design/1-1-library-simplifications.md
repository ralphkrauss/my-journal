# 1.1 library simplifications: no journal history, no Merge Into…, one way to use a template, plain Restore

Status: proposal, step 1 of the design gate in [AGENTS.md](../../AGENTS.md); reviewed twice on 2026-10-09 (approve with changes both times) and revised to address both, see [Changes after review](#changes-after-review). Not built. Covers simplifications K, L, M and N of [release-1-1-scope.md](release-1-1-scope.md) (owner-approved 2026-10-07). The review and the changes it caused are at the end of this record.

Version 1.0 (build 19) is in App Review and will be public before 1.1 ships. Everything below is written so that 1.0 data is never discarded or silently changed and so that 1.0 and 1.1 devices keep syncing one library together.

## Summary

| | Goes | Stays |
| --- | --- | --- |
| K | Version History… for a journal (menus, the deleted journal's page), the Restore Settings comparison, the `restoreJournalSettings` store operation | Version History for entries and templates; every stored history row; checkpoints |
| L | Merge Into… and its sheet, the `mergeJournal` store operation, the agent-access footer that went with it | Move Entry… (one entry at a time); the Merge Journals step when connecting to a server (a different feature); deleted journals that were merged by 1.0 |
| M | A journal's Default Template, New Entry In ▸, New Entry from Template (template menus), File ▸ New Blank Entry, File ▸ New Entry from Template…, the chooser's Journal picker, the chooser's "make a new entry" fallback | The template chooser, opened from **inside an empty entry** ("use a template" and, new wording, File ▸ Use a Template…); Save as Template…; the Templates list; Settings ▸ Default Journal; the stored `defaultTemplateID` field |
| N | Restore and Move…, Restore… (entry with its journal), the Restore Entry and Restore Journal sheets | One verb, Restore, that acts at once on entries, templates and journals (it names the journal when an entry cannot go back to its own); the Delete Permanently paths |

Nothing is migrated and no stored record is rewritten. 1.1 simply stops showing and using four things; the data behind them stays exactly as 1.0 wrote it.

## Ground rules for living with 1.0

1. **No write at upgrade or at open.** 1.1 does not clear `defaultTemplateID`, rewrite journals, delete history rows or touch Recently Deleted when it first opens a 1.0 library. Journal records can conflict between devices (journal review exists in 1.0), so a bulk rewrite on every upgraded device would create the conflicts it is meant to avoid.
2. **Preserve what is not shown.** A 1.1 client keeps `defaultTemplateID` unchanged whenever it saves a journal for another reason, such as Rename, Delete Journal, Restore Journal, conflict resolution, import or merge remapping. (A record with any member the reader does not know is read-only already: its original bytes are kept in `preservedJSON` and it is never rewritten, so it needs no rule here; `defaultTemplateID` is a known member, which is why it needs one.) Test 1 and the new conformance fixture pin this. A 1.0 device keeps using the setting; a 1.1 device ignores it.
3. **1.0 operations stay valid input.** Everything 1.0 can do with these four features writes ordinary records (a journal rename, an entry whose `journalID` changed, a tombstone set or cleared). 1.1 reads them like any other change. Nothing new goes on the wire.
4. **Wire, archive and server are untouched; no protocol version bump.** No change to [protocol/records.md](../../protocol/records.md) formats, the archive's `history` table, the sync API or the server. `defaultTemplateID` stays an optional member that readers parse and writers may omit, and the removed operations are client behaviour described in prose. The one new normative sentence (writers keep the field when they save a journal) gets an **additive** fixture, see [Spec and documentation changes](#spec-and-documentation-changes-the-implementation-makes).
5. **Mixed-version behaviour may differ by device during the transition** and that is accepted: a 1.0 device still offers the features and a 1.1 device does not. Each section below says what the 1.0 device sees.

## K. No journal-level version history

### Current behaviour

- Entry points: Version History… in the journal actions catalog (`AppModel.journalActions` in `Views/JournalSidebarView.swift`; `Views/JournalMoreMenu.swift`; the Mac menu in `Views/Mac/RootView+MacWindow.swift`) and in a deleted journal's page (`Views/DeletedJournalView.swift`, shown when `model.journalHistoryIDs` holds the journal).
- `Views/JournalHistoryView.swift` lists earlier versions of the journal record and offers Restore Settings…; `Views/JournalSettingsConfirmation.swift` is the side-by-side comparison; `JournalStore.restoreJournalSettings` (`StoreHistory.swift`) copies only `title` and `defaultTemplateID` back, after saving the current record into history. [spec/screens/journal-history.md](../../spec/screens/journal-history.md), [protocol/history-recovery.md](../../protocol/history-recovery.md), [history-recovery.md](history-recovery.md).
- What writes journal history rows: Restore Settings, and conflict review (the version not kept). Journals get no automatic checkpoints ([version-checkpoints.md](version-checkpoints.md)), so most libraries have few or no such rows.

### New behaviour

The screen, its entry points and its operation disappear. Entries and templates keep Version History unchanged.

- A journal's actions no longer contain Version History…. A deleted journal's page no longer shows it.
- Renaming remains the only way to change a journal's name. A name that was changed by mistake is fixed by renaming again; the earlier name is not offered back. This is the cost of the simplification, accepted by the owner. It includes journals that sync, import or Merge Journals numbered automatically ("Work 2"): their earlier name is no longer visible anywhere in the app.
- **Order of work with H, and the trade-off accepted.** Today the only screen that shows the version a journal conflict set aside is journal Version History (and the 1.0 review form before a choice). The revised H ([1-1-conflicts-and-reconnect.md](1-1-conflicts-and-reconnect.md), 3.5) resolves a journal renamed on two devices automatically: the later name stays, the other name is in the Changed on Two Devices note on the device that resolved (30 days) and in a history row of the journal record. After K, nothing displays that history row. **Chosen: accept it.** A losing journal name is a short string, the note shows it for 30 days on the resolving device, and the person can rename again; the library record (pins, order) already works the same way. Content (entries) is never affected: this is only about a journal's name. So K may ship with or after H step 1, and **not before it**, because before H step 1 the 1.0 review form is the only place a person chooses between two journal versions and K would remove the screen that keeps the one not chosen. Rejected: keeping the note until cleared (a change to H, not required), and creating a numbered second journal for the losing name (H decided against a journal copy because a copy would not carry entries).

### Existing 1.0 data

| Data | 1.1 |
| --- | --- |
| `history` rows with `kind = 'journal'` | Left in place, never shown, never copied anywhere. They stay in archives (the archive's `history` table is unchanged), stay local (history never syncs), and are removed with the journal by Delete Permanently exactly as today. 1.1 writes no new journal history rows except the one H step 1 keeps when a journal rename loses (see Order of work above); nothing displays them. |
| A journal that has a restored-settings history | Unaffected. |

Deleting the rows would be irreversible for a change that is purely about the interface, and they cost almost nothing (a few small records, no automatic growth). A later release can drop them once nothing reads them; that is not part of 1.1.

### 1.0 devices

A 1.0 device keeps offering journal Version History for its own rows and Restore Settings. A restore there is an ordinary journal update (name and default template) that 1.1 devices receive as a rename plus an ignored field. If the same journal was renamed on a 1.1 device meanwhile, the two versions conflict like any two renames today (journal review in 1.0; H in 1.1).

### Menus and shortcuts that disappear

| Command | iPhone | iPad | Mac |
| --- | --- | --- | --- |
| `journal-version-history` | journal row context menu (touch and hold), ⋯ on a row in edit mode, list bar ⋯ Journal Actions, deleted journal's page | same | sidebar row context menu, toolbar Journal Actions, deleted journal's page |

None had a keyboard shortcut.

### Dead code and stored data that can go

`Views/JournalHistoryView.swift`, `Views/JournalSettingsConfirmation.swift`, the journal parts of `Views/HistoryMenu.swift` (the version picker is shared with entry history and stays), `AppModel.restoreHistoricalJournalSettings` and `journalHistoryIDs` (with the snapshot field, `JournalStore.journalHistoryIDs()` and its use in `Store.swift`), `JournalStore.restoreJournalSettings`, `HistoryRecoveryError.changedJournal` and `.settingsAlreadyApplied`, the "Restore journal settings" section of [protocol/history-recovery.md](../../protocol/history-recovery.md), and the journal tests in `HistoryRecoveryTests`. No stored data goes.

## L. No Merge Into…

### Current behaviour

- `Views/MergeJournalView.swift` is presented from the same journal actions catalog as K (`merge:` closure in `AppModel.journalActions`, `JournalMoreMenu`, `RootView+MacWindow`). `AppModel.mergeJournal` (`Model/JournalOperations.swift`) saves the open entry, then `JournalStore.mergeJournal` (`JournalMerging.swift`) moves every entry (including entries in Recently Deleted, which keep their deletion) into the chosen journal and tombstones the source journal in one transaction. The sheet explains agent-access consequences (`library.merge.agents.*`). [spec/screens/merge-journal.md](../../spec/screens/merge-journal.md), [journal-name-uniqueness.md](journal-name-uniqueness.md) §5.
- Not related and not touched: the Merge Journals step when a device with journals connects to a server (`Views/MergeJournalsView.swift`, `JournalStore` merge plan, `settings.connect.merge.*`, `common.merge`, `common.merging`).

### New behaviour

The command is gone. There is no bulk move in 1.1: the owner decided on 2026-10-09 that lists have no multiple selection (open question D13), so a multi-select Move Entry is not planned for 1.1 or as a promised follow-up.

**The answer for duplicates is Rename.** Journal names stay unique: Rename refuses a taken name, and sync, import and Merge Journals add a number to the newer journal ("Work 2", [journal-name-uniqueness.md](journal-name-uniqueness.md)). Two journals that two devices each created offline are two real journals, and keeping both is harmless: the person renames the numbered one to something meaningful ("Work 2" to "Work, laptop"). Merge Into… was the shortcut for people who wanted one journal; they now use Move Entry… one entry at a time and then Delete Journal…, which is slow for hundreds of entries and is a known cost of the approved removal. The guide says this next to Move Entry (`docs/guide/getting-started.md`).

The plan edits [journal-name-uniqueness.md](journal-name-uniqueness.md) sections 4.5, 4.6 and 5 and its Merge Journals footer decisions so no record still promises Merge Into… or an earlier name kept in Version History: they now say "rename it".

### Existing 1.0 data

A journal merged by 1.0 is an ordinary deleted journal with no entries (its entries now belong to the destination). It appears in Recently Deleted with `library.recentlyDeleted.journalCount` "0 entries on this device", and can be restored (an empty journal, numbered if its name is taken) or deleted permanently. Entries that were in Recently Deleted when it was merged are in Recently Deleted under the destination journal and restore into it (N). Nothing needs a migration.

### 1.0 devices

A merge on a 1.0 device syncs as a batch of entry updates plus one journal tombstone. 1.1 shows the destination with all entries and the source in Recently Deleted. Pins, dates and images are untouched. A 1.0 merge racing a 1.1 entry edit on the same entry produces an entry conflict that is resolved as today (H).

### Menus and shortcuts that disappear

| Command | iPhone | iPad | Mac |
| --- | --- | --- | --- |
| `merge-journal` | row context menu, edit-mode ⋯, list bar ⋯ Journal Actions | same | sidebar row context menu, toolbar Journal Actions |

No shortcut. After K and L (and M) the journal actions are Rename… and Delete Journal… on every device, plus New Journal… first on the Mac. The ⋯ menu stays with two items rather than being replaced by a different pattern; changing the pattern is not part of this change.

### Dead code and stored data that can go

`Views/MergeJournalView.swift`, `Model/JournalOperations.swift` `mergeJournal`, `JournalCore/JournalMerging.swift` (`JournalMergeError`, `mergeJournal`), `Packages/JournalCore/Tests/JournalCoreTests/MergeIntoTests.swift` (replaced by one interop test, see Tests), the agent-scope footer code that reads grants for the merge sheet, and the `AgentJournalsProbe` calls to `mergeJournal` (the probe moves entries with `moveEntry` and deletes the journal instead). `common.merge` and `common.merging` stay for Merge Journals. No stored data goes.

## M. One way to start from a template

### Current behaviour

There are five ways to start from a template today:

1. **Journal default template.** Journal actions ▸ Default Template (`common.defaultTemplate`, `AppModel.changeJournal(_:template:)`, `offersDefaultTemplateChoice`); New Entry then copies it (`AppModel.newEntry`, `Model/AppModel.swift`, the `templates.first { $0.id == journal.defaultTemplateID }` lookup). File ▸ New Blank Entry (⇧⌘N) exists only to ignore it.
2. **New Entry In ▸ / New Entry from Template** in a template's context menu and Entry Actions (`AppModel.newEntryFromTemplateAction`, `Model/TemplateSuggestion.swift`; `RootView.entryActionCatalog`).
3. **File ▸ New Entry from Template…** (Mac, iPad; `AppCommands.swift`), a sheet with a Journal picker outside a journal (`TemplateChooserView`, `choosesJournal`).
4. **"use a template"** in an empty entry's placeholder (`TemplateSuggestionView`, popover on Mac and iPad, sheet on iPhone): fills the open entry.
5. Fallback inside 3 and 4: if the open entry is no longer empty, the choice creates a new entry where New Entry would put it (open question D16).

Records: [new-entry-template-suggestion.md](new-entry-template-suggestion.md), [template-journal-choice-2026-10-03.md](template-journal-choice-2026-10-03.md), [no-built-in-templates-2026-10-04.md](no-built-in-templates-2026-10-04.md), [default-journal.md](default-journal.md).

### Decision: which path stays

**The template chooser, opened from inside an entry, filling that entry.** One action in one place:

- Start an entry the usual way (New Entry, ⌘N, which is now always blank). If templates exist, the empty entry's placeholder reads "Start writing or [symbol] use a template".
- Choosing the link opens the chooser. A choice fills the entry's body and keeps the title, as one undoable change (existing behaviour, [template-initial-insertion.md](template-initial-insertion.md)).
- The same action has a menu route for keyboard, Voice Control and VoiceOver users on the Mac and iPad: **File ▸ Use a Template…** (`use-a-template`). It is enabled exactly when the link is shown (open entry editable, body empty, no pictures, an editable template exists) and opens the chooser as the sheet the File menu already used.

Why this one and not the others:

- It works on every device the same way. iPhone has no menu bar, so a "New Entry from Template…" command could not be the single path; the link already exists on all three.
- The entry already has a journal, so the chooser needs no Journal picker, no "journal is gone" state and no rule about where the entry goes. That removes most of the code and the whole of D16.
- It matches how templates are described to people everywhere else ("Save as Template…", "use a template"), and it keeps New Entry predictable: ⌘N always gives the same blank entry.
- A one-step "create from template" can be added later as a convenience on top of this chooser without reintroducing a default template; it is not needed to meet the scope.

Costs, stated plainly: a person who relied on a journal's default template (for example a daily reflection) now taps once more per entry; File ▸ New Blank Entry and ⇧⌘N disappear because New Entry is now always blank; there is no one-step "new entry from this template" in the Templates list.

### New behaviour

**New Entry.** Always an empty entry in the journal it already used (the shown journal; otherwise the Default Journal). ([flows/new-entry.md](../../spec/flows/new-entry.md) step 4 becomes one line.)

**Template chooser** ([screens/template-chooser.md](../../spec/screens/template-chooser.md)). Same list, search field and keyboard behaviour. Removed: the Journal picker, `choosesJournal`, the create-a-new-entry branch, `templateChooserPresented` as "new entry" (it now means "chooser for the open entry"). Containers are unchanged: popover (Mac, iPad regular width), sheet (iPhone, iPad compact width, and from File ▸ Use a Template…, Mac sheet 320 × 352 points).

Choosing a template while the entry has stopped being empty (text typed or synced in) changes nothing, closes the chooser and shows the message `library.templateChooser.entryChanged` ("This entry changed, so the template wasn’t added.") in the general error alert, because choosing again would fail the same way. If the entry itself was closed or deleted meanwhile, the chooser just closes. Nothing is ever created implicitly.

**Templates list** ([screens/templates.md](../../spec/screens/templates.md)). A template's context menu and Entry Actions are now:

| Item | Shown when |
| --- | --- |
| Image Descriptions… | the template has pictures |
| Version History… | always |
| — | |
| Delete Template (destructive) | editable and not deleted |

Swipe: trailing Delete as before. New Entry In ▸ and New Entry from Template are gone. Templates in Recently Deleted keep Restore and Delete Permanently….

**Journal actions** lose Default Template ▸ (K and L remove two more items, see the table below).

**Settings ▸ Default Journal** is unrelated (it chooses where New Entry files an entry outside a journal) and stays unchanged. Its help text does not mention templates today.

### Existing 1.0 data

| Data | 1.1 |
| --- | --- |
| A journal with `defaultTemplateID` set | Field kept in the record and preserved on every save; ignored. New Entry in that journal is blank on 1.1. |
| `defaultTemplateID` naming a template in Recently Deleted or gone | Same: ignored. A 1.0 device keeps its own fallback rule (blank while the template is deleted, back when it is restored). |
| Archives containing the field | Read and written as today; import and merge keep remapping it (`protocol/archive.md`, "the same mapping applies to every `defaultTemplateID`") so a 1.0 device on the same library still resolves it. |
| The template itself | Untouched; it is an ordinary template and still appears in the chooser. |

People who used a default template get no warning in the app (see [Owner decisions](#decisions-for-the-owner)); the 1.1 release notes and the guide say it plainly.

### 1.0 devices

- A 1.0 device that sets, changes or clears a default template syncs a journal update. 1.1 stores the field and ignores it, and its own Rename keeps the field (ground rule 2).
- A 1.0 device creating a new entry in that journal still copies the template; a 1.1 device creates a blank one. This inconsistency is intentional and temporary.
- Deleting the template on a 1.1 device makes a 1.0 device's New Entry blank in that journal while it is deleted (existing 1.0 rule). Restoring it brings the behaviour back there.
- **A journal changed on both sides.** If a 1.0 device changes a journal's default template while a 1.1 device renames the same journal, the revised H resolves it automatically and keeps the local record's `defaultTemplateID`, which may silently replace the 1.0 device's choice. Accepted: 1.1 ignores the setting, the template is untouched, and the person can set it again on the 1.0 device. Test 1 covers that the field is kept, not lost.

### Menus, shortcuts and commands that disappear

| Command | iPhone | iPad | Mac |
| --- | --- | --- | --- |
| `journal-default-template` | Default Template ▸ in journal actions | same | same, in sidebar context menu and toolbar Journal Actions |
| `new-entry-in` (both forms) | template row context menu and Entry Actions | same | same |
| `new-blank-entry` | — | File ▸ New Blank Entry, ⇧⌘N (also in the ⌘-hold overlay) | File ▸ New Blank Entry, ⇧⌘N |
| `new-entry-from-template` | — | File ▸ New Entry from Template… (also in the ⌘-hold overlay) | File ▸ New Entry from Template… |
| `use-a-template` | unchanged: the link opens a sheet | the link (popover or sheet) **plus** File ▸ Use a Template… (new menu placement, replaces New Entry from Template…) | the link (popover) **plus** File ▸ Use a Template… |

`new-entry` (⌘N) keeps its shortcut and placement; its description loses "with the journal's default template".

Only the menu placement of `use-a-template` is new; the File menu gains no item overall (one item replaces another, and New Blank Entry leaves).

### Dead code and stored data that can go

`AppModel.changeJournal(_:template:)`, `defaultTemplateID(of:)`, `offersDefaultTemplateChoice(for:)`, the `blank:` and `template:` parameters and the `defaultTemplateID` lookup of `AppModel.newEntry`, the `filling:` and `chosen:` parameters if nothing else uses them, `canStartEntry(fromTemplate:)`, `newEntryFromTemplateAction`, `newEntry(fromTemplate:in:)`, `lastOpenedJournal` (if `configuration.lastJournalID` has no other reader), `RootView`'s `startEntry(fromTemplate:in:)` and the template menu catalog entries, `TemplateChooserView`'s `choosesJournal`, `showsJournalPicker`, `pickedJournalID`, `journalPicker` and the "create" path, the `Views/JournalSettingsView.swift` and `Views/JournalsSheet.swift` pair (already unreachable, simplification A), the default-template line in `JournalMetadataSummary` (`Views/JournalConflictView.swift`; if H has not yet removed the whole journal review form when this lands, drop the line), `ScreenshotLibrary` seeds that set default templates, and the tests listed under Tests. `JournalItem.defaultTemplateID`, its encoding and the import and merge remapping **stay** (ground rules 2 and 4). No stored data goes.

## N. Recently Deleted offers plain Restore only

### Current behaviour

- Entries: leading swipe, context menu and Entry Actions show **Restore** only when `canRestoreDirectly` (`Views/RootView.swift`): editable, not deleted with its journal by an earlier version, and the journal in use. Otherwise the person must open the entry and find, in the recovery notice (`Views/EntryRecoveryNotice.swift`), **Restore…** (entry with its deleted journal; `Views/JournalLifecycleView.swift` in its Restore Entry form, `prepareEntryRestoration`, `restoreEntryAndJournal`) or **Restore and Move…** (`Views/MoveEntryView.swift` with `restoring: true`, `JournalStore.restoreAndMoveEntry`). Open question D15.
- Journals: the deleted journal's page has **Restore Journal…** opening the Restore Journal sheet (`JournalLifecycleView`), a confirmation with the count, name-taken numbering, legacy-entry note and recovery paths.
- Templates: Restore at once, unchanged.
- [spec/screens/recently-deleted.md](../../spec/screens/recently-deleted.md), [spec/screens/restore-journal.md](../../spec/screens/restore-journal.md), [spec/screens/move-entry.md](../../spec/screens/move-entry.md), [flows/delete-and-restore.md](../../spec/flows/delete-and-restore.md).

### New behaviour: one Restore, acts at once, no sheet

Entries, templates and journals each have one restore action that acts immediately, as Restore does today for an entry. There is no confirmation sheet and no destination picker. The label is **Restore** when the entry returns to its own journal, **Restore to “{name}”** (`library.recentlyDeleted.restoreTo`) when it cannot, and **Restore Journal** on a deleted journal's page. The label always says where the entry goes, so the person never moves an entry across journals without being told at the moment they act.

**Where a restored entry goes.** The same rule on every device:

| Situation of the entry | Restore puts it in |
| --- | --- |
| Its journal is in use | That journal. Label: Restore. Pins, date, text and images are unchanged. |
| Its journal is in Recently Deleted | The **Default Journal** (Settings ▸ Default Journal, else the oldest journal in use). Label: Restore to “{Default Journal}”. The deleted journal stays deleted and keeps its other entries; restoring the journal is a separate action. |
| Deleted with its journal by an earlier version (legacy marker), journal in use | That journal. Label: Restore. |
| The entry has its own tombstone or a legacy marker and its journal is **missing or permanently deleted** (the entry is listed under Unavailable Journals). This includes an entry the revised H parked next to a permanent-deletion marker ([1-1-conflicts-and-reconnect.md](1-1-conflicts-and-reconnect.md), 3.4) when its journal is gone, and a legacy entry whose journal is missing | The Default Journal. Label: Restore to “{Default Journal}”, in the Unavailable Journals notice and the row's context menu and Entry Actions, never on a swipe. On a syncing library the notice also keeps Try Syncing Again (`common.journalNotArrived`), because a journal that merely hasn't arrived may still come. Move Entry does not apply: it refuses deleted entries. |
| Its journal is unsupported (saved by a newer version), or the journal or the entry has a **held** conflict | Not offered. After H a held conflict is treated like a newer-version record: the notice says `common.updateToRestoreEntry` and offers Export Archive… where it did; there is no "changes to review" state and no Review Changes button (H step 1 removes the journal review form and `common.journalNeedsReview`; H step 2 removes the entry review). |
| The entry itself was saved by a newer version | Not offered; unchanged. |
| No journal is in use at all | Not offered; the notice says `library.recoveryNotice.createJournalFirst`. |

Entries that are not deleted but whose journal is missing (nothing of their own is deleted) stay in Unavailable Journals as today and are not restorable: there is nothing to restore.

**Order with H.** N may ship before H step 1 only with the 1.0 wording kept for the changes-to-review row (`common.journalNeedsReview` with Review Changes, and Restore Journal disabled while the journal has changes to review); H step 1 then deletes that wording and the buttons. Written for the final state, which is the one specified in this record.

**Where the control appears.** The leading full swipe (iPhone, iPad) is offered only when the entry's own journal is in use, so a long swipe never files an entry somewhere unexpected. When the destination differs, Restore to “{name}” is in the row's context menu, Entry Actions and the notice button (all devices); the notice adds `library.recoveryNotice.journalDeleted` ("The journal is in Recently Deleted.") for a deleted journal. Because the destination is chosen when the control is drawn, the store decides again at the moment of the tap (next paragraph).

**One store operation decides the destination inside the transaction.** A new `JournalStore.restoreEntry(_ id:, fallback:)` replaces the UI's use of `restoreAndMoveEntry(entryID, to:)`. In one write transaction it requires the entry itself to be editable and to have no held conflict row (as `restoreAndMoveEntry` required), then uses the entry's own journal when that journal is live, supported and without a held conflict, else the fallback journal (which must be live, supported and without a held conflict). An absent journal, a permanent-deletion marker and a journal in Recently Deleted all mean "own journal not usable". It clears only that entry's own tombstone and legacy marker, and returns the saved entry and the journal it landed in. Nothing else is written. If neither journal qualifies it throws `messages.restore.destinationGone` and writes nothing. The pins in the library record are keyed by entry id and are untouched, so a restored entry keeps its pin and journal order is unaffected. The rule table above lives in this one operation, so other platforms port from the store contract and not from `AppModel`. The app passes the Default Journal as `fallback`, opens the returned journal with the entry (iPhone: the stack becomes [journal, entry]) and compares it with what the control named. If the entry did not return to its own journal, VoiceOver announces `messages.announce.restoredIn` naming the journal it actually went to; if the entry's own journal was restored by sync or another window between drawing and tapping, the entry simply goes home and nothing is announced. `restoreAndMoveEntry` is deleted once nothing else calls it.

**Agent access.** The restored entry follows the grants of the journal it lands in, exactly as a moved entry does; nothing about agent scope is special-cased. An entry in Recently Deleted is never readable by agents, so restoring in place changes nothing about who can read it, and restoring into the Default Journal makes it readable to a grant on the Default Journal and no longer to a grant on the old journal. This is why the cross-journal case is named in the control and kept off the swipe: it is the one place Restore can cross an agent boundary, and the person chooses it knowingly, like Move Entry. Test 3 asserts both cases on what the agent copy publisher publishes, not only on the store.

**Alternatives considered for an entry whose journal is deleted.**

- *Restore the entry's journal with it, "only this entry".* Rejected. The journal's other entries were deleted by inheritance (they have no tombstone of their own), so restoring the journal brings every sibling back; keeping them deleted would mean writing a tombstone into each sibling, a bulk rewrite of records the person did not touch that also syncs to every device. It also revives a whole journal, and numbers it if its name is taken, from one tap on one entry.
- *Not offering Restore for such an entry.* The person would have to restore the whole journal and delete what they do not want; no boundary is crossed, but a single rescued entry costs several steps.
- *Restore to the Default Journal, named in the control* (chosen). Changes exactly one entry, needs no sheet, and the destination is stated up front. It is the owner's single remaining decision, below.

Nothing is announced when the entry returns to its own journal. If the person wants a different journal they use Move Entry… afterwards.

**Restore Journal.** The deleted journal's page shows, in order: the name, `library.recentlyDeleted.journalCount`, `common.restoredAsRenamed` when the name is taken (the journal returns as "Work 2"; it stays directly above the button because it changes the result), the **Restore Journal** button, then `library.restoreJournal.explanation`, the legacy-entry note `library.restoreJournal.legacy` when it applies, and Delete Permanently…. The primary action therefore sits near the top even at the largest text sizes, and VoiceOver reaches it before the explanatory text. The sheet goes; its text moves here as secondary text. The journal returns to its place in the order or the end, with every entry deleted with it, including entries that sync later. Entries deleted separately stay in Recently Deleted and restore individually. On success the journal is shown.

Restore Journal is disabled while the library is being replaced. (There is no Review Changes button after H: a journal with a held conflict is treated like one saved by a newer version.) A journal saved by a newer version or with a held conflict shows `messages.unavailable.restoreJournalNeedsUpdate` and Export Archive… as today.

**Errors** (the general error alert, no sheet): the open entry could not be saved first (`messages.save.before.restoreEntry`, `...restoreTemplate` or `...restoreJournal`, which B later replaces with its two generic messages); the journal was restored elsewhere meanwhile (`messages.lifecycle.alreadyRestored`, then the journal is shown); the journal changed or vanished (`messages.lifecycle.missingJournal`, `messages.lifecycle.unsupportedJournal`); stored but not shown (`messages.refresh.journalRestored`, `common.entryMovedNotDisplayed`). The Review Entry recovery, the "changed, try again" states and the Try Again loop of the sheet disappear because nothing is previewed first; the store's atomic checks stay.

### Existing 1.0 data

All of it is ordinary records. Entries with their own tombstone, entries under a deleted journal, legacy `deletedWithJournal` markers, deleted journals (merged or not) and templates all restore by the rules above. Nothing is rewritten at upgrade.

### 1.0 devices

- A 1.0 device's Restore…, Restore and Move… and Restore Journal… produce ordinary updates (tombstone cleared, `journalID` changed, journal tombstone cleared). 1.1 reads them.
- A 1.1 restore into the Default Journal looks to a 1.0 device like any move out of Recently Deleted. A restore on 1.1 racing a restore of the same entry's journal on 1.0 gives an entry conflict, resolved as today.
- A parked entry (H) reaches a 1.0 device as an ordinary entry with `deletedAt` set; 1.0 can restore it with Restore and Move… and 1.1 with Restore to the Default Journal; both are ordinary updates.
- The Default Journal is a per-device setting. Two devices may therefore restore the same kind of entry into different journals; each result is a normal synced `journalID`, and each person saw the destination in the control.

### Menus, shortcuts and commands that disappear

| Command | iPhone | iPad | Mac |
| --- | --- | --- | --- |
| `restore-and-move` | recovery notice, Unavailable Journals notice | same | same |
| `restore-with-journal` | recovery notice | same | same |
| The Restore Journal… sheet (the command `restore-journal` stays and acts at once) | deleted journal's page: the button opens no sheet | same | same |
| `restore` | unchanged placement (leading swipe only when the entry returns to its own journal; context menu, Entry Actions, notice), shown in more situations and labelled with the journal when it differs | same | same (context menu, Entry Actions, notice; no swipe) |

No keyboard shortcuts were attached to any of them (the Restore Journal sheet had no Return default by design; Delete and ⌘⌫ still delete permanently). The Move Entry sheet loses its restoring form (`library.moveEntry.restoreTitle`, `library.moveEntry.onlyThisEntry`).

### Dead code and stored data that can go

`Views/JournalLifecycleView.swift`'s Restore Journal, Restore Entry and (already unreachable) Delete Journal modes, so the whole file once the three modes go (the Delete Journal alert is `JournalDeletionPrompt`), `AppModel.prepareEntryRestoration`, `restoreEntryAndJournal`, `commitEntryRestoration`, `reviewRestoredEntry` (`Model/EntryRestorationOperations.swift`), `JournalCore/EntryRestoration.swift` (`EntryRestorationPlan`, `prepareEntryRestoration`, `restoreEntryAndJournal`, `EntryRestorationError`) and its paragraph in [protocol/journal-lifecycle.md](../../protocol/journal-lifecycle.md), `MoveEntryView(restoring:)` and `moveEntry(restoring:)`, `JournalStore.restoreAndMoveEntry` (replaced by `restoreEntry(_:fallback:)`) and its protocol paragraph, the recovery notice buttons, `ArchivingProbe`'s use of `prepareEntryRestoration` (rewritten to restore the journal and then the entry), and the sheet's tests. No stored data goes.

## Menus and commands, per device, after this change

| Surface | iPhone | iPad | Mac |
| --- | --- | --- | --- |
| Journal actions (row context menu; edit-mode ⋯; list bar ⋯) | Rename…, Delete Journal… | same | Mac sidebar context menu and toolbar Journal Actions: New Journal…, —, Rename…, —, Delete Journal… |
| Template row and Entry Actions (template) | Image Descriptions… (if pictures), Version History…, Delete Template | same | same |
| Recently Deleted entry or template (row menu, Entry Actions) | Version History…, Restore, —, Delete Permanently… (Image Descriptions… if pictures) | same | same |
| Deleted journal's page | Restore Journal, Delete Permanently… | same | same |
| File menu | not applicable | New Entry ⌘N, New Journal… ⌥⌘N, Use a Template… | same |
| Empty entry | "Start writing or [symbol] use a template" | same | same |

## Copy and catalog changes

Run `python3 spec/tools/check-spec.py` after every step; unused keys show as warnings and are removed in the same change.

**Removed** (each only if no other screen still uses it; the implementer greps first):

- K: all of `library.journalHistory.*` (cantChange, confirm.current, confirm.explanation, confirm.nameTaken, confirm.restore, confirm.restoring, confirm.title, loadingSettings, restoreSettings, restored, templateDuplicate, unavailableTemplateNumbered), `messages.history.journalChanged`, `messages.history.settingsInUse`, `messages.save.before.restoreJournalSettings`.
- L: `library.journalActions.mergeInto`, all of `library.merge.*` (agents.gainingMany, gainingOne, losingMany, losingOne, unknown; created; destinationGone; displayFailed; footer.none, one, other, target, targetNone; header; hint; merged; title), `messages.merge.newerVersion`, `messages.save.before.mergeJournal`, `messages.generic.journalUnavailable`.
- M: `common.defaultTemplate`, `common.blankEntry` (also used by the journal review form: **H step 1 removes them if it lands first, otherwise M does**), `messages.conflict.journal.value.unavailableTemplate` (H step 1 removes it with `messages.conflict.journal.*`; M never lists it), `library.entryActions.newEntryIn`, `library.entryActions.newEntryFromTemplate`, `library.menu.file.newBlankEntry`, `library.menu.file.newEntryFromTemplate`, `library.templateChooser.journal`, `library.templateChooser.journalGone`, `messages.generic.journalNamedUnavailable`, `messages.generic.templateUnavailable`. (`messages.generic.templateNeedsReview` is **removed by H step 2**, which the conflicts record lists; M deletes its only caller, so until step 2 lands the key is unreferenced and the checker warns; whichever lands first removes it.)
- N: `library.recoveryNotice.restoreAndMove`, `library.recoveryNotice.restoreWithJournal`, `library.restoreEntry.*` (displayFailed, explanation, needsJournal, title), `library.restoreJournal.title`, `library.restoreJournal.reviewEntry`, `library.restoreJournal.unavailableLocal`, `library.moveEntry.restoreTitle`, `library.moveEntry.onlyThisEntry`, `messages.restore.alreadyRestored`, `messages.restore.changed`, `messages.restore.unavailable`, `messages.lifecycle.changedContinue`, `messages.save.before.openRestoredJournal`, `messages.save.before.reviewEntry`. **Keys this record does not remove because H does** ([1-1-conflicts-and-reconnect.md](1-1-conflicts-and-reconnect.md), 6.1 and 6.2): `common.journalNeedsReview` and `messages.lifecycle.needsReview` (changed to the update wording or removed) at step 1, and `common.reviewChanges` at step 2; N's text uses none of them. (`messages.save.before.restoreEntry`, `.restoreTemplate` and `.restoreJournal` stay: plain Restore uses them until B replaces them.)

**Changed text:**

| Key | Before | After |
| --- | --- | --- |
| `library.recentlyDeleted.restoreJournal` | Restore Journal… | Restore Journal |
| `library.recoveryNotice.legacy` | This entry was deleted by an earlier version of My Journal. Choose a journal to restore this entry. | This entry was deleted by an earlier version of My Journal. |

**Changed context only** (the text is the same, the "where it appears" line is rewritten): `common.restore`, `common.restoredAsRenamed` (now the deleted journal's page, before Restore), `library.restoreJournal.explanation`, `library.restoreJournal.legacy`, `library.recentlyDeleted.journalCount`, `common.journalNotArrived`, `common.journalGone`, `common.versionHistoryEllipsis`, `common.merge`, `common.merging`, `common.journalCount`, `messages.lifecycle.needsReview`, `library.templateChooser.title`, `library.templateChooser.popoverTitle`, `library.moveEntry.*` remaining keys, `library.entryList.empty.noTemplatesHelp` (unchanged text).

**Added:**

| Key | Text | Where |
| --- | --- | --- |
| `library.menu.file.useTemplate` | Use a Template… | File menu (Mac, iPad); same wording as `library.templateChooser.popoverTitle`, recorded in `copy/same-wording.json` (menu item against tooltip) |
| `library.templateChooser.entryChanged` | This entry changed, so the template wasn’t added. | General error alert after the chooser closes |
| `library.recentlyDeleted.restoreTo` | Restore to “{name}” | Context menu, Entry Actions and notice button of an entry that cannot return to its own journal; `{name}` is the Default Journal (`common.untitledJournal` when blank). The plain `common.restore` stays for the in-place case |
| `library.recoveryNotice.journalDeleted` | The journal is in Recently Deleted. | Notice line under `library.recoveryNotice.entry`, when the entry's journal is in Recently Deleted |
| `library.recoveryNotice.createJournalFirst` | Create a journal to restore this entry. | Notice, when no journal is in use |
| `messages.restore.destinationGone` | The journal to restore into is no longer available. Nothing was restored. | General error alert when neither the entry's journal nor the Default Journal can be used at the moment of the tap |
| `messages.announce.restoredIn` | Restored to {name}. | VoiceOver announcement after Restore put an entry in a journal other than its own |

## Layout and interaction notes per device

- **Mac.** Journal sidebar context menu and toolbar Journal Actions menu become short. The deleted journal's page is a scrolling column (28 points of padding as today). The chooser keeps its two containers; the File-menu sheet is 320 × 352 points (the picker row and its divider are gone). Return in the chooser still picks the highlighted template; Escape closes. No new shortcut is added: ⇧⌘N is freed, not reassigned.
- **iPad.** Same as Mac in regular width; in compact width the chooser from the link is a sheet. The ⌘-hold overlay lists New Entry, New Journal… and Use a Template….
- **iPhone.** No menu bar, so the link is the only entry point to the chooser. The Templates list is a plain list: tap to edit, swipe to delete. The leading full swipe restores a Recently Deleted entry only when its own journal is in use; for an entry whose journal is deleted, Restore to “{name}” is in the long-press menu, Entry Actions and the notice, and opens that journal and entry.
- No differences in behaviour between devices beyond the existing ones: the Mac has no swipe; the iPhone chooser is always a sheet.

## Accessibility

- File ▸ Use a Template… and the link open the same chooser; their VoiceOver names are "Use a Template…" (menu) and "Use a Template" (link). The menu is disabled, not hidden, when the link is not shown.
- `library.templateChooser.entryChanged` is shown in the general error alert (announced like any alert); focus returns to the entry.
- The notice sentences are read with the notice (one element per paragraph, as today). The destination is part of the button's own name ("Restore to Personal"), so VoiceOver and Voice Control users hear and say it before acting; `messages.announce.restoredIn` confirms it afterwards when the entry did not go home.
- The deleted journal's page keeps its heading, count and text as plain text; Restore Journal comes before the explanatory text and Delete Permanently… is last; both are buttons reachable by Full Keyboard Access and Voice Control by name ("Restore Journal"). Dynamic Type: all text wraps; the page scrolls and the primary action stays near the top. The UI journey includes one pass at an accessibility text size and one with VoiceOver.
- Removing sheets removes the focus handoffs they needed; after Restore the focus lands where it does for any Restore today (the opened entry's title is not forced).
- Reduce Motion and Increase Contrast: no animation or colour was added.

## Empty, offline and error states

- **No templates:** the chooser's menu item is disabled and the link is not shown (unchanged); the Templates list empty state is unchanged.
- **Chooser with the last template deleted meanwhile:** shows `library.entryList.empty.noTemplates` (unchanged); a highlighted template that leaves shows `library.templateChooser.templateGone`.
- **Offline or no server:** all four features are local operations; nothing in this record needs a connection. Restore results sync like any other change; a journal restored offline reaches other devices later.
- **Locked, or the library is being replaced:** Restore and the chooser are unavailable and close as they do today; no restore starts after locking.
- **No journal in use:** `library.recoveryNotice.createJournalFirst` instead of Restore for entries; templates and journals still restore.
- **The entry's own journal comes back between drawing the control and the tap:** the store sends the entry home; the app opens that journal and announces nothing.
- **Open entry cannot be saved:** the general error alert with the existing save-before message; nothing changes.

## Spec and documentation changes the implementation makes

In the same change as the code, per [spec/README.md](../../spec/README.md):

- **Remove:** `spec/screens/journal-history.md`, `merge-journal.md`, `restore-journal.md`; the matching pages, `index.md` rows and screenshots under `spec/platforms/apple/` (`journal-history-default`, `merge-journal-default`, `restore-journal-default`, `move-entry-restore-and-move` on all three devices) and `spec/platforms/windows/`, and their states in `design/spec-screenshots/capture.sh`.
- **Rewrite:** `screens/journals.md` (Purpose; journal actions table; delete the Default Template section; Rules), `screens/templates.md` (menus; remove the New Entry In sections and `After New Entry In`), `screens/template-chooser.md` (entry points, Journal picker, states, Rules), `screens/recently-deleted.md` (row actions, deleted journal page, recovery notice table), `screens/move-entry.md` (no restoring form), `screens/destination-journal.md` (entry points), `screens/entry-editor.md` (recovery notice band), `screens/unavailable-content.md` (Restore replaces Restore and Move…), `screens/conflict-review.md` and `flows/resolve-conflict.md` (drop the dimmed-actions lines for Default Template and Merge Into…), `flows/new-entry.md` (entry points, steps 4, Rules), `flows/delete-and-restore.md` (Restore section), `messages.md`, and the Apple and Windows notes for every page above.
- **`commands.md`** and both platforms' `commands.md`: delete `journal-default-template`, `merge-journal`, `journal-version-history`, `new-entry-in`, `new-blank-entry`, `new-entry-from-template`, `restore-with-journal`, `restore-and-move`; edit `journal-actions`, `new-entry`, `use-a-template` (add the File ▸ Use a Template… placement, scope `app`), `restore` (enabled when a destination exists; description names the destination rule), `restore-journal` (acts at once).
- **`parity.yaml`:** mark `journal-default-template`, `merge-journal`, `journal-version-history`, `new-blank-entry`, `new-entry-from-template` and `restore-and-move` as `not-applicable` on every platform with a reason ("Removed in 1.1, simplification K/L/M/N; see docs/design/1-1-library-simplifications.md"); retitle `new-entry`, `templates-collection`, `template-chooser`, `template-suggestion`, `restore-entry`, `restore-journal`; drop `screens/merge-journal.md` from `unique-journal-names`. `reference` stays `apple`.
- **`copy/en.json`, `copy/same-wording.json`:** as in the copy section.
- **`open-questions.md`:** mark B21 (merge footer), B22, D14 (K, L, M parts), D15, D16 and B11 (merge and chooser wordings) "Resolved in 1.1 by simplification X"; A47 and A40 (journal pickers in the merge and journal history screens) as "Not applicable after 1.1"; keep "still open for 1.0" wording that is already there.
- **Protocol (no version bump; one additive fixture).** Prose edits: [protocol/records.md](../../protocol/records.md) describes `defaultTemplateID` as legacy (written by versions up to 1.0; 1.1 and later neither show nor use it; every client keeps it unchanged when it saves a journal; archive import and merge keep remapping it). [protocol/history-recovery.md](../../protocol/history-recovery.md): the intro, the "Restore journal settings" section and the Tests paragraph lose the journal-settings parts. [protocol/journal-lifecycle.md](../../protocol/journal-lifecycle.md): remove `prepareEntryRestoration` / `restoreEntryAndJournal`, replace `restoreAndMoveEntry` with the one `restoreEntry(_:fallback:)` rule (own journal when live, else the fallback, decided in the transaction; an absent or permanently deleted journal counts as not usable, so a deleted entry whose journal is gone can be recovered, which the "ordinary missing-parent entries stay read-only" sentence must allow for entries with their own tombstone) and fix the Tests paragraph; the "Journal names" section drops "restoring a name from Version History" from the local writes that refuse a taken name. None of this changes a wire or archive layout, so no version is bumped. The new writer rule gets an **additive** file under `protocol/conformance/records/` (for example `journal-rewrite-v1.json`, not an edit of `records-v1.json`): a journal with `defaultTemplateID` and a rename applied, with the members expected after the rewrite; the folder README and the Swift conformance test are extended, and the server's `RecordConformanceTests` if it iterates the folder. Windows and Android clients must pass it, so a client that drops the field on Rename fails a test instead of silently breaking 1.0 devices.
- **Documents outside the spec:** [docs/design/README.md](README.md) (add this record; mark the records it amends: history-recovery, journal-name-uniqueness §5, journal-lifecycle-ui, new-entry-template-suggestion, template-journal-choice-2026-10-03, default-journal, no-built-in-templates-2026-10-04); `README.md` feature list; `docs/guide/getting-started.md` (New Entry, Templates, and a sentence on Rename for numbered duplicate journals); `docs/app-store/listing.md` (both "Each journal can have a default template" lines and the feature table), `review-notes.md` and `screenshots-plan.md` (File > New Entry from Template…, seeded default templates); `scripts/test-native-accessibility.sh` test names. The 1.0 App Store listing advertises a default template per journal, so 1.1 removes a listed feature of a one-time purchase: the listing, README and guide change in the same release as the code, and the 1.1 release notes name the change in plain words ("A journal's default template is gone; use a template from inside a new entry"). There is no in-app note.
- **Journal name uniqueness:** edit [journal-name-uniqueness.md](journal-name-uniqueness.md) sections 4.5, 4.6 and 5 and its Merge Journals footer decisions (Rename replaces Merge Into… and the earlier-name-in-history remedy).
- **Housekeeping the checker and reviewers will otherwise catch:** the retitled features `restore-entry` and `restore-journal` must keep a spec file once `screens/restore-journal.md` goes, so move them to the front matter of `flows/delete-and-restore.md` and `screens/recently-deleted.md`; the removed features are marked `not-applicable` on **all three** platforms in one edit (the checker rejects `apple: not-applicable` on a feature whose reference is Apple otherwise); Windows notes and `copy-proposals.md` that mention removed keys change in the same commit, checking first that `messages.lifecycle.alreadyDeleted` and other keys the delete flows use stay; the iPad capture is refreshed for the ⌘-hold overlay.
- Screenshots come from `design/spec-screenshots/capture.sh` only, from the seeded sample library.

## Tests

Only tests that protect a behaviour that could plausibly break. Delete, rather than rewrite, tests that only exercised the removed features (`MergeIntoTests`, journal parts of `HistoryRecoveryTests`, `EntryRestorationTests` and `EntryRestorationLifecycleTests`, the New Entry In and picker cases of `TemplateSuggestionTests` and `PinnedListTests`, and the UI tests for Merge Into…, journal Version History, Restore Journal sheet, Restore and Move and New Entry In).

**JournalCore, real isolated stores:**

1. **`defaultTemplateID` survives every 1.1 journal write path.** A journal record with `defaultTemplateID`, written as 1.0 writes it, goes through Rename, Delete Journal, Restore Journal, conflict resolution (the automatic outcome of the revised H: a 1.0 device changed `defaultTemplateID`, a 1.1 device renamed the journal, and the resolved record keeps the local `defaultTemplateID`), archive import and merge remapping, and a sync to a second store; after each, the field is present (remapped where remapping is the rule). A second record with an unknown member is neither rewritten nor made editable by any of them. One test, plus the additive conformance fixture for the Rename case.
2. **A 1.0 merge arrives intact.** Build the result of a 1.0 Merge Into… from records (entries moved to B, A tombstoned, one deleted entry left deleted), sync it to a 1.1 replica: A is in Recently Deleted with no entries, restores as an empty journal, and the deleted entry restores into B. Replaces the replication case of `MergeIntoTests`.
3. **Restore destination, decided in the transaction.** With a real store: an entry under a deleted journal lands in the fallback journal and the deleted journal is untouched; a legacy-marker entry with a missing journal lands in the fallback; an entry whose journal is in use returns there; a parked entry (own tombstone) whose journal was permanently deleted, and one whose journal is missing, restore into the fallback and appear in the list; when the entry's journal is restored **between preparing the control and committing**, the entry goes home, not to the fallback; an entry with a held conflict row is refused; with no usable journal nothing is written; no sibling record changes. Agent scope, asserted on the agent copy publisher's output after republishing: a grant on the destination sees the entry, a grant on the old journal no longer does, and an entry restored in place is published as before.

**App model:**

4. **New Entry ignores a stored default template.** In a journal whose record names an existing template, New Entry creates an empty entry.
5. **The chooser never creates.** Choosing a template after the entry gained text changes nothing, creates nothing, and reports `library.templateChooser.entryChanged`.

Do not add a test that only proves a removed menu item is absent; the UI journey covers it.

**iOS UI, one realistic journey on long-lived state:** delete a journal that has entries; in Recently Deleted swipe-Restore an entry whose own journal is in use, then Restore to “{name}” from the long-press menu on an entry whose journal is deleted (it opens in the Default Journal, with the journal selected); open the deleted journal and press Restore Journal (no sheet), the remaining entries return; then check that Journal Actions lists Rename… and Delete Journal… only, that a template's menu has no New Entry In, and that "use a template" fills a new empty entry. Add one pass at an accessibility text size and one with VoiceOver on the deleted journal's page (Restore Journal reachable first). Mac: a manual pass on the File menu (Use a Template… enabled with an empty entry open and disabled with an entry that has text; New Blank Entry and New Entry from Template… gone), because menu bar items are not covered by the iOS lane. Record screenshots with the capture script.

Run `scripts/check.sh` lanes `apple` and `hygiene`, and the end-to-end sync probe (`scripts/test-sync.sh`) because `AgentJournalsProbe` and `ArchivingProbe` change.

## Decision for the owner

**May Restore put an entry in the Default Journal when the entry's own journal is gone?** "Gone" covers a journal in Recently Deleted, a journal that is missing, and a journal that was deleted permanently (which is where an entry the revised H parked next to a permanent-deletion marker ends up). Recommended: yes, named in the control (Restore to “{name}”), never on the swipe, decided in the store transaction, and subject to the destination's agent grants like Move Entry. Without it a parked or legacy entry whose journal no longer exists can't be recovered at all, because Move Entry refuses deleted entries. The alternative that never moves an entry across journals is to offer Restore only when the journal is in use, which leaves such entries stuck (or, for a deleted journal, requires restoring the whole journal first and deleting the unwanted siblings again). Restoring the journal "with only this entry" is rejected because it needs a tombstone written into every sibling. This is a product choice because Restore, unlike Move Entry, is not usually thought of as choosing a journal, and it moves an entry across an agent grant.

Decided in this revision, no longer open: File ▸ Use a Template… stays and ⇧⌘N and New Entry from Template… go (a command without a menu route fails the keyboard, Voice Control and native-menu requirements); people who used default templates are told by the release notes, the guide, and the App Store description changed in the same release, with no in-app note.

## Risks

- **Behaviour change for default-template users.** A person who wrote every entry from a default template now gets blank entries on 1.1 and needs a tap or click per entry (⌘N is blank, ⇧⌘N is gone), with no in-app explanation; the release notes, guide and App Store description say so. The data is intact and the template still works through the chooser.
- **Mixed-version libraries behave differently per device** (1.0 still fills new entries from a default template; 1.1 does not). Accepted, but support questions are likely during the transition.
- **Preserving `defaultTemplateID` depends on the model keeping the field through every save path.** If any 1.1 write path rebuilds a journal from shown fields only, 1.0 devices lose the setting and could conflict. Test 1 guards it; reviewers should look at the journal save paths (`editJournal`, Rename, restore, import, merge remapping).
- **Restore no longer previews.** The sheet absorbed several races (journal changed meanwhile, conflicts). The store operations still validate atomically (and `restoreEntry` decides the destination inside the transaction), but the person now sees an error alert instead of a refreshed plan. The journal page therefore shows the count and rename note before Restore Journal is pressed.
- **Costs of N.** The old Restore… could return one entry to its own deleted journal without reviving its siblings. After N the choices are Restore Journal (every entry deleted with it) or Restore to the Default Journal and then Move Entry….
- **Moving entries by hand replaces Merge.** There is no bulk Move Entry and, by the owner's decision of 2026-10-09 (D13), no multiple selection. Rename covers the common duplicate; combining two large journals gets slower.
- **An entry restored into the Default Journal crosses journal and agent-grant boundaries** when the Default Journal is an unrelated journal. Mitigated by naming the journal in the control, keeping it off the swipe, the visible navigation and the announcement.
- **Protocol wording.** The reviewer confirmed there is no wire or archive change and so no version bump; the additive conformance fixture is the guard for the writer rule.
- **Order of work.** H (journal review form) and A (dead code) touch the same files (`JournalConflictView`, `JournalSettingsView`, `JournalLifecycleView`). K ships with or after H step 1 (see K for the accepted loss of a losing journal name's history); N is written for the post-H world (no journal Review Changes) and ships before H step 1 only with the old wording. Landing M first leaves a default-template line in the journal review until H removes the form; the plan above drops the line if H has not landed.

## Independent review (date 2026-10-09)

Reviewer: independent design agent, given the owner-approved scope (K to N), the 1.0 and 1.1 constraints and this proposal. Claims were checked against `apps/apple` and `spec/`; where the proposal's file references were wrong or incomplete, the finding says so.

**Verdict: approve with changes.** No Blocker. The shape is right: nothing is migrated, no record is rewritten, the one path left for templates is the one that works on all three devices, and plain Restore is the right model for Recently Deleted. The wire format is untouched, so no protocol version bump is needed (finding 4). Four Material findings need a decision or a text change before implementation: the restore destination can move an entry across an agent-access boundary without saying so (1), the destination is decided in the UI instead of in the store transaction (2), the claim about unknown members is wrong and its test would not test the risk (3), and Merge Into… is removed without an honest replacement for the numbered duplicates the app itself creates (5). The record needs no second full review, but findings 1 and 2 change the specified behaviour of N, so the owner should confirm the revised Restore rule when answering decision 1.

### Material

1. **Material: Restore into the Default Journal silently changes which journal, and so which agent grants, can see an entry.** Agent access is journal-scoped ([AGENTS.md](../../AGENTS.md), "Security and agent access"). An entry from a "Work" or "Therapy" journal that is restored into the device's Default Journal becomes readable by an agent granted that journal, and the person is told nothing at the moment they press Restore on the leading swipe, in the context menu or in Entry Actions: the proposal's only warning is the notice inside the open entry. Merge Into… carried an explicit agent sentence (`library.merge.agents.*`); L removes it and N adds an implicit move with none. Move Entry has no such sentence either, but there the person chooses the destination. The Default Journal is a per-device setting, so two devices also file the same kind of entry in different journals. Fix: (a) show the destination where the person acts: when the destination is not the entry's own journal, the context menu, Entry Actions and the notice button read `Restore to “{name}”` (new key; the plain `common.restore` stays for the in-place case); (b) offer the full leading swipe only when the entry's own journal is in use, so a long swipe never moves an entry anywhere unexpected; (c) say in the record that the restored entry follows the destination's agent grants exactly as Move Entry does, and add one assertion to test 3: an entry restored into a journal with an agent grant is visible to that grant and an entry restored in place is unchanged. Decision 1 then becomes a real owner decision between "Default Journal, named in the control" (recommended) and "restore the entry's journal with it" (not recommended: it revives siblings and a whole journal from one tap).

2. **Material: the destination is chosen from a UI snapshot, but the store only checks what it is told.** The proposal reuses `restoreAndMoveEntry(entryID, to:)`, whose guard only requires the target to be live and the source journal to be editable and conflict-free ([Store.swift](../../apps/apple/Packages/JournalCore/Sources/JournalCore/Store.swift), `restoreAndMoveEntry`). If the entry's journal is restored by sync or by another window between the moment the notice or menu was drawn ("restores to “Personal”" or "restores in place") and the tap, the app still passes the Default Journal and the entry lands in the wrong journal although its own journal is now live. The old sheet absorbed this with its plan check. Fix: add one store operation (for example `restoreEntry(_:fallback:)`) that, in the one write transaction, uses the entry's own journal when it is live and supported, else the fallback, and returns where it went; the app compares the result with what it showed and posts `messages.announce.restoredIn` only when they differ. Add a test with a journal restored between preparing and committing. This also keeps the rule table in the record in one place (the store) for the other platforms to port from, instead of in `AppModel`.

3. **Material: ground rule 2 and test 1 rest on a wrong premise about unknown members.** The record says a 1.1 client keeps `defaultTemplateID` "and every unknown member" when it saves a journal for another reason. In the code a record with any unknown member is not editable: `PortableRecord.decode` keeps the original bytes in `preservedJSON` and sets the document version to `Int.max` (the `knownRecord` check), so Rename and Restore refuse it and never rewrite it ([PortableRecord.swift](../../apps/apple/Packages/JournalCore/Sources/JournalCore/PortableRecord.swift); the conformance rule `rewrite: unchanged`). So the unknown-member half of test 1 is already covered by `records-v1.json` and tests nothing new, while the real risk, `defaultTemplateID` (a known member) being lost, is the part that matters: every journal save path copies the whole `JournalItem` today (`editJournal` takes the latest item and mutates one field), and the risk is a future edit that builds a journal from shown fields only. Fix: reword rule 2 to "keeps `defaultTemplateID`" (unknown members make the record read-only, as today); make test 1 a real round trip through each journal write path that exists in 1.1 (Rename, Delete Journal, Restore Journal, conflict resolution keeping the local version, import and merge remapping), asserting `defaultTemplateID` and that a record with an unknown member is neither rewritten nor made editable.

4. **Material (confirms the proposal's reading, with one addition): no protocol version bump, but add a fixture for the new writer rule.** Nothing on the wire, in the record layout, in the archive or in the sync API changes: `defaultTemplateID` stays an optional member that readers parse and writers may omit, so a 1.0 reader and a 1.1 reader agree on every existing record, and the removed operations (`restoreJournalSettings`, `prepareEntryRestoration`, `restoreEntryAndJournal`, `mergeJournal`) are client behaviour described in prose, not contracts with fixtures. A bump here would only force needless fixture churn. But the proposal adds a new normative sentence to `protocol/records.md` (every client keeps the field unchanged when it saves a journal), and no fixture can fail a client that breaks it: a Windows or Android client could pass every existing record case while dropping the field on Rename, and Apple 1.0 devices would then lose the setting. Interoperability is a product requirement. Fix: keep the version, and add an additive fixture file under `protocol/conformance/records/` (a new file such as `journal-rewrite-v1.json`, not an edit of `records-v1.json`): a journal with `defaultTemplateID` and a rename applied to it, with the expected members after the rewrite; extend the folder README and the Swift conformance test. The records README paragraph on `rewrite` already supports this reading. Also update two prose spots the proposal's protocol list misses: the "Journal names" section of `protocol/journal-lifecycle.md` (local writes include "restoring a name from Version History", which no longer exists) and the intro and test paragraph of `protocol/history-recovery.md`.

5. **Material: Merge Into… and journal Version History are the documented remedies for duplicates the app creates by itself, and the replacement is understated.** [journal-name-uniqueness.md](journal-name-uniqueness.md) (sections 4.5, 4.6 and 5) makes sync, import and Merge Journals add a number ("Travel 2") without asking, and names Merge Into… as the way to combine afterwards and Version History as where the earlier name is kept. Those are not user mistakes: two devices that each created "Work" offline end up with two real journals, possibly hundreds of entries each. After K and L the only combine path is Move Entry, one entry at a time, and the entry list has no multiple selection ([spec/screens/entry-list.md](../../spec/screens/entry-list.md): "there is no multiple selection"), so each move opens the entry and a sheet. The record offers this and promises a follow-up "if this proves too slow", which is not a plan. Fix: (a) say in the record that the common case needs no merge: Rename the numbered journal ("Work 2" to something meaningful); duplicates are harmless; put that sentence in `docs/guide/getting-started.md` next to Move Entry; (b) decide now, not later, whether multi-select Move Entry is in 1.1 (the owner approved the removal, not leaving it without a bulk path), and if it is deferred, list it in release-1-1-scope.md "Also in 1.1" or the backlog with that reason; (c) edit [journal-name-uniqueness.md](journal-name-uniqueness.md) sections 4.5, 4.6 and 5 and the "Merge Journals" footer decisions so no record still promises Merge Into…. Also note in K that an automatically renamed journal's earlier name is no longer visible anywhere in the app.

### Minor

6. **Minor: `restoreElsewhere` copy is ambiguous.** "Its journal isn’t available." follows "This entry is in Recently Deleted." and "isn’t available" also describes unsupported and missing journals, which this notice never covers. Use the precise cause: `The journal is in Recently Deleted. Restore puts this entry in “{name}”.` For the legacy notice, `This entry was deleted by an earlier version of My Journal.` plus the same sentence when the journal is gone. Keep `{name}` as `common.untitledJournal` when blank. With finding 1 the button already says `Restore to “{name}”`, so this sentence can shrink to `The journal is in Recently Deleted.`

7. **Minor: the chooser's inline error cannot be acted on.** `library.templateChooser.entryChanged` leaves the chooser open with the same list, so choosing again fails the same way. Close the chooser and show the message as the general alert, or disable the list when it appears. Keep the text; it is plain and matches `templateGone`. If the entry itself was closed, the chooser should just close.

8. **Minor: place Restore Journal first on the deleted journal's page.** The proposal puts the button after four blocks of secondary text; at the largest Dynamic Type sizes the page scrolls and the primary action sits below the fold, and VoiceOver users must swipe through all the text before the button. Put name, count, then the **Restore Journal** button, then the explanation, legacy note and rename sentence (the rename sentence stays directly above the button if it applies, since it changes the result). Add an accessibility-size and VoiceOver pass to the UI journey.

9. **Minor: decisions 2 and 3 should be decided, not asked.** Decision 2: keep File ▸ Use a Template…. A command with no menu route fails the project's keyboard, Voice Control and native-menu requirements on Mac and iPad, and the cost is one item replacing another. Decision 3: release notes and the guide are enough, but record one fact the proposal omits: the 1.0 App Store listing says "Each journal can have a default template" (`docs/app-store/listing.md`, twice), so 1.1 removes a listed feature of a one-time purchase. The listing, the README and the guide must change in the same release, and the 1.1 release notes must name the change; an in-app note is not needed. Decision 1 stays an owner decision (finding 1).

10. **Minor: costs of N to state plainly.** The old Restore… could return one entry to its own deleted journal without reviving its siblings. After N the choices are Restore Journal (all entries deleted with it) or Restore to the Default Journal and Move Entry. Say so under Risks. Also name the lost one-keystroke path: ⌘N is blank, ⇧⌘N is gone, and a default-template user now needs a click or tap per entry.

11. **Minor: order of work with H.** K removes the only screen that shows the version kept back by a journal conflict review. This is safe only while the journal review form (H, step 1) lets the person choose the version explicitly; if K ships without H step 1, the version not kept is in history that nothing shows. State that K ships with or after H step 1, or that the conflict path keeps both journals (numbered) instead.

12. **Minor: housekeeping the implementer would otherwise miss.** The retitled features `restore-entry` and `restore-journal` must keep a spec file once `screens/restore-journal.md` goes (move them to `flows/delete-and-restore.md` and `screens/recently-deleted.md` front matter; `check-spec.py` will fail otherwise). `parity.yaml` marks `apple: not-applicable` on features whose `reference` is apple; that is allowed only when all three platforms are `not-applicable` (as the proposal says), so mark all three in one edit. Windows notes and `copy-proposals.md` mention removed keys (`messages.lifecycle.alreadyDeleted` stays in use by delete flows, check before removing); those pages are the owner's own plans, but change them in the same commit and say so. The "also in the ⌘-hold overlay" lines need the iPad capture refreshed.

13. **Minor: tests.** Keep the list short; the five tests plus the UI journey are right. Change test 3 to cover finding 2 (journal restored between preparing and committing) and the agent-scope assertion of finding 1; test 1 as in finding 3. Do not keep a test that only proves a hidden menu item is absent (the journey covers it). Add to the Mac manual pass the File ▸ Use a Template… disabled state with an entry open that has text.

### Checked and found accurate

- `defaultTemplateID` is read and written only as listed; `JournalItem` copies it through `editJournal`, `ContentImport` and `MergePlan` (both remap it), so keeping the field costs nothing.
- Journal history rows are written only by Restore Settings and conflict review; checkpoints exclude journals ([version-checkpoints.md](version-checkpoints.md)).
- A 1.0 merge is ordinary entry updates plus one journal tombstone ([JournalMerging.swift](../../apps/apple/Packages/JournalCore/Sources/JournalCore/JournalMerging.swift)); a merged-away journal restores as an empty journal, as the record says.
- The template chooser and the empty-entry link already exist on all three devices with the conditions the record describes (`TemplateSuggestion.resolve`), and `fillEmptyEntry` already refuses a non-empty body, so "never creates" needs only the removal of the fallback.
- `AgentJournalsProbe` (`mergeJournal`) and `ArchivingProbe` (`prepareEntryRestoration`) are the only non-UI callers; both need rewriting as the record says.

## Changes after review

| Finding | What changed |
| --- | --- |
| 1 Agent boundary | Evaluated "restore the journal too, with only this entry" (rejected: siblings were deleted by inheritance, so it needs a tombstone written into each of them and revives a whole journal) against "Default Journal, named in the control" (chosen). Control reads Restore to “{name}” (`library.recentlyDeleted.restoreTo`) in the context menu, Entry Actions and notice; the full swipe is offered only when the entry returns to its own journal; the agent-scope rule (follows the destination's grants, as Move Entry) is written down and asserted in test 3. This stays as the one owner decision, with "do not offer Restore for such an entry" as the alternative that never crosses a boundary. |
| 2 Destination in the store | New `restoreEntry(_:fallback:)` decides own journal or fallback in one transaction and returns where it landed; the app announces only when the entry did not go home; `restoreAndMoveEntry` goes; race test added to test 3. |
| 3 Unknown members | Ground rule 2 reworded (unknown members already make a record read-only); test 1 is now a round trip through each 1.1 journal write path asserting `defaultTemplateID`, plus the unknown-member record staying unrewritten. |
| 4 Protocol | No version bump kept; an additive fixture file under `protocol/conformance/records/` is in the plan (not created now); prose edits listed for `records.md`, `history-recovery.md` (intro, journal-settings section, tests) and `journal-lifecycle.md` (entry restoration, `restoreEntry` rule, Journal names list). |
| 5 Duplicates | L now says Rename is the answer for numbered duplicates and the guide says so; multi-select is out of 1.1 (D13, 2026-10-09) and no follow-up is promised; the plan edits `journal-name-uniqueness.md` 4.5, 4.6, 5 and the footer decisions; K notes that an automatically numbered journal's earlier name is no longer visible. |
| 6 Notice copy | `restoreElsewhere` replaced by `library.recoveryNotice.journalDeleted` ("The journal is in Recently Deleted."); the destination is in the button. |
| 7 Chooser error | The chooser closes and the message is the general alert; a closed entry just closes the chooser. |
| 8 Restore Journal order | Name, count, rename sentence, then the button, then explanation and legacy note; accessibility-size and VoiceOver passes added to the journey. |
| 9 Decisions 2 and 3 | Decided and removed from the owner list; the 1.0 listing's "default template" lines, README and guide change in the same release and the release notes name it. |
| 10 Costs of N | Listed under Risks, with the lost one-keystroke path. |
| 11 Order with H | K ships with or after H step 1. |
| 12 Housekeeping | Added: features keep a spec file, all three platforms `not-applicable` in one edit, Windows notes and copy proposals in the same commit, iPad overlay capture. |
| 13 Tests | Test 3 covers the race and agent scope, test 1 as in finding 3; no absent-menu-item test; File ▸ Use a Template… disabled state added to the Mac pass. |

## Second independent review (2026-10-09)

**Verdict: approve with changes.** No Blocker. All thirteen findings of the first review are resolved in the body: the destination is named where the person acts (`Restore to “{name}”`, context menu, Entry Actions and notice; the full swipe only when the entry returns to its own journal); the agent rule and its test are written down; the destination is decided inside one store transaction (`restoreEntry(_:fallback:)`) and the race test is in; ground rule 2 and test 1 are corrected to the known `defaultTemplateID` field; the additive `journal-rewrite-v1.json` fixture and the prose edits to `records.md`, `history-recovery.md` and `journal-lifecycle.md` (including the "Journal names" sentence, which I confirmed still names "restoring a name from Version History") are planned; the numbered-duplicate answer is Rename and D13 is cited; Restore Journal comes before the explanation; the chooser closes and the alert carries the message. Three Material points remain, all caused by the revised conflicts record rather than by this one, and the table in N has a hole that the revised H makes reachable. They are edits to this record; no re-review is needed once they are made.

Method: I read the record against `Store.swift` (`restoreAndMoveEntry`, `moveEntry`, `restoreTemplate`), `JournalLifecycle.swift` (`location(of:)`, `deletionPlan`), `AgentCopyPublisher.swift` (the published-entry filter), `protocol/journal-lifecycle.md`, `protocol/permanent-deletion.md` and the revised [1-1-conflicts-and-reconnect.md](1-1-conflicts-and-reconnect.md). I did not run anything.

### Restore destination rule, transaction, agent scope: what I re-checked

- **Rule.** For every row of the table the result matches the code I read: an entry whose own journal is live goes home; an entry under a deleted journal goes to the fallback and the deleted journal is not touched (`location(of:)` puts it in Recently Deleted through the parent's `deletedAt`, so no sibling needs a tombstone, which is why "restore the journal with only this entry" was correctly rejected); a legacy `deletedWithJournal` entry is cleared by the same operation. The 1.0 data section is accurate: nothing is rewritten at upgrade.
- **Transaction.** Deciding inside the write is the right shape; it removes the UI snapshot problem and puts the rule where Windows and Android will port it from. The returned landing journal drives navigation and the announcement. One more guard to state: the fallback journal must also be checked for a conflict row on the entry itself, as `restoreAndMoveEntry` does with `requireNoConflict(entryID)`.
- **Agent scope.** Confirmed in `AgentCopyPublisher`: an entry is published only when its journal is shared and live and the entry has no `deletedAt`, no `deletedWithJournal` and is not a marker, so an entry in Recently Deleted is never readable, restoring in place changes nothing for the grants it had, and a restore into another journal changes `journalID` and so the grant that sees it. The swipe exclusion and the named control are the right mitigation, and the question stays a genuine owner decision (it is a product choice and a security-boundary choice at once). Test 3 should assert the publisher's result, not only the store's: a grant on the destination sees the entry after the republish, and a grant on the old journal no longer does.

### Material

**1. The Restore table has no row for an entry with its own tombstone whose journal is missing or permanently deleted, which the revised H creates (N, Where a restored entry goes). Material.** The revised conflicts design (section 3.4) parks the edit of a permanently deleted item as a new entry with `deletedAt` set, and when its journal is also permanently deleted or missing the entry is shown in Unavailable Journals (`location(of:)` returns `.unavailable(.missing)`), where that record says "Move Entry brings it into a journal". It does not: `moveEntry` refuses a deleted entry (`guard entry.deletedAt == nil, !entry.deletedWithJournal`, `Store.swift:263`), and `protocol/journal-lifecycle.md` says ordinary missing-parent entries stay read-only; the only operation that recovers one today, `restoreAndMoveEntry`, is deleted by N, and the new `restoreEntry` table covers "legacy marker, journal missing" but not "own tombstone, journal missing or permanently deleted". After N and H such an entry cannot be recovered. Fix: add the row (the entry has its own tombstone and its journal is missing or is a permanent-deletion marker: Restore puts it in the Default Journal; label `Restore to “{name}”`; offered in the Unavailable Journals notice and the row menu, never on a swipe); make `restoreEntry` accept a stored marker journal and an absent journal as "not usable, use the fallback" for any entry whose own record is editable; add it to protocol `journal-lifecycle.md` and a case to test 3 (a parked entry whose journal was permanently deleted restores into the fallback and the result is visible in the list). The conflicts record is edited to say Restore, not Move Entry (its second-review finding 4).

**2. K's order-of-work paragraph is now wrong (K, Order of work with H, Existing 1.0 data, Risks). Material.** K says it "must not ship while any journal conflict path still writes a version into history that nothing shows", and treats "the app keeping both journals, numbered" as the H outcome. The revised H does the opposite: for a journal renamed on two devices the local name stays and the other version goes to the record's history (conflicts 3.5, row 6) with a 30-day note on the resolving device only. After K nothing shows that history. So shipping K with H step 1 does exactly what K forbids, and "H decides what remains of those" in the Existing 1.0 data table is not an answer. The cost is real but small (a rename is overwritten, as the library record is). Fix: rewrite the paragraph to state the truth: with H step 1 and K, a name that loses a journal rename is visible only in the Changed on Two Devices note and in a history row nothing displays; say that this is accepted, or have H keep the note until cleared (conflicts review, finding 10), and drop the numbered-journals alternative. If the owner will not accept this, K ships after H step 1 only with that note change. Decide it here, since K is the record that removes the screen.

**3. N refers to journal review that H removes (N rows, Restore Journal, copy lists). Material.** The "Its journal is unsupported or has changes to review" row, `common.journalNeedsReview` with Review Changes, the sentence "Restore Journal is disabled while the journal has changes to review (its page still shows Review Changes)", and "Review Entry" all assume the 1.0 journal review. H step 1 deletes the journal review form, the Review Changes buttons on the deleted journal's page and the recovery notice, and `common.journalNeedsReview` itself (conflicts section 6.1), and after step 2 a conflict exists only as a held row for an unreadable version. Both records list the same keys and files as removed and edit the same views (`DeletedJournalView`, `EntryRecoveryNotice`, `JournalLifecycleView`). Fix: write N against the post-H world: a journal or entry with a held conflict is treated like an unsupported one (the update wording, no button); no "changes to review" state remains; state the order (N may ship before H step 1 only with the old wording, and that wording is then deleted by H) and name which record removes `common.journalNeedsReview`, `messages.lifecycle.needsReview` and `messages.generic.templateNeedsReview` (the conflicts list also removes the last one; this record lists it under M).

### Minor

**4. State what Restore leaves alone (N). Minor.** A restored entry keeps its pin and the pins and journal order are unaffected; say so for the cross-journal case, since the library record holds pins by entry id and a reader will otherwise wonder.

**5. Error text when the fallback disappears (N, Errors). Minor.** If the Default Journal was deleted between the tap and the transaction, `restoreEntry` throws the destination-unavailable error, whose existing text is "This journal is unavailable." That reads as a statement about the entry. Use `messages.lifecycle.missingJournal`'s wording only if it says nothing was restored, or add one sentence ("Nothing was restored.") to the alert text.

**6. Test 1 and automatic journal conflicts (Tests). Minor.** "Conflict resolution keeping the local version" is now the automatic row 6 of the conflicts design. Add the case where a 1.0 device changed `defaultTemplateID` and a 1.1 device renamed the journal: the resolved record keeps the local `defaultTemplateID`, which silently replaces the 1.0 device's choice. State in the Mixed-version section that this is accepted (the setting is ignored by 1.1) so the first 1.0 user who notices has an answer.

**7. Housekeeping. Minor.** The conflicts record removes `messages.generic.templateNeedsReview` and `common.journalNeedsReview`; this record lists both as removed by M and as still used. Say which record deletes each so `check-spec.py` neither warns about a still-used key nor leaves an unused one.

### Owner decision: genuine?

Yes. Whether Restore may place an entry in the Default Journal when its own journal is deleted is a product choice that also moves an entry across an agent grant, and the recommendation (named control, no swipe, decided in the transaction, destination grants apply) is a sound default. With finding 1 the decision also covers entries whose journal was permanently deleted, which the owner should be told when deciding.

### Resolution

First-review findings: all resolved in the body. New: findings 1 to 3 (Material) are edits to this record; finding 1 depends on the conflicts record's matching edit. No second full review is needed.

## Changes after the second review

| Finding | What changed |
| --- | --- |
| 1 Parked entries | N's table has a new row: an entry with its own tombstone or legacy marker whose journal is missing or permanently deleted (including an entry H parked) restores into the Default Journal as Restore to “{name}”, in the Unavailable Journals notice and the row menus, never on a swipe. `restoreEntry` treats an absent journal, a permanent-deletion marker and a deleted journal alike as "own journal not usable" and also requires the entry to be editable and without a held conflict. The protocol prose edit and a test-3 case are added; the conflicts record must say Restore, not Move Entry (edit to be made there). The owner decision now says "gone", including permanently deleted. |
| 2 K and H | Resolved against the revised H: K may ship with or after H step 1 and not before. The loss is stated and accepted: a journal name that loses a rename is shown only in H's 30-day note on the resolving device and in a history row nothing displays. The numbered-journals alternative is dropped; keeping the note until cleared is rejected as unnecessary. The history-row line in K's data table is corrected. |
| 3 Post-H world | N's rows for "changes to review" are now held conflicts treated like newer-version records (update wording, no Review Changes); Restore Journal is disabled only while the library is replaced. Order stated: N ships before H step 1 only with the old wording. Key ownership named: `common.journalNeedsReview`, `messages.lifecycle.needsReview` and `common.reviewChanges` are removed by H (step 1 and 2); `messages.generic.templateNeedsReview` is removed by H step 2 (M deletes its caller); `common.defaultTemplate` and `common.blankEntry` by whichever of H step 1 and M lands first; `messages.conflict.journal.value.unavailableTemplate` by H step 1. |
| 4 Pins | Stated in the store paragraph: pins are keyed by entry id, a restored entry keeps its pin and journal order is untouched. |
| 5 Error text | New `messages.restore.destinationGone`: "The journal to restore into is no longer available. Nothing was restored." |
| 6 Test 1 | Adds the 1.0 default-template change against a 1.1 rename resolved automatically; the loss of the 1.0 choice is accepted and written under M's 1.0 devices. |
| 7 Housekeeping | Key ownership above, so the checker neither warns about a still-used key nor leaves an unused one. Also: test 3 asserts the agent copy publisher's output, and the fallback guard (entry editable, no held conflict) is stated. |
