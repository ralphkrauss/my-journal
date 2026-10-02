# Already-resolved conflict review

Date: 2026-09-21
Reviewer: independent native design audit agent
Disposition: accepted for the entry-notice presentation route; no production UI change required.

## Request and evidence

Review whether a stale entry conflict review may dismiss into the resolved entry after another store resolves the conflict, instead of remaining open with “These changes have been resolved.” The requirement is to prevent replay of stale Keep Both and preserve the authoritative result. No new UI was proposed or implemented for this review.

Independently inspected:

- `apps/apple/JournalUITests/EntryConflictUITests.swift`, `testAlreadyResolvedConflictDoesNotReplayStaleKeepBoth`.
- `EntryHeaderView.swift`, `SettingsView.swift` (`ConflictNotice`), `ConflictRouting.swift`, and `EntryConflictReview.swift` under `apps/apple/JournalApp/Views`.
- `JournalStore.resolve` in `apps/apple/Packages/JournalCore/Sources/JournalCore/Store.swift`.
- `/tmp/journal-resolved-review-final-test.log`: the selected test passed in 17.877 seconds.
- Final-run screenshot `artifacts/resolved-review-final/evidence/F6BB8166-6BB6-449A-A76B-0702E4836F39.png`.
- Earlier screenshot `artifacts/resolved-review/evidence/E98E51BC-CF84-42A1-9F1A-C45783C9CD3F.png`, treated as earlier evidence, not as the final-run capture.

The parent reports passing formatting, lint, and hygiene checks. These were not independently rerun. No tests were rerun by the reviewer, and the locked Mac was not operated.

## Findings

Dismissal is coherent for this route. The sheet belongs to `ConflictNotice`, which exists only while the selected entry has a conflict. After the stale action is rejected and the model refreshes, the conflict notice disappears along with its sheet. The entry displays the authoritative resolved content. Keeping an obsolete review open solely to satisfy a status-string assertion would impose a new interaction requirement without protecting additional data.

The final screenshot shows the complete title “A reflection”, the body “Words from the other device”, and the full blue fixture image below it. The native back, formatting, image, and more controls remain visible. There is no obsolete conflict notice, version picker, resolution action, or error. Nothing overlaps or truncates in this normal-text, light-appearance capture.

The source supports the observed result. Store resolution checks that the conflict row still exists and matches the reviewed revision and contents before history or record writes. An absent conflict throws `JournalError.conflict`. The review catches that condition and refreshes, resetting obsolete confirmation and preview state. It replaces an unchanged selected draft with the current stored entry. This path does not retry Keep Both automatically.

Quiet dismissal does not explicitly explain which external actor resolved the conflict. That is a limited discoverability tradeoff, not a material usability blocker in this already-resolved case: the review is no longer actionable and the current entry is visibly available. This conclusion is specific to the notice-owned entry presentation. A review presented by another owner may instead retain the existing completed-state copy; the test should not require every route to dismiss.

## Verification contract

The revised test protects meaningful behavior:

- It opens the review before a separate disposable `JournalStore` resolves the conflict to the remote version, then taps stale Keep Both.
- It requires the obsolete version picker and both resolution actions to disappear, and the remote body to appear.
- After termination and relaunch, it requires the entry title and no Review Changes action.
- A reopened store must have exactly the post-resolution baseline items and history, no conflicts, the exact attachment bytes, and the remote document under the original entry ID.

The post-resolution baseline is appropriate: equality against it detects an extra copy, unintended content mutation, or appended history caused by replay of the stale action. The image assertion additionally protects fixture attachment preservation. These assertions are stronger for this requirement than demanding transient, presentation-owner-dependent status copy.

No material findings remain for this bounded case. Acceptance does not establish VoiceOver focus behavior, accessibility text sizes, physical-device behavior, macOS behavior, every presentation owner, or a live sync-service race. The external resolution is deliberately supplied through an isolated second store.
