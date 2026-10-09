# Libraries written by earlier builds

Six libraries, written by the real code of two TestFlight builds, for tests that prove a newer version still opens them. Every name, text, image, password and token in them is synthetic. Nothing here comes from a real journal, device or server.

| Build | Commit | Why it is here |
| --- | --- | --- |
| 16 | `3989184037c2402a7b587346734c83762a199137` | Builds 16 to 18 wrote `configuration.json` as build 16 does. |
| 19 | `80a6e3b24c7c5188532d64fbd4adeea270fbd761` | The build released before 1.1. |

Per build there are three libraries, one flat JSON file each (the test target bundles flat resources, so there are no folders): `build16-password.json`, `build16-unencrypted.json`, `build16-unencrypted-synced.json`, and the same three for `build19`.

| Variant | Library |
| --- | --- |
| `password` | Format 2: a master password, encrypted journals, local only. The password has been typed correctly, so the configuration holds `"passwordChecked":true`. |
| `unencrypted` | Format 4: the old “Continue Without Encryption” (`AppModel.start(encrypted: false)`), local only. Records are not sealed; the library holds readable content. |
| `unencrypted-synced` | Format 4 with a saved server connection, a server position and an acknowledged history, as after real syncs against an unencrypted server. |

## How they were made

The throwaway test `FixtureBuilderTests` (not committed) was added to a detached `git worktree` of each commit, outside this repository's working tree, and run in that commit's Mac test host. It calls the real `AppModel` and `JournalStore` of that commit, and nothing from a later version. The Xcode project was generated with `scripts/generate-apple.sh` in each worktree. The command was the `scripts/check.sh mac` invocation of the commit, narrowed to the one test and given its own derived data folder:

```
xcodebuild -jobs 2 -project apps/apple/Journal.xcodeproj -scheme 'My Journal (Mac)' -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath <scratch>/dd<build> -clonedSourcePackagesDirPath <scratch>/SourcePackages \
  -onlyUsePackageVersionsFromResolvedFile CODE_SIGN_IDENTITY=- \
  JOURNAL_MAC_ENTITLEMENTS=Signing/JournalMac-Tests.entitlements \
  -only-testing:JournalMacTests/FixtureBuilderTests test
```

Build 16 has no `JournalMac-Tests.entitlements` (build 19 added it), so its run omits that setting, as its own `check.sh mac` did. The test host ran XCTest, so the vault key and the saved connection lived in the in-memory test keychain, never the login keychain. After the library was built, the test closed the store (an empty write-ahead log remained, so every committed write is in `journal.sqlite`) and copied out the storage folder, the exact bytes of `configuration.json` and the keychain items. A script that is not committed then wrote the JSON files, and read the unencrypted tables of `journal.sqlite` (`history`, `conflicts`, `records`, `outbox`) to fill the counts in `manifest`.

What each library holds, and how it was made:

- **Journals.** The library's first journal, renamed with `changeJournal(_:name:)`; a second made with `createJournal`; a third made with `createJournal`, given an entry, and deleted with `prepareJournalDeletion` and `deleteJournal` (it is in Recently Deleted). The journal order was changed with `moveJournal`: the second journal is listed first.
- **Entries.** Made with `newEntry` and `updateDraft`; the document is the Markdown the editor stores. One has a table, one a checklist (`- [x]`, `- [ ]`), one two images (24 by 16 and 40 by 20 pixel PNGs, different bytes, added with `AppModel.addImage`), one the marker text, one is plain, one is deleted with `deleteSelected` (Recently Deleted), one belongs to the deleted journal, one is the history entry, one holds the conflict.
- **Pins.** The checklist entry and the history entry, with `setPinned`.
- **Version History.** The history entry was edited four times, 20 minutes apart. The store only keeps a version of an ordinary change once ten minutes have passed, so the test set the store's own clock (`JournalStore.useClock`, the seam JournalCore's `VersionCheckpointTests` use), 6 hours before the run. So it holds four checkpoints (`history.checkpoint = 1`). Its other history rows come from a conflict resolved with `JournalStore.resolve` (and, in the synced library, from one more edit). The four checkpoints are therefore dated 5 to 6 hours before the files were made; no other time was set. The fifth checkpoint of the synced library, made by the later edit, has the real time.
- **Entry conflict.** One entry has a version from another device kept for review (`conflicts` table). In the two local libraries the version came from `JournalStore.recordConflict`, the call the sync engine makes when a push is refused, with the other version sealed by the store's own `encode`. In the synced library it came from a real refused push (see below).
- **Marker.** One entry body contains the library's `marker`, `FIXTURE-MARKER-<16 hex digits>`, different in each file.

### The synced libraries

There is no server in this repository that a test target can start, so the test ran the real `SyncEngine` (through `AppModel.syncNow`) against a small in-process stand-in that answers `/v1/status`, `/v1/recovery`, `/v1/sync/` and `/v1/attachments/` the way the protocol-1 server does (it is built on `FakeJournalServer`, the loopback server the app's tests use). It advertises only the `record-kinds` capability, so pins and journal order were sent as the library record. The steps:

1. Connect to the stand-in and sync. Every record, the library record and both images were pushed and acknowledged (revision 1; images marked uploaded), and the log was read back to cursor 16 (`settings.cursor`, `cursor-change`, `server-id`, `sent-change` and `server_versions` are written by the sync engine).
2. The stand-in was given a newer revision of two entries, as another device would push. This device edited both entries without knowing it, and synced. Both pushes were refused (409) and the engine kept the server's versions for review. One was then resolved with `JournalStore.resolve(.local)`; the other, the conflict entry, stays in review (`conflicts.revision = 2`, still waiting in `outbox`). A last sync followed.
3. The saved connection was replaced by one for `http://127.0.0.1:9` (nothing listens there) with a synthetic token. `commitConnection`, which a real join uses, is private, so the test repeated its steps: a new Keychain item named `<keyAccount>-connection-<uuid>`, `connectionKeyID` set to it and the configuration saved, then the previous item removed. The library therefore reads as a library that once synced with a server that is no longer reachable. The stand-in itself is not part of the fixture.

### What could not be produced

- **Build 16 has no former-Mac-server field.** `stoppedSyncingWithFormerMacServer` was added by build 19, and build 16 recorded its Mac server only in files beside the library (`local-server.json` and others, which `FormerMacServer` in build 19 looks for). Those files need the server process build 16 started, so none of the six libraries has them. The only configuration fields these builds write that matter here are `passwordChecked` (in the two `password` files), `recoveryConfirmed`, `connectionKeyID` and `lastJournalID`.
- **Checkpoint times** of the first four checkpoints are earlier than the creation time, as described above.
- **The sync history is two syncs against a stand-in**, not months of use against a real server.
- **The saved connection's address** was rewritten after the syncs, so the position is real but the server it names is not.
- **Unencrypted records are Base64.** In format 4 the store writes each record as Base64 text of its JSON, so the marker is not visible as plain text in `journal.sqlite`; images are stored as the exact PNG bytes. `manifest.markerNeedles` lists the marker and the three Base64 forms of it (one for each position within a Base64 group) that occur in the unencrypted files, so a test can look for readable text before and after encrypting. In the `password` files no form occurs.
- The `-shm` file was left out; it holds no data, and the empty `-wal` file was left out too.

## Schema

Each file is a JSON object. Every `files` value and `material` are Base64 of the exact bytes.

| Field | Meaning |
| --- | --- |
| `build` | `16` or `19`. |
| `commit` | The full commit hash of that build. |
| `variant` | `password`, `unencrypted` or `unencrypted-synced`. |
| `storageFolder` | The folder name the library lives in, beside `configuration.json` (`vault-<uuid>`). It is also `configuration.storageFolder`. |
| `configuration` | The exact text of `configuration.json` as the build wrote it. Write it as is; do not decode and encode it again. |
| `files` | Path under the storage folder to bytes: `journal.sqlite` and `attachments/<image id>`. Image files are sealed in the `password` files and are the plain PNG bytes in the others. |
| `keyID` | The Keychain account of the vault key (`configuration.keyID`). |
| `material` | The 32 byte vault key held under `keyID`. In format 4 libraries it is a random key that is stored but does not protect content. |
| `phrase` | The master password (`password` variant), otherwise `null`. |
| `connectionKeyID` | The Keychain account `configuration.connectionKeyID` names. |
| `connectionItem` | The saved connection as the Keychain item holds it (JSON text of address, device id and token), under `connectionKeyID`, for `unencrypted-synced`; otherwise `null` (the local libraries have no item). |
| `manifest` | What the library should hold, below. |

`manifest`:

| Field | Meaning |
| --- | --- |
| `recoveryFormatVersion` | `configuration.recovery.formatVersion`: 2 or 4. |
| `records` | Every journal and entry: `id`, `kind` (`journal` or `entry`), `journalID` (`null` for a journal), `title`, `deleted` (in Recently Deleted by itself), `pinned`, `inDeletedJournal` (its journal is deleted), `revision` (the stored server revision, 0 if it never synced), `historyRows` (all rows in `history`) and `historyCheckpoints` (rows kept by the checkpoint rule). Ids are lowercase here; the library's own JSON writes them in upper case. The library record (pins and order) is a further row of `records` with kind `library`, not listed. |
| `liveJournalOrder` | The ids of the journals in use, in the custom order the person chose. |
| `deletedJournalID` | The journal in Recently Deleted. |
| `pinnedEntryIDs` | Pinned entries. |
| `namedEntries` | Ids of the entries that hold something particular: `table`, `checklist`, `twoImages`, `history`, `marker`, `deletedEntry`, `entryInDeletedJournal`, `plain`. |
| `images` | `entryID`, `id`, `sha256` and `bytes` of the image as added, and `storedBytes`, the size of the file on disk. |
| `conflictCount`, `conflictedEntryID` | Entries with a version kept for review, and the one entry. |
| `syncCursor`, `syncedPositionCursor`, `syncedPositionRecordID` | The position in the server's log (`JournalStore.cursor()` and `syncedPosition()`): 0 and `null` for the local libraries. |
| `queuedChanges` | Rows in `outbox`: changes not yet sent. |
| `marker`, `markerEntryID`, `markerNeedles` | The marker text, the entry holding it, and the strings to search for. |

## Numbers

| Library | Journals in use / deleted | Entries (deleted) | Pinned | Images | History rows (checkpoints) of the history entry | Conflicts | Server position | Queued |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `password` (both builds) | 2 / 1 | 9 (1) | 2 | 2 | 6 (4) | 1 | none | 12 |
| `unencrypted` (both builds) | 2 / 1 | 9 (1) | 2 | 2 | 6 (4) | 1 | none | 12 |
| `unencrypted-synced` (both builds) | 2 / 1 | 9 (1) | 2 | 2 | 7 (5) | 1 | cursor 16 | 1 |

Ids and the marker differ in every file, so the six cannot be confused. The `title` of every record ends with the build and variant, such as `(b16 password)`.
