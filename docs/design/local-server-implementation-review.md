# Local server implementation review

Date: 2026-09-20. Independent source review against `local-server.md` and `local-server-review.md`. Inspected `LocalServerView.swift`, `LocalServerController.swift`, and relevant connection/sync methods in `AppModel.swift`. No implementation edits or independent tests. No rendered local-server artifacts were supplied for this first pass, and no interactive Mac UI was inspected.

## Findings

1. **P2 — A slow shutdown leaves the promised retry unavailable.** After the ten-second shutdown wait, `stopProcess` reports “The server is still stopping. Try again in a moment.” but leaves phase `.stopping`. `LocalServerSection` displays disabled Start Server, and controller `stop()` also refuses calls while busy. If the child remains alive, no offered action can retry stopping it. Keep the truthful Stopping state, but provide an explicit retry of owned-child shutdown or clear guidance for the actual supported next action. Never enable Start until the old child exits; do not label it Stopped prematurely.
2. **P2 — Corrupt-settings guidance points to an undefined repair.** The configuration-load error says “Restore a backup before trying again,” while `invalidConfiguration` blocks start/setup indefinitely. The app's journal archive import does not restore `local-server.json` or clear this controller state. Name the supported server-settings recovery route and preserve the nonempty server data directory, or use an accurate unavailable-settings message with a real repair/export path. Do not suggest that importing an ordinary journal archive repairs this state if it does not.
3. **P2 — Initial-sync failure lacks the reviewed explanation.** Running is correctly separate from `model.syncError`, but the settings section displays only the raw sync error. Add the reviewed contextual explanation that the server is running and local changes remain saved when that is true, with retry directed to Sync Now rather than startup. If local saving has failed, do not claim durability. The setup sheet can otherwise close onto an error without explaining whether server setup succeeded.
4. **P2 — Transitional status has no explicit accessible announcement.** The configured-server section pairs a raw status Text with an unlabeled ProgressView. Setup's ProgressView is labeled and key errors restore focus, but Starting/Stopping/crash changes in Settings have no explicit VoiceOver announcement or focus handling. Use a labeled native status/progress element and verify announcements without moving focus unnecessarily. This is source evidence of missing explicit handling, not proof of actual VoiceOver output.

## Positive source observations

The native structure matches the proposal: setup scrolls with separate persistent actions, the recovery key stays concealed, the guide uses a native disclosure, Local Address and Copy Local Address are distinct from private HTTPS guidance, and macOS 13 users receive the platform limitation without losing separate-server/local-only use.

Running requires an owned live process and readiness with its per-launch instance identity; a coincidental listener cannot satisfy that check. Stop persists the disabled preference before shutdown, and status stays Stopping until exit. Crash changes status with an explicit restart action. Initialization retries an existing server using recovery rather than overwriting its directory. Setup flushes local edits, checks cancellation/lock before connection commit, and only stops an uncommitted owned child on cancellation. PIN settings are preserved by the shared vault-install path. These are source observations, not comprehensive lifecycle verification.

## Verification still required

Inspect setup, wrong-key error, running/stopped, startup/shutdown, helper failure, port collision, initial-sync failure, and partial-setup retry. Test slow/nonexiting child shutdown, corrupted settings with intact server data, last-window close, quit with failed local save, lock during setup versus after commit, small Mac window, large text, keyboard and VoiceOver. Source review alone does not complete the mandatory actual-UI inspection gate.

## Proposed refinement review — 2026-09-20

**Approved before implementation**, with the saved-state condition below:

- Slow stop may say “The server is taking longer to stop. Quit Journal to try stopping it again.” The described Quit path retries owned-child shutdown and refuses to quit while the child still runs, so the action is real. Keep Stopping and keep Start disabled. Verify the retry and refusal on the actual app.
- Corrupt settings may say “The server settings couldn’t be opened. You can keep writing and export your journals from Settings.” This accurately offers available journal-preservation actions without claiming archive import repairs server configuration. Maintenance instructions may explain preserving `local-server-data` and recovering the original settings file from a system backup. This resolves the misleading-copy finding; it does not establish an in-app server-repair workflow.
- Initial-sync errors may distinguish Running and offer Sync Now. Use “Your changes are saved on this Mac” only when local persistence is actually complete; `!saveFailure` alone also includes a draft still waiting for its debounce. If the implementation cannot establish that all current changes are durable, use the simpler “The server is running, but couldn’t sync. Choose Sync Now to try again.” alongside the contextual error. No added confirmation is needed.
- Label configured-server progress with its phase and announce phase changes using the native accessibility API without moving focus. This matches the reviewed accessibility behavior; actual VoiceOver output remains to be verified.

These changes need no further proposal review unless their lifecycle behavior changes. No new rendered or interactive state was inspected in this refinement review.

## Offscreen render and refinement recheck — 2026-09-20

Independently viewed three **offscreen native, normal-size light-mode renders**:

- `artifacts/local-server-previews/6E9B3589-1CB1-47DA-A696-8B6114100C68.png`: setup with empty Recovery Key and disabled Start Server.
- `artifacts/local-server-previews/A9F9FF26-0291-46E1-B766-2800FA552A36.png`: configured Running state, Sync Now/Stop Server, collapsed Connection Details.
- `artifacts/local-server-previews/82CE7FD7-EDB3-4FA9-9236-AC54F955D18C.png`: Stopped state with Start Server and other-device availability explanation.

**These rendered states meet the approved visual direction.** Setup has readable explanatory copy, a clear concealed-key input, and separated persistent actions. Running/Stopped are legible native status rows with the correct corresponding action, and technical connection guidance stays collapsed. No clipping, overlapping controls, or unnecessary decoration is visible. The flexible blank space in the setup sheet is acceptable. Do not extrapolate these observations to interactive behavior.

Source recheck confirms the approved refinements: slow shutdown now names Quit Journal as the supported retry; corrupt-settings copy offers continued writing/export without implying archive repair; running-but-failed-sync copy makes no unverified local-durability claim; progress has its phase label and phase changes post a native accessibility announcement without a focus move. **Original findings are resolved in source/copy**, with behavioral verification still needed. Minor polish: during a transition the section currently renders the phase Text and the same ProgressView label; a single labeled progress row could avoid repeating “Starting Server…”/“Stopping Server…” visually.

No new material finding arose from these renders. They are not desktop screenshots or interactive Mac QA; the desktop was not unlocked. Wrong-key/collision/helper errors, slow stop and quit retry, corrupted settings, initial-sync failure, expanded details, partial setup, dark appearance, large text, keyboard, and actual VoiceOver output remain uninspected here. The renders also predate the final error/status changes; those changes were rechecked in source only.
