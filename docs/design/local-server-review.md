# Server on this Mac proposal review

Date: 2026-09-20. Independent review of `local-server.md` revision 1 against `AGENTS.md`, approved `screens.md`, and the existing recovery/lock design. Proposal review only; no local-server UI inspected or implementation edited.

## Outcome

**Approved for implementation with the lifecycle/copy clarifications below.** The two choices, Use This Mac and Connect to a Server, are understandable and preserve local-only use. Bundling the optional self-contained server avoids Docker/.NET setup in the Mac flow. Keeping port/Tailscale details behind a disclosure, pairing in Devices, and Stop/Start distinct from deletion fits native conventions and keeps writing primary. Existing remote hosting is not silently migrated.

The proposal appropriately distinguishes encrypted backend availability from app/agent unlock and last-window behavior. Keeping a manually stopped server stopped after relaunch is important and explicitly covered. No additional setup screen, broad migration flow, or confirmation is needed.

## Clarifications to implement

1. **Make the partial-setup retry path explicit.** If the local server initialized but committing this device's connection failed, retry/relaunch must recognize the same private server directory and complete recovery/authorization with the existing recovery key; it must not attempt a fresh initialization or create a second server. Retain a retryable settings state such as “Setup couldn’t finish.” / “Try Again.” Until authorization and connection commit finish, do not present setup success merely because the child process is healthy. The underlying proposal requires recovery after partial setup; this specifies the user-facing continuation.
2. **Define cancel versus ordinary lock once.** Cancel or lock before setup commit stops any child started only for that uncommitted setup and leaves local journals/PIN/recovery intact; preserve initialized server data for the retry described above. After setup is committed, locking only hides settings/content and leaves the encrypted server running as intended. In-flight startup must not later commit a connection after cancellation. Quit should stop only the child owned by this app after successful local-save handling, never another process at the same address.
3. **Tie Running to the owned process and verified readiness.** A listener already using the port is not proof that this server is running. Starting must be disabled while a start is pending, and crash/exit/readiness failure must replace Running promptly. Stop must show stopping progress until shutdown is confirmed; do not claim Stopped while an owned child continues listening. Preserve Start Server as the deliberate retry, without a restart loop.
4. **Use narrower port-conflict copy.** “Close the other app” may ask the user to disrupt an unrelated service they cannot identify. Prefer “This server address is in use. Quit another copy of Journal if one is open, then try again.” If the implementation supports selecting another local port, offer that as the explicit alternative and explain that any configured private forwarding must be updated. Do not silently change an established forwarded port.

These are refinements of the approved lifecycle, not a request for additional scope. No further design round is required unless the implementation changes hosting identity, network exposure, or recovery behavior.

## Copy and accessibility

- Replace “The server runs while Journal is open” with “The server runs until you quit Journal.” This matches macOS behavior when the last window closes. “Keep this Mac awake” remains useful context for other-device access.
- Label the loopback value “Local Address” and its action “Copy Local Address,” alongside a short explanation that other devices need the private HTTPS address. This avoids a generic Copy Address appearing to provide a usable phone connection address. Copy only the address, as proposed.
- Wrong-key errors should retain focus in Recovery Key. Startup, stopping, and errors need accessible status announcements without speaking secrets. Keep recovery input concealed and exclude it from logs, command lines, and copied connection guidance.
- A failed initial sync must say the server is running separately from the sync failure, and should only claim journals are saved when no actual local-save failure is outstanding.
- Keep Tailscale commands/setup detail in the disclosure or linked distribution instructions. The main setup should remain a recovery-key field and a clear Start Server action.

## Required verification

Inspect native setup, wrong key, starting/stopping, running, crash, missing helper, collision, and initial-sync failure; include minimum Mac size, long guidance, keyboard and VoiceOver. Verify restart after partial setup, manual stop across launch, closing the last window, quitting with failed local save, lock during setup versus lock after setup, and protection of a nonempty server directory. Verify the packaged app on a Mac without an installed .NET runtime or Docker. Source/build success alone does not establish the UI or lifecycle behavior.
