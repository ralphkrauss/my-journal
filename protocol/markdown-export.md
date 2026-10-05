# Markdown export, format version 1

Export as Markdown (Settings ▸ Backup, or File ▸ Export Journals as Markdown…) saves a folder of plain Markdown files that other apps can open. This page is the contract for that folder. Every client that offers the export writes it this way, and a future import reads it. The design and its reviews are in [client-only-mac-lists-markdown-2026-10-05.md](../docs/design/client-only-mac-lists-markdown-2026-10-05.md), section 3.

The export is one way: it isn't a backup. Use the [archive](archive.md) to keep a copy you can restore. The files aren't encrypted. Photos keep their original metadata, which can include where they were taken, so check before you publish an export.

## Layout

```
Journal Markdown 2026-10-05/
├── .journal-export.json
├── Personal/
│   ├── 2026-10-05 Morning pages.md
│   ├── 2026-10-04 Untitled.md
│   └── attachments/
│       └── 6f1c0d7e-1f0b-4c56-9a43-2f6f0f1d2c3e.jpg
├── Work/
├── Other Entries/          (only when an entry's journal isn't in the library)
└── Templates/
    ├── Weekly review.md
    └── attachments/
```

- `.journal-export.json` is `{"exported": "<ISO 8601, UTC>", "format": "my-journal-markdown", "version": 1}`. A change to the layout, the names or the front matter keys raises `version`.
- There is one folder per journal that isn't deleted, in the order the app shows them.
- Each entry that isn't deleted is a file in its journal's folder. Each template is a file in `Templates`.
- Images are in the `attachments` folder beside the files that use them. An image used in two folders is written to both.
- Not exported:
  - entries and journals in Recently Deleted;
  - version history;
  - the other version of an unresolved conflict;
  - settings and agent access.

## Names

Folder and file names are built from journal names, entry titles and dates. A name is made safe in these steps:

1. Normalize to Unicode NFC.
2. Replace line breaks and tabs with a space.
3. Replace these characters with `-`: control characters, noncharacters, unassigned code points and surrogates (refused by APFS), the direction overrides U+202A–U+202E and U+2066–U+2069, the characters `/ \ : * ? " < > |` (unsafe on Windows, macOS or Linux) and `# ^ [ ]` (rejected by Obsidian).
4. Trim spaces, leading dots, and trailing dots and spaces.
5. Keep whole characters (grapheme clusters) up to 60 characters and 120 UTF-8 bytes, then trim again.
6. Use a fallback for a name that is now empty: `Untitled Journal`, `Untitled` or `Untitled Template`.
7. If the part before the first dot is a Windows device name (`CON`, `PRN`, `AUX`, `NUL`, `COM1`–`COM9`, `COM¹`–`COM³`, `LPT1`–`LPT9`, `LPT¹`–`LPT³`, in any letter case), insert `-` before that dot: `CON.txt` becomes `CON-.txt`, `nul` becomes `nul-`.

Entry files are named `YYYY-MM-DD <title>.md`, using the entry's date in the exporting device's time zone. The title is the entry's title, or, without one, its first line, as the app's list shows it. Template files are named `<title>.md`.

Names that are the same apart from letter case (compared with full case folding, as APFS does: `Straße` and `STRASSE` are the same) or Unicode form get ` 2`, ` 3`, and so on, in a fixed order, so exporting the same library twice gives the same names:

- journals by the app's order;
- entries by date, then id;
- templates by title, then id.

`Other Entries` and `Templates` join the same numbering as the journal folders.

## Files

UTF-8, LF line endings. Each file is YAML front matter, then the body.

| Key | Entries | Templates | Value |
| --- | --- | --- | --- |
| `title` | if the title isn't empty | if not empty | Double-quoted string. Never filled in from the first line. |
| `date` | always | — | The entry's date, ISO 8601 with the device's offset. |
| `modified` | always | always | The last change, ISO 8601 with the device's offset. |
| `journal` | when its journal is in the library | — | The journal's name, double-quoted. |
| `journal_id` | when its journal is in the library | — | The journal's id, lower case. |
| `id` | always | always | The entry's or template's id, lower case. |
| `archived: true` | when archived | — | |
| `pinned: true` | when pinned | — | |
| `kind: template` | — | always | |

Strings are double-quoted with these escapes: `\"`, `\\`, `\n`, `\r`, `\t`, and `\uXXXX` (or `\UXXXXXXXX` above U+FFFF) for other control characters, noncharacters, unassigned code points, U+0085, U+2028 and U+2029.

When there is a title, the body starts with `# <title>` and a blank line, so apps that hide front matter still show it. The heading is one line. These characters are backslash-escaped, so it reads as plain text:

- `\` `` ` `` `*` `_` `[` `]` `<` `>` `#` `|` `~`, always;
- `&`, before a letter or `#`;
- `!`, before `[`.

An import removes that heading when its text, after unescaping, equals `title`.

The rest of the body is the entry's Markdown exactly as the app stores it ([records.md](records.md)), except image references:

- **Format.** CommonMark with GitHub Flavored Markdown tables, task lists (`- [ ]`, `- [x]`) and strikethrough.
- **Image links.** `attachments/<id>` becomes `attachments/<id>.<ext>`. This applies wherever an image refers to it: block images, images inside text, and reference definitions. Text and code that merely quote such a path are left alone.
  - A reference definition that a text link also uses keeps `attachments/<id>`, so the link doesn't change, and the image is also written there without an extension.
  - Raw HTML `<img>` tags are left as written, and their images aren't exported.
- **Missing images.** An image that hasn't downloaded to the device isn't written, and its link stays `attachments/<id>`. The app counts it in the note it shows after saving.
- **Newer content.** An entry this version can show but not edit is exported from its stored Markdown, unchanged. A record this version can't read isn't exported and is counted.

## Images

| Stored as | Written as |
| --- | --- |
| JPEG, PNG, GIF, WebP | the original bytes: `.jpg`, `.png`, `.gif`, `.webp` |
| HEIC, HEIF, TIFF and other types the system can decode | JPEG at quality 0.9, or PNG when the image has transparency. Orientation and metadata are kept. |
| anything that can't be decoded | not written; counted |

## How other apps show it

These are checked against a sample export with every construct the app writes. The sample was made with `MarkdownWriter`, then rendered with GitHub's Markdown API (GitHub Flavored Markdown) on 2026-10-05.

| Construct | GitHub |
| --- | --- |
| Front matter | Shown as a table in the file view. The raw API renders it as text under a rule. |
| `# Title` heading, escaped | Correct |
| Bold, italic, strikethrough, code | Correct |
| `<!-- -->` between adjacent formats (`**bold**<!-- -->*italic*`) | Hidden; formats render correctly |
| `<u>…</u>` underline | Removed; the text shows without underline |
| Link destinations in angle brackets (`[text](<https://…>)`) | Correct |
| Backslash escapes (`\*`, `\[`, `\<`, `\|`) | Correct |
| Task lists, tables, fenced code, quotes, rules | Correct |
| Block and inline images (`![](<attachments/….png>)`) | Shown from the `attachments` folder |

Not yet checked:

- **Obsidian and VS Code.** Their previews couldn't be driven unattended.
- **Typora, iA Writer and Bear.** These aren't installed on the machines used for testing.

Known differences elsewhere:

- Editors that show the source (iA Writer, Bear, Obsidian's source mode) show `<!-- -->` and `<u>` as text.
- Hard line breaks are written as two trailing spaces, which editors that trim whitespace remove.
- Imported soft line breaks render as spaces on GitHub.
