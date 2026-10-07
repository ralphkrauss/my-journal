# Retained-draft save failure recovery

Current RootView presents a save-error alert with Try Again, Export Entry… and OK. After OK, the persistent editor warning only offers export. The user is told to keep Journal open but has no explicit retry beside the retained draft. A native test injects a SQLite abort trigger in an isolated synthetic vault, preserves the original record, dismisses the alert, and expects a persistent retry that can save the draft after the trigger is removed.

## Proposed presentation and interaction

Use one shared save-failure notice on Mac and iOS. Show the existing exact warning “Changes haven’t been saved. Keep Journal open.” first, wrapping vertically, then native Try Again and Export Entry… buttons in a leading-aligned vertical stack. Keep the existing alert unchanged. The notice exists only while saving has failed. As of build 18 the alert shows once, when saving first fails, and again only for a retry the person asked for (Try Again in the alert or in the notice); later failures while typing leave the notice showing and say nothing more, and the notice is announced to VoiceOver once, when it appears. Closing the Mac window or quitting flushes without the alert, so only the modal “Couldn’t save changes on this Mac.” appears.

On iOS place this notice first in the scrollable entry header, before the title/recovery/conflict contents, with the existing padding. On transition into failure, scroll the header without animation to the notice. The modal alert remains the initial accessible announcement; after dismissal the warning and its recovery actions remain in the header. Do not steal focus from the alert or repeat announcements on every edit. On Mac replace the existing below-editor warning/export pair with this same component in the same location.

Try Again retries local persistence of the retained draft. Disable both notice actions during that owned operation and show a small native ProgressView labelled “Saving…” in the notice. Success removes the warning through the existing saveFailure state; failure leaves the draft and notice and retains the existing error-alert behavior. Export continues to use the existing export flow. Ordinary successful writing is unchanged.

Use system text and controls, the existing red warning plus explicit explanatory words (not color alone), intrinsic vertical wrapping, no animation, and keyboard/VoiceOver accessible button labels. On cancellation, view disappearance, lock or vault replacement cancel the owned task. Capture the session and validate it at task entry before invoking flush. Do not auto-retry indefinitely or replay any unrelated action.

## Verification

Native isolated SQLite failure/recovery: original document unchanged while write is rejected; dismiss error, retained draft visible, explicit retry reachable; remove rejection, retry saves exact draft, relaunch verifies it. Inspect normal and largest-dark screenshots independently, including header scrolling and keyboard. Run strict Apple and hygiene checks. This synthetic transactional rejection is not a claim of full-disk, real permission failure, crash-during-write, VoiceOver, or live Mac acceptance.

## Review revision

Add an optional scoped form of the existing flush operation, `flush(whileEditing: entryID)`. It captures the store/vault session at entry and validates cancellation, unlock/replacement state, same store/session and same selected draft identity before work, after mutationTask, after store.save, before error/success publication and before recursively saving newer edits. The existing unscoped `flush()` retains its lock/import cleanup semantics. The notice captures session and entry identity before creating its task and validates at task entry before invoking the scoped form. No stale operation may mutate a replacement draft or publish failure/success into a later session. A write already accepted by the old store may complete durably without publishing stale UI state.

Capture the immediate post-alert-dismissal warning before any test scrolling, then verify explicit reachable retry. Header scrolling is unanimated; no new focus transition competes with the alert.

## Largest-text presentation revision (awaiting review)

Actual largest-dark capture clips the full persistent warning mid-sentence within the half-height header when the keyboard is visible. Replace only the persistent warning with the concise status “Not Saved”, followed by Try Again and Export Entry…. The existing alert keeps its full explanation and instruction to keep Journal open. The persistent status plus primary retry must be visible without scrolling at the tested largest text/keyboard size. Export remains in the scrollable header if space is constrained. Retain the native red status and unchanged normal-state editor.

The acceptance helper must use the header's visible intersection below the navigation bar, and scroll in either direction; frame.minY alone incorrectly accepted a retry behind the toolbar. Capture immediate status and fully visible retry before invoking it. No production implementation of this revision until independent approval.

## Alert copy refinement (awaiting review)

The largest native alert keeps the message region separate from its scrolling actions; after reaching OK, the final word “again.” remains outside the captured message viewport. Shorten the save-specific error on both platforms to “Couldn’t save changes. Keep Journal open.” The native alert title/actions remain unchanged. This preserves the local failure and keep-open guidance without repeating the device or the Try Again button. Capture the complete shorter message and targeted persistent Export Entry… action, using navigation-safe header scrolling before returning to retry.
