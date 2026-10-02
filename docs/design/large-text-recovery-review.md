# Large-text recovery layout review

Date: 2026-09-20. Independent preimplementation review of `large-text-recovery.md` and actual simulator screenshot `artifacts/journal-large-dark-scroll-previews/7F2F9003-74BD-4AB4-BDFA-674F0AE22534.png`.

## Outcome

**Approved for implementation and final visual verification.** The screenshot confirms a real overlap: the retention sentence occupies the same area as Entries and September 2026, impairing readability at the largest accessibility text setting. A passing navigation E2E does not resolve this visual defect.

Moving the unchanged sentence into a final, secondary, clear-background List row is an appropriate native correction. It gives the text measured layout space and a normal scroll position, retains the user's text size, and leaves native search behavior intact. Show it once after the result rows, only when filtered journal or entry results exist. This keeps No Results and No Deleted Items overlays unobstructed. Make it ordinary nonselectable informational text in the list's accessibility reading order, with no button/navigation semantics or image-specific label.

The collection selector's visible truncation is acceptable within this bounded fix provided its accessible name remains the complete collection/journal name. Do not cap Dynamic Type or replace the current structure with a fixed, taller header. Confirmation content can extend beyond one screen when all text and actions are reachable by native scrolling.

## Required final evidence

Rerun the single large-text/dark recovery E2E and inspect trash at the top and after scrolling to the entry and final note. Verify no overlap, clipping of the note, accidental selectable note row, or duplicate retention copy. Capture scrolled confirmation action states separately from top-of-sheet states so action reachability is visible. Confirm the simulator's prior text-size and appearance settings are restored after the run. These are bounded verification steps, not a request for broad additional E2Es.

The supplied E2E pass is parent-reported here; this review inspected the screenshot and proposal, not an independently executed run. Full VoiceOver/interactive Mac verification retains its previous limitations.

## Implementation and rendered-state review — 2026-09-20

**Approved: the inspected largest-text dark states resolve the retention overlap.** Source moves the unchanged note into the List after result sections, conditioned on Recently Deleted having filtered journal or entry results. The row uses secondary footnote text, a clear background and hidden separator; it is ordinary text without a selection tag or navigation action. The prior safe-area inset is removed.

Inspected `artifacts/journal-large-dark-fixed-previews/33F6D1A0-21B2-455B-9002-64DA44E6E254.png`: the entry and fully wrapped retention sentence occupy separate measured areas, and the sentence ends above the native search control without overlay. `71D54245-6E70-4183-BC45-350E44DF7973.png` shows the top journal and month groups without retention text obscuring them. The partial month visible at a scroll boundary is ordinary scrolling, not the previous text collision.

The scrolled sheet images `899656E2-DAE5-49DB-B51F-2B6AA12568BB.png` and `9ABEECD9-4DCE-4996-B5C5-80F0B93B411D.png` visibly expose Restore Journal and Delete Journal respectively, with their scope text above and Cancel remaining in the native toolbar. These now supply the action-state visual evidence missing from top-only screenshots. No font-size restriction or new fixed header is present.

The parent reports the targeted dark/largest-text E2E passed. Inspected `scripts/test-native-accessibility.sh`: it captures appearance/text settings before changing them, installs an EXIT trap to restore both, and runs the single bounded recovery E2E. The script's own execution/restored-setting result is still pending at this review point; source inspection alone does not prove restoration occurred. This review did not rerun the test or perform VoiceOver interaction. No additional implementation correction is requested for the reviewed overlap.
