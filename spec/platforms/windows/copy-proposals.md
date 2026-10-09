# Windows copy proposals

Every Windows wording the mapping files propose, in one table for the owner to review. **Nothing here is in [copy/en.json](../../copy/en.json).** A proposal becomes a catalog variant only after the owner approves the casing rule (D21) and the question named in its last column ([open-questions.md](../../open-questions.md)). Which variant: the casing rows (casing, label in a sentence) are `sentence` variants, named for the casing and shared with Android; every other row (vocabulary, ellipsis, shortcut text, removed, new) is a `windows` variant, written in sentence case itself. The mapping files' Copy differences sections say why each string differs on one page; this file is the single list.

## How to read the table

- **Copy key.** An existing key, or a group written with a star (`library.lock.method.*`). A key that does not exist yet is written in two parts, for example “settings ▸ backup.lastExported”, because the checker rejects dotted names that are not in the catalog; join the parts with a dot when it is added.
- **Default text.** The text in `copy/en.json` today. Where the key already has a Mac variant it is shown after the default as “Mac:”. Non-breaking spaces in the catalog are shown here as plain spaces; the tool that writes the variants keeps them.
- **Proposed Windows text.** The text for a `{"default": …, "sentence": …}` variant (casing and label-in-a-sentence rows) or a `{"default": …, "windows": …}` variant (all other rows). “Not shown” means the Windows app never shows the string (B30). Plural keys show both forms.
- **Category.** Vocabulary (Windows names for Apple things, 12.3), ellipsis (12.2), casing (12.1), label in a sentence (B27), shortcut text (12.3), removed (never shown) or new (a string the catalog does not have).
- **Rule or question.** A section of [platform.md, 12](platform.md#12-copy-casing-ellipses-and-vocabulary) or the id of the open question that decides it. A row may be approved or changed on its own.

Sentence case also applies to about 340 more short strings that the mapping files name only by their quoted text (“Add device”, “Show new code”, “Don’t add”, and so on); they follow the rule of [platform.md, 12.1](platform.md#121-casing) and are produced by the tool, not listed. The rows below are the strings that a mapping file names by key, plus every string that needs more than the casing rule. Feature names inside a sentence are lower case (“turn on app lock”); a label that a sentence names as an instruction is written as it is shown (“select Try again”); a label that continues a phrase is lower case (“from this device”) (B27).

## Applying the proposals

1. The owner decides D21 (the casing rule, the protected terms, the Windows names) and each question named in the last column. A row can be approved, changed or dropped on its own; a dropped row leaves the default text.
2. The tool described in D21 writes the approved casing rows into `copy/en.json` as `sentence` variants and the other approved rows as `windows` variants (keeping any `mac` variant), adds the approved new keys with a context, and marks the “not shown” rows as B30 decides. The checker then fails if a stored `sentence` variant differs from what the rule produces, except for the reviewed exceptions in `copy/`. Android reuses the `sentence` variants and adds an `android` variant only where its words differ.
3. In the same change, each mapping file’s Copy differences section shrinks to a link to the catalog (the table stays in the file for what the rows cannot say, such as layout-dependent wording), this file is deleted, and [README.md](README.md) loses its pointer to it.
4. Until then, mapping files write labels as the default text and say “sentence case on Windows” ([platform.md, 12.4](platform.md#124-other-copy-rules)).

## The table

| Copy key | Default text | Proposed Windows text | Category | Rule or question |
| --- | --- | --- | --- | --- |
| `common.journalGone` | That journal is no longer available. Choose another journal. | That journal is no longer available. Select another journal. | vocabulary | B26 |
| `library.templateChooser.templateGone` | This template is no longer available. Choose another template. | This template is no longer available. Select another template. | vocabulary | B26 |
| `library.recoveryNotice.legacy` | This entry was deleted by an earlier version of My Journal. Choose a journal to restore this entry. | This entry was deleted by an earlier version of My Journal. Select a journal to restore this entry. | vocabulary | B26 |
| `messages.image.tooLarge` | Choose an image smaller than 25 MB. | Select an image smaller than 25 MB. | vocabulary | B26 |
| `editor.imageImport.cause.mixed` | Try again, or choose other images. | Try again, or select other images. | vocabulary | B26 |
| `library.entryList.empty.noTemplatesHelp` | To create a template, open an entry and choose Save as Template. | To create a template, open an entry and select Save as template. | vocabulary | B26, B27 |
| `settings.addDevice.scanInstructions` | On your iPhone or iPad, choose Connect to a Server, then Scan Code. If it already has journals, Connect to a Server is in Settings ▸ Sync. | On your iPhone or iPad, select Connect to a server, then Scan code. If it already has journals, Connect to a server is in Settings ▸ Sync. | vocabulary | B26, B27 |
| `settings.addDevice.codeFooter` | On the new device, choose Connect to a Server, then Add This Device. | On the new device, select Connect to a server, then Add this device. | vocabulary | B26, B27 |
| `settings.connect.addThisDevice.instructions` | On a connected device, open Settings ▸ Sync ▸ Devices ▸ Add Device, then choose Enter Code Instead. | On a connected device, open Settings ▸ Sync ▸ Devices ▸ Add Device, then select Enter code instead. | vocabulary | B26, B27 |
| `settings.sync.stopSyncing.message` | Your journals stay on this device. To sync again later, choose Connect to a Server in Settings ▸ Sync. | Your journals stay on this device. To sync again later, select Connect to a server in Settings ▸ Sync. | vocabulary | B26, B27 |
| `messages.connection.serverChanged` | This server has changed since you checked it. Choose Continue to check it again. | This server has changed since you checked it. Select Continue to check it again. | vocabulary | B26 |
| `messages.connection.setUpElsewhere` | This server has just been set up. Choose it again to sign in. | This server has just been set up. Select it again to sign in. | vocabulary | B26 |
| `messages.save.before.tryAgain` | Your changes aren’t saved yet. Choose Try Again, then repeat what you were doing. | Your changes aren’t saved yet. Select Try again, then repeat what you were doing. | vocabulary | B26, B27 |
| `messages.save.before.goBack` | Your changes aren’t saved yet. Go back to your entry, choose Try Again under Not Saved, then repeat what you were doing. | Your changes aren’t saved yet. Go back to your entry, select Try again under Not saved, then repeat what you were doing. | vocabulary | B26, B27 |
| `messages.sync.pausedForSaveFailure` | Syncing is paused until your changes are saved. Choose Try Again in the entry. | Syncing is paused until your changes are saved. Select Try again in the entry. | vocabulary | B26, B27 |
| `messages.sync.localDataUnreadable` | My Journal couldn’t read its data on this device. Your journals haven’t been changed. To keep a copy, choose Export Archive in Settings > Backup. | My Journal couldn’t read its data on this device. Your journals haven’t been changed. To keep a copy, select Export archive in Settings > Backup. | vocabulary | B26, B27 |
| `library.moveEntry.renameExplanation` | Journals with the same name can’t be chosen. To move this entry to one of them, rename it in the Journals list first. (Mac: Journals with the same name can’t be chosen. To move this entry to one of them, rename it in the sidebar first.) | Journals with the same name can’t be selected. To move this entry to one of them, rename it in the navigation pane first. (Small layout: “… in the Journals list first.”) | vocabulary | B26, B28 |
| `messages.writingPaused.connecting` | Writing is paused while this Mac connects to your server. | Writing is paused while this PC connects to your server. | vocabulary | 12.3 |
| `messages.writingPaused.connectionFailed` | This Mac couldn’t finish connecting to your server. Try again, or cancel to keep writing. | This PC couldn’t finish connecting to your server. Try again, or cancel to keep writing. | vocabulary | 12.3 |
| `messages.save.mac.title` | Couldn’t save changes on this Mac. | Couldn’t save changes on this PC. | vocabulary | 12.3, B39 |
| `settings.agents.thisMac` | this Mac | this PC | vocabulary | 12.3 |
| `settings.agents.reach.local` | Only agents running on this Mac, such as Claude Code, can use this address. | Only agents running on this PC, such as Claude Code, can use this address. | vocabulary | 12.3 |
| `editor.imageDescriptions.intro` | Describe what matters in each image. Descriptions help people using VoiceOver. | Describe what matters in each image. Descriptions help people using Narrator. | vocabulary | B28 |
| `editor.imageImport.cause.unavailable` | They may still be downloading from iCloud. Try again later. | They may still be downloading. Try again later. | vocabulary | 12.3 |
| `messages.image.unavailable` | The image couldn’t be added. It may still be downloading from iCloud. Try again later. | The image couldn’t be added. It may still be downloading. Try again later. | vocabulary | 12.3 |
| `messages.library.cannotOpen` | Your journals couldn’t be opened. Quit and reopen My Journal. | Your journals couldn’t be opened. Close My Journal and open it again. | vocabulary | 12.3 |
| `messages.library.deviceKeyUnavailable` | Your device key is unavailable. Use your recovery key to unlock your journals. | Your device key is unavailable. Use your master password to unlock your journals. | vocabulary | B35 |
| `messages.entry.dateChanged` | This entry’s date changed. Close this sheet and try again. | This entry’s date changed. Close this dialog and try again. | vocabulary | 12.3 |
| `settings.addDevice.enterCodeInstead.footer` | For a Mac or a device that can’t scan the code. | For a computer or a device that can’t scan the code. | vocabulary | B28 |
| `settings.general.formatAsYouType.footer` | Typing “- ”, “1. ”, “# ” or “> ” at the start of a line formats it. Press Delete right after to keep what you typed. | Typing “- ”, “1. ”, “# ” or “> ” at the start of a line formats it. Press Backspace right after to keep what you typed. | vocabulary | 12.3 |
| `settings.pane.general` | General | General | none: the same text on every platform since 1.1 | 12.3 |
| `library.menu.view.showSidebarAndList` | Show Sidebar and List | Show all panes | vocabulary | 12.3 |
| `settings.lock.unlockWith` | Unlock with {method} | Unlock with Windows Hello | vocabulary | 12.3, D25 |
| `library.lock.method.*` | Face ID, Touch ID, Optic ID, Passcode, Login Password | Windows Hello (one method) | vocabulary | 12.3, D25 |
| `settings.privacy.appLock.require` | Require {method} | Require Windows Hello | vocabulary | 12.3, D25 |
| `library.lock.phrase.*` | “{method} or your {device} passcode” and similar | “Windows Hello” as the method | vocabulary | 12.3, D25 |
| `settings.lock.turnedOff.passcodeRemoved` | This {device} no longer has a passcode… (Mac: Your Mac user no longer has a login password…) | Not shown: App lock pauses instead of turning itself off (the paused bar below) | removed | B32, D42 |
| `settings.privacy.appLock.noPasscode` | To use App Lock, set a passcode for this {device} in Settings. (Mac: To use App Lock, set a login password for your Mac user in System Settings.) | To use app lock, set up Windows Hello in Settings > Accounts > Sign-in options. | vocabulary | B32, D25 |
| `settings.privacy.appLock.unavailable` | App Lock isn’t available on this device. | App lock isn’t available on this PC. | vocabulary | B32 |
| `settings.privacy.appLock.footerInactive` |  It also locks when you haven’t used it for the time you choose, and when your Mac sleeps or its screen locks. |  It also locks when you haven’t used it for the time you choose, and when this PC sleeps or is locked. | vocabulary | B28 |
| `settings.privacy.appLock.footerSleepOnly` |  It also locks when your Mac sleeps or its screen locks. |  It also locks when this PC sleeps or is locked. | vocabulary | B28 |
| `settings.privacy.appLock.reason.turnOn` | Turn on App Lock (Mac: turn on App Lock) | Turn on app lock | vocabulary | 12.3: the default (capitalised) form, not the Mac variant |
| `settings.privacy.appLock.reason.turnOff` | Turn off App Lock (Mac: turn off App Lock) | Turn off app lock | vocabulary | 12.3: the default (capitalised) form, not the Mac variant |
| `settings.privacy.appLock.reason.change` | Change App Lock settings (Mac: change App Lock settings) | Change app lock settings | vocabulary | 12.3: the default (capitalised) form, not the Mac variant |
| `settings.privacy.appLock.reason.unlock` | Unlock your journals (Mac: unlock your journals) | The default form: Unlock your journals | vocabulary | 12.3: the default (capitalised) form, not the Mac variant |
| `settings.erase.authReason` | Erase journals on this device (Mac: erase journals on this device) | The default form: Erase journals on this device | vocabulary | 12.3: the default (capitalised) form, not the Mac variant |
| `settings.backup.markdownReason` | Export your journals as files that aren’t encrypted (Mac: export your journals as files that aren’t encrypted) | The default form: Export your journals as files that aren’t encrypted | vocabulary | 12.3: the default (capitalised) form, not the Mac variant |
| `settings.backup.markdownReasonUnencrypted` | Export your journals as Markdown files (Mac: export your journals as Markdown files) | The default form: Export your journals as Markdown files | vocabulary | 12.3: the default (capitalised) form, not the Mac variant |
| `settings.addDevice.authReason` | Add “{device}” to your journals (Mac: add “{device}” to your journals) | The default form: Add “{device}” to your journals | vocabulary | 12.3: the default (capitalised) form, not the Mac variant |
| `settings.changePassword.authReason` | Set a new password for your journals (Mac: set a new password for your journals) | The default form: Set a new password for your journals | vocabulary | B23, 12.3: the default (capitalised) form, not the Mac variant |
| `library.entryActions.deletePermanently` | Delete Permanently… | Delete permanently | ellipsis | 12.2 |
| `library.menu.file.deleteAll` | Delete All in Recently Deleted… | Delete all in Recently deleted | ellipsis | 12.2 |
| `library.recentlyDeleted.deleteAll` | Delete All (Mac: Delete All…) | Delete all | ellipsis | 12.2 |
| `library.journalActions.deleteJournal` | Delete Journal… | Delete journal | ellipsis | 12.2 |
| `settings.sync.stopSyncing` | Stop Syncing… | Stop syncing | ellipsis | 12.2 |
| `settings.sync.stopSyncing.confirm` | Stop Syncing | Stop syncing | ellipsis | 12.2 |
| `settings.erase.button` | Erase Journals and Settings… | Erase journals and settings | ellipsis | 12.2 |
| `common.share` | Share… | Share | ellipsis | 12.2; the image actions use it, the Agent access page does not |
| `settings.devices.revoke` | Revoke Access… | Revoke access | ellipsis | 12.2 |
| `messages.syncStatus.settings` | Sync Settings… | Sync settings | ellipsis | 12.2 |
| `common.exportArchive` | Export Archive… | Export archive… | casing | 12.1; the ellipsis stays (12.2) |
| `messages.conflict.kept.clear` | Clear List | Clear list | casing | 12.1 |
| `messages.conflict.kept.showOther` | Show Other Version | Show other version | casing | 12.1 |
| `messages.conflict.kept.section` | Changed on Two Devices | Changed on two devices | casing | 12.1 |
| `library.recentlyDeleted.restoreJournal` | Restore Journal | Restore journal | casing | 12.1 |
| `library.menu.file.useTemplate` | Use a Template… | Use a template… | casing | 12.1; the ellipsis stays (12.2) |
| `editor.image.saveImageAs` | Save Image As… | Save image as… | casing | 12.1; the ellipsis stays (12.2) |
| `common.connectToServer` | Connect to a Server… | Connect to a server… | casing | 12.1; the ellipsis stays (12.2) |
| `common.importArchive` | Import Archive… | Import archive… | casing | 12.1; the ellipsis stays (12.2) |
| `settings.connect.signIn.useDevice` | Use a Connected Device Instead… | Use a connected device instead… | casing | 12.1; the ellipsis stays (12.2) |
| `settings.connect.addThisDevice.useRecoveryCode` | Use a Recovery Code Instead… | Use a recovery code instead… | casing | 12.1; the ellipsis stays (12.2) |
| `settings.archiveImport.title` | Import Archive | Import archive | casing | 12.1 |
| `settings.archiveImport.restore` | Restore Journals | Restore journals | casing | 12.1 |
| `settings.archiveImport.importAsNew` | Import as New Journals | Import as new journals | casing | 12.1 |
| `settings.archiveImport.imported` | Journals Imported | Journals imported | casing | 12.1 |
| `settings.archiveImport.restored` | Journals Restored | Journals restored | casing | 12.1 |
| `settings.archiveImport.opening` | Opening Archive… | Opening archive… | casing | 12.1 |
| `settings.archiveImport.importing` | Importing Journals… | Importing journals… | casing | 12.1 |
| `common.passwordOrRecoveryKey` | Password or Recovery Key | Password or recovery key | casing | 12.1 |
| `library.changeDate.title` | Change Date | Change date | casing | 12.1 |
| `library.entryList.empty.noEntries` | No Entries | No entries | casing | 12.1 |
| `library.entryList.empty.noResults` | No Results | No results | casing | 12.1 |
| `library.entryList.empty.noDeletedItems` | No Deleted Items | No deleted items | casing | 12.1 |
| `editor.imageDescriptions.copy` | Copy Descriptions | Copy descriptions | casing | 12.1 |
| `editor.imageDescriptions.reload` | Reload Images | Reload images | casing | 12.1 |
| `editor.imageDescriptions.title` | Image Descriptions | Image descriptions | casing | 12.1 |
| `library.nameTaken.title` | Name Taken | Name taken | casing | 12.1 |
| `settings.lock.turnedOff.title` | App Lock Is Off | Not shown: App lock pauses instead of turning itself off | removed | B32, D42 |
| `settings.privacy.appLock.error.turnOn` | Couldn’t Turn On App Lock | Couldn’t turn on app lock | casing | 12.1 |
| `settings.privacy.appLock.error.turnOff` | Couldn’t Turn Off App Lock | Couldn’t turn off app lock | casing | 12.1 |
| `settings.privacy.appLock.inactive.error` | Couldn’t Change Setting | Couldn’t change setting | casing | 12.1 |
| `library.welcome.start` | Start a Journal | Start a journal | casing | 12.1 |
| `settings.backup.openFailed` | Couldn’t Open Archive | Couldn’t open archive | casing | 12.1 |
| `library.deletePermanently.title` | Delete “{name}” Permanently? | Delete “{name}” permanently? | casing | 12.1 |
| `library.deletePermanently.titleWithEntries` | Delete “{name}” and Its Entries Permanently? | Delete “{name}” and its entries permanently? | casing | 12.1 |
| `library.menu.help.source` | Source Code on GitHub | Source code on GitHub | casing | 12.1 |
| `common.chooseMasterPassword` | Choose a Master Password | Choose a master password | casing | 12.1 |
| `settings.changePassword.forgot` | Forgot Password? | Forgot password? | casing | 12.1 |
| `settings.backup.archive.changePassword` | Not sure of your password? Change Password… | Not sure of your password? Change password… | casing | 12.1 |
| `common.masterPassword` | Master Password | Master password | casing | 12.1 |
| `common.showPassword` | Show Password | Show password | casing | 12.1 |
| `library.templateChooser.useTemplate` | Use a Template | Use a template | casing | 12.1 |
| `library.window.selectEntry` | Select an Entry | Select an entry | casing | 12.1 |
| `library.deleteAll.changed.title` | one: 1 Item Couldn’t Be Deleted / other: {count} Items Couldn’t Be Deleted | one: 1 item couldn’t be deleted / other: {count} items couldn’t be deleted | casing | 12.1 |
| `editor.imageImport.addingSeveral` | Adding Images… {done} of {total} | Adding images… {done} of {total} | casing | 12.1 |
| `settings.agents.connect.guide` | How to Connect an Agent | How to connect an agent | casing | 12.1 |
| `settings.allowAgent.number.field` | Number Shown on the Page | Number shown on the page | casing | 12.1 |
| `settings.general.formatAsYouType` | Format Markdown as You Type (Mac: Format Markdown as you type) | Format Markdown as you type | casing | 12.1 |
| `settings.sync.footer.howToSetUp` | How to Set Up a Server | How to set up a server | casing | 12.1 |
| `library.deleteAll.changed.message` | one: It changed since you chose to delete it. It’s still in Recently Deleted. / other: They changed since you chose to delete them. They’re still in Recently Deleted. | one: It changed since you chose to delete it. It’s still in Recently deleted. / other: They changed since you chose to delete them. They’re still in Recently deleted. | label in a sentence | B27, 12.1 |
| `library.deleteAll.held.newerVersion` | one: 1 item was saved by a newer version and stays in Recently Deleted. Update My Journal to delete it. / other: {count} items were saved by a newer version and stay in Recently Deleted. Update My Journal to delete them. | one: 1 item was saved by a newer version and stays in Recently deleted. Update My Journal to delete it. / other: {count} items were saved by a newer version and stay in Recently deleted. Update My Journal to delete them. | label in a sentence | B27, 12.1 |
| `library.deleteAll.held.other` | one: 1 item can’t be deleted yet and will stay in Recently Deleted. / other: {count} items can’t be deleted yet and will stay in Recently Deleted. | one: 1 item can’t be deleted yet and will stay in Recently deleted. / other: {count} items can’t be deleted yet and will stay in Recently deleted. | label in a sentence | B27, 12.1 |
| `library.deleteJournal.message` | one: Its entry moves to Recently Deleted. / other: Its {count} entries move to Recently Deleted. | one: Its entry moves to Recently deleted. / other: Its {count} entries move to Recently deleted. | label in a sentence | B27, 12.1 |
| `library.recentlyDeleted.deleteAll.help` | Permanently delete all items in Recently Deleted | Permanently delete all items in Recently deleted | label in a sentence | B27, 12.1 |
| `library.recoveryNotice.entry` | This entry is in Recently Deleted. | This entry is in Recently deleted. | label in a sentence | B27, 12.1 |
| `library.recoveryNotice.journalDeleted` | The journal is in Recently Deleted. | The journal is in Recently deleted. | label in a sentence | B27, 12.1 |
| `library.recoveryNotice.template` | This template is in Recently Deleted. | This template is in Recently deleted. | label in a sentence | B27, 12.1 |
| `library.restoreJournal.explanation` | Entries deleted with this journal will return, including entries that sync later. Entries you deleted separately will stay in Recently Deleted. | Entries deleted with this journal will return, including entries that sync later. Entries you deleted separately will stay in Recently deleted. | label in a sentence | B27, 12.1 |
| `messages.lifecycle.alreadyDeleted` | This journal is already in Recently Deleted. | This journal is already in Recently deleted. | label in a sentence | B27, 12.1 |
| `settings.archiveImport.recentlyDeleted` | {count} in Recently Deleted | {count} in Recently deleted | label in a sentence | B27, 12.1 |
| `settings.backup.markdown.footer` | Saves your journals and their images as Markdown files that other apps can open. The files aren’t encrypted. To keep a copy you can import later, use Export Archive. | Saves your journals and their images as Markdown files that other apps can open. The files aren’t encrypted. To keep a copy you can import later, use Export archive. | label in a sentence | B27, 12.1 |
| `settings.backup.markdown.footerUnencrypted` | Saves your journals and their images as Markdown files that other apps can open. To keep a copy you can import later, use Export Archive. | Saves your journals and their images as Markdown files that other apps can open. To keep a copy you can import later, use Export archive. | label in a sentence | B27, 12.1 |
| `settings.connect.merge.footerLeaveOut` | To leave something out, cancel and delete it first, including from Recently Deleted. | To leave something out, cancel and delete it first, including from Recently deleted. | label in a sentence | B27, 12.1 |
| `settings.privacy.appLock.footer` | {who} is needed to open My Journal.{automatic} App Lock doesn’t change how your journals are encrypted. | {who} is needed to open My Journal.{automatic} App lock doesn’t change how your journals are encrypted. | label in a sentence | B27, 12.1 |
| `library.toolbar.editorOnly.help` | Show Editor Only (⇧⌘D) | Not shown: Show editor only has no header button on Windows; the View menu item shows its own shortcut | removed | S15, 12.3 |
| `library.toolbar.editorOnly.helpActive` | Show Sidebar and List (⇧⌘D) | Not shown: as above; the View menu item reads "Show all panes" (`library.menu.view.showSidebarAndList`) | removed | S15, 12.3 |
| `settings.connect.addThisDevice.connectHelp` | Connect (⌘Return) | Not shown (WinUI adds the accelerator to tooltips and Narrator reads it) | shortcut text | 12.3 |
| `settings.connect.addThisDevice.connectHint` | Press Command-Return to connect. | Not shown (WinUI adds the accelerator to tooltips and Narrator reads it) | shortcut text | 12.3 |
| `settings.connect.merge.help` | Merge (⌘Return) | Not shown (WinUI adds the accelerator to tooltips and Narrator reads it) | shortcut text | 12.3 |
| `settings.connect.merge.hint` | Press Command-Return to merge. | Not shown (WinUI adds the accelerator to tooltips and Narrator reads it) | shortcut text | 12.3 |
| `library.nameTaken.title` | Name Taken | Not shown: the name field shows messages.journal.nameTaken itself | removed | B30 |
| `library.nameTaken.message` | A journal named “{name}” already exists. Choose a different name. | Not shown: the name field shows messages.journal.nameTaken itself | removed | B30 |
| `settings.agents.shareLabel` | Share MCP Server Address | Not shown: no Share on the Agent access page, as on the Mac | removed | 12.3 |
| `settings.sync.footer.formerMacServer` | My Journal no longer runs a server on this Mac, so this Mac stopped syncing. Your journals are saved on this Mac. To sync again, connect to a server. | Not shown: Mac-only state | removed | 12.3 |
| `settings.sync.footer.learnMore` | Learn More | Not shown: Mac-only state | removed | 12.3 |
| `settings.erase.footerFormerServer` | A copy of your journals from the server this Mac used to run isn’t removed. | Not shown: Mac-only state | removed | 12.3 |
| `settings.lock.pinRetired` | App Lock now uses {phrase} instead of a PIN. | Not shown: Windows never had an app PIN | removed | 12.3 |
| `settings.lock.turnedOff.pinRetired` | App Lock now uses your {device} passcode instead of a PIN. This {device} doesn’t have a passcode, so App Lock is off. | Not shown: Windows never had an app PIN | removed | 12.3 |
| `settings.connect.nearby.denied` | To find servers automatically, turn on Local Network for My Journal in Settings. | Not shown: Windows has no Local Network prompt | removed | 12.3, platform.md 32 |
| `settings.connect.scanCode` | Scan Code | Not shown: a PC does not scan (D24) | removed | D24 |
| `settings.connect.scanCode.footer` | On a connected device, open Settings ▸ Sync ▸ Devices ▸ Add Device, then scan the code it shows. | Not shown: a PC does not scan (D24) | removed | D24 |
| `settings.connect.scanAgain` | Scan Again | Not shown: a PC does not scan (D24) | removed | D24 |
| `settings.connect.finish.*` | (the group) | Not shown: a PC does not scan (D24) | removed | D24 |
| `settings.scan.*` | (the group) | Not shown: a PC does not scan (D24) | removed | D24 |
| `settings.recoveryKey.*` | (the group) | Not shown: recovery key screen is Apple-only (D11) | removed | D11 |
| `settings.locked` | Unlock My Journal to open Settings. | Not shown: the lock page replaces the window | removed | B30 |
| `messages.encryption.background` | Encryption stopped because My Journal was in the background. Keep My Journal open and try again. | Not shown: desktop apps are not suspended in the background | removed | B30 |
| `messages.writingPaused.showConnection` | Show Connection | Not shown: the flow’s dialog is modal | removed | B30 |
| `library.templateChooser.title` | Choose a Template | Not shown: the flyout has no title or Cancel | removed | B30 |
| `library.templateChooser.popoverTitle` | Use a Template… | Not shown: the flyout has no title or Cancel | removed | B30 |
| `editor.insertImage.chooseFile` | Choose File… | Not shown: the Insert image button opens the picker at once | removed | B30 |
| `editor.format.state.on` | On | Not shown: Narrator speaks toggle state | removed | B30 |
| `editor.format.state.off` | Off | Not shown: Narrator speaks toggle state | removed | B30 |
| `editor.format.state.mixed` | Mixed | Not shown: Narrator speaks toggle state | removed | B30 |
| `common.format` | Format | Not shown: the formatting bar has no header | removed | B30 |
| `editor.format.close` | Close | Not shown: the formatting bar has no close button | removed | B30 |
| `editor.format.moreHeadings` | More Headings | Not shown: the paragraph-style drop-down lists Heading 1 to 6 | removed | B30, D20 |
| `library.lock.device.*` | (the group) | Not shown: device names are not shown | removed | 12.3 |
| `editor.insertImage.photoLibrary` | Photo Library | Not shown: no photo library on Windows (D24) | removed | D24 |
| `editor.insertImage.takePhoto` | Take Photo | Not shown: no camera route in version 1 (D24) | removed | D24 |
| `editor.insertImage.cameraOff.*` | (the group) | Not shown: no camera route in version 1 (D24) | removed | D24 |
| `editor.image.saveToPhotos` | Save to Photos | Not shown: no Photos on Windows (D24) | removed | D24 |
| `editor.image.photosOff.*` | (the group) | Not shown: no Photos on Windows (D24) | removed | D24 |
| `editor.announce.savedToPhotos` | Saved to Photos | Not shown: no Photos on Windows (D24) | removed | D24 |
| `editor.image.saveToPhotosFailed` | The image couldn’t be saved to Photos. | Not shown: no Photos on Windows (D24) | removed | D24 |
| `editor.permission.*` | (the group) | Not shown: no camera or photo permission prompt (D24) | removed | D24 |
| settings ▸ privacy.appLock.paused.title (new; area settings) | none | App lock is paused | new | B32, D42 |
| settings ▸ privacy.appLock.paused.notSetUp (new; area settings) | none | Windows Hello isn’t set up on this PC, so your journals open without it. | new | B32, D42 |
| settings ▸ privacy.appLock.paused.unavailable (new; area settings) | none | Windows Hello isn’t available right now, so your journals open without it. App lock turns back on when it is. | new | B32, D42 |
| settings ▸ privacy.appLock.paused.policy (new; area settings) | none | Your organization turned off Windows Hello, so your journals open without it. | new | B32, D42 |
| settings ▸ privacy.keyNotSaved (new; area settings) | none | This PC couldn’t save your device key. My Journal will ask for your password again the next time it opens. | new | D43 |
| editor ▸ imageDescriptions.saveTitle (new; area editor) | none | Save description changes? | new | B41, D39 |
| common ▸ dontSave (new; area common) | none | Don’t save | new | B41, D39 |
| settings ▸ devices.nameNote (new; area settings) | none | This PC shares its name, “{name}”, with your server and your other devices. | new | D45 |
| settings ▸ backup.lastExported (new; area settings) | none | Last exported {date} | new | D22 |
| settings ▸ backup.neverExported (new; area settings) | none | Not exported yet | new | D22 |
| editor ▸ find.* (new; eight keys) | none | Find in entry; Replace; Previous match; Next match; Replace all; “{current} of {total}”; No matches; Close find | new | B31, D37 |
| common ▸ timeAgo.minutes (new; area common, plural) | the platform’s relative time (the Mac abbreviates: “2 min. ago”) | {“one”: “1 minute ago”, “other”: “{count} minutes ago”} | new | B34 |
| common ▸ timeAgo.hours (new; area common, plural) | the platform’s relative time | {“one”: “1 hour ago”, “other”: “{count} hours ago”} | new | B34 |
| messages ▸ sync.getUpdates (new; area messages) | none | Get updates | new | B38, D51 |
| settings ▸ privacy.appLock.disabledByPolicy (new; area settings) | none | App lock isn’t available because your organization turned off Windows Hello. | new | B32, D25 |
| settings ▸ privacy.appLock.openSignInOptions (new; area settings) | none | Open Sign-in options | new | B32, D25 |
| settings ▸ privacy.capture.title (new; area settings) | none | Hide from screenshots and screen sharing | new | B33, D28 |
| settings ▸ privacy.capture.description (new; area settings) | none | My Journal appears blank in screenshots, screen recordings and screen sharing, and Windows Recall doesn’t save it. | new | B33, D28 |
| settings ▸ backup.pickerSave (new; area settings) | none | Save here | new | B36 (the Markdown export's folder picker; the archive uses the system's Save button) |
