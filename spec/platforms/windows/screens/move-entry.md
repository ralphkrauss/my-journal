---
id: move-entry
title: Move entry (Windows)
spec: screens/move-entry.md
features: [move-entry, restore-and-move]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/listview-and-gridview
---

# Move entry (Windows)

Moves one entry to another journal, or restores an entry from Recently deleted into a chosen journal. Behaviour, rules and copy keys are the spec's [move-entry](../../../screens/move-entry.md).

## Controls

One `ContentDialog`, default width (320 to 420 epx), content scrolling. Its title is `library.moveEntry.title`, or `library.moveEntry.restoreTitle` when restoring. It has two steps: the list (below) and New journal ([destination-journal](destination-journal.md)), which replaces the content without opening a second dialog ([8.1](../platform.md#81-rules)).

| Spec element | Control | Notes |
| --- | --- | --- |
| Action button | `PrimaryButton` `library.moveEntry.move`, or `common.restore` when restoring; `DefaultButton` Primary | Disabled until a choosable journal is selected, and while moving |
| Cancel | `CloseButton` `common.cancel`; Esc | Not while moving |
| No other journals | A centred `StackPanel`: `library.moveEntry.noOtherJournals` (`BodyStrong`), `library.moveEntry.noOtherJournals.message` (secondary), a `Button` `common.newJournalEllipsis` | |
| List of journals | `ListView`, `SelectionMode` Single, the journals in use except the entry's current one, in the pane's order; each row the name | The selected row uses the standard selection visual; no extra checkmark. A row whose name is the same as another listed journal's (ignoring case) is disabled (`IsEnabled` false, dimmed), cannot be chosen and shows `library.moveEntry.sameName` below its name |
| Same-name explanation | `TextBlock`, `Caption`, secondary, under the list, `library.moveEntry.renameExplanation` | Windows wording: the pane, see Copy differences |
| New journal | A `HyperlinkButton` `common.newJournalEllipsis` below the list (when there are journals) | Switches the dialog to the New journal step |
| Restoring note | `TextBlock`, secondary: `library.moveEntry.onlyThisEntry` when restoring or when the entry is in Recently deleted | |
| Error | `InfoBar`, Severity Error, not closable, content the message; then a `Button` `common.reviewChanges` when a conflict blocks the move | Announced when it opens. Review changes closes the dialog and opens the review page (journal or entry); if already resolved, `messages.conflict.resolved` |
| Moving | The list and buttons disabled, a `ProgressRing` beside `library.moveEntry.moving`; the dialog cannot be dismissed | |

### Action and states

- **Move or Restore** saves the open entry first, then moves it (restoring it from Recently deleted when restoring). The dialog closes; the entry stays open, now shown in the destination journal's list. The entry keeps its date, text and images, and nothing else in either journal changes. Edit ▸ Undo does not undo a move.
- **Selected journal disappears or becomes ambiguous:** the selection clears and `common.journalGone` shows. **Conflict on the entry or a journal:** `messages.lifecycle.needsReview` with Review changes. **Open entry could not be saved:** `common.saveBeforeMoveEntry`. **Moved but not shown:** the dialog closes and the general error dialog says `common.entryMovedNotDisplayed`. Other errors show the error's own text. Errors are announced.
- **Locked, or another entry opened:** the dialog closes and the move is cancelled if not committed. A lock after the commit cannot save the old journal membership back.

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium | Dialog 320 to 420 epx wide, list at most 240 epx tall, scrolling | Mac sheet 320–420 × 280–360 pt |
| Small | Fills the window width | iPhone sheet |
| 200% text size or more | Names wrap; the list scrolls; the dialog scrolls; no fixed height | |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `move-entry` | Entry row context menu; Entry actions | none | The entry is editable in a journal in use |
| `restore-and-move` | The recovery notice's action ([recently-deleted](recently-deleted.md)) | none | The notice's rules; opens the dialog in its restoring form |
| `new-journal` | The link under the list; the No other journals button | as in commands.md | Not while moving |

- Up and Down move the selection in the list, Enter chooses Move or Restore when a choosable journal is selected, Esc cancels. Focus starts on the list (or on the New journal button when there are no other journals).

## Copy differences

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `library.moveEntry.renameExplanation` | Default: … rename it in the Journals list first. Mac: … in the sidebar first. | … rename it in the navigation pane first. (and, at small width, "in the Journals list") | vocabulary; see B28 |
| `library.moveEntry.noOtherJournals.message`, `library.moveEntry.onlyThisEntry` | unchanged | unchanged | none |

Sentence case: "Move entry", "Restore and move", "No other journals". `library.moveEntry.renameExplanation` also says "can't be chosen", which the select-for-choose proposal (B26) would change to "can't be selected".

## Accessibility

- The list is named by the dialog title; the selected row is read as selected; disabled rows read as dimmed with their `library.moveEntry.sameName` line; the explanation is read after the list.
- Errors are announced when their `InfoBar` opens; focus does not move to them.
- Closing returns focus to the control that opened the dialog, or to the entry list when that row is gone.

## Different by design

- **New journal is a step of the dialog**, not a second sheet over the first ([8.1](../platform.md#81-rules)).
- **Review changes closes the dialog and opens a page**, because conflict review is a page on Windows ([9](../platform.md#9-sheets-popovers-and-notices)), where Apple nests a sheet.
- **No separate checkmark** on the selected row: the selection visual says it.
- **The explanation names the navigation pane**, not the sidebar.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): B26 (select and choose), B28 (Apple names in sentences).
