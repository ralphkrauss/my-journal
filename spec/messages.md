---
id: messages
title: Messages
features: [sync-health, sync-status, sync-item-refusal, save-failure-recovery, writing-paused-notice, generic-error-alert, conflict-notice, changes-to-review-list, conflict-review-entry, conflict-review-journal, conflict-review-deletion, conflict-review-unsupported, library-open-failure, read-only-newer-content, unavailable-journals, privacy-cover, accessibility-announcements]
sources:
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncHealth.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Models.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/ServerClient.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncEngine.swift
  - apps/apple/JournalApp/Model/
  - apps/apple/JournalApp/Views/SaveFailureNotice.swift
  - apps/apple/JournalApp/Views/SyncNowRows.swift
  - apps/apple/JournalApp/Views/ConflictRouting.swift
  - apps/apple/JournalApp/Views/EntryConflictReview.swift
  - apps/apple/JournalApp/Views/JournalConflictView.swift
  - apps/apple/JournalApp/Views/DeletionConflictView.swift
---

# Messages

Every message that comes from the model layer rather than from one screen: sync states and their actions, server and network errors, every error type's description, save failures and paused writing, the generic alert, conflicts, unavailable and read-only content, the privacy cover, and accessibility announcements that aren't tied to one screen. The exact text of each key is in [copy/en.json](copy/en.json) (a message whose text another area also uses is keyed `common.*`); this page says when each appears, where, and what the person can do.

Related files: [screens/sync-status.md](screens/sync-status.md), [flows/sync-recovery.md](flows/sync-recovery.md), [flows/save-failure.md](flows/save-failure.md), [screens/conflict-review.md](screens/conflict-review.md), [flows/resolve-conflict.md](flows/resolve-conflict.md), [screens/unavailable-content.md](screens/unavailable-content.md).

## How messages reach the person

| Surface | What it shows | Rules |
| --- | --- | --- |
| **Settings ▸ Sync footer** | The current sync message, item refusal, save-paused note, or library note | One message at a time. Priority: `messages.sync.pausedForSaveFailure` (connected and a save failed), then the sync message, then the not-connected text, then `messages.library.needsUpdate` / `messages.library.waitingForServer`. |
| **Sync Status** | The same sync message, its action, and Sync Settings… | Only when the person must act, or after a long wait. See [screens/sync-status.md](screens/sync-status.md). |
| **Generic alert** | Title `common.alertTitle`, the message, `common.ok`, plus `common.tryAgain` while a save has failed | One per window. Never while locked or while the first journal is being created. Most "Couldn’t …", "Save your … before …", "… couldn’t be displayed" messages and any operation error without its own place go here. |
| **Lock screen note** | The same model error, in red, under "My Journal Is Locked" | Used instead of the generic alert while locked, and for launch failures. |
| **Sheet errors** | An operation's error inside its own sheet (Connect to a Server, Turn On Encryption, Change Password, Add Device, Move Entry, Change Date, Image Descriptions, the conflict reviews, exports) | Errors stay on the sheet that caused them, never in an alert behind it. |
| **Notices** | Save failure, writing paused (Mac), conflict, recovery and unavailable notices in the entry | Persistent while the state lasts, with their single action. |
| **Announcements** | VoiceOver announcements | Only for results of actions the person started, and for errors appearing in an open sheet. |

**Wording rules** (from AGENTS.md and the sync-health record): plain language; say what happened and what to do; "the server" rather than its address, except where the person confirms something about a specific server; local saving is distinguished from syncing ("Your changes are saved on this device."); no status codes, SQL, error domains or the word "request"; actions that open a flow end in "…"; no exclamation marks.

**Shared keys used here** (defined in the common catalog, not here): `common.ok`, `common.cancel`, `common.done`, `common.tryAgain`.

## Catalog

"Notes": *unreachable* means the text exists in code but can't be shown; *overridden* means the UI shows another key in its place; *rare* means only a guard or a race leads to it; *legacy archive* means it describes entries archived by older versions; *shared with permanent deletion* means the same text is part of the Delete Permanently confirmation.

### Sync states

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.sync.offline` | You’re offline. Your changes are saved on this device and will sync when you’re back online. | Sync state Temporary (offline): the last sync failed because this device has no network connection. | Settings ▸ Sync footer; Sync Status menu only after a long wait | common.tryAgain |  |
| `messages.sync.unreachable` | Can’t reach the server right now. Your changes are saved on this device and will sync automatically. | Sync state Temporary (can’t reach): the server refused the connection, timed out, the connection was lost, or its name didn’t resolve. | Settings ▸ Sync footer; Sync Status menu only after a long wait | common.tryAgain |  |
| `messages.sync.unreachableTailscale` | Can’t reach the server right now. If it uses Tailscale, turn on Tailscale on this device. Your changes are saved on this device and will sync automatically. | As messages.sync.unreachable, when the server’s host name ends in “.ts.net”. | Settings ▸ Sync footer; Sync Status menu only after a long wait | common.tryAgain |  |
| `messages.sync.unavailable` | The server isn’t available right now. Your changes are saved on this device and will sync automatically. | Sync state Temporary (busy): the server answered with a server error (5xx), asked this device to slow down (429), or sent an answer that couldn’t be parsed. | Settings ▸ Sync footer; Sync Status menu only after a long wait | common.tryAgain |  |
| `messages.sync.signInNeeded` | The server now uses encryption or was replaced. Sign in to keep syncing. | Sync state Needs you: this device was refused and the server’s identity changed to an encrypted library while this library isn’t encrypted (encryption turned on from another device, or the server replaced). Automatic sync stops. | Settings ▸ Sync footer; Sync Status menu | common.signIn |  |
| `messages.sync.serverNotSetUp` | The server isn’t set up. Your journals are still on this device. | Sync state Server changed (not set up): the server was reset and waits for a setup code. Automatic sync stops. | Settings ▸ Sync footer; Sync Status menu | messages.sync.action.setUpServerAgain |  |
| `messages.sync.serverReplaced` | The server was restored or replaced and doesn’t recognize this device. Your journals are still on this device. | Sync state Server changed (restored or replaced): this device was refused and the server now has a different identity. Automatic sync stops. | Settings ▸ Sync footer; Sync Status menu; Settings ▸ Devices | messages.sync.action.connectAgain |  |
| `messages.sync.accessRemoved` | This device no longer has access to the server. Your journals are still on this device. | Sync state No access: the same server refuses this device (removed in Devices, or its credential stopped working). Automatic sync stops. Also Settings ▸ Devices’ text when loading devices is refused. | Settings ▸ Sync footer; Sync Status menu; Settings ▸ Devices | messages.sync.action.connectAgain |  |
| `messages.sync.appUpdateNeeded` | Update My Journal to sync with this server. Your changes are saved on this device. | Sync state Update or fix needed (update My Journal): the server speaks a newer protocol or recovery format, or the data needs a newer app. Automatic sync stops. | Settings ▸ Sync footer; Sync Status menu | messages.sync.action.checkAgain |  |
| `messages.sync.serverUpdateNeeded` | The server needs an update before this device can sync. Your changes are saved on this device. | Sync state Update or fix needed (server): the server lacks an endpoint this app needs (404 or 405 on a sync request). Checked again every 5 minutes. | Settings ▸ Sync footer; Sync Status menu | messages.sync.action.checkAgain |  |
| `messages.sync.certificateInvalid` | Can’t connect securely to the server because its certificate isn’t valid. Your changes are saved on this device. | Sync state Update or fix needed (certificate): no secure connection could be made or the certificate isn’t trusted, expired or not yet valid. Checked again every 5 minutes. | Settings ▸ Sync footer; Sync Status menu | messages.sync.action.checkAgain |  |
| `messages.sync.notJournalServer` | The server address doesn’t lead to a My Journal server. Your changes are saved on this device. | Sync state Update or fix needed (not a journal server): the address answers, but its status isn’t a My Journal status (for example a web page or a captive portal). Checked again every 5 minutes. | Settings ▸ Sync footer; Sync Status menu | messages.sync.action.checkAgain |  |
| `messages.sync.localDataUnreadable` | My Journal couldn’t read its data on this device. Your journals haven’t been changed. To keep a copy, choose Export Archive in Settings > Backup. | Sync state Unexpected (this device’s data): this device’s own store couldn’t be read or written during a sync. Retries continue with the usual backoff. | Settings ▸ Sync footer; Sync Status menu | common.tryAgain |  |
| `messages.sync.unexpected` | Couldn’t sync because of an unexpected problem. Your changes are saved on this device. | Sync state Unexpected: any other sync failure. Retries continue with the usual backoff. | Settings ▸ Sync footer; Sync Status menu | common.tryAgain |  |
| `messages.sync.waiting` | Saved on this device. Waiting to sync. | Sync Status’s message when it shows but no sync message is held. Only after the app locked and unlocked while a state that needs the person persists, until the next sync (the lock clears the message, not the state). | Sync Status menu | the state’s action | rare |
| `messages.sync.pausedForSaveFailure` | Syncing is paused until your changes are saved. Choose Try Again in the entry. | Settings ▸ Sync footer while connected and the open entry’s save has failed. Takes priority over every other footer message; Sync Now is dimmed. | Settings ▸ Sync footer | none here; Try Again in the entry |  |
| `messages.sync.recordTooLarge` | “{title}” is too large to sync. It’s saved on this device. Shorten it or split it into separate entries. | One entry, journal or template is larger than the server accepts; the rest syncs. {title} is the item’s title, cut to 40 characters with “…”. | Settings ▸ Sync footer; Sync Status menu | messages.sync.action.syncNow (sends it again) |  |
| `messages.sync.recordRefused` | Your server didn’t accept “{title}”. It’s saved on this device. Edit it to try again. | The server refused one record as invalid, or its push failed with a server error 3 times in a row while other requests succeeded; the rest syncs. | Settings ▸ Sync footer; Sync Status menu | messages.sync.action.syncNow (sends it again) |  |
| `messages.sync.imageTooLarge` | An image is too large for your server. Entries that include it are saved on this device. | The server refused an image as too large (413); entries that include it wait, the rest syncs. | Settings ▸ Sync footer; Sync Status menu | messages.sync.action.syncNow |  |
| `messages.sync.imageRefused` | Your server didn’t accept an image. Entries that include it are saved on this device. | The server refused an image as invalid; entries that include it wait, the rest syncs. | Settings ▸ Sync footer; Sync Status menu | messages.sync.action.syncNow |  |
| `messages.sync.action.syncNow` | Sync Now | The single action while syncing normally, or when only one record or image was refused. | Settings ▸ Sync; Sync Status menu |  |  |
| `messages.sync.action.checkAgain` | Check Again | The single action for Update or fix needed: runs a full sync now. | Settings ▸ Sync; Sync Status menu |  |  |
| `messages.sync.action.setUpServerAgain` | Set Up Server Again… | The single action when the server isn’t set up: opens Connect to a Server at this device’s server, which goes to the setup-code step. | Settings ▸ Sync; Sync Status menu |  |  |
| `messages.sync.action.connectAgain` | Connect Again… | The single action when the server was restored or replaced, or this device lost access: opens Connect to a Server at this device’s server, which goes to sign-in. | Settings ▸ Sync; Sync Status menu; Settings ▸ Devices |  |  |
| `common.signIn` | Sign In… | The single action for Needs you: opens Connect to a Server at this device’s server, which signs in straight away. | Settings ▸ Sync; Sync Status menu; Settings ▸ Privacy ▸ Encryption |  |  |
| `messages.sync.announce.synced` | Synced | VoiceOver announcement after Sync Now, Try Again or Check Again finishes with a successful sync and no item-level message. | announcement |  |  |
| `messages.sync.announce.failed` | Couldn’t sync. | VoiceOver announcement after a sync the person started didn’t succeed and no message explains it (for example it was cancelled). | announcement |  |  |

### Sync Status

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.syncStatus.title` | Sync Status | The Sync Status control’s label, help tag and accessibility label (Mac toolbar button and overflow item; iPhone and iPad submenu of the entry’s … menu). | Sync Status |  |  |
| `messages.syncStatus.settings` | Sync Settings… | Last item of the Sync Status menu: opens Settings at Sync. | Sync Status menu |  |  |

### Library record (pins and journal order)

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.library.needsUpdate` | Update My Journal to use pinned entries and journal order. | Settings ▸ Sync footer while connected, when the synced library record (pins and journal order) was written by a newer version. Same text as the LibraryError.newerVersion description, which itself is never shown (pin and move failures show their own text). | Settings ▸ Sync footer |  |  |
| `messages.library.waitingForServer` | Pinned entries and journal order stay on this device until the server is updated. | Settings ▸ Sync footer while connected, when the server can’t store the library record and this device has changes to it. | Settings ▸ Sync footer |  |  |
| `messages.library.itemUnavailable` | This item is no longer available. | LibraryError.unavailable. Never shown: pinning and moving journals show messages.generic.pinFailed / unpinFailed / moveJournalFailed instead. | none |  | unreachable |

### Server and network errors outside sync

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.server.unavailable` | The server isn’t available right now. Try again in a moment. | ServerUnavailable (any 5xx) outside sync: connecting, pairing, setting up a server, Devices, Agent Access. In sync it becomes messages.sync.unavailable. | Connect to a Server; Add Device; other server requests | common.tryAgain where the screen offers it |  |
| `messages.server.unanswered` | Couldn’t reach the server. Check the address and your connection, then try again. | A request the server answered with an unexpected status (not 5xx) that nothing more specific explains, outside sync. | Connect to a Server; Add Device; other server requests |  |  |
| `messages.server.rateLimited` | Too many attempts. Try again in a few minutes. | ServerRateLimited (429) where the screen has no more specific text. In sync it becomes messages.sync.unavailable. | server requests outside sync |  |  |
| `messages.server.responseTooLarge` | The server sent more data than expected. | A response larger than the client reads (a faulty server). In sync it becomes messages.sync.unexpected. | server requests outside sync |  |  |
| `messages.server.noSetupCode` | The server has no setup code. Restart the server to create a new one. | Setting up a server: the server answered 503 to the setup or setup-check request. | Connect to a Server ▸ Set Up Server |  |  |
| `messages.server.updateForRecoveryFormat` | Update your server before connecting this journal. | Setting up a server with a library whose recovery format the server doesn’t list as supported. | Connect to a Server ▸ Set Up Server |  |  |
| `messages.server.syncRequestFailed` | Couldn’t sync. Your changes are saved on this device. | A sync request answered with an unexplained 4xx. Never shown as is: sync classifies it as messages.sync.unexpected, and for one record it is retried per item. | none |  | unreachable |
| `messages.server.imageUploadFailed` | Couldn’t upload an image. Try again. | An image upload answered with an unexpected status. Never shown: the image is retried on its own. | none |  | unreachable |
| `messages.server.imageUnavailable` | Image unavailable. | An image download that didn’t answer 200. Never shown: the image is retried on its own. | none |  | unreachable |
| `messages.server.revokeFailed` | Couldn’t revoke this device. | Revoking a device didn’t answer 204. Never shown: Devices shows its own “Couldn’t revoke access…” text and every other caller ignores the failure. | none |  | unreachable |
| `messages.server.cancelPairingFailed` | Couldn’t cancel pairing. | Cancelling a pairing request failed. Never shown: every caller ignores the failure. | none |  | unreachable |

### JournalError

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.error.unsupportedFormat` | Update My Journal to edit this entry. | JournalError.unsupportedFormat: content or a recovery format from a newer version. Also the read-only note under the title of an entry from a newer version (same text). Where an operation fails with it, it appears in that operation’s sheet or the generic alert. | entry editor note; generic alert; sheet errors |  |  |
| `messages.error.newerVersion` | These journals were saved by a newer version of My Journal. Update My Journal to open them. | JournalError.newerVersion: the library’s database was migrated by a newer version. Shown at launch on the lock screen; nothing can be opened or changed. | lock screen (launch) | none |  |
| `messages.error.invalidData` | This data couldn’t be read. | JournalError.invalidData: a record, archive or server answer that can’t be decoded, where an operation reports its error directly (archive import, connecting). In sync it becomes messages.sync.unexpected. | sheet errors; generic alert |  |  |
| `messages.error.invalidRecoveryKey` | That password or recovery key couldn’t unlock your journals. | JournalError.invalidRecoveryKey where no more specific text applies: unlocking with the password or recovery key on the lock screen, importing an archive. | lock screen; Import Archive |  |  |
| `messages.error.locked` | Unlock My Journal to continue. | JournalError.locked: an operation found the journals locked or being replaced. Usually suppressed because the lock closes the sheet; may appear in a sheet’s error if the lock and the error race. | sheet errors (rare) |  | rare |
| `messages.error.unauthorized` | This device no longer has access. | JournalError.unauthorized outside sync and Devices, for example in Add Device, Change Password or Agent Access. In sync it becomes messages.sync.accessRemoved. | server screens outside sync |  |  |
| `messages.error.invalidAddress` | Enter a valid HTTPS server address. | JournalError.invalidAddress: the server address typed isn’t a valid HTTPS address. | Connect to a Server |  |  |
| `messages.error.invalidSetupCode` | That setup code isn’t valid. Check it and try again. | JournalError.invalidSetupCode where the connection flow doesn’t override it. In Connect to a Server it shows as messages.connection.setupCodeIncorrect instead. | none in the Apple app |  | overridden |

### Connecting to a server

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.connection.serverChanged` | This server has changed since you checked it. Choose Continue to check it again. | ServerConnectionError.serverChanged: the server’s recovery envelope changed between checking it and signing in, setting up or finishing a pairing. The flow returns to the address step. | Connect to a Server | Continue (address step) |  |
| `messages.connection.encryptionOff` | Encryption is off for this server, so it can’t store your encrypted journals. Connect to a server that uses encryption. | ServerConnectionError.encryptionOff, shown as is only when finishing a pairing. Checking the address shows messages.connection.encryptionOffOnHost instead. | Connect to a Server (finishing Add This Device) |  |  |
| `messages.connection.invalidRecoveryCode` | That recovery code isn’t valid. Check it and try again. | ServerConnectionError.invalidRecoveryCode. Never shown: signing in shows messages.connection.recoveryCodeIncorrect instead. | none |  | overridden |
| `messages.connection.encryptionOffOnHost` | The journals on this device are encrypted, but {host} doesn’t use encryption. Turn on encryption in Settings > Privacy on a connected device, then try again. | Connect to a Server, checking an address whose server stores journals without encryption while this library is encrypted. | Connect to a Server |  |  |
| `messages.connection.cannotConnect` | Couldn’t connect to the server. Check your connection and try again. | Connect to a Server: a network error (no connection, refused, timed out, not found, certificate). | Connect to a Server |  |  |
| `messages.connection.cannotConnectTailscale` | Couldn’t connect to the server. If it uses Tailscale, turn on Tailscale on this device and try again. | As messages.connection.cannotConnect for a “.ts.net” host. | Connect to a Server |  |  |
| `messages.connection.notJournalServer` | This address doesn’t lead to a My Journal server. Check it and try again. | Connect to a Server: the address answers, but not as a journal server. | Connect to a Server |  |  |
| `messages.connection.pairingDeclined` | Your connected device didn’t add this one. | Adding this device with a scanned code: the connected device declined. | Connect to a Server |  |  |
| `messages.connection.pairingExpired` | This code has expired. Show a new code on your connected device. | Adding this device with a scanned code: the code expired. | Connect to a Server |  |  |
| `messages.connection.pairingInsecure` | Couldn’t add this device securely. Show a new code on your connected device and try again. | Adding this device with a scanned code: the received grant failed its security check. | Connect to a Server |  |  |
| `messages.connection.mergeFailed` | Couldn’t finish connecting. Your journals are still on this device. Try again, or cancel to keep writing. | Merging this device’s journals with the server stopped before anything was sent. | Connect to a Server | common.tryAgain, common.cancel |  |
| `messages.connection.mergeFailedSent` | Couldn’t finish connecting. Your journals are still on this device, and some may already be on {host}. Try again, or cancel to keep writing. | Merging stopped after sending had started. | Connect to a Server | common.tryAgain, common.cancel |  |
| `messages.connection.finishFailed` | Couldn’t finish connecting. | Finishing Add This Device failed on a device with no library. | Connect to a Server |  |  |
| `messages.connection.finishFailedRetry` | Couldn’t finish connecting. Your local journals remain on this device. Try again, or cancel to keep writing. | Finishing Add This Device failed while a staged copy waits for Try Again (writing is paused). | Connect to a Server | common.tryAgain, common.cancel |  |
| `messages.connection.finishFailedLocal` | Couldn’t finish connecting. Your local journals remain on this device. | Finishing Add This Device failed otherwise. | Connect to a Server |  |  |
| `messages.connection.setupFailedSaved` | Your journal is saved on this device, but the server couldn’t be set up. {message} | Setting up a server from a device that just created its first journal in the same flow; {message} is the failure’s own message. | Connect to a Server |  |  |
| `messages.connection.setUpElsewhere` | This server has just been set up. Choose it again to sign in. | Setting up failed because another device set the server up meanwhile; the flow returns to the address. | Connect to a Server |  |  |
| `messages.connection.setupCodeIncorrect` | That setup code isn’t correct. Check the code on your server. | Set Up Server: the server refused the setup code. | Connect to a Server ▸ setup code field |  |  |
| `messages.connection.setupCodeRateLimited` | Too many incorrect codes. Try again in a few minutes. | Set Up Server: the server rate-limited setup codes. | Connect to a Server ▸ setup code field |  |  |
| `messages.connection.setupCodeLength` | Enter the 6-character setup code from your server. | Set Up Server: the typed code doesn’t have 6 characters. | Connect to a Server ▸ setup code field |  |  |
| `messages.connection.setupCodeCharacters` | Setup codes use letters and the digits 2–9, without I or O. | Set Up Server: the typed code has characters a setup code never uses. | Connect to a Server ▸ setup code field |  |  |
| `messages.connection.passwordsDontMatch` | The passwords don’t match. | Choosing a master password while setting up a server: the two fields differ. (Turn On Encryption uses the same text.) | Connect to a Server; Turn On Encryption |  |  |
| `messages.connection.credentialIncorrect` | That {credential} isn’t correct. | Signing in or setting up with an existing password: the credential is wrong. {credential} is “password” for any kind of password, or “recovery key” / “recovery code”. | Connect to a Server ▸ credential field |  |  |
| `messages.connection.recoveryCodeIncorrect` | That recovery code isn’t correct or has already been used. | Signing in with a server’s one-time recovery code: wrong, already used, or not a recovery code at all. | Connect to a Server ▸ credential field |  |  |
| `messages.connection.credentialRateLimited` | Too many {credential} attempts on this server. Try again in a few minutes, or use a connected device. | Signing in: the server rate-limited attempts. {credential} as in messages.connection.credentialIncorrect. | Connect to a Server ▸ credential field |  |  |
| `messages.connection.createFailed` | Couldn’t create your journal. Try again. | Setting up a server from a device with no library, when creating the library failed without its own message. | Connect to a Server |  |  |
| `messages.connection.updateApp` | Update My Journal to connect to this server. | Connect to a Server: the server speaks a newer protocol, or a scanned pairing needs a newer app. | Connect to a Server |  |  |
| `messages.connection.serverNeedsUpdateForDevices` | This server needs an update before you can add devices this way. | Adding this device with a scanned code to a server without check-code pairing. | Connect to a Server |  |  |
| `messages.connection.saveBeforeConnecting` | Save your changes before connecting. | Connecting, setting up or signing in while the open entry couldn’t be saved. | Connect to a Server |  |  |
| `messages.connection.chooseUpload` | Choose whether to upload your local journals before connecting. | Connecting a library with journals before Merge Journals was agreed (a guard; the flow asks first). | Connect to a Server |  | rare |
| `messages.connection.createJournalFirst` | Create a journal before setting up your server. | Setting up a server with no library (a guard; the flow creates one first). | Connect to a Server |  | rare |
| `messages.connection.alreadyHasJournals` | This device already has journals. | Joining as an empty device after journals were written meanwhile. | Connect to a Server |  | rare |
| `messages.connection.alreadyConnecting` | A connection is already being set up. | Starting a second connection while one is being set up. | Connect to a Server |  | rare |
| `messages.connection.reconnectSameServer` | Reconnect to the same server to keep your journals together. | Connecting to another address while this device is connected. (To move servers: Stop Syncing, then connect.) | Connect to a Server |  |  |
| `messages.connection.alreadyConnected` | This device is already connected to this server. | Connecting again to the server this device is connected to, when nothing needs repairing. | Connect to a Server |  |  |
| `messages.connection.connectedNotDisplayed` | The server is connected, but your journals couldn’t be displayed. Reopen My Journal to try again. | Joining succeeded but reading the journals for display failed. | generic alert | common.ok |  |

### Pairing

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.pairing.serverOutdated` | This server needs an update before you can add devices. | PairingError.serverOutdated: the server doesn’t support check-code pairing. | Add Device; Connect to a Server |  |  |
| `messages.pairing.deviceOutdated` | Update My Journal on the new device, then try again. | PairingError.deviceOutdated: the new device runs an older version. | Add Device |  |  |
| `messages.pairing.insecureCandidate` | Couldn’t add this device securely. Get a new code on the new device and try again. | PairingError.insecureCandidate: the new device’s key failed its check. | Add Device |  |  |
| `messages.pairing.insecureGrant` | Couldn’t add this device securely. Get a new code and try again. | PairingError.insecureGrant, typed-code path (a scanned code shows messages.connection.pairingInsecure). | Connect to a Server |  |  |
| `messages.pairing.declined` | Your other device didn’t approve this request. | PairingError.declined, typed-code path (a scanned code shows messages.connection.pairingDeclined). | Connect to a Server |  |  |
| `messages.pairing.expired` | This pairing code has expired. | PairingError.expired, typed-code path (a scanned code shows messages.connection.pairingExpired). | Connect to a Server; Add Device |  |  |
| `messages.pairing.codeNotFound` | That pairing code wasn’t found. Check the code and try again. | PairingError.codeNotFound. | Add Device |  |  |
| `messages.pairing.inviteUsed` | This code was already used. Show a new code on your other device. | PairingError.inviteUsed: a scanned code was used before. | Connect to a Server |  |  |
| `messages.pairing.noResponse` | {name} didn’t respond. Get a new code on the new device and try again. | PairingError.noResponse: the new device stopped answering. {name} is that device’s name. | Add Device |  |  |
| `messages.pairing.inviteNewerVersion` | Update My Journal to use this code. | PairingInvite.ReadError.newerVersion: a scanned code from a newer version. | Scan Code |  |  |
| `messages.pairing.inviteUnreachable` | This code points to a server this device can’t reach. | PairingInvite.ReadError.unreachableServer: the code’s server address isn’t HTTPS. | Scan Code |  |  |

### Password change

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.password.incorrect` | The current password is incorrect. | PasswordChangeError.incorrectPassword. | Change Password |  |  |
| `messages.password.same` | Choose a password that’s different from your current password. | PasswordChangeError.samePassword. | Change Password |  |  |
| `messages.password.empty` | Enter a new password. | PasswordChangeError.tooShort (an empty new password). | Change Password |  |  |
| `messages.password.unsupported` | This journal library doesn’t use a master password. | PasswordChangeError.unsupported. | Change Password |  |  |
| `messages.password.serverOutdated` | This server needs an update before you can change your password. | PasswordChangeError.serverOutdated. | Change Password |  |  |
| `messages.password.failed` | Couldn’t change your password. Your current password still works. Check your connection and try again. | PasswordChangeError.failed. | Change Password |  |  |
| `messages.password.notSavedLocally` | Your password was changed on your server but not on this device. Try again to finish. | PasswordChangeError.notSavedLocally. | Change Password | common.tryAgain |  |
| `messages.password.enterMaster` | Enter a master password. | Creating an encrypted library without a password (a guard). | first launch |  | rare |

### Turn On Encryption

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.encryption.turnedOnElsewhere` | Encryption was turned on from another device. Sign in to keep syncing. | Settings ▸ Privacy ▸ Encryption footer while sign-in is offered, and Turn On Encryption’s error when the server switched to encryption meanwhile. Sync itself says messages.sync.signInNeeded. | Settings ▸ Privacy; Turn On Encryption | common.signIn |  |
| `messages.encryption.incorrectPassword` | That password isn’t correct. | Turn On Encryption, current server password field. | Turn On Encryption |  |  |
| `messages.encryption.rateLimited` | Too many password attempts on this server. Try again in a few minutes. | Turn On Encryption, current server password field. | Turn On Encryption |  |  |
| `common.couldntReachHost` | Couldn’t reach {host}. Check your connection and try again. | Turn On Encryption on its first step. | Turn On Encryption |  |  |
| `messages.encryption.unreachable` | Couldn’t reach {host}. Encryption wasn’t turned on. Check your connection and try again. | Turn On Encryption after its first step. | Turn On Encryption |  |  |
| `messages.encryption.serverOutdated` | {host} needs an update before you can turn on encryption. | Turn On Encryption: the server lacks encryption support; {host} is the host name with its first letter capitalized. | Turn On Encryption |  |  |
| `messages.encryption.notEnoughSpace` | There isn’t enough space to encrypt your journals. Free up {size} and try again. | Turn On Encryption; {size} is a file size such as “120 MB”. | Turn On Encryption |  |  |
| `messages.encryption.accessLost` | This device no longer has access to {host}. Connect again in Settings > Devices, then try again. | Turn On Encryption: the server refused this device. | Turn On Encryption |  |  |
| `messages.encryption.stillSyncing` | Your other devices are still syncing. Wait for them to finish, then try again. | Turn On Encryption: other devices’ changes are still arriving, or the server changed meanwhile. | Turn On Encryption |  |  |
| `messages.encryption.imagesMissing` | Some images haven’t downloaded to this device yet. Keep My Journal open for a moment, then try again. | Turn On Encryption. | Turn On Encryption |  |  |
| `messages.encryption.unfinished` | Your journals are encrypted on {host}, but this device couldn’t finish. Free up space, then try again. | Turn On Encryption: the server was updated but this device couldn’t re-encrypt its copy. | Turn On Encryption | common.tryAgain |  |
| `messages.encryption.failed` | Encryption wasn’t turned on. Your journals are unchanged. | Turn On Encryption: any other failure. | Turn On Encryption |  |  |
| `messages.encryption.background` | Encryption stopped because My Journal was in the background. Keep My Journal open and try again. | Turn On Encryption on iPhone and iPad when background time ran out. | Turn On Encryption |  |  |
| `messages.encryption.announce.turningOn` | Turning on encryption | VoiceOver announcement when encryption starts. | announcement |  |  |
| `messages.encryption.announce.updatingServer` | Updating {host}. You can’t stop this now. | VoiceOver announcement when the server update starts. | announcement |  |  |
| `messages.encryption.announce.done` | Your journals are encrypted. | VoiceOver announcement when encryption finished. | announcement |  |  |

### Generic alert

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `common.alertTitle` | Journal | Title of the generic alert that shows model errors (save failures and every “Couldn’t …” or “Save your … before …” message routed to the window). Not shown while locked; the lock screen shows the message instead. | generic alert | common.ok; common.tryAgain while a save has failed |  |

### Save failures

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `common.saveFailed` | Couldn’t save “{title}”. Keep it open and try again. | The open entry or template couldn’t be written to this device. {title} is its display title. Shown again after each failed attempt (typing, Try Again, navigating away). | generic alert | common.tryAgain, common.ok |  |
| `common.saveFailedLocked` | Couldn’t save your changes. Unlock My Journal to try again. | The save after locking failed; the lock screen shows this without naming the entry. | lock screen | unlock, then Try Again in the entry |  |
| `messages.save.notSaved` | Not Saved | The save-failure notice’s status, in red, while saving has failed: first in the entry’s header on iPhone and iPad, below the editor on the Mac. | entry editor (save-failure notice) | common.tryAgain |  |
| `messages.save.saving` | Saving… | Progress label in the save-failure notice while Try Again runs. | save-failure notice |  |  |
| `messages.save.mac.title` | Couldn’t save changes on this Mac. | Mac only: closing the journal window or quitting while the open entry can’t be saved. The window stays open and quitting is cancelled. | Mac app-modal alert | messages.save.mac.keepOpen |  |
| `messages.save.mac.message` | Keep this window open and try again, so your changes aren’t lost. | Message of messages.save.mac.title. | Mac app-modal alert |  |  |
| `messages.save.mac.keepOpen` | Keep Open | Only button of messages.save.mac.title. | Mac app-modal alert |  |  |
| `common.saveBeforeMoveEntry` | Save your changes before moving this entry. | Shown when Move Entry, or Restore and Move… is attempted while the open entry can’t be saved (its save failed). Nothing else happens. | that operation’s sheet error, or the generic alert | save the entry (Try Again), then repeat |  |
| `messages.save.before.reviewEntry` | Save your changes before reviewing this entry. | Shown when reviewing an entry’s restoration is attempted while the open entry can’t be saved (its save failed). Nothing else happens. | that operation’s sheet error, or the generic alert | save the entry (Try Again), then repeat |  |
| `messages.save.before.restoreEntry` | Save your changes before restoring this entry. | Shown when restoring an entry from Recently Deleted is attempted while the open entry can’t be saved (its save failed). Nothing else happens. | that operation’s sheet error, or the generic alert | save the entry (Try Again), then repeat |  |
| `messages.save.before.restoreTemplate` | Save your changes before restoring this template. | Shown when restoring a template from Recently Deleted is attempted while the open entry can’t be saved (its save failed). Nothing else happens. | that operation’s sheet error, or the generic alert | save the entry (Try Again), then repeat |  |
| `messages.save.before.exportMarkdown` | Save your changes before exporting your journals. | Shown when Export as Markdown is attempted while the open entry can’t be saved (its save failed). Nothing else happens. | that operation’s sheet error, or the generic alert | save the entry (Try Again), then repeat |  |
| `messages.save.before.exportArchive` | Save your changes before exporting an archive. | Shown when Export Archive is attempted while the open entry can’t be saved (its save failed). Nothing else happens. | that operation’s sheet error, or the generic alert | save the entry (Try Again), then repeat |  |
| `messages.save.before.importArchive` | Save your changes before importing journals. | Shown when Import Archive is attempted while the open entry can’t be saved (its save failed). Nothing else happens. | that operation’s sheet error, or the generic alert | save the entry (Try Again), then repeat |  |
| `messages.save.before.reviewChanges` | Save your entry before reviewing these changes. | Shown when resolving a journal or deletion conflict is attempted while the open entry can’t be saved (its save failed). Nothing else happens. | that operation’s sheet error, or the generic alert | save the entry (Try Again), then repeat |  |
| `messages.save.before.deleteJournal` | Save your entry before deleting this journal. | Shown when Delete Journal is attempted while the open entry can’t be saved (its save failed). Nothing else happens. | that operation’s sheet error, or the generic alert | save the entry (Try Again), then repeat |  |
| `messages.save.before.restoreJournal` | Save your entry before restoring this journal. | Shown when Restore Journal is attempted while the open entry can’t be saved (its save failed). Nothing else happens. | that operation’s sheet error, or the generic alert | save the entry (Try Again), then repeat |  |
| `messages.save.before.mergeJournal` | Save your entry before merging this journal. | Shown when Merge Into… is attempted while the open entry can’t be saved (its save failed). Nothing else happens. | that operation’s sheet error, or the generic alert | save the entry (Try Again), then repeat |  |
| `common.saveBeforeCreateJournal` | Save your entry before creating a journal. | Shown when creating a journal from a sheet is attempted while the open entry can’t be saved (its save failed). Nothing else happens. | that operation’s sheet error, or the generic alert | save the entry (Try Again), then repeat |  |
| `messages.save.before.restoreVersion` | Save your current entry before restoring a version. | Shown when Version History ▸ restore is attempted while the open entry can’t be saved (its save failed). Nothing else happens. | that operation’s sheet error, or the generic alert | save the entry (Try Again), then repeat |  |
| `messages.save.before.restoreJournalSettings` | Save your current entry before restoring journal settings. | Shown when journal Version History ▸ restore is attempted while the open entry can’t be saved (its save failed). Nothing else happens. | that operation’s sheet error, or the generic alert | save the entry (Try Again), then repeat |  |
| `messages.save.before.exportArchiveForConflict` | Save your entry before exporting the archive. | Shown when the unsupported journal conflict, under Export Archive…, while a save has failed is attempted while the open entry can’t be saved (its save failed). Nothing else happens. | that operation’s sheet error, or the generic alert | save the entry (Try Again), then repeat |  |
| `messages.save.before.openRestoredJournal` | The journal has already been restored. Save your entry before opening it. | Shown when Restore Journal when another device already restored it and the open entry can’t be saved is attempted while the open entry can’t be saved (its save failed). Nothing else happens. | that operation’s sheet error, or the generic alert | save the entry (Try Again), then repeat |  |
| `messages.save.before.resolveEntryConflict` | Your latest changes couldn’t be saved. Try again. | Keep Both or Keep Version in an entry conflict when the open entry’s pending save fails first. | Review Changes (entry) error | the same button again |  |
| `messages.save.before.changeDate` | Your entry has unsaved changes. Close this sheet and save your entry before changing its date. | EntryDateError.saveRequired: Change Date while the entry’s save hasn’t settled. | Change Date sheet |  |  |
| `messages.save.before.imageDescriptions` | Copy your descriptions, then close this view and save your entry before trying again. | ImageDescriptionError.entrySaveRequired: saving image descriptions while the entry’s save hasn’t settled. | Image Descriptions sheet |  |  |

### Writing paused

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.writingPaused.connecting` | Writing is paused while this Mac connects to your server. | Mac journal window, above the editor, while Connect to a Server (in the Settings window) replaces the library; appears after 1 second so a quick connection doesn’t flash it. | Mac journal window notice | messages.writingPaused.showConnection |  |
| `messages.writingPaused.connectionFailed` | This Mac couldn’t finish connecting to your server. Try again, or cancel to keep writing. | Mac journal window while a failed connection’s staged copy waits for Try Again or Cancel in the connection sheet. | Mac journal window notice | messages.writingPaused.showConnection |  |
| `messages.writingPaused.showConnection` | Show Connection | Brings the Settings window with the connection sheet forward. | Mac journal window notice |  |  |
| `messages.writingPaused.encrypting` | Writing is paused while this Mac encrypts your journals. | Mac journal window while Turn On Encryption (in Settings) re-encrypts the library. | Mac journal window notice | messages.writingPaused.showProgress |  |
| `messages.writingPaused.encryptionUnfinished` | Your journals are encrypted on {host}, but this Mac couldn’t finish. Free up space, then try again. | Mac journal window when the server was encrypted but this Mac’s copy wasn’t finished. | Mac journal window notice | messages.writingPaused.showProgress |  |
| `messages.writingPaused.showProgress` | Show Progress | Opens Turn On Encryption’s progress. | Mac journal window notice |  |  |
| `messages.writingPaused.updating` | My Journal is updating your journals. Try again when it’s finished. | Opening an archive (from Finder or Files) while connecting or turning on encryption replaces the library. | generic alert | common.ok |  |

### Library can’t be opened

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.library.deviceKeyUnavailable` | Your device key is unavailable. Use your recovery key to unlock your journals. | Launch or unlock: the key that opens the journals isn’t in this device’s keychain (for example after restoring a device backup). The lock screen asks for the password or recovery key. | lock screen | unlock with the credential |  |
| `messages.library.cannotOpen` | Your journals couldn’t be opened. Quit and reopen My Journal. | Unlocking when the journals were never opened (opening the store failed at launch) and no other message is shown. | lock screen | none |  |

### Saved, but not displayed

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.refresh.encryptionOn` | Encryption is on, but your journals couldn’t be displayed. Reopen My Journal to try again. | The change was committed when turning on encryption finished, but reading the journals again for display failed. | generic alert, or the operation’s sheet | common.ok |  |
| `messages.refresh.imported` | Your journals were imported, but couldn’t be displayed. Reopen My Journal to try again. | The change was committed when importing an archive finished, but reading the journals again for display failed. | generic alert, or the operation’s sheet | common.ok |  |
| `messages.refresh.templateRestored` | The template was restored, but couldn’t be displayed. Reopen My Journal to try again. | The change was committed when restoring a template finished, but reading the journals again for display failed. | generic alert, or the operation’s sheet | common.ok |  |
| `common.entryMovedNotDisplayed` | The entry was moved, but couldn’t be displayed. Reopen My Journal to try again. | The change was committed when moving an entry finished, but reading the journals again for display failed. | generic alert, or the operation’s sheet | common.ok |  |
| `messages.refresh.dateSaved` | The date was saved. Reopen My Journal to refresh your entries. | The change was committed when Change Date finished, but reading the journals again for display failed. | generic alert, or the operation’s sheet | common.ok |  |
| `messages.refresh.journalDeleted` | The journal was deleted, but couldn’t be displayed. Reopen My Journal to try again. | The change was committed when Delete Journal found the journal already deleted elsewhere, but reading the journals again for display failed. | generic alert, or the operation’s sheet | common.ok |  |
| `messages.refresh.journalRestored` | The journal was restored, but couldn’t be displayed. Reopen My Journal to try again. | The change was committed when Restore Journal found the journal already restored elsewhere, but reading the journals again for display failed. | generic alert, or the operation’s sheet | common.ok |  |
| `messages.refresh.itemsDeleted` | The items were deleted, but My Journal couldn’t update the view. Reopen My Journal to continue. | The change was committed when Delete All in Recently Deleted finished, but reading the journals again for display failed. | generic alert, or the operation’s sheet | common.ok |  |
| `messages.refresh.journalDeletedView` | The journal was deleted, but My Journal couldn’t update the view. Reopen My Journal to continue. | The change was committed when deleting a journal finished, but reading the journals again for display failed. | generic alert, or the operation’s sheet | common.ok |  |
| `messages.refresh.itemDeleted` | The item was deleted, but My Journal couldn’t update the view. Reopen My Journal to continue. | The change was committed when Delete Permanently finished, but reading the journals again for display failed. | generic alert, or the operation’s sheet | common.ok |  |

### Other generic alert messages

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.generic.defaultJournalFailed` | Couldn’t save the default journal. | Choosing Settings ▸ General ▸ Default Journal failed to save. | generic alert | common.ok |  |
| `messages.generic.pinFailed` | Couldn’t pin the entry. | Pin Entry failed (including when the library record is from a newer version). | generic alert | common.ok |  |
| `messages.generic.unpinFailed` | Couldn’t unpin the entry. | Unpin Entry failed. | generic alert | common.ok |  |
| `messages.generic.moveJournalFailed` | Couldn’t move the journal. | Reordering a journal failed. | generic alert | common.ok |  |
| `messages.generic.journalNamedUnavailable` | “{name}” is no longer available. | New Entry In ▸ a journal from a template, when that journal left the list meanwhile. | generic alert | common.ok |  |
| `messages.generic.journalUnavailable` | This journal is no longer available. | As messages.generic.journalNamedUnavailable when the journal has no name to show; also JournalMergeError.sourceUnavailable in Merge Into…. | generic alert; Merge Into… | common.ok |  |
| `messages.generic.templateUnavailable` | This template is no longer available. | Starting an entry from a template that was deleted or is from a newer version. | generic alert; template chooser | common.ok |  |
| `messages.generic.templateNeedsReview` | Review the changes to this template first. | Starting an entry from a template that has changes to review. | generic alert; template chooser | common.ok |  |
| `messages.generic.journalDeleteNeedsReview` | This journal has changes that need review before it can be deleted. | Delete Journal when the journal or one of its entries has changes to review, or it changed meanwhile. | generic alert | common.ok |  |
| `messages.generic.journalDeleteNeedsUpdate` | Update My Journal to delete this journal. | Delete Journal for a journal saved by a newer version. | generic alert | common.ok |  |
| `messages.generic.deleteChanged` | This has changed since you chose to delete it. Check it and try again. | Delete Permanently when the item changed or was restored meanwhile. | generic alert | common.ok |  |
| `messages.generic.deleteNeedsUpdate` | Update My Journal to delete this. | Delete Permanently for an item saved by a newer version. | generic alert | common.ok |  |
| `messages.generic.deleteNeedsReview` | This has changes that need review before it can be deleted. | Delete Permanently for an item with changes to review. | generic alert | common.ok |  |

### Export and import

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.export.archiveSaveFailed` | Couldn’t save the archive. Try again, or choose another location. | Export Archive: writing to the chosen location failed. | Export Archive error |  |  |
| `messages.export.archiveNoSpace` | There isn’t enough space to export the archive. Free up space, then try again. | Export Archive: the disk is full. | Export Archive error |  |  |
| `messages.export.archiveFailed` | Couldn’t export the archive. Try again. | Export Archive: any other failure. | Export Archive error |  |  |
| `messages.export.markdownSaveFailed` | Couldn’t save the files. Try again, or choose another location. | Export as Markdown: writing to the chosen location failed. | Export as Markdown error |  |  |
| `messages.export.markdownNoSpace` | There isn’t enough space to export your journals. Free up space, then try again. | Export as Markdown: the disk is full. | Export as Markdown error |  |  |
| `messages.export.markdownFailed` | Couldn’t export your journals. Try again. | Export as Markdown: any other failure. | Export as Markdown error |  |  |
| `messages.import.archiveNeedsUpdate` | Update My Journal to import this archive as new journals. You can still restore it on a device with no journals. | Import Archive into a device with journals, when the archive has content from a newer version. | Import Archive |  |  |
| `messages.import.mergeNeedsUpdate` | Update My Journal to merge the journals on this device. Some of them were saved by a newer version. | Merge Journals while connecting, when this device has content from a newer version. | Connect to a Server |  |  |

### Images

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.image.tooLarge` | Choose an image smaller than 25 MB. | Insert Image, paste or drop of an image over 25 MB (also the store’s own check). | image notice; generic alert |  |  |
| `messages.image.unreadable` | This file couldn’t be read as an image. | Insert Image of a file that isn’t a readable image. | image notice; generic alert |  |  |
| `messages.image.unavailable` | The image couldn’t be added. It may still be downloading from iCloud. Try again later. | Insert Image of a photo the photo library couldn’t provide. | image notice |  |  |
| `messages.image.descriptionsNeedSource` | Edit image descriptions in Markdown source for this entry. | Image Descriptions for an entry whose images can only be edited in View Source. | Image Descriptions sheet |  |  |

### Other operation errors

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.entry.unavailableForEditing` | This entry is no longer available for editing. | EntryDateError / ImageDescriptionError / EntryArchivingError .unavailable: the entry was deleted or moved meanwhile. | Change Date; Image Descriptions |  |  |
| `messages.entry.dateChanged` | This entry’s date changed. Close this sheet and try again. | EntryDateError.changed. | Change Date sheet |  |  |
| `messages.entry.imagesChanged` | This entry has changed. Review its images again. | ImageDescriptionError.changed. | Image Descriptions sheet |  |  |
| `messages.entry.archiveChanged` | This entry’s archive status changed. Review it before trying again. | EntryArchivingError.changed. Archiving was removed; nothing calls it. | none |  | unreachable |
| `common.journalGone` | That journal is no longer available. Choose another journal. | Move Entry or Merge Into… when the chosen journal was deleted meanwhile (also JournalMergeError.destinationUnavailable). | Move Entry; Merge Into… |  |  |
| `messages.entry.moveNeedsReview` | Review this entry’s changes before moving it. | Move Entry for an entry with changes to review. | Move Entry |  |  |
| `messages.entry.copyLocation` | Choose a new location for the journal copy. | Restoring a journal copy without a new location (a guard). | journal restore |  | rare |
| `messages.restore.changed` | This entry or journal has changed. Review it again before restoring. | EntryRestorationError.changed. | Restore sheet |  |  |
| `messages.restore.unavailable` | This entry or journal is no longer available for restoration. | EntryRestorationError.unavailable. | Restore sheet |  |  |
| `messages.restore.alreadyRestored` | This journal has already been restored. Review the entry before continuing. | EntryRestorationError.alreadyRestored. | Restore sheet |  |  |
| `messages.history.versionUnavailable` | This version is no longer available. Reload its history. | HistoryRecoveryError.unavailableVersion. | Version History |  |  |
| `messages.history.chooseJournal` | Choose an available journal. | HistoryRecoveryError.destinationUnavailable (Version History restore). In a deletion conflict it shows as messages.conflict.deletion.journalUnavailable. | Version History |  |  |
| `messages.history.journalChanged` | This journal has changed. Review its settings again. | HistoryRecoveryError.changedJournal. | journal Version History |  |  |
| `messages.history.settingsInUse` | These settings are already in use. | HistoryRecoveryError.settingsAlreadyApplied. | journal Version History |  |  |
| `messages.lifecycle.changed` | This journal has changed. Review the entries before deleting it. | JournalLifecycleError.changed (Delete Journal sheet; the delete prompt shows messages.generic.journalDeleteNeedsReview instead). | Delete Journal sheet |  |  |
| `messages.lifecycle.changedContinue` | This journal has changed. Review it again before continuing. | Restore Journal sheet when the journal changed meanwhile. | Restore Journal sheet |  |  |
| `messages.lifecycle.missingJournal` | This journal is unavailable. | JournalLifecycleError.missingJournal. | journal sheets |  |  |
| `messages.lifecycle.unsupportedJournal` | Update My Journal to make changes to this journal. | JournalLifecycleError.unsupportedJournal: a journal saved by a newer version. | journal sheets |  |  |
| `messages.lifecycle.alreadyDeleted` | This journal is already in Recently Deleted. | JournalLifecycleError.alreadyDeleted. | journal sheets |  |  |
| `messages.lifecycle.alreadyRestored` | This journal has already been restored. | JournalLifecycleError.alreadyRestored. | journal sheets |  |  |
| `messages.lifecycle.needsReview` | These changes need review before you can continue. | JournalLifecycleError.conflict and JournalMergeError.conflict. | journal sheets; Merge Into… | Review Changes where offered |  |
| `messages.merge.newerVersion` | Update My Journal to merge this journal. Some entries were saved by a newer version. | JournalMergeError.newerVersion. | Merge Into… |  |  |
| `messages.journal.nameTaken` | A journal named “{name}” already exists. | JournalNameError.taken, and the Name Taken alert’s announcement. | Name Taken alert; journal settings |  |  |

### Unavailable and read-only content

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.unavailable.markdownSource` | This entry uses Markdown that can’t be previewed. | Under the title of an entry whose Markdown can only be shown and edited as source. | entry editor note |  |  |
| `common.previewUnavailable` | Preview isn’t available for this entry | Help tag of the dimmed View Preview / View Source control for such an entry. | editor toolbar help |  |  |
| `common.unavailableJournals` | Unavailable Journals | Sidebar row and list title of the collection of entries whose journal is missing, from a newer version, or has changes to review. Shown only while such entries exist or it is open. | sidebar; entries list title |  |  |
| `messages.unavailable.empty` | No Unavailable Entries | Entries list of Unavailable Journals when it is empty. | entries list |  |  |
| `common.searchUnavailableEntries` | Search Unavailable Entries | Search field placeholder, help and label in Unavailable Journals. | search field |  |  |
| `common.updateToRestoreEntry` | Update My Journal to restore this entry. | Notice above an entry whose journal was saved by a newer version. | entry recovery notice |  |  |
| `common.journalNotArrived` | This journal hasn’t arrived on this device. | Notice above an entry whose journal is missing, while this device syncs. | entry recovery notice | common.trySyncingAgain |  |
| `common.trySyncingAgain` | Try Syncing Again | Runs a sync that also resends refused items. | entry recovery notice |  |  |
| `common.journalUnavailableEntrySaved` | The journal for this entry is unavailable. Your entry is still saved. | Notice above an entry whose journal is missing, on a device that doesn’t sync. | entry recovery notice | Restore and Move… when it was deleted with its journal |  |
| `common.journalNeedsReview` | This journal has changes to review. | Notice above an entry whose journal has changes to review. | entry recovery notice | common.reviewChanges |  |
| `messages.unavailable.restoreJournalNeedsUpdate` | Update My Journal to restore this journal. | A deleted journal saved by a newer version, in Recently Deleted. | deleted journal view | Export Archive… |  |

### Privacy cover and announcements

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `common.myJournalIsLocked` | My Journal Is Locked | Label on the privacy cover, only while the journals are locked; while the app is merely inactive the cover is blank. | privacy cover |  |  |
| `messages.announce.pinned` | Pinned | VoiceOver announcement after Pin Entry, from any place it is offered. | announcement |  |  |
| `messages.announce.unpinned` | Unpinned | VoiceOver announcement after Unpin Entry. | announcement |  |  |
| `messages.announce.journalMovedAbove` | Moved above {name}. | VoiceOver announcement after reordering a journal; {name} is the journal now below it. | announcement |  |  |
| `messages.announce.journalMovedBelow` | Moved below {name}. | As above, when the journal moved to the end; {name} is the journal now above it. | announcement |  |  |

### Conflicts

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.conflict.entryNotice` | This entry has changes from another device. | Notice above an entry or template that has changes to review (above the writing on every platform). Also JournalError.conflict’s description. | entry editor notice | common.reviewChanges |  |
| `common.reviewChangesFor` | Review Changes for {title} | Accessibility label of each Review Changes button in Settings ▸ Sync ▸ Changes to Review. | Settings ▸ Sync |  |  |
| `messages.conflict.needsReview` | Changes need review | Accessibility label of the exclamation mark on an entry row with changes to review, and visible text in a journal’s settings section. | entries list row; journal settings |  |  |
| `messages.conflict.settingsSection` | Changes to Review | Header of the section in Settings ▸ Sync that lists every record with changes to review, shown only when there is one and the app is unlocked. | Settings ▸ Sync |  |  |
| `messages.conflict.locked` | Unlock My Journal to review changes. | Review sheet content when the journals locked while it was open (the sheet then closes). | review sheet |  |  |
| `messages.conflict.resolved` | These changes have been resolved. | Review sheet when the conflict no longer exists (resolved here or on another device). | review sheet | common.done |  |
| `messages.conflict.updateToReview` | Update My Journal to review these changes. | Review sheet when either version has content this version can’t read (unsupported conflict). | review sheet | Export Archive… |  |
| `common.version` | Version | Label of the This Device / Other Device choice. | review sheet |  |  |
| `common.thisDevice` | This Device | This device’s version, in the version choice and as the shown version’s heading. | review sheet |  |  |
| `messages.conflict.version.otherDevice` | Other Device | The received version. | review sheet |  |  |
| `messages.conflict.version.hintThisDevice` | Version from This Device | Accessibility hint of the read-only preview while This Device is shown. | entry review |  |  |
| `messages.conflict.version.hintOtherDevice` | Version from Other Device | Accessibility hint of the preview while Other Device is shown. | entry review |  |  |
| `messages.conflict.keepBoth` | Keep Both | Primary action in an entry or template review: keeps both versions as separate items. | entry review |  |  |
| `messages.conflict.keepBothNote.entries` | Keep Both saves the versions as separate entries. | Note above Keep Both for an entry. | entry review |  |  |
| `messages.conflict.keepBothNote.templates` | Keep Both saves the versions as separate templates. | Note above Keep Both for a template. | entry review |  |  |
| `messages.conflict.keepBothOutcome.place` | Each version stays where it is. | Added after the Keep Both note when the versions are in different places (journal, Recently Deleted or archive). | entry review |  |  |
| `messages.conflict.keepBothOutcome.date` | Each version keeps its date. | Added when the versions have different entry dates. | entry review |  |  |
| `messages.conflict.keepBothOutcome.placeAndDate` | Each version keeps its place and date. | Added when both differ. | entry review |  |  |
| `messages.conflict.keepOne` | Keep One Version | Menu with the two single-version choices. | entry review |  |  |
| `messages.conflict.keepThisDevice` | Keep Version from This Device… | Item of Keep One Version; asks for confirmation. | entry review |  |  |
| `messages.conflict.keepOtherDevice` | Keep Version from Other Device… | Item of Keep One Version; asks for confirmation. | entry review |  |  |
| `messages.conflict.keepOne.title` | Keep this version? | Confirmation title for Keep Version from This Device… or Other Device…. | entry review confirmation | messages.conflict.keepVersion, common.cancel |  |
| `messages.conflict.keepVersion` | Keep Version | Confirming button in every keep-one-version confirmation (entries and journals). | confirmations |  |  |
| `messages.conflict.keepOne.history` | The original versions will remain in Version History. | Confirmation message; for Other Device it follows an outcome line when keeping it moves or redates the entry. | entry review confirmation |  |  |
| `messages.conflict.outcome.entry.moveToRecentlyDeleted` | The entry will move to Recently Deleted. | Confirmation for Keep Version from Other Device… when that version of the entry is in Recently Deleted and this one isn’t. | entry review confirmation |  |  |
| `messages.conflict.outcome.entry.moveTo` | The entry will move to {journal}. | Confirmation when that version of the entry is in another place; {journal} is its journal name (“Untitled Journal” when unnamed). | entry review confirmation |  |  |
| `messages.conflict.outcome.entry.archiveIn` | The entry will be archived in {journal}. | Confirmation when that version of the entry was archived by an earlier version of My Journal. | entry review confirmation |  | legacy archive |
| `messages.conflict.outcome.entry.dateChange` | The entry’s date will change to {date}. | Confirmation when only the entry’s date differs; {date} is the abbreviated date, for example “1 Oct 2026”. | entry review confirmation |  |  |
| `messages.conflict.outcome.entry.moveToRecentlyDeletedAndDate` | The entry will move to Recently Deleted, and its date will change to {date}. | Place and date both differ. | entry review confirmation |  |  |
| `messages.conflict.outcome.entry.moveToAndDate` | The entry will move to {journal}, and its date will change to {date}. | Place and date both differ. | entry review confirmation |  |  |
| `messages.conflict.outcome.entry.archiveInAndDate` | The entry will be archived in {journal}, and its date will change to {date}. | Archived place and date both differ. | entry review confirmation |  | legacy archive |
| `messages.conflict.outcome.template.moveToRecentlyDeleted` | The template will move to Recently Deleted. | Confirmation for Keep Version from Other Device… when that version of the template is in Recently Deleted and this one isn’t. | entry review confirmation |  |  |
| `messages.conflict.outcome.template.moveTo` | The template will move to {journal}. | Confirmation when that version of the template is in another place; {journal} is its journal name (“Untitled Journal” when unnamed), or “Templates”. | entry review confirmation |  |  |
| `messages.conflict.outcome.template.archiveIn` | The template will be archived in {journal}. | Confirmation when that version of the template was archived by an earlier version of My Journal. | entry review confirmation |  | legacy archive |
| `messages.conflict.outcome.template.dateChange` | The template’s date will change to {date}. | Confirmation when only the template’s date differs; {date} is the abbreviated date, for example “1 Oct 2026”. | entry review confirmation |  |  |
| `messages.conflict.outcome.template.moveToRecentlyDeletedAndDate` | The template will move to Recently Deleted, and its date will change to {date}. | Place and date both differ. | entry review confirmation |  |  |
| `messages.conflict.outcome.template.moveToAndDate` | The template will move to {journal}, and its date will change to {date}. | Place and date both differ. | entry review confirmation |  |  |
| `messages.conflict.outcome.template.archiveInAndDate` | The template will be archived in {journal}, and its date will change to {date}. | Archived place and date both differ. | entry review confirmation |  | legacy archive |
| `messages.conflict.placement.inJournal` | In {journal} | Line under the shown version’s date when the versions are in different places; {journal} is its journal (“Untitled Journal” when unnamed). | entry review |  |  |
| `messages.conflict.placement.inRecentlyDeleted` | In Recently Deleted | As above, for a version in Recently Deleted. | entry review |  |  |
| `messages.conflict.placement.inTemplates` | In Templates | As above, for a template version. | entry review |  |  |
| `messages.conflict.placement.archivedIn` | Archived in {journal} | As above, for a version archived by an earlier version of My Journal. | entry review |  | legacy archive |
| `messages.conflict.placement.dated` | Dated {date} | Line when only the entry dates differ. | entry review |  |  |
| `messages.conflict.placement.inJournalDated` | In {journal}, dated {date} | Place and date both differ. | entry review |  |  |
| `messages.conflict.placement.inRecentlyDeletedDated` | In Recently Deleted, dated {date} | Place and date both differ. | entry review |  |  |
| `messages.conflict.placement.inTemplatesDated` | In Templates, dated {date} | Place and date both differ. | entry review |  |  |
| `messages.conflict.placement.archivedInDated` | Archived in {journal}, dated {date} | Place and date both differ. | entry review |  | legacy archive |
| `messages.conflict.status.updated` | These changes were updated. Review both versions again. | Entry review: the other device’s version changed while the review was open, or a choice was refused because it changed. The choice is cleared and This Device is shown. | entry review status |  |  |
| `messages.conflict.status.refreshFailed` | Changes couldn’t be updated. | Entry review: reading the changed versions again failed; previews and choices are hidden. | entry review status | common.tryAgain |  |
| `messages.conflict.savingChanges` | Saving Changes… | Progress while a choice is saved (entry and journal reviews). | review sheet |  |  |
| `messages.conflict.updatingChanges` | Updating Changes… | Progress while the entry review reads the versions again. | entry review |  |  |
| `messages.conflict.committedNotReloaded` | Changes saved. The entry couldn’t be reloaded. | Entry review: the choice was saved but reading the result failed. Only reloading is offered; the choice is never applied twice. | entry review | common.tryAgain, common.done |  |
| `messages.conflict.updatedReviewAgain` | These changes have been updated. Review them again. | Journal or deletion review: the versions changed since the review was read; the choice wasn’t applied. | journal review; deletion review | messages.conflict.journal.reloadChanges (journal); messages.conflict.deletion.reviewAgain (deletion) |  |
| `messages.conflict.journal.keepVersion` | Keep Version… | Journal review: keeps the shown version, after confirmation. There is no Keep Both for journals. | journal review |  |  |
| `messages.conflict.journal.confirmThisDevice` | Keep the version from This Device? | Confirmation title when This Device is shown. | journal review confirmation | messages.conflict.keepVersion, common.cancel |  |
| `messages.conflict.journal.confirmOtherDevice` | Keep the version from Other Device? | Confirmation title when Other Device is shown. | journal review confirmation | messages.conflict.keepVersion, common.cancel |  |
| `messages.conflict.journal.confirmMessage` | {date}. Both versions will remain in Version History. | Confirmation message; {date} is the version’s modification date and time (abbreviated date, standard time). | journal review confirmation |  |  |
| `common.name` | Name | Field label in the journal version summary. | journal review |  |  |
| `common.defaultTemplate` | Default Template | Field label. | journal review |  |  |
| `messages.conflict.journal.field.location` | Location | Field label. | journal review |  |  |
| `common.journals` | Journals | Location of a version in the Journals list. | journal review |  |  |
| `common.recentlyDeleted` | Recently Deleted | Location of a version in Recently Deleted. | journal review |  |  |
| `common.blankEntry` | Blank Entry | Default Template value when none is set. | journal review |  |  |
| `messages.conflict.journal.value.unavailableTemplate` | Unavailable Template | Default Template value when the template isn’t on this device. | journal review |  |  |
| `common.untitledJournal` | Untitled Journal | Name value for an unnamed journal. | journal review |  |  |
| `messages.conflict.journal.details` | Details | Disclosure under Other Device that shows the recorded device ID (lower-case, selectable). | journal review |  |  |
| `messages.conflict.journal.deviceIDLabel` | Recorded device ID {id} | Accessibility label of the device ID. | journal review |  |  |
| `messages.conflict.journal.saved` | Your choice was saved. | Journal review after a successful choice. | journal review | common.done |  |
| `messages.conflict.journal.savedNotDisplayed` | Your choice was saved, but the journal couldn’t be displayed. | Journal review: saved, but reading the journals again failed. | journal review | messages.conflict.journal.reload |  |
| `messages.conflict.journal.reload` | Reload | Retries reading after a saved choice. | journal review |  |  |
| `messages.conflict.journal.reloadChanges` | Reload Changes | Reads the conflict again after an error before a choice was saved. | journal review |  |  |
| `messages.conflict.journal.loading` | Loading Changes… | Progress while Reload Changes runs. | journal review |  |  |
| `messages.conflict.journal.errorLabel` | Error: {message} | Accessibility label of the journal review’s error text. | journal review |  |  |
| `messages.conflict.journal.chooseOne` | Choose one version of this journal. Its entries will stay in the same journal. | The store refuses Keep Both for a journal. Never shown: the journal review only offers Keep Version…. | none |  | unreachable |
| `common.onThisDevice` | On This Device | Location line of this device’s version. | deletion review |  |  |
| `messages.conflict.deletion.receivedVersion` | Received Version | Location line of the received version. | deletion review |  |  |
| `messages.conflict.deletion.unknownDevice` | Unknown Device | Device line of each version (no device name is known). | deletion review |  |  |
| `messages.conflict.deletion.deletionToKeep` | Deletion to Keep | Location line of the deletion in the Keep Deletion confirmation when both versions are deletions. | deletion review confirmation |  |  |
| `messages.conflict.deletion.deletedTitle.entry` | Deleted Entry | How a permanently deleted entry is named (its marker has no title): heading of the version, and its row in Settings ▸ Sync ▸ Changes to Review. | deletion review; Settings ▸ Sync |  |  |
| `messages.conflict.deletion.bothDeleted.entry` | Both versions show this entry as deleted. | Deletion review when both versions of a entry are deletions. | deletion review | messages.conflict.deletion.keepDeletion |  |
| `messages.conflict.deletion.confirmKeepDeleted.entry` | Keep Entry Deleted? | Title of the destructive confirmation sheet when both versions of a entry are deletions. | deletion review confirmation | messages.conflict.deletion.deletePermanently, common.cancel |  |
| `messages.conflict.deletion.confirmDeleteEdited.entry` | Delete Edited Entry? | Title of the destructive confirmation sheet when one version is an edited entry. | deletion review confirmation | messages.conflict.deletion.deletePermanently, common.cancel |  |
| `messages.conflict.deletion.deletedTitle.template` | Deleted Template | How a permanently deleted template is named (its marker has no title): heading of the version, and its row in Settings ▸ Sync ▸ Changes to Review. | deletion review; Settings ▸ Sync |  |  |
| `messages.conflict.deletion.bothDeleted.template` | Both versions show this template as deleted. | Deletion review when both versions of a template are deletions. | deletion review | messages.conflict.deletion.keepDeletion |  |
| `messages.conflict.deletion.confirmKeepDeleted.template` | Keep Template Deleted? | Title of the destructive confirmation sheet when both versions of a template are deletions. | deletion review confirmation | messages.conflict.deletion.deletePermanently, common.cancel |  |
| `messages.conflict.deletion.confirmDeleteEdited.template` | Delete Edited Template? | Title of the destructive confirmation sheet when one version is an edited template. | deletion review confirmation | messages.conflict.deletion.deletePermanently, common.cancel |  |
| `messages.conflict.deletion.deletedTitle.journal` | Deleted Journal | How a permanently deleted journal is named (its marker has no title): heading of the version, and its row in Settings ▸ Sync ▸ Changes to Review. | deletion review; Settings ▸ Sync |  |  |
| `messages.conflict.deletion.bothDeleted.journal` | Both versions show this journal as deleted. | Deletion review when both versions of a journal are deletions. | deletion review | messages.conflict.deletion.keepDeletion |  |
| `messages.conflict.deletion.confirmKeepDeleted.journal` | Keep Journal Deleted? | Title of the destructive confirmation sheet when both versions of a journal are deletions. | deletion review confirmation | messages.conflict.deletion.deletePermanently, common.cancel |  |
| `messages.conflict.deletion.confirmDeleteEdited.journal` | Delete Edited Journal? | Title of the destructive confirmation sheet when one version is an edited journal. | deletion review confirmation | messages.conflict.deletion.deletePermanently, common.cancel |  |
| `messages.conflict.deletion.bothDeletedExplanation` | Keeping the deletion also removes any remaining earlier versions from My Journal. | Under messages.conflict.deletion.bothDeleted.*. | deletion review |  |  |
| `messages.conflict.deletion.keepEntry` | Keep Entry… | Edited entry against a deletion: keep the edited entry in a journal chosen next. | deletion review |  |  |
| `messages.conflict.deletion.keepEntryExplanation` | Keeps the edited entry. Earlier versions already deleted aren’t restored. | Under Keep Entry…. | deletion review |  |  |
| `messages.conflict.deletion.keepEntryAsCopy` | Keep Entry as Copy… | Keep the edited entry as a new entry in a journal chosen next. | deletion review |  |  |
| `messages.conflict.deletion.keepEntryAsCopyExplanation` | Creates a new entry and keeps the original deleted. Any remaining earlier versions stay available in archive exports. | Under Keep Entry as Copy…. | deletion review |  |  |
| `messages.conflict.deletion.keepTemplate` | Keep Template | Edited template against a deletion: keeps it at once. | deletion review |  |  |
| `messages.conflict.deletion.keepTemplateExplanation` | Keeps the edited template. Earlier versions already deleted aren’t restored. | Under Keep Template. | deletion review |  |  |
| `messages.conflict.deletion.keepJournal` | Keep Journal | Edited journal against a deletion: keeps it at once. | deletion review |  |  |
| `messages.conflict.deletion.keepJournalExplanation` | Keeps this journal’s name and template. Deleted entries aren’t restored. | Under Keep Journal. | deletion review |  |  |
| `common.restoredAsRenamed` | Another journal is named “{name}”, so this one will be restored as “{newName}”. | Under Keep Journal when the name is taken; {newName} is the numbered name. | deletion review |  |  |
| `messages.conflict.deletion.keepDeletion` | Keep Deletion… | Destructive: opens the confirmation that deletes the edited version permanently. | deletion review |  |  |
| `messages.conflict.deletion.keepDeletionExplanation.journal` | Removes this edited journal’s name, template setting, and earlier versions from My Journal. | Under Keep Deletion… for a journal, and in its confirmation. | deletion review; confirmation |  |  |
| `messages.conflict.deletion.keepDeletionExplanation.other` | Removes this edited version and its earlier versions from My Journal. | Under Keep Deletion… for an entry or template, and in its confirmation. | deletion review; confirmation |  |  |
| `messages.conflict.deletion.remainingVersionsRemoved` | Any remaining earlier versions will be removed from My Journal on this device. | Confirmation when both versions are deletions. | deletion review confirmation |  |  |
| `messages.conflict.deletion.consequence.sync` | This deletion will sync to your other connected devices. | Confirmation consequence line (shared with Delete Permanently). | deletion review confirmation |  | shared with permanent deletion |
| `messages.conflict.deletion.consequence.copies` | Copies may remain in archives, backups, and server history. | Confirmation consequence line (shared with Delete Permanently). | deletion review confirmation |  | shared with permanent deletion |
| `messages.conflict.deletion.consequence.noUndo` | You can’t undo this. | Confirmation consequence line (shared with Delete Permanently). | deletion review confirmation |  | shared with permanent deletion |
| `messages.conflict.deletion.deletePermanently` | Delete Permanently | Destructive button of the confirmation. | deletion review confirmation |  |  |
| `messages.conflict.deletion.deleting` | Deleting… | Progress in the confirmation. | deletion review confirmation |  |  |
| `common.pleaseWait` | Please Wait… | Progress while the review is prepared or a choice is saved. | deletion review |  |  |
| `common.chooseJournal` | Choose a Journal | Heading of the journal list after Keep Entry… or Keep Entry as Copy…. Journals with changes to review aren’t listed; journals with the same name add their date, then an ID prefix. | deletion review |  |  |
| `common.newJournalEllipsis` | New Journal… | Creates a journal to keep the entry in. | deletion review |  |  |
| `messages.conflict.deletion.selectedJournal` | Journal: {name} | Shows the chosen journal. | deletion review |  |  |
| `messages.conflict.deletion.confirmKeepEntry` | Keep Entry | Keeps the entry in the chosen journal. | deletion review |  |  |
| `messages.conflict.deletion.confirmKeepEntryAsCopy` | Keep Entry as Copy | Keeps a copy in the chosen journal. | deletion review |  |  |
| `common.back` | Back | Returns from the journal list to the choices. | deletion review |  |  |
| `messages.conflict.deletion.reviewAgain` | Review Again | Reads the conflict again after an error. | deletion review |  |  |
| `common.reloadJournals` | Reload Journals | Reads the conflict and journals again after the chosen journal became unavailable. | deletion review |  |  |
| `messages.conflict.deletion.journalUnavailable` | That journal is no longer available. Reload journals and choose another. | The chosen journal was deleted or has changes to review. | deletion review | common.reloadJournals |  |
| `messages.conflict.deletion.updateToReview` | Update My Journal to review these changes. You can export an archive to keep a copy. | A version can’t be read by this version of My Journal. | deletion review | Export Archive… |  |
| `messages.conflict.deletion.savedNotDisplayed` | Your choice was saved, but My Journal couldn’t update the view. Reopen My Journal to continue. | The choice was saved but reading the journals again failed. | deletion review | common.done |  |

## Accessibility announcements not tied to one screen

| Announcement | When |
| --- | --- |
| The held sync message, else `messages.sync.announce.synced`, else `messages.sync.announce.failed` | After Sync Now, Try Again or Check Again finishes, from Settings ▸ Sync or Sync Status. Never for automatic syncs. |
| `messages.announce.pinned`, `messages.announce.unpinned` | After Pin Entry or Unpin Entry, from any place it's offered (context menu, More menu, swipe, menu bar, Undo). |
| `messages.announce.journalMovedAbove`, `messages.announce.journalMovedBelow` | After a journal is reordered (drag, edit mode, Undo). |
| `messages.encryption.announce.turningOn`, `messages.encryption.announce.updatingServer`, `messages.encryption.announce.done` | Turn On Encryption's progress, wherever it is showing. |
| Errors in open sheets | Connect to a Server, Turn On Encryption, the journal and deletion reviews, and the lock screen announce their error when it appears. |
| Focus moves | The entry review moves VoiceOver focus to its status after reading the versions again; unlocking behind App Lock's closing panel moves focus to the journals (iPhone and iPad). |

The alert and the notices are not announced separately: an alert is read by the system, and notices are read in place.

## Errors without their own text

Some errors have no description, so if one reaches a place that shows `localizedDescription`, the person sees the system's generic text, such as "The operation couldn’t be completed. (… error 1.)". Known places:

- `PermanentDeletionError` (`missing`, `notDeleted`, `permanentlyDeleted`) in the deletion review's fallback ([flows/resolve-conflict.md](flows/resolve-conflict.md); [open-questions.md](open-questions.md), A7).
- Keychain failures (`SecretStoreError`) at launch, on the lock screen.
- Database errors at launch (the database's own text, which can include SQL), on the lock screen; and database errors from operations whose errors go to the generic alert.
- Decoding errors of the configuration file at launch, in the generic alert over the first-launch screen.

Sync never shows these: it classifies every error into a state.

## Open questions

Open questions about this file are collected in [open-questions.md](open-questions.md).
