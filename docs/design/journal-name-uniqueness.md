# Journal names stay unique

Status: **revision 2, approved with required changes by an independent design review (see Review), which this
revision applies; implemented.** It amends [join-with-local-journals.md](join-with-local-journals.md) §2.2 and §3.2 (footer),
[agent-access-simplified.md](agent-access-simplified.md) §7.1 (the bullet about joining devices) and
[move-entry.md](move-entry.md) (the same-name fallback becomes a rare case), and adds a client rule to
[protocol/journal-lifecycle.md](../../protocol/journal-lifecycle.md).

Amended 2026-10-09 by [1-1-library-simplifications.md](1-1-library-simplifications.md) (K, L): Merge Into… and journal
Version History are removed in release 1.1. Rename replaces Merge Into… as the answer for a numbered journal (§5), and
an automatically numbered journal's earlier name is no longer visible anywhere. The rule itself (§3, §4.1, §4.4 to
§4.6) is unchanged. Where the Tests, Review and Implementation sections mention Merge Into… or Version History, they
record what version 1.0 shipped.

## Owner report (2026-09-30)

"on my phone it asked me to merge journals, I said yes, but now under the 'Journals' section I have 2 journals called
'Default'. one with 3 entries, and one with 1 entry. this violates the invariant that journals names need to be
unique (at least visibly)."

## Summary

- **The invariant is new.** No code enforces unique journal names today. Seven paths make two live journals
  with the same name (§2).
- **Cause of the report, confirmed from code:** during Merge Journals, a server journal that an agent can read is
  never a combine target. When any agent has **All Journals**, *no* journal is combined. In both cases the phone's
  "Default" was added as a second "Default" (§1).
- **Fix:**
  1. Every local action checks the name: New Journal, Rename, the Settings name field and the recovery New Journal
     sheet show **Name Taken**. Restore, Keep Journal, archive import and joining add a number, such as
     "Default 2", and say so first. (Version 1.0 also refused restoring a taken name from Version History; journal
     Version History is gone in 1.1.)
  2. For Merge Journals, recommendation **(b)**: an agent-read journal is added separately as "Default 2", and
     the Merge step says so. **All Journals** agents no longer block combining, because they read the journal
     either way.
  3. Two devices that name journals the same while offline: after each sync, every journal except the oldest of
     that name gets a number. The rule is deterministic, nothing is lost, and an automatic rename never needs
     review.
  4. A numbered journal is renamed to a name of its own, or its entries are moved one at a time with Move Entry…
     (§5). (Revision 2 added a Merge Into… action here; release 1.1 removes it.)
  5. Rule B: a join tried again respects what the server deleted since the earlier attempt (§4.5).

## 1. Cause (confirmed)

- `ServerJoining.swift:332` asks `ServerClient.journalsAgentsCanRead` and passes the result to `importMerging`.
- `AgentCopyClient.swift:102–115` returns:
  - the union of the journals that Selected-Journals agents chose;
  - **nil as soon as one agent has All Journals** (line 111), or when an agent's settings can't be opened.
- `MergePlan.swift:29–31`: only server journals *not* in that set are `combinable`, and nil makes none combinable.
  `planJournals` (line 70) then gives the phone's "Default" a derived identity with its own title. The result is
  two live "Default" journals.
- **Reproduced, no owner server or device touched:**
  - `swift test --filter MergeTests/(testUnknownAgentAccessCombinesNoJournal|testMergingCombinesSameNameJournals…)`
    passes today. It asserts two "Default" journals when agent access is unknown or All Journals (nil), and two
    "Work" journals when an agent selected "Work".
  - `JournalProbe agent-connect` against a disposable loopback server built from `server/`: "PASS: a device joining
    can tell which journals agents read" (`readByAgents == [shared.id]`).
- **Which case the owner hit** can't be told without their server. Their agent row in Settings > Agent Access shows
  either "All Journals" or "Default". Both lead to the same result.
- **The All Journals case is a design flaw, not only a naming problem.** With All Journals, the phone's journal
  is shared with the agent however it's added ("Includes journals you create later"). Keeping it separate
  protected nothing and only produced a duplicate.

## 2. Every path to two visible journals with the same name, today

"Name" means the name as shown: trimmed, compared ignoring case, "Untitled Journal" for an empty title. Only journals
not in Recently Deleted count.

| # | Path | Check today | Evidence |
|---|---|---|---|
| 1 | **New Journal** (sidebar, toolbar, File menu, Settings > Journals "New Journal" section) | Only non-empty | `JournalOperations.createJournal` (JournalOperations.swift:86) saves any trimmed name. `RootView.swift:88`, `JournalSettingsView.swift:57` |
| 2 | **New Journal…** in Move Entry, Deletion Conflict and Unavailable Journals (`RecoveryJournalView`) | Only non-empty | `createRecoveryJournal` (JournalOperations.swift:98) |
| 3 | **Rename** (sidebar context menu, Journal Actions, Mac window, Settings name field) | Only non-empty | `changeJournal(_:name:)` (JournalEditing.swift:67) |
| 4 | **Restore** from Recently Deleted, restoring an entry with its journal, and **Keep Journal** in a deletion conflict | None | `Store.restoreJournal` (Store.swift:353), `restoreEntryAndJournal` (EntryRestoration.swift:58), `DeletionConflictView.swift:153` |
| 5 | **Version History**: restoring a journal's earlier settings brings back its earlier name | None | `restoreJournalSettings` (Store.swift:709) |
| 6 | **Import Archive** into an existing library ("Import as New Journals") | None: every journal is added | `importAsNewJournals` (Store.swift:794). The sheet says "Imported journals will be added as separate journals." |
| 7 | **Merge Journals** when joining a server | Combines same-name journals, **except**: agent-read targets; any All Journals agent or unreadable settings (nil); a server journal in Recently Deleted (restoring it later makes a pair); two same-name journals on this device with no server match (both added) | `MergePlan.swift:29–37, 70–81`; `testUnknownAgentAccessCombinesNoJournal` |
| 8 | **Sync**: two devices create, rename or restore to the same name before either has synced the other's change. Also a journal conflict resolved with the other device's name. | None, and it can't be checked by the server: titles are encrypted | Records carry no name constraint (`protocol/records.md`). `Store.apply` (Store.swift:524) accepts any journal. |

Already mitigated for display only:

- Move Entry disables same-name destinations ("Same name as another journal", `MoveEntryView.swift:28–45`).
- Deletion conflict destinations show the creation date (permanent-deletion.md).
- Templates are out of scope. Duplicate template names are allowed by design and shown with a short identifier
  (markdown-writing-revision.md).

## 3. The rule

**Journals not in Recently Deleted have different names.** Two names are the same when they're equal after
trimming spaces and ignoring case (`MergePlan.nameKey`, moved to one shared `JournalNames.key` in JournalCore that
Move Entry uses too). An empty title counts as "Untitled Journal".

- **The store enforces it on local writes only,** inside the write transaction, not only in the view, so two
  windows can't slip past it. A local save that keeps a journal's name, or changes only its case, is never refused,
  so journals an earlier version named alike stay editable.
- **Receiving never refuses or changes a journal because of its name.** `Store.apply` accepts every incoming journal
  as it is; only the rule in §4.6 renames afterwards.
- **Numbered names:** "‹name› 2", then 3 and so on, using the smallest number whose name is free. The number is
  always added to the whole name, so "Chapter 1" becomes "Chapter 1 2", never "Chapter 2". This is the same scheme
  as agents ("Claude Code 2").
- **Journals in Recently Deleted** may share a name with anything. Restoring one applies the rule (§4.2).

## 4. Behavior by path

### 4.1 New Journal and Rename: Name Taken

Apple Notes answers a taken folder name the same way.

- **Alert-based flows** (New Journal and Rename alerts on iPhone, iPad and Mac):
  - Create or Rename with a taken name closes the text alert and shows an alert.
    - **Title:** Name Taken
    - **Message:** A journal named “‹existing name›” already exists. Choose a different name.
    - **Button:** OK
  - OK reopens the same New Journal or Rename alert with the typed text kept, so it can be edited.
  - A pending "create an entry after the journal" (`createAfterJournal`) is kept.
- **Form-based flows:** the Settings name field, the Settings "New Journal" section and the recovery New Journal
  sheet.
  - No alert. Secondary text appears directly below the field: "A journal named “‹existing name›” already
    exists."
  - After Return, the Settings name field keeps the typed text and focus, with the message, and doesn't save.
    Leaving the field puts back the saved name and removes the message. The message also goes with the next edit.
  - VoiceOver announces the message (`JournalAccessibility.announce`).
- **Allowed:**
  - Renaming a journal to its own name in different case ("default" to "Default").
  - A name used only by a journal in Recently Deleted.
- The name check happens on commit, not while typing. Create and Rename stay enabled for any non-empty name, so
  nothing is disabled without an explanation.

### 4.2 Restore, restore with an entry, Keep Journal: numbered, said first

- If a live journal already has the name, the restored journal gets the next numbered name in the same
  transaction. It's an ordinary edit. The earlier name isn't kept anywhere the person can see (1.1).
- **Restore Journal sheet** (`JournalLifecycleView`): when the name is taken at preparation, one sentence is
  added after the restoration explanation:
  "Another journal is named “Travel”, so this one will be restored as “Travel 2”."
- **Restore Journal and Entry** confirmation: the same sentence, after "Other deleted entries will stay in Recently
  Deleted."
- **Keep Journal** (deletion conflict): the same sentence below the Keep Journal explanation.
- **If the name becomes taken between preparing and committing** (a sync arrived), the store still numbers it, and
  nothing fails. The sentence isn't shown in that rare case, because the number is visible in the sidebar.

### 4.3 Version History: restoring a taken name is refused

Removed in 1.1: a journal has no Version History, so there is no earlier name to restore. A name changed by mistake is
changed back with Rename, which refuses a taken name like any other rename (§4.1). What follows describes version 1.0.

A numbered name would defeat the purpose of restoring the name, so it isn't offered.

- The Restore action in `JournalSettingsConfirmation` is disabled, with this text in its place:
  "Another journal is named “Travel”. Rename that journal first to restore this name."
- **Default Template only:** when the version differs from the current settings only in its default template, the
  restore proceeds as today.
- **Name and template both differ:** Restore stays disabled, with the same text. There's no partial restore.
- **The name became taken after the confirmation opened:** the store refuses with the same text as an inline
  error, and nothing changes.

### 4.4 Import Archive: numbered

- Imported journals whose names are taken, by existing journals or by each other, get numbered names.
- The sheet's sentence becomes: "Your current journals will be kept. Imported journals will be added as separate
  journals. If a name is already used, a number is added, such as “Default 2”."
- The last sentence is shown only when the preview finds a name that's already used. The preview already reads the
  archive's journals.

### 4.5 Merge Journals (joining a server)

**Options for a server journal an agent can read** (the owner decided combining is the default):

| | (a) Combine after an explicit choice in Merge | (b) Add separately with a number, say so in Merge | (c) Combine silently, as for other journals |
|---|---|---|---|
| AGENTS.md "agents must not silently gain content" | Met, if the choice names the agent and journal | Met: the agent gains nothing | **Violated** |
| Feasible in the current flow | **No.** Merge Journals comes *before* Sign In or pairing (join-with-local-journals.md §2.7, "Nothing that uploads is sent before Merge"). Which journals agents read is only known after the grant, because the settings are sealed with the vault key. It would need a second consent step after downloading, plus cancel and revoke handling for a grant already issued. | Yes: decided after the grant, as today | Yes |
| Simplicity | New step, new states, new failure copy | One changed footer sentence | None |
| Visible uniqueness | Yes | Yes ("Default 2") | Yes |
| Keeping or combining later | n/a | **Rename** the numbered journal (§5); entries move one at a time with Move Entry… | n/a |

**Recommendation: (b).** It's the only option that is both feasible before consent and silent about nothing. Naming it
"Default (iPhone)" was considered. Device names are personal and long ("Alex’s iPhone 17 Pro"). They would also
differ from every other numbering path in this design, so "Default 2" is used.

**Changed rules** (join-with-local-journals.md §2.2):

- **What agents read.** `journalsAgentsCanRead` returns only the journals that **Selected Journals** agents chose.
  - An All Journals agent adds nothing to the set: it reads the journal whether it's combined or added.
  - The result is still nil when an agent's settings can't be opened. Then no journal is combined, as before.
- **No combine target.** A device journal whose name matches a live server journal it may not combine with is
  added with the next numbered name. The same applies to a later device journal with the same name as one already
  added in this merge. The number is chosen against every live server journal and every journal added so far, in
  the order (date, id).
- **Idempotence is unchanged.** Numbering is deterministic for a given server state. A record an earlier attempt
  already sent keeps its identity and is updated as an ordinary edit at revision 1.
- **Unknown agent access** (nil, an agent's settings can't be opened) combines nothing, so every device journal
  whose name matches a server journal is added with a number.
- **A server journal in Recently Deleted** still isn't a target. The device journal is added under its own name,
  which is free among live journals. Restoring the server one later follows §4.2.
- **Rule B: a repeated join respects deletions.** When something an earlier attempt sent (it has the derived
  identity) was deleted on the server since, joining again keeps the deletion instead of turning this device's
  version into a change to review:
  - moved to Recently Deleted on the server: it stays there; if this device's content differs, it's saved as an
    ordinary change that stays in Recently Deleted, when the server's content apart from the deletion is what this
    library sent; otherwise, such as when another device changed it or sent it from a copy of this library, both
    versions are kept for review (join-with-local-journals.md, red-team finding);
  - deleted permanently: it isn't imported, and neither are its earlier versions. An entry or template changed on
    this device after the deletion is kept as a copy with a new identity, as Keep Entry as Copy would;
  - what this device wrote since into such a journal arrives as any entry written offline into it would: in Recently
    Deleted with it, or under Unavailable Journals when it was deleted permanently (protocol/permanent-deletion.md).
    Nothing is lost.

**Merge step footer**, first sentence (MergeJournalsView.swift:41), before and after:

- Before: "Journals already on the server are kept. A journal with the same name as one there is combined with it."
- After: "Journals already on the server are kept. A journal with the same name as one there is combined with it,
  unless you chose that journal for an agent. Then yours is added with a number, such as “Default 2”."

"Chose that journal for an agent" names the Selected Journals case, the only one where combining would let an agent
read more. No other copy changes: the step can't know the specifics before the grant, and after joining, the
numbered journal in the sidebar is the result. The person renames it ("Default 2" to a name of their own) or moves its
entries with Move Entry…; the footer mentions neither, and the earlier name is not kept anywhere (1.1).

### 4.6 Sync: two devices, same name, offline

**What the person sees:** nothing unusual. After the sync that brings the second journal, one of them is named
"Travel 2", with all of its entries. There's no alert, because syncing stays quiet. The earlier name is not shown
anywhere. The person renames the numbered journal to something meaningful ("Travel 2" to "Travel, laptop"), or moves
its entries with Move Entry… and deletes the empty journal.

**Rule (client-side; documented in protocol/journal-lifecycle.md so other clients can follow it):**

1. After a synchronization has read every page of changes, and before the app refreshes, the device groups live
   journals by name.
2. In each group of two or more, the oldest by (`date`, then `id`) keeps its name. Every other journal, in (`date`,
   `id`) order, gets the next free numbered name. The numbers don't depend on which journals can be renamed.
3. **Only journals with no pending local change** are renamed: none with a change waiting to be sent, a change to
   review, or content saved by a newer version. They're skipped without blocking the others; their duplicate stays
   until that change is sent or reviewed, and the next sync applies the rule again. Move Entry's "Same name as
   another journal" fallback still covers that rare state.
4. **A rename is sent directly and stored only once the server accepts it,** on the revision it was based on. When
   the server refuses it as stale, because another device renamed or changed that journal first, nothing was stored:
   the device reads the new changes and applies the rule again, in the same synchronization (at most three rounds).
   A rename that can't be sent now is worked out again at the next synchronization. **An automatic rename never
   creates a change to review,** and no state is stored for it.
5. The renames go out in the same synchronization, before the app refreshes, so the duplicate isn't shown.
6. **Libraries without a server** apply the rule every time they open, with no stored flag, as ordinary edits. That
   covers duplicates made by earlier versions.

**Why every device can apply it without dueling:**

- Every device computes the same result from the same data.
- A device renames only after reading the whole log, so a device that syncs later sees the earlier rename and has
  nothing left to do.
- Two devices finishing a sync at the same moment can both send the same rename. The second one is refused as stale,
  stores nothing, reads the first one's rename and finds nothing left to do.

**Rejected alternatives:**

- **Combining same-name journals automatically:** it moves entries without consent, and it can let a
  Selected-Journals agent read another device's entries.
- **Showing a display-only suffix** while the stored name stays the same: Rename, agents and exports would all show a
  different name than the sidebar.
- **Letting only the "later" device rename,** by comparing log cursors: it needs new stored state per journal to be
  robust. The deterministic rule plus renames stored only on acceptance gives the same result with no state.
- **Dropping identical edits in the store** (revision 1's rule): too broad a change to conflict handling for this.

**Agents:** a rename changes only the name the agent sees. What it can read doesn't change.

## 5. Combining duplicates: Rename (amended 2026-10-09)

Revision 2 designed a Merge Into… journal action here, and version 1.0 shipped it. Release 1.1 removes it
([1-1-library-simplifications.md](1-1-library-simplifications.md), L), together with journal Version History (K). The
numbered names of §4.2 and §4.4 to §4.6 stay.

- **Two journals with similar content are two real journals.** Two devices that each created "Travel" offline, or a
  join that met a taken name, leave "Travel" and "Travel 2". Keeping both is harmless and nothing is lost.
- **Rename gives the numbered journal a name of its own.** Choose Rename… in the journal's actions and type a name
  that is free ("Travel 2" to "Travel, laptop"). A taken name is refused (§4.1). Rename is also the only way to change
  a name that was changed by mistake: the earlier name is not offered back, and an automatically numbered journal's
  earlier name isn't visible anywhere.
- **To end up with one journal,** open each entry's actions, choose Move Entry… and pick the other journal, then
  choose Delete Journal… for the empty one. This is one entry at a time: lists have no multiple selection (owner
  decision, 2026-10-09), so a bulk move isn't planned.
- **Agents.** A rename changes only the name an agent sees. Move Entry… changes what an agent can read as described in
  [move-entry.md](move-entry.md).
- **A journal merged by 1.0** is an ordinary deleted journal with no entries. It is in Recently Deleted and can be
  restored (numbered if its name is taken) or deleted permanently.

## 6. The owner's library now

The owner's server (read-only, metadata only) has exactly two journal records, both never changed: the Mac's
"Default" from setup, and the iPhone's merged "Default" with a derived identity, pushed when the iPhone joined with
its recovery key. The only agent grant is Claude Code, most likely with All Journals. So the duplicate is the original
merge rule (§1), not a deletion that came back; see Review.

**After this change:**

- The next sync of an updated device renames the newer "Default" (by creation date) to "Default 2" (§4.6).
- In 1.0, Journal Actions > **Merge Into…** combined them. In 1.1, rename "Default 2", or move its entry with
  Move Entry… and delete the empty journal (§5).

**With an earlier build:** rename one "Default", move its entry with Move Entry (which doesn't offer same-name
journals), then delete the empty journal.

## 7. Accessibility

- **Name Taken:** a system alert: the title is read first, then the message, and OK is the default button.
  Reopening the text alert returns focus to its field.
- **Inline name messages:** plain secondary text below the field, announced when they appear. They're never shown
  by color alone.
- **Restore sentences:** part of the existing explanation text, read in order and wrapping at every Dynamic Type
  size.
- **Merge sheet:**
  - Rows are buttons with the `.isSelected` trait on the chosen row, and the checkmark is hidden from VoiceOver.
  - A same-name row reads "‹name›, Created ‹date›".
  - The footer and agent sentence come after the list and are read in order, with
    `fixedSize(horizontal: false, vertical: true)`.
  - Merge's hint on the Mac: "Moves every entry, then moves this journal to Recently Deleted." Full keyboard
    navigation: arrow keys in the list, Return for Merge, Escape to cancel.
  - Reduced motion: no custom animation.
- **Merge Journals footer:** it's one more sentence in an existing footer, so nothing changes.

## 8. Tests (useful tests only)

Core tests use real isolated stores and the in-memory `MergeServer`. Probes run against a disposable real server
(`scripts/test-sync.sh`). Rows about Merge Into… or restoring a name from Version History describe version 1.0; the
tests of those features go with them in 1.1.

| Protects | Test |
|---|---|
| A taken name, in other case or with spaces, is refused by the store for create and rename. Your own name in other case, and a name held only in Recently Deleted, are allowed. | `JournalNameTests.testNamesTakenByLiveJournalsAreRefused` |
| Restore and restore with an entry number a taken name in the same transaction, even when the name was taken after preparing; nothing else changes. | `JournalNameTests.testRestoringIntoATakenNameAddsANumber` |
| Restoring settings with a taken name is refused unchanged; template-only restores still work. | `JournalNameTests.testVersionHistoryDoesntRestoreATakenName` |
| Archive import numbers names taken by existing journals and by each other, and entries arrive. | `JournalNameTests.testImportedJournalsWithTakenNamesAreNumbered` |
| A library without a server that has duplicates is numbered when opened, and again finds nothing to do. | `JournalNameTests.testExistingDuplicatesAreNumberedWhenOpened` |
| Two devices name journals alike offline and sync in either order: both end with the older name and "‹name› 2", entries intact, nothing to review or unsent; a third offline device's "Travel 2" becomes "Travel 2 2". | `JournalNameSyncTests.testSameNameJournalsFromTwoDevicesAreNumberedOnce`; `MergeProbe` on a real server |
| Receiving accepts a journal as it is, whatever its name. | `JournalNameSyncTests.testIncomingJournalsAreAcceptedAsTheyAre` |
| A rename refused as stale stores nothing; the sync reads again and renames once; one refused because another device renamed first leaves nothing to send or review. | `JournalNameSyncTests.testARefusedRenameLeavesNothingToReview` |
| A journal with a change to review or an unsent change isn't renamed, and the others' numbers don't change. | `JournalNameSyncTests.testAJournalWithAReviewOrAnUnsentChangeIsNotRenamed` |
| Merge: a journal a Selected agent reads isn't combined, and this device's is "Work 2"; unknown agent access numbers every match; device journals named alike with no match are numbered the same on every attempt. | `MergeTests.testMergingCombinesSameNameJournalsAndReviewsOnlyDifferentTemplates`, `testUnknownAgentAccessNumbersEveryMatch`, `testUnmatchedSameNameJournalsAreNumberedTheSameOnEveryAttempt` |
| An All Journals agent doesn't keep a joining device from combining. | `AgentJournalsProbe` on a real server |
| Rule B: a join tried again after the server moved a journal to Recently Deleted or deleted it permanently keeps the deletion, creates no review, and keeps what was written since. | `MergeTests.testARetriedJoinDoesNotReviveAJournalDeletedMeanwhile`; `MergeProbe` (joining again with a recovery code, as the owner's iPhone did) |
| A journal deleted permanently on one device is gone on the other, and stays deleted after the server is restored from a backup taken before the deletion. | `MergeProbe`, `RestoreProbe` on a real server |
| Merge Into moves every entry (live, archived, Recently Deleted, deleted with its journal) keeping their state, and moves the source to Recently Deleted; a change to review, a journal in Recently Deleted or an entry saved by a newer version refuses with nothing changed. | `MergeIntoTests.testMergingAJournalMovesEveryEntryOrNothing`, `testAnEntrySavedByANewerVersionStopsTheMerge` |
| After Merge Into, another device's offline edit becomes a review, and its offline new entry arrives in Recently Deleted. | `MergeIntoTests.testOfflineChangesToAMergedJournalAreKept` |
| Merged entries enter the copy of a Selected agent reading the destination, leave the copy of one reading only the source, and stay for an All Journals agent. | `AgentJournalsProbe` on a real server |
| Name Taken from New Journal and Rename returns to the alert with the name kept; the restore sentence; Merge Into from the Journals list. | `JournalNamesUITests` (iOS) |

**Not tested:** copy, plural wording, and view composition beyond the one UI test.

## 9. Out of scope

- **Template names.** Duplicates are allowed by design.
- **Names in Recently Deleted.** Two deleted journals may share a name. Restoring applies the rule.
- **Whether the Merge step should mention All Journals agents.** They'll read the merged journals ("Includes
  journals you create later"). That's the owner's earlier decision, and the step can't know about agents before the
  grant.

## Review

**Independent design review (revision 1): approved with required changes,** all applied in revision 2:

1. The rule is enforced only on local writes; `Store.apply` accepts any incoming journal and the rule in §4.6
   renames afterwards (§3; `testIncomingJournalsAreAcceptedAsTheyAre`).
2. The general identical-edit store rule was dropped. Automatic renames touch only journals with no pending local
   change, are stored only once accepted, and a stale refusal reads again and reruns the rule in the same sync,
   never creating a review, with no new stored state (§4.6; `testARefusedRenameLeavesNothingToReview`).
3. Libraries without a server apply the rule on every open, without a flag.
4. Merge Into's data claims match the store: its own transaction; Recently Deleted entries keep `deletedAt`;
   `deletedWithJournal` is defined; an entry saved by a newer version refuses the whole merge (§5.3).
5. Merge Into is tested at the agent boundary in `AgentJournalsProbe`, including All Journals.
6. The Merge Into footer includes the count.
7. The Merge Journals footer reads "…unless you chose that journal for an agent. Then yours is added with a number,
   such as “Default 2”."
8. Leaving the Settings name field restores the saved name and removes the message.

Optional suggestions adopted: the "will no longer be able to read" sentence, the note that nil agent access numbers
every match (§4.5), older app versions in protocol/journal-lifecycle.md, and the title “Merge “Default 2””.

**"The deleted duplicate came back" (owner, 2026-09-30).** Deletion, permanent deletion, both devices deleting,
and restoring the server from a backup made before the deletion or before the merge all kept the journal deleted,
on the in-memory server and on a real disposable server. Two mechanisms can show a "Default" again: another join
adding a new one under an All Journals agent (the original rule, fixed in §4.5), and a join tried again after its
journal was deleted, which showed the deleted journal with a change to review on that device (rule B, added to §4.5
without another review round at the coordinator's decision). The owner's server shows only the first: two journal
records, never deleted. The disappearing and reappearing on the iPhone is being investigated separately as a
display problem.

## Implementation (2026-09-30)

- JournalCore: `JournalNames.swift` (the rule, local-write check, numbering, automatic renames),
  `JournalMerging.swift` (Merge Into), `MergePlan`/`StoreMerge` (numbering, agent rule, rule B), `SyncEngine`
  (renames after reading), `AgentCopyClient.journalsAgentsCanRead` (All Journals adds nothing).
- App: Name Taken (`JournalNameTakenAlert`), inline messages in Settings > Journals, restore and Keep Journal
  sentences, Version History refusal, archive import and Merge Journals copy, `MergeJournalView` from Journal
  Actions, and numbering when a library without a server opens.
- Checked: JournalCore tests with strict concurrency, Mac unit tests (team-signed), `JournalNamesUITests` on an
  iPhone 17 simulator with screenshots of Name Taken, the Merge sheet and the restore sentence, and
  `scripts/test-sync.sh`.
- Not checked in the running app: the Mac sheet and alerts, the Settings name field message, the agent sentences
  with real agents (covered by `AgentJournalsProbe` for the data, not the copy), dark mode, the largest text sizes
  and VoiceOver.
