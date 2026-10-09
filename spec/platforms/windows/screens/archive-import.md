---
id: archive-import
title: Import archive, task page (Windows)
spec: screens/archive-import.md
features: [import-archive]
status: draft
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/password-box
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/progress-controls
---

# Import archive, task page (Windows)

Opens a My Journal archive, shows what it holds, and either restores it (on a PC without journals) or adds its journals as new journals (on a PC with journals). Content, states, rules and copy keys are the spec's [archive-import](../../../screens/archive-import.md); getting to it (picker, drag and drop, opening from Explorer, locked, library being replaced) is [import-archive](../flows/import-archive.md).

## Controls

One task page, the multi-step pattern of [9](../platform.md#9-sheets-popovers-and-notices) (a flow with a password step, a preview, progress and a result is a page's job, not a dialog's): the heading and content follow the step (password, preview, done), the buttons are the step's in a footer row, and the navigation pane and menu commands are disabled while it runs. The content is a column at most 640 epx wide and scrolls; there is no fixed height. While opening, Cancel stops the opening and returns; while importing it is disabled and a lock request waits for the work to stop (the spec: Cancel is disabled only while importing). Closing the window follows the one rule of [platform.md, 3](../platform.md#3-windows-and-instances): it waits for the current atomic step (the commit is one step), discards the opened copy and closes. Esc is not Back and is not bound; Back (the back button, Alt+Left) is the same as Cancel while nothing is importing.

| Spec element | Windows control | Notes |
| --- | --- | --- |
| Title | The page heading (level 1): `settings.archiveImport.title`; after importing `settings.archiveImport.imported` or `settings.archiveImport.restored` | The heading changes with the step and Narrator is notified |
| Locked | Not shown | The page closes when the library locks, and an archive opened while locked waits until unlocked ([import-archive](../flows/import-archive.md)), so `settings.archiveImport.locked` is never displayed on Windows |
| Password step | A `PasswordBox` with the reveal button, `Header` `common.passwordOrRecoveryKey`, `InputScope` Password, focused when the step appears, and under it a `TextBlock` `Caption` secondary with `settings.archiveImport.fieldHint` (also the box's `AutomationProperties.HelpText`) | Shown only when the archive is protected. Windows has no password autofill for app fields ([25](../platform.md#25-text-input-and-spelling)). Enter chooses Continue. The text is cleared once the archive opens |
| Preview | A `StackPanel` in the content, in the spec's order: for each journal its name as a heading (`BodyStrong`, `common.untitledJournal` when blank) and `settings.archiveImport.entries` under it; `settings.archiveImport.recentlyDeleted` in secondary text; when any, `settings.archiveImport.unavailable` and `settings.archiveImport.unavailableNote` in secondary text; when this PC already has journals, `settings.archiveImport.kept` or `settings.archiveImport.keptNumbered`; and when connected `settings.archiveImport.willSync` | Each journal's name and counts read as one group |
| Error | An Error `InfoBar` in the content, selectable text, brought into view when it opens | Opening errors: `settings.archiveImport.error.wrongPassword` (the password box keeps focus), `settings.archiveImport.error.newerVersion` (with a "Get updates" link, D51), `settings.archiveImport.error.damaged`, `settings.archiveImport.error.couldntOpen`. Import errors: the error's own message, for example `messages.save.before.goBack`, `messages.import.archiveNeedsUpdate`, `messages.error.locked`. Imported but not shown: `messages.refresh.imported` in this bar (the import stands, and importing is not offered again) |
| Progress | An indeterminate `ProgressBar` at the top of the content with `settings.archiveImport.opening` or `settings.archiveImport.importing` | Text, not only the bar. The buttons and the field are disabled meanwhile |
| Primary button | The footer row's accent `Button`: `common.continue` (password step), `settings.archiveImport.restore` (no journals on this PC) or `settings.archiveImport.importAsNew` (journals on this PC) | Enabled when not busy and (the archive is opened, or needs no password, or a password is typed). On the password step it is the default button; on the preview step there is **no default button** (accent style, but Enter does not choose), so the person has read the preview before the library changes |
| Cancel button | `Button` `common.cancel`, after the primary | Stops opening, discards the opened copy and returns to where the import started; disabled while importing |
| Done | Content `settings.archiveImport.setUpSync` after a restore; the one button reads `common.done` and is the default | There is no other button |

Rules the spec states and Windows keeps: the opened copy lives apart from the journals until imported, and cancelling, closing or locking discards it; importing adds separate journals and never replaces or merges; restoring makes the archive's library this PC's library with the archive's password. While opening or importing, App Lock's inactivity timer does not fire ([13](../platform.md#13-device-authentication-and-app-lock)); a lock the person asks for (Ctrl+L, Win+L, sleep) cancels the work and discards the copy as the spec says.

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium | A column up to 640 epx on the content layer, content scrolling | Mac sheet about 480 × 420 pt |
| Small | Fills the window width with 12 epx margins; the buttons stay at the foot of the page | iPhone sheet |
| 200% text size or more | Text and names wrap; the page scrolls; the buttons stay reachable at the foot | Buttons stacked with the primary full width |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `archive-open` | Primary button on the password step | Enter in the password box | A password is typed (or none needed), not busy |
| `archive-import` | Primary button on the preview step | none | Previewed, not busy |
| `archive-import-cancel` | Cancel button | — | Not importing; Esc is not bound |
| `archive-import-done` | Done button on the done step, default | `Enter` | Imported |

## Copy differences

Sentence case ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)):

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `settings.archiveImport.title` | Import Archive | Import archive | casing |
| `settings.archiveImport.restore`, `settings.archiveImport.importAsNew` | Restore Journals, Import as New Journals | Restore journals, Import as new journals | casing |
| `settings.archiveImport.imported`, `settings.archiveImport.restored` | Journals Imported, Journals Restored | Journals imported, Journals restored | casing |
| `settings.archiveImport.opening`, `settings.archiveImport.importing` | Opening Archive…, Importing Journals… | Opening archive…, Importing journals… | casing |
| `common.passwordOrRecoveryKey` | Password or Recovery Key | Password or recovery key | casing |

## Accessibility

- Narrator reads the heading and the step's content when the page opens and again, by a notification, when the step changes. The password box has its name, the hint as help text, and the reveal button, which Alt+F8 also operates, is reachable by keyboard.
- Errors are bars that announce themselves; the progress text is read once when it appears, not on every update.
- Focus starts on the password box (password step), on the Cancel button (preview step, as there is no default), and on Done (done step).
- All controls work with the keyboard at 225% text size; in contrast themes the bars and buttons use theme brushes.

## Different by design

- **A task page**, not a sheet with its own sub-views and not a dialog with changing content: a password step, a preview, progress and a result are a page's job ([9](../platform.md#9-sheets-popovers-and-notices)); Cancel is a button and Esc is not Back.
- **No default button on the preview step**, so the import is a considered act; Apple's sheet gives its prominent button no stated Return shortcut either way.
- **Button order:** the action first and Cancel after it, as in every Windows dialog and task page.
- **The locked variant does not exist**: Windows closes the page when the library locks.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D51 (update link), B38 (update link wording).
