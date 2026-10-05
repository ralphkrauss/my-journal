# Mac app without a server, list indentation, Export as Markdown — 2026-10-05

Status: current. Revision 2 was approved with required changes by a second independent review (section 6); those changes are made below.

Process note: the first draft's server removal was partly implemented before its review, which the design gate doesn't allow. That code is being brought in line with this revision after its review, not before.

## Requests

The owner, after testing build 16:

- “Why is the app for mac also the server? … I just want it simple and the client should be the client, and the server should be the server. Not a mix of the two. Clean that up.”
- “Our lists don't have default indentation. By default (first level list) it's on the same indentation level as normal text. This is quite odd, because most editors have an indent for them. Change this.”
- “We should also export as markdown. We should follow the open format and make sure it's portable outside of the app.”

## 1. The Mac app is only a client

Today the Mac app bundles the .NET sync server (`Contents/Helpers/JournalServer.app`) and offers Use This Mac… in Settings ▸ Sync, with a setup sheet, Running and Stopped states, Start Server, Stop Server and Connection Details. All of it is removed. The Mac app becomes the same kind of client as the iPhone and iPad apps. The server is installed and run on its own, as the container or the standalone server ([self-hosting](../self-hosting/README.md)), on any computer, a Mac included.

### 1.1 Settings ▸ Sync (Mac, iPhone, iPad)

The Mac tab and the iPhone page show the same content, each in its platform's grouped form.

```
Not connected                                       Connected
┌ Server ─────────────────────────────────┐          ┌ Server ──────────────────────────────┐
│ Connect to a Server…                     │          │ https://journal.example.ts.net        │
└──────────────────────────────────────────┘          │ Sync Now                              │
 Your journals are saved on this device.               └───────────────────────────────────────┘
 How to Set Up a Server                                 (status footer, unchanged)
```

- Header **Server**.
- When not connected, the section has one button, **Connect to a Server…**. Its footer reads “Your journals are saved on this device.”, followed by the link **How to Set Up a Server**, which opens the sync guide (`docs/guide/sync.md` on GitHub) in the browser.
- When connected, the section shows the address (selectable) and Sync Now. The status footer, Stop Syncing and Conflicts are unchanged.
- Removed:
  - Use This Mac… and its “Use This Mac as Your Server” sheet;
  - the Running and Stopped states;
  - Start Server, Stop Server and Connection Details;
  - every message about the bundled server.

### 1.2 A Mac still connected to the removed server

A Mac library that used Use This Mac is connected to `http://127.0.0.1:46371`. Nothing will ever answer there again, so “will sync automatically” would be false.

When the library opens (at launch, or after unlocking with the password when the device key isn't available), and before the first sync starts, the app checks:

- the data folder has the old server's `local-server.json`;
- the data folder has no `local-server-retired` marker;
- no encryption change is unfinished.

If all three hold and the connection's address is exactly that address, the app runs **Stop Syncing** once, without telling the old address. Nothing answers there, and something else could. Either way it then writes the marker, so the check never runs again, not even after the person reconnects to the same address, as the recovery steps allow. Erase leaves the marker in place along with the old server's files. Stop Syncing already:

- keeps the library as it is, including changes not yet sent;
- forgets the connection;
- tries to give up the device's access, best effort.

Only when Stop Syncing actually ran (it does nothing while a library is being replaced) does the app record, in the library's configuration, that it did, so the Sync tab can explain it:

- The not-connected footer becomes: “My Journal no longer runs a server on this Mac, so this Mac stopped syncing. Your journals are saved on this Mac. To sync again, connect to a server.” It is followed by **Learn More**, which opens the guide's “If you used Use This Mac” section.
- The note goes away once the Mac connects to a server.
- Agent Access then shows its ordinary not-connected state (1.3). Erase shows its ordinary not-syncing footer and warning, which tell the person to export an archive first.

**The old server's files are kept.** `local-server.json`, `local-server-process.json`, `local-server.log` and the `local-server-data` folder stay where they are. That folder may hold the only copy of changes another device sent and this Mac never received.

- Erase Journals and Settings keeps leaving them alone, as it does today. While they exist, its footer adds: “A copy of your journals from the server this Mac used to run isn't removed.”
- The troubleshooting guide explains:
  - how to recover from them: start the standalone server or the container with that folder as its data directory, then connect;
  - how to remove them: delete those four items in Finder, after exporting an archive if the library matters. Deleting the app's whole container would also delete the library.

**Other devices that synced through the Mac** (for example an iPhone using a Tailscale Serve address) show the existing unreachable-server message. The sync and troubleshooting guides gain a section, “If you used Use This Mac”:

1. Set up a server elsewhere.
2. On the Mac, connect to it and upload this Mac's journals.
3. On each other device, choose Stop Syncing, then connect to the new server and join with its journals. Joining keeps unsent changes; nothing is overwritten.
4. Turn off the old Tailscale Serve rule on the Mac (`tailscale serve --https=443 off`, or `tailscale serve reset` if it was the only rule).
5. Connect agents again. Their access belonged to the old server.

### 1.3 Other places that mention the server on this Mac

| Place | Today | After |
| --- | --- | --- |
| Settings ▸ Agent Access, not connected | Mac: “To let agents read your journals, use this Mac as your server or connect to one.” · Set Up Sync… iOS: “…connect to a sync server.” · Set Up Sync… | Both: “To let agents read your journals, connect to a server.” · **Connect to a Server…**, which opens the connection sheet, as Connect Again… does. |
| Devices ▸ Add Device, connected over plain HTTP | Mac: “Other devices connect to this Mac using the HTTPS address from Connection Details.” | Both platforms: “Other devices can't connect to <host>. To add devices, connect this device to the server's HTTPS address.” Plain HTTP is only accepted for a server on this device (`127.0.0.1`, `localhost`), such as the container on this Mac. |
| Erase Journals and Settings | Unavailable while this Mac runs the server | That block and its message go away. The old server's files are still kept (1.2). |
| Turn On Encryption | Calls the built-in server “the server on this Mac” | Always names the server's host. |

Agent copy that calls a loopback server “this Mac” stays: someone may run the container on their Mac and connect to `http://127.0.0.1:…`.

### 1.4 What else changes

- The Mac app has no Apple-silicon-only part left, so it runs fully on Intel Macs. The Intel gate added for build 17 (`LocalServerHardware`) is removed.
- The download loses the .NET runtime, which was over 100 MB.
- Build and packaging:
  - Removed: the server packaging steps in `archive-mac.sh` and `package-mac.sh`, plus `embed-mac-server.sh`, `assemble-mac-server.sh`, the server's sandbox entitlements and its privacy manifest.
  - Removed from the server: the parent-process watchdog, which existed only for being embedded.
  - Third-party notices are split. The apps ship only their own; the server package and container carry the server's.
- Tests:
  - The Mac sandbox lane tests only the app.
  - The Mac's real-server recovery tests run in the `server-recovery` lane, renamed from local-server.
- The docs (distribution, guide, troubleshooting, architecture, App Store listing and review notes) drop Use This Mac. Self-hosting explains running the container on a Mac.

## 2. Lists start indented

Today a first-level list's marker (bullet, number or checkbox) sits on the body text's left edge, and its text starts one list column (1.5 × the text size) further in.

After the change, every list moves in by a fixed **list inset of 18 points**. The inset is the same as the quote indent (`BlockDecorations.quoteIndent`), so a first-level marker lines up with a quote's text and the page has one inset rather than two nearly equal ones.

- The first-level marker sits 18 points in from the edge of the body text.
- Its text starts one list column after the marker, as today.
- Each deeper level adds one list column, so a nested marker lines up with its parent's text.

```
Body text starts here.
   •  First item wraps onto a second line
      aligned with its text.
      ◦  Nested item
   1. Numbered
   ☐  Checklist item
 ▎ Quote text starts at the same inset as the markers above.
```

| Text size | Marker at | Text at (first level) | Nested marker at |
| --- | --- | --- | --- |
| Mac default (16 pt) | 18 | 18 + 24 = 42 | 42 |
| iPhone default (17 pt) | 18 | 18 + 26 = 44 | 44 |
| Largest accessibility size (53 pt) | 18 | 18 + 80 = 98 | 98 (deeper levels capped) |

For comparison, Word and Google Docs place a first-level bullet 0.25 in (18 pt) in and its text 0.5 in (36 pt) in.

The inset is fixed rather than scaled, so large text sizes don't lose more width.

- **Nesting at large sizes.** The 160-point allowance for drawing deeper levels is unchanged and comes on top of the inset, so Increase Indent allows the same depth as today at every size. At the largest size on an iPhone SE (320-point text width), level 1 text starts at 98 and level 2 at 178, leaving 142 points for text.
- **Content inside an item.** Paragraphs, code blocks and quotes that belong to a list item move in with the inset, so they stay aligned with the item's text. Images keep the full text width, as they do today at any nesting level: indenting them would change how pictures are sized, which is outside this change. A list inside a quote starts the inset after the quote's own indent.
- **What it applies to.** Bullets, numbers and checklists on iPhone, iPad and Mac. Quotes and code blocks are unchanged.
- **Storage.** Only presentation changes. The stored Markdown is unchanged, so other devices and older builds read the same entries.
- **Unchanged behaviour:**
  - wrapped lines align with the item's text;
  - numbers wider than the column keep their extra room;
  - checkbox hit targets, the caret, selection, Return, Backspace, Tab, Shift-Tab, and Increase and Decrease Indent move with the markers;
  - nothing changes for VoiceOver.

## 3. Export as Markdown

### 3.1 Where

| Place | Control |
| --- | --- |
| Settings ▸ Backup (iPhone, iPad, and the Mac's Backup tab) | A new section below Archive: header **Markdown**, the button **Export as Markdown…**, and a footer. |
| File menu (Mac, and iPad with a keyboard) | **Export Journals as Markdown…** after Export Archive…. “Journals” keeps it from reading as an export of the open entry. It is disabled while the library isn't ready or the app is locked, like Export Archive…. It opens a small sheet titled **Export as Markdown** in the journal window, with the same section and a Done button, as File ▸ Export Archive… opens its sheet today. |

Footer copy:

- encrypted library: “Saves your journals and their images as Markdown files that other apps can open. The files aren't encrypted. To keep a copy you can import later, use Export Archive.”
- not encrypted: “Saves your journals and their images as Markdown files that other apps can open. To keep a copy you can import later, use Export Archive.”

### 3.2 Flow

1. **Authentication.** When App Lock is on, Export as Markdown… first asks for Face ID, Touch ID or the device password, as the Passwords app does before exporting. The reason shown is “Export your journals as files that aren't encrypted.”, or “Export your journals as Markdown files.” for a library without encryption. Cancelling does nothing. When App Lock is off, there is no prompt.
2. **Preparing.** The app finishes the open edit and prepares the files in a `markdown-<UUID>` folder in its data folder. The folder is excluded from backups and, on iPhone and iPad, written with complete file protection; Erase and the launch cleanup remove it like archive copies. After 0.3 seconds a small spinner appears at the end of the row, labelled “Preparing Files…” for VoiceOver. The row keeps its size, as for Export Archive. Pressing the button again does nothing.
3. **Saving.** The system save dialog asks where to save a folder named `Journal Markdown 2026-10-05`, matching `Journal Archive 2026-10-05`. Cancel discards the prepared copy. Saving is quiet: there is no alert.
4. **Anything left out.** If something was left out, a secondary note appears under the button after saving, and VoiceOver announces it:
   - “2 images weren't included because they haven't downloaded yet. Export again after syncing.”
   - “1 image wasn't included because it couldn't be read.”
   - “1 entry wasn't included because it was made with a newer version of My Journal. Update My Journal, then export again.” (records this version can't read)
   - “1 entry has another version that wasn't included. Choose a version, then export again.” (unresolved conflicts: only the version shown is exported)

   The sentences that apply appear together. The note stays until the next export or until the pane closes.
5. **Errors.** Errors appear under the button in red and are announced to VoiceOver:
   - “Couldn't export your journals. Try again.”
   - “There isn't enough space to export your journals. Free up space, then try again.”
   - “Couldn't save the files. Try again, or choose another location.”
6. **Locking.** Locking the app cancels preparing, closes the save dialog and removes the prepared copy. Prepared copies left by a crash are removed at the next launch, as archive copies are.

Preparing before the dialog matches Export Archive and lets the dialog write a complete folder. Writing after the dialog would avoid a second copy on disk, but SwiftUI's file exporter needs the document up front. This is recorded as a known cost for very large photo libraries.

### 3.3 Format (portable; documented in `protocol/markdown-export.md`)

```
Journal Markdown 2026-10-05/
├── Personal/
│   ├── 2026-10-05 Morning pages.md
│   ├── 2026-10-04 Untitled.md
│   └── attachments/
│       └── 6f1c0d7e-….jpg
├── Work/
│   └── …
└── Templates/
    ├── Weekly review.md
    └── attachments/
```

**Names (folders and files)**

1. Normalize to NFC.
2. Replace control characters, noncharacters and unassigned code points (which APFS refuses), direction overrides (which can disguise a name), `/ \ : * ? " < > |` (unsafe on Windows, macOS and Linux) and `# ^ [ ]` (which Obsidian rejects in note names) with `-`.
3. Trim spaces, and remove leading dots and trailing dots.
4. Cut at a grapheme boundary so the name is at most 60 characters and at most 120 UTF-8 bytes, leaving room for the date, a duplicate number and `.md` within 255 bytes. Then trim again.
5. If the part before the first dot is a Windows reserved name (`CON`, `PRN`, `AUX`, `NUL`, `COM1`–`COM9`, `COM¹`–`COM³`, `LPT1`–`LPT9`, `LPT¹`–`LPT³`, in any letter case), insert `-` before that dot, so `CON.txt` becomes `CON-.txt`.
6. Duplicates that differ only in letter case (with full case folding, as APFS compares names: “Straße” and “STRASSE”) or Unicode form get “ 2”, “ 3”, … in a fixed order: journals by their order in the app, entries by date and then id, templates by title and then id. Exporting twice gives the same names.

These caps keep a journal path under Windows' 260-character limit when unzipped into a typical user folder.

**Folders**
- One folder for each journal that isn't deleted. An empty name becomes `Untitled Journal`.
- Templates go in `Templates`. If a journal already uses that name, the templates folder becomes `Templates 2`.

**Files**
- An entry that isn't deleted becomes `YYYY-MM-DD Title.md`, using the entry's date in the device's time zone.
  - Without a title, the file name uses the entry's first line, as the list does, or `Untitled` when there's no text. The app's list shows “New Entry” in that case; the file uses “Untitled” on purpose, because “New Entry” would be misleading in a folder.
- A template becomes `Title.md`, or `Untitled Template.md` without a title.
- Archived entries are included and marked as archived.
- Not exported: entries and journals in Recently Deleted, version history, the other versions of a conflict, settings and agent access.

**Contents**
- UTF-8 with LF line endings.
- YAML front matter comes first. Keys:

  | Key | Entry | Template | Notes |
  | --- | --- | --- | --- |
  | `title` | when the stored title isn't empty | when not empty | never filled in from the first line |
  | `date` | always | — | ISO 8601 with the device's offset |
  | `modified` | always | always | ISO 8601 with the device's offset |
  | `journal` | always | — | the journal's name |
  | `journal_id` | always | — | lets a future import recognize a renamed journal |
  | `id` | always | always | lets a future import recognize the entry |
  | `archived: true` | when archived | — | |
  | `pinned: true` | when pinned | — | |
  | `kind: template` | — | always | |

  Strings are always double-quoted, with YAML escapes for `"`, `\` and control characters.
- When the entry has a title, the body starts with `# Title` and a blank line. Most previews hide front matter, and Bear and iA Writer take a note's title from its first line. The title is one line, with `\` `` ` `` `*` `_` `[` `]` `<` `>` `#` `|` `~` backslash-escaped, `&` escaped before a letter or `#`, and `!` escaped before `[`, so it reads as plain text. A future import removes that heading when its text, after unescaping, equals `title:`.
- **Format version.** The root folder holds `.journal-export.json`, hidden in Finder and ignored by Obsidian: `{"format": "my-journal-markdown", "version": 1, "exported": "<ISO 8601>"}`. A change to the layout or the keys raises the version.
- The body follows exactly as the app stores it: CommonMark with GitHub Flavored Markdown tables, task lists (`- [ ]`, `- [x]`) and strikethrough. Image links are rewritten (below).

**Images**
- Images are written to `attachments/<id>.<ext>` in the folder of their journal, or of Templates.
- JPEG, PNG, GIF and WebP keep their original bytes.
- HEIC, HEIF and TIFF don't display in Obsidian, Typora, VS Code or GitHub, so they are converted to JPEG (quality 0.9), or to PNG when the image has transparency. Orientation and metadata are kept.
- Unknown types are identified from their bytes. An image that still can't be read isn't written and is counted as not included.
- Every image link is rewritten from `attachments/<id>` to that relative path, in all three forms: blocks, inline images, and reference definitions. A reference definition that a text link also uses can't change without changing the link; its image is then also written without an extension, at `attachments/<id>`, so the link still finds it. Raw HTML `<img>` tags are left as written and their images aren't exported.
- The image description stays the alt text.
- An image that hasn't downloaded yet is left out and counted for the note in 3.2. Its link stays as written in the entry.
- The format document notes that photos keep their EXIF metadata, which may include the location, before an export is shared.

**Content this version can't read**
- An entry this version can show but not edit, written by a newer format, is exported from its stored Markdown, unchanged.
- A record this version can't read at all is left out and counted.

**App-specific constructs in the stored Markdown**

The writer emits valid CommonMark that other apps may show differently. `protocol/markdown-export.md` lists each one with the result checked in Obsidian, VS Code's preview and GitHub's renderer:

- `<!-- -->` separators between adjacent delimiters;
- `&#32;` and `&#9;` at emphasis edges;
- `<u>…</u>` for underline;
- angle-bracket link destinations;
- backslash escapes;
- hard line breaks written as two trailing spaces, which editors that trim whitespace remove, and soft line breaks, which GitHub shows as spaces.

Typora, iA Writer and Bear aren't available for testing here. They are listed as not checked rather than claimed.

### 3.4 States

- **Empty library:** the folders of the empty journals are saved.
- **Offline, or not connected to a server:** no difference; the export reads only this device.
- **Encryption off:** the same flow, and the footer leaves out “aren't encrypted”.

## 4. Tests

- **JournalCore `MarkdownExportTests`:**
  - names: unsafe and Obsidian characters, NFC, the byte cap with emoji and CJK, reserved names before the first dot (entries and templates), case-insensitive duplicates numbered the same way twice, the Templates collision, untitled entries and templates;
  - front matter: escaping and the keys present for each case;
  - the title heading;
  - every image link (block, inline, reference) resolving to a written file;
  - HEIC converted to JPEG, and transparency kept as PNG;
  - images that haven't downloaded and unreadable records, both counted;
  - deleted entries and journals left out; archived and pinned marked;
  - content from a newer format exported unchanged;
  - re-parsing gives the same blocks apart from image paths.
- **App:**
  - an end-to-end export on the Mac to a temporary folder, with its files checked;
  - the authentication prompt when App Lock is on;
  - locking during preparation removes the prepared copy;
  - leftover cleanup at launch.
- **Real apps:** the exported folder opened in Obsidian and VS Code and rendered with GitHub's Markdown API; the results recorded in the format document.
- **Lists:**
  - the first-level marker's x equals the inset at 13, 17 and 53 pt;
  - a nested marker lines up with its parent's text;
  - checkbox taps still toggle;
  - the drawn markers match the characters they replace;
  - the nesting cap at the largest size leaves room for text.
- **Server removal:**
  - Stop Syncing runs once at launch for a library on the former Mac server (exact address plus `local-server.json`) and not for any other loopback server;
  - the notice appears and clears on connecting;
  - Erase keeps the old server's files;
  - the Mac Sync tab is checked in a real window.

## 5. Review of revision 1

An independent review (2026-10-05) returned **revise**. Required changes and how this revision answers them:

1. **A Mac connected to the removed server would see a false “will sync automatically”.** Section 1.2 runs Stop Syncing once and explains it in Sync.
2. **Other devices that synced through the Mac were left stranded.** The guides get a step-by-step section, including removing the Tailscale Serve rule.
3. **Erase and the old server data were undecided.** The files are kept, and their recovery and removal are documented.
4. **Agents of the old server.** Documented in step 5. Agent Access shows its ordinary not-connected state after Stop Syncing.
5. **Add Device showed nothing on a plain-HTTP connection.** It now explains, on both platforms.
6. **No pointer to where a server comes from.** Sync gets the How to Set Up a Server link.
7. **The inset grew with the text size.** It is now a fixed 18 points and counts against the nesting allowance.
8. **The editor comparison wasn't measured.** It is replaced with the Word and Docs measurements, and the inset is aligned with the quote indent.
9. **HEIC and TIFF images.** They are converted.
10. **Titles hidden by previews.** The body gets a `# Title` heading, and `title:` is written only when the entry has a title.
11. **Content silently left out.** The note after saving reports it.
12. **File-name limits.** Bytes are capped, cuts fall on grapheme boundaries, names are NFC, the reserved-name and Obsidian rules apply, templates get their own attachments folder, and duplicate numbering is deterministic.
13. **App-specific constructs and portability claims.** They are documented, checked in Obsidian, VS Code and GitHub, and the rest is marked as not checked.
14. **The File-menu flow.** It is specified to match Export Archive's sheet.

Suggestions taken:

- authentication before the export;
- the footer pointing to Export Archive;
- “Preparing Files…”;
- “Journal Markdown <date>”;
- VoiceOver announcements;
- the Obsidian characters;
- `journal_id`;
- the EXIF note;
- Connect to a Server… in Agent Access.

One suggestion wasn't taken: showing the save dialog first. Its reason is recorded in 3.2.

## 6. Review of revision 2

A second independent review (2026-10-05) returned **approve with required changes**. It confirmed that findings 1, 2, 4, 5, 8, 9 and 14 were resolved. Required changes and what was done:

1. **The once-only check could stop a working connection again** after someone reconnected to the old address. A permanent `local-server-retired` marker now gates it, separate from the notice.
2. **Erase deleted the old server's files** in the working tree. The exclusion is restored, and a test checks that Erase keeps them.
3. **Erase's copy wasn't true on these Macs.** A sentence is added while the files exist. The guide names the four items to delete, rather than the whole container.
4. **The notice linked to the general guide.** It now has Learn More, which goes to the Use This Mac section.
5. **Timing and order.** The check runs when the library opens and before the first sync. It is skipped while an encryption change is unfinished, and is recorded only when Stop Syncing ran. The revoke is skipped.
6. **The plaintext staging copy.** It is excluded from backups, gets complete file protection on iOS, and is removed by Erase and the launch cleanup.
7. **Other versions of a conflict.** They are counted in the note.
8. **Content inside list items.** It moves with the inset, and lists inside quotes are specified.
9. **Nesting depth.** The 160-point allowance is unchanged, so Increase Indent keeps its depth.
10. **Format version.** Recorded in `.journal-export.json`.
11. **Title escaping and the import rule.** Specified.
12. **The menu label.** It is now Export Journals as Markdown….

Suggestions taken:

- skipping the revoke;
- leftover notes that say what to do;
- line breaks in the constructs list;
- `kind: template`;
- the authentication reason for libraries without encryption;
- the Add Device copy naming the host;
- the same-address recovery path in the guide;
- the build 17 tester notes.

Names that clean down to nothing already fall back to the Untitled names, and the Templates folder already takes part in the same numbering pass.

## 7. Implementation check

- **Lists.** Checked on 2026-10-05 in images of the real editor at 16 and 30 pt on the Mac, and at 17 and 53 pt on iPhone. The editor drew the images itself, inside the app; they aren't screenshots of the whole window. Results:
  - markers sit 18 pt in;
  - wrapped lines, nested items, a second paragraph and two-digit numbers line up;
  - checkboxes follow the markers.
- **Mac Settings windows.** Captured from the app's own windows with a disposable library:
  - Sync, not connected, with How to Set Up a Server;
  - Sync after stopping syncing with the former Mac server, with Learn More;
  - Backup with the Markdown section;
  - Agent Access, not connected;
  - General with the Erase sentence;
  - the Export as Markdown sheet, in light and dark appearance.
  
  Each matched this record, and File ▸ Export Journals as Markdown… sits after Export Archive….
- **Mac save dialog.** It opens with “Journal Markdown 2026-10-05”. The sandboxed dialog runs outside the app, so the test can't press Save in it.
- **iPhone save dialog.** `MarkdownExportUITests` saves a folder through the Files save dialog with no error.

## 8. Adversarial QA (2026-10-05)

An independent QA pass tried to break the three changes:

- the Mac and JournalCore suites;
- 95 adversarial names checked with libyaml and markdown-it;
- 600 entries with 300 images, exported in 0.55 s;
- the former-server check with a missing device key, an encrypted library, and repeated runs;
- lists at every size.

The former-server check and the lists held up. It found these, now fixed and covered by tests:

1. **A deleted journal's entries were exported to Other Entries**, because only the journal carries `deletedAt`. They now stay out, with the journal.
2. **Names equal only under full case folding** (“Straße”/“STRASSE”) collided on APFS and failed the whole export. Names are now numbered as APFS compares them.
3. **Noncharacters and unassigned code points in a title** failed the whole export. They are now replaced in names and escaped in YAML. Direction overrides are replaced too.
4. **A reference definition shared by an image and a link** left every image link in that entry unrewritten. Each image is now rewritten on its own; the shared one also gets a bare-name copy.
5. **An image missing from two entries was counted twice.** Each image now counts once.
6. **`CON.txt` became `CON.txt-`,** which Windows still reserves. It now becomes `CON-.txt`, and `COM¹`–`COM³` and `LPT¹`–`LPT³` are reserved too.
7. **Copying a list to another app misaligned its wrapped lines.** The copied paragraph now puts the marker where the editor draws it, with a tab stop at the item's text.

Known and unchanged:

- A quote or code block inside a list item still draws its bar or background from the text's left edge. This was already so before the inset; it is now 18 points further from the text.
- Entries in Other Entries have no `journal` keys, because their journal isn't in the library.
- A Mac whose encryption upgrade was cut off mid-request against the removed server keeps writing paused until the upgrade is cancelled. Such a Mac skips the one-time check by design.

