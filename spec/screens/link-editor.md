---
id: link-editor
title: Add Link and Edit Link
features: [links, inert-links, edit-link]
sources:
  - apps/apple/JournalApp/Views/LinkEditorView.swift
  - apps/apple/JournalApp/Editor/LinkEditing.swift
  - apps/apple/JournalApp/Editor/LinkMenuMac.swift
  - apps/apple/JournalApp/Editor/FormattingState.swift (LinkAddress, LinkInsertion)
  - apps/apple/JournalApp/Editor/RichText.swift (EditorActions.openLinkFromKeyboard, prepareLink)
  - apps/apple/JournalApp/Editor/SourceFormatting.swift (.link)
  - apps/apple/JournalTests/LinkInsertionTests.swift
  - docs/design/menus-and-popovers.md (D8)
  - docs/design/build-18-fixes-2026-10-06.md (section 2.4)
---

# Add Link and Edit Link

## Purpose

Turn the selected text into a link to a web page or an email address, insert a new link, change where an existing link goes (and, for plain text, what it says), or take a link off.

## Entry points

- Format ▸ Insert ▸ Add Link… (⌘K) on the computer and tablet; ⌘K with a hardware keyboard on the phone and tablet (`insert-link`). Works only while the body or a table cell has keyboard focus.
- With the caret or selection in one link, the same item reads Edit Link… and opens the sheet for that link (`insert-link`).
- Formatting ▸ Insert ▸ Add Link… or Edit Link… ([screens/format-sheet](format-sheet.md)); the Formatting surface closes first.
- Computer: the context menu on a link has Edit Link… and Remove Link in place of the system's own link items.
- Remove Link (`remove-link`) is also in Format ▸ Insert and Formatting ▸ Insert; it is dimmed unless the caret or selection touches a link.

## Content

A small sheet (computer: 420 pt wide, 220 pt tall when adding and 270 pt when editing; phone, tablet: a sheet with a navigation bar), in a grouped form:

1. Title `editor.link.title` when adding, `editor.link.editTitle` when editing.
2. Text field `editor.link.text`. Adding: filled with the selected text (empty when nothing is selected), editable. Editing: filled with the link's own text, editable, **but shown only when the link's characters are plain text on one line**. A link that holds a line break, a paragraph break or a picture has no Text field, so an edit can never drop a picture or flatten paragraphs.
3. Text field `editor.link.address`. Adding: empty. Editing: the link's address, an email address without `mailto:`, and an address the app doesn't open (an inert link) exactly as stored. Focused when the sheet appears. No autocorrection; on the phone and tablet a URL keyboard, no autocapitalization, Return key “Done”.
4. Below the fields, only when the address isn't empty and isn't valid: `editor.link.invalid` (callout, secondary).
5. Editing only: a separate group at the end with a destructive button `editor.link.remove`.
6. Toolbar: `common.cancel` (cancellation position) and, in the confirmation position, `editor.link.add` when adding or `common.done` when editing, disabled until the address is valid.

## Actions

| Action | Command | Result |
| --- | --- | --- |
| Add Link (or Return in the address field on the phone and tablet, when valid) | `insert-link` | Applies the link to the selection captured when the sheet opened (`flows/editing-rules.md` L-1 to L-6). Closes without animation. Focus returns to the text. |
| Done (editing) | `insert-link` | Changes the address of the whole link, and its text when the Text field was shown and its content now differs (`flows/editing-rules.md` L-8). One undo step named `editor.undo.editLink`. Closes; focus returns to the text. |
| Remove Link (in the sheet) | `remove-link` | Takes the link off (L-9) and closes. |
| Return with an invalid address (phone, tablet) | `insert-link` | The field keeps focus; VoiceOver announces `editor.link.invalid` (when the field isn't empty). |
| Cancel, Escape | — | Closes without changes. Focus returns to the text. |

## States

- Address empty: the confirmation button is disabled, no message.
- Address invalid: the confirmation button is disabled, message shown. Editing an inert link starts in this state until the address is corrected, but Remove Link is available.
- Locked, another entry opened, or the app's journals erased: the sheet closes without changes.
- The text became shorter than the captured link while the sheet was open: the edit is skipped.

## Rules

- Valid addresses (`LinkAddress.url`): `http:`, `https:` or `mailto:` in any letter case, with a host for web addresses and an `@` for email; or, written without a scheme, an email address (`name@example.com` → `mailto:`) or a host name with a domain (`www.example.com`, `example.com/path?q=1` → `https://`). Leading and trailing spaces are ignored. The scheme is stored in lower case. Everything else is refused, including `localhost`, `e.g`, `name@host`, `@example.com`, `javascript:` and `tel:` (`LinkInsertionTests.testAddLinkCompletesEmailAndWebAddressesWithoutAScheme`).
- Which link is edited, what Edit Link and Remove Link change and where they don't work: `flows/editing-rules.md`, L-7 to L-10.
- The sheet appears and closes without animation where the platform allows (computer: the system sheet may still slide).

## Accessibility

- Fields are labelled by their placeholders (“Text”, “Link”). The invalid message is read after the field and announced on Return.
- Standard sheet: Escape cancels; the confirmation button is the default action only when enabled.
- Remove Link in the sheet is a destructive button in its own group. After any Remove Link, VoiceOver announces `editor.link.removed`.

## Platform notes (Apple)

- Same sheet on all platforms; on the phone and tablet Return in the address field adds a valid link, as Notes does.
- The computer's right-click menu on a link shows Edit Link… and Remove Link instead of the system's own link-editing items, only when the pointer is on a character of the link; Edit Link… selects the whole link first, so the sheet and the selection agree.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
