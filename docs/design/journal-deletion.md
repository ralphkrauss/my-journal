# Delete and restore journals — proposal

Pending independent review. Extends the previously approved journal tombstone behavior in screens.md. Do not implement until reviewed.

## Settings and deletion

Settings > Journals keeps its familiar list of journals, names, and default templates. Each live journal section gains a destructive “Delete Journal…” button. A native confirmation captures the journal ID and says “Delete ‘[name]’?” with “[count] entries will move to Recently Deleted.” Cancel is the default; Delete Journal is destructive. If empty, use “You can restore this journal in Recently Deleted.” Count only live entries currently in this journal. Journal deletion remains available for the last journal; the empty journal selector offers New Journal rather than silently creating a replacement.

Before committing, save the current draft. A failed save leaves the captured journal and all entries unchanged, shows the existing actionable save error, and offers Export Entry through the established lossless exporter. During commit disable dismissal and mutation; lock hides content immediately and awaits/reconciles committed work before any retained-draft save. Reject unresolved conflicts in the journal or affected entries with “Review changes before deleting this journal.” Cancellation before commit preserves all data. Failure after commit must explicitly distinguish display refresh from deletion failure.

## Recently Deleted

Keep one familiar Recently Deleted destination. Show separate native sections “Journals” and “Entries,” omitting empty sections. Deleted journals retain names and show their count of entries deleted with them. Selecting a journal shows its name, count, and “Restore Journal”; no editable rich-text editor for a journal record. Selecting an entry uses the existing read-only preview and Restore action. Entries remain individually discoverable, including those deleted with a journal. No fixed-height truncation, color-only states, or hidden swipe-only actions.

Restore Journal restores its tombstone and entries still assigned to it that were deleted with it. Entries deleted separately stay deleted. Restore Entry from a deleted journal uses a native confirmation: “Restore ‘[journal]’ and this entry?” with “Other deleted entries will stay in Recently Deleted.” Action “Restore Journal and Entry.” Do not resurrect other entries as a side effect. Reject restoration if the referenced journal is missing or unsupported, preserve the entry, and explain “This journal is unavailable. Try syncing again.” Conflict checks apply to every record modified. Restoration preserves identity/history/attachments and navigates to the restored journal, selecting the restored entry when applicable.

## Sync and data retention

Use one local transaction per delete or restore, preserving immutable pending retry bytes. Sync may deliver related tombstones across pages; a deleted parent journal must hide its entries from normal writing views even if their tombstones have not arrived yet. Restoring must not turn a independently deleted entry into a live entry. Preserve unsupported entry documents byte-for-byte by changing supported record metadata only, or refuse without mutation if preservation cannot be guaranteed.

Permanent erasure is not offered in this increment: the current encrypted revision log and backups retain versions. A misleading Delete Permanently action would violate the privacy promise. Recently Deleted explains “Deleted items stay here until you restore them.” Document retention and the absence of automatic purging in the privacy guide; do not add a false 30-day expiration. Actual irreversible purge needs a separate protocol design covering offline devices, histories, attachments, archives and backups before implementation.

## Inspection and meaningful tests

Inspect actual native Mac offscreen and iOS simulator layouts, including empty, deleted journal, entry restoration confirmation, and large text. Interactive Mac/VoiceOver remains separately tracked while the desktop is locked. Use focused real-store tests for atomicity, conflicts, retry bytes, independent deletions, move-after-delete interleavings and replica page boundaries. One native lifecycle test should cover retained-draft reconciliation, last-journal deletion and restoration; reuse existing fixtures and avoid testing routine view composition.

## Review revisions — prerequisite decisions

This proposal remains gated until these revisions are approved and the sync restoration semantics are settled.

- A deletion plan captures the journal identity/name plus the complete live-entry ID set. The atomic mutation rechecks that set and refuses with “This journal has changed. Review the entries before deleting it.” if membership differs. Refresh the count and require a fresh explicit confirmation; never automatically retry deletion with an expanded set.
- Conflict blockers offer Review Changes in the active sheet. Route to the first affected conflicted record; retain the pending action but require fresh confirmation after review. Journal conflicts need a prerequisite native metadata review: This Device / Other Device shows Name, Default Template (resolved name or “Unavailable Template”), and status (“In Recently Deleted” or “In Journals”). Use Keep Version from This Device / Other Device with the existing history-preservation confirmation. Do not offer Keep Both for journal metadata: copying a parent cannot silently duplicate or reassign its entries. Entry conflicts reuse the existing full entry review, including Keep Both. After resolution re-evaluate the remaining conflicts. Unsupported conflicting content stays preserved and offers lossless export and “Update Journal to review these changes.” This prerequisite will get a concrete design and separate review before implementation.
- Unsupported parent uses “Update Journal to restore this entry.” Missing parent with a configured connection uses “This journal hasn’t arrived on this device.” with Try Syncing Again. Missing parent without a connection uses “The journal for this entry is unavailable. Your entry is still saved.” Offer the existing lossless Export Entry route. Do not invent an archive recovery action that promises to reconnect unrelated IDs.
- Partial sync restoration needs a protocol decision before implementation. The current boolean deletedWithJournal cannot identify separate deletion cycles or safely recognize child tombstones arriving after their parent was restored. Do not implement a UI that implies reliable whole-journal restoration until this case is represented and tested. Evaluate operation identity and atomic sync grouping without using wall-clock last-write-wins or silently reviving independent deletions.
