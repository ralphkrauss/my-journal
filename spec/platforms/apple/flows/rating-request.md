---
id: rating-request
title: Asking for a rating (Apple)
spec: flows/rating-request.md
features: [rating-request]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/JournalApp/Model/ReviewRequest.swift
  - apps/apple/JournalApp/Model/ReviewRequestTiming.swift
  - apps/apple/JournalApp/Views/ReviewRequestPresenter.swift
  - apps/apple/JournalApp/JournalApp.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/JournalNavigation.swift
  - apps/apple/JournalApp/Model/AppLockOperations.swift
  - apps/apple/JournalApp/Model/SyncHealthOperations.swift
  - apps/apple/JournalApp/Model/EraseOperations.swift
  - apps/apple/JournalTests/ReviewRequestTests.swift
  - docs/design/about-and-ratings-2026-10-05.md
---

# Asking for a rating (Apple)

How the spec's [Asking for a rating](../../../flows/rating-request.md) is built. The app draws nothing of its own: it calls StoreKit's `requestReview` and the system decides whether to show its prompt. The permanent Rate My Journal item is a separate command in About and the Help menu ([settings-about.md](../screens/settings-about.md)).

## Controls

- The system's request: `@Environment(\.requestReview)` (`RequestReviewAction`, StoreKit). `ReviewRequestPresenter` is a `ViewModifier` applied to the root view of the `WindowGroup` in `JournalApp.swift`; on appear it stores `{ requestReview() }` as `ReviewRequests.present`, so the prompt is requested from the window that is in front, on all three devices.
- The decision is made by `ReviewRequests` (`ReviewRequestTiming.swift`), one per `AppModel` (`model.reviewRequests`), together with `ReviewRequestRules.allow` and `ReviewUsage` (`ReviewRequest.swift`).
- Storage: `ReviewUsageStore.preferences()`, one JSON value in the app's `UserDefaults` under `ReviewRequestUsage`: `firstUse`, `writingDays`, `lastWritingDay` (a local calendar day key such as "2026-10-5", so a day counts once), `lastRequestVersion`, `lastRequest`. No journal content. `noteLaunch()` creates it on the first launch (`JournalApp.swift`, after `model.load()`). Erase Journals and Settings removes the key (`EraseOperations.swift`) and calls `reset()`.
- Rules (`ReviewRequestRules.allow`): a usage record exists; no problem this session; at least 7 days since `firstUse`; `writingDays` at least 4; `lastRequestVersion` differs from `CFBundleShortVersionString`; at least 120 days since `lastRequest`. The check that the build came from the App Store is separate and asynchronous: `AppTransaction.shared` must be `.verified` with `environment == .production`, so TestFlight and development builds never ask.
- Counting writing days: `noteEdit(entry:)` runs in `AppModel.updateDraft`, which only the editor's own edits reach (title and body), and remembers the edited entry. `noteSaved(entry:)` runs when `AppModel.flush` has stored the draft and records today if the saved entry is the edited one.
- The moment: `AppModel.applySelection` (all selection changes: choosing another entry, going back to the list on iPhone, which first saves and then deselects) calls `selectionChanged(leaving:)` with the entry that was left, only when it is a live entry in a live journal (not deleted, moved or recovered). If the person edited that entry, a `Task` waits 2 seconds, then `askIfStillPaused` checks that nothing called `interrupt()` meanwhile (`activity` counter), that `AppModel.reviewMomentIsClear` holds, that the rules allow it and the build is from the store, then checks the moment again, calls `present()` and records the version and the date, whether or not the system shows anything.
- Interruptions call `interrupt()`, which bumps the counter and cancels the task: another edit, a new entry (`newEntry`), a lock (`noteLocked`, which also forgets the edited entry), the app resigning active (`applicationResignedActive`), another selection change. Sheets and panels are not events: they are tested at the end of the wait by `reviewMomentIsClear`.
- Problems: `noteProblem()` sets `problemThisSession` until the next launch (or `reset()` after an erase) and interrupts. It is called when `model.error` is set, `saveFailure` becomes true, `conflicts` is not empty, `syncLongWait` becomes true (changes have waited more than a day while sync fails), and `recordSyncHealth` gets a state of any kind except `temporary` (offline, unreachable, unavailable and `localDataUnavailable` are `temporary`).
- Clear moment (`reviewMomentIsClear`): unlocked, app active, no device authentication request in front, library open and ready; not replacing the library, erasing, connecting, creating an entry, deleting all, or opening journals; no failed save, error or conflict; none of these presented: Settings, Journals, the template chooser, the archive and Markdown export sheets, an archive import request or a New Journal request; the selected entry is not a new empty entry (`draft.title.isEmpty` and an empty body). Then the window test, which differs by platform (below).
- Tests: `ReviewRequests.forApp(hostsTests:)` returns a store of nil in unit-test hosts and UI-test runs, so tests never ask; a debug build with `JOURNAL_UI_TEST_REVIEW=eligible` starts with an in-memory record that meets the rules. `ReviewRequestTests` cover the rules, writing days, the single request and the problem cases.

## Layout

Not applicable: there is no app UI. The system draws the prompt over the window that requested it. The screenshot shows the screen the person is on at the moment: the entry list after leaving an entry.

## Commands and shortcuts

None: the request is automatic. The permanent Rate command (`about-rate` in Settings ▸ About, `help-rate` in the Mac and iPad Help menu) is described with those pages and does not depend on these rules.

## Copy differences

None. The app has no copy for this flow; the prompt's text comes from the system.

## Accessibility

The prompt is the system's, so its accessibility is the system's. The app adds no announcement, focus change or label, and asking never moves VoiceOver focus. It never asks while a text input has focus, a sheet or alert is shown, or authentication is in front, so it does not interrupt VoiceOver reading of the editor.

## Differences between iPhone, iPad and Mac

The only difference is how "nothing is over the window and no text input is focused" is tested (`ReviewMoment.windowIsClear`), because the two toolkits expose it differently:

- Mac: the app is active; no modal window (`NSApp.modalWindow`); the key window is the journal window (`journalWindow`); the run loop is not tracking a menu (`eventTracking`); the window has no attached sheet and no child windows (a popover or the Formatting popover is a child window); the first responder is not an `NSText` (the entry, the title field's editor or the search field).
- iPhone and iPad: `applicationState == .active`; the key window of a foreground-active scene has no presented view controller (a sheet, popover, full-screen cover or alert); the first responder, found with a nil-targeted action (`FirstResponder`), is neither a `UITextView` nor a `UITextField`.

Everything else (rules, storage, timing, problems) is shared code.

## Screenshots

None. The rating prompt is the system's own UI and a simulator shows no rating prompt, so the capture script cannot produce it; the screen behind it is the entry list ([entry-list](../screens/entry-list.md)). The page is checked against the source only, so it stays draft.

## Source files

View:

- `apps/apple/JournalApp/Views/ReviewRequestPresenter.swift`: gives the model the window's `requestReview`.
- `apps/apple/JournalApp/JournalApp.swift`: applies the modifier and calls `noteLaunch`.

Model:

- `apps/apple/JournalApp/Model/ReviewRequestTiming.swift`: `ReviewRequests` (the moment, interruptions, the store check), `reviewMomentIsClear` and `ReviewMoment`.
- `apps/apple/JournalApp/Model/ReviewRequest.swift`: `ReviewUsage`, the rules and the preferences store.
- `apps/apple/JournalApp/Model/AppModel.swift`: `noteEdit`, `noteSaved` and `noteProblem` calls (`updateDraft`, `flush`, the `error`, `saveFailure`, `conflicts` and `syncLongWait` observers).
- `apps/apple/JournalApp/Model/JournalNavigation.swift`: `applySelection` starts the moment.
- `apps/apple/JournalApp/Model/SyncHealthOperations.swift`, `AppLockOperations.swift`, `EraseOperations.swift`: sync problems, resigning active, and the erase.

Core: none; nothing is shared with JournalCore.

Design record: `docs/design/about-and-ratings-2026-10-05.md` (section 3). Tests: `apps/apple/JournalTests/ReviewRequestTests.swift`.

## Open questions

See [open-questions.md](../../../open-questions.md), C24: sync health `localDataUnavailable` also counts as quiet (the spec lists offline, unreachable and unavailable), and the spec's "no text field has focus" is checked at the end of the two seconds, together with sheets, not as an interruption.
