# Apple implementation index

Every screen and flow of the spec, the Apple page that describes it, and where that page stands. [README](README.md) says what a page is; [platform.md](platform.md) holds the conventions every page follows. The checker verifies that every screen, flow and `messages` page of the spec is listed exactly once, that each page is named as shown, and that the status here is the status in the page's front matter.

Status: `todo` (no page yet), `draft` (written from the source, not yet verified against the running apps and screenshots), `verified` (checked against the current source; screenshots captured by the capture script).

Pages live in `platforms/apple/screens/<id>.md`, `platforms/apple/flows/<id>.md` and `platforms/apple/messages.md`, mirroring the spec's folders (screens and flows can share an id, such as `connect-to-server`). Every page is written from the source; the `verified` ones were also checked against screenshots captured by `design/spec-screenshots/capture.sh`. A `draft` page has no screenshot of its states (see its Screenshots section for why) or was not checked against all of its source.

## Screens

| Spec | Kind | Page file | Status | Title |
| --- | --- | --- | --- | --- |
| `add-device` | screen | `screens/add-device.md` | verified | Add Device |
| `agent-detail` | screen | `screens/agent-detail.md` | verified | Agent detail and Recent Activity |
| `allow-agent` | screen | `screens/allow-agent.md` | verified | Allow Access (agent request) |
| `archive-import` | screen | `screens/archive-import.md` | draft | Import Archive (sheet) |
| `change-date` | screen | `screens/change-date.md` | verified | Change Date (sheet) |
| `change-password` | screen | `screens/change-password.md` | draft | Change Password |
| `conflict-review` | screen | `screens/conflict-review.md` | draft | Review Changes (conflicts) |
| `connect-to-server` | screen | `screens/connect-to-server.md` | draft | Connect to a Server (sheet and its steps) |
| `destination-journal` | screen | `screens/destination-journal.md` | draft | New Journal (from Move Entry and Version History) |
| `encrypt-journals` | screen | `screens/encrypt-journals.md` | draft | Encrypt Your Journals (form, notice, Done sheet) |
| `entry-conflict` | screen | `screens/entry-conflict.md` | verified | Review Changes (entry or template) |
| `entry-editor` | screen | `screens/entry-editor.md` | verified | Entry editor |
| `entry-list` | screen | `screens/entry-list.md` | verified | Entry list (a journal, All Entries, Unavailable Journals) |
| `format-sheet` | screen | `screens/format-sheet.md` | verified | Formatting (Format panel and popover) |
| `image-description` | screen | `screens/image-description.md` | verified | Image Descriptions |
| `journals` | screen | `screens/journals.md` | verified | Journals (sidebar and Journals screen) |
| `library-window` | screen | `screens/library-window.md` | verified | Library window (structure, toolbars, windows, restoration) |
| `link-editor` | screen | `screens/link-editor.md` | draft | Add Link |
| `lock-screen` | screen | `screens/lock-screen.md` | verified | Lock screen and privacy cover |
| `move-entry` | screen | `screens/move-entry.md` | verified | Move Entry |
| `recently-deleted` | screen | `screens/recently-deleted.md` | verified | Recently Deleted (list, deleted journal, recovery notice, Delete All) |
| `recovery-key` | screen | `screens/recovery-key.md` | draft | Keep Your Recovery Key (early libraries) |
| `scan-code` | screen | `screens/scan-code.md` | draft | Scan Code |
| `search` | screen | `screens/search.md` | verified | Search |
| `settings-about` | screen | `screens/settings-about.md` | verified | Settings ▸ About, and the Help menu |
| `settings-agent-access` | screen | `screens/settings-agent-access.md` | verified | Settings ▸ Agent Access |
| `settings-backup` | screen | `screens/settings-backup.md` | draft | Settings ▸ Backup, and the Export sheets |
| `settings-devices` | screen | `screens/settings-devices.md` | verified | Settings ▸ Sync ▸ Devices (a section of Sync) |
| `settings-erase` | screen | `screens/settings-erase.md` | draft | Erase Journals and Settings (section and alerts) |
| `settings-general` | screen | `screens/settings-general.md` | verified | Settings ▸ General |
| `settings-privacy` | screen | `screens/settings-privacy.md` | draft | Settings ▸ Privacy |
| `settings-sync` | screen | `screens/settings-sync.md` | verified | Settings ▸ Sync |
| `settings` | screen | `screens/settings.md` | draft | Settings |
| `sync-status` | screen | `screens/sync-status.md` | draft | Sync Status |
| `template-chooser` | screen | `screens/template-chooser.md` | verified | Template chooser (Choose a Template, Use a Template…) |
| `templates` | screen | `screens/templates.md` | verified | Templates (collection) |
| `unavailable-content` | screen | `screens/unavailable-content.md` | draft | Unavailable and read-only content |
| `version-history` | screen | `screens/version-history.md` | verified | Version History (entries and templates) |
| `welcome` | screen | `screens/welcome.md` | draft | Welcome (first launch) |

## Flows

| Spec | Kind | Page file | Status | Title |
| --- | --- | --- | --- | --- |
| `allow-agent` | flow | `flows/allow-agent.md` | draft | Connect and allow an agent |
| `app-lock` | flow | `flows/app-lock.md` | draft | App Lock |
| `change-password` | flow | `flows/change-password.md` | draft | Change password |
| `connect-to-server` | flow | `flows/connect-to-server.md` | draft | Connect to a server |
| `create-library` | flow | `flows/create-library.md` | draft | Create a library (Start a Journal) |
| `delete-and-restore` | flow | `flows/delete-and-restore.md` | verified | Delete, restore and delete permanently |
| `edit-table` | flow | `flows/edit-table.md` | verified | Edit a table |
| `editing-rules` | flow | `flows/editing-rules.md` | draft | Editing rules |
| `encrypt-journals` | flow | `flows/encrypt-journals.md` | draft | Encrypt your journals |
| `erase` | flow | `flows/erase.md` | draft | Erase journals and settings |
| `export-archive` | flow | `flows/export-archive.md` | draft | Export an archive |
| `export-markdown` | flow | `flows/export-markdown.md` | verified | Export journals as Markdown |
| `image-actions` | flow | `flows/image-actions.md` | verified | Act on a picture |
| `import-archive` | flow | `flows/import-archive.md` | draft | Import an archive (preview, restore or add) |
| `insert-image` | flow | `flows/insert-image.md` | verified | Insert an image |
| `markdown-as-you-type` | flow | `flows/markdown-as-you-type.md` | verified | Markdown as you type |
| `new-entry` | flow | `flows/new-entry.md` | verified | New entry (New Entry, then a template if wanted) |
| `pair-device` | flow | `flows/pair-device.md` | verified | Pair a new device (approving side, and both sides together) |
| `rating-request` | flow | `flows/rating-request.md` | draft | Asking for a rating |
| `reconnect-to-server` | flow | `flows/reconnect-to-server.md` | draft | Reconnect after the server changed (set up again, connect again, sign in again) |
| `resolve-conflict` | flow | `flows/resolve-conflict.md` | draft | Changes made on two devices |
| `save-entry` | flow | `flows/save-entry.md` | draft | Saving an entry |
| `save-failure` | flow | `flows/save-failure.md` | draft | Save failure and paused writing |
| `source-view` | flow | `flows/source-view.md` | verified | View Source and View Preview |
| `stop-syncing` | flow | `flows/stop-syncing.md` | draft | Stop syncing |
| `sync-recovery` | flow | `flows/sync-recovery.md` | draft | Sync health and recovery |

## Messages

| Spec | Kind | Page file | Status | Title |
| --- | --- | --- | --- | --- |
| `messages` | messages | `messages.md` | draft | Messages |
