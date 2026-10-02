# Move Entry proposal review

Date: 2026-09-20. Independent review of `move-entry.md` against `AGENTS.md`, the approved journal-management design, and current RootView/SettingsView entry points. Proposal review only; no Move Entry implementation or actual UI inspected.

## Outcome

**Approved for implementation with the small clarifications below.** A native destination list with no default selection, Cancel/Move actions, an explicit empty state, and no extra confirmation is appropriate for this reversible action. Showing the destination journal and retaining the moved entry selected provides an understandable result. Directly opening the Journals tab from Manage Journals fixes an existing navigation mismatch without changing ordinary Settings behavior.

The proposed save-before-move boundary, mutation freeze, live-destination validation, conflict rejection, post-commit success handling, and lock semantics address the material preservation risks. Unsupported/deleted/template exclusions keep the action within its intended scope. Journal deletion and image-description editing are correctly outside this particular review.

## Clarifications to carry into implementation

1. **Capture the intended entry identity when opening the sheet.** A shared model or another window could change selection while the picker is open. The final action must move the entry for which the user opened Move Entry, or close the picker if that entry is no longer current; it must never silently move a newly selected entry. Keep the captured identity through flush and commit.
2. **Keep sync revision protection while scheduling the move for sync.** “Retaining sync state” must mean retaining remote revision/conflict history, not leaving a formerly synchronized entry marked clean. The changed journal membership needs the normal pending-sync behavior, with no destructive overwrite of a newly arrived conflicting version.
3. **Finish the post-commit error wording.** If the move committed but refresh fails, use a message such as “The entry was moved, but couldn’t be displayed. Reopen Journal to try again.” Close the move flow and never offer another Move submission as recovery from that display failure. This directly implements the proposal's required distinction.
4. **Make selected destination accessible without relying on the checkmark alone.** Native selected accessibility state/value should identify the selected row. Preserve keyboard focus when a destination disappears; announce the inline error and clear the unavailable selection so Move remains disabled until a valid choice is made. Long or duplicate journal names must remain distinguishable; the selected state cannot depend only on color.

These details do not require another proposal-review round unless the preservation/navigation behavior changes substantially.

## Copy and native interaction notes

The proposed titles and action/error labels are concise and appropriate. Keep the empty-state instruction short; a direct Manage Journals… action could reduce navigation, but is optional for this scope. Cancel must remain a real no-op until committing; during commit its disabled/hidden state and the progress indicator should make clear why the sheet cannot yet dismiss. If progress is shown, “Moving Entry…” is sufficient.

The macOS footer and iOS navigation-toolbar placement are approved. Do not force the two platforms into an identical custom action bar. Verify a long journal name with enlarged text, keyboard-only destination selection, VoiceOver selected-state announcement, and the no-destination state.

## Required implementation verification

Check the last-second edit/image persistence, same entry identity and retained history, pending sync after move, reopened destination selection, removed destination, conflict arriving before commit, lock/cancel before and after the commit boundary, and a failed refresh after successful commit. The proposed actual iOS picker/reopen E2E is meaningful. Offscreen Mac renders may establish limited layout evidence while the desktop is locked, but do not replace interactive/assistive-technology inspection.

## Duplicate destination clarification — 2026-09-20

**Approved as a narrow fallback:** if other destination journals have indistinguishable names (case-insensitive), show those rows disabled with “Rename in Settings” and explain once, “Some journals have the same name. Rename them in Settings before moving this entry.” Keep uniquely named destinations selectable. Requiring distinct user-visible names is preferable here to exposing internal IDs or suggesting the user can reliably distinguish identical empty journals from timestamps alone.

Keep the explanation outside the disabled row so keyboard/VoiceOver users can discover why selection is unavailable. When every destination is ambiguous, show the existing rows and this explanation; do not say “No Other Journals.” A direct Manage Journals… action opening the Journals tab is a useful optional shortcut, provided it exits the picker without moving anything. Do not automatically rename journals, and do not prevent selecting an otherwise unique destination merely because it happens to have the same name as the source journal.

This is acceptable without a broader journal-identity redesign or another review round. Verify the disabled reason and available alternatives with keyboard/VoiceOver during implementation inspection.

## Related iOS Settings navigation refinement — 2026-09-20

Approved adding a native NavigationStack around iOS Settings with inline “Settings” title and Done in the confirmation toolbar. Preserve the four tabs, last-selected-tab behavior, Manage Journals routing, and unchanged Mac layout. This repairs the potentially unhosted Done toolbar without adding navigation complexity. See `move-entry-implementation-review.md` for source inspection findings and verification boundaries.

## Restore writing position — navigation repair approval — 2026-09-20

**Approved before implementation.** Remember the last selected live journal and live entry using UUIDs only in existing device-local configuration; restore them on relaunch/unlock when valid. Templates and Recently Deleted must not overwrite normal writing position. Move remembers the destination and unchanged entry identity. Invalid IDs after deletion/import/migration fall back to a live journal and the existing today's-entry behavior. No new controls or explanatory copy are needed.

Implementation boundaries: remember a navigation/move result only after its required save/commit succeeds; a failed-save pinned draft must not acquire a misleading destination. Validate that the remembered entry is live and belongs to the restored live journal. On unlock, retain an already-held draft (especially a failed-save draft) rather than replacing it with remembered storage state. Apply remembered selection only when no retained editing session should take precedence. A fallback should not silently create a new entry or discard unavailable content.

This is familiar navigation restoration and fixes the reported relaunch hiding of work, rather than adding product scope. Verify create/write in a nonfirst journal, move, restart, app lock/unlock with a retained draft, deleted/invalid IDs, and a visit to Templates/Recently Deleted followed by relaunch. Archive/server credential behavior and confidentiality remain unchanged; store no titles or entry text in navigation preferences.
