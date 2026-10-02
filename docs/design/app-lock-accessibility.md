# App lock text accessibility

## Observed problem

The largest Dynamic Type/dark native run completes PIN setup, rejection, unlock and recovery, but its wrong-PIN screenshot (`artifacts/app-lock-large/BC26C6E0-5E46-41E5-9745-978D57691F3E.png`) truncates “Journal Is Locked”, “That PIN isn’t correct.” and “Use Recovery Key”. The current full-height VStack compresses content into the keyboard-reduced region. A passing interaction test is insufficient.

## Proposed layout and behavior

Retain the same native controls, order and copy: lock symbol, Journal Is Locked heading, secure PIN/Recovery Key field, inline error when present, Unlock, optional biometric action, and Use Recovery Key/Use PIN. No new steps or authentication behavior.

Use a vertical ScrollView with a content VStack, centered horizontally. Give the content at least the available viewport height so ordinary content remains vertically centered, while allowing its natural height to grow and scroll when text or keyboard requires it. Keep 32-point surrounding padding and the existing 300-point maximum input width. Allow heading, error and action labels to wrap with intrinsic vertical height; use centered multiline alignment and no font shrinking or Dynamic Type cap. Keep Unlock's native prominent button and the secondary recovery action's existing accent/plain appearance. On macOS preserve the current centered layout through the same viewport behavior.

The system keyboard continues to reduce the safe viewport; controls below it must be reachable by scrolling. No auto-dismissal, focus jump or new progress copy is introduced. Empty input keeps Unlock disabled. Wrong PIN remains inline and recovery mode clears that error as today. Preserve biometric conditional visibility and secure field submission.

## Verification

Re-run only the affected native AppLock route at normal and largest-dark sizes. Capture complete wrong-PIN text and recovery action by scrolling as necessary, plus actual enabled recovery form. Verify content frames against scroll viewport and keyboard input region where present. Keep exact stored entry equality and cleared PIN/biometrics after recovery. Independent actual screenshot review follows. Run strict Apple and hygiene checks; refresh packages if this production change is accepted. This does not establish VoiceOver, physical keyboard, biometric or real Mac interaction acceptance.
