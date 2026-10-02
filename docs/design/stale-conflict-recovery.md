# Stale conflict recovery

A native regression reproduces an open review whose remote version changes before Keep Both: storage correctly rejects the stale request, but the view displays a generic conflict error and keeps its old previews.

## Proposed interaction

Keep the existing Review Changes sheet, native version selector, preview and resolution controls. When storage rejects a stale resolution, discard the pending confirmation and refresh the current conflict without replaying the choice. Show “Updating Changes…” while refreshing. Disable resolution and version selection during the operation. On success reset to This Device and show “These changes were updated. Review both versions again.” above the selector, so it precedes the content and actions. The user must make a fresh choice. If already resolved, use the existing completed state; if the conflict changes type, use the existing router.

If refreshing fails, hide stale previews and resolution controls. Show “Changes couldn’t be updated.” followed by a native Try Again button. Retry only refreshes. Keep Cancel available when not busy. Ordinary save errors retain existing behavior. Normal successful resolution remains unchanged.

Use wrapping system text, semantic secondary color and existing scroll layout, supporting dark mode and the accessibility-size menu. No new persistent controls in the editor.

## Data and lifetime

Capture store and vault-session identity for each operation; check cancellation, lock/replacement, store and session after awaits before further work or publication. Preserve unsaved draft ownership: snapshot the previous selected stored item before refresh, and replace the draft from refreshed items only if it still equals that snapshot. Do not resolve using previews whose refresh failed. Clear pending confirmation when versions change. Stale rejection must leave both versions and history untouched. Shared refresh captures the starting replacement phase to permit legitimate post-import display refresh, while explicit forSession callers opt into cancellation checks; existing cleanup refreshes retain their cancellation behavior.

## Verification

Run the reproduced native case normally and at largest Dynamic Type in dark mode; inspect screenshots independently. Verify stale rejection retains the exact current conflict and does not change the pre-choice history, then explicit retry retains exact local/new remote documents and image bytes. Run Apple strict checks and hygiene. Document untested reload-failure and adversarial lifetime paths honestly.

## Review revision

After an explicit stale refresh finishes (success or failure), scroll without animation to a stable status target at the top of the sheet and move VoiceOver focus to the wrapping status message. This works with Reduce Motion without conditional animation. Do this only for the explicit refresh completion, not unrelated model changes. The status precedes the reset selector on success and Try Again on failure. Preserve a draft only against a nonnil prior stored item, unchanged selected identity, and post-await equality. Independent review of this revision is required before implementation.
