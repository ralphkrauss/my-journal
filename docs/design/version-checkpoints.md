# Version checkpoints

Version History only held versions kept for conflict review and recovery. Ordinary writing replaced the stored entry, so once the editor's undo history was gone, earlier writing couldn't be recovered, although the guide promised earlier versions (finding 4 of the 2026-09-29 full review). This record adds automatic, local checkpoints of ordinary changes. The Version History interface and its copy are unchanged; it lists these versions with the others.

## Rule

A checkpoint keeps the stored version that a change replaces. It applies to entries and templates, not journals (journal settings already keep a version when restored). With a 10-minute interval, a checkpoint is due when the change:

- starts an editing session: the item's stored version was saved on this device 10 minutes ago or more, or before the app last opened the journals, or was received from another device; or
- continues a session in which no version was kept for 10 minutes.

A due checkpoint is kept only if:

- no checkpoint of the item was kept in the last 10 minutes (this also holds across relaunches);
- the title or text changes; a change of date, journal, archive or deletion status keeps nothing, and the checkpoint stays due for the next change;
- the replaced version has a title, text or images; an untouched blank or new item has nothing worth keeping, and its first period starts with its first words.

So Version History has the version from before each editing session and one every 10 minutes while editing continues, never one per autosave. A version received from another device that replaces an unchanged version here follows the same rule, so a change made elsewhere can be undone here too. When a newer version replaces one this device can't fully read, or a deletion marker arrives, the existing rules apply instead.

Before other replacements, a version is already kept: conflict review keeps both versions, and restoring journal settings keeps the current settings. Restoring from Version History creates a new entry or template and replaces nothing.

The time since saving is kept only in memory. After a relaunch every item starts a new session, limited by the 10 minutes since its last checkpoint, which is stored.

## Retention

Each item keeps at most 50 checkpoints; when another is kept, the oldest checkpoint is removed. Checkpoints are marked in the database (`history.checkpoint`, migration `history-checkpoints`) so that only they are removed this way. Versions kept for conflict review or recovery are never removed by this limit. History imported from another library is kept as it is and isn't marked.

Delete Permanently, Keep Deletion and an incoming deletion marker remove an item's whole history, checkpoints included, as before.

## Images

Checkpoints refer to images like any other earlier version (`referencedAttachmentIDs`), so an image that only a checkpoint uses still counts as used for archives, archive validation, downloads and uploads. The app doesn't delete image files, so no image a checkpoint needs can disappear. Delete Permanently removes the versions, not the image files, as described in [permanent deletion](../../protocol/permanent-deletion.md).

## Sync and storage

Checkpoints are local: they aren't sent to the server or other devices, and the sync protocol is unchanged. Each device keeps checkpoints of the changes it saves and receives. Archives contain them, since they contain the whole database. The server's own revision log is not exposed as history.

Storage grows by at most 50 copies of each item's encrypted record; images aren't copied.

## Tests

`VersionCheckpointTests` uses real encrypted stores and an injected clock: editing after reopening keeps the earlier version; rapid autosaves keep nothing until 10 minutes pass, then one; a pause starts a new session; blank items and date-only changes keep nothing but don't use up the next checkpoint; the limit removes only the oldest checkpoint, never reviewed versions; a checkpoint's image stays referenced and it can be restored as a new entry; Delete Permanently removes checkpoints; and a change received from another device keeps the version it replaced.

## Decisions for the owner

- The interval (10 minutes) and the limit (50 per item, oldest first) are simple defaults. Thinning older checkpoints (for example one per day after a week) would keep a longer span in the same space.
- Checkpoints stay on the device that made them. Syncing them would need a protocol change and would expose more version metadata to the server.
