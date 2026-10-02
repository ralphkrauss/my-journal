# Unsaved draft export: independent acceptance review

## Evidence inspected

Read `apps/apple/JournalFileTests/UnsavedDraftExportUITests.swift`, export verification in `scripts/test-native-file-import.sh`, `/tmp/journal-unsaved-draft-export-baseline.log`, the evidence manifest, all three PNGs, and the exported `artifacts/unsaved-draft-export-baseline/unsaved-entry.html` source. No tests were rerun and no production code was changed. The HTML was not opened or rendered in a browser; no workaround for the previously rejected file URL was attempted.

The native test passed in 30.143 seconds, with zero failures and TEST SUCCEEDED. The log separately reports simulator diagnostic collection could not locate simctl and duplicate accessibility-loader warnings; these do not replace or invalidate the reported test outcome. The host verification subsequently reports that the native export rescued the unsaved draft.

## Behavior established

The fixture saves an empty entry, reads its serialized/persisted baseline back, and installs a SQLite trigger rejecting inserts into records. The native editor receives one X, shows the save error, and the test dismisses the alert. It opens Export Entry… from the persistent notice, cancels the options sheet, verifies the body still equals X, reopens export, and completes the native local Files save. The trigger is never removed in this route. After export, the test verifies Try Again remains available and the body still equals X, then reads the selected entry from the store and compares the complete JournalItem with the persisted pre-edit baseline. Thus this route rescues an unsaved value without pretending it was committed to the vault. It does not assert whole-database equality, unrelated entry count, or retention after quitting with the rejected draft.

The host script uses a unique UUID-derived filename in the simulator's local Files provider, checks that the expected export path did not exist before the run, copies the resulting HTML into the evidence directory, and checks for the exact title, X paragraph, and CSP marker. The source itself contains `<h1>Unsaved writing</h1><p>X</p>`, with a UTF-8 declaration, date, viewport metadata, and restrictive CSP. The full short artifact contains no alternate body payload. The script's assertions are presence checks rather than a general HTML equality/security audit; this inspection confirms the simple fixture output, not all rich content or attachment export fidelity.

## Actual presentation

- `5ADC7A01-C23E-4970-800A-FF373AC19594.png`: Export Entry sheet shows the Readable Document choice, complete “These files aren’t encrypted. Share them only with people you trust.” explanation, and clear Cancel and Export… actions. No clipping or overlap is visible.
- `CBC1B3BF-D776-491C-93BF-98070998D085.png`: native On My iPhone destination and Save control are visible, with the active filename field above the keyboard. Its long synthetic filename is horizontally scrolled to the insertion point; this is native field presentation, not lost filename content. The image is a pre-save capture; completion is established by the subsequent route and host file verification.
- `04C1D28B-07D3-4D24-865D-F8D1630E32AC.png`: after native export, the complete Not Saved, Try Again, and Export Entry… notice remains visible above the full title and X with insertion caret. All are clear above the predictive keyboard. The interface correctly continues to distinguish an exported rescue copy from a successful local vault save.

No material visual or copy finding was identified in these normal-text light-mode iPhone captures. Cancellation/reopening is demonstrated by the test route, not by separate before/after cancellation screenshots.

## Disposition and limits

Accepted for the bounded synthetic rejected-write → cancel/reopen export → local Files save route and its retained failure/draft state. This is useful recovery evidence: the exported bytes contain the value absent from the unchanged persisted entry. It is not a real disk-full, read-only filesystem, permissions failure, other Files provider, export-write failure, largest-text, dark-mode, VoiceOver, physical-device, or Mac acceptance result. It does not cover multi-character typing while an alert interrupts input, large/rich drafts, or unsaved attachment recovery. Browser-rendered HTML quality remains outside this review.

The parent reports earlier fixture failures from missing MainActor isolation, an alert interrupting multi-character typing, and timestamp comparisons against an unserialized object. The current source explicitly uses MainActor for UI work, types one X, and compares against the reread persisted baseline. Those corrections make the present assertions appropriate; the earlier attempts were not reviewed or treated as passing evidence. No further material finding remains for this acceptance scope.
