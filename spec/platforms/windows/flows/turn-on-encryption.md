---
id: turn-on-encryption
title: Turn on encryption (Windows)
spec: flows/turn-on-encryption.md
features: [turn-on-encryption]
status: draft
sources:
  - https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setthreadexecutionstate
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/progress-controls
---

# Turn on encryption (Windows)

Moves journals without encryption to encryption with a master password, on this PC and on its server, without losing anything and without other devices silently diverging. The steps, every error and every rule are the spec's [flow](../../../flows/turn-on-encryption.md); the task page is [turn-on-encryption (screen)](../screens/turn-on-encryption.md). This file says what Windows does around them.

## Controls

The steps are the screen's three steps (Turn on encryption, Choose a master password, Your journals are encrypted), shown on one task page. Windows details of the spec's steps:

| Spec step | Windows |
| --- | --- |
| 1 Continue: free space, server check | Free space is read from the volume that holds the app's local folder (`StorageFolder.Properties`, "System.FreeSpace"); the encrypted copy needs room for the library plus its images. `messages.encryption.notEnoughSpace` names the size to free, formatted with the shell's byte formatter in the user's language. A PC with a nearly full system drive is common, so this check is shown plainly |
| 2.1 Current access password | Checked as in the spec: `messages.encryption.incorrectPassword`, `messages.encryption.rateLimited` |
| 2.2 to 2.3 Save, receive everything | Syncing runs first; images download until a pass gets none; `messages.encryption.imagesMissing` otherwise |
| 2.4 Encrypted copy | `settings.encryption.progress` with a determinate bar on the page. Writing is paused from here ([Controls of the screen](../screens/turn-on-encryption.md)); the library is behind a modal task page, so no notice is shown |
| 2.5 Server switch | `settings.encryption.updatingServer`, announced with `messages.encryption.announce.updatingServer`; Cancel is disabled; this cannot be cancelled |
| 2.6 Open the encrypted copy | The new key is protected with the Windows Data Protection API through `ISecretStore` and the old secret is replaced in one step ([platform.md, 14](../platform.md#14-secure-storage)); writing resumes. If the secret cannot be saved the unfinished state applies (below) |
| 3 Done | `messages.encryption.announce.done`; the page offers Add another device when syncing |

### Windows adds

- **The PC does not sleep while encrypting.** From Turn on until the page ends the app holds the system awake (`SetThreadExecutionState` with the system-required flag), because a laptop that sleeps between "server updated" and "this PC finished" lands in the unfinished state. It is released on every exit path, including a failure. The display may still turn off.
- **No background time limit.** The spec's iPhone and iPad rule (background time runs out; `messages.encryption.background`) does not apply: a Windows desktop app is not suspended in the background and the window is modal anyway. The message is never shown.
- **Closing the window or signing out** follows the one rule of [platform.md, 3](../platform.md#3-windows-and-instances): before the server is updated, closing the window or ending the session waits for the current atomic step, then cancels the work and discards the copy: the journals are unchanged. After the server was updated, closing leaves the unfinished state, and the next launch opens the page by itself at step 2, where Try again finishes it. The app does not hold up a shutdown for this ([platform.md, 3](../platform.md#3-windows-and-instances) holds it only for saves). Writing stays paused until finished.
- **Locking** cancels the work if it can still be cancelled; once the server is being updated it continues, and the library is locked while it does.
- **Archives and backups made earlier stay unencrypted** (`settings.encryption.done.archives`). That includes Markdown exports and anything in a OneDrive folder; the page says so in the spec's words.
- **Other devices** see `messages.sync.signInNeeded` and use Sign in; agents with access on the server lose it ([flows/allow-agent](allow-agent.md)).
- **Errors** are the spec's table and are shown as the step's `InfoBar` or field error, each announced: `common.couldntReachHost`, `messages.encryption.unreachable`, `messages.encryption.serverOutdated`, `messages.encryption.notEnoughSpace`, `messages.encryption.accessLost`, `messages.encryption.turnedOnElsewhere` (primary becomes Sign in…), `messages.encryption.stillSyncing`, `messages.encryption.imagesMissing`, `messages.encryption.unfinished`, `messages.encryption.failed`, `messages.connection.passwordsDontMatch`. The last row of the spec's table, `messages.refresh.encryptionOn`, appears in the step's error bar while the page is open; if the page has already ended it is the general error dialog (a `ContentDialog` with the message, Close `common.ok`, no title), never a dialog over a dialog ([messages](../messages.md)).

## Layout at each window width

Not applicable: the page's layout is in the [screen file](../screens/turn-on-encryption.md); the flow does not change with width.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `turn-on-encryption` | Button in Settings > Privacy | — | Unlocked; not while the library is being replaced (except to show a run) |
| `encryption-continue`, `encryption-turn-on`, `encryption-finish`, `encryption-cancel`, `encryption-done` | Task page buttons | `Enter` as in the screen file (Esc is not bound) | As in the screen file |

## Copy differences

Only what the screen file lists. `messages.writingPaused.encrypting` and `messages.writingPaused.encryptionUnfinished` say "this PC" ([platform.md, 12.3](../platform.md#123-vocabulary)); `messages.encryption.background` is not shown.

## Accessibility

- Progress is announced as a percentage (every 10% step, at most every five seconds); state changes and errors are announced; the server update announcement cannot be missed (`ImportantMostRecent`).
- Focus: after an error it goes to the field or button that can fix it; at launch the page opens with Narrator reading its heading and the unfinished message.

## Different by design

- **A task page the app reopens by itself** replaces the Mac's journal-window notice with Show Progress.
- **Keep-awake instead of background time**, and a shutdown simply cancels work that can still be cancelled.
- **No `messages.encryption.background`.**

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): B26 (select and choose).
