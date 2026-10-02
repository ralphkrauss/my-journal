# Live Mac acceptance — 2026-09-21

## Environment and isolation

CUA interaction is now available: direct keyboard input and native menu actions succeed. Earlier desktop-lock blocker is no longer current. A copy of the latest Debug Mac build is in artifacts/mac-input-acceptance/Journal Acceptance.app, with only bundle identifier/name changed to org.privatejournal.inputacceptance / Journal Acceptance and a new ad-hoc signature. It runs with JOURNAL_DATA_DIR pointing to the adjacent disposable vault. The user's original Journal instance and entry are not edited. No server, external journal or personal account is connected.

## Observed native workflow

- Read System Settings → Keyboard → Text Input: Correct spelling automatically off, Capitalise words automatically off, smart quotes/dashes off. No keyboard preferences changed.
- Start a Journal and complete the disposable recovery confirmation. Three-column Personal window appears with no persistent editor date control.
- New Entry; type “Native editing check” into Title, Tab into Entry text; type `teh "plain quotes" -- lowercase.` followed by a newline and `Today I finished the writing check.`. Native accessibility text retains exactly those strings. This establishes the off-settings case, not behavior when settings are on, every correction mode or physical IME.
- Select the second sentence, open the visual Formatting popover. Actual screenshot shows B/I/U, typographic Heading/Subheading/Body, list controls and Link. Apply Bold, Escape, Command-Z, Command-Shift-Z. AX rich text first gains bold, Undo removes it, Redo restores it.
- Right-click the entry: Change Date, Move Entry, Archive Entry, Save as Template, Version History, Export Entry and Delete Entry. Change Date opens a native sheet; Cancel returns with current date, title/body and bold retained.
- Native body context menu exposes Spelling and Grammar, Substitutions and standard text actions.
- Quit via Command-Q (process exit0), relaunch the isolated app. Title, text, date/list row and bold sentence remain visible.
- Read System Settings Appearance: Auto originally selected. Temporarily select Dark; actual full-window screenshot shows adaptive dark surfaces and readable title/body with retained bold. Independent live review completed with no visual blocker in the observed window; see mac-live-acceptance-review.md. Auto was restored and observed selected in System Settings afterward.

Screenshots and accessibility trees were recorded by the computer-use automation (CUA) run; they are not in the repository. These are real macOS interactions, not XCTest assertions. They do not establish full VoiceOver, enabled automatic-correction behavior, all window widths, older OS compatibility, signing, physical Intel, or complete integrated acceptance. The app copy predates any subsequent source changes unless explicitly updated.

## File-dialog limit and cleanup

Insert Image opened the native Open panel. The synthetic PNG was generated locally at artifacts/mac-input-acceptance/synthetic-image.png (SHA-256 16e601aaf10f903c9f1f1f1756ee3ad85bfc99aaebed13a0ecaecb89e80aa11a). Go to Folder displayed the complete correct path, but Return reverted the field to `/`; the path result's open action and double-click did not dismiss it. Clipboard paste timed out. A later Escape changed the path to a recent `/private/tmp/` value rather than dismissing the chooser. These CUA-observed inconsistencies do not establish an app import defect. No image was accepted, and export was not attempted. Do not count either route as passed or work around the UI to claim native acceptance.

The isolated process PID63061 was terminated after abandoning the dialog; terminal session87254 reports exit143. This is test-process cleanup, not successful app quit/relaunch evidence. The earlier normal Command-Q exit0 and relaunch above remain independently observed. Original Journal instance was not terminated. Fixture vault and app copy remain for diagnosis. No production files were changed. Codesigning recheck still reports0 valid identities.

## Picker follow-up

A new turn resumed the same isolated vault and used the ordinary folder list instead of Go to Folder. The home-location AX action selected Pictures after scrolling; subsequent current visible home-row/coordinate actions did not navigate. No personal image was opened or imported. The native Cancel button did dismiss the picker, returning to the unchanged displayed entry with no attachment. Command-Q then ended process/session14475 normally with exit0. This improves cancellation evidence, not image-import acceptance.


## Keyboard and VoiceOver follow-up

The same isolated current-build vault was launched for a bounded follow-up. System Settings → Accessibility → VoiceOver initially showed off. It was temporarily enabled and verified on. Control-Option-Right from the app window and title did not expose a distinguishable VoiceOver cursor, caption or spoken-output result through CUA. This is **not a VoiceOver pass or an established app defect**. The original off setting was restored and verified before continuing. No VoiceOver utility, keyboard or other accessibility preferences were changed.

Title → Tab focused Entry text. Command-K opened Add Link with URL focused; Escape dismissed it and returned focus to Entry text without changing displayed content. Opening Entry Actions then Down/Return opened Change Date with the date control focused; Escape dismissed it and returned focus to Entry text, preserving the displayed date/title/body/bold. Command-Q ended the isolated process/session13413 normally with exit0.

Shift-Tab and Command-F from the body did not produce a different reported focus in this run. The inspected Edit menu has no Find command. These observations do not establish complete keyboard traversal or search-shortcut support; the native rich editor's Tab behavior and platform search conventions should be reviewed before adding or changing shortcuts. CUA occasionally returned a stale menu tree while the next sheet was already opening, so instantaneous unchanged trees alone are insufficient failure evidence. No production changes or additional automated tests were made.


## Live agent onboarding follow-up

Started the same isolated app/vault (session22176). Command-comma opened the Settings scene at Sync. Its generated toolbar exposed Sync/Devices/Privacy/Journals as containers, not selectable AX tabs; bounded clicks and keyboard attempts did not switch pages. An independent reviewer reproduced the CUA result, observed crowded labels, and correctly left physical input failure unproven. See mac-settings-navigation-review.md. Closing Settings succeeded. Main-sidebar Manage Journals opened the same SettingsView as a sheet with actual selectable AX tabs; Privacy immediately worked there. This narrows the navigation limitation to the Settings scene representation, not the content or selection model.

Through the sheet: Add Access → name “Local acceptance” → select only Personal → Continue → inspect scope/provider/revocation explanation → Allow Read Access. The detail showed Read Only, Personal, a collapsed Connection Instructions disclosure and visible Copy/Revoke/Done footer. Expanding the disclosure exposed a real executable and private connection-file path, the three read-only tools, untrusted-content instructions, open/unlocked requirement and provider warning. The footer remained visible below the scrolling instructions at the observed size. No Copy action was used; clipboard behavior remains unverified.

Used the executable/path named by the UI with a local synthetic JSON-RPC harness. An initial harness incorrectly started a fresh connector per call and correctly received “Initialize this MCP connection before calling tools.” A corrected same-process initialize/initialized/tools-list/list-journals/search batch returned four successful protocol replies and the exact three expected tools, but the harness then incorrectly expected journal “title” instead of the documented source's “name”; no full content assertion passed. These harness errors are not app defects. Before the corrected full-content/read run could complete, initialization was denied with “Access unavailable.” CUA then explicitly reported the Mac locked and unable to unlock automatically. This establishes lock denial for this fixture; it does not establish full search/read content or successful UI revocation. No external agent was configured and no personal journals were connected.

The synthetic grant remains only in artifacts/mac-input-acceptance/vault; do not treat it as revoked. Complete/revoke it through the UI after unlock. Test PID79863 was terminated with SIGTERM, session22176 exit143, because the desktop was locked. This is cleanup, not normal quit acceptance. No PIN/OS preference/security setting was altered in this follow-up.
