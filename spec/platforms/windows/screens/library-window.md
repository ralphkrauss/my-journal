---
id: library-window
title: Library window (Windows)
spec: screens/library-window.md
features: [three-column-layout, stacked-navigation, editor-only, previous-next-entry, text-size, state-restoration, new-entry, search-entries]
status: draft
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/navigationview
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/title-bar
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/command-bar
---

# Library window (Windows)

The shell every other page sits in. [platform.md](../platform.md) sections [2](../platform.md#2-app-shell-and-window), [4](../platform.md#4-menus-and-toolbars) and [7](../platform.md#7-keyboard-shortcuts) decide the shell; this file applies them to the spec's [library window](../../../screens/library-window.md) and says what the other pages can rely on. Behaviour, states and copy keys are the spec's.

## Controls

| Spec element | Windows control | Notes |
| --- | --- | --- |
| The window | `Window` with `ExtendsContentIntoTitleBar`, `MicaBackdrop`, one `AppWindow`. The minimum size (360 × 420 epx) is enforced through the windowing API, not by clipping | [platform.md, 2](../platform.md#2-app-shell-and-window). Default 1100 × 720 epx |
| Window title (taskbar, Alt+Tab, Task View, Narrator, window pickers) | `AppWindow.Title` | `library.app.name` in every state, never the collection's name and not `settings.title` while the Settings page is open: a window title is readable by every process, and a journal name is more private than the text capture exclusion hides (B29). The title bar itself also says `library.app.name` |
| Title bar | `TitleBar` (tall, 48 epx): pane toggle, app icon, `library.app.name`, `MenuBar`, drag region, Sync status (only when sync needs the person, D47), caption buttons | The menu bar holds every command ([4.1](../platform.md#41-where-the-menu-bar-sits)). Back button in the small layout and while a page (Settings, a task page, a history or the Image descriptions page) is open. **On the lock page and the first-launch pages the menu bar and pane toggle are not shown**; the title bar holds the icon, the name, one More button (Help and Exit; Settings too on the first-launch pages) and the caption buttons |
| Journals and collections | `NavigationView`, left pane, `OpenPaneLength` 240 epx, with the journals as a `ListView` in its custom content ([2.1](../platform.md#21-controls)) | Content in [journals](journals.md). Settings is the **built-in Settings item** (`library.toolbar.settings`, gear, last item), handled in `ItemInvoked` so the open entry is saved first; it opens the Settings page, not a pane of its own because Windows keeps Settings in the window ([10](../platform.md#10-settings)) |
| Entry list | A pane with a header and a `ListView` | Content in [entry-list](entry-list.md), [templates](templates.md), [recently-deleted](recently-deleted.md), [search](search.md) |
| Column divider | CommunityToolkit `GridSplitter` (or `ContentSizer`) between list and editor; the pane width is fixed | Keyboard-resizable (arrow keys on the focused splitter, 16 epx steps). The new width is remembered on this device |
| Editor | [entry-editor](entry-editor.md) in its own `Grid` column, text column at most 760 epx, centred, 24 epx margins | Same measure as the Apple window |
| Editor column with nothing open | A centred `TextBlock`, `library.window.selectEntry`, `TextFillColorSecondaryBrush`, `Body` | Not announced. With an empty list the column is blank; in Show editor only it shows what the empty list would ([entry-list](entry-list.md), States) |
| Loading after unlock | Blank list, no message, no progress ring | The spec forbids an empty state before the journals are read |
| Locked | The lock page replaces the window's content and every dialog hides | [platform.md, 13](../platform.md#13-device-authentication-and-app-lock); content in [screens/lock-screen](../../../screens/lock-screen.md) |
| Library being replaced | Notices above the editor as `InfoBar` (informational, not closable); New entry, editing and organising commands disabled | Notice and copy: [entry-editor](entry-editor.md), Controls |
| Erasing | Every dialog and flyout closes, then the window shows the first-launch page | [platform.md, 10](../platform.md#10-settings) |
| General error alert | `ContentDialog` with the error as content, Close button `common.ok`, no title | Different by design: [8.1, rule 3](../platform.md#81-rules). After a failed save the same dialog has Primary `common.tryAgain`, Close `common.ok` (copy `common.saveFailed`); the persistent notice is in [entry-editor](entry-editor.md) |
| Close or exit with an unsaved entry | `AppWindow.Closing` is cancelled until the save ends; if it fails, `ContentDialog` titled `messages.save.mac.title`, content `messages.save.mac.message`, Close button `messages.save.mac.keepOpen`, and the window stays open | [flows/save-entry](../../../flows/save-entry.md). Windows has no Quit, so the same dialog serves Alt+F4, the Close button and Exit |

### Command bars

The three bars of [4.2](../platform.md#42-command-bars) are `CommandBar`s (`DefaultLabelPosition` Right in the large layout, Collapsed in the medium layout; `IsDynamicOverflowEnabled` true).

| Bar | Item | Control | Copy | Notes |
| --- | --- | --- | --- | --- |
| Navigation pane, above the items | New journal | `AppBarButton`, icon NewFolder (E8F4) | `library.toolbar.newJournal` | Tooltip adds the shortcut |
| Entry list header | Collection name and count | Two `TextBlock`s: `Subtitle` style and `Caption` secondary | the collection's name; the count keys in the spec's Window title section | The Mac title and subtitle move here. Heading level 1 for Narrator |
| Entry list header | Search | `AutoSuggestBox` with the find icon, no suggestions | the prompt of [search](search.md) | In the list header rather than the editor bar, because it filters the list; hides with the list in Show editor only |
| Entry list header | New entry (primary) | `AppBarButton` with accent style and label | `library.menu.file.newEntry` | Keeps its label as the bar narrows |
| Entry list header | Journal actions | `AppBarButton` (More, E712) with a `MenuFlyout` | `library.toolbar.journalActions` | New journal… first, then the shown journal's actions ([journals](journals.md)); in Recently deleted with items and no search the Delete all button sits here instead |
| Editor header | Formatting | `AppToggleButton`, icon Font (E8D2), shows or hides the formatting bar under the header | `library.toolbar.formatting` | [format-sheet](format-sheet.md); shown selected while the bar is shown; also View ▸ Formatting |
| Editor header | Insert image | `AppBarButton`, icon Picture (E8B9) | `library.toolbar.insertImage` | Opens the picker directly: [insert-image](../flows/insert-image.md) |
| Title bar, trailing area (every width, D47) | Sync status | `Button` with an `InfoBadge`, shown only when sync needs the person; its place is kept so nothing moves | `messages.syncStatus.title` | One place on every page and at every width, reachable from Settings too. Page and states: [sync-status](sync-status.md) |
| Editor header | Entry actions | `AppBarButton` (More) with a `MenuFlyout` | `library.toolbar.entryActions` | One list with the row context menu ([entry-list](entry-list.md)) |

Show editor only and View source / View preview are View-menu commands with shortcuts, not buttons: Full screen (F11) and Snap layouts already give Windows people the editor-only view, Notepad puts its view switch in the View menu, and the header is the busiest bar. Enabled states are the spec's: New journal while a library is open and unlocked; New entry also not while the library is being replaced; Formatting (the toggle always; its buttons while the open item can be edited), Insert image while the open item can be edited; View source while the open item can be edited and not for a source-only entry; Entry actions while an entry or template is open and not for a deleted journal.

## Layout at each window width

Breakpoints and rules are [platform.md, 2.2](../platform.md#22-layout-by-window-width); the pieces below are specific to this window.

| Width (epx) | Layout | Apple equivalent |
| --- | --- | --- |
| Large, 1008 and up | `NavigationView` open (240) · list (300 to 460, default 340) · editor (at least 439). Menu bar in the title bar | Mac three columns; iPad regular width |
| Medium, 641 to 1007 | `NavigationView` in minimal mode (`CompactModeThresholdWidth` and `ExpandedModeThresholdWidth` both 1007, [2.2](../platform.md#22-layout-by-window-width)): the title bar's pane button opens it as an overlay that closes after a choice · list (280 to 420, default 300) · editor (at least 360). Choosing a collection closes the overlay | iPad narrower than 1,000 points |
| Small, 640 and down | Stacked pages in a `Frame`: Journals, then the collection's entries, then the entry. The `NavigationView` pane is not used: the Journals page is a `ListView` with the same items. The title bar back button, Alt+Left and the mouse back button go back. The menu bar becomes one More button ([4.1](../platform.md#41-where-the-menu-bar-sits)) | iPhone; iPad at compact width |
| Text size 200% or more | One layout narrower than the width would give | iPad at accessibility text sizes |

- Command bars lose labels first, then items go to the overflow menu from the end. Sync status goes first. At 225% text size a bar shows icons and overflow only.
- The list header's search box collapses to a search icon button below 340 epx of list width and expands in place when pressed or when Ctrl+E is used.
- The first build reviews the chrome (title bar, menu bar, command bars, formatting bar and navigation pane) at the default 1100 × 720 epx and removes an icon or a row before adding a feature.
- Switching layouts keeps the open entry, unsaved writing and the selection. Focus moves to the list or the editor, never to a hidden column.
- Show editor only hides the pane and the list together and works in the large and medium layouts. The editor then fills the window, its text column still at most 760 epx. Searching (Ctrl+E) and New journal leave it first. Entering it moves focus to the editor. Full screen (F11) is independent of it.
- **Restoring state.** On this device only, in local settings: window position, size and maximised state (clamped to the visible work area), list width, whether Show editor only was on and what it replaced, and the last journal and entry by the spec's rules. Text size is not remembered.

## Commands and shortcuts

Shortcuts, menu placement and scopes are in [commands.md](../commands.md); only what this window adds is stated here.

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `new-entry` | File menu; New entry in the list header | as in commands.md | As in the spec. The button works with no journal in use (it opens New journal first); the menu item needs one |
| `new-journal` | File menu; button above the navigation pane items; pane context menu | as in commands.md | A library is open and unlocked. Leaves Show editor only first |
| `journal-actions` | List header More button | as in commands.md | A library is open and unlocked |
| `show-editor-only` | View menu | as in commands.md | Not at small width |
| `toggle-sidebar` | View menu; the title bar pane button | as in commands.md | Large and medium layouts. From Show editor only it shows every pane |
| `previous-entry`, `next-entry` | View menu | as in commands.md | The spec's rules: list order with Pinned first, works while the list is hidden, disabled at either end and without a library |
| `zoom-in`, `zoom-out`, `actual-size` | View menu; Ctrl+mouse wheel and touchpad pinch in the editor | as in commands.md | Actual size is disabled at the default. Range 12 to 30; multiplied by the system text size ([22](../platform.md#22-typography)) |
| `search-entries` | Edit menu; list header search box | as in commands.md | Focuses the search box; shows a hidden list first |
| `enter-full-screen` | View menu | F11 | Always |
| `open-settings` | The built-in Settings item; File menu | as in commands.md | Saves the open entry first; not while locked |
| `quit`, `close-window` | File ▸ Exit; Close button | Alt+F4 | See Controls: the save finishes first |
| `entry-actions`, `show-formatting`, `insert-image-choose-file` | Editor header | as in commands.md | Enabled states as above |
| `view-source` | View menu | as in commands.md | Enabled states as above |
| `sync-status` | Title bar, trailing area | as in commands.md | Only when sync needs the person |

Keyboard behaviour of the window:

- F6 and Shift+F6 move focus between the navigation pane, the list, the formatting bar (when shown) and the editor, skipping a hidden one. Tab inside the editor types a tab only where the spec says so; F6 always leaves it ([24](../platform.md#24-accessibility)).
- Ctrl+S finishes the open entry's save silently ([7.2](../platform.md#72-additions)). Alt+Left goes back in the stacked layout.
- Arrow keys in the list and the pane are in [7.3](../platform.md#73-keys-in-lists-dialogs-and-choosers).

## Copy differences

Sentence case applies to every title and label as in [platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary) (for example `library.window.selectEntry` reads "Select an entry"). Beyond that:

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `library.menu.view.showSidebarAndList` | Show Sidebar and List | Show all panes | vocabulary (already in platform.md, 12.3) |
| `library.toolbar.editorOnly.help`, `library.toolbar.editorOnly.helpActive` | Show Editor Only (⇧⌘D), Show Sidebar and List (⇧⌘D) | Show editor only, Show all panes (no shortcut text) | shortcut text (platform.md, 12.3) |
| `messages.save.mac.title` | Couldn’t save changes on this Mac. | Couldn’t save changes on this PC. | vocabulary (platform.md, 12.3) |

## Accessibility

- Landmarks: the navigation pane is Navigation (name `common.journals`), the list header with the list is Search plus Main for the list, the editor is Main (name `editor.body.accessibilityLabel`). The window title is not read as a heading.
- Focus order: title bar menu bar, pane button, Sync status when shown, navigation pane, list header, list, editor header, formatting bar when shown, editor. After a layout change focus goes to the list or the editor.
- Closing the pane overlay returns focus to the pane button. After New entry focus is in the new entry's title ([flows/new-entry](../flows/new-entry.md)).
- Hiding a column (Show editor only, layout change) is announced by notification event only when focus moves; nothing else.
- Command bar buttons have names and tooltips; icon-only ones get `AutomationProperties.Name` from the label keys above. `AutomationProperties.AcceleratorKey` carries the shortcut.
- The window works in the four contrast themes (every brush is a theme resource, Mica falls back to solid), at 225% text size and with reduced motion ([21](../platform.md#21-theming-and-contrast)).

## Different by design

- **Window title.** Apple puts the collection name and count in the title bar. Windows names the app in the title bar and puts the collection and count in the list header; the window's own title (taskbar, Alt+Tab, Task View, window pickers) stays "My Journal" in every state. Reason: window titles are readable by every process, and a journal name is itself private; the Windows convention of "document - app" is not followed because the document name is a private category.
- **Journals are a `ListView`, Settings is the built-in item.** Reason: the journals are a person's own growing, reorderable list with counts, which Windows apps keep in a `ListView` or `TreeView`; Settings uses the platform's own item as Microsoft's guidance asks.
- **Show editor only and View source have no header buttons.** Reason: Windows has full screen and Snap layouts, and the header is the busiest bar; both remain in the View menu with their shortcuts.
- **Settings and Exit.** Apple has an app menu (and an iPad sidebar row). Windows has the built-in Settings item, the File menu and Ctrl+,; Exit sits in File. Reason: there is no application menu on Windows.
- **Search.** The Mac puts the search field at the far end of the editor toolbar. Windows puts it in the list header with the list it filters; the spec's rules (clearing, leaving Show editor only) are unchanged.
- **No Window menu, no Done in the editor, no Edit mode.** Windows window management is the system's; editing is always live, as on the Mac.
- **Several windows.** The iPad can show several windows. Windows version 1 has one ([3](../platform.md#3-windows-and-instances)).
- **Pane widths.** Lower minimums than the Mac (360 × 420) because windows are routinely snapped.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D38 (counts in the navigation pane), B29 (window title), D47 (where Sync status lives), D20 (menu bar, formatting bar and chrome on the lock page).
