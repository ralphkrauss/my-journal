# Erase Journals and Settings on this device — 2026-10-04

Status: current, built 2026-10-04 (reviewed: approve with required changes, addressed in section 9; implementation check in section 10).

## Request

Owner: “There should be a way to reset the app (start from scratch). This would simply be locally and not delete everything on the remote.”

Today there is no way back to the first screen short of deleting the app. Stop Syncing keeps the library; Delete All only empties Recently Deleted.

## 1. Where it lives

**Settings ▸ Privacy, in a last section of its own**, on iPhone, iPad and in the Mac Settings window (Privacy tab). Privacy already holds the device's protection (Encryption, App Lock), it's where someone handing on or clearing a device looks, and both platforms have the same pane, so the instructions are the same everywhere. A single destructive button at the end of a settings pane is the familiar place for this in Apple's apps (General ▸ Transfer or Reset ▸ Erase All Content and Settings; Safari's Clear History and Website Data).

```
Settings ▸ Privacy
  ENCRYPTION …
  APP LOCK …
 ┌──────────────────────────────────────────┐
 │ Erase Journals and Settings…             │   red text (destructive role)
 └──────────────────────────────────────────┘
  Removes your journals, settings and server
  connection from this device, as if My Journal
  had just been installed. Your server and your
  other devices aren’t changed.
```

- Button: **Erase Journals and Settings…** (`role: .destructive`; the ellipsis because a confirmation follows). Title case on both platforms, as other buttons.
- Footer, connected: **“Removes your journals, settings and server connection from this device, as if My Journal had just been installed. Your server and your other devices aren’t changed.”** Not connected: **“Removes your journals and settings from this device, as if My Journal had just been installed.”**
- No keyboard shortcut and no menu item.

## 2. Flow

1. **Erase Journals and Settings…** saves the open writing (`flush`), counts what exists only on this device, and shows an alert.
2. **Alert** (`alert`, not an action sheet, as for other irreversible confirmations in the app). Title: **“Erase Journals and Settings?”** (title case, as “Delete 3 Items Permanently?”). Message and buttons by case (`host` is the server's name as shown elsewhere, `N items` uses the existing “1 item / 3 items” wording):

   | Case | Message | Buttons |
   | --- | --- | --- |
   | Connected, syncing normally, nothing waiting | “Your journals stay on host and your other devices, and this device is signed out of host. To use them here again, connect to host.” | Erase · Cancel |
   | Connected, N items not on the server yet (everything waiting to be sent, including changes waiting for a review or refused by the server; an entry waiting for its image counts) | “N items haven’t reached host yet. They’re only on this device and will be lost. Export an archive first to keep a copy. You can’t undo this.” | Export Archive… · Erase · Cancel |
   | Connected, but the last sync failed or the server needs attention (any sync problem state, never synced, or encryption turned on elsewhere) | “This device couldn’t confirm that your journals are on host. Anything that isn’t will be lost. Export an archive first to keep a copy. You can’t undo this.” | Export Archive… · Erase · Cancel |
   | Not syncing, with journals written | “Your journals aren’t synced to a server, so they’ll be deleted permanently. Export an archive first to keep a copy. You can’t undo this.” | Export Archive… · Erase · Cancel |
   | Not syncing, nothing written yet | “This removes the empty journal and your settings from this device.” | Erase · Cancel |

   Erase has the destructive role; Cancel is the cancel role (Escape). On the Mac Return must never choose Erase: the two-button alert has no default button (as Delete All, checked in ios-delete-all-and-settings-2026-10-03.md); in the three-button alert Return may only choose Export Archive… (checked in the real UI). **Export Archive…** opens the existing Export Archive sheet (the same one as File ▸ Export Archive…, with its one-time password check) over Settings; nothing is erased, and the person chooses Erase again afterwards, which counts again.
3. **Erase** → if App Lock is on, the device's own authentication (Face ID, Touch ID, passcode or Mac login password) with the reason **“Erase journals on this device”** (the Mac shows “My Journal is trying to erase journals on this device”). Cancelling or failing it erases nothing and leaves Settings as it was. With App Lock off there is no extra step: the alert is the confirmation, as for Delete Journal.
4. **Erasing** takes well under a second (files are moved aside, then deleted in the background). Writing is paused and saved, and what is waiting is counted again; if it grew since the alert (writing in another window meanwhile), nothing is erased and the alert is shown again with the new count. Settings closes (the iPhone/iPad sheet, the Mac Settings window), every window closes its open sheets and popovers as it does when the app locks, and shows the first-launch screen: **Start a Journal**, **Connect to a Server…**, **Import Archive…**. On the Mac the journal window opens if it was closed. VoiceOver is told the screen changed, so focus moves to it. App Lock and the inactivity lock end with the configuration; no lock screen appears over the first-launch screen.
5. **If erasing fails before anything is removed**: an alert **“Couldn't Erase”** with **“Nothing was removed from this device. Try again.”** and OK. Syncing resumes; the library is unchanged.

## 3. What is erased, and what isn't

**Erased on this device**

- The library: its database (entries, journals, templates, versions, pending changes, conflicts) and attachments, in the folder the configuration names (or the older layout's `journal.sqlite` files and `attachments` folder); earlier libraries this one replaced (`supersededLibraries`) that are still waiting for removal; an unfinished encryption copy (`encryptionUpgrade`); staged import folders and unfinished archive exports in the data folder, and the Export Archive dialog's temporary copies. The exact list of names is fixed while writing is paused, before the commit; nothing is chosen by a name prefix afterwards, so a library started right after erasing can never be caught.
- This library's keychain items, by their exact account names from the configuration: the device key (`keyID`, or the older path-derived name), the server connection with its device token (`connectionKeyID`, or the older `…-connection`), and the accounts of the superseded libraries and the encryption copy above. Through the app's own `Keychain.remove`; no other item and no other app's item is touched, and never an account the current configuration names.
- In-memory secrets: the copied recovery key on the pasteboard (`SensitivePasteboard`), as locking does.
- `configuration.json`: recovery envelope, App Lock, inactivity lock, default journal, last open journal and entry, password-check state.
- Preferences the app owns: Last Synced for this library (removed with the connection) and Format Markdown as You Type (back to its default, on).
- In memory: everything shown, the selection, sync status, the recovery key, unlock state.

There are no on-disk caches: images are decoded in memory, and the server client uses ephemeral sessions without a URL cache.

**Not touched**

- The server and everything on it. No record is deleted there; the only request is the sign-out below.
- Other devices.
- Archives and exported entries the person saved (they're wherever the person put them, outside the data folder).
- On the Mac: a local sync server's files (`local-server.json`, `local-server-process.json`, `local-server.log`, `local-server-data/`, see 4.2), and system data the app doesn't own (Keychain items of other libraries, window positions).
- Device backups (iCloud Backup, Finder or Time Machine backups) made before erasing still hold the library. Libraries without encryption (Access Password, Recovery Code) are plain files until they are deleted, a moment after erasing; encrypted ones are unreadable once the device key is gone.

## 4. Decisions

### 4.1 Sign this device out of the server: yes, best effort

Recommended: after the erase has committed (step 3 of section 5), send the existing `DELETE /v1/devices/<this device>` with the device's own token, in the background, ignoring failures — exactly what Stop Syncing does. The device token is being deleted from this device anyway, so keeping the server's record only leaves a dead “device” in Settings ▸ Devices on the other devices with a credential nobody has. If the server can't be reached, the record stays and another device can remove it in Settings ▸ Devices (that's the existing Revoke Access…); nothing else depends on it. It's sent after the commit so a failed erase never leaves an intact library signed out. The token is only held in memory for it: a sign-out lost to a crash isn't retried, and the token is never written anywhere to make that possible.

Alternatives: not contacting the server at all (leaves the dead device listed); requiring the server to confirm before erasing (makes erasing impossible offline, which is when people often want it).

### 4.2 A Mac that runs the sync server

When this Mac is set up as the sync server (Settings ▸ Sync shows “This Mac”, or a setup that didn't finish), the button is disabled with the footer **“Your other devices sync through this Mac, so its journals can’t be erased here.”** The local server's data is the server's copy of every device's journals, which this feature promises not to touch, and the server only runs with this Mac's library connected to it. Erasing a Mac that hosts the server, and what then happens to the server, is a separate decision for the owner.

### 4.3 Unavailable while

…another operation is replacing or committing to the library (connecting, importing an archive, turning on encryption, an entry action being saved), Delete All is checking or deleting, a save has failed (the entry shows Try Again), or the Mac's local server is starting, stopping or being set up: the button is disabled until it finishes, as Stop Syncing is. Settings isn't available while the app is locked, and the erase checks again that the app isn't locked right before the commit (the inactivity lock can fire while it saves).

## 5. Order of the steps, and failures

The configuration file is the single commit point, as it already is for importing and connecting (`installArchive`, `commitConfiguration`): a library exists for the app exactly when `configuration.json` names it.

1. Check the preconditions again (unlocked, not replacing, configuration present, App Lock authentication from this request).
2. **Pause**: block writing (`vaultReplacement`), save the open writing, stop sync and agent copies in memory (the connection stays in the Keychain), cancel pending saves, mutations, superseded-library removal and Mac server setup. **Count again**; if more is waiting than the alert said, resume and show the alert again. **Fix the exact list** of folders, files and Keychain accounts to remove (section 3).
3. **Commit**: create `erased-<uuid>` in the data folder and move `configuration.json` into it (one rename on the same volume). **If this fails**, remove the empty folder, resume sync and writing, and show “Couldn't Erase”: nothing was removed.
4. **Remove the Keychain items** on the list. A failure doesn't stop the rest; it is recorded for the retry (step 7).
5. **Move every listed folder and file into the erased folder** (renames, before anything else can start), reset the in-memory session to first launch, close the store, and show the first-launch screen.
6. **Delete the erased folder** in the background; remove the app's preferences and the Export dialog's temporary copies; send the sign-out (4.1).
7. If any of 4–6 fails, or the app stops meanwhile, the erased folder keeps the moved `configuration.json`. **At the next launch, before anything is loaded**, the app finishes it from that configuration alone: removes its Keychain items (never one the current configuration names), moves what is still in place by its exact name, then deletes the erased folder. A Keychain item that can't be removed (on the Mac, an older login-keychain copy only the build that made it can delete) is tried at three launches, then left; it's harmless once its library is gone, because every library now records the name of its own connection item.

Why keys after the commit and before the files: before the commit nothing may be removed, because a later failure would leave a library without its key (unopenable without the recovery key, and a library without a password would even get a new key). Right after the commit the library no longer exists for the app, so its key goes first: an encrypted library's content becomes unreadable at once, while the database and attachments are deleted in the background, and an older library's path-named connection item is gone before a new library could look for it. As a second guard, new libraries (Start a Journal, and an archive imported without a library) now record a connection account name of their own, so they never fall back to the older path-derived name.

There is no state in which the old library is partly removed but still opened: before step 3 it is complete; after it, it is no longer named.

## 6. Accessibility

- Standard SwiftUI button, alert and system authentication: VoiceOver reads “Erase Journals and Settings…, button”; the alert's destructive button is announced as such; Dynamic Type and Increase Contrast apply; on the Mac Escape cancels and Return doesn't choose Erase.
- The disabled state (4.2, 4.3) is announced as dimmed; the footer explains why for 4.2.
- After erasing, focus lands on the first-launch screen.

## 7. Tests

- **Erase removes everything and a new library starts** (`JournalTests`, real `AppModel` in a temporary folder, in-memory Keychain): a library with entries, an image, a connection to a fake server and superseded libraries; after erasing: no configuration, folders or Keychain items for it; `store`, `configuration` and the shown state equal a fresh model's; `start()` creates a new library that opens.
- **The warning's count**: unsent entries, unresolved conflicts and changes the server refused are counted, with and without a connection; an untouched new library counts as nothing written; a connection whose last sync failed gets the “couldn't confirm” case; the count is taken again after pausing and a larger count stops the erase.
- **The server**: the fake server receives only `DELETE /v1/devices/<own id>` (and nothing when not connected); no record is deleted; an unreachable server doesn't stop or delay the erase.
- **Failure before the commit**: when the configuration can't be moved, the library, its Keychain items and its connection are unchanged, it opens again and syncs.
- **Interrupted after the commit**: an erased folder left behind is finished at the next load, before a new library is created; its Keychain items are removed, other libraries' items and the current configuration's aren't; a library started right after erasing survives the background deletion; a Keychain removal that fails doesn't let a new library pick up the old connection.
- **Mac**: the local server's files are left in place.
- **App Lock**: a cancelled authentication erases nothing.
- iOS UI test: Settings ▸ Privacy ▸ Erase Journals and Settings… ▸ Erase ▸ the first-launch screen; starting a new journal works. Mac: inspected in a scratch copy with its own data folder.

## 8. For the owner

1. The name and place: “Erase Journals and Settings…” in Settings ▸ Privacy. The reviewer suggested General (where iOS keeps Transfer or Reset); on iPhone that pane is “Writing”, so Privacy keeps one place on every device.
2. Signing this device out of the server when it can be reached (4.1).
3. A Mac that runs the sync server can't be erased this way for now (4.2); the footer says why but offers no way forward.
4. Erasing from the lock screen when the device key and the recovery key are both lost (today only deleting the app starts over there), and while an encryption upgrade waits for a server that never answers, aren't offered. Possible follow-ups.

## 9. Review

An independent design and security review (2026-10-04, given the owner's request, the coordinator's requirements and the first draft) returned **approve with required changes**. It agreed with the commit point, sending the sign-out after it, and keys before files. Required changes and how they were addressed:

1. *“Everything on the server” can be wrong when sync is unhealthy (server reset or replaced, access removed, encryption elsewhere).* A separate “couldn't confirm” case for any sync problem or a library that never synced (2).
2. *The count left out conflicts and refused changes.* The erase counts the whole outbox and the conflicts (a new store query); an entry waiting for its image is in the outbox (2).
3. *Count again after pausing* (another window may be writing): done; a larger count shows the alert again (2, 5).
4. *Never pick files by prefix after the commit*: the list is fixed before the commit, every rename happens before the first-launch screen appears, and only the final delete runs in the background (3, 5).
5. *The fallback connection name and failing Keychain removals*: new libraries record their own connection account; a failed removal doesn't stop the files; the retry is bounded and never removes an account the current configuration names (5).
6. *Incomplete list*: the encryption copy, the Export dialog's temporary copies, and the Mac local-server files explicitly excluded (3).
7. *More busy states*: Delete All, a failed save, local server setup; locked checked again before the commit (4.3).
8. *Mac Return key*: the two-button alert has no default button; the three-button case is checked in the real UI (2).
9. *Close everything open in every window*: windows close their sheets and popovers as on locking (2).

Suggestions taken: the encryption qualifier and device backups under “Not touched”; the sign-out isn't retried and the token isn't persisted; the pasteboard cleared; no host, folder or account names in logs; “caches” removed (there are none); title-case alert title; a footer without the server when not connected; “You can’t undo this.” and how to get the journals back; curly apostrophes; VoiceOver screen change. Left for the owner: General instead of Privacy, the Mac-server dead end, erasing from the lock screen and during a stuck encryption upgrade (8).

## 10. Implementation check (2026-10-04)

- Code: `EraseOperations.swift` (warning, preconditions, authentication, the erase and the list), `LocalErasure.swift` (commit, Keychain removal, moves, deletion, an earlier run's leftovers), `AppModel.clearErasedLibrary()` and `erasingLibrary`, `finishEarlierErasures()` at the start of `load()`, connection names for new libraries in `start()` and the archive import, `EraseSection.swift` in Settings ▸ Privacy, `RootView.closePresentations()` on locking and erasing. JournalCore: `JournalStore.unsentItemCount()`.
- Tests: `EraseLibraryTests` (6, Mac and iOS: everything removed and a new library starts, warnings per state, a larger count stops the erase, a failure before the commit leaves the library that opens again, an interrupted erase finished at the next launch, cancelled authentication), `UnsentItemsTests` (JournalCore: a change waiting for a review counts), `EraseUITests` (iPhone 17: Privacy ▸ Erase ▸ the warning ▸ Erase ▸ the first screen ▸ a new journal starts empty).
- Screenshots: iPhone Privacy with the row, the warning for a library that isn't synced, the first screen after erasing; the Mac Privacy pane (light and dark), rendered from the real views.
- Not verified on the Mac's real window (the screen was locked during this work): the alert on the Settings window, the Return key with three buttons, and the journal window opening after Settings closes. The two-button alert follows Delete All's checked behaviour.
- While Settings closes after erasing, Privacy shows only the erase row (the encryption and App Lock sections describe a library and are hidden without one).
