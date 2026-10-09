---
id: export-markdown
title: Export journals as Markdown
features: [export-markdown]
sources:
  - apps/apple/JournalApp/Views/MarkdownExportView.swift
  - apps/apple/JournalApp/Model/MarkdownExportOperations.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/MarkdownExport.swift
  - docs/design/client-only-mac-lists-markdown-2026-10-05.md
  - protocol/markdown-export.md
---

# Export journals as Markdown

## Purpose

Saves every journal as Markdown files, with their images, in a folder other apps can open. It isn't a backup: it can't be imported (that's Export Archive). The folder's format is defined in `protocol/markdown-export.md`.

## Entry points

- Settings ▸ Backup ▸ Export as Markdown…; File ▸ Export Journals as Markdown… (sheet).

## Steps

1. Export as Markdown….
2. **When App Lock is on:** the device owner authenticates first, with the reason `settings.backup.markdownReason` ("Export your journals as files that aren’t encrypted") for encrypted journals, or `settings.backup.markdownReasonUnencrypted` ("Export your journals as Markdown files"). Cancelled: nothing happens, nothing is said. Failed (for example biometrics locked out): nothing is exported and `settings.backup.verifyFailed` shows in the place where the export's own errors show.
3. **Preparing:** the open entry is saved (if it can't be: `messages.save.before.goBack`); the folder is written to a temporary place excluded from backups. Indicator after 0.3 seconds.
4. **Save dialog** with the folder, suggesting `settings.backup.markdownFolderName` ("Journal Markdown {yyyy-MM-dd}").
   - Saved: if something was left out, a note appears under the button (below) and is announced.
   - Cancelled: nothing.
   - Saving failed: `messages.export.markdownSaveFailed`.
5. The temporary folder is removed when the dialog closes.

### The note after saving

Sentences, in this order, each only when it applies, joined with a space:
- `settings.backup.markdownNote.imagesNotDownloaded` (plural): images that haven't downloaded yet;
- `settings.backup.markdownNote.imagesUnreadable` (plural): images that couldn't be read;
- `settings.backup.markdownNote.itemsUnreadable` (plural): entries made with a newer version;
- `settings.backup.markdownNote.otherVersions` (plural): entries with another version that wasn't included.

## Errors

| When | Message |
| --- | --- |
| The open entry can't be saved first | `messages.save.before.goBack` |
| Not enough space | `messages.export.markdownNoSpace` |
| Anything else while preparing | `messages.export.markdownFailed` |
| Saving to the chosen place failed | `messages.export.markdownSaveFailed` |

Errors are announced and shown in red under the button.

## Rules

- One Markdown export at a time.
- Locking cancels; leftovers are removed at the next launch.
- The files aren't encrypted, whatever the journals are; the footer says so for encrypted journals.

## Accessibility

- Errors and notes are announced; the indicator is labelled `settings.backup.preparingFiles`.

## Platform notes (Apple)

- On the Mac the authentication dialog reads “My Journal is trying to export your journals…”, so the reason starts in lower case there (`mac` variant).

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
