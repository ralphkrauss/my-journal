---
id: reconnect-to-server
title: Reconnect after the server changed (set up again, connect again, sign in again) (Apple)
spec: flows/reconnect-to-server.md
features: [sync-recovery]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/JournalApp/Model/SyncHealthOperations.swift
  - apps/apple/JournalApp/Model/ConnectionFlow.swift
  - apps/apple/JournalApp/Model/ServerJoining.swift
  - apps/apple/JournalApp/Model/EncryptionUpgrade.swift
  - apps/apple/JournalApp/Views/ConnectionView.swift
  - apps/apple/JournalApp/Views/ConnectionSteps.swift
  - apps/apple/JournalApp/Views/TurnOnEncryptionView.swift
  - apps/apple/JournalApp/Views/DevicesView.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncHealth.swift
  - docs/design/sync-health-and-recovery.md
---

# Reconnect after the server changed (Apple)

There is no reconnect screen. Reconnecting is the ordinary Connect to a Server sheet ([connect-to-server](../screens/connect-to-server.md), mechanics in [connect-to-server](connect-to-server.md)) opened at this device's own server, which checks the server as soon as it appears. What makes it a reconnect is `AppModel.reconnectsOnConnect`, `joinPlan` and `checkReconnection`. States, messages and the pace of automatic sync are in [sync-recovery](sync-recovery.md). Spec: [reconnect-to-server](../../../flows/reconnect-to-server.md).

## Controls

**Choosing the action.** `AppModel.syncStatusAction` (`Model/SyncHealthOperations.swift`) maps `SyncHealth.kind` to one `SyncStatusAction`: `.serverChanged` gives `.setUpServerAgain` for `.serverNotSetUp` and `.connectAgain` for `.serverReplaced`; `.noAccess` gives `.connectAgain`; `.needsYou` (`.signInNeeded`) gives `.signIn`. `SyncStatusAction.connects` is true for exactly these three. `AppModel.perform(_:presentConnection:)` runs the connect closure the caller passes in:

| Where | Closure | Presented over |
| --- | --- | --- |
| Settings ▸ Sync (`SyncNowRows`) | `connect = ConnectionRequest()` | Settings (`.sheet(item:)` in `SettingsView`) |
| Sync Status (`syncMenu` on iPhone and iPad, the AppKit toolbar menu on the Mac) | `model.encryption.signInRequested = true` | the journal window (`EncryptionPresentation` in `TurnOnEncryptionView.swift`: `.sheet` of `ConnectionView()`) |
| Settings ▸ Devices when access was refused | `connect = true` | Settings (`DevicesView`); the button is the same action's title, or `messages.sync.action.connectAgain` |
| Settings ▸ Privacy ▸ Encryption, Turn On Encryption | `Sign In…` (`common.signIn`) | Settings, via `EncryptionSettingsSection` and `takeSignInRequest()` |

**Skipping page 1.** `ConnectionSheet.onAppear` fills `flow.address` from `model.connection?.address` and, when `model.reconnectsOnConnect` and the path is empty, calls `flow.check()`. `reconnectsOnConnect` is `encryption.offersSignIn` (encryption turned on elsewhere, library not encrypted, still connected) or a `syncHealth.kind` of `.needsYou`, `.serverChanged` or `.noAccess`. The sheet then shows page 1 with the busy row `settings.connect.busy.checking` until `check()` pushes a step, or an error row if it fails.

**Which step follows `check()`** (`ConnectionFlow.check`): server not initialised: Set Up Server with focus on the setup code (a setup code is always typed); initialised with a password: Enter {credential} (`.signIn`); initialised without one: Add This Device, with Use a Recovery Code Instead…. Merge Journals is not pushed up front: `asksToMerge` needs `model.joinsByMerging`, which is false while a connection exists. It appears later, from `joinPlan`, only when the server holds a library other than this one (`SyncLineage.serverHoldsLibrary` is false) and `agreedMergeHost` is not this host: `MergeConsentNeeded` is thrown before anything is sent, `ConnectionFlow.askToMerge` pushes `.merge`, and Merge resumes the interrupted `signIn()` or `resumeImport()`.

**Set Up Server Again.** `stepAfterSetupCode`: `.enterPassword` when the library has a password and no recovery key is held (`needsExistingPassword`), else Set Up runs directly. `initializeServer` calls `checkReconnection(address:)` first: a different address throws `messages.connection.reconnectSameServer`; an address where the current token still works (`devices()` succeeds) throws `messages.connection.alreadyConnected`; only an `unauthorized` answer proceeds. It uploads with `uploadLocal: true` (identities and encryption kept) and `commitConnection` writes the new keychain item, then removes the one it replaces.

**Connect Again and Sign In.** `recoverServer(...)` asks the server for access with the typed credential (`recoverVault`) or a one-time recovery code, then `installServerVault`. `joinPlan` decides identity versus merge: an encrypted library on an encrypted server has the same library when the vault key is the same; otherwise `SyncLineage.serverHoldsLibrary(store, client:)`. Joining by identity keeps pending changes; staging is `stageCopy` (a snapshot of the store when the key is the same, or `reencryptForRejoin` for a library that is not encrypted joining an encrypted server, with `encryption.rejoinProgress` driving `EncryptionProgressRow` in the busy row via `ConnectionBusyRow`, `settings.encryption.progress`).

**After success.** `completed = true`, `finished = true` closes the sheet. `installServerVault` ends with `await sync()`; `configureSync` calls `resetSyncHealth()`, so the message, action and Sync Status clear. `SyncActivity.connectionChanged` keys Last Synced by address and device id, so a new access starts with no Last Synced until that first sync finishes.

**Back and Cancel.** `ConnectionFlow.pathChanged` calls `leaveMergeWithoutAgreeing()` when the person goes back from a Merge Journals step pushed by `askToMerge`, which calls `abandon()` and gives up access just granted (a received pairing grant is revoked; `giveUpRetry()` revokes a kept recovery-code grant and discards the staged copy), and resets the step it lands on. For a password sign-in the access is revoked at once when `MergeConsentNeeded` is thrown (`installServerVault`'s catch, since that path does not keep the grant for retry). This answers the question the spec marks unverified ([open-questions.md](../../../open-questions.md), A35): by the source, Back does give the access up; not run.

## Layout

Same sheet as [connect-to-server](../screens/connect-to-server.md): form sheet on iPhone and iPad, 440 to 480 points wide on the Mac. From Settings it sits on the Settings window or sheet; from Sync Status it sits on the journal window.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `sync-reconnect` | Settings ▸ Sync button; Settings ▸ Devices button; Settings ▸ Privacy | none | not while a sync the person started runs |
| `sync-status` | Sync Status menu's action row (toolbar on the Mac, Entry Actions on iPhone and iPad) | none | Sync Status is shown |
| `connect-set-up` | Set Up on Set Up Server or Enter {credential} | Return | code or credential not empty, not busy |
| `connect-sign-in` | Sign In, or Connect on Use a Recovery Code | Return | not empty, not busy |
| `connect-merge` | Merge on Merge Journals | Command-Return | not busy |
| `connect-cancel` | Cancel | Escape | not while installing |

Placement details are in [commands.md](../commands.md). Merge uses Command-Return, never Return, so a merge cannot start before the server's name is read.

## Copy differences

None. The action titles and messages are the same on all devices; `messages.sync.action.setUpServerAgain`, `messages.sync.action.connectAgain` and `common.signIn` are the button titles everywhere.

## Accessibility

As [connect-to-server](connect-to-server.md): errors announced, field errors announced after focus moves, Merge Journals' heading gets VoiceOver focus on the Mac before macOS 26. Settings ▸ Sync's connecting actions end in an ellipsis because they open a sheet. Nothing is announced when the sheet opens or closes.

## Differences between iPhone, iPad and Mac

- Sync Status reaches the sheet from a toolbar menu on the Mac, but from the Entry Actions menu on iPhone and iPad, which exists only with an entry open ([sync-status](../screens/sync-status.md)); Settings ▸ Sync and Settings ▸ Devices are the other entry points on every device.
- The Mac adds a notice in the journal window while the connection runs ([connect-to-server](../screens/connect-to-server.md)).
- Otherwise identical; the logic does not branch on the device.

## Screenshots

None. This flow has no screen of its own; the pages it reuses are captured on iPhone and iPad under [connect-to-server](../screens/connect-to-server.md) (Set Up Server, Enter Master Password, Use a Recovery Code, Server Is Ready). Captures of the states that start a reconnect (an error footer with Connect Again…, the Sync Status menu) do not exist.

## Source files

Model:
- `apps/apple/JournalApp/Model/SyncHealthOperations.swift`: `SyncStatusAction`, `perform`, `reconnectsOnConnect`, `lostAccessHealth`.
- `apps/apple/JournalApp/Model/ConnectionFlow.swift`: `check`, `askToMerge`, `leaveMergeWithoutAgreeing`, set up and sign in.
- `apps/apple/JournalApp/Model/ServerJoining.swift`: `checkReconnection`, `joinPlan`, `installServerVault`, `commitConnection`, `stageCopy`.
- `apps/apple/JournalApp/Model/EncryptionUpgrade.swift` and `EncryptionOperations.swift`: `offersSignIn`, `turnedOnElsewhere`, `reencryptForRejoin`.

View:
- `apps/apple/JournalApp/Views/ConnectionView.swift`, `apps/apple/JournalApp/Views/ConnectionSteps.swift`: the sheet.
- `apps/apple/JournalApp/Views/TurnOnEncryptionView.swift`: `EncryptionPresentation`, the Privacy Sign In… row, `ConnectionBusyRow`.
- `apps/apple/JournalApp/Views/DevicesView.swift`: the Devices entry.

Core:
- `apps/apple/Packages/JournalCore/Sources/JournalCore/SyncHealth.swift`: states, kinds, messages.

Design record: [sync-health-and-recovery.md](../../../../docs/design/sync-health-and-recovery.md).

## Open questions

See [open-questions.md](../../../open-questions.md). A35 (whether Back from Merge Journals gives up access) is answered by the source as described above; confirm by running before closing it.
