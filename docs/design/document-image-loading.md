# Load images for the document being viewed

## Problem and intent

AppModel.refresh currently decrypts every attachment referenced by every current record and retains all of those bytes in imageData. Merely opening or syncing a large vault can therefore allocate the vault's entire image collection. This conflicts with the lightweight requirement. Ordinary entry-conflict previews also use this global cache, which does not necessarily include attachments referenced only by the remote version.

Preserve the current native editor, document format and permanent image references. Load image bytes for the selected draft and separately for each visible conflict/history preview. Keep no vault-wide image cache. This bounds retained source bytes to the documents actually being viewed; a single very large document can still consume substantial memory and is not solved by this change.

## Behavior and ownership

- Changing the selected draft immediately releases images no longer referenced by it and cancels its previous load. Start a new owned asynchronous load for missing attachment IDs. Plain text editing must remain available while bytes load. Typing that does not change attachment references must not restart loading.
- Use a captured store identity, selected entry identity and load generation. Cancellation, selecting another entry, lock or vault replacement prevents old completions from publishing bytes. Lock releases rendered/cache image state; unlock/reopen reloads only the selected document. A sync refresh retries missing images for the current document after downloads complete.
- Newly inserted image bytes remain available immediately to the inserted block. Export reads all required bytes from the store regardless of the viewing cache. Saving, locking, switching entries and missing files must never delete an attachment reference or alter document contents.
- Ordinary entry-conflict previews load the actual selected local/remote document's attachments independently, including remote-only images. Switch-version, dismissal, lock and vault replacement cancel/clear that preview's load. Existing history and deletion-conflict previews already have per-preview loaders; audit their lifetimes and preserve that ownership.

## Presentation and copy

No new toolbar, setting, dialog or permanent indicator. While an image slot is loading, its native attachment placeholder reads “Loading Image…”, retaining the block's description/reference. Once reading fails or the attachment remains absent, use the existing “Image unavailable” treatment. Loaded images appear in place. Do not replace the whole editor with a loading screen or interrupt typing. The description editor uses its existing unavailable thumbnail treatment after completion, with a small native progress indicator during an active load if a thumbnail slot is visible.

Late image arrival must not reset keyboard focus, selection, marked composition, scroll position or undo history. The native editor's update logic must distinguish image-key/loading-state changes rather than only dictionary count. Data-preserving attachment metadata stays embedded even in placeholders. Native accessibility must expose loading/unavailable descriptions without repeated announcements for background work; use semantic text and OS appearance/type.

## Verification

First reproduce eager loading with a model fixture containing images in unselected documents. Verify refresh without a selected document retains none, selection loads exactly its references, switching/clearing drops prior bytes, stale completion after switch/lock is discarded, and absent images recover after sync refresh. Use real isolated stores and only deterministic lifecycle coordination, not timed memory thresholds.

Verify an ordinary conflict's remote-only attachment is displayed when that version is chosen. Recheck real native image editing/description and undo/selection behavior as images arrive, including normal/largest type screenshots and independent actual UI review. Measure populated native refresh/search separately; this fix is a prerequisite, not evidence that the whole client meets its performance target.
