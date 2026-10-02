# Newer-format conflict actual review

2026-09-21. No production changes in this acceptance work. Native UnsupportedConflictUITests seeds a known local entry and remote raw JSON containing an unknown futureLayout field. It opens Review Changes, checks the update explanation and enabled Export Archive action, refuses the presence of known destructive resolution controls, cancels, relaunches and repeats. After each cancellation it compares the complete local record and exact raw remote JSON and asserts no history was created.

Normal22.162s and largest-dark22.308s pass. Evidence: artifacts/unsupported-conflict-normal and artifacts/unsupported-conflict-large; original result bundles are recorded in /tmp/journal-unsupported-{normal,large}.log. Tests use synthetic isolated storage.

Independent normal review inspected both screenshots: full explanation, Export Archive, Cancel and heading are readable; no resolution/deletion actions visible. No visual blocker. Actual archive saving/failure is not exercised by this test, nor are stale conflicts, lock transitions, unsupported local records, every possible future schema, VoiceOver or live Mac interaction. Exact preservation is asserted by the test, not proven by screenshots.

Independent largest-dark review inspected both captures and approved the full wrapped heading, explanation and archive label plus native Cancel; no clipping or destructive actions. The export ellipsis is intentional punctuation. Scoped actual normal/largest review is complete, with the limitations above retained.
