# Sync and security UI: pairing check code and Change Password

Date: 2026-09-24. Owner-approved audit items S2 (pairing check code) and S5 (Change Master Password). Server, sync and restore changes (S1, S3, S4, S6) have no new UI beyond existing error text and are documented in protocol/README.md and docs/self-hosting.

## 1. Pairing check code (S2)

### Why the code appears after the pairing code is entered

The pairing code only finds the request. A check code proves both devices use the same keys, so the server cannot swap in its own key. To stop a dishonest server from trying keys until a 6-digit code happens to match, the new device first publishes only a commitment (hash) to its key; the approving device then contributes its own one-time key; only then does the new device reveal its key. Each device derives the same 6 digits from the pairing ID and both public keys. As a result the new device can show the check code only after the approving device has entered the pairing code. This matches familiar Bluetooth-style pairing: enter a code, then compare numbers.

### New device (ConnectionView, "Add This Device") — revision 2

Existing layout is unchanged until approval starts: title "Connect to a Server", Server Address (disabled), large pairing code (monospaced, selectable, VoiceOver reads digits), Copy Code, "On a connected device, open Settings > Devices > Add Device.", progress "Waiting for approval…".

When the other device has entered the pairing code, the pairing code, Copy Code and the "On a connected device…" instruction are all removed and the sheet shows exactly:

1. Title "Connect to a Server" and the disabled Server Address (unchanged).
2. Headline: "Check Code".
3. The code in large monospaced digits, grouped "123 456", primary label color (no tint, holds up with Increase Contrast), wraps rather than truncates at the largest text sizes. Not selectable. VoiceOver label "Check code", value read digit by digit.
4. Secondary text: "Make sure your other device shows the same code."
5. Progress: "Waiting for approval on your other device…".
6. Buttons: Cancel (leading).

The swap is not animated (no motion to reduce). VoiceOver announces: "Check code 1 2 3 4 5 6. Make sure your other device shows the same code."

If the approving device chooses Cancel, it declines the request. The new device then replaces the check code with "Your other device didn’t approve this request." and offers Get New Code (primary) and Cancel. If approval completes, the existing "Connecting…" state follows. Expiry is unchanged: "This pairing code has expired." with Get New Code.

Errors specific to this flow:
- The approving device's key doesn't match the one used for the check code (tampering): "Couldn’t add this device securely. Get a new code and try again." with Get New Code. No key material is accepted.
- The server doesn't support check codes: "This server needs an update before you can add devices." with Get New Code (to retry after updating) and Cancel.
- Occasional "too many requests" responses while waiting are handled silently by waiting longer between checks; only an expired or declined request ends waiting.
- VoiceOver announces each of these state changes (declined, expired, errors), since the user is probably looking at the other device.

### Approving device (Settings > Devices > Add Device… sheet) — revision 2

Step 1 is unchanged: title "Add Device", Pairing Code field, Cancel / Continue (Return continues).

After Continue, a short waiting step: progress "Waiting for [Device Name]…", Cancel. (Usually a couple of seconds: the new device reveals its key on its next check.) If the request expires first: "[Device Name] didn’t respond. Get a new code on the new device and try again." (returns to step 1).

Step 2 (confirmation):
- Title "Add Device".
- Question (headline, wraps): "Does [Device Name] show this code?" with the code in large monospaced digits "123 456" below it, primary label color. VoiceOver reads the question, then "Check code, 1 2 3 4 5 6".
- Secondary: "Approve only if the codes match. [Device Name] will be able to read and sync all your journals."
- Buttons: Cancel (leading, cancel role, Escape) and Approve (trailing, visually prominent). Approve is deliberately NOT the default (Return) button, so pressing Return twice can’t approve without comparing codes. It has its own keyboard shortcut, Command-Return, shown in its help tag, with the accessibility hint "Press Command-Return to approve." on macOS only While approving: Approve disabled, progress "Adding Device…", Cancel disabled.

Cancel at the waiting or confirmation step declines the request (best effort) and dismisses the sheet; the new device shows "Your other device didn’t approve this request." There is no separate "Codes Don’t Match" action.

Errors:
- The new device's key doesn't match what it committed to, or the pairing code expired: the sheet returns to step 1 with the Pairing Code field cleared and the error shown beneath it: "Couldn’t add this device securely. Get a new code on the new device and try again." / "This pairing code has expired."
- Temporary network error before Approve: the sheet stays on the current step, keeps the code, and shows "Couldn’t reach the server. Check the address and your connection, then try again." with Try Again (wording from sync-health-and-recovery.md; a server error says "The server isn’t available right now. Try again in a moment.").
- Network error after Approve was sent (the device may have been added): "Couldn’t confirm that [Device Name] was added. Check the device list." with Done; the device list reloads when the sheet closes. The user is never told to approve again.
- New device is an older version without check codes: "Update Journal on the new device, then try again." with only a Done button.

Accessibility: all text wraps and the sheet scrolls at large sizes; no fixed heights. Buttons have text labels. Escape cancels. The code is never conveyed by color alone.

## 2. Change Password (S5) — revision 2

Entry point: `ChangePasswordButton`, a "Change Password…" row for Settings > Privacy > Encryption section (placed by the lead; no extra explanation text in the row). It renders nothing for recovery-key, unencrypted or access-password libraries, and is disabled while Journal is locked.

Sheet (NavigationStack with a grouped Form on both platforms; ~440 pt wide on Mac):
- Title: "Change Password"
- Explanation (secondary, top section footer): "Use your new password to recover your journals on a new device. Backups and archives made earlier still use your current password."
- Section 1: "Current Password" secure field — content type password. Its footer shows the wrong-password error.
- Section 2: "New Password" (content type new password) and "Confirm New Password" (content type new password). Footer: "Use at least 12 characters." (same rule as creating the password). The mismatch message "The passwords don’t match." appears in this footer only once Confirm is at least as long as New Password or Confirm loses focus.
- Submit labels: Next on the first two fields, Done on Confirm; Return in Confirm submits when valid.
- Toolbar: Cancel (cancellation action) and a confirmation action labeled "Change" on both platforms. Enabled only when all fields are filled, the new password has at least 12 characters and both new fields match.
- Busy: fields and Change disabled, progress "Changing Password…" in the last section. Cancel is disabled while the request is in flight. Locking Journal doesn't interrupt a change already sent: it finishes and saves on this device in the background.
- Success: sheet dismisses quietly. The new password takes effect immediately on this device and the server.
- If connected to a server, the server copy is changed first, then this device. Other devices keep working; their device keys are unaffected.

Errors: shown as the relevant section footer with an exclamation-mark symbol and red text (not color alone), and announced to VoiceOver.
- Wrong current password (Current Password footer): "The current password is incorrect." Focus returns to Current Password.
- New password same as current (last footer): "Choose a password that’s different from your current password."
- Offline/server failure: "Couldn’t change your password. Your current password still works. Check your connection and try again."
- Server too old: "This server needs an update before you can change your password."
- Server changed, local save failed (rare, e.g. disk full): "Your password was changed on your server but not on this device. Try again to finish." The confirmation action becomes "Try Again", which retries only saving on this device (the new envelope is kept in memory; the Current Password isn't re-checked). Cancel is disabled for the first retry so the sheet isn't dismissed by accident; if Try Again fails too, Cancel returns and the footer reads "Your password was changed on your server but not on this device. Free up space, then try again." If the sheet is closed, Journal is locked or quits, nothing is lost: this device keeps opening with its device key as usual. Offline password behavior: when this device asks for the password (only if its device key is unavailable), it first tries the password it has saved; if that fails and the server can be reached, it checks the password against the server's copy and, if it opens the same journals, saves it. So offline, the old password still works on a device that hasn't saved the new one yet; once the new one has been checked and saved, the old one stops working on that device. Changing the password again on this device verifies the current password against the server's copy, so the new password is the current one.

Known limitation: another device that later needs the password to unlock (for example after losing its device key) accepts the new password by checking it against the server; archives it exported earlier keep the old password.

Accessibility: visible labels, full keyboard navigation (Tab order Current → New → Confirm → Change), Dynamic Type/scrolling supported, no reliance on color.

## Review

Round 1 (independent reviewer, original proposal): approve with changes. Addressed: Approve no longer the Return default; approver Cancel now declines and the new device says so; the new device's final contents specified with no animation; partial password-change failure keeps the new envelope and offers Try Again; explanation copy rewritten (no implementation terms, mentions older backups); errors as section footers with a symbol and VoiceOver announcements; mismatch shown only when Confirm is complete or loses focus; approver question shortened; tamper copy fixed; submit labels; primary-color code; old-server state keeps Get New Code; placement specified (Privacy > Encryption row).

Round 2 (independent reviewer, revision 2): approve with changes. Addressed: Approve gets Command-Return plus a hint (was unreachable by keyboard); approver warning names the new device; partial-failure end state defined (Cancel disabled, lock/quit safe, new password verified against the server on this device); approver errors return to step 1 with the field cleared, version error offers only Done; duplicate device-name headline removed; expiry copy for the waiting step; VoiceOver announcements for declined/expired/errors; "Change" on both platforms; explanation shortened; offline error says the current password still works; "This server needs an update…" wording.

Round 3 (same reviewer, short re-review): approve with changes; no further review needed once added. Addressed: Command-Return hint on macOS only; after a failed Try Again Cancel returns with a free-space footer; offline password behavior specified; approver keeps the code on temporary network errors and never asks to re-approve after an uncertain Approve.

Not adopted, with reasons (accepted by the reviewer): moving the existing pairing sheets to a Form/toolbar layout (a broader restyle of existing sheets outside this change; recorded for a consistency pass); a hidden username field for password managers (hidden autofill fields behave inconsistently across platforms and could not be verified here; the fields carry password and new-password content types).

## Implementation notes (2026-09-25)

- Implemented in `ConnectionView.swift` (new device), `DevicesView.swift` (`ApproveDeviceView`, approving device) and the new `ChangePasswordView.swift` (`ChangePasswordButton` and sheet). `ChangePasswordButton` still needs to be placed as a row in Settings > Privacy > Encryption by the lead.
- Deviation: when the server lacks check-code support, the new device shows "This server needs an update before you can add devices." and the existing Add This Device button retries (no pairing code exists yet, so "Get New Code" would be misleading).
- Pending: inspection of the running UI (step 4 of the design gate). The Mac app build was blocked by unrelated in-progress edits elsewhere in the app when this was implemented; the new files compiled without diagnostics. Inspect both pairing sides and the Change Password sheet (light/dark, largest text size, VoiceOver, keyboard-only with Command-Return) once the app builds.
