---
id: connect-to-server
title: Connect to a Server (sheet and its steps)
features: [sync-connect, server-discovery, server-setup, join-with-local-journals, pair-device-scan, pair-device-code, recovery-code-join, sync-recovery]
sources:
  - apps/apple/JournalApp/Views/ConnectionView.swift
  - apps/apple/JournalApp/Views/ConnectionSteps.swift
  - apps/apple/JournalApp/Views/MergeJournalsView.swift
  - apps/apple/JournalApp/Model/EncryptionUpgrade.swift
  - apps/apple/JournalApp/Views/SaveFailureNotice.swift
  - apps/apple/JournalApp/Model/ConnectionFlow.swift
  - apps/apple/JournalApp/Model/ServerJoining.swift
  - apps/apple/JournalApp/Model/ServerEnvelopeCheck.swift
  - apps/apple/JournalApp/Model/ServerBrowser.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/CodeEntry.swift
  - docs/design/connection-onboarding.md
  - docs/design/effortless-connection.md
  - docs/design/join-with-local-journals.md
  - docs/design/sync-health-and-recovery.md
  - docs/design/sync-security-2026-09-24.md
  - docs/design/1-1-encryption-and-passwords.md
---

# Connect to a Server

## Purpose

One sheet that takes this device from "not syncing" (or "sync stopped working") to syncing with a server: choose the server, then set it up or add this device to it, one step at a time. The full decision tree, with every branch and error, is in `flows/connect-to-server`; reconnecting a device whose server changed is in `flows/reconnect-to-server`. This file describes each page.

## Entry points

- First-launch screen: Connect to a Server… (`screens/welcome`, owned by onboarding).
- Settings ▸ Sync: Connect to a Server… (not connected), and Reconnect… (`screens/settings-sync`).
- Settings ▸ Privacy: Reconnect… after encryption was turned on elsewhere (`screens/settings-privacy`).
- Settings ▸ Agent Access: Connect to a Server…, and Reconnect… when this device lost access (`screens/settings-agent-access`).
- Sync Status's Reconnect… (`screens/sync-status`).

Opened by Reconnect… the sheet is titled `settings.connect.reconnect.title` ("Reconnect") instead; everything else on it is the same.

The sheet is a navigation stack: the first page chooses a server; each later step is pushed. Work and its failure stay on the step where it started; the next step appears only once the work succeeds.

## Content

### Common to every page

- An error row at the end of the page, in red, smaller text, for a failure that isn't about one field. Field errors appear under their field instead.
- A busy row while waiting on the server (activity indicator and a label such as `settings.connect.busy.checking`), except on Add This Device and Finish, which show progress beside their instructions. While a device that signs in again encrypts its own journals, the busy row shows the encryption progress (`settings.encryption.progress`, with a progress bar).
- Toolbar: a cancel button and the step's primary (confirming) button, described per page.
  - Cancel (`common.cancel`) is disabled while installing (connecting, setting up, signing in).
  - Phone/tablet: Back is shown where going back is allowed; Cancel is shown only where Back isn't. Computer: Cancel is always shown (Back is available as well where allowed).
  - Back isn't allowed while working, on Server Is Ready and Finish, or on Choose a Master Password once a journal was created in this sheet.

### Page 1: Choose a server

Title `settings.connect.title` ("Connect to a Server"), or `settings.connect.reconnect.title` ("Reconnect") when the sheet was opened by Reconnect…; the title is fixed when the sheet opens.

- **Locked:** only `settings.connect.locked`; no primary button.
- **A scanned code is being used:** a section with the label `settings.connect.server` and the code's server host (selectable); while it's checked, a busy row `settings.connect.busy.checking`. If checking failed, the primary button is `common.tryAgain` (the connection failed and the same code can be used again) or `settings.connect.scanAgain` ("Scan Again", the code can't be used again).
- **Otherwise**, in order:
  1. **Scan Code** (only on devices that can scan with a camera): a button `settings.connect.scanCode` with a QR icon; footer `settings.connect.scanCode.footer`. Opens `screens/scan-code`.
  2. **Servers on This Network** (header `settings.connect.nearby.header`): one row per server announced on the local network, sorted by host. Each row shows the host (with port when not the default) and, in secondary text, the announced name (for example “My Journal on server”). While that server is being checked its row shows an activity indicator; all rows are disabled while checking. Under the rows:
     - local network access denied: `settings.connect.nearby.denied` (variant for computer and phone/tablet);
     - no servers yet, during the first 5 seconds: busy row `settings.connect.nearby.looking`;
     - no servers after 5 seconds: `settings.connect.nearby.none`.
  3. **Server Address** (header `common.serverAddress`): a text field (label `common.serverAddress`, placeholder `settings.connect.address.placeholder`), no autocorrection or capitalisation, URL keyboard; prefilled with this device's current server address if it has one. While a typed address is checked, a busy row `settings.connect.busy.checking`. Footer `settings.connect.address.footer`.
- Primary: `common.continue`, disabled while checking or when the address is empty. Return in the field does the same.

### Step: Set Up Server

Title `settings.connect.setUp.title`. Shown when the chosen server isn't set up yet.

1. Row: label `settings.connect.server`, value the host (selectable).
2. Section with header `settings.connect.setUp.code`: a monospaced field (accessibility label `settings.connect.setUp.code`, placeholder `settings.connect.setUp.codePlaceholder` "XXX-XXX"), capitalising, ASCII keyboard. Its field error appears under it. Footer, in order:
   - `settings.connect.setUp.footer`;
   - link `settings.sync.footer.howToSetUp` ("How to Set Up a Server") → `<repository>/blob/main/docs/guide/sync.md#use-your-own-server`;
   - only when Set Up follows directly and this device already had journals before opening the sheet: `settings.connect.setUp.upload` ("The journals on this device will be uploaded to {host}."), followed by `settings.connect.merge.footerUnencrypted` when the journals aren't encrypted.
- Primary: `settings.connect.setUp.setUp` ("Set Up") when Set Up follows directly, otherwise `common.continue`. Disabled while working or when the code is empty. Return does the same.
- Field errors: `messages.connection.setupCodeLength`, `messages.connection.setupCodeCharacters`, `messages.connection.setupCodeIncorrect`, `messages.connection.setupCodeRateLimited`.

### Step: Choose a Master Password

Title `common.chooseMasterPassword`. Only when this device has no journals yet (a server is being set up from a new device): there is no Protect step and no choice of whether to encrypt, because every new library is encrypted. The page after the setup code is this one.

1. Intro: `settings.connect.choosePassword.intro` ("…before they’re sent to {host}.").
2. Fields: `common.masterPassword` ("Master Password"), then `common.verify` ("Verify"), both new-password fields (`spec/README.md`, Master passwords: two fields, they must match, no minimum length); no autocorrection. A switch `common.showPassword` ("Show Password") shows both as plain text. Return in the first moves to Verify; Return in Verify sets up.
3. Footer: `settings.password.footer`.
- The fields are disabled while working and once a journal was created here (Try Again reuses the same password).
- Primary: `settings.connect.setUp.setUp`, or `common.tryAgain` after a journal was created here; disabled while working or when either field is empty.
- Field error on Verify: `messages.connection.passwordsDontMatch`.

### Step: Enter {credential} (setting up from a device with a password)

Title `settings.connect.signIn.title` ("Enter {credential}", for example "Enter Master Password"). When this device's journals are protected by a password the server's recovery must be derived from.

1. Intro: `settings.connect.enterExisting.intro` ("Enter the {credential} for the journals on this device. Your other devices will use it to sign in to {host}."), credential in lower case.
2. A secure field labelled with the credential's name; a switch `settings.connect.showCredential` ("Show {credential}"). Field error under it.
3. Footer: `settings.connect.setUp.upload`.
- Primary: `settings.connect.setUp.setUp`; disabled while working or empty.

### Step: Server Is Ready

No title in the bar.

1. A centred block: a checkmark symbol (decorative), heading `settings.connect.ready.title` ("Server Is Ready"), and `settings.connect.ready.message` ("Your journals will sync with {host}.").
2. A section with `settings.connect.ready.addDevice` ("Add Another Device…"), which opens `screens/add-device` as a sheet. Footer, only when the journals have a password: `settings.connect.ready.footer` ("You can also sign in on your other devices with your {credential}.").
- Toolbar: only `common.done`, which closes the sheet.

### Step: Enter {credential} (sign in)

Title `settings.connect.signIn.title` ("Enter {credential}"), where the credential is what the server's journals use: Master Password, Recovery Key (servers set up by early versions) or Access Password.

1. Intro, one of:
   - signing in after the server started using encryption: `settings.connect.signIn.introEncrypted`;
   - a server set up with a recovery key: `settings.connect.signIn.introRecoveryKey` ("Enter the recovery key you saved when you set up {host}.");
   - otherwise: `settings.connect.signIn.intro` ("Enter the {credential} you chose when you set up {host}.").
2. A secure field (label: the credential's name) with password-manager autofill; switch `settings.connect.showCredential`. Field error under it.
   Footer: when signing in after encryption was turned on elsewhere, `settings.connect.signIn.footerEncrypted`; otherwise, only when this device has nothing written, `settings.connect.download` ("Your journals will download to this device.").
3. A section with `settings.connect.signIn.useDevice` ("Use a Connected Device Instead…"), which pushes Add This Device. Disabled while working.
- Primary: `settings.connect.signIn.signIn` ("Sign In"), or `common.tryAgain` after merging stopped part way. Disabled while working or empty.
- Busy row: `settings.connect.busy.signingIn`, then the joining phases `settings.connect.busy.checking`, `settings.connect.busy.downloading`, `common.merging`.

### Step: Add This Device

Title `settings.connect.addThisDevice.title`. For a server with a password, after Use a Connected Device Instead…; for a server without encryption, directly.

One section, showing one of:
- after a failure: nothing (the error row explains, and the primary button offers the next step);
- before a code exists: busy row `settings.connect.addThisDevice.gettingCode` ("Getting a code…");
- **the pairing code:** the nine digits in large monospaced type, grouped in threes (“123 456 789”), selectable; a button `settings.connect.addThisDevice.copyCode` ("Copy Code"); the instruction `settings.connect.addThisDevice.instructions`; and while waiting, a busy row `settings.connect.waitingForApproval` (or, while installing, the installing label such as `common.connecting`);
- **the check code** (once the approving device joined): heading `settings.connect.checkCode.title` ("Check Code"), the six digits in large monospaced type grouped in threes (“123 456”), `settings.connect.checkCode.instructions` ("Connect only if your other device shows the same code."), and while installing the installing label, or after Connect while waiting for the other device, `settings.connect.checkCode.waiting`.

Footer: `settings.connect.download` when this device has nothing written.

For a server without encryption, a further section: `settings.connect.addThisDevice.useRecoveryCode` ("Use a Recovery Code Instead…"), which withdraws the pairing request and pushes Use a Recovery Code. Disabled while installing.

- Primary:
  - while the check code is shown and not yet confirmed: `common.connect` ("Connect"), shortcut Command-Return (not Return); on the computer its help tag is `settings.connect.addThisDevice.connectHelp` and its accessibility hint `settings.connect.addThisDevice.connectHint`;
  - after a failure: `settings.connect.addThisDevice.getNewCode` ("Get New Code") if nothing was received from the other device, else `common.tryAgain`.

### Step: Use a Recovery Code

Title `settings.connect.recoveryCode.title`. For a server without encryption.

1. A secure field `common.recoveryCode` ("Recovery Code"); switch `settings.connect.recoveryCode.show` ("Show Recovery Code"). Field error under it.
2. Footer: `settings.connect.recoveryCode.footer`, followed by a space and `settings.connect.download` when this device has nothing written.
- Primary: `common.connect` ("Connect"), or `common.tryAgain` when the one-time code was already used by an attempt that failed afterwards (Try Again continues with the access it gave). Disabled while working or empty.

### Step: Merge Journals

Title `settings.connect.merge.title`. Before anything is sent from a device that already has journals.

1. Intro: `settings.connect.merge.intro` ("The journals on this device will be merged with the journals on {host}.").
2. Rows: `settings.connect.server` → host (selectable); `common.onThisDevice` ("On This Device") → a summary: `common.journalCount` and `common.entryCount` always, then `common.templateCount` and `settings.connect.merge.recentlyDeleted` when non-zero, joined with “, ” (for example “3 journals, 42 entries, 2 templates, 3 recently deleted”).
3. Footer lines, in order:
   - `settings.connect.merge.footerKept`;
   - what happens to encryption, when it applies:
     - device not encrypted, server encrypted: `settings.connect.merge.footerWillEncrypt`;
     - both encrypted: `settings.connect.merge.footerSamePassword` ("Afterward, this device uses the same {serverCredential} as your other devices. Archives you exported earlier still open with the {deviceCredential} you use now.");
     - neither encrypted: `settings.connect.merge.footerUnencrypted`;
   - `settings.connect.merge.footerLeaveOut`;
   - `settings.connect.merge.footerOnlyIf` ("Merge only if {host} is your server.").
- Primary: `common.merge` ("Merge"), shortcut Command-Return (not Return); computer help `settings.connect.merge.help`, hint `settings.connect.merge.hint`. Disabled while working.
- Back is allowed. Going back from Merge Journals after a scanned code forgets the code (nothing was sent for it).

### Step: Finish on Your Other Device (after a scanned code)

Title `settings.connect.title` (the longer instruction is in the content, because a long title is cut off beside Cancel and Scan Again).

1. Row: `settings.connect.server` → host.
2. When there's no error: heading `settings.connect.finish.title` ("Finish on Your Other Device"), `settings.connect.finish.instructions` ("Choose Add Device on your connected device."), and a busy row `settings.connect.waitingForApproval` (or the installing label).
- Primary, only after a failure: `common.tryAgain` (installing failed after approval, or only the connection failed), otherwise `settings.connect.scanAgain`.

### Computer: notices in the journal window

While the computer connects to a server from the Settings window, the journal window shows a notice bar above the editor:
- after one second of connecting: `messages.writingPaused.connecting` ("Writing is paused while this Mac connects to your server.");
- when a connection failed and a copy waits for Try Again: `messages.writingPaused.connectionFailed`;
- with a button `messages.writingPaused.showConnection` ("Show Connection"), which brings the Settings window with the sheet to the front.

## Actions

| Action | Command | Notes |
| --- | --- | --- |
| Continue (address) | `connect-check-server` | Checks the typed address. |
| Choose a nearby server | `connect-check-server` | Fills the address and checks it. |
| Scan Code | `connect-scan-code` | Opens the scanner. |
| Set Up / Continue (setup code) | `connect-set-up` | Validates the code; checks it with the server. |
| Sign In | `connect-sign-in` | Signs in with the typed credential. |
| Use a Connected Device Instead… | `connect-use-device` | Pushes Add This Device. |
| Copy Code | `connect-copy-code` | Copies the nine digits only. |
| Connect (check code) | `connect-confirm-check-code` | Accepts the other device's approval. |
| Get New Code | `connect-new-code` | Withdraws the old request and asks for a new code. |
| Use a Recovery Code Instead… | `connect-use-recovery-code` | Pushes Use a Recovery Code. |
| Connect (recovery code) | `connect-sign-in` | Signs in with the recovery code. |
| Merge | `connect-merge` | Agrees to merge with this server; continues. |
| Try Again / Scan Again | `connect-retry` | See `flows/connect-to-server`. |
| Add Another Device… | `add-device` | Opens Add Device. |
| Cancel | `connect-cancel` | Stops what's running, withdraws a pairing request, gives up access received but not used, discards a staged copy, closes. |
| Done | `connect-done` | Closes after Server Is Ready. |
| Show Connection (computer) | `show-connection` | Brings Settings forward. |

## States

- **Locked:** page 1 shows `settings.connect.locked`. Locking while the sheet is open cancels everything (as Cancel) and closes it.
- **Checking / working:** fields and choices disabled; busy row; Cancel disabled while installing; the sheet can't be swiped away while installing.
- **Error:** shown on the step where the work started (see `flows/connect-to-server` for every message).
- **Reconnecting:** when this device's server needs Reconnect… (set up again, access lost or restored, or encryption turned on elsewhere), and the address is known, the sheet checks the server as soon as it opens and goes straight to its next step.
- **Computer inactivity:** while the sheet is waiting on the server or another device, My Journal doesn't lock for inactivity.

## Rules

- Searching for nearby servers runs only while page 1 is shown, unlocked and without a scanned code.
- **Servers without encryption.** A device with an encrypted library, or with no library, never sets up, joins or keeps a server whose recovery format is 3 or 4 (set up without encryption): the check on page 1, pairing and the scanned-code check refuse it with `messages.connection.encryptionOff` and nothing is sent. A device with an unencrypted library (one that chose Not Now in Encrypt Your Journals) keeps the earlier behaviour toward its own unencrypted server, including Add This Device and Use a Recovery Code for a server without encryption; the Encrypt Your Journals form then encrypts the server ([flows/encrypt-journals](../flows/encrypt-journals.md)). Those steps and their keys stay until Not Now is removed in a later release.
- Nearby servers are suggestions only: the address is checked exactly as a typed one. Only HTTPS announcements are listed, one row per address.
- The setup code field formats as the person types: letters are upper-cased, spaces and dashes are removed and the hyphen is inserted after three characters (`XXX-XXX`); the code is never submitted automatically.
- Field errors clear when the field changes. The two password fields' errors clear together.
- After a field error, focus moves to the field and the message is announced (after focus moves, so it isn't cut off).
- Steps take focus on their first field after the push transition.
- A password typed here never leaves the device; only a value derived from it is sent. A recovery code is sent as typed only if it has the recovery code's exact form (64 hexadecimal digits); anything else is refused without sending.
- Nothing is sent to a server for a device with journals until the person chose Merge on Merge Journals for that server.
- The server's encryption details seen when the server was chosen must still hold when connecting; otherwise the sheet returns to page 1 with `messages.connection.serverChanged`.

## Accessibility

- Nearby server rows read “{host}, {name}”.
- Each step's title is a heading; on the computer, before macOS 26, a heading row repeats the title at the top of the form because the sheet has no title bar; VoiceOver starts there on Merge Journals.
- Field errors are also the field's accessibility hint, so VoiceOver reads them with the field.
- The pairing code is labelled `settings.connect.addThisDevice.codeLabel` ("Pairing code") and its value read digit by digit; the check code is labelled `settings.connect.checkCode.label` ("Check code"), read digit by digit.
- When the check code appears, VoiceOver announces `settings.connect.checkCode.announcement` ("Check code {digits}. Connect only if your other device shows the same code."), except after a scanned code.
- Busy rows are read as one element.
- Merge and Connect use Command-Return so they can't be triggered by Return before reading.

## Platform notes (Apple)

- iPhone and iPad: a sheet with inline titles; Scan Code opens a full-screen camera (`screens/scan-code`). Scan Code appears only where the system's live text scanner is supported.
- Mac: a sheet on the Settings window (about 480 × 340 points), or on the journal window from the first-launch screen; no Scan Code (the Mac can't scan); the computer's local-network message names System Settings.
- The Tailscale hints appear for hosts ending in `.ts.net`.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
