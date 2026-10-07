---
id: link-editor
title: Add Link
features: [links, inert-links]
sources:
  - apps/apple/JournalApp/Views/LinkEditorView.swift
  - apps/apple/JournalApp/Editor/FormattingState.swift (LinkAddress, LinkInsertion)
  - apps/apple/JournalApp/Editor/RichText.swift (EditorActions.openLinkFromKeyboard, prepareLink)
  - apps/apple/JournalApp/Editor/SourceFormatting.swift (.link)
  - apps/apple/JournalTests/LinkInsertionTests.swift
  - docs/design/menus-and-popovers.md (D8)
---

# Add Link

## Purpose

Turn the selected text into a link to a web page or an email address, or insert a new link.

## Entry points

- Format ▸ Insert ▸ Link… (⌘K) on the computer and tablet; ⌘K with a hardware keyboard on the phone and tablet (`insert-link`). Works only while the body or a table cell has keyboard focus.
- Formatting ▸ Insert ▸ Link… (`screens/format-sheet.md`); the Formatting surface closes first.

## Content

A small sheet (computer: 420 × 220 pt; phone, tablet: a sheet with a navigation bar), in a grouped form:

1. Title `editor.link.title`.
2. Text field `editor.link.text`: filled with the selected text when it opens (empty when nothing is selected). Editable.
3. Text field `editor.link.address`: empty, focused when the sheet appears. No autocorrection; on the phone and tablet a URL keyboard, no autocapitalization, Return key “Done”.
4. Below the fields, only when the address isn't empty and isn't valid: `editor.link.invalid` (callout, secondary).
5. Toolbar: `common.cancel` (cancellation position) and `editor.link.add` (confirmation position), disabled until the address is valid.

## Actions

| Action | Result |
| --- | --- |
| Add Link (or Return in the address field on the phone and tablet, when valid) | Applies the link to the selection captured when the sheet opened (`flows/editing-rules.md` L-1 to L-6). Closes without animation. Focus returns to the text. |
| Return with an invalid address (phone, tablet) | The field keeps focus; VoiceOver announces `editor.link.invalid` (when the field isn't empty). |
| Cancel, Escape | Closes without changes. Focus returns to the text. |

## States

- Address empty: Add Link disabled, no message.
- Address invalid: Add Link disabled, message shown.
- Locked, another entry opened, or the app's journals erased: the sheet closes without changes.

## Rules

- Valid addresses (`LinkAddress.url`): `http:`, `https:` or `mailto:` in any letter case, with a host for web addresses and an `@` for email; or, written without a scheme, an email address (`name@example.com` → `mailto:`) or a host name with a domain (`www.example.com`, `example.com/path?q=1` → `https://`). Leading and trailing spaces are ignored. The scheme is stored in lower case. Everything else is refused, including `localhost`, `e.g`, `name@host`, `@example.com`, `javascript:` and `tel:` (`LinkInsertionTests.testAddLinkCompletesEmailAndWebAddressesWithoutAScheme`).
- There is no Edit Link or Remove Link: choosing Add Link on an existing link opens the same empty sheet, and adding replaces the link on the selected text.
- The sheet appears and closes without animation where the platform allows (computer: the system sheet may still slide).

## Accessibility

- Fields are labelled by their placeholders (“Text”, “Link”). The invalid message is read after the field and announced on Return.
- Standard sheet: Escape cancels; the confirmation button is the default action only when enabled.

## Platform notes (Apple)

- Same sheet on all platforms; on the phone and tablet Return in the address field adds a valid link, as Notes does.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
