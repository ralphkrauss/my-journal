# App lock accessibility review

Independent reviewer: native_design_audit, 2026-09-21.

Normal-size four original captures: no material blocker in Lock Journal, wrong-PIN/error/recovery action or restored writing. Settings capture scrolls past heading and leaves substantial empty lower space; setup fields, keyboard, enabled Unlock and recovery form were not captured.

Largest-dark original four captures: material P2 finding in wrong-PIN screen: heading, error and recovery action truncate. Passing interaction is not readable-copy acceptance. Lock Journal and restored writing are readable in their bounded captures.

Proposal `app-lock-accessibility.md` approved before implementation. Reviewer requires optional biometric label to wrap, padding counted once in viewport minimum height, secure accessible field labels and system keyboard safe area retained. Actual normal/largest wrong-PIN and enabled recovery keyboard evidence remains required. No authentication behavior changes requested.

Bounded implementation source review approved: ScrollView content's padding is inside the viewport minimum height; all heading/error/action text including biometrics has intrinsic wrapping; field submission, copy and actions preserved. First corrected largest run captured full wrapping text but exposed a test navigation race after recovery: the editor appeared after the test had committed to waiting only for a list row. Failure hierarchy contains the expected Entry title. Corrected test waits for either actual editor or row before navigation. This run is visual diagnostic evidence only, not a passing end-to-end run.

Corrected largest route passes73.167s (`/tmp/journal-lock-layout-large2.log`). Independent review inspected all seven captures in `artifacts/app-lock-large-corrected` and closed the truncation finding: full heading/error/recovery action wrap and scroll; enabled recovery controls and restored writing are readable. Some captures naturally scroll the heading above the viewport. Keyboard and secure-content rendering are not visible in these captures, so neither is accepted visually; test interaction considers keyboard/inputView bounds when those elements exist. Setup heading/biometric and full Settings layout remain outside the bounded captures.

Corrected normal route passes62.881s (`/tmp/journal-lock-layout-normal.log`). Independent review inspected all seven `artifacts/app-lock-normal-corrected` captures and found no normal-size regression: complete error/recovery labels, enabled recovery controls, Lock Journal and restored writing. Centered field placeholder follows the approved alignment. Scoped normal/largest actual review is complete. Keyboard, biometric, VoiceOver and live Mac evidence remain outside it.
