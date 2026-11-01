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

When sync stops because of the server, not the network, the person takes one action and this PC continues with its journals intact: the server was reset and needs setting up again; it was restored or replaced and does not know this PC; or this PC's access was removed. One action, Reconnect…, covers all three. The steps, the lineage rules (join by identity, or Merge journals), the errors and the rules are the spec's [reconnect-to-server](../../../flows/reconnect-to-server.md); the states and their messages belong to [sync-recovery](sync-recovery.md); the flow itself, with every step and message, is [connect-to-server](../../../flows/connect-to-server.md). This file maps where the action is offered and how it opens the Connect task page on Windows.

## Controls

| Spec element | Windows control | Notes |
| --- | --- | --- |
| Reconnect… (`common.reconnect`) | The one `ActionButton` of the Sync page's bar (the Server section, once); the accent button of the Sync status flyout; the same action as an `InfoBar` or card on the Agent Access page with `settings.agents.connect.noAccess` when the server refuses this PC ([messages](../messages.md)). The Devices section of the Sync page has no Reconnect: while the server refuses this PC the section is absent | Command `sync-reconnect`. The label is the same whatever the state; the state decides what follows. Each opens the Connect task page, titled `settings.connect.reconnect.title`, at this PC's server and checks it at once; no Continue is needed. The title is fixed when the page opens |
| From the Sync status flyout | The flyout closes, then the page opens | A flyout is never open over a task page |
| The Connect page | One task page with a `Frame` of steps ([9](../platform.md#9-sheets-popovers-and-notices)); the address is filled in and checked; then the setup-code step (server reset), or the sign-in step (restored, replaced, access removed) | Steps, fields, errors and buttons are [connect-to-server](../../../flows/connect-to-server.md)'s |
| The server was reset | The setup-code step (a setup code is always required), then Enter {credential}: the password of the library; the new server is set up from this PC with its journals uploaded as they are, with their identities and encryption, and the library keeps its password | If another device set the server up meanwhile, `messages.connection.setUpElsewhere` and the flow returns to the address; continuing takes the Connect again path |
| The server was restored or replaced, or access was removed | Sign in with the password; Use a connected device instead… is also offered (a server without encryption is refused: `messages.connection.encryptionOff`) | If the server holds this same library, this PC continues by identity, keeping its pending changes; identical records are adopted, different ones keep both versions ([resolve-conflict](resolve-conflict.md)), missing ones are sent |
| Merge journals | A step of the same page, **no default button**, `Ctrl+Enter` chooses Merge ([8.1](../platform.md#81-rules), [7.1](../platform.md#71-translation-table)); the host is named in its message; Cancel or Back gives up the access just granted and nothing was sent (owner decision, 2026-10-06) | Shown only when journals will actually be combined, before anything is sent |
| Writing paused | The Informational `InfoBar` of [entry-editor](../screens/entry-editor.md) (`messages.writingPaused.connecting` after 1 second, `messages.writingPaused.connectionFailed`) | The editor is read-only while the library is replaced; no Show connection button, the task page is the way back |
| After success | The page returns to where it started; sync resumes at once from a clean state; the Sync page's bar goes; the Sync status button goes; the Devices list shows this PC again with how it was added (a section of the Sync page in the spec: C27) | The credential is written to the secret store ([14](../platform.md#14-secure-storage)); the old one is removed once the new one is saved |
| Errors | As [connect-to-server](../../../flows/connect-to-server.md), and `messages.connection.reconnectSameServer`, `messages.connection.alreadyConnected`; when access was removed on purpose the Sync state says `messages.sync.accessRemoved` (it names a password or a connected device) | Inline in the step, never a second dialog |

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
| `sync-reconnect` | The Sync page bar; the Sync status flyout; the Agent Access page | none | The sync state calls for it |
| `connect-merge` | The Merge journals step's primary button | Ctrl+Enter | Not busy; Enter alone does not choose |
| `connect-cancel` | The page's Cancel button | — | Not while installing: stops, withdraws requests, gives up unused access, returns. Esc is not bound; the window's Close button follows [platform.md, 3](../platform.md#3-windows-and-instances) |

## Copy differences

The action is `common.reconnect`, "Reconnect…": the ellipsis stays because it opens a page that asks for input ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)). The Merge journals hint that names a shortcut is replaced by the platform's own ([12.3](../platform.md#123-vocabulary)). The step wording is that of [connect-to-server](../screens/connect-to-server.md).

## Accessibility

- The page heading is read when it opens; the step changes are announced by the heading change and a notification; errors are inline bars that announce themselves.
- After the page returns, focus returns to the control that opened it, or to the Sync page's heading when that control is gone (the bar closes when the state clears).
- No announcement for the state clearing: sync is quiet, and the success is the bar and the button leaving ([messages](../messages.md)).

## Different by design

- **The flyout closes, and a previous task page is replaced, before the Connect page opens**: one modal flow at a time.
- **Merge journals has no default button and uses Ctrl+Enter**, as the other deliberate-choice steps ([8.1](../platform.md#81-rules)).
- **The credential store is DPAPI**, not the keychain.

## Open questions

None (A35, Back from Merge, was resolved on 2026-10-06).
