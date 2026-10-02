# Conflict review and background lock

2026-09-21. No production edits in this acceptance work. AppLockUITests configures a PIN, opens an ordinary two-version conflict, backgrounds the app through the Home action, returns, verifies the lock screen and absence of conflict picker/editor/Keep Both, unlocks with PIN and reopens review. After cancellation it compares the complete local record and ConflictVersion and asserts no history was created. The fixture is synthetic and isolated.

Normal44.967s and largest-dark51.729s pass. Logs: /tmp/journal-conflict-lock-{normal,large}.log. Captures and manifests: artifacts/conflict-background-lock-{normal,large}. Formatting, strict SwiftLint and hygiene pass.

Independent normal review approves all three captures: complete local version/title/date/body/actions before/after, and only the lock screen on foreground return. No visible conflict content/actions or sheet remnants. Other-device text is not captured; its exact stored version is covered by the test comparison. These screenshots do not prove app-switcher snapshots, transition frames, every accessibility-tree node, adversarial timing, biometrics, VoiceOver or live Mac behavior. Largest review follows.

Independent largest-dark review approves all three captures: the foreground-return screen contains only complete lock controls, and the before/after conflict views show the full captured heading/version selector/local title/date/body and Cancel. Resolution actions/explanation lie below this largest viewport and are not re-approved by these images. Scoped normal/largest foreground concealment review is complete; the limitations above remain.
