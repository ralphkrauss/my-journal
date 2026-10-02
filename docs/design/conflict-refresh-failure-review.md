# Conflict refresh failure review

Date: 2026-09-21
Reviewer: independent native design audit agent
Verdict: accepted for the supplied iPhone failure/recovery case; no material UX finding or production change required.

## Evidence and observations

Independently inspected `EntryConflictUITests.testFailedStaleRefreshBlocksResolutionUntilRetryLoadsCurrentVersions`, the existing `EntryConflictReview` source, and `/tmp/journal-refresh-failure-test.log` (selected test passed in 26.498 seconds). Inspected both actual captures under `artifacts/refresh-failure-review/evidence`:

- `DF1533A5-8CF1-4FC8-ACF0-F8EBEA3C0E88.png`: the Review Changes sheet clearly shows “Changes couldn’t be updated.”, Try Again, and Cancel. Obsolete versions and resolution choices are absent. Copy and controls are unobstructed and readable in this normal-text, light-appearance capture.
- `EFA88EE1-466F-487E-9C7B-B53E3C65D4CA.png`: recovery shows “These changes were updated. Review both versions again.”, the version selector with Other Device selected, “A reflection”, current body “Newer words arrived during review”, the complete fixture image, and Keep Both / Keep One Version. The notice explains why review is needed again; visible controls and content do not overlap or truncate.

This is a coherent recovery flow: failure leaves an actionable retry and exit without offering unsafe stale choices. Successful retry restores review of the current versions without replaying the previous choice. The source retains `needsRefresh` on failure, clears confirmation and preview state, hides the version/actions branch, and independently guards resolution while refresh is required. Retry performs refresh rather than resolution.

## Behavioral evidence and limits

The test changes the remote conflict in a second isolated store, then temporarily renames the history table so the refresh read fails after stale resolution is rejected. It asserts the initial failure text and retry are hittable and both resolution choices and the picker are absent. A repeated failed retry again checks failure text and absence of Keep Both; the other two absence assertions are not repeated at that checkpoint. Successful retry must show current remote text. After Cancel and relaunch, exact baseline items/history, the exact updated conflict, and attachment bytes must remain intact. This meaningfully checks that failure and retry neither resolve nor duplicate the conflict.

Acceptance is bounded to these screenshots, source, and passing isolated-fixture test. It does not establish VoiceOver focus, accessibility text sizes, physical-device/macOS behavior, or a live sync-service failure. The parent reports passing format/lint/hygiene checks; the reviewer did not rerun them or the UI test and did not operate the locked Mac.
