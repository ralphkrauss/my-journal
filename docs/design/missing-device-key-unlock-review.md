# Missing device key unlock review

2026-09-21, independent native_design_audit.

Initial proposal approved in UX/copy direction, with required post-authentication lifetime checks. Revised proposal adds captured store/session/credential validation after awaits and in catches, cancellation/replacement rejection, and silent stale completions. Revision approved before implementation.

First source review accepted preflight and authenticated-error handling but required revalidation after refresh before selecting an entry. Corrected both PIN and biometric paths. Existing-vault load ordering extension approved: locked=true after decoding existing config and before Keychain/store construction. This covers failures before the existing configured lock-state assignment; later refresh/unconfirmed-recovery failures are outside that correction.

File-size hygiene rejected the enlarged model. Existing validation/export/inspection/discard operations moved unchanged to DocumentTransferOperations.swift without access widening. Reviewer confirmed retained lifetime/cleanup checks. Final source and native actual evidence follow.

Final source review approves early lock assignment and post-refresh revalidation in both auth paths, closing the source finding. Final Apple lane passes59 core/44 Mac tests and iOS compilation; hygiene passes. Native normal missing-key22.160s and existing PIN61.771s pass; largest missing-key27.155s passes. Independent normal actual review inspects all10 captures and approves full missing-key guidance/recovery action and restored writing, plus unchanged normal PIN controls. Keyboard/secure content, actual missing-key recovery form, store-failure UI, stale-auth timing and live biometrics/VoiceOver/Mac remain outside that evidence. Largest actual review follows.

Independent largest actual review approves all three captures: full wrapped missing-key guidance, full recovery action after scrolling, and complete restored title/body. Heading/field naturally lie above the targeted scrolled viewport. Scoped normal/largest missing-key actual review is complete. No claim of visible keyboard, store-open-failure UI, biometric authentication or adversarial scheduling execution.
