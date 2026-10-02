# Device connection completion review

Date: 2026-09-20  
Reviewer: independent design agent  
Reviewed: `devices.md` against `AGENTS.md` and approved `screens.md` revision 2. Proposal review only; no device UI inspected or implementation edited.

## Outcome

The native Devices tab, separate requesting/approving sheets, explicit upload consent, code-and-name verification, current-device marker, and download/revocation disclosure fit the approved direction. Scrolling forms, labeled progress, copyable codes, and locked-state gating are appropriate. **Request the following concrete revisions before implementing this extension.**

1. **Define approval that arrives during lock or after cancel.** “Never installs data” while locked is safe but incomplete: state whether the pending request is retained and resumed after unlock or canceled with a recoverable retry. The user must not become stuck on Waiting for approval after the server has already approved. Cancel currently stops polling while the server ticket remains approvable until expiry. Explicitly define how cancellation prevents subsequent enrollment, or invalidate/abandon the ticket and credentials so a late approval cannot finish pairing. Preserve the current local vault and consent state throughout; resume must not imply a new upload consent if none was given.

2. **Make errors and retries concrete.** Specify distinct inline outcomes and actions for invalid/not-found code, expired code at lookup or final approval, unreachable server, revoked authorization, and failed final local import. Suggested copy: “That pairing code wasn’t found. Check the code and try again.”; “This pairing code has expired.”; “Couldn’t connect to the server. Check your connection and try again.”; “This device no longer has access.” with Connect Again. Failed import must say local journals remain on this device and offer Try Again without losing the pending authorized state or creating duplicate devices. Revocation must leave the row visible with an error and retry if the request fails, rather than implying access has stopped.

3. **Disambiguate the device to revoke.** Names are not unique. Add a quiet native secondary identifier already supported by the device contract (for example last sync/added date, with sufficient precision for duplicate names), and include that identity in the revoke confirmation when needed. If no identifying metadata is available, add an explicit safe fallback in the proposal before exposing ambiguous destructive row actions. This is especially relevant to several devices all named “iPhone.”

## Nonblocking polish and verification

- Mark Add This Device/Recover Journals as a labeled native choice; “Connection Method” is sufficient if a label is needed. Keep recovery alternative reachable without crowding the waiting state.
- For a separated code, use one accessible label/value that reads every character intelligibly and a Copy Code action. Visual grouping must not change the value accepted on the approving device.
- Show an empty Devices list as loading while fetching, and expose errors instead of presenting a misleading empty connected account.
- Retain keyboard focus on the error/retry context. Disable duplicate submissions, while preserving a way to leave a waiting operation.
- Verify iPhone keyboard plus large text, Mac minimum-window size, VoiceOver code reading, two identical device names, lock during approval/import, and a network failure during revoke.

The revisions can stay within the proposed native controls; no new navigation or visual system is needed. Re-review the completed lifecycle/error decisions before implementation.

## Revision 2 re-review — 2026-09-20

**Approved for implementation and subsequent actual-UI verification.** Reviewed the added lifecycle/error decisions; they resolve the three requested revisions:

- Cancel/lock now abandon the requesting key, cancel the local task, and request serialized server cancellation/revocation. A late grant cannot silently complete pairing; a reopened flow starts with a new code. Lock prevents the final local configuration switch.
- Import failure has a concrete message and retry using the retained grant, preserving local journals and avoiding duplicate enrollment. Lookup, expiry, network, revoked authorization, list loading, and revoke failure each have an appropriate action. A failed revoke keeps the device visible rather than implying success.
- Device rows expose added date/time and a short device ID; revoke confirmation includes the ID. This distinguishes identical names while retaining familiar primary labels.

Treat revision 2 as authoritative over the earlier sentence saying Cancel only ends polling. Consolidate that obsolete sentence when maintaining the proposal. When connecting a device with no existing local journals, shorten the failed-import message to “Couldn’t finish connecting.” rather than referring to nonexistent local journals. These are small copy corrections, not grounds for another design review.

This approves the interaction proposal, not its concurrency/security implementation. Actual verification must still cover cancellation racing approval, lock during final import, retry after a received grant, failed revocation, large text/keyboard layout, and VoiceOver code reading. No device UI was inspected in this re-review.

## Implementation inspection — requesting-device screenshot and source

Date: 2026-09-20. Independently viewed `artifacts/pairing-attachments/93991306-D4ED-4755-9E84-F74223EB5960.png` and inspected `ConnectionView.swift`, `DevicesView.swift`, and the relevant client error mapping. The parent task reports that real simulator end-to-end pairing, encrypted entry download, and reopening passed; this reviewer did not independently run that test.

**Actual visual scope:** one light-mode iPhone requesting-device sheet while waiting for approval, at the pictured text size, without the keyboard. The code is clearly grouped, Copy Code is distinct, the next action on the other device is explained, progress is labeled, and Cancel remains visible. Native sheet presentation, readable spacing, and restrained copy match the approved proposal. No clipping or overlap is visible. This state is visually approved. The screenshot does not verify copied value, VoiceOver speech, cancellation, lock, large text, errors, the approving sheet, or the Devices list.

**Source matches:** requesting code exposes a spaced-digit accessibility value and copies ungrouped digits; sheets scroll; consent precedes local upload; Cancel/lock abandon the pending request; failed import retains the grant for Try Again. Device rows include added date/time and short ID, the current device has no revoke control, and a failed revoke keeps the row visible. Locked-state gates and dismissal handlers are present for the device sheets. These are source observations rather than behavioral test results.

**Remaining concrete departures:**

1. **P2 — Network retry restarts pairing unnecessarily.** After any polling error before receiving a grant, `ConnectionView` offers Get New Code and `beginPairing()` abandons the existing ticket. The reviewed network state calls for Try Again while preserving a still-valid request; another device may already be entering that code. Distinguish transient polling failure from expiry: retry polling the same code while valid, and offer Get New Code for expiry/cancellation. Map network failures to the reviewed concise connection copy rather than raw URLSession descriptions.
2. **P2 — Revoked authorization has no recovery action in two paths.** Initial device-list loading recognizes unauthorized and offers Connect Again, but `ApproveDeviceView.submit` displays only the error, and `DevicesView.revoke` maps unauthorized to a network-style retry. A revoked approving device cannot recover by repeatedly pressing Add Device/Revoke. Use the reviewed “This device no longer has access.” with Connect Again in those paths as well.
3. **P2 — Approval-code VoiceOver behavior differs from the proposal.** The requesting code has an explicit spaced-digit accessibility value; the approving sheet's candidate code is plain `Text(code)` and can be read as one large number. Give that verification code the same intelligible character-by-character value and label, then verify speech on both screens.
4. **P3 — Expiry can repeat the same message twice.** The requesting sheet emits an expiry Text when its date condition is met and also renders the polling error carrying the identical sentence. Keep one contextual expiry message with Get New Code. This state was found in source, not in the screenshot.

The existing-server chooser, initial address errors, expired/canceled requests, revoke confirmation, duplicate-name list, lock during import, dark appearance, and accessibility sizes remain visually uninspected. Do not extend the single screenshot's approval to those states.
