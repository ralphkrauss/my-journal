# Open questions

Everything in the spec that looks unintended, is worded inconsistently, no longer matches its design record, or needs an owner decision. This is the one complete list; the screen and flow files only point here. The spec describes what the Apple app does today and doesn't silently fix these: a client port should follow the spec and the owner's answer, not copy a bug.

Each item names the spec files and the code files involved. Code paths are relative to `apps/apple/JournalApp/`, except those starting with `Packages/`. “Record” means a file in `docs/design/`.

An entry keeps its original text as history. A line in bold at its end says what became of it: **Resolved in build 18** or **Resolved by owner decision** (with the date and the record), **Not a bug**, or “Superseded in 1.1 by simplification X (owner-approved 2026-10-07), still open for 1.0”. The 1.1 simplifications are lettered A to O in [release-1-1-scope.md](../docs/design/release-1-1-scope.md) (owner-approved 2026-10-07). Resolved entries are no longer disagreements between spec and code: the spec was changed to follow the code in the same change.

## A. Likely app bugs

Behaviour that looks unintended, or that differs from a decision or design record that is probably right. Each needs a fix or an explicit decision.

**A1.** The save-failure alert returns after every edit. Each edit retries the save and sets the alert's message again, so dismissing it and typing one more character brings it back; the review of the design said not to repeat announcements on every edit. Consider one alert per failure and the notice afterwards. **Resolved in build 18:** the alert shows when saving first fails and again only for a retry the person asked for; later failures leave the notice and say nothing (audit item #4, record §1.1). Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [flows/save-failure.md](flows/save-failure.md), [messages.md](messages.md). Code: `Model/AppModel.swift`, `Views/RootView.swift`.

**A2.** On the Mac, closing the window or quitting after a failed save shows the app-modal Keep Open alert and also sets the generic alert in the window, so two alerts appear. **Resolved in build 18:** closing a window and quitting save without the generic alert, so only Keep Open shows (audit item #4, record §1.1). Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [flows/save-failure.md](flows/save-failure.md). Code: `Model/WindowSafety.swift`, `Model/AppModel.swift`.

**A3.** After a failed save, Back on iPhone removes the entry's page. The notice with Try Again is visible only after reopening the same entry, which the alert doesn't say, and opening another entry falls back to the list with the alert.

Spec: [flows/save-failure.md](flows/save-failure.md). Code: `Views/CompactJournalNavigation.swift`, `Views/SaveFailureNotice.swift`, `Views/EntryHeaderView.swift`.

**A4.** Raw system text reaches the person at launch. A database error shows its own description (for example “SQLite error 11: database disk image is malformed”) on the lock screen, and a failed key read shows the system's generic description. The sync-health rule says no message shows implementation details; text like `messages.sync.localDataUnreadable`, pointing to Export Archive, would fit. **Resolved in build 18:** database and system errors are mapped to plain messages (`messages.failure.*`) and a library that can't be opened gets its own screen (audit items #1 to #3, record §1.14 and §2.1). The spec describes both. Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [screens/unavailable-content.md](screens/unavailable-content.md), [messages.md](messages.md). Code: `Model/AppModel.swift`, `Model/AppLockOperations.swift`, `Views/UnlockView.swift`.

**A5.** Those launch failures leave the window on the lock screen even when App Lock is off, and its “Unlock with …” button then does nothing, because unlocking with the device needs App Lock. **Resolved in build 18:** a problem state is never locked; the library problem screen replaces the lock screen, except for a missing device key (audit items #2 and #3, record §2.1). Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [screens/unavailable-content.md](screens/unavailable-content.md). Code: `Model/AppModel.swift`, `Views/UnlockView.swift`.

**A6.** An unreadable configuration file looks like a first launch: the welcome screen shows with a generic alert carrying the decoder's text, and Start a Journal then writes a new configuration and library. The old library's files stay on disk but are never opened again. **Resolved in build 18:** unreadable settings show the library problem screen, and Start a Journal, connecting and pairing are refused until the library opens (audit item #3, record §2.1). Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [screens/unavailable-content.md](screens/unavailable-content.md), [screens/welcome.md](screens/welcome.md). Code: `Model/AppModel.swift`, `Views/RootView.swift`.

**A7.** The deletion review shows the system's generic text (“The operation couldn’t be completed. (JournalCore.PermanentDeletionError error 4.)”) for failures it doesn't name, such as a record already deleted permanently or missing. `PermanentDeletionError` has no description, and the generic alert's deletion prompts already handle these cases. **Changed in build 18** (audit item #1, record §1.14): the sheet now shows “Something went wrong. Try again.” (`messages.failure.other`) for a record already deleted permanently or missing, `notDeleted` and `conflict`, which a retry cannot fix; `PermanentDeletionView` maps the same cases to named messages. Still open; recommendation: map them in the review sheet the same way.

Spec: [flows/resolve-conflict.md](flows/resolve-conflict.md), [messages.md](messages.md). Code: `Views/DeletionConflictView.swift` (`handle`), `Model/FailureMessage.swift`, `Views/PermanentDeletionView.swift` (`report`).

**A8.** Pin, Unpin and Move Journal failures always show `messages.generic.pinFailed`, `messages.generic.unpinFailed` or `messages.generic.moveJournalFailed`, including for content from a newer version, for which `messages.library.needsUpdate` exists. Superseded in part in 1.1 by simplification C (version-too-old states say “Update My Journal”; owner-approved 2026-10-07), still open for 1.0. **Resolved in 1.1:** when the failure is a library record from a newer version, Pin Entry, Unpin Entry and Move Journal show `messages.library.needsUpdate` ([1-1-encryption-and-passwords.md](../docs/design/1-1-encryption-and-passwords.md) §5).

Spec: [messages.md](messages.md), [screens/unavailable-content.md](screens/unavailable-content.md). Code: `Model/LibraryOperations.swift`.

**A9.** Network failures while looking up a typed pairing code, or while approving, show the system's own error text (for example “The Internet connection appears to be offline.”) instead of a My Journal message such as `settings.addDevice.unreachable`. **Resolved in build 18:** Add Device maps network errors through the same table as sync (`messages.failure.offline`, `.certificate`, `.unreachable`; audit item #23, record §1.13). Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [flows/pair-device.md](flows/pair-device.md). Code: `Views/AddDeviceView.swift`, `Model/DeviceOperations.swift`.

**A10.** Sync Status after locking shows `messages.sync.waiting` with a state's connect action, while the Settings ▸ Sync footer is empty: locking clears the held message but not the sync state. For states that stop automatic sync, “Waiting to sync” is also misleading, and it can last up to 10 minutes or until the person acts. **Resolved in build 18:** locking keeps the sync state and its message (audit item #5, record §1.2). Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [screens/sync-status.md](screens/sync-status.md), [messages.md](messages.md). Code: `Model/SyncHealthOperations.swift`, `Views/SyncNowRows.swift`.

**A11.** On iPhone and iPad, Sync Status lives in the entry's More menu, which is disabled when no entry is open (the Journals list, an empty journal, a deleted journal). A state that needs the person is then visible only in Settings ▸ Sync. **Reviewed in build 18 and left as is:** Sync Status in the entry menu is the recorded design; a badge on the Settings gear would be new behaviour, left for the owner (audit item #6, record §1.16). This may belong in section D.

Spec: [screens/sync-status.md](screens/sync-status.md), [messages.md](messages.md). Code: `Views/RootView+Toolbar.swift`, `Views/RootView.swift`.

**A12.** The Mac's Sync Status is a single-line menu item, so `messages.sync.localDataUnreadable` (about 150 characters) makes a very wide menu. A wrapping view or a shorter menu text would fit better.

Spec: [screens/sync-status.md](screens/sync-status.md). Code: `Views/Mac/JournalToolbarController.swift`.

**A13.** Temporary sync states retry at once when the app returns from the background, but switching back to an inactive-but-open app (a Mac window behind others, iPad multitasking) retries at once only when the last sync succeeded; while failing it keeps its backoff of up to 5 minutes. The design says “at once”. The Apple page also notes that the loop restarts only when the scene phase leaves the background, so a Mac that is merely deactivated may not re-check a stopped state until relaunch (not run; `platforms/apple/flows/sync-recovery.md`).

Spec: [flows/sync-recovery.md](flows/sync-recovery.md). Code: `Model/SyncSchedule.swift`.

**A14.** When loading devices is refused, Settings ▸ Devices runs a sync to learn why. If that sync ends in a state that isn't about access (offline or busy, because the network changed meanwhile), Devices still shows `messages.sync.accessRemoved` with Connect Again…, which then disagrees with Settings ▸ Sync. Superseded in 1.1 by simplifications E and I (Devices folds into Sync; one Reconnect action; owner-approved 2026-10-07), still open for 1.0.

Spec: [flows/sync-recovery.md](flows/sync-recovery.md), [screens/settings-devices.md](screens/settings-devices.md). Code: `Views/DevicesView.swift`, `Model/SyncHealthOperations.swift`.

**A15.** Review Changes does nothing visible when the save fails. The entry notice saves first; if that fails the sheet doesn't open, and only the save-failure alert explains (and only if it isn't already dismissed). Superseded in 1.1 by simplification H, second step (entries auto-resolve; owner-approved 2026-10-07), still open for 1.0.

Spec: [screens/conflict-review.md](screens/conflict-review.md), [flows/resolve-conflict.md](flows/resolve-conflict.md). Code: `Views/SettingsView.swift` (`ConflictNotice`), `Views/ConflictRouting.swift`.

**A16.** The unsupported-version review offers Export Archive… without saying that a failed save blocks it (the export then reports `messages.save.before.goBack`); only the journal review's own, nearly unreachable, unsupported branch adds the same text beside the controls. Superseded in 1.1 by simplification H, first step (the journal and deletion review forms are dropped; owner-approved 2026-10-07), still open for 1.0.

Spec: [screens/conflict-review.md](screens/conflict-review.md). Code: `Views/ConflictRouting.swift`, `Views/JournalConflictView.swift`.

**A17.** On the Mac the journal review's Cancel or Done has no cancel shortcut, unlike the entry, deletion and unsupported forms, which close with Escape. Superseded in 1.1 by simplification H, first step (the journal review form is dropped; owner-approved 2026-10-07), still open for 1.0.

Spec: [screens/conflict-review.md](screens/conflict-review.md). Code: `Views/JournalConflictView.swift`.

**A18.** On iPhone and iPad, Formatting ▸ Insert ▸ Image… reuses the source last chosen in the Insert Image menu, so it can open the camera or Files, while the menu bar's Image… always opens the photo library. Intended? **Resolved in build 18:** Insert ▸ Image… in Formatting and in the Format menu always opens the photo library (audit item #16, record §1.7); `flows/insert-image.md` says so. Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [flows/insert-image.md](flows/insert-image.md), [screens/format-sheet.md](screens/format-sheet.md). Code: `Editor/WritingAccessory.swift`, `Views/ImagePickerPresenter.swift`.

**A19.** Format menu items (Bold, headings, …) stay enabled while keyboard focus is outside the editor (the entries list, search); choosing one then does nothing, because the handler needs the editor to be first responder. **Resolved in build 18:** the Format group is disabled unless the editor has focus (audit item #19, record §1.9); `commands.md` says so. Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [screens/entry-editor.md](screens/entry-editor.md), [commands.md](commands.md). Code: `AppCommands.swift`, `Editor/NativeEditor.swift`.

**A20.** Image Descriptions doesn't list images in document order: every image on a line of its own comes first, then images inside lines and table cells, so “Image 1, Image 2…” can differ from the entry's order.

Spec: [screens/image-description.md](screens/image-description.md). Code: `Views/ImageDescriptionsView.swift`, `Packages/JournalCore/Sources/JournalCore/DocumentImages.swift`.

**A21.** The sheet that creates a journal from Move Entry, Restore and Version History doesn't check for a taken name, unlike New Journal and Rename. Two journals can get the same name there, and Move Entry then can't choose between them (“Same name as another journal”). **Not a bug (build 18):** `JournalStore.save` refuses a taken journal name on every creation path and the sheet shows the error; duplicates come from earlier versions or sync (record §1.16, audit item #17: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md)). What remains is wording, see B12.

Spec: [screens/destination-journal.md](screens/destination-journal.md), [screens/move-entry.md](screens/move-entry.md). Code: `Views/RecoveryJournalView.swift`, `Model/JournalOperations.swift`.

**A22.** Move Entry lists a journal with an empty name as an empty row; every other journal list shows `common.untitledJournal`. **Resolved in build 18:** an unnamed journal reads “Untitled Journal” in Move Entry (audit item #20, record §1.10). Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [screens/move-entry.md](screens/move-entry.md). Code: `Views/MoveEntryView.swift`.

**A23.** The trailing Delete swipe is offered for any editable entry that isn't deleted yet, including entries in Unavailable Journals, whose context menu offers no Delete Entry. **Resolved in build 18:** the swipe and the menu share one check, so an entry in an unavailable journal is offered no Delete (audit item #8, record §1.4). Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [screens/entry-list.md](screens/entry-list.md). Code: `Views/RootView.swift`, `Views/MenuActions.swift`.

**A24.** The owner decisions ask for Delete and ⌘⌫ in the entries list on the Mac and iPad. Only the Mac has them; on iPad a hardware keyboard has no list shortcut for deleting. **Owner decision, 2026-09-25:** Delete and ⌘⌫ in the entries list on the Mac and iPad ([owner-decisions-2026-09-25.md](../docs/design/owner-decisions-2026-09-25.md), §1 and §8); the iPad part is not built.

Spec: [screens/entry-list.md](screens/entry-list.md). Code: `Views/CommandDeleteKey.swift`.

**A25.** The VoiceOver actions Move Up and Move Down for journals exist only on iPhone and iPad, while the journal-order record asks for them on every platform, including Mac VoiceOver. The Mac has dragging only. **Resolved by owner decision, 2026-10-03:** no Move Up and Move Down on the Mac; reordering there is by drag only, and VoiceOver's actions stay on iOS ([journal-order.md](../docs/design/journal-order.md), Owner decisions). The code matches. (Mac VoiceOver users have drag only; the owner may want to revisit that.)

Spec: [screens/journals.md](screens/journals.md). Code: `Views/JournalSidebarView.swift`.

**A26.** The iPhone Journals search lists results without a Clear Search action, unlike the lists.

Spec: [screens/search.md](screens/search.md). Code: `Views/JournalSearchResults.swift`.

**A27.** Waiting agent requests disappear while the server can't be reached (they show only in the ready state), although the agent-access record says an already loaded list stays visible. **Resolved in build 18:** Requests stay visible while the server can't be reached, once the list has loaded (audit item #13a, record §1.6). Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [screens/settings-agent-access.md](screens/settings-agent-access.md). Code: `Views/ServerAgentsView.swift`, `Model/ServerAgentsController.swift`.

**A28.** Switching an agent to Selected Journals with nothing chosen leaves its previous access in place without saying so on screen; the agent-access record says switching narrows access at once. **Resolved in build 18:** while Selected Journals has none chosen, the detail says the agent can still read all journals, and the approval sheet says to choose one (audit item #13b, record §2.2; `settings.agents.emptyChoice.*`). Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [screens/agent-detail.md](screens/agent-detail.md). Code: `Views/ServerAgentsView.swift`, `Model/ServerAgentsController.swift`.

**A29.** When some images haven't downloaded, an archive export shows the generic `messages.export.archiveFailed` instead of the specific message the archives record describes (“Some images haven’t downloaded. Connect to your server and try again.”).

Spec: [screens/settings-backup.md](screens/settings-backup.md). Code: `Views/ArchiveView.swift`, `Model/DocumentTransferOperations.swift`.

**A30.** The Mac settings window opens on Sync (`settingsTab` defaults to `.sync`) although General is the first tab. No design record says Settings should open on Sync. **Resolved in build 18:** the Mac Settings window opens on General (audit item #22, record §1.12). Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [screens/settings.md](screens/settings.md). Code: `Model/AppModel.swift`, `Views/SettingsView.swift`.

**A31.** Approving a new device with a typed code shows an unlabelled activity indicator. The sync-security record specifies “Adding Device…” and, on the Mac, the help tag and hint “Press Command-Return to approve.”, which the code doesn't have (Merge and Connect do).

Spec: [screens/add-device.md](screens/add-device.md). Code: `Views/AddDeviceView.swift`.

**A32.** The QR code is replaced by a placeholder whenever the app isn't active, including on the Mac when another window is in front, although the effortless-connection review asked that clicking another window on the Mac not drop the code. **Resolved by owner decision, 2026-10-06:** on the Mac the Add Device code is hidden only when the app goes to the background, not when another window is in front (owner decision #12, record §3.3, built in build 18). `screens/add-device.md` says so. Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [screens/add-device.md](screens/add-device.md). Code: `Views/AddDeviceView.swift`, `Views/PairingCodeImage.swift`.

**A33.** A server without check codes shows Get New Code after `messages.pairing.serverOutdated`; the sync-security record says no button, and getting a new code can't help.

Spec: [flows/connect-to-server.md](flows/connect-to-server.md). Code: `Model/ConnectionFlow.swift`, `Views/ConnectionSteps.swift`.

**A34.** When merging stops because this device's journals include items saved by a newer version, the person sees only the generic `messages.connection.mergeFailed`; the specific `messages.import.mergeNeedsUpdate` is wrapped and never shown there. Should it be? **Resolved in build 18:** a refusal to merge because of newer-version journals shows `messages.import.mergeNeedsUpdate` and offers no retry (audit item #11, record §1.5). Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [flows/connect-to-server.md](flows/connect-to-server.md). Code: `Model/ServerJoining.swift`.

**A35.** Back from Merge Journals, reached after Sign In or a pairing (a connected library facing another library), appears to keep the access grant until the sheet closes, while the sync-health record says Back or Cancel gives it up. Not verified by running. **Resolved by owner decision, 2026-10-06:** Back from Merge Journals gives up the one-time grant and the step starts again (owner decision #10, record §3.2, built in build 18; `Model/ConnectionFlow.swift` `leaveMergeWithoutAgreeing`). `flows/connect-to-server.md` says so. Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [screens/connect-to-server.md](screens/connect-to-server.md), [flows/reconnect-to-server.md](flows/reconnect-to-server.md). Code: `Model/ServerJoining.swift`, `Views/MergeJournalsView.swift`.

**A36.** The spec contradicts itself on whether pinning waits for the save. [flows/save-entry.md](flows/save-entry.md) says every action that acts on the open entry first finishes its save, but “Pinning doesn’t wait for the save; it doesn’t change the entry’s content”. [commands.md](commands.md) and [screens/entry-editor.md](screens/entry-editor.md) say each Entry Actions item first saves the open writing, and Pin and Unpin are Entry Actions items. The Apple code decides which is right; the Windows mapping follows flows/save-entry.md (pinning does not wait) and is changed if the answer is the other one. Update after build 18: the Apple code does not wait for the save when pinning (`Model/LibraryOperations.swift`), which matches `flows/save-entry.md`; `commands.md` and `screens/entry-editor.md` say otherwise. The owner confirms before they change.

Spec: [flows/save-entry.md](flows/save-entry.md), [commands.md](commands.md), [screens/entry-editor.md](screens/entry-editor.md), [platforms/windows/screens/entry-list.md](platforms/windows/screens/entry-list.md). Code: `Model/LibraryOperations.swift`.

**A37.** In an agent's detail (Settings ▸ Agent Access), a change to the journals or to Access Ends is saved half a second after the last change, but leaving the page cancels the pending wait, so a change made less than half a second before Done (Mac) or Back (iPhone, iPad) is lost without a word. Return or leaving the name field saves at once. Recommendation: save the pending change when the page closes, or say it was not saved.

Spec: [screens/agent-detail.md](screens/agent-detail.md) (Rules, "Saved half a second after the last change"), [platforms/apple/screens/agent-detail.md](platforms/apple/screens/agent-detail.md). Code: `Views/ServerAgentsView.swift:621` (`onDisappear { saving?.cancel() }`), `:711-718` (`scheduleSave`).

**A38.** The "The passwords don’t match." label under Confirm in Change Password and in Check Your Password (Set New Password) is a computed footer and is not announced to VoiceOver, while the spec says every error is announced. Other errors on both sheets call `announceForAccessibility`. Recommendation: announce the label when it first appears.

Spec: [screens/change-password.md](screens/change-password.md) ("Every error is announced"), [screens/password-check.md](screens/password-check.md). Code: `Views/ChangePasswordView.swift:60,96-98`, `Views/PasswordCheckView.swift:150,173`.

**A39.** On the Mac and iPad, Settings ▸ Devices loads its list when the pane appears and after Add Device closes, but the sheet of Connect Again… or Connect to a Server… has no close handler. After a successful reconnect from this pane the access-lost message and an empty list may stay until the pane is opened again. Read from the source and not run on a device. Recommendation: reload when the sheet closes, as Add Device does.

Spec: [screens/settings-devices.md](screens/settings-devices.md), [flows/reconnect-to-server.md](flows/reconnect-to-server.md). Code: `Views/DevicesView.swift:54-56`.

**A40.** On the Mac the Version and Journal choices in Version History show only their captions ("Version", "Journal") with up-down arrows; the chosen version or journal is not visible until the menu opens. On iPhone and iPad the caption sits above the chosen value, as the spec says. The Mac pop-up appears to take the label's accessibility label as its title, not its content (not established). Recommendation: a control that shows the value on the Mac, such as a pop-up picker with the value as its title.

Spec: [screens/version-history.md](screens/version-history.md) (Version and Journal pickers: "caption above the chosen value"), [platforms/apple/screens/version-history.md](platforms/apple/screens/version-history.md). Code: `Views/HistoryMenu.swift:4-22` (`WrappingMenuLabel`), `:47-61` (`HistoryVersionPicker`), `Views/VersionHistoryView.swift:100,141-152`.

**A41.** On the Mac the privacy cover covers only the journal window. The Settings window is a separate scene without the cover, and sheets are not covered, so with App Lock on and another app in front, Settings and open sheets (for example Add Device with its QR code) stay readable. The spec says every window, including sheets, popovers and alerts, is covered. iPhone and iPad cover all windows with an extra window. Whether the Mac's scene phase leaves active whenever another app is in front was not verified. Recommendation: cover the Settings window too, or record the reason it is exempt.

Spec: [screens/lock-screen.md](screens/lock-screen.md) (Privacy cover), [screens/unavailable-content.md](screens/unavailable-content.md), [flows/app-lock.md](flows/app-lock.md). Code: `JournalApp.swift:24-30` (overlay on the journal window's root view only), `:71` (Settings scene), `Model/PrivacyCover.swift`.

**A42.** On iPhone and iPad the View Source / View Preview button in the keyboard accessory is not dimmed for an entry that can only be shown as source, and has no help text. The toolbar button, the reading bar and the Mac button are dimmed with `common.previewUnavailable`. Recommendation: dim it and add the same help text.

Spec: [flows/source-view.md](flows/source-view.md) ("View Preview is disabled ... for an entry whose stored Markdown can only be shown as source"). Code: `Editor/WritingAccessory.swift:74-81`, against `Views/RootView+Toolbar.swift:52-61`.

**A43.** The Table items of the edit menus (iPhone, iPad) and the Mac cell menu are offered while the entry is read-only. The change is not saved (`InlineTables.commit` returns when not editable), but the grid's own copy of the table is changed, and how long that stays on screen was not verified. The spec says a read-only entry has no structure menu. Recommendation: hide or disable the items when the entry is read-only. **Resolved in 1.1** (with D7): no Table menu is built for a read-only entry, and Format ▸ Table is disabled.

Spec: [flows/edit-table.md](flows/edit-table.md) ("Read-only entry: ... no structure menu"). Code: `Editor/InlineTables.swift:172-173`, `Editor/TablePresentation.swift`, `Editor/InlineTableGridMac.swift:33-36`.

**A44.** On iPhone and iPad, starting a search ends the Journals list's edit mode only on the stacked Journals page. The iPad's list-column search does not end it, although the spec says searching ends edit mode on iPhone and iPad (journal-order owner decision, 2026-10-03). Recommendation: end edit mode from the list column's search too.

Spec: [screens/journals.md](screens/journals.md) (edit mode), [screens/search.md](screens/search.md). Code: `Views/CompactJournalNavigation.swift:44-46`, `Views/RootView.swift:430` (`EntrySearch` in the list column).

**A45.** On the Mac the "writing is paused while encryption is turned on" notice appears without the fade that the connection notice has; the spec says both fade in and out, without animation under Reduce Motion. Recommendation: use the same transition.

Spec: [flows/save-failure.md](flows/save-failure.md) ("they fade in and out"). Code: `Views/TurnOnEncryptionView.swift:369-` (`EncryptionPauseNotice`, no transition), against `Views/SaveFailureNotice.swift:79`.

**A46.** On the Mac before macOS 26, the first page of Connect to a Server (`serverReady`) has no heading row, although the spec says a heading row repeats the title at the top of every step because the sheet has no title bar. Recommendation: show the row on that page too.

Spec: [screens/connect-to-server.md](screens/connect-to-server.md) (Accessibility, "Each step's title is a heading"). Code: `Views/ConnectionSteps.swift:22` (`step != .serverReady`).

**A47.** In the Mac capture of Merge Journal the footer paragraph is cut to one line with an ellipsis in the inset list, so the sentence naming the source and the target is unreadable; iOS wraps it. Taken from the capture, not checked in code. Recommendation: let the footer wrap (a multi-line text or a section footer).

Spec: [screens/merge-journal.md](screens/merge-journal.md). Code: `Views/MergeJournalView.swift:150-152` (`.listStyle(.inset)`), `:157-166` (`footer`).

**A48.** Not verified at runtime: a pasted lone space on the Mac passes the `replacingText` guard, because the paste goes through `shouldChangeText` as an adopting replacement, so it may convert a Markdown marker before it. The spec says pasted text, including a pasted space, never converts. Recommendation: test it, and guard on the paste.

Spec: [flows/markdown-as-you-type.md](flows/markdown-as-you-type.md) (rule K, "pasted text (including a pasted space)"). Code: `Editor/MarkdownShortcutEditing.swift:17`, `Editor/InsertedText.swift:30`.

**A49.** The entry's Review Changes button does not check whether the library is being replaced; the spec enables it only when the app is unlocked and the library is not being replaced. Recommendation: disable it, or let the model refuse.

Spec: [screens/conflict-review.md](screens/conflict-review.md) (Actions: "Review Changes ... unlocked, the library not being replaced"). Code: `Views/SettingsView.swift:237-260` (`ConflictNotice`).

**A50.** On the Mac the library problem screen's window has no title, so the title bar reads “Untitled”; the lock screen and the journal window use `library.app.name` (“My Journal”). Taken from the capture, not checked beyond the source (the screen sets no title). Recommendation: title the window `library.app.name` as while locked.

Spec: [screens/unavailable-content.md](screens/unavailable-content.md), [screens/library-window.md](screens/library-window.md). Code: `Views/LibraryProblemView.swift`, `Views/RootView.swift`.

## B. Copy inconsistencies

The same situation worded differently, wording that no longer matches the product, or text that is never shown. The catalog keeps the text the app shows today.

**B1.** “Save your changes before …”, “Save your entry before …” and “Save your current entry before …” are three wordings for the same situation (20 catalog keys, listed by the record). They could be one. Superseded in 1.1 by simplification B (about 26 save-before messages become two; owner-approved 2026-10-07), still open for 1.0. **Resolved in 1.1:** one typed error, `JournalError.saveRequired`, with two texts: `messages.save.before.tryAgain` in the app's alert, which has a Try Again button, and `messages.save.before.goBack` everywhere else ([1-1-settings-messages-editor.md](../docs/design/1-1-settings-messages-editor.md) §2). The 20 operation-specific keys are gone.

Spec: [flows/save-failure.md](flows/save-failure.md), [messages.md](messages.md). Code: `Model/JournalOperations.swift`, `Model/AppModel.swift`.

**B2.** “Saved but not displayed” has several wordings: “… couldn’t be displayed. Reopen My Journal to try again.” (`messages.refresh.*`, `common.entryMovedNotDisplayed`, `library.recoveryJournal.created`, `library.merge.displayFailed`, `editor.imageDescriptions.savedNotShown`), “… My Journal couldn’t update the view. Reopen My Journal to continue.” (`library.restoreEntry.displayFailed`, `messages.refresh.journalDeletedView`, `messages.refresh.itemsDeleted`), “The date was saved. Reopen My Journal to refresh your entries.”, “Changes saved. The entry couldn’t be reloaded.” and “Your choice was saved, but the journal couldn’t be displayed.” (the conflict reviews).

Spec: [messages.md](messages.md), [screens/conflict-review.md](screens/conflict-review.md), [flows/resolve-conflict.md](flows/resolve-conflict.md). Code: `Model/JournalOperations.swift`, `Views/EntryConflictReview.swift`, `Views/JournalConflictView.swift`, `Views/DeletionConflictView.swift`.

**B3.** “These changes were updated. Review both versions again.” (entry review, `messages.conflict.status.updated`) and “These changes have been updated. Review them again.” (journal and deletion reviews, `messages.conflict.updatedReviewAgain`) say the same thing in two ways. Superseded in 1.1 by simplification H (owner-approved 2026-10-07), still open for 1.0.

Spec: [screens/conflict-review.md](screens/conflict-review.md), [flows/resolve-conflict.md](flows/resolve-conflict.md), [messages.md](messages.md). Code: `Views/EntryConflictReview.swift`, `Views/JournalConflictView.swift`, `Views/DeletionConflictView.swift`.

**B4.** Settings paths are written “Settings > Backup”, “Settings > Privacy” and “Settings > Devices” in some messages (for example `settings.sync.stopSyncing.message`, `messages.connection.encryptionOffOnHost`), while the spec and newer copy use “Settings ▸ …”. Superseded in 1.1 by simplification E (the Settings tabs and paths change; owner-approved 2026-10-07), still open for 1.0. Build 18 added the opposite form in new texts (`Model/FailureMessage.swift`, `SyncHealth.swift` use “Settings ▸ Backup”).

Spec: [messages.md](messages.md), [screens/connect-to-server.md](screens/connect-to-server.md). Code: `Model/ConnectionFlow.swift`.

**B5.** The generic error alert is titled “Journal” (`common.alertTitle`), not “My Journal” or the name of the failed action; the owner decisions ask that copy names the app “My Journal”, and most messages are written as a full sentence for the message field. **Resolved in build 18:** the generic alert is titled “My Journal” and `common.alertTitle` says so (audit item #21, record §1.11). Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [messages.md](messages.md), [screens/entry-editor.md](screens/entry-editor.md). Code: `Views/RootView.swift`.

**B6.** Encryption turned on elsewhere has two texts that can show at the same time, in Settings ▸ Sync and Settings ▸ Privacy: `messages.sync.signInNeeded` (“The server now uses encryption or was replaced…”) and `messages.encryption.turnedOnElsewhere`, which the sync-health record says can be wrong for a replaced server. Superseded in 1.1 by simplification G (every library is always encrypted; owner-approved 2026-10-07), still open for 1.0.

Spec: [flows/sync-recovery.md](flows/sync-recovery.md), [messages.md](messages.md), [flows/reconnect-to-server.md](flows/reconnect-to-server.md). Code: `Packages/JournalCore/Sources/JournalCore/SyncHealth.swift`, `Model/EncryptionUpgrade.swift`.

**B7.** A server that can't be reached has several wordings: sync says “Can’t reach the server right now…”, Connect to a Server says `messages.connection.cannotConnect`, other server requests say `messages.server.unanswered`, and `common.couldntReachHost` and `settings.addDevice.unreachable` word it again (“Couldn’t reach the server. Check your connection.”). Build 18 added “Couldn’t reach the server. Check your connection.” in `Model/NetworkFailureMessage.swift`, equal to `settings.addDevice.unreachable`, and “You’re offline. Check your connection.”.

Spec: [messages.md](messages.md), [screens/add-device.md](screens/add-device.md). Code: `Packages/JournalCore/Sources/JournalCore/ServerClient.swift`, `Views/AddDeviceView.swift`.

**B8.** Pairing errors have separate typed-code and scanned-code wordings (`messages.pairing.*` and the `pairing…` keys of `messages.connection.*`), and they differ in small ways: `messages.pairing.expired` says “This pairing code has expired.” while `settings.addDevice.expired` says “This code has expired.”, and `messages.pairing.inviteUsed` says “… your other device” where the other scanned-code errors say “… your connected device”.

Spec: [messages.md](messages.md), [flows/connect-to-server.md](flows/connect-to-server.md), [screens/add-device.md](screens/add-device.md). Code: `Packages/JournalCore/Sources/JournalCore/Pairing.swift`, `Packages/JournalCore/Sources/JournalCore/PairingInvite.swift`.

**B9.** Rate limiting is worded three ways: `messages.server.rateLimited` (“Too many attempts. Try again in a few minutes.”), `messages.connection.setupCodeRateLimited` (“Too many incorrect codes. Try again in a few minutes.”) and `settings.allowAgent.error.tooManyAttempts` (“Too many attempts. Try again in a minute.”).

Spec: [messages.md](messages.md), [screens/allow-agent.md](screens/allow-agent.md). Code: `Packages/JournalCore/Sources/JournalCore/ServerClient.swift`, `Model/ConnectionFlow.swift`, `Model/EncryptionUpgrade.swift`, `Views/ServerAgentsView.swift`.

**B10.** When the password was changed on the server but not on this device, `messages.password.notSavedLocally` says “Try again to finish.” and `settings.changePassword.error.notSavedRetry` says “Free up space, then try again.”

Spec: [flows/change-password.md](flows/change-password.md), [messages.md](messages.md). Code: `Packages/JournalCore/Sources/JournalCore/Crypto.swift`, `Views/ChangePasswordView.swift`.

**B11.** “No longer available” for a journal has five wordings: `common.journalGone` (“That journal …”), `library.merge.destinationGone` (names the journal), `library.templateChooser.journalGone` (“This journal … Close this and choose a journal.”), `messages.conflict.deletion.journalUnavailable` (“… Reload journals and choose another.”) and `messages.history.chooseJournal` (“Choose an available journal.”). Superseded in part in 1.1 by simplifications L and H (owner-approved 2026-10-07), still open for 1.0.

Spec: [screens/move-entry.md](screens/move-entry.md), [screens/merge-journal.md](screens/merge-journal.md), [screens/template-chooser.md](screens/template-chooser.md), [screens/version-history.md](screens/version-history.md). Code: `Views/MoveEntryView.swift`, `Views/MergeJournalView.swift`, `Views/TemplateChooserView.swift`.

**B12.** Two messages say a journal name is taken: `library.nameTaken.message` (“A journal named “{name}” already exists. Choose a different name.”) and `messages.journal.nameTaken` (without the second sentence).

Spec: [messages.md](messages.md), [screens/journals.md](screens/journals.md). Code: `Views/JournalNameTakenAlert.swift`, `Model/JournalOperations.swift`.

**B13.** The same command has different labels on different surfaces: the File menu says “Export Journals as Markdown…” (`library.menu.file.exportMarkdown`) while Settings says “Export as Markdown…” (`settings.backup.exportMarkdown`); the Help menu says “My Journal Support” and “Source Code on GitHub” while Settings ▸ About says “Support” and “Source Code”.

Spec: [commands.md](commands.md), [platforms/apple/commands.md](platforms/apple/commands.md), [screens/settings-backup.md](screens/settings-backup.md), [screens/settings-about.md](screens/settings-about.md). Code: `AppCommands.swift`, `Views/AboutLinks.swift`.

**B14.** “Image unavailable” is written three ways: `editor.image.unavailable` (“Image unavailable”), `editor.imageDescriptions.imageUnavailable` (“Image Unavailable”, title case) and the accessibility label `editor.image.unavailableAccessibility` (“Image unavailable.”).

Spec: [flows/insert-image.md](flows/insert-image.md), [screens/image-description.md](screens/image-description.md). Code: `Editor/ImagePresentation.swift`, `Views/ImageDescriptionsView.swift`.

**B15.** Several texts exist in code but are never shown: `messages.server.syncRequestFailed`, `messages.server.imageUploadFailed`, `messages.server.imageUnavailable`, `messages.server.revokeFailed`, `messages.server.cancelPairingFailed`, `messages.library.itemUnavailable`, `messages.entry.archiveChanged`, `messages.conflict.journal.chooseOne` (unreachable from the interface), `messages.password.enterMaster` (Create is disabled with an empty field), and the plural forms of the Delete All titles that a single item never reaches. Two are overridden: `messages.connection.invalidRecoveryCode` (shown as `messages.connection.recoveryCodeIncorrect`) and `messages.error.invalidSetupCode` (shown as `messages.connection.setupCodeIncorrect`). Other clients shouldn't copy them as user-facing text; the Apple code could drop or reuse them.

Spec: [messages.md](messages.md), [flows/sync-recovery.md](flows/sync-recovery.md), [screens/conflict-review.md](screens/conflict-review.md), [screens/connect-to-server.md](screens/connect-to-server.md), [flows/create-library.md](flows/create-library.md), [screens/recently-deleted.md](screens/recently-deleted.md). Code: `Packages/JournalCore/Sources/JournalCore/ServerClient.swift`, `Packages/JournalCore/Sources/JournalCore/Store.swift`, `Model/ConnectionFlow.swift`.

**B16.** The undo step after a Markdown shortcut is named with the VoiceOver announcement in sentence case (“Undo Bulleted list”, “Undo Block quote”), while Backspace and the Format menu use title case (“Undo Paragraph”, “Undo Block Quote”).

Spec: [flows/editing-rules.md](flows/editing-rules.md), [flows/markdown-as-you-type.md](flows/markdown-as-you-type.md), [screens/entry-editor.md](screens/entry-editor.md). Code: `Editor/MarkdownShortcutEditing.swift`.

**B17.** The Turn On Encryption notice on the Mac says “… but this Mac couldn’t finish …” while the sheet says “… this device couldn’t finish …”; the encryption record says they are the same message. The access-lost error points to Settings > Devices, where the reconnect button is, though Settings > Sync has the same action. Superseded in 1.1 by simplification G (owner-approved 2026-10-07), still open for 1.0.

Spec: [flows/turn-on-encryption.md](flows/turn-on-encryption.md). Code: `Views/TurnOnEncryptionView.swift`, `Model/EncryptionUpgrade.swift`.

**B18.** The Enter Code footer (`settings.addDevice.codeFooter`) tells the new device to choose Connect to a Server, then Add This Device, but on a server with a password the new device first sees Enter Master Password and must choose Use a Connected Device Instead….

Spec: [screens/add-device.md](screens/add-device.md), [screens/connect-to-server.md](screens/connect-to-server.md). Code: `Views/AddDeviceView.swift`, `Views/ConnectionSteps.swift`.

**B19.** The encryption-off refusal has two wordings: `messages.connection.encryptionOffOnHost` when checking the server and `messages.connection.encryptionOff` when installing a pairing. Should they be one?

Spec: [screens/connect-to-server.md](screens/connect-to-server.md). Code: `Model/ConnectionFlow.swift`.

**B20.** Only Choose a Master Password uses “Show Password”; the other steps say “Show {credential}”, although the connection-onboarding record says every password field has Show Password. Intended?

Spec: [screens/connect-to-server.md](screens/connect-to-server.md). Code: `Views/ConnectionSteps.swift`.

**B21.** Placement and outcome sentences still describe archived versions (“Archived in …”, “will be archived in …”), and the merge footer `library.merge.footer.other` says “including archived and recently deleted ones”, although Archive was removed; “archived” no longer means anything to the person. They appear only for entries archived by an earlier build. Superseded in part in 1.1 by simplification L (the merge footer goes; owner-approved 2026-10-07), still open for 1.0.

Spec: [screens/entry-conflict.md](screens/entry-conflict.md), [flows/resolve-conflict.md](flows/resolve-conflict.md), [screens/merge-journal.md](screens/merge-journal.md). Code: `Views/EntryConflictReview.swift`, `Views/MergeJournalView.swift`.

**B22.** Default Template ▸ lists templates by their display title, which falls back to the template's first line or “New Entry”, while the Restore Settings comparison uses “Untitled Template”. Version History's metadata summary (`JournalMetadataSummary`) shows an empty value for a template with a blank title (`platforms/apple/screens/journal-history.md`). Superseded in 1.1 by simplifications K and M (owner-approved 2026-10-07), still open for 1.0.

Spec: [screens/journals.md](screens/journals.md), [screens/journal-history.md](screens/journal-history.md). Code: `Views/JournalMoreMenu.swift`, `Views/JournalSettingsConfirmation.swift`.

**B23.** The authentication reason in Check Your Password is lower case on every platform (it was written for the Mac's sentence); on iPhone and iPad it reads “set a new password for your journals”. Should iOS capitalise it like the other reasons? Windows proposes the capitalised form for `settings.passwordCheck.authReason` ([platforms/windows/copy-proposals.md](platforms/windows/copy-proposals.md)), because Windows shows the reason as a message, not as the end of a sentence. Superseded in 1.1 by simplification J (Check Your Password folds into Change Password; owner-approved 2026-10-07), still open for 1.0.

Spec: [screens/password-check.md](screens/password-check.md), [flows/forgot-password.md](flows/forgot-password.md). Code: `Views/PasswordCheckView.swift`, `Model/PasswordCheckOperations.swift`.

**B24.** The camera purpose text the system shows (`editor.permission.camera`) is shared with scanning a code to connect a device; the owner decisions proposed “Take photos to add them to your entries.” for taking photos. **Owner decision, 2026-09-25:** the camera text for taking photos is “Take photos to add them to your entries.” ([owner-decisions-2026-09-25.md](../docs/design/owner-decisions-2026-09-25.md), §3). The text now also covers scanning a code, so the owner confirms the combined wording; the project still has the combined text.

Spec: [flows/insert-image.md](flows/insert-image.md). Code: `Views/ScanCodeView.swift`, `Views/ImagePickerPresenter.swift`.

**B25.** When the entry stops being editable, or the library is replaced, while images are being read, `editor.imageImport.left` says the person left the entry, which isn't what happened. **Resolved in build 18:** an entry that only became read-only says `editor.imageImport.unchangeable` instead of “you left the entry” (audit item #18, record §1.8). Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [flows/insert-image.md](flows/insert-image.md). Code: `Editor/ImageInsertionSession.swift`.

**B26.** Windows copy: “choose” becomes “select” for items and controls. [platform.md](platforms/windows/platform.md) (12.3) lists four keys; the mapping files found about twenty more, in three batches that each raised it separately. Keys where a sentence tells the person to pick an item or press a control: `common.journalGone`, `library.merge.destinationGone`, `library.merge.header`, `library.merge.footer.targetNone`, `library.templateChooser.templateGone`, `library.templateChooser.journalGone`, `library.recoveryNotice.legacy`, `library.moveEntry.renameExplanation` (“can’t be chosen”), `library.entryList.empty.noTemplatesHelp`, `messages.image.tooLarge`, `editor.imageImport.cause.mixed`, `settings.addDevice.scanInstructions`, `settings.addDevice.codeFooter`, `settings.connect.addThisDevice.instructions`, `settings.encryption.done.otherDevices`, `settings.sync.stopSyncing.message`, `messages.connection.serverChanged`, `messages.connection.setUpElsewhere`, `messages.sync.pausedForSaveFailure` and `messages.sync.localDataUnreadable`. Draft default: apply it as one family, to every sentence that tells the person to pick an item or press a control, and keep “choose” in titles and prompts that ask for a decision (“Choose a master password”, “Choose a version”), because Microsoft style uses “choose” for deciding between options. Alternatives: keep “choose” everywhere (it reads naturally and matches the Apple text, and the family would be dropped from D21), or change the decision prompts too (“Select a version”). Approve the family together with D21; the rows are in [copy-proposals.md](platforms/windows/copy-proposals.md).

Spec: [platforms/windows/platform.md](platforms/windows/platform.md) (12.3), [platforms/windows/copy-proposals.md](platforms/windows/copy-proposals.md), [platforms/windows/screens/move-entry.md](platforms/windows/screens/move-entry.md), [platforms/windows/screens/merge-journal.md](platforms/windows/screens/merge-journal.md), [platforms/windows/screens/template-chooser.md](platforms/windows/screens/template-chooser.md), [platforms/windows/flows/insert-image.md](platforms/windows/flows/insert-image.md), [platforms/windows/messages.md](platforms/windows/messages.md). Code: none yet.

**B27.** Windows copy: sentences that name a Title Case label. D21 leaves sentences, footers and messages alone, but 41 keys name a command, a place or a feature in Apple title case inside a sentence: 25 name “Recently Deleted” (`library.deleteAll.changed.message`, `library.recoveryNotice.entry`, `messages.conflict.outcome.entry.moveToRecentlyDeleted` and others), and the rest name “Version History”, “This Device”, “Other Device”, “Export Archive”, “Try Again”, “Connect to a Server”, “Add This Device”, “Scan Code”, “Enter Code Instead”, “Sign In”, “Set Up a Server”, “Add Device” or “App Lock”. If the Windows labels are sentence case, a sentence that still says “Recently Deleted” names a label that does not exist. The mapping files hand-wrote about ten of these (the “choose” sentences in B26 and the App Lock sentences in B32) and none of the 25 “Recently Deleted” ones. Draft default (the rule now in platform.md 12.1): a sentence that names a label as an instruction (“select Try again”) uses the label exactly as shown on Windows, and a sentence that names a feature in passing uses lower case (“turn on app lock”); the generator replaces the known label names inside sentences from one list, and the checker fails when a sentence contains a Title Case label that is not on the list. Alternative: write each sentence by hand, which can drift. Decide with D21.

Spec: [platforms/windows/platform.md](platforms/windows/platform.md) (12.1), [platforms/windows/copy-proposals.md](platforms/windows/copy-proposals.md). Code: none yet.

**B28.** Windows copy: Apple technology and device names in sentences beyond the platform.md 12.3 table. `editor.imageDescriptions.intro` names VoiceOver (draft: Narrator); `settings.addDevice.enterCodeInstead.footer` says “For a Mac or a device that can’t scan the code” (draft: “For a computer or a device that can’t scan the code”; the 12.3 table listed this key as “this PC”, but the sentence names the other device, and the table row is corrected); `settings.privacy.appLock.footerInactive` and `settings.privacy.appLock.footerSleepOnly` are Mac-only today and say the Mac sleeps or its screen locks (draft: “when this PC sleeps or is locked”); `library.moveEntry.renameExplanation` says “in the Journals list” (default) or “in the sidebar” (Mac), which on Windows becomes “in the navigation pane”, and “in the Journals list” again at the small width where the pane is a page. Alternatives: a neutral “device” and “list” wording that needs no variant (changes the Apple text, so it needs the owner), or leaving VoiceOver, which is wrong on Windows.

Spec: [platforms/windows/screens/image-description.md](platforms/windows/screens/image-description.md), [platforms/windows/screens/add-device.md](platforms/windows/screens/add-device.md), [platforms/windows/screens/settings-privacy.md](platforms/windows/screens/settings-privacy.md), [platforms/windows/screens/move-entry.md](platforms/windows/screens/move-entry.md). Code: `Views/ImageDescriptionsView.swift`, `Views/AddDeviceView.swift`, `Views/InactivityLockSettings.swift`.

**B29.** Windows copy: the window title. Apple shows the collection name and a count in the title bar; Windows shows the app name there. **Draft default, the review's recommendation: the window's own title (taskbar tooltip, Alt+Tab, Task View, Narrator, window pickers) stays `library.app.name` in every state**, with no composed title and no new key. A window title is readable by every process (Task Manager, the taskbar, window pickers in Teams, Zoom and the Snipping Tool, accessibility tools, Recall's metadata), and a journal called “Therapy” is more private than the text that capture exclusion hides; the Settings page does not change it either. Alternatives: the Windows convention “document - app”, which here would name a private category (one new key, “{name} - My Journal”, with {name} the collection’s name or “Settings” (`settings.title`), only as an off-by-default Privacy setting), or only the collection name. Decide with D28.

Spec: [platforms/windows/screens/library-window.md](platforms/windows/screens/library-window.md), [platforms/windows/screens/settings.md](platforms/windows/screens/settings.md), [platforms/windows/platform.md](platforms/windows/platform.md) (2, 20). Code: none yet.

**B30.** Windows copy: strings that are never shown, and how the catalog says so. The mapping files drop these because the control or the platform makes them unnecessary: `library.templateChooser.title`, `library.templateChooser.popoverTitle` (the flyout has no title or Cancel), `editor.insertImage.chooseFile` (the Insert image button opens the picker at once), `messages.writingPaused.showConnection`, `messages.writingPaused.showProgress` (the flow’s page is modal and cannot be left while the work is unfinished), `library.nameTaken.title`, `library.nameTaken.message` (the name field shows `messages.journal.nameTaken` itself), `editor.format.state.on`, `editor.format.state.off`, `editor.format.state.mixed`, `common.format`, `editor.format.close`, `editor.format.moreHeadings` (Narrator speaks toggle state; the formatting bar has no header, close button or More headings sub-menu), `library.toolbar.editorOnly.help`, `library.toolbar.editorOnly.helpActive` (no header button), `settings.locked` (the lock page replaces the window), `settings.lock.turnedOff.title`, `settings.lock.turnedOff.passcodeRemoved` (App lock pauses instead of turning itself off, D42), `messages.encryption.background` (desktop apps are not suspended), `settings.lock.pinRetired`, `settings.lock.turnedOff.pinRetired`, `settings.sync.footer.formerMacServer`, `settings.sync.footer.learnMore`, `settings.erase.footerFormerServer`, `settings.connect.nearby.denied`, the scan-code strings, `settings.recoveryKey.*`, `editor.announce.savedToPhotos` and the camera and photo-library strings of 12.3. The catalog has no way to say “this platform never shows this key”, so a client cannot tell a missing string from a deliberate omission. Draft default: a `"windows": null` variant (or a short list in `copy/`), checked so that a key a Windows mapping file calls “not shown” is marked and a marked key is called “not shown” somewhere; the checker does not accept `null` yet. Alternative: leave the catalog alone and keep the lists only in the mapping files. D21 decides the variant shape (a platform-named variant, not the casing-named `sentence`, because “not shown” is a platform fact); this needs the same decision for the Android port.

Spec: [platforms/windows/copy-proposals.md](platforms/windows/copy-proposals.md), [copy/en.json](copy/en.json). Code: none yet.

**B31.** Windows copy: the find bar. Windows has no system find bar, so the app draws one and needs new strings: Find in entry, Replace, Previous match, Next match, Replace all, “{current} of {total}”, No matches and Close find. They are proposed in [copy-proposals.md](platforms/windows/copy-proposals.md) as new keys under `editor` and are not in the catalog; they belong to the behaviour in D37 and are decided with it.

Spec: [platforms/windows/screens/entry-editor.md](platforms/windows/screens/entry-editor.md). Code: none yet.

**B32.** Windows copy: Windows Hello strings for App lock. Changed: `settings.privacy.appLock.noPasscode` (“To use app lock, set up Windows Hello in Settings > Accounts > Sign-in options.”) and `settings.privacy.appLock.unavailable` (“App lock isn’t available on this PC.”). New: a policy state, “App lock isn’t available because your organization turned off Windows Hello.”, a link, “Open Sign-in options”, that opens `ms-settings:signinoptions`, and, for the paused bar of D42, a title (“App lock is paused”) and three reason messages (Windows Hello not set up, not available right now, turned off by an organization), all in [copy-proposals.md](platforms/windows/copy-proposals.md). `settings.lock.turnedOff.passcodeRemoved` is no longer used on Windows (App lock pauses instead of turning itself off). Needed by D25 and D42; decided with them. “App lock” is lower case inside a sentence (B27).

Spec: [platforms/windows/screens/settings-privacy.md](platforms/windows/screens/settings-privacy.md), [platforms/windows/screens/lock-screen.md](platforms/windows/screens/lock-screen.md), [platforms/windows/flows/app-lock.md](platforms/windows/flows/app-lock.md). Code: none yet.

**B33.** Windows copy: the capture switch in Settings > Privacy (D28). Draft: title “Hide from screenshots and screen sharing”, description “My Journal appears blank in screenshots, screen recordings and screen sharing, and Windows Recall doesn’t save it.”, on by default **pending the accessibility spike of D28** (if Windows Magnifier, Narrator or Quick Assist fail with the window excluded, the default becomes off). Decided with D28.

Spec: [platforms/windows/screens/settings-privacy.md](platforms/windows/screens/settings-privacy.md). Code: none yet.

**B34.** Windows copy: relative times. Windows has no relative-time formatter, so the app builds “5 minutes ago” and “2 hours ago” for Last synced, Last used, Added and agent request times. Draft default: two new plural keys, “1 minute ago” / “{count} minutes ago” and “1 hour ago” / “{count} hours ago”, in full words everywhere, so the Mac’s abbreviated “2 min. ago” is not copied. Alternative: the abbreviated form, or the date and time only. The spec’s own rule is “the platform’s relative time in full words”, so the draft follows it.

Spec: [platforms/windows/screens/settings-sync.md](platforms/windows/screens/settings-sync.md), [platforms/windows/screens/agent-detail.md](platforms/windows/screens/agent-detail.md), [platforms/windows/screens/settings-agent-access.md](platforms/windows/screens/settings-agent-access.md), [platforms/windows/screens/settings.md](platforms/windows/screens/settings.md). Code: none yet.

**B35.** `messages.library.deviceKeyUnavailable` says “Use your recovery key to unlock your journals”, but its context says the lock screen asks for the password or the recovery key, and a person with an encrypted library usually has the master password at hand and may never have saved a recovery key. Draft Windows text: “Your device key is unavailable. Use your master password to unlock your journals.” On Windows this state is common (restore, new PC, reinstall; see D25), so the sentence matters more there. Alternative: change the shared text for every platform (“Use your master password or recovery key to unlock your journals.”), which also fixes the Apple app; that is the owner’s call.

Spec: [platforms/windows/screens/lock-screen.md](platforms/windows/screens/lock-screen.md), [platforms/windows/screens/unavailable-content.md](platforms/windows/screens/unavailable-content.md). Code: `Model/LibraryProblem.swift`, `Views/UnlockView.swift`.

**B36.** Windows copy: pickers. With a one-file archive (D29, the draft default) the Open and Save pickers use the system's own buttons and a file that is not an archive uses `settings.archiveImport.error.damaged`, so only the Markdown export, which is many files and keeps a folder picker, needs a commit button the spec does not have: “Save here”. Only if the owner keeps the archive a folder (D29's alternative) are two more strings needed: “Select archive” (import) and “This folder isn’t a My Journal archive.” for a folder that does not contain an archive. They are not the Apple strings.

Spec: [platforms/windows/flows/import-archive.md](platforms/windows/flows/import-archive.md), [platforms/windows/flows/export-archive.md](platforms/windows/flows/export-archive.md), [platforms/windows/flows/export-markdown.md](platforms/windows/flows/export-markdown.md), [platforms/windows/screens/archive-import.md](platforms/windows/screens/archive-import.md). Code: none yet.

**B37.** Windows copy: the OneDrive question. Two files drafted different words for the same sentence (“This folder is synced by OneDrive, and the files aren’t encrypted.” and “This folder syncs with OneDrive, and the files aren’t encrypted.”). Draft default: “This folder syncs with OneDrive, and the files aren’t encrypted.”, which is Microsoft’s own phrasing, as the content of the dialog of D46, with a title (“Export to a OneDrive folder?”) and the buttons “Choose another folder” and “Export here”; Cancel is `common.cancel`. The behaviour is D46. **Resolved by owner decision, 2026-10-07:** D46's dialog is not built, so these strings are not needed and are removed from the Windows copy proposals.

Spec: [platforms/windows/screens/settings-backup.md](platforms/windows/screens/settings-backup.md), [platforms/windows/flows/export-markdown.md](platforms/windows/flows/export-markdown.md). Code: none yet.

**B38.** Windows copy: the update link. The Apple messages say “Update My Journal” and the OS does the rest; on Windows the Microsoft Store updates the app, so a message that asks for an update needs a link that opens the Store’s updates page. Draft default: a new Windows-only link “Get updates” on `messages.sync.appUpdateNeeded`, `settings.archiveImport.error.newerVersion` and the unsupported conflict form. The behaviour is D51.

Spec: [platforms/windows/messages.md](platforms/windows/messages.md), [platforms/windows/screens/sync-status.md](platforms/windows/screens/sync-status.md), [platforms/windows/screens/archive-import.md](platforms/windows/screens/archive-import.md), [platforms/windows/screens/conflict-review.md](platforms/windows/screens/conflict-review.md). Code: none yet.

**B39.** The save-failure keys are named `messages.save.mac.*` (title, Keep open) but every platform with a window shows them, and Windows uses them with “this PC” (platform.md 12.3). A key name that says Mac on a Windows screen is only a naming problem, not a copy change; rename or leave it. Draft default: leave the names and say so in the files that use them.

Spec: [flows/save-failure.md](flows/save-failure.md), [platforms/windows/flows/save-failure.md](platforms/windows/flows/save-failure.md). Code: `Model/WindowSafety.swift`.

**B40.** Windows copy: strings added by the design review. Three small additions follow from owner questions and need new strings, all in [copy-proposals.md](platforms/windows/copy-proposals.md): a note under the Devices list that this PC shares its name with the server and the person’s other devices (D45); a one-time warning when the device key could not be saved again (D43); and the Backup page’s “Last exported {date}” and “Not exported yet” (D22). Each is a new key; none is in the catalog, and each is decided with its question.

Spec: [platforms/windows/screens/settings-devices.md](platforms/windows/screens/settings-devices.md), [platforms/windows/screens/lock-screen.md](platforms/windows/screens/lock-screen.md), [platforms/windows/screens/settings-backup.md](platforms/windows/screens/settings-backup.md). Code: none yet.

**B41.** Windows copy: Back with unsaved descriptions (D39). The Save changes dialog needs a title (“Save description changes?”, worded like the existing `editor.imageDescriptions.discardTitle`) and a button, “Don’t save”; Save is `common.save` and Cancel is `common.cancel`. Draft default as above; decided with D39.

Spec: [platforms/windows/screens/image-description.md](platforms/windows/screens/image-description.md). Code: none yet.

**B42.** Three system permission texts in `project.yml` have no copy key. `NSFaceIDUsageDescription` ("Unlock your journals and confirm adding a device.", iPhone and iPad) and `NSLocalNetworkUsageDescription` ("Find and sync with your server on your local network.", iPhone, iPad and Mac) are shown by the system, but only the camera and Add to Photos texts have keys (`editor.permission.camera`, `editor.permission.photosAdd`). A port that copies the catalog cannot find them. Recommendation: add keys for both, noting they are Info.plist values. (Superseded if the 1.1 server cleanup, simplification O, removes local network discovery.)

Spec: [flows/insert-image.md](flows/insert-image.md), [screens/lock-screen.md](screens/lock-screen.md), [screens/connect-to-server.md](screens/connect-to-server.md), [copy/en.json](copy/en.json). Code: `apps/apple/project.yml:30,76,79`.

**B43.** Authentication reasons are written as literals and cased in code. The Mac text is made by lowercasing the first letter (`AppModel.authenticationReason`, because the system prompt reads "My Journal is trying to ..."), except Add Device, which writes both cases by hand, and Check Your Password, whose reason is lower case on every device (see B23). At the time of the spec commit "Export an archive of your journals" and "Restore journals on this device" had no keys; the rest have keys with a `mac` variant. Recommendation: one rule (key every reason, explicit `mac` variant, sentence case on iOS) and settle it with B23.

Spec: [flows/app-lock.md](flows/app-lock.md), [flows/export-archive.md](flows/export-archive.md), [screens/archive-import.md](screens/archive-import.md), [platforms/apple/flows/app-lock.md](platforms/apple/flows/app-lock.md). Code: `Model/AppLockOperations.swift:72-79,121,292`, `Model/DocumentTransferOperations.swift:151`, `Model/ArchiveInstalling.swift:39`, `Model/MarkdownExportOperations.swift:33-36`, `Views/AddDeviceView.swift:451-456`, `Model/PasswordCheckOperations.swift:48`.

**B44.** Two failures show a fixed sentence where the spec says the alert shows the system's message. Saving the recovery key shows "Couldn’t save the key. Try again, or choose another location." (alert title `settings.recoveryKey.saveFailed`), and a failed file picker in Settings ▸ Backup shows the fixed text of `ArchiveImportView.couldntOpen` under `settings.backup.openFailed`. Neither sentence has a key. The fixed sentences are better than raw system text (build 18 plain failure messages). Recommendation: change the spec to the fixed sentences and add keys.

Spec: [screens/recovery-key.md](screens/recovery-key.md), [screens/settings-backup.md](screens/settings-backup.md), [flows/import-archive.md](flows/import-archive.md). Code: `Views/ExportView.swift:61`, `Views/ArchiveView.swift:279-283`.

**B45.** `library.templateChooser.popoverTitle` ("Use a Template…") is described as the title of the Mac popover, but the popover shows no title. The string is only the tooltip and VoiceOver label of the toolbar button that opens it. Recommendation: say so in the spec, or show a title.

Spec: [screens/template-chooser.md](screens/template-chooser.md). Code: `Views/TemplateSuggestionView.swift:91`, `Views/MacFormattingButton.swift:36-45`.

## C. Design records lagging the code

The code, not the record, looks right, or the record names something that no longer exists. The record needs updating; the spec follows the code.

**C1.** The owner decisions say a journal with changes to review gets an alert “This journal has changes that need review.” with Review Changes and Cancel. The app showed the error alert with the text “This journal has changes that need review before it can be deleted.” and OK only. **Resolved in build 18:** Delete Journal and Delete Permanently on a record with changes to review show the “Can’t Be Deleted” alert with Review Changes and Cancel (audit item #7, record §1.3; `messages.deleteConflict.*`). The spec describes it. Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [screens/journals.md](screens/journals.md). Code: `Views/JournalDeletionPrompt.swift`.

**C2.** `JournalsSheet.swift` and `JournalSettingsView.swift` (a Journals form with name fields, Default Template pickers, Deleted Journals and its own New Journal section) are still in the app, but nothing presents them; the owner decisions asked to remove this pane. Its copy is left out of the catalog. **Owner decision, 2026-09-25:** remove the unreachable Journals settings pane ([owner-decisions-2026-09-25.md](../docs/design/owner-decisions-2026-09-25.md), §10); not yet done. Superseded in 1.1 by simplification A (dead code, owner-approved 2026-10-07), still open for 1.0. **Resolved in 1.1:** both files, `RootView.managedJournal`, `AppModel.journalsPresented` and `AppModel.journalRecords` are removed.

Spec: [screens/journals.md](screens/journals.md), [screens/conflict-review.md](screens/conflict-review.md).

**C3.** The Restore Journal view still has a Delete Journal mode (“Delete Journal”, “{count} will move to Recently Deleted. Entries from other devices will appear there when they sync.”), but nothing opens it any more: journals are deleted with the standard alert. Its copy is left out of the catalog. Superseded in 1.1 by simplification A (dead code; owner-approved 2026-10-07), still open for 1.0. **Resolved in 1.1:** `JournalLifecycleView` only restores (its `restoring` parameter and the Delete Journal mode are removed); the model functions `prepareJournalDeletion` and `deleteJournal` stay for the Delete Journal alert.

Spec: [screens/restore-journal.md](screens/restore-journal.md). Code: `Views/JournalLifecycleView.swift`.

**C4.** The effortless-connection record specified a capture method that works on every supported device. The code uses the system's live scanner only, so some older devices show no Scan Code.

Spec: [screens/scan-code.md](screens/scan-code.md). Code: `Views/ScanCodeView.swift`.

**C5.** The effortless-connection record says the approving device asks the server every 3 seconds; the code waits 4.

Spec: [screens/add-device.md](screens/add-device.md). Code: `Views/AddDeviceView.swift`.

**C6.** The effortless-connection record shows the Tailscale hint for every unreachable scanned-code server; the code shows it only for `.ts.net` hosts.

Spec: [flows/connect-to-server.md](flows/connect-to-server.md). Code: `Model/ConnectionFlow.swift`.

**C7.** `settings.addDevice.httpOnly` and `settings.agents.reach.local` (“this Mac”) were written for the server bundled on the Mac, which was removed; they now apply only to a server the person runs on the same computer. Still needed?

Spec: [screens/add-device.md](screens/add-device.md), [screens/settings-agent-access.md](screens/settings-agent-access.md). Code: `Views/AddDeviceView.swift`, `Model/ServerAgentsController.swift`.

**C8.** The sync-security record puts the Change Password explanation in the first section's footer and requires 12 characters; the code shows it as a row and accepts any non-empty password (later records dropped the minimum). **Resolved by owner decision, 2026-09-29:** a master password has no minimum length and the 12-character rule is removed from Change Password ([connection-onboarding.md](../docs/design/connection-onboarding.md), Owner decisions after testing). Only the sync-security record is out of date.

Spec: [screens/change-password.md](screens/change-password.md). Code: `Views/ChangePasswordView.swift`.

**C9.** The app-lock record shows the switch off and disabled without a passcode, with no Lock My Journal. The code keeps the switch enabled while App Lock is on and shows Lock My Journal whenever it's on, which never leaves a dead end. The code looks intended; confirm and update the record.

Spec: [screens/settings-privacy.md](screens/settings-privacy.md). Code: `Views/AppLockSettings.swift`.

**C10.** `sync-now-and-done.md` and `menus-and-popovers.md` define today's Sync Now, Done, Format panel and popover behaviour but aren't in the `docs/design/README.md` index. Also, Check Again syncs exactly like Sync Now; the sync-health record describes a separate check that doesn't exist. `docs/design/README.md` still calls the build 18 record “waiting for its independent review (not built yet)”, though build 18 shipped.

Spec: [screens/settings-sync.md](screens/settings-sync.md), [screens/entry-editor.md](screens/entry-editor.md). Code: `Views/SyncNowRows.swift`, `Views/FormattingPopover.swift`.

**C11.** The pre-release record required every Format option to show without scrolling on the phone; the owner reversed this on 2026-09-30 (`menus-and-popovers.md`, “iPhone panel height”). The panel follows the later decision.

Spec: [screens/format-sheet.md](screens/format-sheet.md). Code: `Views/MobileFormattingPresenter.swift`.

**C12.** The erase-device record still describes blocking erase on a Mac that runs the server; that server was removed, and the code instead keeps the old server's files and adds a footer sentence. The record should be updated.

Spec: [flows/erase.md](flows/erase.md), [screens/settings-erase.md](screens/settings-erase.md). Code: `Model/EraseOperations.swift`, `Model/FormerMacServer.swift`.

**C13.** The client-only record ends the authentication reason for Export as Markdown with a full stop; the code has none.

Spec: [flows/export-markdown.md](flows/export-markdown.md). Code: `Model/MarkdownExportOperations.swift`.

**C14.** The save-failure-retry record's “Couldn’t save changes. Keep Journal open.” and Export Entry… no longer exist; the app says `common.saveFailed` and offers only Try Again.

Spec: [flows/save-failure.md](flows/save-failure.md). Code: `Views/SaveFailureNotice.swift`.

**C15.** “Pairing was canceled.” on the approving device, when the new device cancels, needs a server change first (pre-release-ui record §9) and isn't implemented; the approving device shows the expiry or no-response message instead.

Spec: [flows/pair-device.md](flows/pair-device.md). Code: `Views/AddDeviceView.swift`, `Packages/JournalCore/Sources/JournalCore/Pairing.swift`.

**C16.** The Stop Syncing confirmation is described as an action sheet on phone and a dialog on the computer, with a visible title. The code uses the standard confirmation dialog, and iOS 26 draws it as a popover anchored to the button (seen in the captures); the earlier-system form was not captured. Recommendation: say "the system's confirmation, with a visible title" and not name the form.

Spec: [flows/stop-syncing.md](flows/stop-syncing.md), [screens/settings-sync.md](screens/settings-sync.md), [platforms/apple/flows/stop-syncing.md](platforms/apple/flows/stop-syncing.md). Code: `Views/SyncNowRows.swift:52-60`.

**C17.** The Last Synced rule says the time is forgotten when the library connects to another server. The code also forgets it when the device stops syncing (the connection becomes none), so a later reconnect to the same server starts without it. Recommendation: say that Stop Syncing forgets it as well, or keep it per server.

Spec: [screens/settings-sync.md](screens/settings-sync.md) (Last Synced rule), [flows/stop-syncing.md](flows/stop-syncing.md). Code: `Model/SyncSchedule.swift:285-297` (`connectionChanged`).

**C18.** The spec puts 24 pt margins around the text column "on the computer". The code applies them on every device. Recommendation: say "on every device", or decide a phone margin.

Spec: [screens/entry-editor.md](screens/entry-editor.md) (layout). Code: `Views/RootView.swift:831,843,892`.

**C19.** The spec says the Format header with its close button is for the phone panel only. The code also shows it in the iPad popover. Recommendation: say iPhone and iPad.

Spec: [screens/format-sheet.md](screens/format-sheet.md) (Header). Code: `Views/FormattingPopover.swift:16-22,45-60` (all of `#if os(iOS)`).

**C20.** The spec puts the list's search field in the bottom bar on iPhone and iPad. On iPad it sits under the list title in the column (the system's place for a search field in a regular-width column; the iPad captures show it). Recommendation: update the spec for iPad.

Spec: [screens/search.md](screens/search.md). Code: `Views/RootView.swift:430`.

**C21.** The agent-access design record says the no-server state offers "Set Up Sync…"; the code and `copy/en.json` say "Connect to a Server…". The catalog is current; the record is not.

Spec: [screens/settings-agent-access.md](screens/settings-agent-access.md). Code: `Views/ServerAgentsView.swift`.

**C22.** The Mac app still requested `com.apple.security.network.server` after it stopped running a server, which App Review flags as an entitlement without matching functionality. **Resolved in build 19:** the entitlement was removed (commit 089560c); the Mac app only makes outgoing connections. The Mac test hosts alone are signed with `apps/apple/Signing/JournalMac-Tests.entitlements`, which adds `network.server` for the loopback test servers (commit 80a6e3b); no release archive has it. See [platforms/apple/platform.md](platforms/apple/platform.md) and `docs/app-store/review-notes.md`.

Spec: [platforms/apple/platform.md](platforms/apple/platform.md). Code: `apps/apple/Signing/JournalMac.entitlements`, `apps/apple/Signing/JournalMac-Development.entitlements`, `apps/apple/Signing/JournalMac-Tests.entitlements`.

**C23.** Windows pages still describe Apple behaviour as it was before build 18. Export archive asks for no authentication (`platforms/windows/flows/export-archive.md`, now D2 resolved: Windows Hello when App lock is on and the library isn't encrypted); the save-failure alert repeats after every failed attempt (`platforms/windows/flows/save-failure.md` and D48, now A1 resolved: once per failure); the Mac Settings window opens on Sync (`platforms/windows/screens/settings.md`, now A30 resolved); Return on an empty quote line (`platforms/windows/flows/editing-rules.md`, N-7, now D4 resolved); “whether Back does is unverified” (`platforms/windows/flows/reconnect-to-server.md`, now A35 resolved); “(open-questions A9)” in `platforms/windows/flows/pair-device.md` (fixed on Apple). The library problem screen has no Windows mapping yet (D56). Recommendation: re-read those pages against the spec, which now follows the build 18 behaviour; the owner decides each Windows change.

Spec: [platforms/windows/flows/export-archive.md](platforms/windows/flows/export-archive.md), [platforms/windows/flows/save-failure.md](platforms/windows/flows/save-failure.md), [platforms/windows/screens/settings.md](platforms/windows/screens/settings.md), [platforms/windows/flows/editing-rules.md](platforms/windows/flows/editing-rules.md), [platforms/windows/flows/reconnect-to-server.md](platforms/windows/flows/reconnect-to-server.md), [platforms/windows/flows/pair-device.md](platforms/windows/flows/pair-device.md). Code: none (Windows not started).

**C24.** Build 18 behaviour the Apple notes record but the neutral spec doesn't state: Keep Both gives the copy the current modification time (`platforms/apple/flows/resolve-conflict.md`); the iPhone and iPad Face ID usage text and the local network text are Info.plist values with no key (B42). Recommendation: add one sentence for each to the neutral flows.

The rating-request part of this item ended in 1.1: sync states no longer count as problems, and Sync Status showing blocks the moment instead ([flows/rating-request.md](flows/rating-request.md)).

Spec: [flows/resolve-conflict.md](flows/resolve-conflict.md). Code: the Keep Both copy is written by the store (see the Apple page).

**C25.** Rule, 1.1 (simplification C): every state where this version of the app is too old for what it meets says “Update My Journal”, as a sentence or on the library problem screen as its heading, names what the person cannot do yet or what stays safe, and never names a store (the operating system does the update). A server that is too old keeps “needs an update”, because the person cannot act on it from the app. `python3 spec/tools/check-spec.py` warns when a catalog text about a newer app version lacks the words. **Built in 1.1** on Apple; other platforms may add their own update link to the same key. Windows pages that name `messages.save.before.*` or the Update texts were changed only where they would be false: the Windows agent maps the two save-first texts (`messages.save.before.tryAgain`, `messages.save.before.goBack`) and the changed Update texts in the pages it owns. Record: [1-1-encryption-and-passwords.md](../docs/design/1-1-encryption-and-passwords.md) §5.

Spec: [screens/unavailable-content.md](screens/unavailable-content.md), [messages.md](messages.md). Code: `Views/LibraryProblemView.swift`, `Views/DeleteAllPrompt.swift`, `Model/LibraryOperations.swift`.

**C26.** Windows pages still describe the editor as before 1.1 in four places: F-1 and F-3 (`platforms/windows/flows/editing-rules.md`, row F: strikethrough and inline code by the first character; one rule for all five now), N-8 (Return in a heading, D6: split in the middle, a paragraph above at the start, an empty heading becomes a paragraph), the table menus (`platforms/windows/flows/edit-table.md`, D7: one list in one order with the Alignment submenu checked in Format ▸ Table and the cell menu) and the Don’t Allow row of `platforms/windows/flows/allow-agent.md` (D55: the page now says when the decline did not arrive). This change edited only the statements that would otherwise be false; the Windows agent maps the rest (the checkmark control in a `MenuFlyoutSubItem`, whether the rich edit control can run the one rule over a mixed selection, and the announcement of a decline that completes after the dialog has closed). The owner decides each Windows change.

## D. Product questions for the owner

Behaviour no record decides, or choices for the Windows and Android ports.

**Owner decisions of 2026-10-07 for the Windows questions D20 to D54:** every reviewed recommendation is accepted, except that (1) there is no OneDrive warning before a plain Markdown export (D46, B37) and (2) tables are fully editable in place, exactly like on the Mac, a hard requirement for the editor choice (D30, D33). The accepted archive recommendation (D29, one file) still needs its protocol change in [protocol/archive.md](../protocol/archive.md), with a version bump and conformance fixtures, before Windows builds archives. The questions below keep their text as history; where one disagrees with this paragraph, this paragraph wins.

**D1.** Journal deletion has no Undo, while entry and template deletion do. No record says whether that is intended. **Resolved by owner decision, 2026-10-09:** keep as is. A deleted journal goes to Recently Deleted and is restored from there; it needs no Undo.

Spec: [flows/delete-and-restore.md](flows/delete-and-restore.md). Code: `Model/JournalOperations.swift`.

**D2.** Export Archive doesn't ask for device authentication when App Lock is on, while Export as Markdown does. An encrypted archive needs the password to open, but an archive of journals without encryption is readable. No record decides this. **Resolved by owner decision, 2026-10-06:** Export Archive asks for the device's authentication when App Lock is on and the library isn't encrypted (owner decision #9, record §3.1, built in build 18); a cancel says nothing, a failure shows `settings.backup.verifyFailed`. `flows/export-archive.md` says so. Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [flows/app-lock.md](flows/app-lock.md), [flows/export-archive.md](flows/export-archive.md). Code: `Model/DocumentTransferOperations.swift`, `Model/PasswordCheckOperations.swift`.

**D3.** If the person cancels after `settings.changePassword.error.notSavedRetry`, this device keeps the old password while the server has the new one; the next unlock with the new password recovers from the server's copy. Is that enough, or should the sheet insist? **Resolved by owner decision, 2026-10-09:** keep as is. The next unlock with the new password recovers from the server's copy, so the sheet doesn't insist (simplification J reworks Change Password in 1.1).

Spec: [flows/change-password.md](flows/change-password.md). Code: `Model/PasswordOperations.swift`.

**D4.** Return on an empty quote line never leaves the quote (N-7), while lists leave on an empty item and Notes leaves a quote the same way. No record decides quotes. **Resolved in build 18:** Return on an empty quote line leaves the quote one level (audit item #14, record §2.3); `flows/editing-rules.md` N-7 now says so. Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [flows/editing-rules.md](flows/editing-rules.md), [screens/entry-editor.md](screens/entry-editor.md). Code: `Editor/RichText.swift`.

**D5.** Bold, Italic and Underline use a different rule for a mixed selection than Strikethrough and Inline Code (F-1 and F-3): the first turn on unless everything already has them, the others follow the first selected character. One rule would be clearer. **Resolved by owner decision, 2026-10-09:** one rule for all five styles, the one Bold, Italic and Underline use today: a style turns on unless the whole selection already has it. Strikethrough and Inline Code change in 1.1 (design gate). **Built in 1.1:** F-1 is the one rule, with one predicate for the shown state and the action (`InlineStyles`), and on iPhone and iPad the system's Bold, Italic and Underline run it too; F-3 is merged into F-1.

Spec: [flows/editing-rules.md](flows/editing-rules.md). Code: `Editor/RichText.swift`, `Editor/FormattingState.swift`.

**D6.** Return in the middle of a heading inserts a line break that carries the heading's style while typing continues as a paragraph; whether the second half ends up a heading or a paragraph depends on what is typed next (N-8). No test or record defines it. **Resolved by owner decision, 2026-10-09:** Return in the middle of a heading splits it into two headings of the same level; Return at the end of a heading starts a paragraph. Built in 1.1 (design gate), with N-8 rewritten to match. **Built in 1.1:** the start-of-heading and empty-heading cases are decided in N-8 (an empty paragraph above; the heading becomes a paragraph).

Spec: [flows/editing-rules.md](flows/editing-rules.md). Code: `Editor/RichText.swift`.

**D7.** The table structure menus differ: the Mac's cell menu lists alignment between Add and Delete, Format ▸ Table has no alignment items and orders its items differently, and iPhone and iPad group alignment in a submenu. One list for all three would be simpler. **Resolved by owner decision, 2026-10-09:** one list of table commands, in one order, on every device: add rows, add columns, alignment (a submenu everywhere), then delete row, delete column and delete table. Built in 1.1 (design gate). **Built in 1.1:** one definition (`TableMenu`) renders the Mac cell menu, Format ▸ Table on the Mac and iPad, and the iPhone and iPad edit menu; the current alignment is checked.

Spec: [flows/edit-table.md](flows/edit-table.md), [flows/editing-rules.md](flows/editing-rules.md). Code: `Editor/TablePresentation.swift`, `AppCommands.swift`.

**D8.** There is no way to edit or remove an existing link: the sheet doesn't show the current address and there is no Remove Link (only Undo, or retyping the text). No design record covers editing links. **Resolved in build 18:** Edit Link… and Remove Link exist (audit item #15, record §2.4); `screens/link-editor.md` and `flows/editing-rules.md` L-7 to L-10 describe them. Record: [build-18-fixes-2026-10-06.md](../docs/design/build-18-fixes-2026-10-06.md).

Spec: [screens/link-editor.md](screens/link-editor.md). Code: `Views/LinkEditorView.swift`.

**D9.** Devices can't be renamed (the name iOS reports is often only “iPhone”), although the task brief lists rename; neither the code nor any record has it. Also, there is no way to remove this device from its own list except Stop Syncing, which Devices doesn't mention. **Resolved by owner decision, 2026-10-09:** keep as is: devices aren't renamed, and this device leaves its own list only with Stop Syncing.

Spec: [screens/settings-devices.md](screens/settings-devices.md), [screens/settings.md](screens/settings.md). Code: `Views/DevicesView.swift`, `Model/DeviceOperations.swift`.

**D10.** Libraries from early versions encrypted with a recovery key (format 1) show “Your Journals Are Encrypted” with no Change Password, and their footer says “Keep your recovery key somewhere safe.” Should there be a way to move them to a master password? **Resolved by owner decision, 2026-10-09:** keep as is. Recovery-key libraries came only from early test builds; they keep working and get no conversion path.

Spec: [screens/settings-privacy.md](screens/settings-privacy.md). Code: `Views/SettingsView.swift`, `Views/ChangePasswordView.swift`.

**D11.** Windows and Android will never create libraries with a generated recovery key and can receive one only through an archive or restore, which don't show the Keep Your Recovery Key screen. Is that screen needed outside the Apple app at all? **Resolved by owner decision, 2026-10-09:** not needed. Windows and Android don't build the Keep Your Recovery Key screen; `legacy-recovery-key` in parity.yaml is not-applicable outside Apple.

Spec: [screens/recovery-key.md](screens/recovery-key.md). Code: `Views/RecoveryView.swift`.

**D12.** On iPad the windows share one selection and collection (one model for the app), so two windows can't show different journals. Zoom isn't persisted either: the Mac default text size returns at each launch. No record says whether either is intended. **Resolved by owner decision, 2026-10-09:** keep as is for 1.0: iPad windows share one selection, and the Mac text size returns to the default at each launch. Independent iPad windows can be proposed later as a feature.

Spec: [screens/library-window.md](screens/library-window.md). Code: `Views/RootView.swift`, `Model/WindowColumns.swift`.

**D13.** There is no multiple selection (no Select mode, no Shift-click or ⌘-click) in the entries list on any platform. No record asks for it. **Resolved by owner decision, 2026-10-09:** keep as is: no multiple selection in the entries list.

Spec: [screens/entry-list.md](screens/entry-list.md). Code: `Views/RootView.swift`.

**D14.** A journal with changes to review leaves the list (it is “unavailable”) and Rename, Default Template and Merge Into… are disabled for it, but then there is no row to open those menus from; the disabled states matter only in the brief time before the list updates. Superseded in 1.1 by simplifications H, L and M (owner-approved 2026-10-07), still open for 1.0.

Spec: [screens/journals.md](screens/journals.md), [screens/conflict-review.md](screens/conflict-review.md). Code: `Views/JournalSidebarView.swift`, `Views/JournalMoreMenu.swift`.

**D15.** The leading Restore swipe and the Restore menu item restore an entry directly only when its journal is in use; otherwise only the notice's Restore… and Restore and Move… exist, which the person has to open the entry to find. Superseded in 1.1 by simplification N (Recently Deleted offers plain Restore only; owner-approved 2026-10-07), still open for 1.0.

Spec: [screens/recently-deleted.md](screens/recently-deleted.md). Code: `Views/RootView.swift`, `Views/EntryRecoveryNotice.swift`.

**D16.** When “use a template” or New Entry from Template… finds the open entry's body no longer empty, it creates a new entry where New Entry would put it; from All Entries that is the Default Journal, not the open entry's journal. The template-journal record calls this a known limit. Superseded in 1.1 by simplification M (one way to start from a template; owner-approved 2026-10-07), still open for 1.0.

Spec: [flows/new-entry.md](flows/new-entry.md). Code: `Model/TemplateSuggestion.swift`, `Model/AppModel.swift`.

**D17.** Nothing keeps unsaved writing when the system ends the app on iPhone or iPad after a failed save; the Mac blocks quitting instead. **Resolved by owner decision, 2026-10-09:** keep as is. The save-failure alert explains the problem, and a separate draft store would be a second save path that can fail the same way.

Spec: [flows/save-failure.md](flows/save-failure.md). Code: `Model/AppModel.swift`.

**D18.** The deletion review labels versions “Unknown Device” while the journal review shows the recorded device ID under Details, which people can't relate to a device name. One approach could serve both; a device-name lookup is noted as future work in the journal-conflicts record. **Deferred by owner decision, 2026-10-01:** device names and what changed between versions are “later” ([owner-decisions-2026-10-01.md](../docs/design/owner-decisions-2026-10-01.md), #1). Superseded in 1.1 by simplification H (owner-approved 2026-10-07), still open for 1.0.

Spec: [screens/conflict-review.md](screens/conflict-review.md), [flows/resolve-conflict.md](flows/resolve-conflict.md). Code: `Views/DeletionConflictView.swift`, `Views/JournalConflictView.swift`.

**D19.** Which Apple platform-specific features should Windows and Android follow? Mac-only on Apple: Show Editor Only, Previous and Next Entry, zoom commands; tablet-style three columns. Phone-only on Apple: stacked navigation, search of every journal from the Journals screen. The parity file marks them planned for both platforms, with a note, until decided. **Resolved by owner decision, 2026-10-09:** each platform uses its own native features where they apply, to give the best experience on that device; Windows and Android don't copy Apple-only features for their own sake and add their platform's native ones. The parity notes of the Apple-only features say so.

Spec: [parity.yaml](parity.yaml), [screens/library-window.md](screens/library-window.md). Code: `Views/RootView.swift`, `Views/CompactJournalNavigation.swift`.

**D20.** Windows menu model, formatting and the chrome of the lock and first-launch pages. Draft default: a complete `MenuBar` (File, Edit, Format, View, Help; Settings and Exit under File, About under Help) plus a `CommandBar` in each pane for the frequent subset, with no command that is only on a toolbar; formatting is a toggleable `CommandBar` under the editor header (hidden by default, remembered per device, shown by the Formatting button and View ▸ Formatting) plus the text control's selection mini-toolbar with Bold, Italic and Link, instead of the Apple popover; Show editor only and View source are menu-only; and the menu bar and pane button are not shown on the lock page and the first-launch pages (the title bar then has a More button with Help and Exit, and Settings on the first-launch pages). Design review, recommendation adopted: confirm the menu bar, with Notepad (menu bar plus a formatting bar, 2025) and Paint as the precedent (Photos and Clipchamp are viewers with few commands); use a formatting bar, not a flyout, because a popover costs two clicks per bold, tucks the paragraph styles behind a focus mode that can swallow the first click and is Apple's Notes idiom; hide the menus where they have nothing to command, because disabled menus on a first-run page or the lock page are noise and tell Narrator the app has content; spike Alt access and the drag regions of a `MenuBar` inside the `TitleBar`. Alternatives: a command bar and a hamburger menu only, more like the newest Microsoft apps but hiding about 100 commands, including the whole Format menu, in overflow menus; or the Apple popover as a flyout.

Spec: [platforms/windows/platform.md](platforms/windows/platform.md) (section 4), [platforms/windows/commands.md](platforms/windows/commands.md), [platforms/windows/screens/format-sheet.md](platforms/windows/screens/format-sheet.md), [platforms/windows/screens/lock-screen.md](platforms/windows/screens/lock-screen.md), [platforms/windows/screens/welcome.md](platforms/windows/screens/welcome.md), [commands.md](commands.md). Code: `AppCommands.swift`, `Views/Mac/JournalToolbarController.swift`.

**D21.** Windows copy: sentence case, ellipsis and vocabulary. About 340 of 1,135 copy keys are short strings in Apple title case ("Try Again", "Move Entry…", "Agent Access"). Microsoft style, and every Windows app, uses sentence case ("Try again", "Move entry…", "Agent access"). The proposal: store explicit `sentence` variants in `copy/en.json`, named for the casing and shared with Android (Material guidance is also sentence case, and the Apple catalogue is the only Title Case one), generated from a written rule (feature names lower case; "My Journal", Markdown, Windows Hello and acronyms kept) and checked by the checker so they cannot drift. A platform-named variant (`windows`, later `android`) exists only where the words differ, not the casing, and is written in sentence case itself: dropping the ellipsis on confirmation-only commands ("Delete Permanently…"), and Windows words for Apple ones (Windows Hello for Face ID, Touch ID and passcode; "this PC" for "this Mac"; "select" for "choose"; "Close My Journal and open it again" for "Quit and reopen"; no shortcut glyphs in labels; "General" for "Writing"; "Show editor only" and "Show all panes"). Design review, recommendation adopted: approve the rule, the protected-term list and the vocabulary, but name the variant for the casing, not for Windows, so that about 340 `windows` strings and later about 340 `android` ones never duplicate one list and drift; this is cheap now and expensive once `copy/en.json` is generated. The checker accepts the `sentence` shape. Nothing in `copy/en.json` has changed. Approve or change the rule, the protected-term list and the Windows names; then the variants are generated. Every proposed Windows string, one row per key, is in [platforms/windows/copy-proposals.md](platforms/windows/copy-proposals.md); the related copy questions are B26 to B41 (B27 covers sentences that name a Title Case label, which the rule as first written did not reach).

Spec: [platforms/windows/platform.md](platforms/windows/platform.md) (section 12), [copy/en.json](copy/en.json), [screens/settings.md](screens/settings.md). Code: none yet; Apple copy is in the views named in each screen's `sources:`.

**D22.** Windows distribution. Draft default, the review's recommendation: **Windows 11 (build 22000) is a requirement**, because the Windows Hello desktop call that App Lock and every other authentication use documents build 22000 as its minimum client (WinUI 3 itself would run on Windows 10 1809, and Windows 10 reached end of support in October 2025); one MSIX package for x64 and Arm64 through the Microsoft Store (which signs and updates it) and installable with winget from the msstore source in version 1; a GitHub-hosted MSIX only once a certificate Windows trusts exists (Azure Artifact Signing issues public-trust certificates to individuals only in the United States and Canada, and to organisations in a list of regions that includes the EU; a person outside those regions plans Store-only). Two things need the owner: whether to ship outside the Store at all, and that uninstalling the package removes its local data, including journals that exist only on this PC. Packaging cannot show a prompt at uninstall, so the draft warns in the Store listing and in Settings ▸ Backup, which shows "Last exported {date}" (or "Not exported yet") while the library exists only on this PC; the review judged that better for the data-safety rule than a Store sentence alone.

Spec: [platforms/windows/platform.md](platforms/windows/platform.md) (sections 1, 17, 18), [screens/settings-backup.md](screens/settings-backup.md). Code: none yet.

**D23.** Closing the window on Windows. The proposal: closing the one library window ends the app after the open entry is saved, as Windows apps do, with no tray icon, no background sync and no start-up entry in version 1; the Mac keeps running without a window. Changes from other devices then arrive the next time the app opens. A Microsoft Store update, a reinstall, a sign-out and a restart end the app the same way and take the same save-first path, and closing while a long action runs waits for its current atomic step and then stops it as Cancel would. Design review: confirmed as drafted, with the update and sign-out wording added. Confirm, or ask for a notification-area presence (a visible icon and a setting).

Spec: [platforms/windows/platform.md](platforms/windows/platform.md) (sections 3, 30), [screens/library-window.md](screens/library-window.md), [flows/save-entry.md](flows/save-entry.md). Code: `Model/WindowSafety.swift`, `JournalApp.swift`.

**D24.** Camera features on Windows. The proposal leaves out Photo Library (Windows has no such library), Take Photo and Scan Code in version 1: PCs often have no suitable camera, and pairing, inserting images (file picker, paste, drag and drop) and capturing (Snipping Tool) all work without one. This would mark `insert-image-camera` and `pair-device-scan` as different by design on Windows. A later version could add an in-app camera dialog only when a camera is present. Design review: confirmed as drafted; revisit a camera only with a real user need. Confirm; this also bears on D11 and D19.

Spec: [platforms/windows/platform.md](platforms/windows/platform.md) (sections 26, 29), [flows/insert-image.md](flows/insert-image.md), [screens/scan-code.md](screens/scan-code.md), [parity.yaml](parity.yaml). Code: `Views/ScanCodeView.swift`, `Editor/WritingAccessory.swift`.

**D25.** App Lock and secret storage on Windows. App Lock would use Windows Hello (face, fingerprint or PIN) through the system prompt and nothing of the app's own, as the spec requires, and needs Windows 11 (D22). A PC account with only a password and no Hello PIN could not turn App Lock on (a footer would say how to set Hello up); supporting those accounts would need the app to verify a typed Windows password, which the "only the system's authentication" rule avoids. Where Hello is disabled by an organization's policy the footer needs one new string, and an App Lock that is already on pauses instead of locking a person out (D42). The library key and the device's server credentials would be protected with the Windows Data Protection API for the current user, stored in per-user local data, the closest match to Apple's "when unlocked, this device only" Keychain items. A process running as the same user can read them, App Lock does not change that, and the "device key unavailable" path (restore, new PC, password reset, reinstall) becomes common. A TPM-wrapped key is a spike that does not block. Design review: confirm Hello-only App Lock and DPAPI with the pause rule of D42 and the Windows 11 requirement. Confirm Hello-only App Lock and the storage threat statement.

Spec: [platforms/windows/platform.md](platforms/windows/platform.md) (sections 13, 14), [flows/app-lock.md](flows/app-lock.md), [screens/lock-screen.md](screens/lock-screen.md). Code: `Model/DeviceAuthentication.swift`, `Model/AppLockOperations.swift`, `Packages/JournalCore/Sources/JournalCore/Keychain.swift`.

**D26.** Settings on Windows. The proposal: Settings is a page inside the main window in the style of Windows 11 Settings (the navigation pane's built-in Settings item, File ▸ Settings, Ctrl+,), with the six panes as cards that open sub-pages under a breadcrumb, an About group at the foot (Windows apps show About in Settings) and Erase Journals and Settings as the last group of the first pane, which is therefore called General as on the Mac, not Writing. Every action is a real button in its card, including destructive ones; clickable cards are for navigation and links only. The Mac's separate Settings window and the phone's sheet are not copied. Design review: confirmed; use the built-in Settings item (right icon, localised name, last, pinned) rather than a footer item of our own, buttons in cards, Erase in General's last group and About on the home page; mirroring Microsoft's About expander (app name, icon and version in the header row) was considered and not adopted, because the About group is a short list of cards and an expander adds a level for five rows. Confirm, or choose a separate window.

Spec: [platforms/windows/platform.md](platforms/windows/platform.md) (section 10), [screens/settings.md](screens/settings.md), [screens/settings-general.md](screens/settings-general.md), [screens/settings-about.md](screens/settings-about.md). Code: `Views/SettingsView.swift`, `Views/SettingsPresenter.swift`.

**D27.** Windows shortcuts that depart from a mechanical Command-to-Ctrl translation (all in [platforms/windows/commands.md](platforms/windows/commands.md)): Redo is Ctrl+Y, Find and Replace is Ctrl+H, Search Entries is Ctrl+E, Help is F1, Full Screen is F11, New Journal is Ctrl+Shift+J, Lock is Ctrl+L, Indent is Ctrl+M and Ctrl+Shift+M, and Option-Command shortcuts become Ctrl+Shift shortcuts because Windows reports AltGr as Ctrl+Alt and AltGr plus a letter or digit types characters on many layouts. **Draft default, the review's recommendation: headings are Ctrl+Shift+1 to 6 and Paragraph is Ctrl+Shift+0, not Word's Ctrl+Alt+digit**, which swallows @, #, {, [, |, \ and more on Belgian, French, German, Polish, Czech and Spanish layouts and contradicts the editor's own rule that AltGr characters always type; no shortcut uses Ctrl+Alt (the set was checked for other Ctrl+Alt chords and has none). Ctrl+Alt+1 to 3 could be added later only after `ToUnicodeEx` shows the layout produces no character for the chord, as Google Docs does. Punctuation shortcuts (Ctrl+Plus, Ctrl+Minus, Ctrl+=, Ctrl+, and Ctrl+Shift+Q) are bound to virtual keys that do not follow the printed key on AZERTY and others, so zoom is bound on the main row and the numpad, and every accelerator is tested on the US, Belgian AZERTY, German QWERTZ and Polish programmer layouts. Open points: Ctrl+, (Settings) is used by Windows Terminal and VS Code but is not in Microsoft's accelerator table, and Ctrl+Shift+B (navigation pane) and Alt+Shift+Up and Down (move a journal) have no Windows precedent, so each also has a menu or button route; a hidden Ctrl+S that silently finishes the save is an addition to the spec's commands, as are Move Up and Move Down in the journal context menu and Ctrl+mouse wheel zoom. Also additions: Alt+Left as Back on every page that has a back button (reviews, histories, task pages, Image descriptions, Settings pages), and Open link and Copy link in the editor’s context menu, which the spec does not define. **Esc is not Back** (draft default, from the review): Esc dismisses transient surfaces only, because Back is Alt+Left and Esc as Back collides with "Esc cancels the open drop-down or dialog" and with IME composition; Cancel on those pages is a button. Design review: approve the set with these two changes; keep Ctrl+Y, Ctrl+H, Ctrl+E, F1, F11, Ctrl+Shift+J, Ctrl+L, Ctrl+M and Ctrl+Shift+M, Alt+Up and Down, the hidden Ctrl+S, mouse-wheel zoom and Alt+Left. Approve the set, or name the ones to change.

Spec: [platforms/windows/platform.md](platforms/windows/platform.md) (section 7), [platforms/windows/commands.md](platforms/windows/commands.md), [platforms/apple/commands.md](platforms/apple/commands.md), [commands.md](commands.md). Code: `AppCommands.swift`, `Model/FindMenuShortcuts.swift`.

**D28.** Privacy of the Windows window beyond the lock. Windows shows a window's pixels in more places than iOS: taskbar thumbnails, Alt+Tab, screenshots, screen sharing, remote sessions and, on Copilot+ PCs, Recall snapshots. **Draft default, the review's recommendation: no cover on deactivation.** The Mac's cover protects an app-switcher snapshot; Windows has none, windows there sit side by side and lose focus all day (snapped beside a document, on a second monitor, behind a Windows Hello prompt for another app), nothing in Notepad, OneNote, Mail or Photos hides its content then, and a topmost cover the size of the window would sit over other apps and needs special cases for the Hello prompt, the Store rating dialog and every picker. The protection is App Lock (it locks on launch, Ctrl+L, the inactivity timer, Win+L, user switch, disconnect, display off, lid and sleep) plus capture exclusion with `SetWindowDisplayAffinity` on every top-level window of the app. The flag: Microsoft's Recall guidance says apps can use `SetWindowDisplayAffinity` and its example is `WDA_MONITOR` (the content shows only on a monitor and the window appears with no content elsewhere); `WDA_EXCLUDEFROMCAPTURE` (Windows 10 2004 and later) makes the window not appear in captures at all. The draft uses `WDA_MONITOR` and a spike on a Copilot+ PC compares both. Exclusion is not a security feature, works only with desktop composition, is per top-level window and also blocks the person's own screenshots and screen sharing. It is on by default with a Settings ▸ Privacy switch (new copy, B33), **pending an accessibility spike**: magnifiers and screen readers that capture the screen (for example ZoomText, some OCR and remote-assistance tools) may see an empty window, so Windows Magnifier, Narrator and Quick Assist are tested, and if any fails the default becomes off with a Store listing note. While a QR code or check code is on screen the whole window is excluded whatever the setting says. Alternative, if the owner wants a cover anyway: an opt-in Privacy setting "Hide when not in front", not topmost, only for a minimised or inactive window that is not snapped beside the active one. The window title never names a journal (B29).

Spec: [platforms/windows/platform.md](platforms/windows/platform.md) (section 20), [screens/lock-screen.md](screens/lock-screen.md), [flows/app-lock.md](flows/app-lock.md). Code: `Model/PrivacyCover.swift`.

**D29.** Windows and the archive as a directory. A `.journalarchive` is a directory package ([protocol/archive.md](../protocol/archive.md)). `FileSavePicker` cannot create a directory, `FileOpenPicker` cannot pick one, and a folder cannot have a file type association. **Draft default, the review's recommendation (the mapping files and platform.md now follow it): change the protocol so every platform reads and writes one file**, for example the package inside a ZIP container with a manifest, a content hash and the same checks. A folder holding a SQLite file and images is easy to copy partly, to sync half-way through OneDrive, to break with path-length limits and to hand to someone as 300 loose files, and nothing stops a half-copied folder from looking valid; one file restores the standard Save and Open pickers, a double-click `.journalarchive` association, drag and drop of one object and cross-platform restores (a Windows archive opens on Apple), and removes the folder picker rules, the " (2)" folder naming and the "folder is not an archive" error. The cost is a protocol change on every platform and a decision about the extra layer, and it is cheapest now. Alternative (the previous draft): keep the folder: `FolderPicker` in both directions, the app creates “Journal Archive {date}.journalarchive” inside the chosen folder, nothing is registered with Windows, and the import verifies every file against the manifest's hashes before showing the preview, so a half-copied folder cannot look valid. Decide before the Windows import and export are built; Android’s storage access has the same constraint.

Spec: [protocol/archive.md](../protocol/archive.md), [platforms/windows/platform.md](platforms/windows/platform.md) (16, 19), [platforms/windows/screens/settings-backup.md](platforms/windows/screens/settings-backup.md), [platforms/windows/screens/archive-import.md](platforms/windows/screens/archive-import.md), [platforms/windows/flows/export-archive.md](platforms/windows/flows/export-archive.md), [platforms/windows/flows/import-archive.md](platforms/windows/flows/import-archive.md), [platforms/windows/flows/export-markdown.md](platforms/windows/flows/export-markdown.md). Code: `Model/DocumentTransferOperations.swift`.

**D30.** Technical spike, then an owner decision: the Windows editor control. **Draft default, the review's recommendation: run two spikes in parallel, time-boxed to two or three weeks each, against one shared scorecard**, with the pass criteria and the abandonment criteria written in [entry-editor](platforms/windows/screens/entry-editor.md) (The spikes): Spike A, `RichEditBox` plus an overlay layer (drawn list markers and checkboxes, find highlights, image placeholders) and a custom automation peer behind an `IEditorSurface` interface; Spike B, a `WebView2` block editor that serialises to Markdown. A custom text control stays on paper as the last resort. The reason: by the mapping's own candidate table `RichEditBox` is Blocked for tables and not under the app's control for Narrator before any code is written, and the architecture it needs (the control never holds the Markdown, the app diffs after every change, an app-owned undo stack, overlays positioned from range rectangles) is a second editor on top of a first, with the likeliest source of silent corruption in the product, because text can change without key events. Microsoft's own precedents are mixed (Notepad keeps a native edit control; the new Outlook and Loop use web editors). The scorecard includes Narrator on a real PC, a Japanese input method, 200% display scale, a 50,000-character entry and the Markdown fidelity corpus. `WebView2` adds a second runtime and a bundled JavaScript editor to a native app, which needs the owner's agreement once the scores are in. Previous draft: `RichEditBox` first and `WebView2` only if it fails. Decides the entry-editor, format-sheet, link-editor and editing-rules mappings and D31 to D33, D35. **Owner decision, 2026-10-07: in-place table editing (D33) is now a must for both spikes.**

Spec: [platforms/windows/screens/entry-editor.md](platforms/windows/screens/entry-editor.md), [platforms/windows/flows/editing-rules.md](platforms/windows/flows/editing-rules.md), [platforms/windows/screens/format-sheet.md](platforms/windows/screens/format-sheet.md), [platforms/windows/screens/unavailable-content.md](platforms/windows/screens/unavailable-content.md), [platforms/windows/flows/source-view.md](platforms/windows/flows/source-view.md), [platforms/windows/flows/markdown-as-you-type.md](platforms/windows/flows/markdown-as-you-type.md), [platforms/windows/flows/edit-table.md](platforms/windows/flows/edit-table.md). Code: none yet.

**D31.** Technical spike: the undo model. The preferred control offers undo groups and a limit but no step names and no way to inspect the stack. Rules U-1, K-3, K-4, B-4, S-4 and TB-1 need exact snapshots, two-step Markdown conversions and one history shared with overlay check boxes. **Draft default, the review's recommendation: an app-owned undo stack of 100 steps that restores text, selection and view, with the control’s own undo turned off, but without step names in the Edit menu on Windows**: Word, Notepad and OneNote say plain Undo and Redo, so most of the argument for named steps goes away (the names stay for Narrator announcements, and list-level actions such as Delete entry keep their names). Alternative: the control’s own undo, which cannot make two-step conversions exact or share a history with overlay check boxes. Also an alternative: named steps in the Edit menu as on Apple. Decided by the spike in D30.

Spec: [platforms/windows/screens/entry-editor.md](platforms/windows/screens/entry-editor.md), [platforms/windows/flows/editing-rules.md](platforms/windows/flows/editing-rules.md), [platforms/windows/flows/edit-table.md](platforms/windows/flows/edit-table.md), [platforms/windows/flows/source-view.md](platforms/windows/flows/source-view.md). Code: none yet.

**D32.** Technical spike and ship gate: how Narrator reads what the editor draws. Markers, checkboxes, headings and tables are drawn or overlaid, never characters, so Narrator learns list kind, level, number and checked state from automation properties; overlay checkboxes are toggles named by their item and are not Tab stops (as on the Mac). The text pattern of `RichEditBox` exposes text and formatting runs, not drawn markers or overlay check boxes, so whether it is discoverable in browse mode is unproven. **Draft default, the review's recommendation: a ship gate, not a spike item**: the editor does not ship without a Narrator walkthrough script (a list, a checklist, a heading, an image with its description, a table) that passes on a real PC; Spike A budgets a custom automation peer (a derived `RichEditBoxAutomationPeer`), and Spike B starts from Chromium's accessibility tree, which already has list, check box, heading and table roles. Mark as checked (Ctrl+Shift+Enter) stays discoverable in the menu for Narrator users.

Spec: [platforms/windows/screens/entry-editor.md](platforms/windows/screens/entry-editor.md), [platforms/windows/flows/editing-rules.md](platforms/windows/flows/editing-rules.md). Code: none yet.

**D33.** Tables in version 1 on Windows, if the chosen control cannot edit them in place. **Draft default, the review's recommendation: if `RichEditBox` wins, tables are preserved, byte-exact, read-only grids edited in source view, with no overlay editor and no shared undo with cell editors; if `WebView2` wins, native cells.** Tables already in an entry must stay intact either way. The overlay grid of cell editors with shared undo (the previous draft, design in [edit-table](platforms/windows/flows/edit-table.md)) is a second editor over the first and is not planned. Alternative: hold the table feature on Windows (a parity gap in `parity.yaml`). Decided after D30. **Resolved by owner decision, 2026-10-07: tables are fully editable in place on Windows, exactly like on the Mac. The read-only grid and the source-view route are withdrawn, there is no fallback and no parity gap, and in-place table editing is a hard requirement for the editor technology choice (D30): the editor spike must meet it. The Windows pages (edit-table, editing-rules, entry-editor) follow.**

Spec: [platforms/windows/flows/edit-table.md](platforms/windows/flows/edit-table.md), [platforms/windows/flows/editing-rules.md](platforms/windows/flows/editing-rules.md), [platforms/windows/screens/entry-editor.md](platforms/windows/screens/entry-editor.md). Code: none yet.

**D34.** Text keys the spec does not define on a PC keyboard. Shift+Enter and Ctrl+Enter in the body (the spec only defines Return), and Ctrl+Delete, Ctrl+Left and Right, Home, End, Ctrl+Home, Ctrl+End, Page Up and Down, with Shift to select (the spec defines Backspace, Delete, Return and the arrows by line boundary). **Draft default, the review's recommendation: Shift+Enter and Ctrl+Enter act as Enter in version 1** (nothing unstorable is inserted), and every other key is the control’s own behaviour, with the line-boundary rules (B, E and N in the editing rules) tested for Home, End and Ctrl+arrows. Alternative for Shift+Enter: a hard line break, which needs a document and Markdown decision for every platform.

Spec: [platforms/windows/flows/editing-rules.md](platforms/windows/flows/editing-rules.md), [platforms/windows/screens/entry-editor.md](platforms/windows/screens/entry-editor.md), [flows/editing-rules.md](flows/editing-rules.md). Code: none yet.

**D35.** Spell check inside code, inline code and raw HTML on Windows. The Windows checker has only a control-wide switch (`IsSpellCheckEnabled`), so the spec’s “no spelling marks in code” (SP-1) cannot be kept per range. **Draft default, the review's recommendation: accept squiggles in code blocks and inline code in version 1 and switch the checker off in View source**; revisit with the Windows spell checker API only if `WebView2` is not chosen. Alternatives: switch the checker off for the whole control whenever the caret is in code (marks flicker away and back), or draw the app’s own proofing marks using the Windows spell checker API, which makes per-range control easy but is new work and needs D30. The owner decides whether squiggles in code are acceptable.

Spec: [platforms/windows/flows/editing-rules.md](platforms/windows/flows/editing-rules.md), [platforms/windows/screens/entry-editor.md](platforms/windows/screens/entry-editor.md). Code: none yet.

**D36.** Technical decision: the portable clipboard format for “the entry’s own Markdown” (rule PA-1). Apple uses a type identifier; Windows needs a registered clipboard format with a name. **Draft default, confirmed by the design review:** register one named, versioned format, put the name in the protocol so Android and a future web client can read and write it, and always add plain text (with list markers and a tab) and HTML for other apps. Alternative: plain text only, which loses the exact Markdown when pasting between My Journal windows and devices. The name is not fixed in the mapping files.

Spec: [platforms/windows/flows/editing-rules.md](platforms/windows/flows/editing-rules.md), [platforms/windows/flows/image-actions.md](platforms/windows/flows/image-actions.md), [platforms/windows/screens/entry-editor.md](platforms/windows/screens/entry-editor.md). Code: none yet.

**D37.** Find and replace on Windows. Windows has no system find bar, so the app draws one (Ctrl+F, Ctrl+H, F3, Shift+F3), with strings in B31. The spec does not define scope or match options. Draft default, confirmed by the design review: it searches the body and table cells of the open entry, matching is case-insensitive and by substring, Replace is one undo step per use and Replace all is one undo step, and matches are highlighted with an overlay (never character formats, which would be saved or undone). Notepad puts its find bar at the top right of the content with Match case, Whole word and Wrap options; the review suggested that placement and a Match case toggle. Not adopted for placement: an overlay in the corner would cover text, and this bar sits in the layout and never covers the first line. Alternatives: add “Match case” and “Whole word” options (more controls, more strings), or search every entry from the same bar (the Search box already does that).

Spec: [platforms/windows/screens/entry-editor.md](platforms/windows/screens/entry-editor.md), [platforms/windows/commands.md](platforms/windows/commands.md) (`find`). Code: `Model/FindMenuShortcuts.swift`.

**D38.** The counts in the navigation pane. **Draft default, the review's recommendation: plain secondary-colour text (Caption) at the item's trailing edge, and no badge.** `InfoBadge` is a notification affordance in Fluent 2 and counts are not notifications; Mail does the same for its folder counts. The attention dot (an `InfoBadge` dot) is kept only for things that need attention: Unavailable journals and a journal that has changes to review (D52). Alternatives: the informational (neutral) `InfoBadge` (the previous draft), the accent badge, or no count.

Spec: [platforms/windows/screens/journals.md](platforms/windows/screens/journals.md), [platforms/windows/screens/library-window.md](platforms/windows/screens/library-window.md). Code: none yet.

**D39.** Image descriptions: Back with unsaved descriptions. On Apple, swipe-to-dismiss is blocked while descriptions are unsaved, and only Cancel (or Escape) discards. On Windows the page has a back button, Alt+Left and a breadcrumb. **Draft default, the review's recommendation: leave Back enabled and ask first with the standard Windows unsaved-changes prompt** (Notepad's): a dialog "Save description changes?" with Save (default), Don’t save and Cancel, on Back, the breadcrumb, Alt+Left and the window's Close button; the page's own Cancel button still discards, and Esc does nothing (Esc is not Back). A greyed back button looks like a bug on Windows, and a silent discard breaks "nothing is silently discarded". It needs two new strings (B41). Alternatives: disable Back while descriptions are unsaved, as on Apple (the previous draft); or the discard dialog of Reload images (`editor.imageDescriptions.discardTitle`, `editor.imageDescriptions.keepEditing`), which needs a Discard button string.

Spec: [platforms/windows/screens/image-description.md](platforms/windows/screens/image-description.md), [screens/image-description.md](screens/image-description.md). Code: `Views/ImageDescriptionsView.swift`.

**D40.** Markdown as you type for text that arrives without key presses: voice typing (Win+H), handwriting, the emoji panel and touch suggestions. The spec treats dictation like typing. **Draft default, confirmed by the design review:** convert only a single space inserted after a marker at the start of a plain paragraph, with no composition open; longer insertions are treated as pasted text and not converted. Alternative: also convert multi-character insertions that end in a space after a marker, which is closer to the spec but converts text the person did not type.

Spec: [platforms/windows/flows/markdown-as-you-type.md](platforms/windows/flows/markdown-as-you-type.md), [flows/markdown-as-you-type.md](flows/markdown-as-you-type.md). Code: `Editor/MarkdownShortcuts.swift`.

**D41.** Show Password on Windows. The draft uses a `CheckBox` (“Show password”, `common.showPassword`, `settings.connect.showCredential`, `settings.connect.recoveryCode.show` and `settings.encryption.showPasswords`) that drives `PasswordBox.PasswordRevealMode`, a pattern Microsoft documents, not the built-in press-and-hold reveal button that platform.md 25 names. Reason: the press-and-hold button needs a held pointer, so it fails with switch devices and is awkward by keyboard and Narrator. A check box also lets one control reveal several fields in the same dialog, as on Apple. Alternative: the built-in reveal button, which is the Windows default and less to build. The check box is used where the spec has a Show Password switch and in the two dialogs that set a new password twice (Change password, Set new password); a secure field that reads back an existing password (the lock page, Check your password, Open archive) keeps the built-in reveal button, which Alt+F8 also operates (to verify in the first build). Design review: confirmed as drafted. Related: B20 asks why only one Apple step says “Show Password”.

Spec: [platforms/windows/screens/settings.md](platforms/windows/screens/settings.md), [platforms/windows/screens/connect-to-server.md](platforms/windows/screens/connect-to-server.md), [platforms/windows/screens/change-password.md](platforms/windows/screens/change-password.md), [platforms/windows/screens/turn-on-encryption.md](platforms/windows/screens/turn-on-encryption.md), [platforms/windows/platform.md](platforms/windows/platform.md) (25). Code: `Views/ConnectionSteps.swift`.

**D42.** App lock when Windows Hello cannot be used. If App lock is on and Windows Hello is unusable (not set up, no device, a Remote Desktop session where biometrics are absent and the Hello PIN prompt is not guaranteed to work, or turned off by an organization's policy), a person whose journals have no password has no way in, and the only remaining exit would be Erase, which destroys the data. **Draft default, the review's recommendation: App lock pauses.** At launch, at unlock and whenever a trigger would lock, an unavailable Hello (NotConfiguredForUser, DeviceNotPresent or DisabledByPolicy) means the lock page is not shown, the journals open, and a persistent Warning bar at the top of the window says that App lock is paused and why, with an Open Sign-in options link where the person can fix it; it resumes by itself when Hello is available again. The transient results DeviceBusy and RetriesExhausted keep the lock page with Try again. An organisation policy should not be able to lock a person out of data on their own PC, and App lock is an interface lock, not encryption. This replaces the previous draft (App lock turns itself off with `settings.lock.turnedOff.passcodeRemoved` only for NotConfiguredForUser and keeps the lock page otherwise). Alternatives: the lock page stays (fail closed), which can lock a person out; a refinement that pauses only when the journals have no password, because with one the lock page already offers it; or turn App lock off in every such case (a person can never be locked out, but a policy change silently removes the protection). Related: D25.

Spec: [platforms/windows/flows/app-lock.md](platforms/windows/flows/app-lock.md), [platforms/windows/screens/lock-screen.md](platforms/windows/screens/lock-screen.md), [platforms/windows/screens/settings-privacy.md](platforms/windows/screens/settings-privacy.md), [flows/app-lock.md](flows/app-lock.md). Code: `Model/AppLockOperations.swift`, `Model/DeviceAuthentication.swift`.

**D43.** Device key that cannot be saved again after a credential unlock. The spec does not say what happens if, after the person unlocked with the password or recovery key, the key cannot be stored again for this PC (Windows Data Protection API failure). **Draft default, with the review's addition:** open the journals for this session, show a one-time Warning bar that the key could not be saved and that the password will be asked again at the next launch (so that launch is not a surprise), and show the device-key-unavailable page again at the next launch; nothing is lost. Alternative: refuse to open, which is safer for an App lock that cannot be re-armed but can lock a person out of their journals. This also applies on Apple if the Keychain refuses.

Spec: [platforms/windows/screens/lock-screen.md](platforms/windows/screens/lock-screen.md), [screens/lock-screen.md](screens/lock-screen.md). Code: `Model/AppLockOperations.swift`, `Packages/JournalCore/Sources/JournalCore/Keychain.swift`.

**D44.** The Erase warning dialog’s buttons on Windows. When journals would be lost, the draft puts Export archive… first and as the default button, and Erase second without the accent colour; Export archive… closes the dialog and opens the export, so Enter never erases. This is the one place where the destructive confirmation does not follow the rule that the primary button is the verb (platform.md 8.1, rule 3), because the message itself says to export first. Design review: accepted as drafted (it keeps Enter from erasing and follows the three-button model of `ContentDialog`). Alternative: Erase as the primary button with no default and Export archive… as a link in the text.

Spec: [platforms/windows/screens/settings-erase.md](platforms/windows/screens/settings-erase.md), [platforms/windows/flows/erase.md](platforms/windows/flows/erase.md), [platforms/windows/platform.md](platforms/windows/platform.md) (8.1). Code: `Views/EraseSection.swift`.

**D45.** The device name a PC sends when it connects to a server. **Draft default, confirmed by the design review:** the PC’s name, because that is the point of the Devices list and an access-removed message (names go only to the person's own server and devices), editable with D9’s rename, and disclosed in a note under the list on the Devices page. A PC name can include a person’s name or a work asset tag, and it goes to the server and every paired device. Alternative: a generic name (“Windows PC”) with the option to rename (D9), which is less identifying but cannot tell two PCs apart.

Spec: [platforms/windows/flows/connect-to-server.md](platforms/windows/flows/connect-to-server.md), [platforms/windows/screens/connect-to-server.md](platforms/windows/screens/connect-to-server.md), [platforms/windows/screens/settings-devices.md](platforms/windows/screens/settings-devices.md). Code: `Model/ConnectionFlow.swift`.

**D46.** A OneDrive question before exporting. On many Windows PCs Documents is redirected to OneDrive, and the sync client uploads a file the moment it is written, so an unencrypted Markdown export (or an archive of an unencrypted library) saved there leaves the PC before any note after the save could be read. **Draft default, the review's recommendation: check the chosen location before writing, and when it lies inside a OneDrive folder ask with a short dialog** ("Export to a OneDrive folder?", the sentence of B37, and the buttons "Choose another folder" (the default), "Export here" and Cancel). Encrypted archives are not asked about. Alternatives: an Informational note bar after the save (the previous draft: too late), no extra UI (the footers already say the files are not encrypted), or start the picker outside Documents. Related: D29. **Resolved by owner decision, 2026-10-07: no OneDrive warning for plain Markdown export or an archive; it is the person's risk. The dialog is not built (and B37 is settled with it), and the Windows pages no longer describe it.**

Spec: [platforms/windows/screens/settings-backup.md](platforms/windows/screens/settings-backup.md), [platforms/windows/flows/export-markdown.md](platforms/windows/flows/export-markdown.md), [platforms/windows/flows/export-archive.md](platforms/windows/flows/export-archive.md), [platforms/windows/platform.md](platforms/windows/platform.md) (16). Code: `Model/MarkdownExportOperations.swift`.

**D47.** Where Sync status lives on Windows. The Apple Sync status button is in the editor header, which on Windows exists only on the entry page at the small width, so the control is unreachable from the Journals and entries pages. **Draft default, the review's recommendation: the title bar's trailing area at every width**, shown only when the person must act: one place, reachable from every page and from Settings, nothing depends on the layout. Alternative: the editor header at the large and medium widths and the title bar at the small width (the previous draft), which keeps the window chrome emptier but puts the control in two places.

Spec: [platforms/windows/screens/sync-status.md](platforms/windows/screens/sync-status.md), [platforms/windows/messages.md](platforms/windows/messages.md), [platforms/windows/screens/library-window.md](platforms/windows/screens/library-window.md), [platforms/windows/platform.md](platforms/windows/platform.md) (4.2). Code: none yet.

**D48.** A failed save while typing. The spec shows the alert after every failed attempt (see A1), but a modal dialog that opens under the caret takes focus and swallows keystrokes. **Draft default, confirmed by the design review** (it is also Microsoft's `InfoBar` example, an error while saving when triggered automatically): while typing, only the persistent error `InfoBar` above the title plus one Narrator notification with `common.saveFailed`; the dialog is kept for failures that follow a deliberate action (Try again, leaving the entry, an operation that needs a saved entry, closing, locking). Alternative: the spec’s dialog every time, which interrupts typing. Decided with A1.

Spec: [platforms/windows/flows/save-failure.md](platforms/windows/flows/save-failure.md), [platforms/windows/messages.md](platforms/windows/messages.md), [flows/save-failure.md](flows/save-failure.md). Code: `Model/AppModel.swift`, `Views/RootView.swift`.

**D49.** The Sync page’s message surface. Draft default, confirmed by the design review (the mapping files agree): one non-closable `InfoBar` at the top of the page carries the footer message at the severity of the messages mapping, with the state’s action as its button; the server card holds the action when there is no bar (Sync now) or the message has none; the not-connected text and the two library notes are the status card’s description, never bars. The action therefore appears once. Alternative: the action always stays in the server card next to the address, as in the spec’s layout, and the bar carries only the message.

Spec: [platforms/windows/screens/settings-sync.md](platforms/windows/screens/settings-sync.md), [platforms/windows/messages.md](platforms/windows/messages.md), [platforms/windows/flows/sync-recovery.md](platforms/windows/flows/sync-recovery.md), [screens/settings-sync.md](screens/settings-sync.md). Code: `Views/SettingsView.swift`, `Views/SyncNowRows.swift`.

**D50.** Side by side in the conflict reviews. At 1008 epx and wider the entry review, the journal review and the deletion review could show the two versions side by side, with a `SelectorBar` below that. The spec has one version at a time at every width, so side by side is a presentation difference only; the actions and copy are unchanged. **Draft default, the review's recommendation: defer it.** Ship the spec's one-version-at-a-time control at every width in version 1 (less to build, identical everywhere) and add side by side later if testing shows it matters. Alternative: side by side at large width (the previous draft).

Spec: [platforms/windows/screens/conflict-review.md](platforms/windows/screens/conflict-review.md), [platforms/windows/screens/entry-conflict.md](platforms/windows/screens/entry-conflict.md), [platforms/windows/flows/resolve-conflict.md](platforms/windows/flows/resolve-conflict.md). Code: `Views/EntryConflictReview.swift`.

**D51.** Update messages on Windows. The app cannot update itself; the Microsoft Store does. **Draft default, confirmed by the design review:** a second link, “Get updates” (B38), that opens the Store’s updates page, shown with `messages.sync.appUpdateNeeded`, `settings.archiveImport.error.newerVersion` and the unsupported conflict form, only for Store-signed installs, and nothing else changes. Alternative: no link (the person finds Store updates alone), or a link to the project’s releases page for installs from outside the Store (D22).

Spec: [platforms/windows/messages.md](platforms/windows/messages.md), [platforms/windows/screens/sync-status.md](platforms/windows/screens/sync-status.md), [platforms/windows/screens/archive-import.md](platforms/windows/screens/archive-import.md), [platforms/windows/screens/conflict-review.md](platforms/windows/screens/conflict-review.md), [platforms/windows/platform.md](platforms/windows/platform.md) (18). Code: none yet.

**D52.** Where a journal’s “changes to review” are signalled on Windows. The spec has the Review Changes entry point in a journal settings surface, which Windows does not have. **Draft default, with the review's addition:** an attention-dot `InfoBadge` on the journal’s navigation row, `common.reviewChanges` as the first item of the journal context menu and the Journal actions menu (the dimmed Rename, Default template and Merge items stay), and a Warning `InfoBar` at the top of that journal’s entry list. At the medium and small widths the navigation pane is hidden, so a dot alone is invisible exactly when a conflict needs attention. Alternative: the dot and menu items only (the previous draft), which is quieter.

Spec: [platforms/windows/screens/conflict-review.md](platforms/windows/screens/conflict-review.md), [platforms/windows/flows/resolve-conflict.md](platforms/windows/flows/resolve-conflict.md), [platforms/windows/screens/journals.md](platforms/windows/screens/journals.md), [screens/conflict-review.md](screens/conflict-review.md). Code: `Views/JournalMoreMenu.swift`.

**D53.** The rating request on Windows. With no privacy cover (D28) the earlier technical point, whether the Store’s own dialog deactivating the window triggers the cover, is moot and the request runs with App lock on or off. The owner decision that remains: what counts as “asked”. **Draft default, the review's recommendation:** record only `Succeeded` and `CanceledByUser` results as asked, and retry at a later natural pause (a later session, at most one attempt per session) after `NetworkError` or an error, because a failed call asked nobody; the spec says to always record it. The request runs only for Store-signed installs, and the app never asks how the person likes it first, per Store policy. Alternative: always record it, as the spec says.

Spec: [platforms/windows/flows/rating-request.md](platforms/windows/flows/rating-request.md), [flows/rating-request.md](flows/rating-request.md), [platforms/windows/platform.md](platforms/windows/platform.md) (20, 28). Code: `Model/ReviewRequest.swift`.

**D54.** A second prompt after Win+L. After Win+L and signing in to Windows, the person has just proved who they are to Windows, then must prove it again to the app, because the spec says a screen lock locks. Draft default: keep the spec's rule and record the friction as a known cost (it is stated in the App Lock flow and in platform.md 13); no new setting in version 1. Alternative, from the design review: a Privacy option "Unlock with Windows sign-in" that skips the second prompt after a session lock (not after the inactivity timer or Ctrl+L), at the price of one more setting, new copy and a weaker lock after a shared PC's session unlock. Ask the owner.

Spec: [platforms/windows/flows/app-lock.md](platforms/windows/flows/app-lock.md), [platforms/windows/platform.md](platforms/windows/platform.md) (13), [flows/app-lock.md](flows/app-lock.md). Code: `Model/AppLockOperations.swift`.

**D55.** When the person chooses Don’t Allow on an agent request and the server does not answer, the request comes back on the next refresh and nothing says the decline did not arrive (the code sends it with `try?`). The spec says the page tells the agent and says nothing about this case. Recommendation: show a short message when the decline fails; the owner decides whether quiet is enough. **Resolved by owner decision, 2026-10-09:** follow the recommendation: when Don't Allow can't reach the server, the page shows a short message and the request stays, so the person can try again. Built in 1.1 (design gate, copy key in copy/en.json). **Built in 1.1:** `settings.agents.requests.declineFailed`, shown as the footer of the Requests section; the decline is owned by something that lives as long as the app (flows/allow-agent.md step 8).

Spec: [flows/allow-agent.md](flows/allow-agent.md), [screens/allow-agent.md](screens/allow-agent.md). Code: `Views/ServerAgentsView.swift:564-567`, `Model/ServerAgentsController.swift:114-117`.

**D56.** The Windows mapping of the library problem screen (build 18). The spec now has a screen of its own for a library that can't be opened, with Try Again, Import Archive…, Erase Journals and Settings… and Learn More, and a lock screen group for a missing device key; the Windows page for it still maps the earlier lock-screen note. No default is proposed here: it needs a Windows design that passes the design gate, including the device name in the advice (“PC”), the update channel in `library.problem.newerVersion.message`, and Windows Hello for Erase and Import. **Resolved by owner decision, 2026-10-09:** the Windows agent designs this screen when it builds the Windows client, from the neutral spec, through the design gate; no default is set now.

Spec: [screens/unavailable-content.md](screens/unavailable-content.md), [platforms/windows/screens/unavailable-content.md](platforms/windows/screens/unavailable-content.md). Code: `Views/LibraryProblemView.swift`, `Model/LibraryProblem.swift`.
