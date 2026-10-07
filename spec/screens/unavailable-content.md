---
id: unavailable-content
title: Unavailable and read-only content
features: [library-open-failure, read-only-newer-content, unavailable-journals, privacy-cover]
sources:
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/AppLockOperations.swift
  - apps/apple/JournalApp/Model/JournalNavigation.swift
  - apps/apple/JournalApp/Model/PrivacyCover.swift
  - apps/apple/JournalApp/JournalApp.swift
  - apps/apple/JournalApp/Views/UnlockView.swift
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Views/EntryEditingNote.swift
  - apps/apple/JournalApp/Views/EntryRecoveryNotice.swift
  - apps/apple/JournalApp/Views/DeletedJournalView.swift
  - apps/apple/JournalApp/Views/JournalSidebarView.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Store.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/JournalLifecycle.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Models.swift
  - docs/design/missing-device-key-unlock.md
  - docs/design/journal-lifecycle-ui.md
  - docs/design/pre-release-fixes-2026-09-27.md
---

# Unavailable and read-only content

## Purpose

What the app shows when it can't open the library, when content comes from a newer version of My Journal, when an entry's journal isn't available, and when the app covers its content in the app switcher. Content is never changed or discarded because this version can't handle it: it is kept as it is, shown read-only where possible, and the person is told what to do.

## Entry points

- Launching My Journal, and unlocking it.
- Syncing or importing content saved by a newer version.
- Opening the **Unavailable Journals** collection in the sidebar, or an entry in it.
- The app leaving the foreground while App Lock is on.

## Content

### When the library can't be opened

At launch the app reads its configuration, the key from this device's keychain, and the library. While any of these fails, the journal window shows the lock screen ("My Journal Is Locked") with the failure as a red note:

| Situation | Note | What the person can do |
| --- | --- | --- |
| The key that opens the journals isn't in this device's keychain | `messages.library.deviceKeyUnavailable` | Enter the master password or recovery key (the lock screen shows the credential field) |
| The library was opened by a newer version of My Journal | `messages.error.newerVersion` | Update My Journal |
| The library's database is damaged or can't be read | the error's own text (see [open-questions.md](../open-questions.md), A4) | Quit and reopen |
| Unlocking finds no library open and nothing else explains it | `messages.library.cannotOpen` | Quit and reopen |
| Unlocking with the credential fails | `messages.error.invalidRecoveryKey` | Try again |

Nothing is written to the library in any of these states.

### Content from a newer version

| What | How it shows | Copy |
| --- | --- | --- |
| An entry or template | Opens read-only: the editor can't be edited and its actions are limited; a note under the title | `messages.error.unsupportedFormat` ("Update My Journal to edit this entry.") |
| An entry whose Markdown can only be shown as source | Opens in source; View Preview is dimmed with a help tag | `messages.unavailable.markdownSource`, `common.previewUnavailable` |
| A journal | Left out of the Journals list; its entries are listed in Unavailable Journals | `common.updateToRestoreEntry` on each entry |
| A journal in Recently Deleted | Shown without Restore; Export Archive… is offered | `messages.unavailable.restoreJournalNeedsUpdate` |
| Pins and journal order | Kept as they are; changes are refused | `messages.library.needsUpdate` in Settings ▸ Sync; pinning shows `messages.generic.pinFailed` |
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

| Action | What it does |
| --- | --- |
| Unlock with the credential | Reads the key from the master password or recovery key, saves it to the keychain, and opens the library |
| Try Syncing Again | Runs a sync now, also resending refused items |
| Restore and Move… | Opens Move Entry to put the entry in an available journal |
| Review Changes | Opens the journal's review |
| Export Archive… | Exports everything, including content this version can't read, losslessly |

## States

- **Read-only:** editing, formatting, Insert Image and entry actions that change the entry are unavailable; reading, selecting and copying text still work.
- **Locked:** see the lock screen; the Unavailable Journals row and its entries are hidden with everything else.
- **Offline:** `common.journalNotArrived` stays until a sync brings the journal.

## Rules

- Content from a newer version is kept exactly as stored, including fields this version doesn't know, and is synced and archived unchanged. This version never saves over it.
- A library opened by a newer version is not opened at all, because the newer version may have changed what its tables mean.
- Unavailable entries are never deleted or moved by the app on its own.
- The cover is applied before the system takes its snapshot.

## Accessibility

- Notices are plain text read in order before the title; their buttons are standard and reachable with Full Keyboard Access.
- The lock screen announces its note when it changes.
- The read-only title is read as "Title" with its text as the value.
- The privacy cover's label is the only element while locked; a blank cover has none.

## Platform notes (Apple)

- **iPhone and iPad:** the privacy cover is a window above everything else in each scene, shown when a scene is about to become inactive or enters the background, and removed when it is active again.
- **Mac:** the same cover is drawn over the journal window's content whenever the window's scene isn't active and App Lock is on. The Mac also locks after inactivity, on sleep and on switching users (App Lock screens).
- Notices sit above the title on both; on iPhone and iPad they are part of the entry's scrolling header.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
