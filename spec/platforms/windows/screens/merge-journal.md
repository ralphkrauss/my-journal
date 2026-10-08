---
id: merge-journal
title: Merge into (Windows)
spec: screens/merge-journal.md
features: [merge-journal, unique-journal-names]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
---

# Merge into (Windows)

Moves every entry of one journal into another, then moves the emptied journal to Recently deleted. Behaviour, rules and copy keys are the spec's [merge-journal](../../../screens/merge-journal.md).

## Controls

A `ContentDialog`, 400 epx wide, opened from Merge into… in the journal's context menu or Journal actions ([journals](journals.md)). Merge is the `DefaultButton`, as Return is on the Mac: Enter chooses it once a journal is chosen, and Esc cancels ([8.1](../platform.md#81-rules), rule 3). It is not a confirmation of a loss: the entries move and the journal goes to Recently deleted, from where it can be restored.

| Spec element | Control | Notes |
| --- | --- | --- |
| Title | `library.merge.title` (the journal being merged) | |
| Header | `TextBlock` `library.merge.header` | |
| The other journals in use | `ListView`, `SelectionMode` Single, in the pane's order; a journal whose name another destination shares shows `library.merge.created` under its name | The standard selection visual marks the chosen one |
| Footer | `TextBlock`, `Caption`, secondary: `library.merge.footer.none`, `library.merge.footer.one` or `library.merge.footer.other`, with {target} replaced by `library.merge.footer.target` once a journal is chosen, else `library.merge.footer.targetNone` | |
| Agent changes | A second `TextBlock`, only when the library syncs with a server that has agent access and the journal has entries: `library.merge.agents.unknown` when it could not be checked, else `library.merge.agents.gainingOne` or `library.merge.agents.gainingMany` and `library.merge.agents.losingOne` or `library.merge.agents.losingMany` | Agents with All Journals are never mentioned |
| Error | `InfoBar`, Severity Error, not closable | `messages.lifecycle.needsReview` (with a `Button` `common.reviewChanges`), `messages.merge.newerVersion`, `messages.save.before.mergeJournal`, `library.merge.displayFailed` (then only Done); announced |
| Progress | An indeterminate `ProgressBar` with `common.merging` | |
| Merge | `PrimaryButton` `common.merge`, `AutomationProperties.HelpText` `library.merge.hint`, `DefaultButton` | Enabled once a journal is chosen; hidden once the journal is gone |
| Cancel or Done | `CloseButton` `common.cancel`; `common.done` once the journal is gone; Esc | |

**Merge:** in one step every entry of the journal (including entries in Recently deleted, which keep their deletion) moves to the chosen journal, and the journal moves to Recently deleted. The dialog closes, Narrator is told `library.merge.merged` (notification event, `ImportantMostRecent`), and the chosen journal is shown. If the open entry was in the merged journal it closes. Nothing changes if any entry or either journal has changes to review or was saved by a newer version. Merging renames nothing; the merged journal can be restored but its entries stay where they were merged.

**States:** busy: controls disabled, not dismissable, and the app does not lock for inactivity meanwhile. The merged journal disappeared: `messages.generic.journalNamedUnavailable`, only Done remains. The chosen journal disappeared: the choice clears and `common.journalGone` (before merging) or `library.merge.destinationGone` (while merging) shows. Locked: the dialog closes. Review changes closes the dialog and opens the review page.

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium | 400 epx dialog, list at most 200 epx tall and scrolling | Mac sheet |
| Small | Fills the window width | iPhone sheet |
| 200% text size or more | Names wrap; the dialog scrolls; the footer grows | |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `merge-journal` | Journal context menu; Journal actions; the dialog's Merge button | Enter inside the dialog (the default button) | The journal has no changes to review and another journal is in use; in the dialog, once a journal is chosen and nothing is running |
| `review-changes` | A button in the dialog after a conflict | none | A conflict blocked the merge |

Up and Down move the choice; Esc cancels; focus starts on the list.

## Copy differences

Sentence case: "Merge {name}" and "Merge into…" ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)). `library.merge.header` and `library.merge.destinationGone` use "Choose", which the select-for-choose proposal would turn into "Select" (B26). `library.merge.hint` is an accessibility hint and stays.

## Accessibility

- The chosen row is selected; the result and errors are announced; Merge reads its hint.
- Focus goes to the list on open and back to the journal's row (or the list, when the row is gone) on close.
- Merge is the default button, so Enter chooses it as soon as it is enabled; before a journal is chosen Enter does nothing.

## Different by design

- **Review changes opens a page** instead of a nested sheet.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): B26 (select and choose).
