---
id: template-chooser
title: Template chooser (Windows)
spec: screens/template-chooser.md
features: [template-chooser, new-entry-from-template, template-suggestion]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/flyouts
---

# Template chooser (Windows)

A quick, keyboard-friendly list of templates to start an entry from or fill an empty one. Behaviour, rules and copy keys are the spec's [template-chooser](../../../screens/template-chooser.md).

## Controls

One `Flyout` (`Placement` Bottom, `ShowMode` Standard so light dismiss and Esc work), 320 epx wide, at most 400 tall, content scrolling inside. Reopening starts fresh: no text, highlight or error.

| Spec element | Control | Notes |
| --- | --- | --- |
| Journal picker | `ComboBox`, header `library.templateChooser.journal`, items the journals in use in the pane's order (`common.untitledJournal` when blank); starts on the journal last opened on this device, else the Default Journal | Only when opened from New entry from template… outside a journal, with two or more journals in use |
| Search field | `TextBox`, placeholder `library.search.templates`, focused on open, no autocorrection (`IsSpellCheckEnabled` false, `IsTextPredictionEnabled` false) | Matches template names, case-insensitively |
| List of templates | `ListView`, `SelectionMode` Single, rows at least 40 epx, name only; a duplicate name gets `library.templateChooser.duplicateName` | The highlighted row uses the system selection visual. Empty: `library.entryList.empty.noTemplates`; no match: `library.entryList.empty.noResults` |
| Error text | `InfoBar`, Severity Error, not closable, above the list | `library.templateChooser.templateGone`, `library.merge.destinationGone`, `library.templateChooser.journalGone`, or the creation error |
| Busy | An indeterminate `ProgressBar` along the top; every control disabled; light dismiss and Esc ignored while creating | |
| Title and Cancel | Not shown | A Windows flyout has no title or Cancel button; Esc and light dismiss close it. See B30 |

### Entry points

1. **File ▸ New entry from template…** (`new-entry-from-template`): the flyout is anchored to the New entry button of the list header (to the list header itself when that button is in the overflow menu, and to the title bar menu button at small width). Enabled when New entry is possible and a template exists.
2. **The link in an empty entry's placeholder** ([entry-editor](entry-editor.md)): anchored to the link. At small width the flyout fills the width.

### Choosing

Click or tap a row, or type to filter, Up and Down to move the highlight, Enter to choose (Enter works before anything is typed once a row is highlighted). When the open entry's body is empty (whitespace at most, no pictures) and, with the picker, the entry is in the picked journal, the template fills that entry's body in place as one change (the title is kept; the title takes focus if empty); this is always so for entry point 2. Otherwise a new entry is created from the template in the target journal and opens with its title focused. The flyout closes.

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium | The 320 epx flyout | Mac popover; iPad popover |
| Small | The flyout fills the window width, anchored below the title bar | iPhone sheet (half height, expandable) |
| Text size | The height grows with text size up to the window; the list scrolls | |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `new-entry-from-template` | File menu | none | New entry is possible and a template exists |
| `use-a-template` | The link in an empty entry's placeholder | none | Shown when the body has no text or pictures, it can be edited and an editable template exists |

- Keyboard order: picker, search field, list. Enter chooses; Down from the search field moves into the list; Esc closes **unless an input method is composing**, in which case Esc belongs to the input method. The search `TextBox` tracks `TextCompositionStarted` and `TextCompositionEnded` and ignores Esc while a composition is open ([25](../platform.md#25-text-input-and-spelling)).
- After closing with Esc focus returns to the control that opened the flyout, or to the editor for the placeholder link.

## Copy differences

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `library.templateChooser.title`, `library.templateChooser.popoverTitle` | Choose a Template; Use a Template… | not shown | removed (see B30) |
| `library.templateChooser.templateGone`, `library.templateChooser.journalGone` | … Choose another template. / … choose a journal. | … Select another template. / … select a journal. | vocabulary (see B26) |
| `library.templateChooser.journal` | Journal (Mac: Journal:) | Journal | none: the default is used, the colon is a Mac form |

Sentence case: "Use a template" for `library.templateChooser.useTemplate`.

## Accessibility

- The flyout is announced by its first control's name; the search box has the name `library.search.templates`, the list is named by `library.templateChooser.useTemplate`.
- The highlighted row is the selected item. Narrator reads the picker as "Journal, {name}".
- Errors appear as an `InfoBar` and so are announced when they open.
- The placeholder link is read as `library.templateChooser.useTemplate`.
- Focus goes to the search box when the flyout opens, as the spec says, even when the picker is shown above it; the picker is reached with Shift+Tab.

## Different by design

- **No title and no Cancel.** Windows flyouts close with Esc and light dismiss.
- **One flyout at every width**, not a sheet in one place and a popover in another.
- **Anchor.** The Mac menu command opens a sheet; Windows has no menu-anchored sheet, so the flyout hangs off the New entry button.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): B26 (select and choose), B30 (strings never shown).
