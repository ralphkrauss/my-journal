# Native interface review — revision 1

Date: 2026-09-20  
Reviewer: independent design agent  
Reviewed: `screens.md`, revision 1, against `AGENTS.md` and `initial-review.md`. No implemented UI inspected.

## Outcome

The proposal resolves most initial findings and is sufficiently concrete for the main writing interface. Approval is per feature below. The remaining blockers concern preserving edits and making security and recovery decisions understandable; they do not require expanding the product.

| Feature area | Decision |
| --- | --- |
| Main window, journal selection, scoped search | Approved for implementation and subsequent actual-UI inspection |
| Basic editor, formatting, inline images, read-only unsupported content | Approved for implementation and subsequent actual-UI inspection |
| Entry creation and templates | Approved; keep Blank Entry directly available when a default template is configured |
| Journal deletion, restoration, moving entries | Blocked by findings 1 and 2 |
| Quiet saving, pending sync, offline writing | Approved for ordinary states; local save failure blocked by finding 1 |
| Conflict review | Blocked by finding 3 |
| Local first-run start | Approved; remove the nonessential tagline if it crowds the initial screen |
| Server connection, pairing, recovery, app lock | Blocked by findings 4–6 |
| Agent access | Blocked by finding 7 |
| Shared accessibility direction | Approved as requirements; verify on actual UI, especially rich text and sheets |

## Required revisions

1. **Preserve and locate unsaved edits after failure.** The design retains in-memory text but does not say what happens if selection, journal movement, window close, or lock follows a failed flush. Specify that a move cannot complete until the save succeeds, and that navigation cannot strand or replace failed edits. Closing must offer a clear way to keep the window open or export the complete entry; Copy Text alone does not retain images and formatting. Lock must hide content while retaining the failed draft in memory, with the error restored after unlock. Use “Couldn’t save changes on this Mac.” on macOS to distinguish this from sync failure. Define where the retained draft and its recovery actions remain reachable.

2. **Define restoration after journal deletion.** Recently Deleted is useful, but the original journal no longer exists. Choose whether Restore recreates it or asks for a destination, and describe the choice in the restoration UI. Make clear whether deleting a journal removes the journal itself and its template preference, as well as moving entries. Confirmation must name the journal and entry count. This does not need additional retention features.

3. **Resolve conflict terminology and layout.** In a two-version sheet, “This Version” and “Other Version” are ambiguous when versions are viewed side by side or one at a time. Use labels tied to the visible version, such as “Keep Version from [device]…”, with a date when device names match. Specify a scrollable layout that permits full entry inspection at the minimum supported window size. State where recoverable conflict history is opened and how an original is restored; promising recovery without a reachable action is insufficient. Keep Both should explain that two entries will remain, and retain focus predictably when remote changes require another review.

4. **Finish the connection and pairing failure states.** Define exact copy and actions for an invalid address, unreachable server, failed authentication or setup code, rejected or expired pairing code, and canceled approval. Preserve entered address and existing journals on retry. State how users verify that they are approving the intended device using the displayed code and name. A device name alone is not sufficient identification. Make the choice concerning existing local journals concrete, for example “Keep on This Mac” versus “Upload to [server]”, according to actual supported behavior; do not use an undefined “merge” consent.

5. **Make the recovery consequence explicit.** “You’ll need it if you lose access to your devices” does not explain that a forgotten recovery key cannot be reset to regain encrypted content. Before confirmation, say “If you lose access to all your devices and this recovery key, you won’t be able to recover your journals,” if that matches the contract. Use one user-facing name consistently: Recovery Key or Recovery Passphrase. Define an incorrect-key state and its retry action. Specify whether a purely local journal can be restored with the key alone; if encrypted data or a backup is also required, the setup copy must say so and not imply the key is a backup.

6. **Specify app-lock fallback and forgotten-PIN behavior.** Define the default authentication method, availability without Touch ID, and what happens when the PIN is forgotten. Explain “This PIN unlocks Journal on this device. It cannot recover your journals.” Do not imply PIN reset restores encryption keys. Define which explicit recovery or device-authentication path can restore local access, and whether any reset removes local data. The actual supported path must be reviewed before implementation.

7. **Put agent disclosure before granting access.** Specify the final grant action and its exact explanation, including read-only selected-journal access, the possibility that a cloud agent sends retrieved text to its provider, and that revocation cannot retract content already retrieved. Present this before access is enabled, not solely inside copied connection instructions. Clarify that Revoke prevents future reads immediately; the existing locked-app restriction is appropriate.

## Implementation inspection notes

Approved areas still require actual-UI inspection. Check sidebar/editor usability at 640×420; accessible names for Aa, cloud status, and icon actions; keyboard focus after entry creation, search, and returning from sheets; long journal names in search labels; enlarged text without clipping; and VoiceOver heading/image support in the actual rich-text control. These are verification requirements, not requests for new features.

Re-review the revised blocked areas before implementing them. Approval of the main writing interface does not extend to unresolved security, recovery, deletion, or failure flows.

## Revision 2 review — 2026-09-20

Reviewed only the new Revision 2 decisions. This section supersedes the blocked decisions above; the original findings remain as review history.

| Previously blocked area | Revision 2 outcome |
| --- | --- |
| Failed local save, navigation, close, move, and lock | Approved. Pinned draft, lossless export, and close interception resolve the loss-of-work ambiguity. |
| Journal deletion and restoration | Approved. Recoverable journal metadata and explicit restoration behavior resolve the missing destination. |
| Conflict review and recovery | Approved. Device/time action labels, narrow-window full previews, and Version History provide understandable choice and recovery. |
| Server connection and pairing | Approved subject to the small copy corrections below. Existing local content is preserved and upload requires a concrete choice. |
| Recovery setup and failed recovery | Approved. The key-loss consequence and distinction between key and backup are now explicit. |
| App lock and forgotten PIN | Approved as an interaction design. Recovery-key unlock and retained data resolve the reset ambiguity. This is not a cryptographic implementation review. |
| Agent access | Approved. Disclosure precedes Allow Read Access and covers scope, provider exposure, and limits of revocation. |

Two literal copy corrections are required when consolidating the proposal; neither requires redesign or another independent review:

- A canceled pairing must not say its code expired. Use “Pairing was canceled.” with “Get New Code” when retrying requires a new request. Preserve “This pairing code has expired.” for actual expiry.
- Carry the earlier platform-specific local failure copy into the final specification: “Couldn’t save changes on this Mac.” The existing revision-1 “Couldn’t save changes.” should not override this distinction from sync failure.

Treat Revision 2 as authoritative where it replaces revision-1 terminology or behavior, including Recovery Key and the conflict action labels. Prefer consolidating these overrides before implementation so obsolete copy is not accidentally used.

All reviewed feature areas may proceed to implementation once those copy edits are applied. The actual-UI inspection requirement remains, including keyboard/VoiceOver access to the conflict version selector and errors, full-content export during failed persistence, and hiding drafts on lock without losing them. No UI was implemented or inspected during this review.
