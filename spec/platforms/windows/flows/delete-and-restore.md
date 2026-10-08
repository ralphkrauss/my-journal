---
id: delete-and-restore
title: Delete, restore and delete permanently (Windows)
spec: flows/delete-and-restore.md
features: [delete-entry, undo-delete, delete-journal, restore-entry, restore-and-move, restore-journal, delete-permanently, delete-all-deleted, recently-deleted]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/swipe
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/listview-and-gridview
---

# Delete, restore and delete permanently (Windows)

One path for everything removed: entries, templates and journals go to Recently deleted, can be restored from there, and leave only when deleted permanently. There is no Archive. The steps and rules are the spec's [delete-and-restore](../../../flows/delete-and-restore.md); each surface has its own mapping: [entry-list](../screens/entry-list.md), [journals](../screens/journals.md), [recently-deleted](../screens/recently-deleted.md), [restore-journal](../screens/restore-journal.md), [move-entry](../screens/move-entry.md). This file follows one person through the whole path on Windows.

## Controls

### Delete an entry or template

| Spec step | Windows |
| --- | --- |
| 1. Delete entry / Delete template | The row's context menu and the Entry actions menu (`library.entryActions.deleteEntry`, `library.entryActions.deleteTemplate`, last, icon Delete), the trailing swipe (touch and pen only, `common.delete`), and the Delete key while the list has focus. Shift+Delete is not bound here (in Windows it means permanent deletion, which this flow has only in Recently deleted) |
| 2. No confirmation; the row leaves at once | A `ListView` item removal with its normal transition; none when animation effects are off (`UISettings.AnimationsEnabled`). The item moves to Recently deleted; lists and counts are read again after the transition |
| 3. If the item was open | Large and medium layouts: the next entry below opens (above at the end of the list). Small layout: the page goes back to the list, as on iPhone. Focus goes to the entry that opened, or to the list when none did |
| 4. Undo | Edit ▸ Undo Delete entry or Undo Delete template (Ctrl+Z, scoped to the list so the editor's text undo is not hit) restores it; Edit ▸ Redo (Ctrl+Y) deletes it again. The step does nothing if the item has moved meanwhile |
| 5. Storing fails | The row returns and the alert dialog shows the error |

No toast, no "Undo" bar and no message: deleting is quiet, and the Undo is in the Edit menu, as in the spec.

### Delete a journal

`delete-journal` from the journal's context menu or Journal actions (no ellipsis, no Delete key). The deletion is checked first; then a `ContentDialog` titled `library.deleteJournal.title` with `library.deleteJournal.message` (or `library.deleteJournal.noEntries`), Primary `common.delete`, Close `common.cancel`, no default button ([journals](../screens/journals.md)). On Delete the row leaves at once, the journal and its entries (marked as deleted with it) move to Recently deleted, entries from other devices join them when they sync, and another journal is shown. There is no Undo.

### Restore

| What | Windows |
| --- | --- |
| Entry whose journal is in use | `restore`: row context menu, Entry actions, the recovery notice's button, the leading swipe. Restores at once with no confirmation. It returns to its journal, which is shown with the entry open; pins come back |
| Template | `restore`; returns to Templates, which is shown with the template open |
| Entry whose journal is also deleted | The notice's `library.recoveryNotice.restoreWithJournal` opens the Restore entry dialog ([restore-journal](../screens/restore-journal.md)), which restores the journal too |
| Entry into another journal | `library.recoveryNotice.restoreAndMove` opens [move-entry](../screens/move-entry.md) in its restoring form; only that entry moves |
| Journal | `restore-journal` on a deleted journal's page opens the Restore journal dialog. Entries deleted with it return, including those that sync later; entries deleted separately stay; a taken name returns with a number (`common.restoredAsRenamed`); it returns to its place in the order or the end |

### Delete permanently

One item: `delete-permanently` from the row's context menu, Entry actions, the Delete or Shift+Delete key in Recently deleted, or a deleted journal's page, then the checked `ContentDialog` of [recently-deleted](../screens/recently-deleted.md) (Primary `common.delete`, no default button). A journal takes its entries with it. Everything: `delete-all-recently-deleted`, the dialog described there. The deletion syncs to other devices; copies may remain in archives, backups and the server's history, which the dialog says in `library.deletePermanently.retention`.

### States

| State | Windows |
| --- | --- |
| Locked | The lock page replaces the window and every dialog hides. Nothing is deleted after locking unless it was already confirmed and stored. No row is ever pending removal, because a Windows swipe asks before the row leaves in Recently deleted, and entry deletion needs no question |
| Changes to review, newer versions | Permanent deletion and journal deletion refuse with the messages in [messages](../messages.md) (`messages.generic.*`), shown in the alert dialog; nothing changes |
| Removed by a sync while open | The open item closes unless it has unsaved writing; the editor column shows `library.window.selectEntry` |

Rules of the spec kept: deleting never asks for entries and templates, always asks for journals and for permanent deletion; only Recently deleted's own actions delete permanently; nothing is ever deleted automatically.

## Layout at each window width

As the screens it uses: the list header and its Delete all button ([recently-deleted](../screens/recently-deleted.md)), the pane and its menu ([journals](../screens/journals.md)). At small width an open item that is deleted sends the person back to the list page, and Restore from the recovery notice shows the journal's list with the entry open on its page.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `delete-entry` | Row context menu; Entry actions; trailing swipe | Delete | Focus is in the list, never while typing in the editor |
| `undo`, `redo` | Edit menu | Ctrl+Z, Ctrl+Y | The last list action was a delete |
| `delete-journal` | Journal context menu; Journal actions | none | Always |
| `restore` | Row context menu; Entry actions; notice; leading swipe | none | In Recently deleted, journal in use (entries) |
| `restore-with-journal`, `restore-and-move`, `restore-journal` | The notice; a deleted journal's page | none | As [recently-deleted](../screens/recently-deleted.md) |
| `delete-permanently` | Row context menu; Entry actions; a deleted journal's page | Delete, Shift+Delete in Recently deleted | Focus in the list with an item selected |
| `delete-all-recently-deleted` | File menu; the list header button | Ctrl+Shift+Delete | Recently deleted has rows and no search |

## Copy differences

Sentence case and the ellipsis rule ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)): "Delete entry", "Delete template", "Delete journal", "Delete permanently", "Delete all", "Restore", "Restore and move…", "Version history…". Dialog titles that are questions read as sentences ("Delete “{name}” permanently?"). The proposed variants are in [journals](../screens/journals.md) and [recently-deleted](../screens/recently-deleted.md); nothing new here.

## Accessibility

- Destructive dialogs name the action in words and have no default button; Cancel returns focus to the control that opened them (the row stays).
- After Delete focus goes to the next entry or the list; Narrator reads the new item, which is the only feedback, as in the spec. After Undo focus goes to the restored row. After Restore focus goes to the restored entry.
- Swipe actions are also the row's custom actions for Narrator and the context menu is reachable with Shift+F10 or the Menu key ([6](../platform.md#6-touch-and-swipe-actions)).
- Four contrast themes and 225% text size follow the standard dialog and list behaviour.

## Different by design

- **A destructive swipe asks before the row leaves** in Recently deleted, so no row has to come back ([recently-deleted](../screens/recently-deleted.md)).
- **Shift+Delete means permanent deletion only in Recently deleted**; elsewhere it is not bound.
- **No Edit mode and no confirm-by-position**; the Delete key and menus do the job.
- **Back to the list at small width** where a deleted open entry is replaced on iPad and Mac.

## Open questions

None. Restore returns an item to its place and opens it, as the spec says.
