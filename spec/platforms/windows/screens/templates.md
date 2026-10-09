---
id: templates
title: Templates (Windows)
spec: screens/templates.md
features: [templates-collection, save-as-template, delete-entry, undo-delete]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/menus
---

# Templates (Windows)

The Templates collection of the [navigation pane](journals.md): the [entry list](entry-list.md) with templates instead of entries. Behaviour, errors and copy keys are the spec's [templates](../../../screens/templates.md). Only the differences from entry-list are written here.

## Controls

| Spec element | Control | Notes |
| --- | --- | --- |
| Title and subtitle | The list header's name and count: `library.journals.templates`, with `common.templateCount` or `library.entryList.empty.noTemplates` | As in [library-window](library-window.md) |
| The list | The entry list's `ListView` with template rows: month groups by the template's date, newest first, no Pinned group, no journal label | Row text as entry-list (`library.entryList.untitledEntry` fallback) |
| Selecting a template | Opens it in the [entry editor](entry-editor.md), edited like an entry | A template saved by a newer version opens read-only |
| Template context menu and Entry actions | `MenuFlyout`, one list for the row's `ContextFlyout` and the editor header's More menu ([5](../platform.md#5-context-menus)) | Items below |
| Empty state | Centred secondary `TextBlock` `library.entryList.empty.noTemplates` with `library.entryList.empty.noTemplatesHelp` under it, read as one element | New libraries start here |
| Search without results | `library.entryList.empty.noResults` and a `Button` `library.entryList.empty.clearSearch` | |
| Swipe | `SwipeControl`, trailing Delete as Delete template; no Pin | Touch and pen only |

### Context menu and Entry actions

| Item | Copy | Icon | Shown and enabled |
| --- | --- | --- | --- |
| Image descriptions… | `library.entryActions.imageDescriptions` | none | The template has pictures; enabled when descriptions can be edited |
| Version history… | `common.versionHistoryEllipsis` | History | Always |
| separator | | | |
| Delete template | `library.entryActions.deleteTemplate` | Delete | Editable and not deleted. Moves to Recently deleted at once; Undo brings it back |

A template is never used from this list: there is no New entry in, New entry from template or any other way to start an entry from a template here. A template is used from inside an empty entry ([template-chooser](template-chooser.md)). Errors use the general error dialog with the spec's messages.

## Layout at each window width

As [entry-list](entry-list.md). At small width Templates is a page of the stacked navigation under the Journals page, and the template opens as the next page.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `delete-entry` | Context menu; Entry actions (named Delete template); trailing swipe | Delete | Focus in the list |
| `image-descriptions` | Context menu; Entry actions | none | |
| `entry-version-history` | Context menu; Entry actions | none | |
| `new-entry` | The list header's button | as in commands.md | Creates an empty entry in the Default Journal, never from the selected template ([flows/new-entry](../flows/new-entry.md)) |

There is no New template command; Save as template… on an entry is the way ([entry-list](entry-list.md)). "Use a template" in an empty entry and File ▸ Use a template… open the chooser ([template-chooser](template-chooser.md)).

## Copy differences

Sentence case ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)): "Delete template". `library.entryList.empty.noTemplatesHelp` has a vocabulary proposal, in [entry-list](entry-list.md) (B26).

## Accessibility

As [entry-list](entry-list.md). Template rows carry the value `library.entryList.templateValue`.

## Different by design

None beyond entry-list. The Apple note that iOS 26 opens the sub-menu in place does not apply.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): B26 (select and choose).
