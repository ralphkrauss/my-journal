# About links, the rating request, and Use This Mac on Intel Macs — 2026-10-05

Status: reviewed 2026-10-05 (approve with changes, section 6); revised as below and built for build 17. Owner-approved scope: App Store Guideline 5.1.1(i) needs a privacy policy link inside the app; the growth plan (pick 1) adds a permanent Rate link and a system rating request with strict timing; the owner chose to show Use This Mac… disabled on Intel Macs (launch checklist 0.2, 0.3).

URLs, the same as the App Store listing (docs/app-store/listing.md):

| Item | URL |
| --- | --- |
| Privacy Policy | `https://github.com/ralphkrauss/my-journal/blob/main/PRIVACY.md` |
| Support | `https://github.com/ralphkrauss/my-journal/blob/main/SUPPORT.md` |
| Source Code | `https://github.com/ralphkrauss/my-journal` |
| User guide (Mac Help only) | `https://github.com/ralphkrauss/my-journal/blob/main/docs/guide/README.md` |
| Rate My Journal (iPhone, iPad) | `https://apps.apple.com/app/id6816758959?action=write-review` |
| Rate My Journal (Mac) | `macappstore://apps.apple.com/app/id6816758959?action=write-review` (opens the App Store app directly instead of a browser page that hands over to it) |

## 1. iPhone and iPad: an About section in Settings

Placement: a new section between the panes (Writing … Agent Access) and the standalone Erase section, which stays last (erase-device-2026-10-04.md §1). As iOS Settings ▸ General puts About near the top and Transfer or Reset last, the reference links sit above the one destructive action.

```
Settings                                   Done
 ┌──────────────────────────────────────────┐
 │ ✎  Writing                             › │
 │ ⟳  Sync                                › │
 │ ▭  Devices                             › │
 │ ✋ Privacy                              › │
 │ ⌸  Backup                              › │
 │ ⚿  Agent Access                        › │
 └──────────────────────────────────────────┘
 ABOUT
 ┌──────────────────────────────────────────┐
 │ Privacy Policy                           │  accent colour (links)
 │ Support                                  │
 │ Source Code                              │
 │ Rate My Journal                          │
 └──────────────────────────────────────────┘
 Version 1.0 (17)

 ┌──────────────────────────────────────────┐
 │ Erase Journals and Settings…             │  red
 └──────────────────────────────────────────┘
 Removes your journals and settings from this device, …
```

- Header **About**. Rows are SwiftUI `Link`s in the list: accent-coloured text, no icons, no chevrons, no trailing arrow; they leave the app (Safari, or the App Store for Rate My Journal), as Apple's own link rows do (for example "About Apple Music & Privacy"). No ellipsis: nothing more is asked in the app.
- Order: Privacy Policy, Support, Source Code, Rate My Journal (the owner's order: the required link first, the request last).
- Footer: **Version 1.0 (17)** from `CFBundleShortVersionString` and `CFBundleVersion`, selectable so it can be copied; VoiceOver reads "Version 1.0, build 17". It answers "which version do I have?" for support (SUPPORT.md currently sends iPhone users to Settings app ▸ General ▸ iPhone Storage).
- Available whenever Settings is (Settings isn't shown while locked). The rows don't depend on a library, so they also show while the Erase section is busy.
- Offline: Safari and the App Store show their own messages; the app shows nothing.
- Accessibility: VoiceOver reads "Privacy Policy, link" and so on; the header is a heading; Dynamic Type wraps the text; Increase Contrast and Bold Text apply through the system list. Keyboard: Tab and the arrow keys reach each row on iPad with a keyboard; Space or Return opens it.

## 2. Mac: the Help menu

Today the Help menu has only the system's search field (`CommandGroup(replacing: .help) {}`). Proposed, as Apple apps structure it (app help first, then related pages, then feedback):

```
Help
  [Search                      ]
  My Journal Help            ⌘?
  ───────────────────────────────
  My Journal Support
  Privacy Policy
  Source Code on GitHub
  ───────────────────────────────
  Rate My Journal
```

- **My Journal Help** (⌘?, the standard Help shortcut) opens the user guide; there's no help book. The system item would only say help isn't available.
- **My Journal Support**, **Privacy Policy**, **Source Code on GitHub**, **Rate My Journal**: the URLs above, opened with `openURL` (the default browser; the App Store app for Rate). Named for the app, because a Help menu item is read without the context of a section header (review finding 12). No ellipsis (nothing more is asked in the app), no other shortcuts.
- Always enabled, also while locked or without a window: they show nothing from the journals. The version stays in My Journal ▸ About My Journal, as on every Mac app.
- **iPad with a menu bar (iPadOS 26):** the same Help menu, so the menu bar isn't missing what Settings has (review finding 10). Rate My Journal uses the `https` App Store address there.
- VoiceOver reads menu items as usual; the menu's search field finds them.

## 3. The rating request

The system's own prompt, `@Environment(\.requestReview)` (StoreKit's `RequestReviewAction`, iOS 16 and macOS 13). The app has no copy of its own: no button, no custom pre-prompt. It does nothing in TestFlight (expected) and the system shows it at most three times a year whatever the app asks.

### When (all must be true)

| Rule | Value |
| --- | --- |
| First use on this device | at least **7 days** ago |
| Days with writing | the person's own edits to an entry's title or text, typed (or dictated, pasted) on this device and saved, on at least **4 different calendar days** (local time). Synced-in changes, imports, pinning, moving, Change Date and entries made from a template but never edited don't count. |
| This session | the person edited the entry they're leaving since the app launched or was last unlocked |
| Nothing needed attention this session | no save failure, no error message (import, export, recovery and the other alerts that report a failure), no change to review (one appearing this session, or one unresolved now), and no sync problem the person must act on (signing in, a replaced or reset server, removed access, an update, a certificate or address problem, or Sync Status asking for attention after a long wait). Being offline or a server that can't be reached, which the app treats quietly, doesn't count (review finding 1). |
| Not asked lately | never during this app version (`CFBundleShortVersionString`), and the last request at least **120 days** ago |
| App Store build | the app was installed from the App Store (`AppTransaction`'s environment is production). TestFlight and development builds never ask or record a request, so testers' devices don't carry "already asked in 1.0" into the release (review finding 4). |
| Clear screen | unlocked; this app frontmost and its journal window the key window (in iPad Split View or Stage Manager, the scene in front); no sheet, alert, popover or menu open; no text field or editor with keyboard focus; nothing being saved, replaced, erased or connected |

### The moment

A natural pause: right after leaving an entry the person edited.

- **iPhone:** going back from that entry to the list.
- **iPad and Mac:** selecting another entry in the list (or going back on a compact iPad).
- Then **wait 2 seconds** (as Apple's sample does). The request is dropped (not postponed) if, meanwhile, the selection changes again (for example browsing with the arrow keys or ⌥⌘↓), the person edits anything, starts a new entry, a sheet, alert, popover or menu appears, the app locks, or it leaves the foreground. All rules are checked again at the end of the 2 seconds, including the clear screen: if the editor or the search field has keyboard focus, or the entry now open is new and still empty, nothing is shown.
- Leaving an entry any other way doesn't ask: deleting or moving it, switching journals or collections, closing the window, locking, or a sync removing it.

Never on launch, never right after unlocking (the session rule resets on lock), never during onboarding, connecting, pairing, export or import, Erase, Delete All or a conflict review (each of those is a sheet, an alert, a replacing or erasing state, or reports an error), never while writing, never from a button.

### Storage

On the device only, in the app's own UserDefaults (already declared `CA92.1` in the privacy manifest): first-use date, number of distinct writing days, the last writing day (so a day isn't counted twice), and the version and date of the last request. No journal content, nothing synced, nothing sent by the app. Only when every other rule passes does it ask StoreKit for the installation's environment (`AppTransaction.shared`), which the system answers from the App Store. Erase Journals and Settings removes it with the other preferences, including the record of the last request; a second request in the same version after erasing is still limited by the 7-day and 4-day rules and by the system's own limit (review finding 6). Unit-test hosts and UI-test runs (`JOURNAL_UI_TEST_ID`) never record or ask, so test simulators can't accumulate eligibility; a debug-only launch value makes a UI-test run eligible so the moment can be checked.

### Accessibility

The system prompt is accessible. Because it only comes after leaving an edited entry, with 2 seconds without editing, it doesn't appear while VoiceOver focus is in the editor or while dictating.

## 4. Use This Mac on Intel Macs

The bundled server is built for Apple silicon only. Settings ▸ Sync on a Mac with an Intel processor, before a server is chosen:

```
Server
 ┌──────────────────────────────────────────┐
 │ Your journals are saved on this device.  │
 │ [Use This Mac…]   (dimmed)               │
 │ [Connect to a Server…]                   │
 └──────────────────────────────────────────┘
 Running a server requires a Mac with Apple silicon.
```

- **Use This Mac…** (or **Try Again…** after an unfinished setup) is shown but disabled; the footer says why (review finding 15 shortened the owner's example sentence, which said "Mac" twice). Connect to a Server… works as before. The footer shows whenever the hardware is the reason, also when the button is dimmed for another reason too (finding 17).
- The macOS 13 branch ("Running a server on this Mac requires macOS 14 or later.") is removed: the Mac app's minimum is macOS 14, so it was never shown (finding 14).
- **A server set up on Apple silicon and brought to an Intel Mac** (Migration Assistant or a backup; finding 16): Settings ▸ Sync still shows This Mac, Start Server is disabled with the same footer, and the server isn't started automatically at launch, so no launch error appears. The journals stay on this Mac; writing, Export Archive… and Erase are unaffected.
- Detection checks the hardware, not the app's process: `sysctlbyname("hw.optional.arm64")` is 1 on Apple silicon, also when the app runs under Rosetta, and missing on Intel. Unknown means unavailable. Setting up and starting refuse as well (defence in depth), with the same sentence.
- VoiceOver reads the button as dimmed, then the footer.
- Docs: the guide's Use This Mac section adds the same sentence.

## 5. Tests

- Rating rules: one table-driven test of the eligibility decision (each rule failing alone, the boundary values 7 days / 4 days / 120 days, same version, a new version), and one test that writing on the same day twice counts one day and that days are local calendar days, with an injected clock and calendar.
- The request is cancelled when editing happens during the delay, and fires once after the delay otherwise (injected clock, no real waiting).
- Architecture: the availability decision for Apple silicon, Apple silicon under Rosetta, Intel and an unreadable value.
- UI: Settings shows the About section with the Privacy Policy link and the version footer. It protects the in-app privacy policy link Guideline 5.1.1(i) requires, which no other check would notice going missing (finding 11).

## 6. Review

An independent design-review agent reviewed the requirements and the first version of this proposal on 2026-10-05 (verdict: approve with changes, no full re-review needed). Its findings and what was done:

| # | Finding | Outcome |
| --- | --- | --- |
| 1 | Material: treating every failed sync as an error excludes people whose server is often out of reach (a sleeping Mac at home). | Only failures the person must act on count; offline and unreachable don't. Unresolved changes to review count even from an earlier session. |
| 2 | Material: on iPad and Mac, selecting another entry isn't always a pause; arrow-key browsing would prompt mid-browse. | Dropped on a further selection change, focus in a text field or the editor, a new empty entry, or an open menu; other ways of leaving an entry don't ask. |
| 3 | Material: "days with saved changes" undefined. | Defined as the person's own edits on this device. |
| 4 | Minor: TestFlight and Debug builds would record a request. | Only App Store installations ask and record. |
| 5 | Minor: iPad multitasking and Mac windows. | The app must be active with its journal window (or front scene) key. |
| 6 | Minor: Erase resets the record. | Accepted and noted. |
| 7 | App Review risk low; strictness about right. | No change. |
| 8 | About section correct as specified. | No change. |
| 9 | Version footer: VoiceOver label, selectable, update SUPPORT.md. | Done. |
| 10 | iPadOS 26 menu bar lacks the Help items. | The same Help menu on iPad. |
| 11 | The UI test borders on composition testing. | Kept, limited to the privacy policy link and version, as the 5.1.1 guard. |
| 12 | Bare Help item names are ambiguous. | My Journal Support, Source Code on GitHub. |
| 13 | ⌘? and web help are fine; a guide row on iOS is optional. | Checked in the real menu; no iOS guide row (outside the approved scope; Support links to the guide). |
| 14 | Material: Intel and macOS 13 presentations differ. | The macOS 13 branch was dead code and is removed. |
| 15 | "on this Mac requires a Mac" repeats "Mac". | "Running a server requires a Mac with Apple silicon." |
| 16 | Material: a configured server restored onto an Intel Mac. | Start Server disabled with the footer; no automatic start. |
| 17 | The footer should explain the hardware whenever it applies. | Done. |
| 18 | Before release, Rate My Journal opens an App Store page that doesn't exist yet. | Noted for the TestFlight notes. |
