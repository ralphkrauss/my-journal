---
id: connect-to-server
title: Connect to a server (Windows)
spec: flows/connect-to-server.md
features: [sync-connect, server-discovery, server-setup, join-with-local-journals, pair-device-scan, pair-device-code, recovery-code-join]
status: draft
sources:
  - https://learn.microsoft.com/en-us/uwp/api/windows.networking.servicediscovery.dnssd.dnssdservicewatcher
  - https://learn.microsoft.com/en-us/uwp/api/windows.networking.connectivity.networkinformation.networkstatuschanged
  - https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setthreadexecutionstate
---

# Connect to a server (Windows)

Every way a PC starts syncing: setting up a new server, joining one with a password, a recovery code or another device, with or without journals already on the PC. The decision tree, every branch and every message are the spec's [flow](../../../flows/connect-to-server.md); the task page and its steps are [connect-to-server (screen)](../screens/connect-to-server.md). This file says what Windows does at each point and where it differs.

## Controls

### One task page, one path through it

The flow runs on one task page ([platform.md, 9](../platform.md#9-sheets-popovers-and-notices)) with a `Frame` for its steps. The spec's steps map one to one onto the steps of the screen file; the spec's overview diagram holds, with these Windows changes:

- The scanned-code branches (spec step 2, "Finish on Your Other Device", `Scan Again`, the scanned-code row in the error tables) do not exist on Windows. Everything the spec says there is for a phone or tablet.
- A server whose recovery format is 3 or 4 (set up without encryption by an earlier version) is refused with `messages.connection.encryptionOff`: for a typed or nearby address on the first step, and when finishing a pairing. Nothing is sent. Windows has no unencrypted library, so the spec's branch for a device with one (Add This Device and Use a Recovery Code for a server without encryption, then Encrypt Your Journals) never runs here ([encrypt-journals](encrypt-journals.md)).
- A device that has journals reaches Merge journals before anything is sent, as in the spec; Merge records consent for this server for the rest of the flow; consent is checked again just before installing.

### Windows details of the spec's steps

| Spec step | Windows |
| --- | --- |
| 1 Choose a server | Discovery is `DnssdServiceWatcher` and runs only while the step is shown. A server is checked with HTTPS through the standard HTTP stack, which uses the Windows certificate store and the system proxy settings ([platform.md, 32](../platform.md#32-local-network-and-servers)): a server with a private certificate authority needs that authority installed as trusted; a certificate Windows does not trust fails the request like any other connection failure, which the spec's failure rows cover (the table has no certificate row of its own). The spec's wait of up to 20 seconds for the Local Network permission prompt does not apply (no prompt); the request still has its time limit, and `messages.connection.cannotConnect`, or `messages.connection.cannotConnectTailscale` for hosts ending in `.ts.net` (Tailscale is a normal Windows app; the message tells the person to turn it on), shows when it runs out. Only HTTPS addresses are accepted: `messages.error.invalidAddress` |
| 3 Set up server | The setup code is formatted as typed (upper case, spaces and dashes removed, the hyphen after three characters), validated as in the spec, and never submitted automatically. Field errors: `messages.connection.setupCodeLength`, `messages.connection.setupCodeCharacters`, `messages.connection.setupCodeIncorrect`, `messages.connection.setupCodeRateLimited` |
| 4 to 5 Choose a master password, Enter {credential} | `PasswordBox` fields; nothing is sent but derived secrets; any non-empty password is accepted; the fields are cleared when the step ends. The device key is created and stored with the Windows Data Protection API through `ISecretStore` ([platform.md, 14](../platform.md#14-secure-storage)) when the library is created or installed |
| 6 Setting up | Saves the open entry (`messages.save.before.goBack` if it cannot), checks for an existing connection (`messages.connection.alreadyConnected`, `messages.connection.reconnectSameServer`), sends the setup code with the library's recovery information, saves the connection (the server credentials go to `ISecretStore`, never to a settings file), uploads the journals. The device name sent is the PC's name as the system reports it, editable afterwards with the rename of D9 and disclosed on the Devices page (D45) |
| 7 Merge journals (this flow's step, not Merge into) | As in the spec; Ctrl+Enter, no default button |
| 8 Sign in | As in the spec, with its field errors and the Merge branch |
| 9 Add this device | The nine-digit code with Copy (clipboard options of [platform.md, 15](../platform.md#15-clipboard)); polling every second, slowing to every 16 seconds when the server asks; the check code announced; Connect with Ctrl+Enter |
| 10 Recovery code | Anything that is not 64 hexadecimal digits is refused without sending (`messages.connection.recoveryCodeIncorrect`); a refused code gives the same message; `messages.server.rateLimited` for too many attempts |
| 11 Installing | Saves first; a library with nothing written is replaced by the server's; a library with journals continues by identity or merges into a new copy, with phases `settings.connect.busy.checking`, `settings.connect.busy.downloading`, `common.merging`; only when everything synced does the library switch, then the page shows Server is ready or returns. Writing is paused meanwhile |
| 12 Safeguards | The spec's list is shown if it ever occurs: `messages.connection.chooseUpload`, `messages.connection.createJournalFirst`, `messages.connection.alreadyHasJournals`, `messages.error.locked`, `messages.error.invalidData`, `messages.error.unauthorized`, `messages.error.invalidSetupCode`, as an error row of the current step |

### Windows adds

- **The PC stays awake while installing.** From the moment Set up or Sign in starts until the page ends the app holds the system awake (`SetThreadExecutionState` with the system-required flag) so a laptop's idle sleep does not interrupt a join that downloads many images. It is released on every exit path.
- **Closing the window while connecting** follows the one rule of [platform.md, 3](../platform.md#3-windows-and-instances): Alt+F4 or the Close button while the page is open waits for the current atomic step, then acts as Cancel: it stops what is running, withdraws a pairing request, gives up unused access and discards a staged copy, then the app closes. While installing, the Cancel button is disabled, but the window's Close button is not: it waits for the atomic step of the install and then discards the staged copy. Because the library only switches at the end, an interrupted join always leaves the library as it was ([flows/save-entry](save-entry.md) for the first save). If the library has already switched, the window closes after that step.
- **Network changes.** `NetworkStatusChanged` ends a wait on a failing step sooner than the next poll; it never retries a step by itself. Retrying is the Try Again button.
- **Sleep and lock.** If the PC sleeps or its screen locks while a step is waiting on the server or another device, the library locks and the page cancels as in the spec; after unlocking, the person starts again. A lock never leaves half a join: the same rule as Cancel.
- **The inactivity timer is held** while the page waits on the server or another device ([app-lock](app-lock.md)).
- **Writing paused.** While the page is open the window is modal, so no notice is needed. If a connection failed and a copy waits for Try Again after the page was left (not possible by the buttons, only after a crash), the editor shows `messages.writingPaused.connectionFailed` (this PC) as an `InfoBar` without the Show Connection button ([platform.md, 9.1](../platform.md#91-notices)).

## Layout at each window width

Not applicable beyond the page's behaviour in the [screen file](../screens/connect-to-server.md): the flow is the same at every width.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `connect-to-server` | Entry points: Settings pages, first-launch page | as in commands.md | Always (unlocked) |
| `sync-reconnect` | Reconnect actions: the page opens already on the server's next step ([flows/reconnect-to-server](../../../flows/reconnect-to-server.md)) | as in commands.md | Not while a sync the person started runs |
| `connect-confirm-check-code`, `connect-merge` | Task page | `Ctrl+Enter` | As in the screen file |
| `connect-cancel` | Task page, Cancel button | — | Not while installing; the window's Close button (Alt+F4) then waits for the atomic step and discards the staged copy |

The key table of the page is in the [screen file](../screens/connect-to-server.md).

## Copy differences

Only what the screen file lists; no copy of the spec's messages changes except sentence case and the "select" wording of two (`messages.connection.serverChanged`, `messages.connection.setUpElsewhere`, B26). The Mac-specific writing-paused strings say "this PC" ([platform.md, 12.3](../platform.md#123-vocabulary)).

## Accessibility

- Every error is announced when it appears, and field errors after focus moves to the field. The check code is announced when it appears. Busy rows are one element each.
- Merge and Connect need Ctrl+Enter, never Enter alone.
- Focus: each step takes it on its first field or heading after the page navigates.

## Different by design

- **Servers without encryption are refused** (`messages.connection.encryptionOff`), with no Protect step, no choice of encryption and no Use a Recovery Code path: Windows has no unencrypted library to keep working with one.
- **No scanned-code path.** The scanned-code steps, errors and `messages.pairing.inviteNewerVersion`, `messages.pairing.inviteUnreachable`, `messages.pairing.inviteUsed` belong to phones and tablets (D24).
- **No Local Network permission** and no message about it.
- **Closing the window is Cancel** (after the current atomic step); the PC is kept awake while installing; one task page replaces the Mac's Settings window plus journal-window notices.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): B26 (select and choose), D45 (device name a PC sends).
