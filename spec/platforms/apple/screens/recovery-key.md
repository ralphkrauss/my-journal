---
id: recovery-key
title: Keep Your Recovery Key (early libraries) (Apple)
spec: screens/recovery-key.md
features: [legacy-recovery-key]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/JournalApp/Views/RecoveryView.swift
  - apps/apple/JournalApp/Views/ExportView.swift
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/SensitivePasteboard.swift
  - apps/apple/JournalApp/Model/NewVault.swift
---

# Keep Your Recovery Key (Apple)

Implements [screens/recovery-key](../../../screens/recovery-key.md). The screen exists only for libraries created by early builds with a generated recovery key; the apps no longer create one (the Start a Journal flow always passes a master password or no encryption, see [flows/create-library](../flows/create-library.md)), so it cannot be reached from a fresh install. The views hold the English text as literals; the copy keys named here are the spec's.

## Controls

- **Where it shows.** `RootView.window` in `Views/RootView.swift` chooses, in order: `ProgressView("Opening Journal…")` while `!model.loaded`; `UnlockView` when `model.locked`; the library problem screen; the welcome screen when `model.store == nil`; `RecoveryView(key:)` when `model.recoveryKey` is non-nil; otherwise the main navigation. It is window content, not a sheet, so there is no navigation bar or toolbar.
- **Model.** `AppModel.recoveryKey` is set by `replaceUnconfirmedRecoveryKey()` (`Model/AppModel.swift`), which `finishOpening()` in `Model/LibraryOpening.swift` calls each time an unlocked library whose `configuration.recoveryConfirmed == false` opens. It creates a fresh phrase, re-wraps the key with it and stores the new envelope, so an earlier key stops working. `AppModel.start(password:encrypted:)` also sets it from `NewVault.legacyPhrase`, which is non-nil only for an encrypted library without a password. `confirmRecovery()` sets `recoveryConfirmed`, saves and clears `recoveryKey`; a save failure sets `model.error`, shown by the general error alert in `RootView`.
- **Layout container.** `ScrollView` holding a `VStack(alignment: .leading, spacing: 20)` with `.padding(32)`, `.frame(maxWidth: 520)` and `.frame(maxWidth: .infinity)` so the column is centred; the scroll view fills the window.
- **Heading.** `Text` with `.font(.title2.bold())` (`settings.recoveryKey.title`). No heading trait is set in this file.
- **Warning.** Plain `Text` (`settings.recoveryKey.warning`).
- **The key.** `Text(key)` in `.system(.body, design: .monospaced)`, `.textSelection(.enabled)`, `.padding()`, `.frame(maxWidth: .infinity)`, `.background(.quaternary)`, `.cornerRadius(8)`.
- **Copy Recovery Key.** A default-style `Button` (`settings.recoveryKey.copy`). It calls `SensitivePasteboard.copy(key)`, announces `settings.recoveryKey.copiedNote` the first time (`announceForAccessibility`), and sets `copied`.
- **Save Recovery Key….** `SaveRecoveryKeyButton` in `Views/ExportView.swift` (`settings.recoveryKey.save`): `.fileExporter` with `contentType: .plainText`, a `JournalFile` of the key plus a line feed, default file name from `settings.recoveryKey.filename`. On failure an `.alert` titled `settings.recoveryKey.saveFailed` with the fixed message "Couldn’t save the key. Try again, or choose another location." and an OK button (`common.ok`, `role: .cancel`). The spec says the message is the system's own; the code shows its own text (B44).
- **Copied note.** Shown only while `copied` is true: `Text` in `.callout`, secondary (`settings.recoveryKey.copiedNote`). It stays once shown.
- **Not a backup.** `.callout` secondary `Text` (`settings.recoveryKey.notBackup`).
- **Saved switch.** `Toggle` (`settings.recoveryKey.saved`) with the default style for its context, which is a switch on iOS and a checkbox on the Mac (SwiftUI default outside a `Form`; not captured).
- **Confirm field.** `TextField` with `.textFieldStyle(.roundedBorder)`, placeholder `settings.recoveryKey.confirmField`, `.autocorrectionDisabled()` and, on iOS, `.textInputAutocapitalization(.never)`. It has no `onSubmit`.
- **Continue.** `Button` with `.buttonStyle(.borderedProminent)` (`common.continue`), calls `model.confirmRecovery()`. Disabled unless the toggle is on and the field, trimmed of whitespace and newlines, equals the part of the key after the last "-" (case-sensitive). No `.keyboardShortcut`.
- **Clipboard behaviour.** `SensitivePasteboard.copy` (`Model/SensitivePasteboard.swift`) on iOS writes UTF-8 text with `localOnly: true` (no Universal Clipboard) and an `expirationDate` 120 seconds out. On the Mac it uses `NSPasteboard.prepareForNewContents(with: .currentHostOnly)`, adds the `org.nspasteboard.ConcealedType` marker for clipboard managers, and clears the board after 120 seconds only if the change count is unchanged. `AppModel.lockImmediately` also calls `SensitivePasteboard.clear()` (Mac only does anything).
- **States.** There are no loading, offline or empty states. The only error state is the general alert for a failed save of the confirmation.

## Layout

- **iPhone, iPad, Mac.** Same column: centred, at most 520 points wide, 32 points of padding, scrolling vertically. Nothing switches on size class or platform except autocapitalisation of the field.
- **Dynamic Type.** The column wraps and scrolls; the key `Text` uses `fixedSize(horizontal: false, vertical: true)` so a long key wraps instead of truncating.
- **Mac.** The content fills the journal window (minimum 801 x 420 points).

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `copy-recovery-key` | as in [commands.md](../commands.md) | none | always while the screen shows |
| `save-recovery-key` | as in commands.md | none | always while the screen shows |
| `confirm-recovery-key` | as in commands.md | none (no default button) | switch on and last group typed |

No Return or Escape handling is defined; the Mac menu bar commands that need a library stay as for any window.

## Copy differences

None.

## Accessibility

- The first copy announces `settings.recoveryKey.copiedNote`; later copies are silent.
- The key is ordinary selectable `Text` (`.textSelection(.enabled)`); nothing hides or relabels it.
- The heading has no explicit `isHeader` trait in this file.
- The column scrolls at the largest text sizes.

## Differences between iPhone, iPad and Mac

- The "I've saved" control is a switch on iOS and a checkbox on the Mac: the default `Toggle` style of each platform.
- The field turns off automatic capitalisation on iOS only: the `.textInputAutocapitalization` modifier is iOS API and sits under `#if os(iOS)`.
- The clipboard is cleared by an expiry date on iOS and by a scheduled clear on the Mac, because `UIPasteboard` has expiration and local-only options and `NSPasteboard` has no expiry.

## Screenshots

None. The screen shows only for libraries created by early builds, and the capture script's sample library is a current one, so the screen cannot be captured from it.

## Source files

- View: `Views/RecoveryView.swift` (the screen), `Views/ExportView.swift` (`SaveRecoveryKeyButton`, `JournalFile`), `Views/RootView.swift` (the precedence that shows it).
- Model: `Model/AppModel.swift` (`recoveryKey`, `confirmRecovery`, `replaceUnconfirmedRecoveryKey`), `Model/LibraryOpening.swift` (`finishOpening`), `Model/NewVault.swift` (`legacyPhrase`), `Model/SensitivePasteboard.swift`.
- Core: none specific.

## Open questions

See [open-questions.md](../../../open-questions.md).
