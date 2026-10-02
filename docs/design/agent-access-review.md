# Agent access proposal review

Date: 2026-09-20. Independent review of `agent-access.md` revision 1 against `AGENTS.md` and approved `screens.md` revision 2. Proposal review only; no implemented agent-access UI or connector inspected.

## Outcome

**Approved for implementation with the small clarifications below.** The proposal preserves explicit, journal-scoped, read-only consent and discloses provider exposure before granting access. Native Forms and scrollable sheets, an empty grant list meaning off, bounded private activity, and immediate revoke without a needless confirmation fit the user’s Apple-native, minimal-copy direction. Keeping initial connection support on macOS and giving iPhone users a short explanation is honest and avoids a misleading mobile control.

The technical boundary is concrete enough for implementation review: device-local grants, authenticated loopback, no master key passed to the connector, no automatic inclusion of new journals, and access checked again before returning suspended reads. This is approval of the interaction design, not certification of the authorization implementation.

## Clarifications to carry into implementation

1. **Define “open” consistently.** On macOS closing the last window usually leaves the app running. State whether that closes the bridge, as “Closing Journal stops reads” currently implies, or whether quitting is the boundary. Prefer the literal approved behavior: closing the last journal window stops reads; reopening an unlocked window resumes them. Copy and actual lifecycle must agree. Check this separately from app lock and process termination.
2. **Describe exactly which version an agent reads.** Specify the most recently saved local version, excluding in-memory unsaved drafts and retained conflict/history versions. A live entry that has a conflict should not silently expose the remote/conflict snapshot; define whether its current saved local version remains readable. This can be a short connection-guide capability statement, not extra permanent Settings copy.
3. **Revalidate selected journals at final consent.** Keep selection bound to stable journal IDs and confirm that at least one selected journal is still live when Allow Read Access commits. If deletion removes the selection, return to the form with “Choose at least one journal.” Grants left with no live journals should show “No Journals” and grant no reads; keep Revoke accessible. Do not replace deleted scope with another journal or auto-include an imported/new journal.
4. **Make the confirmation’s Back/Cancel path safe at small widths.** Three horizontal text buttons plus a long primary label can become crowded at large text sizes. Use native sheet toolbar placement or an adaptive vertical action arrangement; preserve a clearly identified Allow Read Access action. No fixed-height footer or horizontal-only layout.

These clarifications do not require a new screen or another design-review round unless implementation changes the consent, scope, or lifecycle substantially.

## Copy and accessibility notes

- Keep the full disclosure on the final confirmation; it is necessary context, not redundant UI copy. In details, “Read Only” and the selected journal list are sufficient persistent status.
- The private connection-file explanation is useful. “Build the agent connector before copying instructions” belongs only to the development fallback; packaged app users should receive a repairable installation error instead of build instructions. Never enable Copy for a nonexistent executable/path.
- Display instructions in selectable text with an accessible label. Give Copy Connection Instructions a short nonpersistent completion acknowledgment accessible to VoiceOver; do not announce or log the credential contents.
- Name and checkbox labels should remain explicit after typing. Focus Name when adding, retain selected checks when going Back, and put error focus where the user can correct the issue. Empty activity should remain one short line.
- Duplicate grant names are possible. The scoped journal names provide useful differentiation; if two grants share both name and scope, show a creation date/time in detail so the user can identify which credential they are revoking.

## Required implementation verification

Inspect empty Settings, journal selection, confirmation, detail/instructions, activity, and errors on the actual Mac, including a small window, large text, dark appearance, keyboard-only use, and VoiceOver. Verify revoked/locked requests reveal no content or scope, an in-flight read is denied after revoke/lock, deletion/import does not broaden scope, failed durable creation/revocation reports the real access state, late creation after lock cannot install a grant, and closing the last window follows the chosen lifecycle. Read attempts and instructions must not expose secret material to logs.

No actual-UI state is approved by this proposal review alone.
