# Performance measurements

These opt-in probes measure resource use with synthetic multi-year datasets. They are observations, not minimum hardware requirements or guarantees, and they are not part of CI. None of them uses real journals or an existing server. Each writes a report to a new path you choose and refuses to overwrite one.

## Heavy library: budgets and measurements

The owner's target is an app that stays fast for someone who has written every day for ten years. This section sets budgets for that use, the method that measures them, and the results before and after the performance work of 2026-09-27.

### Synthetic library

`JournalMeasure seed-heavy <new-directory>` builds the same library on every run from a fixed seed (`Sources/JournalMeasure/SyntheticLibrary.swift`). It holds only generated text and images:

- 20 journals and 4,000 entries over ten years, most between 300 and 1,500 words, and 50 entries of 20,000 to 50,000 words (36.8 MB of Markdown in all). Entries mix paragraphs, headings, lists, tasks, emphasis and links.
- 10 templates, 300 entries edited on two devices at once (their reviews leave 600 versions in history, 3 reviews stay open).
- 5,000 images: 4,950 small photos spread over the library (about 42 KB each) and one entry with 50 camera-sized photos (4032 × 3024 JPEG, about 5.7 MB each). The small photos stand in for the rest of a photo library: every measured cost that depends on the library's images depends on how many there are, not on their size, and camera-sized copies of all of them would need 15 GB of disk.
- The library is encrypted, as by default, and synchronized: its server change log (4,627 changes, encrypted payloads only) is kept beside it for the sync measurements.

### Method

- Store: `JournalMeasure heavy-store <fixture>` (release build) opens a copy of the library and measures decoding, search, reading one entry, and autosaving a normal and a long entry.
- Apps: `mise exec -- scripts/measure-app.sh <new-output-directory> mac|ios [fixture]` builds the app and a hosted test bundle in Release (`JournalMeasurements/App`) and drives the real views, model, editor and store on a copy of the library: unlocking, opening entries, typing at a steady 150 ms per key in the middle of an entry, typing a search, idle syncs, a writing session with the automatic sync running, scrolling the entry with 50 photos, and a new device catching up. A loopback server (`SyncFixtureServer`) answers the sync protocol; image downloads wait 4 ms plus their size at 25 MB/s. `JOURNAL_MEASURE_STEPS` chooses steps; `JOURNAL_SIMULATOR_ID` the simulator.
- Main-thread work per keystroke is the main thread's processor time from one key to the next, so it includes the editor, the model, autosave completion, every view update, layout and drawing the key caused. The report also has the wall-clock time the run loop was awake, which agrees closely.
- Memory is the physical footprint the system counts against the app (what jetsam limits on iOS).
- Mac: Mac mini, Apple M4 Pro, macOS 26.3. iOS: iPhone 17 and iPad Pro 11-inch simulators on the same Mac; a simulator runs on the Mac's processor and says little about a phone's speed, but shows where work happens and how it scales. The measurements ran while other builds used the same machine (load average 15 to 57), so they are upper bounds and vary by up to about a third between runs.

### Budgets and results

Before is the code at the start of this work; after is the same tree with the changes below. Times are p50 / p95 where there is a distribution.

| Budget | Mac before | Mac after | iPhone 17 sim after | iPad sim after |
| --- | --- | --- | --- | --- |
| Unlock or launch to a usable entry list ≤ 1 s (database file not cached / cached) | 12.6 s (10.6 s of it on the main thread) | 1.4–1.5 s / 0.47–0.54 s | 0.19–0.22 s / 0.07–0.43 s (shows the journals first) | 0.33 s / 0.64 s |
| Open a normal entry ≤ 100 ms | 10.4 s | 0.04–0.05 s | 0.03 s | 0.03 s |
| Open a 50,000-word entry ≤ 300 ms | 10.4 s | 0.06–0.08 s | 0.08–0.11 s | 0.06 s |
| Main-thread work per keystroke, normal entry, p95 ≤ 8 ms | 5.2 s / 5.3 s | 6.3–8.4 / 9.8–12.5 ms | 7.4 / 13.2 ms | 3.8 / 10.7 ms |
| Same, 50,000-word entry, p95 ≤ 16 ms | 5.2 s / 5.6 s | 10.9–15.6 / 14.5–24.5 ms | 13.1 / 29.8 ms | 12.5 / 30.4 ms |
| Same, with a search showing in the list | 580 / 617 ms | 7.1–7.3 / 12.0–13.2 ms | 7.8 / 11.8 ms | 8.1 / 11.9 ms |
| Search as you type ≤ 50 ms per keystroke (whole library) | over 30 s to settle (not measured to the end) | 23–47 / 79–92 ms, results 0.15 s after the last key | 13–15 / 21–49 ms | 17–27 / 47–68 ms |
| Idle sync: no decryption, no library-wide work | 5.2 s per pass, all on the main thread | 8–17 ms per pass, 0.5 ms on the main thread, 2 requests | 14 ms, 0.4 ms | |
| New device lists its entries quickly; images arrive progressively | 86 s before the first sync returned, after all 4,948 images | 8.0 s, after about 270 images; the rest follow in 5-second batches | | |
| Scrolling an entry with 50 photos stays under about 300 MB (iPhone) | +418 MB over the library (Mac); images shown after 276 s | +270 MB (Mac, 1,520-pixel pictures); shown after 2.5 s | +114 MB (432 MB peak with the whole library open) | +162 MB |
| Autosave and sync never do whole-library work per edit | an O(library) list rebuild and view update per keystroke and per save; a server revision about every 3 s while writing | none; a revision once writing pauses (4 for 80 keys in 4 bursts) | | |
| Any change the model publishes (all views update) | about 5 s | 27–36 ms | 12–19 ms | 11–13 ms |

Store alone (release, Mac):

| Measurement | Before | After |
| --- | --- | --- |
| First read of the whole library, file not cached / cached | 2.14 s / 1.39–1.47 s | 1.22–1.28 s / 0.35–0.39 s |
| Reading it again while unlocked | 1.39–1.47 s | 33–46 ms |
| Search over all entries (rare word) | 143–182 ms per query, on the main thread | 1.3–6.8 ms per query off the main thread; index built in 20–23 ms |
| Reading one 50,000-word entry | 7.5–7.9 ms | 0.2 ms |
| Autosave of a 50,000-word entry / a normal entry | 10 ms / 0.4 ms | 1.8–2.1 ms / 0.1–0.3 ms |
| Applying one keystroke to a 50,000-word entry's Markdown | 6.1–6.7 ms | 0.9–1.0 ms |

### What changed

- The store decodes records on all cores and keeps decoded records while the journals are unlocked, reusing one whenever its stored payload is unchanged (compared by digest). Locking clears it and stops it from filling until the next unlock; nothing decoded is written anywhere. Saving over a record this store wrote from an editable item doesn't decode it again.
- Search uses an in-memory index of each entry's text, folded the way `localizedStandardContains` compares, updated for changed entries only and searched on all cores off the main thread. The list keeps its results until a newer search's arrive. The index is cleared on lock and never written to disk.
- The lists views show are computed once per change of what they depend on, and a save that only changes an entry's writing updates them in place. The list of entries and each of its rows are rebuilt only when what they show changed, so other changes (a sync, a save, a search result) no longer rebuild thousands of rows.
- Typing and autosave no longer update every view: the open entry's writing changes quietly, and the list shows the saved text once writing pauses for 0.4 s. A query updates the list when its results arrive.
- The editor reads only the paragraph a keystroke changed when nothing else in the text changed (falling back to reading the whole text otherwise), Markdown is verified only around the blocks an edit wrote, and task checkboxes are reused instead of recreated for every key.
- Sync sends writing once it pauses for 2 s (and at once when leaving an entry, locking, going to the background or quitting, the last bounded to 3 s), as one revision of its latest content. A change that may already have reached the server keeps its content, so repeating it is the same request. Local saving stays immediate.
- A synchronization downloads images for at most 5 s, the open entry's first, and the next one continues without waiting; records never wait for images. Large pushes and sync pages get the long transfer timeout. Images nothing uses anymore aren't uploaded.
- Images of the open entry are kept at the largest size an editor shows them (2,560 pixels) instead of as camera originals, read four at a time and shown in batches.
- Archive export and restore check images on several cores outside the store, and restore verifies the copied files once instead of hashing the source first.
- The server keeps each operation's receipt as a reference to its change instead of a second copy of the payload.

### Still open

- The database file itself: when it isn't cached, reading 57 MB of encrypted payloads takes about 0.9 s on this machine before any decoding, which keeps a cold unlock above 1 s. Compressing record payloads before encrypting them would roughly quarter that, but changes the stored and synchronized format (an owner decision; other clients would need to follow).
- Keystrokes in 50,000-word entries on the iOS simulators, and the p95 of normal entries: most of what remains is TextKit layout and drawing and SwiftUI's own work after each key. Decoding pictures only while they are on screen would also bring the photo entry's memory down further.
- Search keystrokes still update the whole window once per results change (about 30 ms on the Mac with a 1,800-entry journal showing). The Observation framework would limit that to the views that show results; see below.
- Tables: each keystroke in an entry with tables still decodes every table's block to keep its grid in place.
- Physical iPhones and iPads, Intel Macs and the oldest supported OS versions are not measured.

### Raising the deployment target (SWF-11), for the owner's decision

The app supports macOS 13 and iOS 16, so its model is an `ObservableObject`: any published change updates every view that observes the model. The work above avoids that for typing, saving, syncing and search by publishing only when a view shows something new, and by isolating the entry list behind comparisons of what it shows. That keeps typing within about 1 ms of what Observation would give, because a keystroke now publishes nothing. What remains is every other published change: measured at 27–36 ms of main-thread work on the Mac and 11–19 ms on the simulators with this library. With macOS 14 and iOS 17, `@Observable` would update only the views that read the changed property, which we estimate at a few milliseconds for such changes, and would make the quiet updates and list isolation unnecessary, removing code that must be kept correct by hand. The Mac now requires macOS 14 (for its AppKit window), but iOS still supports iOS 16, so the shared model stays an `ObservableObject`.

## Server

```sh
mise exec -- python3 scripts/measure-server.py <local-image> artifacts/server-sizing.json
```

Build the image first, for example with `docker build -t journal-server:local -f server/Dockerfile .` The probe starts a disposable container and volume on a random loopback port, as the image's default non-root user, with a read-only root filesystem, dropped capabilities, 1 CPU and 256 MiB of memory. It writes 3,650 entry records with two 4 KiB revisions each and 100 attachments of 256 KiB (random bytes that model ciphertext), then pages through the full change log. It verifies every record, revision and attachment byte, samples resource use after loading and after 20 seconds, checks a clean shutdown without an out-of-memory kill, and removes the container and volume.

Results from 2026-09-21, native Arm64 image, Docker Desktop on an Apple silicon Mac:

| Measurement | Result |
| --- | --- |
| Record writes | 7,300 in 16.55 s, including fixture generation |
| Write latency | median 1.97 ms, p95 2.47 ms, max 64.88 ms |
| 256 KiB attachment upload | median 3.02 ms, p95 5.01 ms |
| Full catch-up | 7,300 verified revisions in 37 pages, 0.29 s |
| Page latency | median 5.76 ms, p95 8.97 ms |
| Container memory after writes / after catch-up | 82.6 / 80.7 MiB |
| Settled samples | 91.7–91.8 MiB, 0.50–0.65% CPU |
| Data directory size | about 150 MiB |

Memory figures are Docker's reported container usage, not a sampled peak. The data size includes revision history, operation receipts, SQLite files and attachments. The client runs outside the container's limits over local HTTP, so the numbers say nothing about network latency, slow disks or concurrent devices.

## Encrypted local store

```sh
mise exec -- python3 scripts/measure-client.py artifacts/client-sizing.json
```

This builds the release `JournalMeasure` tool, creates a disposable encrypted library with 3,650 entries of about 4.2 KiB and 100 attachments of 256 KiB, then opens it in three fresh processes. It measures opening the store, decrypting a full snapshot, and an in-memory body search, and verifies all text and attachment bytes. The temporary library and its key are removed afterwards.

Results from 2026-09-21, release build, Apple silicon Mac, macOS 26.3:

| Measurement | Result |
| --- | --- |
| Store open | 1.05–1.14 ms |
| First full decrypted snapshot | 128–133 ms |
| Second full decrypted snapshot | 124–127 ms |
| In-memory body search | 48–49 ms |
| Peak resident memory of the process | 131.3–131.4 MiB |
| Library size | 82.7 MiB |

An earlier run took about 1.3 s per snapshot because each date created and configured an `ISO8601DateFormatter`. The decoder now uses Foundation's `ISO8601FormatStyle` parsing, and a portable-record test protects time zone offsets, whole seconds, seven-digit fractions and rejection of malformed dates.

These figures cover the store only: not app launch, rendering or the app's own filtering and sorting.

## iOS app with a populated journal

```sh
mise exec -- scripts/measure-native.sh artifacts/native-measurement
```

It uses the same test simulator as the other simulator checks (set `JOURNAL_SIMULATOR_ID` to choose another). A separate measurement scheme builds the app in Release, creates a disposable encrypted journal with 3,650 entries of about 4.2 KiB, and unlocks it once. It then measures three fresh launches until the expected entry title is visible, and three body searches that find and open an older entry.

Results from 2026-09-21, iOS simulator on an Apple silicon Mac, Release build:

| Measurement | Three runs |
| --- | --- |
| Launch until the expected entry title is visible | 3.131, 3.138, 3.100 s |
| Typing a body query until the result is visible | 1.835, 1.821, 1.820 s |

The durations include XCTest launch overhead, automated typing and accessibility queries. They are not render or query latency, and a simulator says nothing about physical devices. The fixture has no attachments, conflicts or history.

## Not yet measured

Physical iPhones and iPads, Intel Macs, the oldest supported OS versions, slow storage and several devices syncing at once. The heavy-library measurements above cover many images, conflicts and history, but only in the synthetic shape described there.
