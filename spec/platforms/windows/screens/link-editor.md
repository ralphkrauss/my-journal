---
id: link-editor
title: Add link and edit link (Windows)
spec: screens/link-editor.md
features: [links, inert-links]
status: draft
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
---

# Add link and edit link (Windows)

Turns the selected text into a link to a web page or an email address, inserts a new link, changes where an existing link goes (and, for plain text, what it says), or takes a link off. Behaviour, address rules and copy keys are the spec's [link-editor](../../../screens/link-editor.md); the editing result follows rules L-1 to L-10 of the spec's [editing rules](../../../flows/editing-rules.md) (the Windows flow mapping [flows/editing-rules](../flows/editing-rules.md) maps L-1 to L-6 only so far: L-7 to L-10 are stated here until it does).

## Controls

A `ContentDialog`, 420 epx wide, opened over the window. Add and edit are one dialog with two forms: **adding** when the caret or selection is not in one link, **editing** when it is (L-7: the caret in a link or at either end of it; a selection that starts outside a link, reaches beyond it or spans several links offers Add link instead). Edit link and Remove link do nothing in a table cell or in the Markdown source, where the menu items stay at Add link… and a dimmed Remove link (L-10).

| Spec element | Control | Notes |
| --- | --- | --- |
| Title | `ContentDialog.Title`: `editor.link.title` when adding, `editor.link.editTitle` when editing | The form is fixed when the dialog opens |
| Text field | `TextBox`, `Header` `editor.link.text`, editable. Adding: filled with the selected text (empty when nothing is selected). Editing: filled with the link's own text, **shown only when the link's characters are plain text on one line**; a link that holds a line break, a paragraph break or a picture has no Text field, so an edit can never drop a picture or flatten paragraphs | `AutomationProperties.Name` the same |
| Address field | `TextBox`, `Header` `editor.link.address`, focused when the dialog opens. Adding: empty. Editing: the link's address, an email address without `mailto:`, and an address the app does not open (an inert link) exactly as stored; `InputScope` Url; `IsSpellCheckEnabled` false; `IsTextPredictionEnabled` false | Enter in this field chooses the default button when it is enabled |
| Invalid message | `TextBlock`, `Caption`, secondary, below the fields, `editor.link.invalid`; shown only when the address is not empty and not valid; `AutomationProperties.LiveSetting` Polite so it is announced when it appears | Not red: the spec uses secondary text |
| Add link / Done | `PrimaryButton`: `editor.link.add` when adding, `common.done` when editing; `DefaultButton` Primary, `IsPrimaryButtonEnabled` false until the address is valid | Editing an inert link starts with the button disabled and the invalid message shown until the address is corrected, but Remove link is available |
| Remove link (editing only) | A standard `Button` `editor.link.remove` in the content, below the fields and separated from them, left-aligned; not red (the destructive treatment of [8.1](../platform.md#81-rules) needs no colour, and the action is undoable) | Takes the link off (L-9) and closes the dialog. Not styled as the primary |
| Cancel | `CloseButton`, `common.cancel`; Esc | |

Valid addresses are the spec's: `http:`, `https:` or `mailto:` in any letter case with a host (web) or an `@` (mail), or without a scheme an email address (becomes `mailto:`) or a host name with a domain (becomes `https:`); surrounding spaces ignored; the scheme is stored in lower case; everything else is refused (`localhost`, `name@host`, `javascript:`, `tel:` and so on). **Done (editing)** gives the whole link the new address and keeps the link's title and every character's formatting; text that differs from the link's own text replaces it, formatted as the link's first character was; empty text changes nothing (L-8). One undo step, named `editor.undo.editLink`. **Remove link** takes off every link the caret or selection touches, each one whole, even when the selection covers only part of it; text, formatting, pictures and titles stay, the selection stays where it was, text typed next does not continue the link, and it is one undo step named `editor.undo.removeLink` (L-9). Narrator is told `editor.link.removed` after any Remove link (a notification event, `MostRecent`), whether from the dialog, the Format menu or the context menu.

**Context menu on a link.** The text context menu shows Edit link… and Remove link in place of the control's own link items, only when the pointer is on a character of the link; Edit link… selects the whole link first, so the dialog and the selection agree.

The dialog applies the link to the selection captured when it opened, closes without animation where the dialog allows it, and returns focus to the text with the selection restored. Cancel and Esc close without changes. It closes without changes when the library locks, another entry opens or the journals are erased. When the text became shorter than the captured link while the dialog was open, the edit is skipped.

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium | 420 epx dialog, centred over the window | Mac sheet 420 × 220; iPad form sheet |
| Small | Fills the window width; the fields stack as at other widths | iPhone sheet |
| 200% text size or more | Fields and buttons grow; the dialog scrolls; no fixed height | |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `insert-link` | Format ▸ Insert ▸ Link… (Edit link… with the caret in a link); the formatting bar's Link button and Insert drop-down; the selection mini-toolbar; the context menu on a link (Edit link…); the dialog's primary button | Ctrl+K | The body has keyboard focus (a table cell too for Add link). Ctrl+K opens the dialog with the selected text as its Text (L-5), or the edit form with the caret in a link |
| `remove-link` | Format ▸ Insert ▸ Remove link; the context menu on a link; the Remove link button in the edit form | none | Dimmed unless the caret or selection touches a link; not in a table cell or the Markdown source |

- Enter in the address field adds a valid link; with an invalid or empty address it does nothing and the field keeps focus (the message is announced when the field is not empty).
- Esc cancels. Ctrl+K inside the dialog does nothing.

## Copy differences

Sentence case: "Add link" for `editor.link.title` and `editor.link.add`, "Edit link" for `editor.link.editTitle`, "Remove link" for `editor.link.remove` and `library.menu.format.insert.removeLink`, "Edit link…" for `library.menu.format.insert.editLink` ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)). The menu item `library.menu.format.insert.link` is "Link…" and keeps its ellipsis. No other differences.

## Accessibility

- Fields are labelled by their `Header`s (read before the value); the invalid message is announced when it appears and again when the person presses Enter on an invalid address.
- Focus starts in the address field; closing returns it to the text.
- Narrator reads the dialog title and the first field on open. The disabled Add link button stays in the tab order and reads as dimmed.

## Different by design

- **Headers instead of placeholders.** Apple labels the fields with placeholders; Windows uses visible `Header`s, which remain when text is typed.
- **Enter relies on the default button**, not a Return key handler; the result is the same as Notes' behaviour on the phone.

## Open questions

None.
