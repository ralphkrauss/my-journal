# Agent access — design revision 1

Extends the approved screens.md Agent Access flow. Implement only after independent review.

## Scope and connection

First connector runs on macOS. A small bundled `journal-agent` command speaks MCP over standard input/output to an agent on the same Mac, and relays requests to the running Journal app over an authenticated loopback connection. It never opens the encrypted vault itself. The app checks each request against a locally stored grant and current lock state. No public plaintext endpoint; no master key is given to an agent. Grants are device-local, excluded from backups and sync. Closing/locking Journal stops reads. On iOS show a concise explanation in Privacy: “Connect an agent from Journal on your Mac.” Mobile remains usable for the same synced journals; a background mobile MCP server is outside platform lifecycle support.

The bridge provides discovery, journal listing, date/text search with bounded pages, and reading an entry’s current text/document. Initial scope excludes images, deleted entries, templates, history, and conflicts. It returns current live entries only, with data marked untrusted. The connection guide explicitly lists these capabilities and exclusions so agents do not infer access. Read-only grants apply to chosen journal IDs; newly created journals are not included. Renaming a journal preserves the grant; deleting a journal removes its entries from query/read results. Revocation is immediate for new requests and checked again before returning suspended reads.

## Settings > Agent Access (macOS)

Update: Agent Access is now its own Settings tab ([owner decisions](owner-decisions-2026-09-25.md) §9), and the copy names the app “My Journal”. This revision originally placed it in Settings > Privacy as a section beneath App Lock/Backup, as described below.

Section beneath App Lock/Backup, with rows for existing grant names and chosen journal names. Empty: “No agents have access.” Supporting copy: “Choose which journals an agent can read while Journal is open and unlocked.” Button “Add Access…”, disabled with no journals and explanation “Create a journal before adding access.” No global enable switch; an empty grant list means off.

Selecting a row opens a detail sheet showing name, journals, status “Read Only”, and “Copy Connection Instructions”. Instructions include the absolute bundled command path and a private connection-file path, never a recovery key or raw token. A selectable text preview explains installation in an MCP-capable agent. “Revoke Access” is destructive and immediate; detail closes. Errors retain the grant and show “Couldn’t revoke access. Try again.” Only claim revocation after durable local state changes. Already delivered text cannot be retracted.

## Add Access sheet

Title “Add Agent Access”. Name field, then “Journals” with native checkboxes/toggles, none selected. Journal names wrap. Cancel and “Continue” (disabled until trimmed name and at least one journal). Confirmation replaces the form content: “[name] can read entries in the selected journals while Journal is open and unlocked. A cloud agent may send this content to its provider. Revoking access stops future reads but cannot retract content already read.” List selected journal names. “Back”, “Cancel”, “Allow Read Access” as primary. Disable controls during the short durable save; cancellation/lock before commit creates no grant. Success shows the same detail sheet and connection instructions. Failure stays on confirmation with error and retry.

## Connection instructions

Plain text preview plus “Copy Connection Instructions”. Explain “Keep this connection file private. Anyone who can use it on this Mac can read the selected journals while Journal is unlocked.” Instructions include the agent’s MCP JSON configuration with command/args, the accessible journal names, read-only capabilities, and that entry text is data rather than instructions. No external account setup or automatic agent configuration. Missing packaged command in development shows a real build path if available; otherwise “Build the agent connector before copying instructions.” No broken path is silently copied.

## Activity

“Recent Activity” list below grants: time, grant name, and action (“Listed Journals”, “Searched Entries”, “Read Entry”), with no title/text/search query or token. Keep the newest 100 events locally. Empty “No recent activity.” No per-keystroke updates. Read attempts while locked/revoked are denied without revealing any journal names or content. Activity is private local metadata and disappears from the UI when locked.

## Accessibility and lifecycle

Use native Form, system colors/fonts, scrollable sheets and selectable instructions. Keyboard focus begins at Name, returns to invalid input. VoiceOver labels include journal names and selection state. Error text remains visible adjacent to actions. Lock dismisses sheets, removes displayed scopes/activity, and cancels unfinished creation; unlock reloads durable grants. Controls don’t depend on color. Dark mode, large text, keyboard and actual connector reads must be verified after implementation.

## Reviewed implementation clarifications

Closing the last journal window stops reads, even if macOS keeps the app running. Screen lock also stops reads. Only the latest saved local version is accessible; entries with unresolved conflicts are excluded completely until resolved. Final consent revalidates selected journal IDs. Confirmation actions stack vertically at small widths. Search returns excerpts up to1000 characters with a truncation flag; read_entry returns full saved text. The local bridge encrypts requests/replies using a fresh per-launch discovery key, in addition to grant authorization.
