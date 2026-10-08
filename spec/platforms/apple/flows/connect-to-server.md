---
id: connect-to-server
title: Connect to a server (Apple)
spec: flows/connect-to-server.md
features: [sync-connect, server-discovery, server-setup, join-with-local-journals, pair-device-scan, pair-device-code, recovery-code-join]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/JournalApp/Model/ConnectionFlow.swift
  - apps/apple/JournalApp/Model/ServerJoining.swift
  - apps/apple/JournalApp/Model/ServerEnvelopeCheck.swift
  - apps/apple/JournalApp/Views/ConnectionView.swift
  - apps/apple/JournalApp/Views/ConnectionSteps.swift
  - apps/apple/JournalApp/Views/MergeJournalsView.swift
  - apps/apple/JournalApp/Views/ScanCodeView.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/ServerClient.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Pairing.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/PairingInvite.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Models.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncHealth.swift
  - docs/design/connection-onboarding.md
  - docs/design/effortless-connection.md
  - docs/design/join-with-local-journals.md
  - docs/design/sync-health-and-recovery.md
  - docs/design/sync-security-2026-09-24.md
---

# Connect to a server (Apple)

How the Apple apps carry out the flow of [connect-to-server](../../../flows/connect-to-server.md). What each page looks like, its controls and copy keys are on the screen note [connect-to-server](../screens/connect-to-server.md); this note is the flow's mechanics: which type decides the next page, what a failure does, and what leaving does. The approving device's side is [pair-device](pair-device.md); reconnecting is [reconnect-to-server](reconnect-to-server.md). Local-network and server address conventions: [platform.md](../platform.md#32-local-network-and-servers).

## Controls

The flow is not a view. `ConnectionFlow` (`Model/ConnectionFlow.swift`, `@MainActor final class ... ObservableObject`) is created once per sheet by `ConnectionSheet` (`@StateObject`). Its `path: [Step]` is the `NavigationStack` path, so pushing a step is `path.append(...)` and going back to page 1 is `path = []`; the next step appears only once the work that leads to it succeeded. `Step` has ten cases: `setUpServer`, `protect`, `choosePassword`, `enterPassword`, `serverReady`, `signIn`, `addThisDevice`, `recoveryCode`, `merge`, `finish`.

State that drives the UI: `busy` (any work), `installing` (setting up, signing in or installing a library; disables Cancel and swipe-to-dismiss), `error` with `errorStep` (an error shows only on the step where it was recorded, `errorMessage(on:)`), `fieldErrors`, `focusRequest`, `invite` (a scanned code), `ticket`, `reveal`, `received`, `confirmed` (pairing), `agreedHost` (merge consent), `createdJournalHere`, `completed`, `finished`. Each long operation is a `Task` held in `operation`; `abandon()` cancels it.

How the pages follow one another, as the code does it:

| From | Trigger | Next |
| --- | --- | --- |
| Page 1 | `check()`: `ServerClient.statusOnFirstContact()` (an ephemeral session with `waitsForConnectivity` and 20-second timeouts, so the system's local-network prompt does not fail the request), then `recoveryParameters()` and `checkServerEnvelope`; protocol version must be 1 | server not initialised: `path = [.setUpServer]`, focus the setup code; initialised and `asksToMerge`: `[.merge]`; initialised without a password (`passwordless`): `[.addThisDevice]`; otherwise `[.signIn]`, focus the field |
| Page 1 | `join(_:)` after the scanner returned a `PairingInvite` | same checks (protocol 1, supports the `pairing-invite` feature, envelope); then `[.merge]` when merging is needed, else `[.finish]` and the pairing request is sent |
| Set Up Server | `continueFromSetupCode()` validates with `CodeEntry`, then, when the server supports `setupCheckFeature`, checks the code with the server | `stepAfterSetupCode`: `.protect` when the device has no library (`model.store == nil`), `.enterPassword` when its journals have a password and no recovery key is held, else Set Up runs here |
| Protect Your Journals | `continueFromProtect()` | `.choosePassword` for Encrypt (unless a journal was already created here), else `setUp()` |
| Choose a Master Password, Enter {credential}, Set Up Server | `setUp()` | on success `completed = true`, `path.append(.serverReady)` |
| Sign In / Recovery Code | `signIn()` | on success `completed = true`, `finished = true` (the sheet closes). The model may throw `MergeConsentNeeded`; `askToMerge` then pushes `.merge` and Merge resumes `signIn()` |
| Add This Device | `beginPairing()` then `awaitApproval` polling | check code appears (`reveal`); after Connect (`confirm()`), `finishImport()` installs and sets `finished` |
| Merge Journals | `confirmMerge()` records `agreedHost` and `model.agreedMergeHost` | the interrupted step: resume closure, `[.finish]` for a scanned code, `.addThisDevice` (no password), else `.signIn` |
| Server Is Ready | Done | `cancel()`, which closes |

A failure stays on the step that started the work: `show(_:)` sets `error` and announces it; field-level failures use `fail(_:_:)`. `ServerConnectionError.serverChanged` resets `path = []` so Continue checks the server again; `returnIfSetUpElsewhere()` checks the server after a setup failure and, if someone else set it up, resets to page 1 with `messages.connection.setUpElsewhere`.

**Model calls** (`AppModel` extension in `Model/ServerJoining.swift`): `initializeServer(address:code:phrase:uploadLocal:)` (sets up, commits the connection, uploads); `recoverServer(address:phrase:uploadLocal:shown:replacingEmptyLibrary:)` (password, recovery key or one-time recovery code); `installPairedVault(...)` (key received from another device). Joining a library with journals makes a staged copy folder (`vault-<uuid>`), merges into it, and switches the configuration only after a full sync (`switchToServerVault`); `stagedVault` holds the copy for Try Again and `replacingVault` blocks other changes meanwhile.

## Layout

The flow's presentation per device is on the screen note. The parts that belong to the flow: iPhone and iPad present everything as one sheet over the app; the Mac presents it over the Settings window (or the journal window from the first-launch screen) and adds the journal window's pause notice while a connection runs. A scanned code needs a camera, so that path exists only on iPhone and iPad.

## Commands and shortcuts

This flow's commands are the buttons of its pages; their placement and shortcuts are in the screen note's table ([connect-to-server](../screens/connect-to-server.md)). The flow-level behaviour:

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `connect-check-server` | Continue, or a nearby server, on page 1 | Return in the address field | address not empty, not busy |
| `connect-set-up` | Primary of the setup steps | Return | not busy, input not empty |
| `connect-sign-in` | Primary of Enter {credential} and Use a Recovery Code | Return | not busy, input not empty |
| `connect-confirm-check-code` | Connect on Add This Device | Command-Return, not Return | check code shown and not confirmed |
| `connect-merge` | Merge on Merge Journals | Command-Return, not Return | not busy |
| `connect-retry` | Try Again and Scan Again | none | after a failure |
| `connect-cancel` | Cancel | Escape | not while installing |

Return and Escape follow the sheet defaults ([commands.md](../commands.md)). Focus after a push: `focusRequest` is set by the flow and taken by the step 400 ms after it appears (`takeRequestedFocus`), so the field receives focus after the push transition.

## Copy differences

None in the flow's own messages (one string per message in `ConnectionFlow.show`). Variants of the pages (`settings.connect.nearby.denied`, the Mac tooltips) are on the screen note. Two flow strings have no key in the catalog: the VoiceOver announcement "New code." when a withdrawn pairing code is replaced, and `codeUsedNotice` ("That code was used. Enter a new one.").

## Accessibility

- `show(_:)` posts every error through `announceForAccessibility` (`NSAccessibility` announcement with high priority on the Mac, `UIAccessibility.post(.announcement)` on iOS); `fail(_:_:)` announces after 300 ms so moving focus to the field does not cut it off.
- The check code announcement (`settings.connect.checkCode.announcement`) is posted in `awaitApproval` when the code is revealed, only when `invite == nil` (typed-code pairing).
- Step focus: first field of each step after the push; Merge Journals moves VoiceOver to the Mac heading row.
- Cancelling or locking is silent. Locking while the sheet is open calls `flow.cancel()` and dismisses.

## Differences between iPhone, iPad and Mac

- Scanned codes (`join(_:)`, Finish on Your Other Device, Scan Again) are reachable only on iPhone and iPad, because `canScan` needs `DataScannerViewController` ([scan-code](../screens/scan-code.md)).
- Mac only: `keepsUnlockedWhile(flow.busy)` stops the inactivity lock while the sheet waits on the server or another device; `ConnectionPauseNotice` explains the paused writing. iPhone and iPad have no inactivity lock and cover the app with the sheet.
- Nothing else in the logic is conditional on the device. The device name sent to the server is `AppModel.deviceName`: the computer name on the Mac, `UIDevice.current.name` on iPhone and iPad.

## Screenshots

None for this page file. The screens of the flow have captures on the screen note ([connect-to-server](../screens/connect-to-server.md)): iPhone and iPad captures of Set Up Server, Protect Your Journals, Choose a Master Password, Server Is Ready, Add This Device, Use a Recovery Code, and (iPad) Enter Master Password. A flow has no screen of its own.

## Source files

Model:
- `apps/apple/JournalApp/Model/ConnectionFlow.swift`: the whole state machine, pairing polling, leaving.
- `apps/apple/JournalApp/Model/ServerJoining.swift`: setup, recover, install, merge, staged copy and Try Again state.
- `apps/apple/JournalApp/Model/ServerEnvelopeCheck.swift`: what a server may take, and the recovery-code form check.
- `apps/apple/JournalApp/Model/ServerBrowser.swift`: nearby servers.

View:
- `apps/apple/JournalApp/Views/ConnectionView.swift`, `apps/apple/JournalApp/Views/ConnectionSteps.swift`, `apps/apple/JournalApp/Views/MergeJournalsView.swift`, `apps/apple/JournalApp/Views/ScanCodeView.swift`: the pages.

Core:
- `apps/apple/Packages/JournalCore/Sources/JournalCore/ServerClient.swift`: server requests (`statusOnFirstContact`, `initialize`, `recoverVault`, `beginPairing`, `pollPairing`, `revoke`).
- `apps/apple/Packages/JournalCore/Sources/JournalCore/Pairing.swift` and `PairingInvite.swift`: pairing cryptography and the scanned code format.
- `apps/apple/Packages/JournalCore/Sources/JournalCore/Models.swift`, `SyncHealth.swift`: shared types and sync states.

Design records: [connection-onboarding.md](../../../../docs/design/connection-onboarding.md), [effortless-connection.md](../../../../docs/design/effortless-connection.md), [join-with-local-journals.md](../../../../docs/design/join-with-local-journals.md), [sync-health-and-recovery.md](../../../../docs/design/sync-health-and-recovery.md), [sync-security-2026-09-24.md](../../../../docs/design/sync-security-2026-09-24.md).

## Open questions

See [open-questions.md](../../../open-questions.md). The `draft` status is because the page has no captures of its own and the Mac and several steps were not captured. Not verified by running; see the screen note.
