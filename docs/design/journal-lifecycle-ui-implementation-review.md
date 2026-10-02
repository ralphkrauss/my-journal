# Whole-journal recovery UI implementation review

Date: 2026-09-20. Independent source review against the approved `journal-lifecycle-ui.md` and its proposal review. Reviewed JournalLifecycleView, DeletedJournalView, JournalSettingsView, RootView, native menu commands, JournalNavigation/Operations, AppModel refresh/save/commit handling, and core deletion/restore checks. No new renders, interactive runs, VoiceOver sessions, or independently executed tests form part of this review.

## Outcome

Request the bounded corrections below before implementation approval. The single captured confirmation sheet, atomic core title/member checks, explicit already-applied errors, inherited restoration semantics, active-sheet conflict/export routes, and owned committed-operation reconciliation are appropriate. The journal detail branch avoids creating an entry editor, and the root toolbar correctly disables entry actions. These findings do not require a new interaction design.

## Findings

1. **P2 — Display the name from the deletion plan actually submitted.** `JournalLifecycleView.swift:155–164` captures `journal` from refresh, then awaits draft saving and another store read to obtain the deletion plan. A synced rename between those reads yields an old displayed name but a new `plan.title`; the store subsequently accepts the new title although the user reviewed the old one. Populate the prepared deletion name and count from the same captured plan (or return an atomic presentation snapshot with it). Preserve that snapshot until renewed explicit preparation. A controlled rename between initial refresh and plan preparation should show the new plan name, and a rename after preparation should still reject commit.

2. **P2 — Separate read failure from a successfully established missing parent.** On the first `refresh()` failure, `journal` stays nil, so `JournalLifecycleView.swift:122–135` claims the journal is unavailable or has not arrived and offers no local Try Again. That is not evidence of missing metadata, and a local-only user must close/reopen just to retry a transient read. Track load failure separately and retain Try Again within the sheet. Conversely, a typed missing-parent rejection during commit leaves the stale journal populated and generic retry visible; clear that presentation and enter the approved missing-parent guidance/export state. Neither path should auto-submit after refreshing.

3. **P2 — Disable the macOS Format menu for journal selections.** `JournalApp.swift:66–78` leaves Bold, paragraph styles, and Link enabled regardless of `model.canEdit`, even though the toolbar and journal detail are read-only. This contradicts the approved explicit action requirement and presents commands with no appropriate editor target. Apply the same editing eligibility to these commands, including their keyboard shortcuts. This is a source-observed enabled-command issue; no unintended content mutation is claimed without an interactive reproduction.

4. **P2 — Preserve date groups in Recently Deleted.** `RootView.swift:199–200` flattens all deleted entries into one Entries section, whereas the approved design explicitly retains existing month groups beneath Entries. Restore those groups so people can locate older deleted content using the established timeline structure.

## Small follow-through refinements

- Use the approved nonzero deletion scope sentence, “[count] entries on this device will move to Recently Deleted,” with singular handling; the current separate count and journal-only sentence leave the local entry effect implicit.
- Give preparation/commit progress a meaningful accessible label, and give repeated Restore Journal buttons in Settings their journal-name context, matching Delete.
- Restore preparation does not flush edits, unlike deletion preparation. In the already-restored path, `switchJournal` can silently return when flushing fails, while the sheet sets completed and hides Export Entry. Keep failed-save recovery visible in that outcome and distinguish completed lifecycle state from unsuccessful navigation; do not retry the restore mutation. Flushing before preparation or explicitly returning/checking navigation success can address this without losing the retained draft.

## Evidence and remaining verification

Core deletion compares both the plan title and live member IDs in the write transaction; restoration checks supported metadata/conflicts and the expected title, with explicit already-restored reporting for confirmation callers. Both mutations use model-owned reconciliation, and post-commit display failure disables repeat mutation and presents Done. Conflict review remains in the active sheet and invalidates the old plan on return. These are source findings, not proof of exercised UI states.

After corrections, inspect native confirmation, journal detail, trash date groups, empty/search states, and large text. Exercise last-journal delete/cancel/restore/relaunch, remote already-applied and stale-name states, preparation read failure, failed-save recovery, and lock around commit using focused existing harnesses. Interactive Mac keyboard/VoiceOver approval remains pending while the desktop is locked; offscreen renders may supply limited layout evidence only. Permanent purge and direct restoration of journal metadata history remain separate unfinished scope.

## Source correction and initial simulator visual review — 2026-09-20

**The four source findings are resolved.** Prepared deletion name now derives from `plan.title`, matching its member count and submitted atomic comparison. Explicit `loaded` state distinguishes refresh failure (Try Again) from absent metadata, and a typed missing-parent rejection clears the stale journal. Native Mac Format commands are disabled by `canEdit`. Recently Deleted uses the existing month groups, with Entries preceding the first group.

The small follow-through changes are also present: nonzero deletion copy explicitly identifies local entries, progress has a label, Settings restore actions include journal context, and failed-save Export Entry stays available even after an already-restored result. That path now explains why navigation did not happen. Preparing restore still does not flush, but commit retains the save gate and the already-applied failure retains draft/export recovery; this no longer blocks bounded source approval.

Inspected supplied simulator screenshots in `artifacts/journal-whole-ios-previews/`: `39696A38-1878-4B8B-B129-EF0D3C088CD5.png` (delete), `26D56A01-C50F-41F6-95A7-D399B1894F80.png` (restore), and `7EAD40C0-E31C-4377-895B-C7479ABFFBF7.png` (trash). The native single sheets have legible wrapping, visible Cancel and specific actions, quiet system surfaces, and clear restore scope; the trash separates journal and entry rows and presents the retention/search copy coherently. No additional visual blocker appears in these states. The delete scope sentence and trash month headers in these images predate the fixes and therefore do not visually verify those final details.

The parent reports all three actual simulator E2Es passed, including last-journal deletion, finding the journal and entry, cancelling restoration, restoring, and surviving relaunch. This is supplied execution evidence, not a test independently rerun by this reviewer. Final updated images/native checks remain pending; the reviewed screenshots do not prove error paths, long names, large text, VoiceOver, or interactive Mac behavior. Prior scope limits remain in effect.

## Final simulator and limited Mac visual evidence — 2026-09-20

**Approved for the reviewed whole-journal UI scope; no concrete blocker remains in the inspected final states.** Final simulator image `artifacts/journal-whole-final-ios-previews/5FDAE737-8494-4D57-8D31-859D308494B3.png` shows the corrected singular deletion sentence clearly and without clipping. `6D41C618-D636-4EF6-B416-6409AB73437F.png` shows Entries followed by September 2026 above the entry row, preserving the month grouping while keeping the separate Journals section. `751C1DB3-B11C-4071-9251-B3C0C1E29662.png` confirms the restore sheet retains readable scope, count, Cancel, and Restore Journal. These close the two final-image follow-ups above.

Also inspected `artifacts/journal-whole-mac-previews/EAB7C03B-40B1-41B8-B88F-E26A7B06438F.png`: the isolated native journal detail has a clear name, local count, and conventional Restore Journal button with adequate spacing. This is an offscreen component render, not evidence of an interactive Mac window, menu shortcuts, focus, or VoiceOver.

Read the supplied `/tmp/journal-whole-final-ios.log`: it reports 14 native iOS tests and 3 UI E2Es with zero failures and TEST SUCCEEDED, including `testDeleteLastJournalAndRestoreWithoutLosingEntry`, device pairing/download, and write/reopen. This reviewer inspected the execution log and screenshots but did not independently rerun the suite. The parent additionally reports 27 core tests, 15 native Mac tests, and an iOS build passed; those remain parent-reported checks here. Large-text/long-name and full accessibility/error-state coverage are not established by these default-state images. Interactive Mac review, permanent purge, and direct metadata-history restoration retain their previously recorded limits.
