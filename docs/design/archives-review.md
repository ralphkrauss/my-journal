# Archive and export completion review

Date: 2026-09-20  
Reviewer: independent design agent  
Reviewed: `archives.md` against `AGENTS.md` and approved `screens.md` revision 2. Proposal review only; no archive UI inspected or implementation edited.

## Outcome

The proposal fits the native, quiet writing experience. Settings and More keep backup/export out of the writing surface; native pickers, explicit encryption distinctions, embedded image bytes, full validation before restore, and separate imported identities are appropriate. **Readable entry export and Save Recovery Key may proceed; archive import needs the preservation decision below before implementation.**

## Required revision

**P1 — Protect an existing unsaved draft during import.** Archive export explicitly flushes before proceeding, but importing into an existing vault does not define the equivalent boundary. Atomic staging alone protects persisted journals; it does not protect text still in the editor when the staged snapshot is taken or the configuration changes. Specify that final import first successfully flushes the current draft and blocks editing/navigation that could alter that snapshot until commit, or otherwise explicitly carries every later edit into the committed vault. If flush fails, retain the draft, cancel/block the import commit, and expose the existing Try Again / Export Entry… recovery actions. Closing the import sheet must return to the unchanged draft. Also state that importing as new journals keeps the current vault's recovery key/app-lock settings and re-encrypts imported content under that vault; the supplied archive key unlocks the source rather than replacing current recovery credentials.

Re-review this small preservation addition before implementing archive import. It does not need another screen or confirmation.

## Required copy/action refinements

- **Use actionable missing-image copy for the actual cause.** “Some images haven’t downloaded. Connect to your server and try again.” is accurate only when the bytes are known to be pending from a configured server. For a local-only vault or an attachment missing from storage, use “Some images are unavailable. Restore them from another copy and try again.” Do not invent a server-recovery option that the app cannot perform. Both paths must leave the failed export without a success indication.
- **Name the final action consistently.** The validation preview should show Restore Journals for a new local vault, or Import as New Journals for an existing vault, matching the described outcome. Include counts that distinguish live entries from Recently Deleted rather than implying everything will appear in the normal timeline.
- **Make active-import cancellation explicit.** State that Cancel is unavailable during final commit, with labeled progress; before that point Cancel discards only staged import work. If lock interrupts import before commit, return to a clear retryable state after unlock. An interrupted import must not leave a completion sheet or claim success.
- **Do not give existing users sync-setup instructions unnecessarily.** Use “Journals Imported” for an additive import into an existing vault and reserve “Journals Restored” / “You can set up sync in Settings.” for creation of a new local vault. If the existing vault is connected, state in the preview that imported journals will also sync to its server; importing into a connected vault is consequential and that behavior should be visible before the action.

## Accessibility and verification

The proposed scrolling forms, explicit Recovery Key label, retained focus on errors, selectable text, and native picker/action ordering are approved. A normal-size mockup is not necessary for these familiar controls, but implemented inspection remains required. Verify iPhone keyboard plus large text, long journal names and counts, a supported and unsupported document export, no server configured with a missing attachment, wrong recovery key, lock before commit, a real failed local save followed by export, and cancellation before import. Verify that the complete archive includes images referenced only by history/conflicts or deleted entries, not just current live entries.

For readable HTML, confirm that journal content is represented as document content rather than executable markup; links and embedded images must not turn arbitrary entry text into active scripts or external fetches. This is a safety property of the promised readable document, not additional UI scope.

## Revision 2 re-review — 2026-09-20

**Approved for implementation and subsequent actual-UI verification.** The added preservation boundary resolves the blocking finding: additive import successfully flushes the draft before snapshotting, prevents concurrent editing/navigation through commit, preserves a failed draft and its export/retry actions, and retains the destination recovery key, PIN/biometric configuration, and connection credentials.

The revised preview now distinguishes live/deleted counts, labels additive import separately from restoration, and explains sync to an existing server. Cancellation/lock have explicit staged-work semantics and no false completion. Missing-image copy depends on the actual recovery path. History/conflict/deleted-only images are included, and the readable HTML rules preserve content without executing markup or fetching remote images.

Revision 2 is authoritative over the earlier general completion and missing-image wording. No further design revision is required before implementation. Approval covers the proposed interaction; source/test evidence and actual UI inspection must establish the promised snapshot boundary, lossless content preservation, failed-save export, lock interruption, keyboard/focus, and large-text behavior. No archive UI has been inspected yet.

## Actual normal iOS local archive round-trip — 2026-09-21

**Accepted for the demonstrated new-vault restoration fixture.** Independently inspected `JournalFileTests/ArchiveFileUITests.swift`, `/tmp/journal-archive-files.log` (43.658-second pass, `TEST SUCCEEDED`), the manifest and all five PNGs in `artifacts/native-archive-roundtrip/evidence`. No production source changed for this route and no reviewer tests were rerun.

The frames show readable Backup copy and complete Export Archive…/Import Archive… actions (`459F7DC5…`), the native named save above the keyboard (`AB199FD6…`), the saved archive as a selectable Files item (`0EB7EBA5…`), a restore preview distinguishing “1 entry in journals” from “1 in Recently Deleted” with complete Cancel/Restore Journals actions (`566DC14B…`), and the restored entry after relaunch (`8B27EC2B…`). The final editor visibly retains its title, bold “Preserved writing” and small blue image. No actionable normal-size visual defect is evident in these states.

The actual route exports through Settings, saves via On My iPhone, launches a fresh destination, imports that saved archive via Files, supplies its recovery phrase, executes Restore Journals, completes and relaunches. Final isolated-store assertions compare the exact three JournalItems and their ID set, including the deleted entry, and exact image bytes. This is native saved-package/restoration evidence for that fixture, not merely a direct archive API test.

The recovery-key entry and completion screens were executed but not captured for this review. Largest text was still pending. This run does not establish additive import into an existing vault, history/conflict-only or deleted-only attachments, server sync effects, failed saves, missing attachments, wrong keys, cancellation/lock during commit, multiple/long journal names, cloud providers, VoiceOver or interactive Mac. Those previously specified acceptance dimensions remain separate; no blanket archive acceptance follows from this successful local new-vault round-trip.

## Largest dark local archive round-trip — 2026-09-21

**Accepted for the demonstrated restore preview, local Files route and restored-content state at largest text.** Inspected `/tmp/journal-archive-files-large.log` (52.045-second pass, `TEST SUCCEEDED`), its manifest and all five PNGs in `artifacts/native-archive-roundtrip-large/evidence`. The same test provides exact three-record and image-byte assertions after native save/import/restoration/relaunch. No reviewer rerun or production change is claimed.

The native save frame (`4DE04AAC…`) exposes Save and the filename field above the keyboard. The Files frame (`B7A4F8D7…`) shows the saved archive enabled and the unrelated image dimmed, with wrapping/truncation of the long synthetic filenames. The restore preview (`9C604AB1…`) shows the complete journal name, live/deleted counts and both Restore Journals and Cancel. The relaunched editor (`8C6FA72C…`) retains the full wrapped title, bold body and blue image without overlap.

The frame labeled Archive backup controls (`24CE1351…`) is scrolled beyond Export Archive… and its explanation; it shows Import Archive… and the following Agent Access section. The test successfully activates Export Archive…, but this particular capture does not establish full largest-size visual readability of that export control or its explanatory copy. That remains a capture coverage limit rather than a demonstrated layout defect. Recovery-key entry/completion screens and the other archive dimensions excluded above remain uninspected. The parent reports an independently checked empty provider staging location after cleanup; this reviewer did not query it.
