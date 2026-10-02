# Adaptive entry conflict review

## Reason

Ordinary EntryConflictReview predates the adaptive recovery sheets. It uses a fixed17pt preview, unscrollable metadata, a fixed horizontal action row and an unowned resolve Task. The user must be able to compare both complete versions, including remote-only images, and deliberately keep both or one without inaccessible actions or content loss.

## Proposed layout and copy

Reuse the existing DeletionSheet container with title “Review Changes”, native Cancel in the iOS navigation bar and Mac footer, and scrollable content. This is an internal reuse; no deletion wording appears. Retain its accessibility-size full title and platform sizing. Use the existing segmented “This Device” / “Other Device” picker at ordinary sizes. At accessibility sizes use a native menu picker with the currently selected version as its visible label and accessibility label “Version”. Do not squeeze the two labels into a segmented row.

Show selected version title and modification date, with title wrapping. The read-only native editor keeps its own vertical scrolling, minimum220pt height, and semantic body text size (@ScaledMetric17). Preserve document/image metadata and separately owned image loading. Show “Keep Both saves the versions as separate entries.” wrapping below the preview. Keep Both remains the primary action, followed vertically by Keep One Version. Its menu retains “Keep Version from This Device…” and “Keep Version from Other Device…”. Single-version confirmation retains “Keep this version?” / “Keep Version” and “The original versions will remain in Version History.” Cancel remains available via the native confirmation.

Do not add persistent options or new controls to the main editor. This change applies to ordinary editable entry/template conflicts only; existing deletion, journal metadata and unsupported-version routes remain separate.

## State and ownership

Own the resolution Task in view state. While it runs, disable version/resolve/Cancel actions and interactive dismissal; show “Saving Changes…” only during the operation. Use existing store.resolve captured conflict precondition. Capture the store and selected resolution; after every await check cancellation, lock, replacement and captured store before updating model selection, showing an error or dismissing. An operation already committed in the store is not falsely described as cancelled or rolled back. On failure remain in review with inline localized actionable error; retain all choices for retry. No success toast.

Cancel, disappearance, lock and replacement cancel pending owned work and clear preview bytes. Existing parent conflict routing conceals content while locked. Resolve errors must remain on this sheet rather than depend on an alert hidden behind it. Changing versions continues to reset preview scroll to the selected version and cancels/prunes the previous image load. Copy/document and OS accessibility settings are preserved.

## Verification

Actual iOS UI fixture: real encrypted store with one local text-only version and a remote version referencing its own blue image; open review, switch versions, Cancel, reopen, Keep Both, relaunch and verify exact local/remote documents plus image bytes and no unresolved conflicts. Capture normal and largest dark versions/actions; inspect image presence independently. Keep One confirmation and cancel should be reachable without mutating data. Required source checks and native editing tests remain separate. No claim of real network conflict arrival from a seeded store, no VoiceOver claim from labels, no AppKit interactive claim from simulator evidence.

## Review revision: committed and stale states

The preview has a bounded300pt height (minimum220pt on constrained Mac sizing); outer content and actions scroll independently outside it. This keeps comparison usable without giving the editor unbounded height inside the sheet. Accessibility picker label wraps fully.

Bind Keep One confirmation to a captured ConflictVersion plus choice. If the observed conflict changes, dismiss that confirmation, return selection to This Device and show “These changes were updated. Review both versions again.” The store still verifies exact local/remote payloads before committing. If the conflict disappears, the existing parent route displays its completed “These changes have been resolved.” sheet; the entry view also has a nonempty fallback.

Mark resolution committed immediately after store.resolve returns. If the subsequent model refresh fails, show “Changes saved. The entry couldn’t be reloaded.”, a Try Again action that only refreshes the model, and Done through the existing completed container. Hide version/resolve controls in that committed recovery state; never call resolve again on retry. On successful refresh update selectedID/draft from the refreshed item set without another asynchronous flush, remember selection, then dismiss. Every post-await publication checks the same captured store, lock/replacement and cancellation. Cancel before commit or view disappearance stops owned work; committed storage is not rolled back. The previous generic retry wording applies only to precommit failures.

## Revision: where each version is (2026-10-01)

Red-team finding SYNC-6: when the other device moved the entry to another journal, to Recently Deleted or to the archive, or changed its date, both versions looked alike apart from their text. Keep Both then quietly left this device's version where it was and put the other device's copy where that device had it, and Keep Version from Other Device moved the entry without saying so.

- Under the selected version's modification date, one muted line says where that version is, only when the two versions differ in journal, Recently Deleted, archive or entry date: “In Home”, “In Recently Deleted”, “Archived in Home”, “Dated 1 Oct 2026”, or a place with its date (“In Home, dated 1 Oct 2026”). Templates read “In Templates”. Nothing is added when both versions are in the same place on the same day, which is the usual case. Like the title and date above it, the line belongs to the selected version.
- Every choice keeps a version where it is, so the line is also where that version will be kept. The Keep Both note says so: “Keep Both saves the versions as separate entries.” is followed by “Each version stays where it is.”, “Each version keeps its date.” or “Each version keeps its place and date.”
- Keeping the other device's version starts its confirmation with what happens to the entry here: “The entry will move to Recently Deleted.”, “The entry will move to Home.”, “The entry will be archived in Home.” or “The entry’s date will change to 1 Oct 2026.”, then the existing “The original versions will remain in Version History.” Keeping this device's version leaves the entry as it is, so its confirmation is unchanged.
- The resolution behavior and flow are unchanged; only text is added. The line is plain secondary text, read in order by VoiceOver, and wraps at every text size.

Review: independent design review of the proposal asked for an active confirmation (“will move to”, only when keeping the other device's version changes something) and one date style; both were adopted. Its suggestions to label the line “Journal: Home” and to show both versions' lines at once were not adopted: the requested copy is “In Home”, and the sheet shows one version at a time. A unit test checks the lines against a real store's Keep Both result; EntryConflictUITests checks the line in the iPhone review.
