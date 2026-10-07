---
id: entry-editor
title: Entry editor
features: [entry-title, entry-body, autosave, save-failure-recovery, inline-formatting, paragraph-styles, lists, checklists, list-indentation, block-quotes, code-blocks, horizontal-rules, tables, links, inert-links, insert-image, image-actions, image-descriptions, image-placeholders, markdown-as-you-type, source-view, paste-and-drop, copy-to-other-apps, undo-redo, find-in-entry, text-size, spelling-and-substitutions, template-suggestion, entry-actions, change-entry-date, move-entry, pin-entry, save-as-template, delete-entry, version-history, conflict-review-entry, read-only-newer-content, source-only-entry, editor-only, writing-controls, conflict-notice, writing-paused-notice, previous-next-entry]
sources:
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Views/RootView+Toolbar.swift
  - apps/apple/JournalApp/Views/Mac/RootView+MacWindow.swift
  - apps/apple/JournalApp/Views/Mac/JournalToolbarController.swift
  - apps/apple/JournalApp/Views/EntryHeaderView.swift
  - apps/apple/JournalApp/Views/EntryEditingNote.swift
  - apps/apple/JournalApp/Views/EntryRecoveryNotice.swift
  - apps/apple/JournalApp/Views/SaveFailureNotice.swift
  - apps/apple/JournalApp/Views/SettingsView.swift (ConflictNotice)
  - apps/apple/JournalApp/Views/ReadingBar.swift
  - apps/apple/JournalApp/Views/ImageImportNotice.swift
  - apps/apple/JournalApp/Editor/NativeEditor.swift
  - apps/apple/JournalApp/Editor/NativeTextView.swift
  - apps/apple/JournalApp/Editor/RichText.swift
  - apps/apple/JournalApp/Editor/EntryTitleEditor.swift
  - apps/apple/JournalApp/Editor/EditorPlaceholder.swift
  - apps/apple/JournalApp/Editor/JournalWritingView.swift
  - apps/apple/JournalApp/Editor/WritingAccessory.swift
  - apps/apple/JournalApp/Editor/TypingRoom.swift
  - apps/apple/JournalApp/Editor/SelectionReveal.swift
  - apps/apple/JournalApp/Editor/ImagePresentation.swift
  - apps/apple/JournalApp/Editor/InlineImages.swift
  - apps/apple/JournalApp/Editor/InlineTasks.swift
  - apps/apple/JournalApp/Editor/BlockDecorations.swift
  - apps/apple/JournalApp/Editor/ListLayout.swift
  - apps/apple/JournalApp/Editor/ListAccessibility.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/JournalNavigation.swift
  - apps/apple/JournalApp/AppCommands.swift
  - docs/design/notes-alignment-revision.md
  - docs/design/owner-decisions-2026-09-25.md
  - docs/design/menus-and-popovers.md
  - docs/design/sync-now-and-done.md
  - docs/design/checklists-2026-10-03.md
  - docs/design/list-markers-2026-10-03.md
  - docs/design/list-indentation-2026-10-04.md
  - docs/design/client-only-mac-lists-markdown-2026-10-05.md
  - docs/design/quiet-sync-and-title-alignment.md
  - docs/design/typing-scroll.md
  - docs/design/mac-typing-room-2026-10-04.md
  - docs/design/unified-entry-scrolling.md
  - docs/design/save-failure-retry.md
  - docs/design/new-entry-template-suggestion.md
  - docs/design/image-block-spacing.md
  - docs/design/document-image-loading.md
---

# Entry editor

## Purpose

Where an entry or template is written and read. Writing is primary: a title and a body of rich text that is stored as Markdown, with formatting, lists, checklists, quotes, code, rules, tables, links and images, saved quietly as the person writes.

The precise behaviour of every key, command and edit is in `flows/editing-rules.md`. This file describes the screen.

## Entry points

- Choosing an entry or template in the entries list (computer, tablet: the detail column; phone: pushed onto the stack).
- New Entry, New Blank Entry, New Entry from Template… (the new entry opens with its title focused and selected; see Rules).
- Restoring a version, moving or restoring an entry, and resolving a conflict open the result in the editor.
- After launch or unlock, the entry that was open reopens (phone: only if it is still editable in its journal).

## Content

Top to bottom, inside the detail area (max 760 pt wide on every platform, centred, with 24 pt margins on the computer).

1. **Notices above the writing** (each only in its state; see States). Order on the computer: writing-paused notice, recovery notice, conflict notice. On the phone and tablet the recovery notice is part of the scrolling header (item 2) and the conflict notice sits above the scrolling writing, so it stays in view.
2. **Header**, which scrolls with the body on the phone and tablet and sits above the body on the computer:
   - Save-failure notice (phone, tablet: first in the header; computer: below the body). See States.
   - Recovery notice (phone, tablet).
   - **Title**: one large bold field (Title 1 style, bold). Placeholder `editor.title.placeholder`. Wraps to as many lines as needed; a pasted title keeps its line breaks. Its first letter starts exactly where the body's first letter does.
   - **Editing note** (only when the entry can't be edited normally): `messages.error.unsupportedFormat` or `messages.unavailable.markdownSource`, in secondary text.
3. **Image import notice** (only while chosen images are being read; see `flows/insert-image.md`).
4. **Body**: the rich text of the entry. Its accessibility label is `editor.body.accessibilityLabel`.
   - **Empty body placeholder**: `editor.body.placeholder`, laid out exactly as typed body text would be. When the entry can use a template (see Rules), the placeholder is `editor.body.placeholder.templatePrefix` followed by a link: a template symbol and the underlined words `editor.body.placeholder.templateLink`, in the accent colour. Activating the link opens the template chooser (`screens/template-chooser.md`); VoiceOver reads the link as `library.templateChooser.useTemplate`. The placeholder and link disappear with the first character typed and come back when the body is empty again.
   - Blocks are drawn as described in “How blocks look” below.
5. **Writing controls** (phone, tablet only): a floating capsule bar at the bottom.
   - While reading: Formatting, Insert Image, then (phone: pushed to the far end) View Source or View Preview. Hidden while the keyboard is up or a table cell is being edited.
   - While writing: the same controls, in the same order and look, ride above the on-screen keyboard (or at the bottom of the screen with a hardware keyboard). Only the capsule takes touches; beside it, touches reach what is behind.
6. **Toolbar items** for the editor:
   - Computer (the window toolbar's editor section, specified with the library window): New Entry, Formatting (`library.toolbar.formatting`), Insert Image (`library.toolbar.insertImage`), then (only with sync) Sync Status, then Editor Only (`library.toolbar.editorOnly`), View Source/View Preview (`library.menu.view.viewSource` / `library.menu.view.viewPreview`), Entry Actions (`library.toolbar.entryActions`), Search. Each item's tooltip is its label. See `commands.md#editor`.
   - Phone, tablet (navigation bar, trailing): Entry Actions (… symbol, label `library.toolbar.entryActions`), and while writing the Done checkmark (label `common.done`).
   - Writing controls' labels (icon-only, read by VoiceOver and shown as tooltips with a pointer): `library.toolbar.formatting` (Aa, shown selected while Formatting is open), `library.toolbar.insertImage`, `library.menu.view.viewSource` / `library.menu.view.viewPreview` (help `common.previewUnavailable` when preview isn't available).

### How blocks look

All sizes are relative to the body text size *s* (computer default 16 pt, View ▸ Zoom from 12 to 30 pt; phone and tablet: the Dynamic Type body size, scaled by View ▸ Zoom).

| Block | Look |
| --- | --- |
| Paragraph | Body font, line spacing 3 pt, 10 pt after the paragraph. |
| Heading 1 / 2 / 3 | Semibold at 1.4 *s* / 1.2 *s* / 1.1 *s*. |
| Heading 4–6 | Semibold at *s*. |
| Bulleted, numbered, checklist item | The marker (•, “n.”, or a checkbox) sits 18 pt in from the body text (the list inset, the same as the quote indent). The item's text starts one list column after the marker; the list column is 1.5 *s* rounded to whole points. Wrapped lines start where the text starts. Each nesting level moves in one list column, so a nested marker sits under its parent's text; nesting stops moving in after 160 pt (6 levels at 16–17 pt). A numbered list whose widest number plus a space doesn't fit the column widens the column for every item of that list. Markers are drawn, never part of the text. |
| Checkbox | Phone, tablet: a rounded square symbol sized by the item's font, unchecked as an outline in secondary colour, checked as a square filled with the accent colour and a white checkmark; centred on the first line's capital letters; touch area 44 pt tall (or 1.3 *s*) from the column's start to the text, split halfway with a neighbouring item's. Computer: the native checkbox (small below 14 pt, regular to 20 pt, large above). Checked text is not dimmed or struck through. Disabled appearance in read-only entries. |
| Block quote | Text 18 pt in; a 3 pt rounded bar in tertiary colour at the left, the height of the quote's lines. |
| Code block, raw HTML block | Monospaced at *s*; a rounded (6 pt) fill behind it, 10 pt padding at the sides, 6 pt above and below; 12 pt extra space after it before the next block. |
| Inline code | Monospaced, with the code fill behind it. |
| Horizontal rule | A hairline across the text width, in separator colour, on a line of its own. |
| Table | A hairline grid with every cell editable in place; the header row is semibold; columns share the text width equally, each at least 7 × *s* wide (more columns scroll sideways); cell text wraps for display only. 12 pt extra space after it. |
| Image on its own line | Its natural size (computer: points from its resolution; phone and tablet: pixels as points), scaled down to fit the text width; spaced like a paragraph, as much room below as above. |
| Image inside a line, or a remote image | Small: at most 120 pt wide and 80 pt high. |
| Image not loaded | A placeholder line in secondary text at the image's place: `editor.image.loading`, `editor.image.unavailable` or `editor.image.remote`. |
| Link | The system link appearance (underlined, link colour) for web and email links. Other links are shown as plain text and kept (inert links). |

## Actions

| Action | Command | Enabled | Result |
| --- | --- | --- | --- |
| Type in the title | — | Entry editable | Saved as typed. Return or Tab (phone, tablet hardware keyboard) moves to the body (`flows/editing-rules.md` T-1). |
| Type in the body | — | Entry editable | Saved as typed (`flows/save-entry.md`). |
| Format text, paragraphs and lists | `format-*` | Entry editable | `screens/format-sheet.md`, `commands.md#editor`, `flows/editing-rules.md`. |
| Insert Image | `insert-image-*` | Entry editable | `flows/insert-image.md`. |
| Add Link | `insert-link` | Entry editable, body or a cell focused | `screens/link-editor.md`. |
| Toggle a checkbox | `toggle-checkbox` | Entry editable | Toggles that item; one undo step; the caret stays where it was. |
| View Source / View Preview | `view-source` | Entry editable; View Preview also needs Markdown the preview can show | `flows/source-view.md`. |
| Entry Actions | `entry-actions` | An entry or template is open | Menu; see below. |
| Done (phone, tablet) | `finish-editing` | Shown only while the title, body or a cell has keyboard focus | Ends editing in all of them, closes the keyboard, waits for the pending save in the background, returns to reading with the writing controls at the bottom. VoiceOver focus moves to the text that was being edited. |
| Find in Entry | `find-in-entry` | — | Phone, tablet: the system find navigator for this entry. Computer: Edit ▸ Find ▸ Find… opens the find bar above the entry (it never covers the first line). |
| Act on a picture | `image-*` | See `flows/image-actions.md` | Context menu or long press on a picture. |
| Use a template | `use-a-template` | Template suggestion shown | Opens the template chooser; a choice fills this entry's body and keeps its title (specified with templates). |
| Review Changes | `review-changes` | Conflict notice shown | Saves the open writing, refreshes, then opens `screens/entry-conflict.md`. |

**Entry Actions menu** (the editor's “…”; same items as the entry's row context menu, built from one list):

- Phone and tablet only, first: `library.entryActions.findInEntry`, then a separator.
- For an entry in a journal: `library.entryActions.pin` / `library.entryActions.unpin` (when pinning is possible), `library.entryActions.changeDate`, `library.entryActions.moveEntry`, `library.entryActions.saveAsTemplate`, `library.entryActions.imageDescriptions` (only when the entry has images; disabled unless descriptions can be edited), `common.versionHistoryEllipsis`, separator, `library.entryActions.deleteEntry` (destructive).
- For a template: New Entry In ▸ (journals) or New Entry from Template (specified with templates), separator, Image Descriptions… (with images), Version History…, separator, `library.entryActions.deleteTemplate`.
- For an item in Recently Deleted: Image Descriptions… (with images, disabled), Version History…, `common.restore` (when it can be restored directly), separator, `library.entryActions.deletePermanently` (destructive).
- Phone and tablet only, last: Sync Status ▸ (only when sync needs the person; specified with sync).

Each item first saves the open writing; if that save fails the action doesn't run. Details: `commands.md#editor`; Change Date `screens/change-date.md`; Move Entry `screens/move-entry.md`; Save as Template (alert) `screens/entry-list.md`; Image Descriptions `screens/image-description.md`; Version History `screens/version-history.md`. Delete Entry moves the entry to Recently Deleted at once, without confirmation; Edit ▸ Undo `library.entryActions.deleteEntry` brings it back; the computer and tablet then open the next entry below (or above, at the end), the phone goes back to the list.

## States

| State | What shows | Copy |
| --- | --- | --- |
| Nothing selected, list has entries | The detail area shows centred secondary text. | `library.window.selectEntry` |
| Nothing selected, list empty | Blank (computer, tablet). Without the list beside it, the editor shows what the empty list would (specified with the entries list). | — |
| Empty body | Placeholder, with the template link when offered. | `editor.body.placeholder`, `editor.body.placeholder.templatePrefix`, `editor.body.placeholder.templateLink` |
| Reading (phone, tablet) | Text not focused; writing controls at the bottom. A tap in the text starts writing there; a tap below the text starts writing at the end. | — |
| Writing (phone, tablet) | Keyboard and writing controls; Done checkmark. The line being typed stays above the controls (they are the text's bottom inset). | `common.done` |
| Writing (computer) | Two lines of room are kept below the line being typed (never more than a quarter of the editor's height); the editor's own edits (Return in a list, shortcuts, paste, undo) reveal the caret with that room. | — |
| Saving | Nothing shows. Saving is quiet. | — |
| Save failed | The app's error alert (title `common.alertTitle`, specified with the journal window) with `common.saveFailed` (named entry) or `common.saveFailedLocked`, buttons `common.tryAgain` and `common.ok`. Then a persistent notice: `messages.save.notSaved` in red, a `common.tryAgain` button, and while retrying `messages.save.saving` with a small progress indicator. The person can't leave the entry until it saves. See `flows/save-entry.md`. | as listed |
| Conflict | A band above the writing (callout text, quaternary fill), side by side; stacked at accessibility text sizes. The entry stays editable. | `messages.conflict.entryNotice`, `common.reviewChanges` |
| Read-only: newer format | Title shown as static text (phone, tablet) or a disabled field (computer); body selectable but not editable; formatting, Insert Image and View Source disabled; checkboxes disabled; picture menus offer only Copy, Share and Save. | `messages.error.unsupportedFormat` |
| Source only | The entry opens in source view; View Preview is disabled, with the help text below. Everything else is editable as Markdown text. | `messages.unavailable.markdownSource`, `common.previewUnavailable` |
| In Recently Deleted (entry) | Read-only, with a recovery notice band (quaternary fill) above: `library.recoveryNotice.entry`, buttons `common.restore` (journal in use), `library.recoveryNotice.restoreWithJournal` (journal is also in Recently Deleted), `library.recoveryNotice.restoreAndMove`. An entry deleted with its journal by an earlier version shows `library.recoveryNotice.legacy` and only Restore and Move…. At accessibility text sizes the notice takes at most half the height and scrolls. | as listed |
| In Recently Deleted (template) | Read-only; `library.recoveryNotice.template` with `common.restore`. | as listed |
| Journal unavailable | Read-only; one of: `common.updateToRestoreEntry`; `common.journalNotArrived` with `common.trySyncingAgain` (with a server); `common.journalUnavailableEntrySaved` (without); `common.journalNeedsReview` with `common.reviewChanges`. An entry deleted with a missing journal also offers Restore and Move…. | as listed |
| Writing paused (computer) | Above the editor, a band with text and a button; the entry is read-only meanwhile. Connecting (shown only after 1 s): `messages.writingPaused.connecting`; failed: `messages.writingPaused.connectionFailed`; both with `messages.writingPaused.showConnection`. Encrypting: `messages.writingPaused.encrypting` or `messages.writingPaused.encryptionUnfinished` with `messages.writingPaused.showProgress`. | as listed |
| Images loading | Each missing picture shows its placeholder line until it arrives, then the picture replaces it in place, keeping the visible text where it was. | `editor.image.loading`, `editor.image.unavailable`, `editor.image.remote` |
| Locked | The editor isn't shown; every sheet, menu, popover, share sheet and save panel the editor opened closes. Writing is saved first (`flows/save-entry.md`). | — |
| Entry removed while open | If it has no unsaved writing, the editor closes (phone: back to the list; computer, tablet: “Select an Entry”). With unsaved writing it stays open with the writing intact. | `library.window.selectEntry` |

## Rules

- **Editable** means: the library is open and unlocked, not being replaced (connecting, turning on encryption), the item isn't deleted, its document is in a format this version can edit, and it is a template or an entry in a journal that is in use. A conflict doesn't make it read-only.
- **Saving**: every change to the title or body is saved to this device as it happens, without a Save command or a delay; sync follows when writing pauses. Leaving the entry first finishes the save. Details and failure handling: `flows/save-entry.md`.
- **Never lose writing**: a change from elsewhere (sync) to the open entry replaces what's shown only while the person isn't composing with an input method; it waits for the composition to end and then applies both, block by block. Writing over a change this device hasn't shown yet keeps both versions for review (`flows/editing-rules.md` X-1 to X-5).
- **New entry**: opens with the title focused and its text selected. When the entry came from a template, Return in the title moves to the template's first empty paragraph (its answer line).
- **Template suggestion**: offered when the item is an entry, it can be edited, at least one template can be used, and the body has no characters and no images (whatever the title).
- **Title display elsewhere**: an entry without a title is named by its first line of text, or `library.entryList.untitledEntry` when it has none.
- **Text size**: View ▸ Zoom In / Zoom Out change the body size by 1 pt between 12 and 30 pt (computer default 16); Actual Size returns to 16. On the phone and tablet the same steps scale the Dynamic Type body size proportionally. Zooming keeps the selection and undo.
- **Undo** keeps the last 100 steps of the body. Opening another entry, or a change from elsewhere, clears it.
- **Source view** is per visit: every entry opens in preview unless its Markdown can only be shown as source.
- **Checkbox controls** exist only for checklist items on screen and just beyond it; they move with the text.
- **Images** are decoded at the size they are shown, not their full size.
- The editor never shows hidden characters for list markers: the text holds only what the person wrote.

## Accessibility

- Title: label `editor.title.accessibilityLabel`. Body: label `editor.body.accessibilityLabel`.
- List items and quotes carry what they are as accessibility text attributes on their own text, not as characters: computer: the item prefix (“•”, `editor.list.number`, `editor.list.checkboxUnchecked`, `editor.list.checkboxChecked`) and nesting level; quotes `editor.list.quote`. Phone, tablet: a custom attribute `editor.list.bullet`, `editor.list.number`, the checkbox phrases, `editor.list.quote`.
- Checkboxes: a button labelled with the item's text (`editor.list.emptyChecklistItem` when empty), value `editor.list.checked` / `editor.list.unchecked`; computer: native checkbox labelled with the text. They follow the text in VoiceOver order, then one element per picture.
- Pictures: label = description, or `editor.image.accessibilityLabel`; when not shown, the status (`editor.image.loadingAccessibility`, `editor.image.unavailableAccessibility`, `editor.image.remoteAccessibility`) followed by the description; the image trait; the picture's actions as custom actions (`flows/image-actions.md`). Activating a picture element does nothing else.
- Announcements: style changes from shortcuts and Backspace (`editor.announce.*`), indentation level (`editor.announce.level`), view mode (`editor.announce.source`, `editor.announce.preview`), images added, copied, saved, deleted.
- Notices stack vertically at accessibility text sizes. The Done action posts a layout change to the edited text.
- Reduce Motion: no editor animation is added; notices appear without motion when it's on. Formatting panels never animate.
- Increased contrast and dark mode: all colours are system colours; checkboxes, rules, quote bars and code fills adapt.
- Keyboard: every formatting command has a menu item; the computer's checkboxes don't take keyboard focus (Mark as Checked is the keyboard route).

## Platform notes (Apple)

- **Computer** (Mac): three columns; the editor is the detail column. Title is a wrapping text field above the body; the body scrolls on its own. Toolbar items are window toolbar items. The save-failure notice is below the body. Writing-paused notices exist only here. No Done button.
- **Phone** (iPhone): the header (title, notices) scrolls with the body as one page. Writing controls float at the bottom; the keyboard accessory shows the same controls. Formatting replaces the keyboard with the Format panel (`screens/format-sheet.md`).
- **Tablet** (iPad): as the phone, but in regular width Formatting is a popover pointing at Aa. The system's own B/I/U and text-format buttons are removed from the keyboard's shortcut bar; undo, redo and paste stay. The menu bar has the Mac's File, Edit, Format and View commands.
- A layout change that replaces the editor mid-sentence (rotation into split view) continues writing at the same place with the keyboard up, but only within the same visit to the entry.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
