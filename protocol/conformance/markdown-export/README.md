# markdown-export

Export as Markdown ([markdown-export.md](../../markdown-export.md)): the rules that make folder and file names, file contents and dates the same on every client that writes the export, and a whole exported folder.

| File | Covers | Produced by |
| --- | --- | --- |
| `names-v1.json` | Safe names (every rule of the Names section, including Windows device names and the 60-character and 120-byte limits), numbering of names that compare equal, YAML strings, heading text, and dates and folder names for fixed offsets | The Swift export |
| `library-v1.json` | A library given as records, images, pins and journal order, and the exact folder the export writes for it | The Swift export, run on a real store |

## Names and escapes (`names-v1.json`)

- `safeNames`: `input` and `fallback` to `expected`, the complete safe-name function (NFC, line breaks and tabs to spaces, unsafe characters to `-`, trimming, cutting at 60 whole characters and 120 UTF-8 bytes, fallback, device names). A reader on another platform needs Unicode normalization and grapheme clusters; the cases use code points that are stable across Unicode versions.
- `uniqueNames`: names claimed in order within one folder (`claimed`) and the names they get (`expected`). Names that are the same ignoring Unicode form and with full case folding (`Straße`, `STRASSE`, `strasse`; `ﬀ`, `FF`; `ς`, `Σ`) get ` 2`, ` 3`; a name that is already taken by a numbered name is numbered again.
- `yamlStrings` and `headingText`: `input` to `expected` for double-quoted front matter strings and escaped `# <title>` headings.
- `dates`: an `instant` and the exporting device's fixed offset in minutes give the front matter `timestamp` (`Z` for offset zero), the entry file's `day` and the save dialog's `folderName`. Offsets are used instead of time zone names so every platform can reproduce them.

## A whole folder (`library-v1.json`)

The library is `records` (plaintext, with `id` and `kind`, as in `../records/records-v1.json`), `attachments` (base64 bytes), `ranks` and `pinned` (the library record's journal order and pins) and `timeZoneOffsetMinutes`. `expected` is what the export writes, with these members:

- `manifest`: the `format` and `version` of `.journal-export.json` (its `exported` date varies and isn't compared);
- `directories`, `files` (the Markdown files, with their exact `text`) and `binaryFiles` (`bytes` and `sha256`), sorted by path in UTF-8 byte order;
- `summary`: what the app tells the person about what was left out.

The library has journals with colliding and reserved names, an empty journal, entries without titles, with titles that need escapes, with equal dates and titles, a pinned and an archived entry, entries and journals in Recently Deleted and permanently deleted, an entry whose journal isn't in the library, an entry from a newer format, an entry that can't be read, templates with colliding and empty names, and images of every kind (written as they are, behind a shared reference definition, not an image, and not downloaded). A client passes when its export of the same library is the same tree, file for file.

An unresolved conflict's other version isn't part of this fixture; `summary.itemsWithOtherVersions` is `0`.
