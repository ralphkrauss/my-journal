---
id: unavailable-content
title: Unavailable and read-only content
features: [library-open-failure, erase-unopened-library, launch-states, read-only-newer-content, unavailable-journals, privacy-cover]
sources:
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/AppLockOperations.swift
  - apps/apple/JournalApp/Model/JournalNavigation.swift
  - apps/apple/JournalApp/Model/PrivacyCover.swift
  - apps/apple/JournalApp/JournalApp.swift
  - apps/apple/JournalApp/Model/LibraryProblem.swift
  - apps/apple/JournalApp/Model/LibraryOpening.swift
  - apps/apple/JournalApp/Model/EraseOperations.swift
  - apps/apple/JournalApp/Views/LibraryProblemView.swift
  - apps/apple/JournalApp/Views/UnopenedEraseButton.swift
  - apps/apple/JournalApp/Views/UnlockView.swift
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Views/EntryEditingNote.swift
  - apps/apple/JournalApp/Views/EntryRecoveryNotice.swift
  - apps/apple/JournalApp/Views/DeletedJournalView.swift
  - apps/apple/JournalApp/Views/JournalSidebarView.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Store.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/JournalLifecycle.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Models.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/LocalDataFailure.swift
  - docs/design/build-18-fixes-2026-10-06.md
  - docs/design/missing-device-key-unlock.md
  - docs/design/journal-lifecycle-ui.md
  - docs/design/pre-release-fixes-2026-09-27.md
---

# Unavailable and read-only content

## Purpose

What the app shows when it can't open the library (and what it offers instead of a dead end), when content comes from a newer version of My Journal, when an entry's journal isn't available, and when the app covers its content in the app switcher. Content is never changed or discarded because this version can't handle it: it is kept as it is, shown read-only where possible, and the person is told what to do.

## Entry points

- Launching My Journal, and unlocking it. If the library can't be opened the person sees the library problem screen; nothing else of the app is reachable until it opens or is replaced.
- Syncing or importing content saved by a newer version.
- Opening the **Unavailable Journals** collection in the sidebar, or an entry in it.
- The app leaving the foreground while App Lock is on.

## Content

### When the library can't be opened

At launch the app reads its settings, the key from this device's secure store, and the library. If any step fails, or the first read of the journals after opening fails, **nothing of the library stays open** (no store, no key, no connection, no sync) and the window shows the **library problem screen**. It is not the lock screen: it needs no authentication, shows nothing of the journals or the server, and a person who can't unlock learns only that something is wrong. It is also shown when a configuration names a library whose database file is missing; nothing is created for it.

The window shows, in this order: `library.app.loading` with a progress indicator until loading has finished; the lock screen; the library problem screen; the first-launch screen when there is no library; the recovery key; the journals.

| Problem | When | Screen |
| --- | --- | --- |
| **Can't open** | The library the settings name doesn't open (the database is missing or damaged, busy or unavailable; the key or saved connection can't be read or decoded; a crypto error), or the first read of the journals fails. Only a newer version is told apart from the rest, because the person's choices are the same and the app can't reliably tell a permanent fault from a temporary one | the library problem screen |
| **Settings unreadable** | The settings file exists but can't be read or decoded. (A missing file means first launch.) | the library problem screen |
| **Newer version** | The journals, or the format their settings name, were saved by a newer version of My Journal | the library problem screen (update form) |
| **Missing device key** | The library needs a password and its key isn't in this device's secure store (for example after restoring the device from a backup) | the lock screen with the credential form, below |

The library problem screen is centred and scrolls at large text sizes, like the lock screen and the first-launch screen:

| | Can't open, settings unreadable | Newer version |
| --- | --- | --- |
| Symbol (decorative) | a warning triangle | a down-arrow into an app |
| Heading | `library.problem.title` | `library.problem.updateTitle` |
| Paragraphs | Can't open: `library.problem.cantOpen.message`, then `library.problem.cantOpen.advice`. Settings unreadable: `library.problem.settingsUnread.message`, then `library.problem.settingsUnread.advice`. {device} is the device's name | `library.problem.newerVersion.message` |
| After one failed Try Again | `library.problem.mayBeFine` in secondary text | — |
| Buttons | Try Again (prominent, default); Import Archive… (can't open only); Erase Journals and Settings… (after a failed Try Again); Learn More | Learn More only (the default) |

While Try Again runs, the buttons give way to `library.app.loading` with a progress indicator; the heading and paragraphs stay. When it ends in a problem again, the line `library.problem.stillClosed` appears directly under Try Again (plain text, announced once) until the next attempt starts, and focus returns to Try Again.

**Missing device key.** The lock screen ([lock-screen.md](lock-screen.md)) with the credential form and the error `messages.library.deviceKeyUnavailable`. Below the form is a group captioned `library.problem.missingKey.caption` ("Don’t have your {credential}?") with Import Archive… and Erase Journals and Settings…, for a person who no longer has the credential. Entering the credential unlocks the journals and saves the device key again. A wrong credential shows `messages.error.invalidRecoveryKey`.

**Settings in a problem state.** Settings shows only `settings.libraryProblem` in place of its panes, whichever way it is opened.

Nothing is written to the library in any of these states.

### Content from a newer version

| What | How it shows | Copy |
| --- | --- | --- |
| An entry or template | Opens read-only: the editor can't be edited and its actions are limited; a note under the title | `messages.error.unsupportedFormat` ("Update My Journal to edit this entry.") |
| An entry whose Markdown can only be shown as source | Opens in source; View Preview is dimmed with a help tag | `messages.unavailable.markdownSource`, `common.previewUnavailable` |
| A journal | Left out of the Journals list; its entries are listed in Unavailable Journals | `common.updateToRestoreEntry` on each entry |
| A journal in Recently Deleted | Shown without Restore; Export Archive… is offered | `messages.unavailable.restoreJournalNeedsUpdate` |
| Pins and journal order | Kept as they are; changes are refused | `messages.library.needsUpdate` in Settings ▸ Sync; pinning, unpinning and moving a journal show `messages.library.needsUpdate` in the error alert |
| A version in a conflict | The review can't be completed | `messages.conflict.updateToReview` (see [conflict-review.md](conflict-review.md)) |
| The server, or content arriving by sync | Sync stops | `messages.sync.appUpdateNeeded` |
| An archive to import into a device with journals | Refused | `messages.import.archiveNeedsUpdate` |
| Merging this device's journals while connecting | Refused | `messages.import.mergeNeedsUpdate` |
| Operations on such content | Refused with an update message | `messages.lifecycle.unsupportedJournal`, `messages.merge.newerVersion`, `messages.generic.journalDeleteNeedsUpdate`, `messages.generic.deleteNeedsUpdate` |

### Unavailable Journals

A sidebar row `common.unavailableJournals` (symbol: a folder with an exclamation mark), after Templates and Recently Deleted. It appears only while at least one entry is unavailable, or while it is open. It lists entries whose journal:

- is **missing** on this device (not synced yet, or removed by an earlier version);
- was saved by a **newer version**;
- has **changes to review**.

The list title is `common.unavailableJournals`; its search field says `common.searchUnavailableEntries`; when empty it shows `messages.unavailable.empty`. Pinned entries aren't grouped at the top here.

An unavailable entry opens read-only with a notice above the title, by reason:

| Reason | Notice | Action |
| --- | --- | --- |
| Missing, while syncing with a server | `common.journalNotArrived` | `common.trySyncingAgain` (a sync that also resends refused items) |
| Missing, without a server | `common.journalUnavailableEntrySaved` | Restore and Move… when the entry was deleted with its journal by an earlier version |
| Newer version | `common.updateToRestoreEntry` | none |
| Journal has changes to review | `common.journalNeedsReview` | `common.reviewChanges` (the journal's review) |

When the journal arrives or its changes are reviewed, the entry returns to its journal; if it is open, the list follows it there.

### Privacy cover

The lock screen and the cover are specified in [lock-screen.md](lock-screen.md); summarized here because the cover hides content.

While App Lock is on and the app isn't active, a plain cover in the system background colour hides every window, including sheets, popovers and alerts, so the app switcher's snapshot never shows journal content. It shows `common.myJournalIsLocked` with a lock symbol only while the journals are actually locked; when the app is merely inactive (Control Center, a system alert) the cover is blank. App Lock's own authentication panel doesn't trigger the cover, so the lock screen isn't hidden behind it.

## Actions

| Action | Command | What it does |
| --- | --- | --- |
| Try Again | `retry-opening` | Clears the problem and runs the whole opening again, re-reading the settings. Not offered for a newer version. A tap that ends in a problem again counts once; only a person's tap counts (see Rules). |
| Import Archive… | `import-archive` | Can't open, at once; also on the missing-key lock screen. Opens the archive flow ([flows/import-archive](../flows/import-archive.md)), which reads and checks the archive before it replaces the library that couldn't be opened. |
| Erase Journals and Settings… | `erase-unopened` | After one failed Try Again (can't open, settings unreadable), or at once on the missing-key lock screen. Authenticates, then the warning `settings.erase.alert.unopened` ([flows/erase](../flows/erase.md)). |
| Learn More | `open-library-guide` | Opens the troubleshooting guide on the web. It needs a connection; the screen's text stands on its own without one. |
| Unlock with the credential | `unlock-with-credential` | Reads the key from the master password or recovery key, saves it to the secure store, and opens the library (missing-key lock screen). |
| Try Syncing Again | `try-syncing-again` | Runs a sync now, also resending refused items. |
| Restore and Move… | `restore-and-move` | Opens Move Entry to put the entry in an available journal. |
| Review Changes | `review-changes` | Opens the journal's review. |
| Export Archive… | `export-archive` | Exports everything, including content this version can't read, losslessly. |

## States

- **Read-only:** editing, formatting, Insert Image and entry actions that change the entry are unavailable; reading, selecting and copying text still work.
- **Locked:** see the lock screen; the Unavailable Journals row and its entries are hidden with everything else. A library with a problem is never locked, because there is nothing to unlock: inactivity and the background don't put up a lock screen over the problem screen.
- **Retrying:** the buttons are replaced by the progress indicator; Import Archive… and the other commands that would replace the library refuse (`messages.library.notOpen`).
- **Protected data not available** (phone and tablet, a launch before the first unlock, or the device locked): opening fails for a reason that ends by itself. The library problem screen offers neither Import Archive… nor Erase, whatever the count, and the app tries again by itself when the data becomes available (that attempt never counts towards offering Erase). If that succeeds with App Lock on, the person lands on the lock screen, never on the journals. The computer has no such state; Try Again is its retry.
- **Offline:** `common.journalNotArrived` stays until a sync brings the journal.

## Rules

- Content from a newer version is kept exactly as stored, including fields this version doesn't know, and is synced and archived unchanged. This version never saves over it.
- A library opened by a newer version is not opened at all, because the newer version may have changed what its tables mean.
- The app never replaces a settings file it couldn't read, never switches to another library without recording the one it leaves, never tells the person more than it knows (“Nothing has been removed” is all it promises), never turns App Lock off on its own, and Erase Journals and Settings removes everything the app stored, whatever it could or couldn't read ([flows/erase](../flows/erase.md)).
- Connecting to a server, pairing and starting a journal replace the library, so they refuse while there is a problem or Try Again runs (`messages.library.notOpen`). Journals a newer version wrote, and settings that couldn't be read, are never imported over (Import Archive… is not offered for them).
- **Erase waits for one failed Try Again; Import doesn't.** Erase removes the journals, so it is held back until a retry has failed: a restart or a few seconds fixes most causes, and the launch's own failed open is the first failure, so one failed tap is two failures in a row. Some causes are permanent, so Try Again must not be the only choice. Import removes nothing until the archive has been read and checked and the person has confirmed a sheet that says what is lost (`library.problem.importNote`). The count lives in memory and starts again at each launch.
- Import Archive… asks for the device's own authentication when App Lock is on, and Erase when App Lock is on **or its setting can't be known** (settings unreadable), so a stranger can't use them; a device without a passcode goes on.
- Unavailable entries are never deleted or moved by the app on its own.
- The cover is applied before the system takes its snapshot.

## Accessibility

- Notices are plain text read in order before the title; their buttons are standard and reachable with Full Keyboard Access.
- The lock screen announces its note when it changes.
- Library problem screen: the screen's heading takes screen-reader focus when it appears and is announced once per problem; the symbol is hidden. `library.problem.stillClosed` is announced when it appears, and focus returns to Try Again. Learn More has the hint `library.problem.learnMore.hint`. The missing-key group is one container labelled with its caption. The screen scrolls at the largest text sizes and every label wraps.
- The read-only title is read as "Title" with its text as the value.
- The privacy cover's label is the only element while locked; a blank cover has none.

## Platform notes (Apple)

- **iPhone and iPad:** the privacy cover is a window above everything else in each scene, shown when a scene is about to become inactive or enters the background, and removed when it is active again.
- **Mac:** the same cover is drawn over the journal window's content whenever the window's scene isn't active and App Lock is on. The Mac also locks after inactivity, on sleep and on switching users (App Lock screens).
- Notices sit above the title on both; on iPhone and iPad they are part of the entry's scrolling header.
- The paragraphs name the device (iPhone, iPad or Mac) in `library.problem.cantOpen.advice` and `library.problem.settingsUnread.advice`, and the update paragraph says only "Update My Journal" (the operating system does the update; no store is named). Another platform names its own device and may add its own update link. An App Store button is planned for after the app is live and is not part of the screen yet.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
