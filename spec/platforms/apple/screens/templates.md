---
id: templates
title: Templates (collection) (Apple)
spec: screens/templates.md
features: [templates-collection, new-entry-from-template, save-as-template, delete-entry, undo-delete]
devices: [iphone, ipad, mac]
status: verified
sources:
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Views/Mac/RootView+MacWindow.swift
  - apps/apple/JournalApp/Model/TemplateSuggestion.swift
  - apps/apple/JournalApp/Model/JournalNavigation.swift
  - docs/design/template-journal-choice-2026-10-03.md
  - docs/design/no-built-in-templates-2026-10-04.md
screenshots:
  - screenshots/iphone/templates-default.png
  - screenshots/ipad/templates-default.png
  - screenshots/mac/templates-default.png
---

# Templates (Apple)

Implements [screens/templates](../../../screens/templates.md). Templates are shown by the same list view as entries ([entry-list](entry-list.md)), so this page records only what differs: the rows, the context menu and the empty state. Choosing a template to start an entry from the editor is [template-chooser](template-chooser.md); the flow is [new-entry](../flows/new-entry.md).

## Controls

- **Collection.** `JournalDestination.templates`; `AppModel.showingTemplates` makes `listedEntries()` return `kind == "template"` items that are not deleted, sorted by date newest first, ties by identifier. Notice that this order is not alphabetical, and templates created in the same second sort by id, so two devices can list the same templates in a different order (the three screenshots do). `model.templates` (sorted by title) is a separate property used by menus and the chooser. `entryGroups` has no Pinned group here (`showsPinnedSection` is false), only month sections.
- **Title.** iOS navigation title `library.journals.templates`; Mac window title the same and subtitle `common.templateCount` or `library.entryList.empty.noTemplates` (`collectionSubtitle`).
- **Row.** The shared `entryRow`: date, `displayTitle` (a blank template title shows the first line of its text, or the text for `library.entryList.untitledEntry`), one-line preview. No journal label and no pin state. The accessibility value is empty here (the value `library.entryList.templateValue` is used only for template rows inside Recently Deleted).
- **Opening.** `model.select(id)` as for entries; the template opens in the same editor (`NativeEditor`), editable when `canEdit` (`draft.kind == "template"`).
- **Context menu and Entry Actions** (`entryActionCatalog` with `entry.kind == "template"`): the first item is the template's New Entry action, then a separator, then Image Descriptions… when it has pictures, Version History…, a separator and Delete Template (`library.entryActions.deleteTemplate`, `trash`, destructive). There is no Pin, Change Date, Move or Save as Template.
  - **New Entry In** (`library.entryActions.newEntryIn`, `square.and.pencil`): `model.newEntryFromTemplateAction` returns `MenuAction.submenu` when two or more journals are in use, with one command per journal in the sidebar order (`JournalNames.displayName`, no checkmark, no separators). On iOS 26 SwiftUI opens the submenu in place; on the Mac it is an `NSMenu` submenu in the toolbar's Entry Actions menu. With one journal or none it is a single `library.entryActions.newEntryFromTemplate` command, disabled with none. It is enabled by `canStartEntry(fromTemplate:)`: a journal exists, no save failure, unlocked, library not being replaced, the template has no changes to review. A template this version can only read (`document.isEditable` false) gets no New Entry item because the catalog only adds it when `offersDelete` holds.
  - The action calls `RootView.startEntry(fromTemplate:in:)`, which runs `model.newEntry(fromTemplate:in:)`: it saves the open item, reads the library again, then reports `messages.generic.journalNamedUnavailable`, `messages.generic.journalUnavailable`, `messages.generic.templateUnavailable` or `messages.generic.templateNeedsReview` in the general error alert, or creates a new entry (`filling: false`, so an open empty entry is never filled) in that journal; the list switches to the journal, the entry opens and its title takes focus. On iPhone `model.revealsSelection = true` rebuilds the stack as [journal list, entry].
- **Swipe.** Trailing `common.delete` as Delete Template through the same `delete(_:)` as entries, with Undo "Delete Template"; no leading swipe (`canPin` needs `kind == "entry"`).
- **Empty state.** `noTemplates` in `RootView`: a `VStack` of `library.entryList.empty.noTemplates` and `library.entryList.empty.noTemplatesHelp` (`.callout`, centered, `fixedSize` vertical so it wraps, with non-breaking spaces in "Save as Template" so the command's name stays on one line), combined into one VoiceOver element (`.accessibilityElement(children: .combine)`). Search without results: the common `library.entryList.empty.noResults` with `library.entryList.empty.clearSearch`. A new library starts empty.
- **Model.** `AppModel` (`templates`, `newEntryFromTemplateAction`, `canStartEntry`, `newEntry(fromTemplate:in:)`, `saveTemplate`).

## Layout

Same as [entry-list](entry-list.md): Mac middle column with lines between rows, iPad content column with grouped cards, iPhone a stacked page. Journal Actions is not shown over Templates on iPhone and iPad (it needs a journal); the Mac's Journal Actions menu holds New Journal… alone. New Entry in the bars still works and files an entry in the Default Journal with that journal's default template (not the selected template).

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `new-entry-in` | as in [commands.md](../commands.md) | | `canStartEntry(fromTemplate:)` and, for the submenu, two or more journals in use |
| `entry-actions` | as in commands.md | | A template is open |
| `delete-entry` | as in commands.md | Mac: Delete or ⌘⌫ in the focused list | `offersDelete` |
| `entry-version-history`, `image-descriptions` | as in commands.md | | Version History always; Image Descriptions with pictures |
| `new-entry` | as in commands.md | ⌘N | Creates in the Default Journal while Templates is shown |

Keyboard: the same list keys as [entry-list](entry-list.md) (Mac arrows, Delete). The submenu is a menu: arrow keys and Return in it are the system's.

## Copy differences

None.

## Accessibility

As [entry-list](entry-list.md). The New Entry In submenu reads "New Entry In, menu" (system menu trait); the empty state is one element.

## Differences between iPhone, iPad and Mac

- **Submenu.** iOS 26 opens it in place and the Mac builds it from an `NSMenu` in the toolbar, because the Mac's Entry Actions menu is AppKit; the contents are the same `MenuAction` list.
- **Delete shortcuts** (Delete, ⌘⌫) are Mac only, as for entries.
- Otherwise none: the list and the editor are the same code on every device.

## Screenshots

| iPhone | iPad | Mac |
| --- | --- | --- |
| ![iPhone: Templates page with August 2026 section and five templates](../screenshots/iphone/templates-default.png) | ![iPad: sidebar with Templates selected, template list, editor reads Select an Entry](../screenshots/ipad/templates-default.png) | ![Mac: title Templates and 5 templates, rows with a one-line preview](../screenshots/mac/templates-default.png) |

The row order differs between the captures because the seeded templates share one date.

## Source files

View:
- `apps/apple/JournalApp/Views/RootView.swift`: `entryActionCatalog` (the template branch), `startEntry(fromTemplate:in:)`, `noTemplates`, `emptyListState`.
- `apps/apple/JournalApp/Views/Mac/RootView+MacWindow.swift`: the Mac subtitle.

Model:
- `apps/apple/JournalApp/Model/TemplateSuggestion.swift`: `newEntryFromTemplateAction`, `canStartEntry`, `newEntry(fromTemplate:in:)`.
- `apps/apple/JournalApp/Model/JournalNavigation.swift`: the templates list and sorting.

Core: none specific.

Design records: `docs/design/template-journal-choice-2026-10-03.md`, `docs/design/no-built-in-templates-2026-10-04.md`.

## Open questions

None.
