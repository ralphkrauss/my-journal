---
id: template-chooser
title: Template chooser (Windows)
spec: screens/template-chooser.md
features: [template-chooser, template-suggestion]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/flyouts
---

# Template chooser (Windows)

A quick, keyboard-friendly list of templates that fills the empty entry that is open. It is the one way to start from a template: New entry gives a blank entry, and the chooser is opened from inside it. The chooser never creates an entry. Behaviour, rules and copy keys are the spec's [template-chooser](../../../screens/template-chooser.md).

## Controls

One `Flyout` (`Placement` Bottom, `ShowMode` Standard so light dismiss and Esc work), 320 epx wide, at most 400 tall, content scrolling inside. Reopening starts fresh: no text, highlight or error.

| Spec element | Control | Notes |
| --- | --- | --- |
| Search field | `TextBox`, placeholder `library.search.templates`, focused on open, no autocorrection (`IsSpellCheckEnabled` false, `IsTextPredictionEnabled` false) | Matches template names, case-insensitively |
| List of templates | `ListView`, `SelectionMode` Single, rows at least 40 epx, name only; a duplicate name gets `library.templateChooser.duplicateName` | The highlighted row uses the system selection visual. Empty: `library.entryList.empty.noTemplates`; no match: `library.entryList.empty.noResults` |
| Error text | `InfoBar`, Severity Error, not closable, above the list | `library.templateChooser.templateGone` (the highlighted template left, or the last one was deleted: the list then shows `library.entryList.empty.noTemplates`) |
| Title and Cancel | Not shown | A Windows flyout has no title or Cancel button; Esc and light dismiss close it. See B30 |

### Entry points

1. **The link in an empty entry's placeholder** ([entry-editor](entry-editor.md)): the flyout is anchored to the link. At small width it fills the width.
2. **File ▸ Use a template…** (`use-a-template`, no shortcut): the flyout is anchored to the editor's writing area (to its top edge when the placeholder is not in view). The menu item is enabled exactly when the link is shown and dimmed, not hidden, otherwise. It gives keyboard, Voice Control and Narrator users a menu route to the action.

### Choosing

Click or tap a row, or type to filter, Up and Down to move the highlight, Enter to choose (Enter works before anything is typed once a row is highlighted). The template fills the open entry's body in place, with its formatting and pictures, as one change undone by one Undo ([editing-rules](../flows/editing-rules.md)); the title is kept, and takes focus if it is empty. The flyout closes. If the entry's body is no longer empty (text typed or synced in meanwhile), nothing changes: the flyout closes and the general error dialog shows `library.templateChooser.entryChanged`, and focus returns to the entry. If the entry itself was closed or deleted meanwhile, the flyout just closes. Nothing is ever created: there is no journal to pick.

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium | The 320 epx flyout | Mac popover; iPad popover; the Mac and iPad menu route is a sheet |
| Small | The flyout fills the window width, anchored below the title bar | iPhone sheet (half height, expandable) |
| Text size | The height grows with text size up to the window; the list scrolls | |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `use-a-template` | The link in an empty entry's placeholder; File menu | none | The link is shown: the body has no text or pictures, it can be edited and an editable template exists |

- Keyboard order: search field, list. Enter chooses; Down from the search field moves into the list; Esc closes **unless an input method is composing**, in which case Esc belongs to the input method. The search `TextBox` tracks `TextCompositionStarted` and `TextCompositionEnded` and ignores Esc while a composition is open ([25](../platform.md#25-text-input-and-spelling)).
- After closing with Esc focus returns to the control that opened the flyout, or to the editor for the placeholder link.

## Copy differences

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `library.templateChooser.title`, `library.templateChooser.popoverTitle` | Choose a Template; Use a Template… | not shown | removed (see B30) |
| `library.templateChooser.templateGone` | … Choose another template. | … Select another template. | vocabulary (see B26) |

Sentence case: "Use a template" for `library.templateChooser.useTemplate`.

## Accessibility

- The flyout is announced by its first control's name; the search box has the name `library.search.templates`, the list is named by `library.templateChooser.useTemplate`. The menu item reads `library.menu.file.useTemplate`.
- The highlighted row is the selected item.
- The inline error appears as an `InfoBar` and so is announced when it opens; `library.templateChooser.entryChanged` is read like any error dialog.
- The placeholder link is read as `library.templateChooser.useTemplate`.
- Focus goes to the search box when the flyout opens, as the spec says.

## Different by design

- **No title and no Cancel.** Windows flyouts close with Esc and light dismiss.
- **One flyout at every width**, not a sheet in one place and a popover in another.
- **Anchor.** The Mac and iPad menu command opens a sheet; Windows has no menu-anchored sheet, so the flyout hangs off the editor, as it does for the link.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): B26 (select and choose), B30 (strings never shown).
