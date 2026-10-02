# Native multiline title paste review

## Scope and evidence

Independent review of the existing title editor and the native Select All → Copy → new entry → Paste → Next → body → relaunch workflow. No production UI change was proposed or reviewed here. The source title is the synthetic string `Monday\nReview`; the newline is explicit, rather than a visual wrap caused by width.

Inspected `apps/apple/JournalUITests/WritingWorkflowUITests.swift`, including `testMultilineTitlePasteThenNextPreservesWritingAcrossRelaunch`, and all three screenshots listed in `artifacts/title-paste-normal/manifest.json`. The parent reports that the normal-size test passed in 34.166 seconds; the reviewer did not inspect its execution log or rerun the test. Initial navigation and direct-clipboard harness issues were corrected before that reported run.

## Normal-size actual UI

- `43EC8955-E94B-490F-B27B-80403F8288FB.png`: the complete bold title appears as “Monday” and “Review” on separate lines, with the caret after “Review”. The body placeholder and keyboard are visible, including the next arrow. The title and caret remain clear above the keyboard.
- `C7F29CFC-ED8D-4A2A-9A94-96F8C16035E3.png`: the complete title remains intact while the body reads “Orchid delivery completed.” with its caret at the end. The keyboard now shows the return arrow. The presentation keeps writing primary without extra status clutter.
- `C1CA0F4A-D683-4A38-84F8-A822FAAADE9B.png`: after relaunch, the complete two-line title and body remain visible. No keyboard or insertion caret is shown.

No material visual blocker was found in the normal-size captures. This bounded presentation review is approved.

## Behavioral evidence and limits

The inspected test uses native edit actions to copy and paste, asserts the exact multiline title, explicitly taps the keyboard's Next action, types and checks the body, and checks both strings after relaunch. Its final real-store assertions identify a distinct new entry with the exact title, verify the chosen journal, require the exact body text block list, and require three entries. These protect the title newline, body destination, journal placement, and persistence for this scenario.

The test does not assert full document equality or exact preservation of the source record. The native edit menus themselves are not captured in the normal screenshot set. This review does not establish other-app clipboard behavior, IME behavior, VoiceOver behavior, macOS behavior, or minimum-OS compatibility. Larger-text/dark evidence remains pending.

## Final larger-text dark actual UI

Inspected all three screenshots listed in `artifacts/title-paste-large/manifest.json`. The parent reports the largest-text dark run passed in 38.513 seconds after the test helper handled native edit-menu roles and paging. The reviewer did not inspect its execution log or rerun the test. The earlier run stopped before copying because Select All was in the native menu overflow; the parent reports no production changes.

- `4F90A19B-EB70-4572-880D-DBAD4EA7F925.png`: the complete large, bold two-line title and “Start writing…” placeholder are visible above the dark keyboard. The keyboard's next arrow is clear. No title insertion caret is visible in this capture, so its rendering cannot be assessed here.
- `FCD37836-81DA-4862-9EF9-EC20360F9A84.png`: the title remains fully visible. “Orchid delivery completed.” wraps naturally across two lines; the complete body and its insertion caret remain above the keyboard. The return arrow is visible.
- `29FD2CB0-8E9F-41BB-87ED-39FD939C638A.png`: the complete title and body remain readable after relaunch, with no keyboard or caret shown.

No material clipping, overlap, or keyboard obstruction was found in these captures. Normal-size and largest-text dark presentation are approved for this bounded multiline-title paste, Next, body-writing, and relaunch scenario. The successful larger-text screenshots do not show the native menus themselves. The behavioral and platform limits above still apply; this is not a general accessibility or clipboard-interoperability acceptance.
