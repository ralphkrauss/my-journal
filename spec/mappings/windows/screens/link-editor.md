---
id: link-editor
title: Add link (Windows)
spec: screens/link-editor.md
features: [links, inert-links]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
---

# Add link (Windows)

Turns the selected text into a link to a web page or an email address, or inserts a new link. Behaviour, address rules and copy keys are the spec's [link-editor](../../../screens/link-editor.md); the editing result follows rules L-1 to L-6 of [flows/editing-rules](../flows/editing-rules.md).

## Controls

A `ContentDialog`, 420 epx wide, opened over the window.

| Spec element | Control | Notes |
| --- | --- | --- |
| Title | `ContentDialog.Title`, `editor.link.title` | |
| Text field | `TextBox`, `Header` `editor.link.text`, filled with the selected text (empty when nothing is selected), editable | `AutomationProperties.Name` the same |
| Address field | `TextBox`, `Header` `editor.link.address`, empty, focused when the dialog opens; `InputScope` Url; `IsSpellCheckEnabled` false; `IsTextPredictionEnabled` false | Enter in this field chooses the default button when it is enabled |
| Invalid message | `TextBlock`, `Caption`, secondary, below the fields, `editor.link.invalid`; shown only when the address is not empty and not valid; `AutomationProperties.LiveSetting` Polite so it is announced when it appears | Not red: the spec uses secondary text |
| Add Link | `PrimaryButton`, `editor.link.add`, `DefaultButton` Primary, `IsPrimaryButtonEnabled` false until the address is valid | |
| Cancel | `CloseButton`, `common.cancel`; Esc | |

Valid addresses are the spec's: `http:`, `https:` or `mailto:` in any letter case with a host (web) or an `@` (mail), or without a scheme an email address (becomes `mailto:`) or a host name with a domain (becomes `https:`); surrounding spaces ignored; the scheme is stored in lower case; everything else is refused (`localhost`, `name@host`, `javascript:`, `tel:` and so on). There is no Edit link or Remove link: Add link on an existing link opens the same dialog, empty, and adding replaces the link on the selected text.

The dialog applies the link to the selection captured when it opened, closes without animation where the dialog allows it, and returns focus to the text with the selection restored. Cancel and Esc close without changes. It closes without changes when the library locks, another entry opens or the journals are erased.

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium | 420 epx dialog, centred over the window | Mac sheet 420 × 220; iPad form sheet |
| Small | Fills the window width; the fields stack as at other widths | iPhone sheet |
| 200% text size or more | Fields and buttons grow; the dialog scrolls; no fixed height | |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `insert-link` | Format ▸ Insert ▸ Link…; the formatting bar's Link button and Insert drop-down; the selection mini-toolbar; the dialog's primary button | Ctrl+K | The body or a table cell has keyboard focus. Ctrl+K opens the dialog with the selected text as its Text (L-5) |

- Enter in the address field adds a valid link; with an invalid or empty address it does nothing and the field keeps focus (the message is announced when the field is not empty).
- Esc cancels. Ctrl+K inside the dialog does nothing.

## Copy differences

Sentence case: "Add link" for `editor.link.title` and `editor.link.add` ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)). The menu item `library.menu.format.insert.link` is "Link…" and keeps its ellipsis. No other differences.

## Accessibility

- Fields are labelled by their `Header`s (read before the value); the invalid message is announced when it appears and again when the person presses Enter on an invalid address.
- Focus starts in the address field; closing returns it to the text.
- Narrator reads the dialog title and the first field on open. The disabled Add link button stays in the tab order and reads as dimmed.

## Different by design

- **Headers instead of placeholders.** Apple labels the fields with placeholders; Windows uses visible `Header`s, which remain when text is typed.
- **Enter relies on the default button**, not a Return key handler; the result is the same as Notes' behaviour on the phone.

## Open questions

None.
