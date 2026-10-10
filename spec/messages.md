---
id: messages
title: Messages
features: [sync-health, sync-status, sync-item-refusal, save-failure-recovery, writing-paused-notice, generic-error-alert, kept-both-notice, conflict-kept-both, changed-on-two-devices-list, library-open-failure, erase-unopened-library, failure-messages, read-only-newer-content, unavailable-journals, privacy-cover, accessibility-announcements]
sources:
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncHealth.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Models.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/ServerClient.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncEngine.swift
  - apps/apple/JournalApp/Model/
  - apps/apple/JournalApp/Views/SaveFailureNotice.swift
  - apps/apple/JournalApp/Views/SyncNowRows.swift
  - apps/apple/JournalApp/Views/KeptVersionNotice.swift
  - apps/apple/JournalApp/Views/KeptNotesSection.swift
  - apps/apple/JournalApp/Model/ConflictNotes.swift
  - apps/apple/JournalApp/Views/LibraryProblemView.swift
  - apps/apple/JournalApp/Model/FailureMessage.swift
  - apps/apple/JournalApp/Model/NetworkFailureMessage.swift
  - apps/apple/JournalApp/Model/LibraryProblem.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/LocalDataFailure.swift
  - docs/design/build-18-fixes-2026-10-06.md
---

# Messages

Every message that comes from the model layer rather than from one screen: sync states and their actions, server and network errors, every error type's description, save failures and paused writing, the generic alert, conflicts, unavailable and read-only content, the privacy cover, and accessibility announcements that aren't tied to one screen. The exact text of each key is in [copy/en.json](copy/en.json) (a message whose text another area also uses is keyed `common.*`); this page says when each appears, where, and what the person can do.

Related files: [screens/sync-status.md](screens/sync-status.md), [flows/sync-recovery.md](flows/sync-recovery.md), [flows/save-failure.md](flows/save-failure.md), [screens/kept-version-notice.md](screens/kept-version-notice.md), [flows/resolve-conflict.md](flows/resolve-conflict.md), [screens/unavailable-content.md](screens/unavailable-content.md).

## How messages reach the person

| Surface | What it shows | Rules |
| --- | --- | --- |
| **Settings ▸ Sync footer** | The current sync message, item refusal, save-paused note, or library note | One message at a time. Priority: `messages.sync.pausedForSaveFailure` (connected and a save failed), then the sync message, then the not-connected text, then `messages.library.needsUpdate`. |
| **Sync Status** | The same sync message, its action, and Sync Settings… | Only when the person must act, or after a long wait. See [screens/sync-status.md](screens/sync-status.md). |
| **Generic alert** | Title `common.alertTitle`, the message, `common.ok`, plus `common.tryAgain` while a save has failed | One per window. Never while locked or while the first journal is being created. Most "Couldn’t …", `messages.save.before.tryAgain`, "… couldn’t be displayed" messages and any operation error without its own place go here. |
| **Lock screen note** | The same model error, in red, under "My Journal Is Locked" | Used instead of the generic alert while locked. Launch failures no longer use it: they show the library problem screen. |
| **Library problem screen** | Heading, paragraphs and buttons for a library that can't be opened | Replaces the window; needs no authentication. See [screens/unavailable-content](screens/unavailable-content.md) and Library can’t be opened below. |
| **Sheet errors** | An operation's error inside its own sheet (Connect to a Server, Change Password, Add Device, Move Entry, Change Date, Image Descriptions, exports) | Errors stay on the sheet that caused them, never in an alert behind it. |
| **Notices** | Save failure, writing paused (Mac), other version kept, recovery and unavailable notices in the entry | Persistent while the state lasts, with their single action. |
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
| `messages.sync.serverNotSetUp` | The server isn’t set up. Your journals are still on this device. | Sync state Server changed (not set up): the server was reset and waits for a setup code. Automatic sync stops. | Settings ▸ Sync footer; Sync Status menu | common.reconnect |  |
| `messages.sync.serverReplaced` | The server was restored or replaced and doesn’t recognize this device. Your journals are still on this device. | Sync state Server changed (restored or replaced): this device was refused and the server now has a different identity. Automatic sync stops. | Settings ▸ Sync footer; Sync Status menu | common.reconnect |  |
| `messages.sync.accessRemoved` | This device no longer has access to the server. Your journals are still on this device. To reconnect, you need your password or a connected device. | Sync state No access for a library with a password: the same server refuses this device (removed in Settings ▸ Sync ▸ Devices on another device, or its credential stopped working). Automatic sync stops. Also what the Server section shows when loading the device list is refused and no sync can say why. | Settings ▸ Sync footer; Sync Status menu | common.reconnect | the device was removed on purpose, so the text says what signing in again needs |
| `messages.sync.appUpdateNeeded` | Update My Journal to sync with this server. Your changes are saved on this device. | Sync state Update or fix needed (update My Journal): the server speaks a newer protocol or recovery format, or the data needs a newer app. Automatic sync stops. | Settings ▸ Sync footer; Sync Status menu | messages.sync.action.checkAgain |  |
| `messages.sync.serverUpdateNeeded` | The server needs an update before this device can sync. Your changes are saved on this device. | Sync state Update or fix needed (server): the server reports a protocol revision below 1, or lacks an endpoint this app needs (404 or 405 on a sync request). Nothing queued is changed or sent; checked again every 5 minutes. | Settings ▸ Sync footer; Sync Status menu | messages.sync.action.checkAgain |  |
| `messages.sync.certificateInvalid` | Can’t connect securely to the server because its certificate isn’t valid. Your changes are saved on this device. | Sync state Update or fix needed (certificate): no secure connection could be made or the certificate isn’t trusted, expired or not yet valid. Checked again every 5 minutes. | Settings ▸ Sync footer; Sync Status menu | messages.sync.action.checkAgain |  |
| `messages.sync.notJournalServer` | The server address doesn’t lead to a My Journal server. Your changes are saved on this device. | Sync state Update or fix needed (not a journal server): the address answers, but its status isn’t a My Journal status (for example a web page or a captive portal). Checked again every 5 minutes. | Settings ▸ Sync footer; Sync Status menu | messages.sync.action.checkAgain |  |
| `messages.sync.localDataUnreadable` | My Journal can’t read your journals on this device. Nothing has been removed. To keep a copy, choose Export Archive in Settings ▸ Backup. | Sync state Unexpected (this device’s data is damaged): this device’s own database is malformed or isn’t a database, or the store’s own validation found it inconsistent. Retries continue with the usual backoff. Same wording as `messages.failure.damagedReading`. | Settings ▸ Sync footer; Sync Status menu | common.tryAgain |  |
| `messages.sync.localDataUnavailable` | Couldn’t sync right now. My Journal will try again. | Sync state Temporary (this device’s data): the local database was busy or locked, the device was locked, or the disk is failing or full. The data is fine, and the text makes no claim about saving. Retries continue with the usual backoff. | Settings ▸ Sync footer; Sync Status menu only after a long wait | common.tryAgain |  |
| `messages.sync.unexpected` | Couldn’t sync because of an unexpected problem. Your changes are saved on this device. | Sync state Unexpected: any other sync failure. Retries continue with the usual backoff. | Settings ▸ Sync footer; Sync Status menu | common.tryAgain |  |
| `messages.sync.waiting` | Saved on this device. Waiting to sync. | Sync Status’s message when it shows but no sync message is held. Only after the app locked and unlocked while a state that needs the person persists, until the next sync (the lock clears the message, not the state). | Sync Status menu | the state’s action | rare |
| `messages.sync.pausedForSaveFailure` | Syncing is paused until your changes are saved. Choose Try Again in the entry. | Settings ▸ Sync footer while connected and the open entry’s save has failed. Takes priority over every other footer message; Sync Now is dimmed. | Settings ▸ Sync footer | none here; Try Again in the entry |  |
| `messages.sync.recordTooLarge` | “{title}” is too large to sync. It’s saved on this device. Shorten it or split it into separate entries. | One entry, journal or template is larger than the server accepts; the rest syncs. {title} is the item’s title, cut to 40 characters with “…”. | Settings ▸ Sync footer; Sync Status menu | messages.sync.action.syncNow (sends it again) |  |
| `messages.sync.recordRefused` | Your server didn’t accept “{title}”. It’s saved on this device. Edit it to try again. | The server refused one record as invalid, or its push failed with a server error 3 times in a row while other requests succeeded; the rest syncs. | Settings ▸ Sync footer; Sync Status menu | messages.sync.action.syncNow (sends it again) |  |
| `messages.sync.imageTooLarge` | An image is too large for your server. Entries that include it are saved on this device. | The server refused an image as too large (413); entries that include it wait, the rest syncs. | Settings ▸ Sync footer; Sync Status menu | messages.sync.action.syncNow |  |
| `messages.sync.imageRefused` | Your server didn’t accept an image. Entries that include it are saved on this device. | The server refused an image as invalid; entries that include it wait, the rest syncs. | Settings ▸ Sync footer; Sync Status menu | messages.sync.action.syncNow |  |
| `messages.sync.action.syncNow` | Sync Now | The single action while syncing normally, or when only one record or image was refused. | Settings ▸ Sync; Sync Status menu |  |  |
| `messages.sync.action.checkAgain` | Check Again | The single action for Update or fix needed: runs a full sync now. | Settings ▸ Sync; Sync Status menu |  |  |
| `common.reconnect` | Reconnect… | The single action when the server was reset, restored or replaced, or this device lost access: opens Reconnect at this device’s server, which goes straight to the next step. One action for three states; the state decides the step, not the label. | Settings ▸ Sync (Server section, once); Sync Status menu; Settings ▸ Agent Access |  |  |
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
| `messages.library.itemUnavailable` | This item is no longer available. | LibraryError.unavailable. Never shown: pinning and moving journals show messages.generic.pinFailed / unpinFailed / moveJournalFailed instead (or messages.library.needsUpdate for a newer library record). | none |  | unreachable |

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
| `messages.error.newerVersion` | These journals were saved by a newer version of My Journal. Update My Journal to open them. | JournalError.newerVersion where no more specific text applies: the library’s database was migrated by a newer version. Since build 18 the launch shows `library.problem.newerVersion.message` on the library problem screen instead, so this text is no longer shown at launch. | none at launch (overridden) | none | overridden |
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
| `messages.connection.encryptionOff` | {host} doesn’t use encryption. On a device that has your journals, turn on encryption in Settings, or connect to a server that uses encryption. | A server set up without encryption (recovery format 3 or 4) refused by every device of this version: checking an address, a scanned code, or finishing a pairing. One text for all three (the address check used to have its own text). “Turn on encryption in Settings” is advice for a device that still runs version 1.0 and has the journals. | Connect to a Server |  |  |
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
| `messages.connection.passwordsDontMatch` | The passwords don’t match. | Choosing a master password: the two fields differ (Start a Journal, Connect to a Server, Change Password and Forgot Password?). | Start a Journal; Connect to a Server; Change Password |  |  |
| `messages.connection.credentialIncorrect` | That {credential} isn’t correct. | Signing in or setting up with an existing password: the credential is wrong. {credential} is “password” for any kind of password, or “recovery key”. | Connect to a Server ▸ credential field |  |  |
| `messages.connection.credentialRateLimited` | Too many {credential} attempts on this server. Try again in a few minutes, or use a connected device. | Signing in: the server rate-limited attempts. {credential} as in messages.connection.credentialIncorrect. | Connect to a Server ▸ credential field |  |  |
| `common.couldntReachHost` | Couldn’t reach {host}. Check your connection and try again. | Allow Access, when the request can’t be loaded or the server can’t be reached. | Allow Access | common.tryAgain | the one text for an unreachable server |
| `messages.connection.createFailed` | Couldn’t create your journal. Try again. | Setting up a server from a device with no library, when creating the library failed without its own message. | Connect to a Server |  |  |
| `messages.connection.updateApp` | Update My Journal to connect to this server. | Connect to a Server: the server speaks a newer protocol (a newer wire major), or a scanned pairing needs a newer app. | Connect to a Server |  |  |
| `messages.connection.serverNeedsUpdate` | This server needs an update before this device can connect. | The server reports a protocol revision below 1 (a server from before the first 1.0 releases). One message from every place that needs the server, with nothing changed on this device: Connect to a Server (page 1 and after a scanned code), Add This Device with a typed code, Add Device, Change Password, Encrypt Your Journals and Agent Access. It clears as soon as a status read shows an updated server. The sync state says the same in its own words (`messages.sync.serverUpdateNeeded`). | Connect to a Server; Add Device; Change Password; Encrypt Your Journals; Settings ▸ Agent Access |  |  |
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
| `messages.password.failed` | Couldn’t change your password. Your current password still works. Check your connection and try again. | PasswordChangeError.failed. | Change Password |  |  |
| `messages.password.notSavedLocally` | Your password was changed on your server but not on this device. Try again to finish. | PasswordChangeError.notSavedLocally. | Change Password | common.tryAgain |  |
| `messages.password.enterMaster` | Enter a master password. | Creating an encrypted library without a password (a guard). | first launch |  | rare |

### Generic alert

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `common.alertTitle` | My Journal | Title of the generic alert that shows model errors (save failures and every “Couldn’t …” message and `messages.save.before.tryAgain` routed to the window). The app’s name; it read “Journal” before build 18. Not shown while locked; the lock screen shows the message instead. | generic alert | common.ok; common.tryAgain while a save has failed |  |

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
| `messages.save.before.tryAgain` | Your changes aren’t saved yet. Choose Try Again, then repeat what you were doing. | An operation that needs the open entry written first was attempted while its save has failed, and the generic alert is where the refusal is shown: restoring a template, Delete Journal, Delete Permanently, Delete All, Move Entry when Restore calls it. Nothing else happens. The model throws one typed error; the alert chooses these words when it is shown, together with its Try Again button. If the save has succeeded by then, nothing is shown. | generic alert | common.tryAgain, common.ok | Replaces the 20 operation-specific “save first” messages. |
| `messages.save.before.goBack` | Your changes aren’t saved yet. Go back to your entry, choose Try Again under Not Saved, then repeat what you were doing. | The same refusal anywhere but the generic alert: inline in the sheet or pane of Move Entry, Create Journal, Version History, Restore Journal, Change Date, Image Descriptions, Export Archive, Export as Markdown, Import Archive and Connect to a Server. Also the fallback for any place that does not say it is the alert, so a forgotten place never mentions a button it does not have. | that operation’s sheet or pane error | go back to the entry, common.tryAgain in the Not Saved notice, then repeat | “Go back” means closing the sheet; on the Mac it also means switching from the Settings window to the journal window ([Apple notes](platforms/apple/messages.md)). In Image Descriptions the typed descriptions stay and Copy Descriptions stays available. |

### Writing paused

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.writingPaused.connecting` | Writing is paused while this Mac connects to your server. | Mac journal window, above the editor, while Connect to a Server (in the Settings window) replaces the library; appears after 1 second so a quick connection doesn’t flash it. | Mac journal window notice | messages.writingPaused.showConnection |  |
| `messages.writingPaused.connectionFailed` | This Mac couldn’t finish connecting to your server. Try again, or cancel to keep writing. | Mac journal window while a failed connection’s staged copy waits for Try Again or Cancel in the connection sheet. | Mac journal window notice | messages.writingPaused.showConnection |  |
| `messages.writingPaused.showConnection` | Show Connection | Brings the Settings window with the connection sheet forward. | Mac journal window notice |  |  |
| `messages.writingPaused.updating` | My Journal is updating your journals. Try again when it’s finished. | Opening an archive (from Finder or Files) while connecting replaces the library. | generic alert | common.ok |  |

### Library can’t be opened

The library problem screen ([screens/unavailable-content](screens/unavailable-content.md)) replaces the window; it has no alert and no generic message of its own. Its text is these keys:

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `library.problem.title` | Your Journals Can’t Be Opened | Heading when the library can’t be opened, its settings can’t be read, or the library isn’t encrypted. | library problem screen | retry-opening, import-archive, erase-unopened, open-library-guide | for a library that isn’t encrypted only erase-unopened and open-library-guide are offered |
| `library.problem.cantOpen.message` | My Journal can’t open the journals on this device. Nothing has been removed. | Can’t open: the library doesn’t open, or its first read fails. | library problem screen |  |  |
| `library.problem.cantOpen.advice` | Try again. If this keeps happening, restart your {device}. | Can’t open: second paragraph. {device} is the device’s name. | library problem screen |  |  |
| `library.problem.notEncrypted.message` | These journals aren’t encrypted, and this version of My Journal opens only encrypted journals. | Not encrypted: second paragraph, in place of the advice. The library on this device was made by version 1.0 without encryption (recovery format 3 or 4). No Try Again and no Import Archive…; Erase Journals and Settings… is offered at once. The files stay as they are. | library problem screen | erase-unopened, open-library-guide |  |
| `library.problem.settingsUnread.message` | My Journal can’t read the settings saved on this device. Nothing has been removed. | Settings unreadable: the settings file exists but doesn’t read or decode. | library problem screen |  |  |
| `library.problem.settingsUnread.advice` | If a newer version of My Journal saved these settings, update My Journal, then try again. If this keeps happening, restart your {device}. | Settings unreadable: second paragraph. | library problem screen |  |  |
| `library.problem.updateTitle` | Update My Journal | Heading when the journals were saved by a newer version. | library problem screen | open-library-guide |  |
| `library.problem.newerVersion.message` | These journals were saved by a newer version of My Journal. Update My Journal to open them. | Newer version: the only paragraph. Never names a store. | library problem screen |  |  |
| `library.problem.mayBeFine` | Your journals may still be fine. Only erase them if this keeps happening. | After one failed Try Again, in secondary text. | library problem screen |  |  |
| `library.problem.stillClosed` | Still can’t be opened. | Under Try Again after an attempt that ended in a problem again; announced when it appears. | library problem screen |  |  |
| `library.problem.learnMore` | Learn More | Opens the troubleshooting guide on the web. | library problem screen | open-library-guide |  |
| `library.problem.learnMore.hint` | Opens the troubleshooting guide in your browser. | Accessibility hint of Learn More. | library problem screen |  |  |
| `library.problem.importNote` | The journals on this device can’t be opened, but they may still be fine. Restoring removes them from this device and ends any syncing with a server. | Import Archive sheet, above its buttons, while the library can’t be opened. | Import Archive sheet |  |  |
| `library.problem.missingKey.caption` | Don’t have your {credential}? | Above Import Archive… and Erase Journals and Settings… on the lock screen of a missing device key. | lock screen | import-archive, erase-unopened |  |
| `settings.libraryProblem` | Settings are available once your journals open. | Settings while the library problem screen is showing. | Settings |  |  |
| `messages.library.deviceKeyUnavailable` | Your device key is unavailable. Use your {credential} to unlock your journals. | Launch or unlock: the key that opens the journals isn’t in this device’s keychain (for example after restoring a device backup). The lock screen asks for the library’s credential; {credential} is its name in lower case (“master password”, or “recovery key” for a library from an early build), the same name the field has. | lock screen | unlock with the credential |  |
| `messages.library.notOpen` | Your journals need to open before this can be done. | Connecting to a server, pairing and starting a journal while the library problem screen is showing or Try Again is running: they would replace the library. | generic alert; Connect to a Server | common.ok | rare |
| `messages.library.cannotOpen` | Your journals couldn’t be opened. Quit and reopen My Journal. | Only a guard: unlocking finds no library open. A library that fails to open shows the library problem screen and is never locked, so this text is rarely reachable. | lock screen | none | rare; overridden |

The erase warning for journals that can’t be opened has its own keys, `settings.erase.alert.unopened` and its parts ([flows/erase](flows/erase.md)).

### Failure messages

What the person is told when an operation fails and the failure has no text of its own. One function turns an error into a message and is given whether the operation was **reading** (a list, history or conflict read) or **saving** (anything that writes: Move Entry, Change Date, deleting, restoring, installing, descriptions). The system’s own text never reaches the person, because it can hold SQL, a title or an internal code; it is logged as private data (error domain and code only). The app’s own named errors keep their own text, which is already plain.

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.failure.damagedReading` | My Journal can’t read your journals on this device. Nothing has been removed. To keep a copy, choose Export Archive in Settings ▸ Backup. | Reading fails because the database is damaged (malformed, not a database, or the store’s own validation failed). Nothing else counts as damaged: a busy or locked database, a full disk, an unavailable file or a failing disk are temporary. | generic alert; the operation’s sheet | common.ok |  |
| `messages.failure.damagedSaving` | My Journal can’t save to your journals on this device. Nothing has been removed. To keep a copy, choose Export Archive in Settings ▸ Backup. | A change can’t be saved because the database is damaged. | generic alert; the operation’s sheet | common.ok |  |
| `messages.failure.temporaryReading` | My Journal couldn’t use its data on this device right now. Try again. | Reading fails for any other database, file-system or unknown reason. | generic alert; the operation’s sheet | common.ok |  |
| `messages.failure.temporarySaving` | My Journal couldn’t save your changes right now. Try again. | Saving fails for any other database, file-system or unknown reason. | generic alert; the operation’s sheet | common.ok |  |
| `messages.failure.full` | There isn’t enough space on this device. Free up space, then try again. | The database is full or a file write ran out of space. | generic alert; the operation’s sheet | common.ok |  |
| `messages.failure.keychain` | My Journal couldn’t use the device key. Try again. | The secure store (keychain) failed. “Device key” is the term the lock screen uses. | generic alert; the operation’s sheet | common.ok |  |
| `messages.failure.offline` | You’re offline. Check your connection. | A network error while the device has no connection. | Add Device; the operation’s sheet | common.ok |  |
| `messages.failure.certificate` | Can’t connect securely to the server because its certificate isn’t valid. | A network error caused by the server’s certificate. | Add Device; the operation’s sheet | common.ok |  |
| `messages.failure.unreachable` | Couldn’t reach the server. Check your connection. | Every other network error. | Add Device; the operation’s sheet | common.ok |  |
| `messages.failure.other` | Something went wrong. Try again. | Anything else with no text of its own. | generic alert; the operation’s sheet | common.ok |  |

A network error is classified as sync classifies it, so one place knows what a network error means. Surfaces that already had their own mapping (archive import and export, Export as Markdown, the connection flow, the sync states) keep it and use this function only for what falls through.

### Saved, but not displayed

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
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
| `messages.generic.pinFailed` | Couldn’t pin the entry. | Pin Entry failed, except when the library record is from a newer version, which shows `messages.library.needsUpdate`. | generic alert | common.ok |  |
| `messages.generic.unpinFailed` | Couldn’t unpin the entry. | Unpin Entry failed, except when the library record is from a newer version, which shows `messages.library.needsUpdate`. | generic alert | common.ok |  |
| `messages.generic.moveJournalFailed` | Couldn’t move the journal. | Reordering a journal failed, except when the library record is from a newer version, which shows `messages.library.needsUpdate`. | generic alert | common.ok |  |
| `library.templateChooser.entryChanged` | This entry changed, so the template wasn’t added. | The template chooser closes without adding anything when the open entry stopped being empty before a template was chosen. Nothing is created. | generic alert | common.ok |  |
| `messages.generic.journalDeleteNeedsUpdate` | Update My Journal to delete this journal. | Delete Journal for a journal saved by a newer version. | generic alert | common.ok |  |
| `messages.generic.deleteChanged` | This has changed since you chose to delete it. Check it and try again. | Delete Permanently when the item changed or was restored meanwhile. | generic alert | common.ok |  |
| `messages.generic.deleteNeedsUpdate` | Update My Journal to delete this. | Delete Permanently for an item saved by a newer version. | generic alert | common.ok |  |

### Export and import

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.export.archiveSaveFailed` | Couldn’t save the archive. Try again, or choose another location. | Export Archive: writing to the chosen location failed. | Export Archive error |  |  |
| `messages.export.archiveNoSpace` | There isn’t enough space to export the archive. Free up space, then try again. | Export Archive: the disk is full. | Export Archive error |  |  |
| `messages.export.archiveFailed` | Couldn’t export the archive. Try again. | Export Archive: any other failure. | Export Archive error |  |  |
| `messages.export.archiveSaved` | Archive saved. Keep your {credential} with it. | Export Archive: the save dialog saved the archive. {credential} is “master password” or “recovery key”, in lower case. Shown in the Export row until the next export starts and announced. | Export Archive row (Settings ▸ Backup, Export Archive sheet) |  | replaces the earlier silent save |
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
| `common.journalGone` | That journal is no longer available. Choose another journal. | Move Entry when the chosen journal was deleted meanwhile. | Move Entry |  |  |
| `messages.entry.copyLocation` | Choose a new location for the journal copy. | Restoring a journal copy without a new location (a guard). | journal restore |  | rare |
| `messages.history.versionUnavailable` | This version is no longer available. Reload its history. | HistoryRecoveryError.unavailableVersion. | Version History |  |  |
| `messages.history.chooseJournal` | Choose an available journal. | HistoryRecoveryError.destinationUnavailable (Version History restore). | Version History |  |  |
| `messages.lifecycle.changed` | This journal has changed. Review the entries before deleting it. | JournalLifecycleError.changed: the entries changed while the Delete Journal alert was open. It is not a conflict, so it shows in the generic alert with OK, not in the deletion conflict alert. | generic alert; Delete Journal sheet |  |  |
| `messages.lifecycle.missingJournal` | This journal is unavailable. | JournalLifecycleError.missingJournal. | journal sheets |  |  |
| `messages.lifecycle.unsupportedJournal` | Update My Journal to make changes to this journal. | JournalLifecycleError.unsupportedJournal: a journal saved by a newer version. | journal sheets |  |  |
| `messages.lifecycle.alreadyDeleted` | This journal is already in Recently Deleted. | JournalLifecycleError.alreadyDeleted. | journal sheets |  |  |
| `messages.lifecycle.alreadyRestored` | This journal has already been restored. | JournalLifecycleError.alreadyRestored. | journal sheets |  |  |
| `messages.restore.destinationGone` | The journal to restore into is no longer available. Nothing was restored. | Restore of an entry when the journal the control named, its own or the Default Journal, can't be used at that moment. | generic alert | common.ok |  |
| `messages.journal.nameTaken` | A journal named “{name}” already exists. | JournalNameError.taken, and the Name Taken alert’s announcement. | Name Taken alert; journal settings |  |  |

### Unavailable and read-only content

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.unavailable.markdownSource` | This entry uses Markdown that can’t be previewed. | Under the title of an entry whose Markdown can only be shown and edited as source. | entry editor note |  |  |
| `common.previewUnavailable` | Preview isn’t available for this entry | Help tag of the dimmed View Preview / View Source control for such an entry. | editor toolbar help |  |  |
| `common.unavailableJournals` | Unavailable Journals | Sidebar row and list title of the collection of entries whose journal is missing or was saved by a newer version. Shown only while such entries exist or it is open. | sidebar; entries list title |  |  |
| `messages.unavailable.empty` | No Unavailable Entries | Entries list of Unavailable Journals when it is empty. | entries list |  |  |
| `common.searchUnavailableEntries` | Search Unavailable Entries | Search field placeholder, help and label in Unavailable Journals. | search field |  |  |
| `common.updateToRestoreEntry` | Update My Journal to restore this entry. | Notice above an entry whose journal was saved by a newer version. | entry recovery notice |  |  |
| `common.journalNotArrived` | This journal hasn’t arrived on this device. | Notice above an entry whose journal is missing, while this device syncs. | entry recovery notice | common.trySyncingAgain |  |
| `common.trySyncingAgain` | Try Syncing Again | Runs a sync that also resends refused items. | entry recovery notice |  |  |
| `common.journalUnavailableEntrySaved` | The journal for this entry is unavailable. Your entry is still saved. | Notice above an entry whose journal is missing, on a device that doesn’t sync. | entry recovery notice | Restore to “{name}” when the entry itself is deleted |  |
| `messages.unavailable.restoreJournalNeedsUpdate` | Update My Journal to restore this journal. | A deleted journal saved by a newer version, in Recently Deleted. | deleted journal view | Export Archive… |  |

### Privacy cover and announcements

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `common.myJournalIsLocked` | My Journal Is Locked | Label on the privacy cover, only while the journals are locked; while the app is merely inactive the cover is blank. | privacy cover |  |  |
| `messages.announce.pinned` | Pinned | VoiceOver announcement after Pin Entry, from any place it is offered. | announcement |  |  |
| `messages.announce.unpinned` | Unpinned | VoiceOver announcement after Unpin Entry. | announcement |  |  |
| `messages.announce.journalMovedAbove` | Moved above {name}. | VoiceOver announcement after reordering a journal; {name} is the journal now below it. | announcement |  |  |
| `messages.announce.journalMovedBelow` | Moved below {name}. | As above, when the journal moved to the end; {name} is the journal now above it. | announcement |  |  |
| `messages.announce.restoredIn` | Restored to {name}. | VoiceOver announcement after Restore put an entry in a journal other than its own; {name} is that journal. Nothing is announced when the entry went back to its own journal. | announcement |  |  |

### Conflicts

| Key | Text | When it appears | Shown in | Actions | Notes |
| --- | --- | --- | --- | --- | --- |
| `messages.conflict.kept.notice.entry` | This entry was also changed on another device. The other version is saved as a separate entry. | Notice above the open entry on the device that kept both versions, when neither the title nor the text has the keyboard (otherwise the next time the entry is shown). | entry editor notice | show-other-version, dismiss-kept-notice | local to this device; no announcement |
| `messages.conflict.kept.notice.entryNewer` | This entry was also changed on another device, and that version is newer. It is saved as a separate entry. | As above, when the other version’s modified time is later (device clocks; the wording only). | entry editor notice | show-other-version, dismiss-kept-notice |  |
| `messages.conflict.kept.notice.template` | This template was also changed on another device. The other version is saved as a separate template. | As the entry notice, for a template. | entry editor notice | show-other-version, dismiss-kept-notice |  |
| `messages.conflict.kept.notice.templateNewer` | This template was also changed on another device, and that version is newer. It is saved as a separate template. | As above, when the other version’s modified time is later. | entry editor notice | show-other-version, dismiss-kept-notice |  |
| `messages.conflict.kept.noticeUpdate` | This entry has a version from a newer My Journal. Update My Journal to combine them. | Notice above an entry or template whose conflict is held because a newer My Journal wrote one of the versions. No buttons. | entry editor notice |  | settles by itself once the app can read both |
| `messages.conflict.kept.showOther` | Show Other Version | First button of the notice: opens the other version wherever it is and marks the notice seen. | entry editor notice | show-other-version |  |
| `common.dismiss` | Dismiss | Second button of the notice: marks it seen. The list row stays. | entry editor notice | dismiss-kept-notice |  |
| `messages.conflict.copyTitle` | {title} (other version) | Title of the other version of an entry or template kept as a separate item: the title the lists show for it (its title, else its first line cut at 60 characters, else the name of an untitled entry or template) with this text appended. Always appended, never detected, never parsed; the body is untouched. | the entries list and everywhere the item’s title shows |  | written into the item, so every device and a 1.0 device see it |
| `messages.lifecycle.combining` | Some changes from another device will finish combining when My Journal next syncs. | JournalLifecycleError.conflict (and the permanent-deletion equivalent): Move Entry, restoring a Version History version, Delete Permanently and Delete Journal for an item whose conflict still waits to be settled: after a pull, until the sync that finishes it; after a save over a version that arrived, a moment after writing pauses. A conflict only a newer version can read shows the update messages instead. Delete All reads such an item as one that can’t be deleted yet. | Move Entry, Version History, generic alert |  |  |
| `messages.conflict.kept.section` | Changed on Two Devices | Header of the section in Settings ▸ Sync that lists what the app settled itself: an entry or template kept as two versions, a journal renamed on two devices, and an item deleted permanently on one device and changed on another. Shown only when there are rows and the app is unlocked. | Settings ▸ Sync |  |  |
| `messages.conflict.kept.footer` | Both versions are kept. This list clears after 30 days. | Footer of that section. Journal rename notes do not expire; only Clear List removes them. | Settings ▸ Sync |  |  |
| `messages.conflict.kept.entry` | Changed on two devices. Both versions are kept. | Row: an entry or template changed on two devices and kept as two. The title is the other version’s current title; the row opens it wherever it is. A replaced copy updates its row. | Settings ▸ Sync ▸ Changed on Two Devices | open-kept-note |  |
| `messages.conflict.kept.entryNewer` | Changed on two devices. The other version is newer. Both versions are kept. | As above, when the other version’s modified time is later (device clocks; the wording only). | Settings ▸ Sync ▸ Changed on Two Devices | open-kept-note |  |
| `messages.conflict.kept.journalRenamed` | Renamed on two devices. The name is now “{name}”; the other was “{otherName}”. | Row: a journal renamed on two devices keeps the name that reached the server later (the server’s order, not the newer edit); the other name is here and in the journal’s history. Plain text. | Settings ▸ Sync ▸ Changed on Two Devices |  |  |
| `messages.conflict.kept.deletedAndChanged` | Deleted permanently on one device and changed on another. The changed version is saved separately. | Row: the deletion stays final and the changed entry or template is saved as a new one in Recently Deleted (Unavailable Journals when its journal is gone). The row opens it wherever it is. | Settings ▸ Sync ▸ Changed on Two Devices | open-kept-note |  |
| `messages.conflict.kept.journalDeleted` | Deleted permanently on one device and changed on another. It stays deleted. | Row: a journal deleted permanently on one device and changed on another stays deleted; no journal is created. Plain text. | Settings ▸ Sync ▸ Changed on Two Devices |  |  |
| `messages.conflict.kept.rowHint` | Opens it. | Accessibility hint of a row that opens an item; its label is the title, the sentence, then the date and time. | Settings ▸ Sync ▸ Changed on Two Devices |  |  |
| `messages.conflict.kept.clear` | Clear List | Last row of the section; forgets the notes at once, without confirmation. | Settings ▸ Sync ▸ Changed on Two Devices | clear-kept-notes |  |
| `messages.conflict.kept.updateNeeded` | Some changes from another device need a newer version of My Journal. Update My Journal to combine them. | One more line in the Settings ▸ Sync footer while a change from another device (an entry, template, journal or deletion) stays held because a newer version of My Journal wrote it. No row, no alert. | Settings ▸ Sync footer |  |  |

## Accessibility announcements not tied to one screen

| Announcement | When |
| --- | --- |
| The held sync message, else `messages.sync.announce.synced`, else `messages.sync.announce.failed` | After Sync Now, Try Again or Check Again finishes, from Settings ▸ Sync or Sync Status. Never for automatic syncs. |
| `messages.announce.pinned`, `messages.announce.unpinned` | After Pin Entry or Unpin Entry, from any place it's offered (context menu, More menu, swipe, menu bar, Undo). |
| `messages.announce.journalMovedAbove`, `messages.announce.journalMovedBelow` | After a journal is reordered (drag, edit mode, Undo). |
| `messages.announce.restoredIn` | After Restore put an entry in a journal other than its own (iPhone, iPad and Mac). |
| `messages.export.archiveSaved` | After the archive is saved. |
| Errors in open sheets | Connect to a Server and the lock screen announce their error when it appears. |
| Focus moves | Unlocking behind App Lock's closing panel moves focus to the journals (iPhone and iPad). |

The alert and the notices are not announced separately: an alert is read by the system, and notices are read in place.

## Errors without their own text

Some errors have no description of their own, so if one reached a place that shows its description, the person would see the system’s generic text, such as “The operation couldn’t be completed. (… error 1.)”, or a database error with its SQL. Since build 18 those places use the failure messages above, and the generic fallback is `messages.failure.other`. The places that took this text before were the deletion review’s fallback for `PermanentDeletionError` (the review is gone in 1.1), keychain failures and database errors at launch and in operations, and the decoding error of a settings file at launch (now the library problem screen).

Sync never shows these: it classifies every error into a state.

## Open questions

Open questions about this file are collected in [open-questions.md](open-questions.md).
