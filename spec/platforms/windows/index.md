# Windows mapping index

Every screen and flow of the spec, the Windows mapping file that will describe it, and where that file stands. [README](README.md) says what a mapping file is; [platform.md](platform.md) holds the conventions every file follows; [commands.md](commands.md) places every command. The checker verifies that every screen, flow and `messages` page of the spec is listed exactly once, that each mapping file is named as shown, and that the status here is the status in the file's front matter.

Status: `todo` (no file yet), `draft` (written, not reviewed by the design reviewer), `reviewed` (design review done and findings addressed), `done` (implemented and checked against the running app).

Mapping files live in `platforms/windows/screens/<id>.md`, `platforms/windows/flows/<id>.md` and `platforms/windows/messages.md`, mirroring the spec's folders (screens and flows can share an id, such as `connect-to-server`).

## Batches

Three batches of about equal size. Batch 1 first: it fixes the shell and the editor control that the others reuse. Batches 2 and 3 can run in parallel after `library-window` and `settings` are written. In each batch, write the first row first and link to it from the rest. The questions the batches raised are consolidated in [open-questions.md](../../open-questions.md) (D20 to D54 and B26 to B41 for the Windows mapping), and every proposed Windows string is in [copy-proposals.md](copy-proposals.md). The folder had an independent design review on 2026-10-06 ([review-2026-10-06.md](review-2026-10-06.md)); a page is `reviewed` when every finding touching it is resolved, and stays `draft` when it was substantially revised and needs a second review before implementation, or when a finding is waiting on a spike or an owner decision.

| Batch | Pages | Covers |
| --- | --- | --- |
| 1. Library and editor | 23 | The window, journals, entries, search, editor, formatting, images, tables |
| 2. Settings, connections and security | 24 | Settings pages, connecting, devices, encryption, App Lock, agents, erase |
| 3. Messages, states and flows not covered | 18 | First launch, import and export, sync states and recovery, conflicts, history, ratings, messages |

## Batch 1: library and editor

Sources: [screens/library-window](../../screens/library-window.md), [screens/entry-editor](../../screens/entry-editor.md) and their neighbours. Start from [platform.md](platform.md) sections 2, 4, 5, 7 and 9. The entry-editor mapping waits for the two editor control spikes, run in parallel ([34](platform.md#34-open-questions)).

| Spec | Kind | Mapping file | Status | Notes |
| --- | --- | --- | --- | --- |
| `library-window` | screen | `screens/library-window.md` | draft | The shell: `TitleBar` (Sync status, no menus on lock and first-run pages), `NavigationView` with the built-in Settings item, `ListView`, splitter; layouts at the three widths; window state; command bars. Write this first. |
| `journals` | screen | `screens/journals.md` | draft | The journals as a `ListView` in the navigation pane, counts as plain text, journal context menu (New journal…, Rename…, Delete journal), reordering, New journal dialog. |
| `entry-list` | screen | `screens/entry-list.md` | reviewed | `ListView` with month groups, rows, pin, swipe, context menu, empty states, the list header. |
| `templates` | screen | `screens/templates.md` | reviewed | Templates collection; context menu items; a template is never used from this list. |
| `recently-deleted` | screen | `screens/recently-deleted.md` | reviewed | Collection, Restore and Restore to “{name}” at once (no dialog), deleted journal's page with Restore journal, recovery notice as `InfoBar`, Delete all. |
| `unavailable-content` | screen | `screens/unavailable-content.md` | reviewed | Unavailable and read-only states; notices with Restore to “{name}”; no cover. |
| `search` | screen | `screens/search.md` | reviewed | `AutoSuggestBox` in the list header; prompts; No results. |
| `template-chooser` | screen | `screens/template-chooser.md` | reviewed | Flyout anchored to the editor with filter and list, filling the open empty entry; File ▸ Use a template…; IME composition rule. |
| `entry-editor` | screen | `screens/entry-editor.md` | draft | Depends on two parallel editor control spikes with written pass and fail criteria; layout, notices, blocks, Zoom, UI Automation. |
| `format-sheet` | screen | `screens/format-sheet.md` | draft | Formatting bar and selection mini-toolbar; toggle buttons; the Format menu. |
| `link-editor` | screen | `screens/link-editor.md` | reviewed | Link dialog. |
| `image-description` | screen | `screens/image-description.md` | reviewed | A page with a list of pictures and text boxes. |
| `change-date` | screen | `screens/change-date.md` | reviewed | Dialog with a `CalendarDatePicker`, date only. |
| `move-entry` | screen | `screens/move-entry.md` | reviewed | Dialog with a list of journals; moving only (restoring is plain Restore). |
| `destination-journal` | screen | `screens/destination-journal.md` | reviewed | New journal from Move entry and Version history; no dialog on a dialog. |
| `new-entry` | flow | `flows/new-entry.md` | reviewed | New entry, always blank; a template is used afterwards from inside the entry; Ctrl+N. |
| `save-entry` | flow | `flows/save-entry.md` | reviewed | Save before closing, locking, moving; Ctrl+S. |
| `editing-rules` | flow | `flows/editing-rules.md` | draft | Key by key: Windows key names, Ctrl+Backspace, IME composition. |
| `markdown-as-you-type` | flow | `flows/markdown-as-you-type.md` | reviewed | Typing rules; Backspace undoes a shortcut. |
| `insert-image` | flow | `flows/insert-image.md` | reviewed | Image file picker, paste, drag and drop; no Photo Library or Take Photo. |
| `image-actions` | flow | `flows/image-actions.md` | reviewed | Picture context menu; Share UI; Save image as. |
| `edit-table` | flow | `flows/edit-table.md` | draft | Cell menus, Tab and Enter in cells. |
| `source-view` | flow | `flows/source-view.md` | reviewed | View source and View preview. |

## Batch 2: settings, connections and security

Sources: [screens/settings](../../screens/settings.md), [screens/lock-screen](../../screens/lock-screen.md), [flows/app-lock](../../flows/app-lock.md). Start from [platform.md](platform.md) sections 8, 10, 13, 14, 15, 20 and 29.

| Spec | Kind | Mapping file | Status | Notes |
| --- | --- | --- | --- | --- |
| `settings` | screen | `screens/settings.md` | reviewed | Settings page, home cards, About group, `BreadcrumbBar`; sets the card patterns the other settings pages reuse. |
| `settings-general` | screen | `screens/settings-general.md` | reviewed | General page: default journal, Markdown as you type, Erase group. |
| `settings-sync` | screen | `screens/settings-sync.md` | reviewed | Sync page: status, Sync now, Stop syncing, Changed on two devices (clickable cards for entries, templates and edits against deletions; Clear list), footers as descriptions. |
| `settings-devices` | screen | `screens/settings-devices.md` | reviewed | Devices page: list, Add device, revoke. |
| `settings-privacy` | screen | `screens/settings-privacy.md` | draft | Privacy page: encryption, App lock expander, Lock when inactive. |
| `settings-backup` | screen | `screens/settings-backup.md` | draft | Backup page: archive and Markdown groups; pickers. |
| `settings-agent-access` | screen | `screens/settings-agent-access.md` | reviewed | Agent Access page: address, requests, agents. |
| `settings-about` | screen | `screens/settings-about.md` | reviewed | About group and the Help menu; version; Store rating link. |
| `settings-erase` | screen | `screens/settings-erase.md` | reviewed | Erase group and its dialogs. |
| `connect-to-server` | screen | `screens/connect-to-server.md` | draft | A task page with a `Frame` of steps; typed-code path; no scanner. |
| `scan-code` | screen | `screens/scan-code.md` | reviewed | Not offered in version 1; records the decision and the later design. |
| `add-device` | screen | `screens/add-device.md` | reviewed | Dialog: QR code on a white tile, typed code, check code, Windows Hello. |
| `change-password` | screen | `screens/change-password.md` | reviewed | Dialog with three `PasswordBox` fields; Forgot password? replaces the current-password field after Windows Hello. |
| `encrypt-journals` | screen | `screens/encrypt-journals.md` | draft | Not applicable: Windows has no unencrypted libraries; never shown. |
| `lock-screen` | screen | `screens/lock-screen.md` | draft | Lock page, Windows Hello, App Lock paused, no privacy cover, capture exclusion; written with `platform.md` sections 13, 14 and 20. |
| `agent-detail` | screen | `screens/agent-detail.md` | reviewed | Agent's page. |
| `allow-agent` | screen | `screens/allow-agent.md` | reviewed | Allow access dialog. |
| `connect-to-server` | flow | `flows/connect-to-server.md` | draft | Step by step, with the task page's states. |
| `pair-device` | flow | `flows/pair-device.md` | reviewed | Both sides; no camera needed. |
| `encrypt-journals` | flow | `flows/encrypt-journals.md` | draft | Not applicable: never run; a server without encryption is refused. |
| `change-password` | flow | `flows/change-password.md` | reviewed | Steps, the failure branches and Forgot password?. |
| `app-lock` | flow | `flows/app-lock.md` | draft | Triggers on Windows: launch, Ctrl+L, inactivity, session lock, sleep. |
| `allow-agent` | flow | `flows/allow-agent.md` | reviewed | Connect and allow an agent. |
| `erase` | flow | `flows/erase.md` | reviewed | What Windows removes; Windows Hello when App Lock is on. |

## Batch 3: messages, states and flows not covered

Sources: [messages](../../messages.md), [flows/sync-recovery](../../flows/sync-recovery.md), [flows/save-failure](../../flows/save-failure.md). Start from [platform.md](platform.md) sections 9, 11, 16, 28 and 30.

| Spec | Kind | Mapping file | Status | Notes |
| --- | --- | --- | --- | --- |
| `welcome` | screen | `screens/welcome.md` | reviewed | First-launch page; Start a Journal; Connect; Import. |
| `archive-import` | screen | `screens/archive-import.md` | draft | Import task page with preview. |
| `recovery-key` | screen | `screens/recovery-key.md` | reviewed | Probably not offered on Windows (open-questions D11). |
| `sync-status` | screen | `screens/sync-status.md` | reviewed | Title bar button with an `InfoBadge`; a flyout with the states. |
| `kept-version-notice` | screen | `screens/kept-version-notice.md` | draft | The Informational `InfoBar` above the open entry or template that was kept as two versions; no review page. |
| `version-history` | screen | `screens/version-history.md` | reviewed | Entry and template version history page with side-by-side comparison. |
| `messages` | messages | `messages.md` | reviewed | Sync states, save failures, kept versions, unavailable content as `InfoBar`s and dialogs; severity table; announcements. |
| `create-library` | flow | `flows/create-library.md` | reviewed | Start a Journal, encryption choices. |
| `import-archive` | flow | `flows/import-archive.md` | draft | File activation, Open picker, preview, restore or add. |
| `export-archive` | flow | `flows/export-archive.md` | draft | Save picker, progress, password check. |
| `export-markdown` | flow | `flows/export-markdown.md` | draft | Folder picker, Windows-safe file names, Windows Hello when App Lock is on. |
| `reconnect-to-server` | flow | `flows/reconnect-to-server.md` | draft | Reconnect. |
| `stop-syncing` | flow | `flows/stop-syncing.md` | reviewed | Confirmation dialog. |
| `sync-recovery` | flow | `flows/sync-recovery.md` | reviewed | Triggers: window activation, network change, resume; paces. |
| `resolve-conflict` | flow | `flows/resolve-conflict.md` | draft | Changes made on two devices: nothing shows when it happens; the notice, the quiet list, opening a note, the short refusals. |
| `save-failure` | flow | `flows/save-failure.md` | reviewed | Keep Open dialog on close; notices. |
| `rating-request` | flow | `flows/rating-request.md` | reviewed | `StoreContext` request and the Store-only rule. |
| `delete-and-restore` | flow | `flows/delete-and-restore.md` | reviewed | Delete, Undo, Restore (one verb, at once), delete permanently. |

## Reading order for a mapping author

1. The spec file you are mapping, and the screens and flows it links.
2. [platform.md](platform.md) for every convention that applies; link to its sections instead of repeating them.
3. [commands.md](commands.md) for the shortcuts and placements of the commands your screen uses; do not restate them except where your screen differs.
4. The Apple reference code named in the spec file's `sources:`.
5. Write the mapping file ([README](README.md)); ask the independent design reviewer to review it before any implementation, as [AGENTS.md](../../../AGENTS.md) requires.
