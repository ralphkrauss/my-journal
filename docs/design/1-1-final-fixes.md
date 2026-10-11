# 1.1 final message fixes — 2026-10-11

Status: implemented 2026-10-11 for the 1.1 TestFlight build 21. Approved with changes by the independent review (2026-10-11); the body below includes them, and [Changes after review](#changes-after-review) maps each finding. Design for the mandatory design gate in [AGENTS.md](../../AGENTS.md). Two messages in the 1.1 build give advice that is wrong in 1.1; the owner asked for both to be fixed before the build is tested (2026-10-11). Both are copy and state fixes. Nothing is added to layouts or flows.

## 1. A server without encryption

**Today.** A 1.1 device refuses a server that 1.0 set up without encryption (recovery format 3 or 4), before anything is sent, with `messages.connection.encryptionOff`: "{host} doesn’t use encryption. On a device that has your journals, turn on encryption in Settings, or connect to a server that uses encryption." It appears on page 1 of Connect to a Server, for a typed or nearby address, a scanned code and finishing a pairing, and in Reconnect ([spec/flows/connect-to-server.md](../../spec/flows/connect-to-server.md)).

**Problem.** "Turn on encryption in Settings" only exists in 1.0. In 1.1 every library is encrypted and Settings has no such action, so a person reading the advice on a 1.1 device looks for a control that isn't there. The owner decided (2026-10-09) that 1.1 ignores the case of a 1.0 user with an unencrypted server: 1.0 is released with encryption on by default, and the owner's own journals are encrypted.

**Proposal.** `messages.connection.encryptionOff` becomes:

> {host} doesn’t use encryption. My Journal can only sync with a server that does.

- Keeps the host first (the same capitalisation rule as today: the host's first letter is upper-cased; "This server" when no host is known).
- States the consequence in plain words. It doesn't tell the person to connect to another server: that is what the screen is for.
- No mention of 1.0. The guide ([docs/guide/devices.md](../guide/devices.md)) keeps its paragraph for the rare person who still has a 1.0 device with journals; it quotes only the first sentence of the message, which is unchanged, and its advice for that 1.0 device stays correct.
- Placement, timing, VoiceOver behaviour and states are unchanged: the error on page 1, nothing sent.

## 2. A change from another device that can't be read

**Today.** A record has a conflict whose other version (or local version) this version can't open: its ciphertext doesn't authenticate or decode, as after a server or library mix-up, or reading it fails. Since the 1.1 review fix M1, such a row is not settled and does not stop other rows settling; it is counted with the conflicts **held for a newer version** (`JournalStore.heldConflictIDs()`). So every place that explains a held conflict tells the person to update My Journal:

| Place | Today's text (held for a newer version) |
| --- | --- |
| Settings ▸ Sync footer, extra line | `messages.conflict.kept.updateNeeded`: "Some changes from another device need a newer version of My Journal. Update My Journal to combine them." |
| Notice above the open entry or template | `messages.conflict.kept.noticeUpdate`: "This entry has a version from a newer My Journal. Update My Journal to combine them." |
| Move Entry, Version History (Restore This Version) refused | `JournalLifecycleError.unsupportedJournal`: "Update My Journal to make changes to this journal." |
| Restore of a deleted entry; a deleted journal's Restore | the "needs a newer version" state (`RestoreAvailability.needsUpdate`, `DeletedJournalView.needsNewerVersion`) |

**Problem.** Updating doesn't help: the version can't be read by any version of the app. The advice is wrong, and on an up-to-date device it is confusing. It is rare (it needs damaged data or a key mix-up).

**Proposal.** The store reports the two kinds separately, and each place says what is true. Behaviour does not change: an unreadable row still stays, is never settled, never sent, never deleted, and still blocks the same actions as today (the lifecycle keeps treating both kinds alike).

- `JournalStore` gains `unreadableConflictIDs()` (rows where reading either version fails), and `heldConflictIDs()` keeps returning both kinds so nothing that blocks actions changes. The app derives "needs a newer version" as held minus unreadable.
- New copy, used only for unreadable rows:

| Key | Text | Where |
| --- | --- | --- |
| `messages.conflict.kept.unreadable` | Some changes from another device can’t be read, so they weren’t combined. Nothing on this device was changed. | Extra line in the Settings ▸ Sync footer, like `updateNeeded`; both lines can show. |
| `messages.conflict.kept.noticeUnreadable` | A version from another device can’t be read, so it wasn’t combined with this one. | Notice above the open entry or template, text only, no buttons, same view and accessibility as `noticeUpdate` (it reads for entries and templates alike). |
| `messages.conflict.unreadableChange` | A version of this from another device can’t be read, so this can’t be changed. | The error shown when Move Entry, Restore This Version or a journal change (rename, default template) is refused for an unreadable row; the same alert as today. |

- Restore of a deleted entry or a deleted journal with an unreadable row: Restore stays unavailable as today, but the "needs a newer version" state is not shown; the entry's notice explains why.
- The rating request: an unreadable row counts as a problem, like a held one (unchanged).
- Precedence where a record somehow has both: unreadable wins (updating can't help it).

**Not changed.** The conflict rules, the sync state, Changed on Two Devices, the lifecycle, and every other message.

## 3. Accessibility and platforms

All new text appears in existing views with existing behaviour: the footer is static text, the notice is announced as today, the alert is the app's generic alert. No new controls. Windows and Android follow the same copy keys when they implement conflicts.

## 4. Spec changes (same change as the code)

`spec/copy/en.json`, `spec/messages.md`, `spec/flows/connect-to-server.md`, `spec/flows/resolve-conflict.md` (a row for a version that can't be read), the Apple notes (`spec/platforms/apple/flows/resolve-conflict.md`, `screens/kept-version-notice.md`, `messages.md`), [docs/guide/devices.md](../guide/devices.md) and a note in [1-1-encryption-and-passwords.md](1-1-encryption-and-passwords.md) where the old text was decided.

## 5. The Mac Settings window after locking (owner report on build 21, 2026-10-11)

**Today.** On the Mac, `SettingsView` shows a standard Settings window: a `TabView` whose tabs SwiftUI turns into the window's toolbar (General, Sync, Privacy, Backup, Agent Access). While the app is locked the whole view is replaced by one line, "Unlock My Journal to open Settings." (`settings.locked`), and while the journals can't be opened by "Settings are available once your journals open." The owner turned on App Lock, chose Lock, unlocked and opened Settings again: the window's toolbar showed one blank tile and no tab icons or names. The same code is in 1.0.

**Cause.** Replacing the `TabView` with a `Text` removes the tabs SwiftUI put into the window's toolbar; when the `TabView` comes back in the same window, the toolbar is not rebuilt correctly.

**Proposal (Mac only).** The window always shows the tab view. While locked, or while the journals can't be opened, every tab shows the existing one-line text instead of its controls, centred in the pane, at the pane's usual width; the tabs stay in the toolbar and can be chosen, but show nothing else. No new copy. No journal content and no setting is shown while locked, as today. iPhone and iPad are unchanged (their Settings is a navigation stack in a sheet, which isn't affected).

- Accessibility: the text is the pane's only element; VoiceOver reads the tab names, then the text.
- The window keeps its size rules; the pane is the minimum height of a normal pane, so the window doesn't jump when unlocking.

**Review and implementation (2026-10-11).** The independent review approved with changes, all applied: the panes are removed, not hidden, while unavailable (nothing reachable by VoiceOver or Full Keyboard Access, no pane loaders run); a Connect or Reconnect sheet's request is cleared when the app locks; each locked pane keeps that tab's usual frame, so the window doesn't jump. Closing Settings on lock was rejected: Settings can also be opened while locked, so it wouldn't fix the bug, and Apple's apps don't do it. A temporary check in the Mac screenshot harness (lock with Settings open, unlock; close and reopen Settings while locked, unlock) passed on both the old and the new code, so it didn't reproduce the owner's exact trigger, most likely unlocking with Touch ID while the shrunken locked window was in front, which the harness can't drive. With the fix the window never changes structure or shrinks, which removes that path; its captures show the tabs kept while locked and after unlocking. The owner checks it on build 22.

## Changes after review

The review (Sonnet, 2026-10-11) approved with changes. Each finding and its change:

1. **More places give update advice for a held conflict** (Delete Permanently, Delete All in Recently Deleted, deleting a journal, the Recently Deleted and Unavailable Journals recovery notices, and the lifecycle errors the store throws for a conflict row). The implementation lists every consumer of the held set and every refusal for a conflict row, and gives each an unreadable variant: the one shared line below. Nothing about which actions are refused changes.
2. **"Unreadable" means what the code can tell.** A version whose ciphertext doesn't authenticate or isn't valid base64 is unreadable. A version that authenticates but doesn't decode becomes an unreadable `PortableRecord` that the code can't tell from a newer version's, so it stays "needs a newer version", as before. A database read error is not "unreadable": it is rethrown, and the app keeps the state it had until the next refresh reads again. `heldConflicts()` returns `needUpdate` and `unreadable` per record (a record is unreadable when either version is); `heldConflictIDs()` stays their union, so `unreadable ⊆ held`.
3. **Encryption-off wording.** Changed to two sentences that don't restate the person's goal: "{host} doesn’t use encryption. My Journal can only sync with a server that does." Every literal copy of the old text (app, unit and UI tests, spec, guide, design note) changes with it.
4. **A journal with an ordinary conflict is told to update.** `JournalEditing` checks every conflict and shows `unsupportedJournal`. It now splits three ways: a conflict that settles at the next sync shows the existing "Some changes from another device will finish combining when My Journal next syncs."; an unreadable one shows the shared line; one held for a newer version keeps the update text. The same split applies to deleting a journal.
5. **Copy.** Footer and notice kept as proposed. The refusal line becomes one shared text for every refused action (change, move, restore, delete), `messages.conflict.unreadableAction`: "This can’t be done because a version from another device can’t be read." No line offers a recovery action because there is none in the app; the data is kept, and the spec says so.
6. **Restore with no explanation.** Where Recently Deleted or Unavailable Journals would show "Update My Journal to restore this entry." (and a deleted journal its update line), an unreadable row shows the shared line instead of nothing.
7. **State.** `heldChangesNeedUpdate` stays for the update line and the rating request; a second flag, `heldChangesUnreadable`, drives the unreadable footer line and also counts as a problem for the rating request. A model test covers a damaged row: the unreadable flag is set, the update flag is not, and the entry notice is the unreadable one.
8. **Accessibility.** No new controls. New keys get `context` entries in `spec/copy/en.json`.

Final copy:

| Key | Text |
| --- | --- |
| `messages.connection.encryptionOff` | {host} doesn’t use encryption. My Journal can only sync with a server that does. |
| `messages.conflict.kept.unreadable` | Some changes from another device can’t be read, so they weren’t combined. Nothing on this device was changed. |
| `messages.conflict.kept.noticeUnreadable` | A version from another device can’t be read, so it wasn’t combined with this one. |
| `messages.conflict.unreadableAction` | This can’t be done because a version from another device can’t be read. |

## Implementation notes

- An independent code review (Sonnet, 2026-10-11) found no blockers. Its two should-fix findings were applied: Change Date and Edit Image Descriptions also use the three-way refusal (`AppModel.conflictRefusal(for:)`), and a failed read of the held conflicts keeps the ones already known held instead of clearing them.
- Two places beyond section 2's table use the shared line: restoring a template and the Delete All notice (`DeletionHold.unreadable`, with `library.deleteAll.held.unreadable`).
- A refusal that names one conflicting child (Move Entry, restore) reports the first conflict the store finds; when a journal has both a settling and an unreadable child the text can name the settling one. Nothing is unblocked by it.
