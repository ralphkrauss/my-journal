# Entry export at accessibility text sizes

## Observed problem

Actual largest Dynamic Type dark screenshot `artifacts/native-export-large-probe/evidence/B3DA1AD4-FB87-4F57-A523-708A6231790A.png` shows the native menu picker's two-line Readable Document label clipped and the side-by-side Cancel/Export actions splitting Export within the word. Export itself opens the system save picker. The subsequent test failure tapped the underlying sheet's Cancel rather than the active system picker; that is a test targeting defect, not proof that export failed.

## Proposed layout and interaction

Keep the existing scrollable Export Entry sheet, format names, unencrypted-file explanation, failure/unsupported copy and native file exporter. At accessibility text sizes replace the compact menu picker with two full-width native buttons in a vertical group labeled Format: Readable Document and Journal Entry. Each wraps naturally, has a trailing system checkmark for the selected value, a selected accessibility trait and its full name as the accessibility label. These buttons select a format without starting export. At ordinary sizes retain the current native Picker.

At accessibility sizes stack progress, a full-width Export… button, then Cancel. Permit natural multiline labels without fixed heights. Keep the existing horizontal actions at ordinary sizes. Scroll the whole form; do not shrink or cap the user's font size. Disable format changes during preparation/export and preserve existing export eligibility. No changes to export serialization, encryption, filename, content type, lock behavior or dismissal semantics.

## Verification

Independently inspect normal and largest dark actual UI, including both selected formats and full control reachability. Exercise native save with a unique synthetic filename and check resulting data from local Files storage; verify cancellation separately through an actual active system control. Preserve source entry across cancellation and export. This remains opt-in provider-dependent acceptance, not a new routine CI UI suite. Browser rendering, VoiceOver and live Mac remain separate evidence.
