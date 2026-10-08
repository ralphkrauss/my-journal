---
id: reconnect-to-server
title: Reconnect after the server changed (Windows)
spec: flows/reconnect-to-server.md
features: [sync-recovery]
status: draft
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobar
---

# Reconnect after the server changed (Windows)

When sync stops because of the server, not the network, the person takes one action and this PC continues with its journals intact: the server was reset and needs setting up again; it was restored or replaced and does not know this PC; this PC's access was removed; or the server's journals are now encrypted and this PC must sign in. The steps, the lineage rules (join by identity, or Merge journals), the errors and the rules are the spec's [reconnect-to-server](../../../flows/reconnect-to-server.md); the states and their messages belong to [sync-recovery](sync-recovery.md); the flow itself, with every step and message, is [connect-to-server](../../../flows/connect-to-server.md). This file maps where the action is offered and how it opens the Connect task page on Windows.

## Controls

| Spec element | Windows control | Notes |
| --- | --- | --- |
| Set up server again…, Connect again…, Sign in… | The `ActionButton` of the Sync page's bar; the accent button of the Sync status flyout; the same action as an `InfoBar` or card on the Devices, Privacy and Agent Access pages when access is refused or encryption was turned on elsewhere ([messages](../messages.md)) | Commands `sync-reconnect`. Each opens the Connect task page at this PC's server and checks it at once; no Continue is needed |
| From the Sync status flyout | The flyout closes, then the page opens | A flyout is never open over a task page |
| From Turn on encryption (`messages.encryption.turnedOnElsewhere`, Sign in…) | The Turn on encryption page is replaced by the Connect page at the sign-in step | One task page at a time; the first is left, not stacked |
| The Connect page | One task page with a `Frame` of steps ([9](../platform.md#9-sheets-popovers-and-notices)); the address is filled in and checked; then the setup-code step (server reset), or the sign-in step (restored, replaced, access removed, encryption turned on elsewhere) | Steps, fields, errors and buttons are [connect-to-server](../../../flows/connect-to-server.md)'s |
| Set up server again | The setup-code step, with the library's password asked first when the journals have one; the new server is set up from this PC with its journals uploaded as they are | A setup code is always required and always typed. If another device set the server up meanwhile, `messages.connection.setUpElsewhere` and the flow returns to the address; continuing takes the Connect again path |
| Connect again | Sign in with the password (Add this device, or a recovery code, for a server without encryption); Use a connected device instead… is also offered | If the server holds this same library, this PC continues by identity, keeping its pending changes; identical records are adopted, different ones become changes to review, missing ones are sent |
| Merge journals (this flow's step, not Merge into) | A step of the same page, **no default button**, `Ctrl+Enter` chooses Merge ([8.1](../platform.md#81-rules), [7.1](../platform.md#71-translation-table)); the host is named in its message; Cancel or Back gives up the access just granted and nothing was sent (the spec's A35 notes that whether Back does is unverified) | Shown only when journals will actually be combined, before anything is sent |
| Sign in (encryption turned on elsewhere) | The sign-in step reads `settings.connect.signIn.introEncrypted` with `settings.connect.signIn.footerEncrypted`; the busy row shows `settings.encryption.progress` as a determinate or indeterminate `ProgressBar` | The journals on this PC are encrypted with the server's key, keeping identities and unsynced changes |
| Writing paused | The Informational `InfoBar` of [entry-editor](../screens/entry-editor.md) (`messages.writingPaused.connecting` after 1 second, `messages.writingPaused.connectionFailed`) | The editor is read-only while the library is replaced; no Show connection button, the task page is the way back |
| After success | The page returns to where it started; sync resumes at once from a clean state; the Sync page's bar goes; the Sync status button goes; the Devices list shows this PC again with how it was added | The credential is written to the secret store ([14](../platform.md#14-secure-storage)); the old one is removed once the new one is saved |
| Errors | As [connect-to-server](../../../flows/connect-to-server.md), and `messages.connection.reconnectSameServer`, `messages.connection.alreadyConnected` | Inline in the step, never a second dialog |

Rules of the spec kept: reconnecting never discards local changes (journals, unsent changes and the identity they last synced with are kept until the new connection has synchronised); a connected library facing another library merges only after Merge journals, and nothing is sent first; any other sync state or a successful sync ends the Sign in state.

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium | The page is a column at most 640 epx wide, scrolling, replacing the Settings page it started from | Mac sheet over the Settings window or the journal window |
| Small | Fills the window width | iPhone sheet |

The entry points sit where their pages are laid out: the bar of the Sync page, the Sync status button, the Devices page.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `sync-reconnect` | The Sync page bar; the Sync status flyout; the Devices, Privacy and Agent Access pages | none | The sync state calls for it |
| `connect-merge` | The Merge journals step's primary button | Ctrl+Enter | Not busy; Enter alone does not choose |
| `connect-cancel` | The page's Cancel button | — | Not while installing: stops, withdraws requests, gives up unused access, returns. Esc is not bound; the window's Close button follows [platform.md, 3](../platform.md#3-windows-and-instances) |

## Copy differences

Sentence case on the actions: "Set up server again…", "Connect again…", "Sign in…" ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)); the ellipsis stays because each opens a page that asks for input. The Merge journals hint that names a shortcut is replaced by the platform's own ([12.3](../platform.md#123-vocabulary)). The step wording is that of [connect-to-server](../screens/connect-to-server.md).

## Accessibility

- The page heading is read when it opens; the step changes are announced by the heading change and a notification; errors are inline bars that announce themselves.
- After the page returns, focus returns to the control that opened it, or to the Sync page's heading when that control is gone (the bar closes when the state clears).
- No announcement for the state clearing: sync is quiet, and the success is the bar and the button leaving ([messages](../messages.md)).

## Different by design

- **The flyout closes, and a previous task page is replaced, before the Connect page opens**: one modal flow at a time.
- **Merge journals has no default button and uses Ctrl+Enter**, as the other deliberate-choice steps ([8.1](../platform.md#81-rules)).
- **The credential store is DPAPI**, not the keychain.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): A35 (Back from Merge).
