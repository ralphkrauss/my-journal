# Windows conventions

The cross-cutting decisions every Windows mapping file follows. Each section says what the Apple app does, what the Windows app does instead, and why. A mapping file for one screen or flow ([README](README.md)) links here instead of repeating a convention, and records only what is specific to its screen.

Status: **proposal for owner review, revised after an independent design review** ([review-2026-10-06.md](review-2026-10-06.md)). The decisions that need the owner are collected in [open-questions.md](../../open-questions.md), section D (D20 to D54) and marked **Decision needed** below; where the review recommended a different default, the question and this file now follow the reviewer's recommendation and say so. Everything else follows from Microsoft's own guidance and is the default until the owner says otherwise. Guidance was checked on 2026-10-06; every section ends with the Microsoft pages it rests on.

How to read a section:

- Product rules stay: data safety, quiet saving and syncing, plain copy, no exclamation marks, nothing silently discarded, nothing of the journals shown while locked. Only their presentation changes.
- Where Windows has a standard control or convention, the Windows app uses it, even when the Apple app does something else. Where Apple behaviour is a feature rather than a convention (for example Show Editor Only), it stays, unless this file says otherwise with a reason.
- Sizes are in effective pixels (epx), the unit WinUI layout uses; the system scales them with the display's scale factor.
- Names in code font (`NavigationView`, `ContentDialog`) are Windows App SDK / WinUI 3 controls and APIs.

Contents: [1 Target and toolkit](#1-target-and-toolkit), [2 App shell and window](#2-app-shell-and-window), [3 Windows and instances](#3-windows-and-instances), [4 Menus and toolbars](#4-menus-and-toolbars), [5 Context menus](#5-context-menus), [6 Touch and swipe actions](#6-touch-and-swipe-actions), [7 Keyboard shortcuts](#7-keyboard-shortcuts), [8 Dialogs](#8-dialogs), [9 Sheets, popovers and notices](#9-sheets-popovers-and-notices), [10 Settings](#10-settings), [11 Progress and announcements](#11-progress-and-announcements), [12 Copy: casing, ellipses and vocabulary](#12-copy-casing-ellipses-and-vocabulary), [13 Device authentication and App Lock](#13-device-authentication-and-app-lock), [14 Secure storage](#14-secure-storage), [15 Clipboard](#15-clipboard), [16 Files and pickers](#16-files-and-pickers), [17 App data, backups and erasing](#17-app-data-backups-and-erasing), [18 Packaging, distribution and updates](#18-packaging-distribution-and-updates), [19 Single instance and activation](#19-single-instance-and-activation), [20 Screen capture and window privacy](#20-screen-capture-and-window-privacy), [21 Theming and contrast](#21-theming-and-contrast), [22 Typography](#22-typography), [23 Icons](#23-icons), [24 Accessibility](#24-accessibility), [25 Text input and spelling](#25-text-input-and-spelling), [26 Camera, photos and images](#26-camera-photos-and-images), [27 Sharing](#27-sharing), [28 Rating](#28-rating), [29 QR codes and Add Device](#29-qr-codes-and-add-device), [30 Sync, lifecycle and power](#30-sync-lifecycle-and-power), [31 Dates, time zones and formats](#31-dates-time-zones-and-formats), [32 Local network and servers](#32-local-network-and-servers), [33 Summary of departures from the Apple app](#33-summary-of-departures-from-the-apple-app), [34 Open questions](#34-open-questions).

## 1 Target and toolkit

| Topic | Windows | Why |
| --- | --- | --- |
| UI framework | WinUI 3 with the Windows App SDK (C#, XAML); Fluent 2 design language as shipped in WinUI 3 | The owner's brief: it must feel as if Microsoft built it. Earlier research recommended native C# and WinUI 3. |
| Extra controls | CommunityToolkit.WinUI (SettingsCard, SettingsExpander, Sizers) only where WinUI has no equivalent; each use is named in the mapping file | The toolkit is Microsoft-published and is what the Windows 11 Settings look is built from. New dependencies need documented reasons ([AGENTS.md](../../../AGENTS.md)). |
| Minimum OS | **Windows 11, build 22000 or later: a requirement.** The app does not target Windows 10, although WinUI 3 itself runs on Windows 10 version 1809 and later | The Windows Hello desktop call that App Lock and every other authentication use, `IUserConsentVerifierInterop.RequestVerificationForWindowAsync`, documents build 22000 as its minimum client, so App Lock cannot work on Windows 10 with the documented call. Windows 10 also reached end of support in October 2025, and Mica, rounded corners and snap layouts need Windows 11. Draft default of D22 (the owner confirms). |
| Packaging | Packaged (MSIX), see [18](#18-packaging-distribution-and-updates) | Identity is needed for the Store rating API and clean uninstall, and for the `.journalarchive` file association (D29). |
| Language and shared code | C#. The sync, crypto and document engine is a separate portable module; a mapping file never assumes where it lives | Decided later by the engine spike. A mapping file talks to it through interfaces only. |
| Units | epx. 1 epx = 1/96 inch at 100% display scale | WinUI's layout unit. |

The editor control is the largest open technical question for the Windows client: the platform rich-text control (`RichEditBox`) is RTF-based, while entries are Markdown with drawn list markers and checkboxes ([screens/entry-editor](../../screens/entry-editor.md)). **Two spikes run in parallel, not one after the other**: `RichEditBox` with an overlay layer (Spike A) and a `WebView2` block editor that serialises to Markdown (Spike B), each time-boxed, against one shared scorecard with written pass and fail criteria ([the entry-editor mapping, The spikes](./screens/entry-editor.md#the-spikes)); the owner decides (D30). This file only lists what any choice must satisfy: UI Automation text pattern, spelling, IME composition, undo steps per `flows/editing-rules`, and no formatting the document model can't store (see [7](#7-keyboard-shortcuts), built-in accelerators).

Sources: [Packaging overview](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/packaging/), [Rich edit box](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/rich-edit-box), [SettingsCard](https://learn.microsoft.com/en-us/dotnet/communitytoolkit/windows/settingscontrols/settingscard).

## 2 App shell and window

### Title bar and material

| Apple (Mac) | Windows | Why |
| --- | --- | --- |
| System title bar with the collection name and its count, toolbar integrated into it | A custom title bar (`ExtendsContentIntoTitleBar`) using the `TitleBar` control (Windows App SDK 1.7 or later): pane toggle, app icon, title `library.app.name`, the menu bar ([4](#4-menus-and-toolbars)), a drag region, and the system caption buttons. Tall height (48 epx) because it holds interactive content. | This is the Windows 11 pattern for apps with a navigation pane; the system keeps snap layouts, caption button colours and high-contrast behaviour. |
| Window title shows the collection and a subtitle count | The title bar says "My Journal". The collection name and its count are the header of the entry list pane ([screens/library-window](../../screens/library-window.md), Window title). **The window's own title (taskbar tooltip, Alt+Tab, Task View, Narrator) stays "My Journal" in every state**, never the collection's name, and the Settings page does not change it | A window title is readable by every process: Task Manager, the taskbar, window pickers in Teams, Zoom and the Snipping Tool, accessibility tools and Recall's metadata. A journal called "Therapy" is more private than the text that capture exclusion hides ([20](#20-screen-capture-and-window-privacy)). Windows convention would add the document name; here the document name is a private category. An optional Privacy setting that adds the collection name, off by default, is the alternative in B29. |
| Vibrancy sidebar and standard window background | Mica as the window backdrop (`MicaBackdrop`); the navigation pane is translucent over Mica; the list and editor sit on the solid content layer, which in Windows 11 is a rounded layer over Mica (the content area beside the pane, `LayerFillColorDefaultBrush`, `OverlayCornerRadius`), as in Windows 11 Settings; it is not drawn as a flat rectangle edge to edge. Falls back to solid colours when transparency effects are off, in contrast themes and when the window is inactive (the control does this itself) | Fluent 2 layering: Mica for long-lived windows, content on a layer above. Writing stays on a quiet, opaque surface. |
| No visible back button on the Mac | `TitleBar` back button in the stacked layout ([2.2](#22-layout-by-window-width)) and while a page (Settings, a review, a history or the Image descriptions page) is open at any width | Matches Windows apps with page stacks. |

### 2.1 Controls

Three columns map to these controls:

| Apple | Windows | Notes |
| --- | --- | --- |
| Sidebar (journals, collections) | `NavigationView`, left pane, for the shell: Templates, Recently deleted and Unavailable journals (when needed) are menu items, and Settings is **the built-in Settings item** (`IsSettingsVisible` true: gear, localised name, last item, pinned; the app handles `ItemInvoked` and `IsSettingsInvoked` so it can save the open entry first). All entries and the journals are a `ListView` in the pane's custom content area, above those items. `OpenPaneLength` is set to 240 epx on purpose (the default is 320) | The standard left navigation of Windows 11 apps, and Microsoft's app-settings guidance says to use the built-in Settings item. `NavigationView` is for a handful of top-level sections; a person's own list of journals is data that grows, has counts and is reordered, and such lists (Mail's folders, OneNote's notebooks) are a `ListView` or `TreeView`. Counts are plain secondary text, not badges ([journals](screens/journals.md), D38). |
| Entries list | `ListView` in a pane with a header (collection name, count, search, actions) | Selection drives the editor. Grouping by month uses a grouped `CollectionViewSource` with sticky headers. |
| Editor (detail) | The editor control ([1](#1-target-and-toolkit)) in a page of its own, text column at most 760 epx, centred, 24 epx margins | Same measure as the Apple app. |
| Column dividers | A splitter between the list and the editor (CommunityToolkit Sizers); the navigation pane width is fixed | Windows has no draggable `NavigationView` pane. Remember the list width per device, not synced. |
| Reordering journals by drag | Drag within the journals `ListView` (`CanReorderItems`, `AllowDrop`), plus Move up and Move down items in the journal context menu | `NavigationView` items have no built-in reordering; a `ListView` does, and the context-menu route also gives keyboard, Narrator and switch users a way (see `reorder-journal` in [commands](commands.md)). |

The journals `ListView` and the `NavigationView` items share one selection (the current collection, kept in the model: choosing in one clears the other). This is planned as the primary design, so the first build does not discover late that `NavigationView` items cannot be reordered. If the two controls do not coexist cleanly in the pane (selection, keyboard order, the pane scrolling as one), the fallback is a `SplitView` whose pane is one sectioned `ListView` or `TreeView`, with Settings as a footer button of our own that saves first; the built-in Settings item is then lost. The look and behaviour stay the same, so mapping files must not depend on which is used.

### 2.2 Layout by window width

Breakpoints are the Windows responsive-design standard: small up to 640, medium 641 to 1007, large 1008 and up. They are **not** `NavigationView`'s default adaptive thresholds, which are Minimal at 640 and below, Compact (an icon rail) from 641 to 1007 and Expanded from 1008. The mapping wants a hidden pane at medium width, so it sets `CompactModeThresholdWidth` and `ExpandedModeThresholdWidth` both to 1007 (the example in the NavigationView documentation): Minimal below 1008, Expanded from 1008, no icon rail.

| Width (epx) | Layout | Apple equivalent |
| --- | --- | --- |
| Large, 1008 and up | Navigation pane open (240) · list (300 to 460, default 340) · editor (at least 439) | Mac three columns; iPad regular width |
| Medium, 641 to 1007 | Pane hidden (Minimal mode through the thresholds above: the title bar's pane button opens it as an overlay that closes after a choice) · list (280 to 420, default 300) · editor (at least 360) | iPad narrower than 1,000 points, where choosing a collection hides the sidebar |
| Small, 640 and down | Stacked pages: Journals, then the collection's entries, then the entry. The title bar back button (and Alt+Left and the mouse back button) goes back; the same journals list is the first page. The navigation pane is not used | iPhone stacked navigation; iPad at compact width |

Rules:

- The minimum window size is 360 × 420 epx. Windows app windows are routinely snapped to half or a third of a screen, so the minimums are lower than the Mac's (801 × 420) and the editor's minimum in the medium layout is 360, not 439. Different by design.
- Text scaling: when the system text size is 200% or more (`UISettings.TextScaleFactor` of 2.0 or more), use the next narrower layout (large becomes medium, medium becomes small), as the Apple app does at accessibility text sizes. Proposal; revisit after testing with a real screen reader and magnifier.
- Switching layouts never loses state: the open entry stays open, unsaved writing stays in the editor, and focus moves to the list or the editor, never to a hidden column.
- Reduced motion: when animation effects are off (`UISettings.AnimationsEnabled` is false), pane and page transitions are instant.
- The default window is 1100 × 720 epx, placed on the monitor the pointer or the previous window was on, clamped to the visible work area. The window's position, size and maximised state, the list width and the last collection and entry are remembered on this device only ([screens/library-window](../../screens/library-window.md), State restoration). Entry state follows the Apple rules; placement is a Windows addition.
- Show Editor Only (`show-editor-only`) hides the pane and the list together and works at the large and medium widths; at small width it is not offered because only one page shows. It is not full screen. It is a View-menu command with its shortcut and **has no button in the editor header**: Full screen (F11) and Snap layouts already give Windows people the same result, and the header is the busiest bar ([4.2](#42-command-bars)).
- Full screen (`enter-full-screen`) uses the full-screen presenter and F11. In full screen the title bar and menu bar hide and return when the pointer reaches the top edge.

### 2.3 Window states

Locked, loading, library being replaced, erasing and error states keep the rules in [screens/library-window](../../screens/library-window.md); the Windows differences are the notices (an `InfoBar` above the editor, [9](#9-sheets-popovers-and-notices)) and that dialogs close when the library locks ([8](#8-dialogs)).

Sources: [Title bar customization](https://learn.microsoft.com/en-us/windows/apps/develop/title-bar), [Title bar control](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/title-bar), [Title bar design](https://learn.microsoft.com/en-us/windows/apps/design/basics/titlebar-design), [Mica](https://learn.microsoft.com/en-us/windows/apps/design/style/mica), [Materials](https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/materials), [NavigationView](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/navigationview), [Screen sizes and breakpoints](https://learn.microsoft.com/en-us/windows/apps/design/layout/screen-sizes-and-breakpoints-for-responsive-design).

## 3 Windows and instances

| Apple | Windows | Why |
| --- | --- | --- |
| Mac: one journal window; closing it leaves the app running; menu commands reopen it; no tabs. iPad: several windows sharing one library, collection and open entry | One library window. The app is single-instance ([19](#19-single-instance-and-activation)). Closing the window closes the app after the open entry is saved (Alt+F4, the Close button, File ▸ Exit); there is no background or notification-area presence in version 1 | On Windows, closing the last window ends the app. A hidden running app would need a visible presence (tray icon, setting) that the product does not otherwise have, and would keep the library open and syncing unseen. **Decision needed** (D23). |
| `window-*` items (Minimize, Zoom, Bring All to Front, window list) | Not offered; the caption buttons, the taskbar and snap layouts (Win+Z) do this | Windows owns window management. |
| Several iPad windows share one model | The control layout allows more than one window in the process later (WinUI 3 supports it), all sharing one model like the iPad. Not in version 1 | Keeps the door open without adding a window menu now. |
| Save before closing or quitting; Keep Open alert if the save fails | Same rule on window close and on session end (`AppWindow.Closing` is cancelled until the save finishes, then the window closes; if the save fails, the close stays cancelled and the Keep Open dialog shows, [8](#8-dialogs)). Windows may end the process at sign-out or restart: the app handles the end-of-session message and holds shutdown back briefly (a shutdown block reason) while a save finishes. **A Microsoft Store update or a reinstall while the app runs ends it the same way** (a close or end-of-session message), so it takes the same save-first path, and the save tests include being closed by an update | See [flows/save-entry](../../flows/save-entry.md), [flows/save-failure](../../flows/save-failure.md). |
| Closing the window while a long action runs (connecting, importing, turning on encryption, exporting) | **One rule for all of them:** the close waits for the current atomic step to finish, then stops the action as Cancel would (a staged copy is discarded, nothing half-finished is kept, requests are withdrawn, unused access is given up), then the window closes after the save-first rule above. While the action is running its Cancel button may be disabled (a step that cannot be interrupted), but Alt+F4 and the Close button are never blocked; each flow's file states only what is discarded | The Apple app has Cancel only. On Windows the window's Close button is always there, so it needs one defined meaning instead of one per page |

Source: [Windows App SDK app lifecycle](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/applifecycle/applifecycle-single-instance).

## 4 Menus and toolbars

**Recommendation: a `MenuBar` is the complete command surface, and a `CommandBar` in each pane carries the frequent subset.** No command exists only on a toolbar, and every toolbar command is also in a menu.

| Choice | Why |
| --- | --- |
| `MenuBar` for all commands | The app has about 100 commands (a full Format menu, View, Edit, file operations). Microsoft's menu guidance offers the menu bar for several top-level menus in a row, and Notepad and Paint use one. It gives Alt access keys, shows every shortcut next to its command, and is fully reachable by keyboard and Narrator. The Apple apps have the same shape (menu bar plus toolbar). |
| `CommandBar` per pane for frequent actions | Windows 11 apps show frequent actions as labelled or icon buttons in a command bar, with the rest in the overflow menu; the Mac toolbar's sections map onto it directly. |
| No hamburger-only command model | A command only in a hamburger or "…" flyout is hard to discover and to reach with a screen reader. |

### 4.1 Where the menu bar sits

In the title bar's content area after the app icon and name, left to right: pane button, icon, "My Journal", then the `MenuBar` (File, Edit, Format, View, Help), then the drag region, then the Sync status button when sync needs the person (D47), then the caption buttons. In the small layout the menu bar becomes one menu button (More, E712) whose flyout holds the same menus as sub-menus; the commands and shortcuts are unchanged. **On the lock page and on the first-launch pages the menu bar and the pane button are not shown**: a row of disabled menus tells Narrator users the app has content and is noise to everyone else. The title bar then holds the icon, the name, one More button whose flyout has only Help and Exit (and Settings on the first-launch pages, where Settings and Import archive are the only commands that apply), and the caption buttons. Alt access to the menu bar and drag regions inside the title bar are checked in the first shell build.

Menus differ from the Mac's: no application menu (Settings and Exit move to File; About moves to Help), no Window menu.

| Menu | Items, in order (labels are the copy keys named in [commands](commands.md)) |
| --- | --- |
| File | New entry, New blank entry, New entry from template…, New journal…, Pin entry / Unpin entry, —, Import archive…, Export archive…, Export journals as Markdown…, —, Delete all in Recently deleted, —, Lock My Journal, —, Settings, Exit |
| Edit | Undo, Redo, —, Cut, Copy, Paste, Paste as plain text, Select all, —, Find, Find and replace, Find next, Find previous, —, Search entries |
| Format | As on the Mac and iPad: Bold, Italic, Underline, Strikethrough, Inline code, —, Paragraph, Heading 1 to 6, —, Bulleted list, Numbered list, Checklist, Mark as checked / unchecked, Block quote, —, Increase indent, Decrease indent, —, Insert ▸ (Code block, Table, Horizontal rule, —, Link…, Image…), Table ▸ |
| View | Show navigation pane / Hide navigation pane, Show editor only / Show all panes, —, Previous entry, Next entry, —, Formatting (a check mark when the formatting bar is shown), View source / View preview, —, Zoom in, Zoom out, Actual size, —, Full screen |
| Help | My Journal Help (F1), My Journal Support, Privacy Policy, Source Code on GitHub, —, Rate My Journal, —, About My Journal |

Rules:

- Items show their shortcut (the framework fills `KeyboardAccelerator` text) and, for the most common commands, a 16 epx icon from [23](#23-icons). Cryptic icons are left off; Microsoft advises icons only for common or well-known items.
- Disabled items stay visible and dimmed, with the Apple "enabled when" rules from [commands](commands.md). The whole Format menu is disabled while the open item can't be edited.
- Access keys: File F, Edit E, Format O, View V, Help H, with item access keys chosen per menu; Alt shows the key tips. Labels in this repository carry no ampersands: access keys are set with `AccessKey`, so they can be localised.
- Toggle items use `ToggleMenuFlyoutItem` (Show navigation pane) or swap labels as the Mac does (View source / View preview, Show editor only / Show all panes). Radio items are not needed.
- A menu item that opens a dialog or page needing more input ends in an ellipsis, see [12](#12-copy-casing-ellipses-and-vocabulary).
- The menu bar is a command surface, not navigation. Pane and page navigation is the `NavigationView`.

### 4.2 Command bars

| Pane | Items, leading to trailing | Apple toolbar section |
| --- | --- | --- |
| Navigation pane (above the items) | New journal (button) | Sidebar section: New Journal, sidebar button |
| Entry list header | Collection name and count (title and subtitle), search box (`AutoSuggestBox` with the find icon; placeholder is the search prompt), New entry (button, primary), Journal actions (More, E712) | List section: Journal Actions menu, search field (the Mac puts it at the far end) |
| Editor header | Formatting (toggle button that shows or hides the formatting bar below it), Insert image, Entry actions (More). Show editor only and View source are View-menu commands with shortcuts and are not on this bar; Sync status is in the title bar, not here | Editor section |
| Formatting bar (under the editor header, when shown) | A `CommandBar`: paragraph style `DropDownButton`, Bold, Italic, Underline, Strikethrough, Inline code, Link, Bulleted list, Numbered list, Checklist, Block quote, Decrease indent, Increase indent, Insert `DropDownButton`, and an overflow for the rest ([format-sheet](screens/format-sheet.md)). Beside it, a selection mini-toolbar: the text control's own command flyout, extended with Bold, Italic and Link | Notepad (2025) and Word, OneNote and Mail show formatting as a bar under the menus, with a setting or toggle to hide it; a popover with a column of buttons is Apple's idiom. See D20 |
| Title bar, trailing area | Sync status (shown only when sync needs the person) | One place at every width, reachable from every page and from Settings (D47) |

Rules:

- Buttons are labelled icon plus text where there is room (large layout), icon only with a tooltip in the medium layout, and move to the overflow menu from the end of the bar as the pane narrows. The primary New entry button keeps its label. `CommandBar` does this by itself with `DefaultLabelPosition` and `IsDynamicOverflowEnabled`.
- Every icon-only button has a tooltip with its name and shortcut and an `AutomationProperties.Name`.
- Sync status is not in a command bar, so it is never pushed into an overflow menu: it sits in the title bar's trailing area at every width (D47).
- The command bars cannot be customised.

Sources: [Menu flyout and menu bar](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/menus), [Command bar](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/command-bar), [Access keys](https://learn.microsoft.com/en-us/windows/apps/develop/input/access-keys), [Collection commanding](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/collection-commanding).

## 5 Context menus

| Apple | Windows | Why |
| --- | --- | --- |
| Context menus on entry rows, journal rows, the sidebar's empty area, template rows, pictures and table cells; the same items as the Entry Actions menu | `MenuFlyout` through `ContextFlyout` for rows and the navigation pane; `CommandBarFlyout` for a picture (primary commands Cut, Copy, Paste, Share; the rest secondary) and for table cells; the text selection flyout of the text control for spelling and the system text commands | Matches Windows: right-click, Shift+F10 and the Menu key open a context menu; touch long-press and pen press-and-hold do too. |
| Entry actions "…" menu built from one list shared with the context menu | One command list, two presentations: the entry row's `ContextFlyout` and the Entry actions `AppBarButton` flyout. The menu bar's File and Edit items for the same commands share the same `XamlUICommand` objects | One definition keeps labels, icons, shortcuts and enabled states identical everywhere. |

Rules:

- A context-menu item has an icon when Segoe Fluent Icons has a well-known glyph for it (Pin, Calendar for Change date, Move to folder, History for Version history, Rename, Delete, Copy, Share); an item with no such glyph (Image descriptions, Default template, Merge into) has none. A `MenuFlyout` reserves the icon column once one item has an icon, so the text stays aligned. Cryptic glyphs are never invented. Separators and order follow [screens/entry-list](../../screens/entry-list.md); Delete entry is last and uses the standard destructive treatment (no special colour is required).
- A context menu opened by keyboard appears at the focused row, not at the pointer.
- Each item first saves the open writing; if that fails, nothing happens ([commands](../../commands.md#toolbars-context-menus-and-swipes)); Pin and Unpin do not wait for the save, as [flows/save-entry](../../flows/save-entry.md) says (A36).
- Accelerators shown on context-menu items are scoped to the list with `ScopeOwner`, so Delete in the list does not fire while the editor has focus.

Sources: [Menus and context menus](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/menus-and-context-menus), [Command bar flyout](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/command-bar-flyout).

## 6 Touch and swipe actions

| Apple | Windows | Why |
| --- | --- | --- |
| Swipe actions on rows: leading Pin / Unpin (full swipe), Restore; trailing Delete (full swipe) | `SwipeControl` in the list item template, for touch and pen only: leading Pin / Unpin or Restore, trailing Delete, the same full-swipe behaviour | `SwipeControl` responds to touch and pen. A mouse or keyboard user never sees it. |
| Trackpad leading swipe on the Mac | Not offered | A precision touchpad swipe is a scroll on Windows. |

Rule: **a swipe action is never the only way.** Every swipe action is also in the row's context menu, in the Entry actions menu and, where Apple has one, on the keyboard (Delete in the list). The Windows list has no Edit mode and no reorder handles; journal reordering uses drag and the Move Up and Move Down items ([2.1](#21-controls)).

Source: [Swipe](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/swipe).

## 7 Keyboard shortcuts

Windows keyboards have Ctrl, Alt, Shift and the Windows key; the Mac's Command, Option and Control do not map one to one. The rules, in order:

1. **Command becomes Ctrl.** Standard text and window shortcuts follow Microsoft's list: Ctrl+Z, Ctrl+Y, Ctrl+X, Ctrl+C, Ctrl+V, Ctrl+A, Ctrl+F, Ctrl+N, Ctrl+B, Ctrl+I, Ctrl+U, Ctrl+K, Ctrl+Plus, Ctrl+Minus, Ctrl+0, F2, F3, F6.
2. **Where Windows has its own convention, it wins** (table below).
3. **Option becomes Shift or nothing; no shortcut uses Ctrl+Alt.** Windows reports AltGr as Ctrl+Alt, and on Belgian, French, German, Polish, Czech, Spanish and many other layouts AltGr plus a letter or a digit types characters (@, #, {, [, |, \, ~, ², ³ and more). A journal is long-form typing in the person's own language, so no command may swallow those chords: headings are Ctrl+Shift+1 to Ctrl+Shift+6 and Paragraph is Ctrl+Shift+0, not Ctrl+Alt+digit as in Word (D27). The set was checked for other Ctrl+Alt chords and has none. If Word's Ctrl+Alt+1 to 3 are ever added for muscle memory, they may be bound only after asking `ToUnicodeEx` whether the current layout produces a character for that chord, as Google Docs does.
4. **No shortcut text in the copy.** The framework appends the shortcut to tooltips and menu items and exposes it to Narrator (`AutomationProperties.AcceleratorKey`); copy keys that spell a Mac shortcut get a Windows variant ([12](#12-copy-casing-ellipses-and-vocabulary)).
5. **No two app or editor shortcuts are the same.** [commands](commands.md) lists every shortcut with its scope and the checker verifies that no two overlap.
6. **Neutralise the editor control's own accelerators.** A rich edit control binds Ctrl+E, Ctrl+L, Ctrl+R, Ctrl+J, Ctrl+1/2/5, Ctrl+Shift+> and similar for alignment, line spacing and font size. The document model has no such formats, so these keys do nothing in the editor (handle them in `PreviewKeyDown`); otherwise the editor would show formatting the stored Markdown cannot keep, which would be silent loss. `DisabledFormattingAccelerators` covers only Ctrl+B, Ctrl+I and Ctrl+U, so the rest is a deny-list that a future control version can outgrow: the keyboard test below runs on every Windows App SDK update.
7. **Accelerators are proved in the first shell build, not assumed.** Three WinUI 3 behaviours are shell-spike items with pass criteria: (a) a menu item's `KeyboardAccelerator` reaches the app while the editor control has focus, and the control's own handling of the same chord does not run first (pass: every chord in [commands](commands.md) fires its command once, in the editor, in a table cell and in the find box); (b) accelerators declared on window-level elements can still fire while a `ContentDialog` is open, so commands are gated by a modal-state flag as well as by their enabled rules (pass: with any dialog open, no menu accelerator acts on the library behind it); (c) Ctrl+Enter as a `KeyboardAccelerator` on a `ContentDialog` (rule 5 of [8.1](#81-rules)) works with focus inside a `PasswordBox` and a `TextBox` (pass: it clicks Primary exactly once from every field).
8. **Layouts.** Every accelerator is tested on the US, Belgian AZERTY, German QWERTZ and Polish programmer layouts, including that AltGr characters on each still type in the editor. Accelerators on punctuation keys (Ctrl+Plus, Ctrl+Minus, Ctrl+=, Ctrl+, and Ctrl+Shift+Q) are bound to virtual keys, which do not follow the printed key on AZERTY and others, so each is bound on the main row and on the numpad where both exist, and tested per layout.

### 7.1 Translation table

| Apple | Windows | Notes |
| --- | --- | --- |
| ⌘, Settings… | Ctrl+, Settings | Windows says Settings, never Preferences or Options. Ctrl+, is used by Windows Terminal and VS Code but is not in Microsoft's accelerator table, so Settings is also reachable from the navigation pane's built-in Settings item and the File menu. No ellipsis: it opens a page. |
| ⌘Q Quit | Alt+F4 / File ▸ Exit | Closes the window, which ends the app. "Exit" is the menu label Microsoft menus use. |
| ⌘W Close window | Alt+F4 | Ctrl+W is left free for a future per-entry close. |
| ⌘H, ⌥⌘H Hide | none | No Windows equivalent; Win+D and Win+M belong to the system. |
| ⌘Z, ⇧⌘Z Undo, Redo | Ctrl+Z, **Ctrl+Y** (Ctrl+Shift+Z also accepted) | Microsoft's list says Redo is Ctrl+Y. Ctrl+Shift+Z is accepted for muscle memory but not displayed. |
| ⌘F Find, ⇧⌘F Find and Replace…, ⌘G, ⇧⌘G | Ctrl+F, **Ctrl+H**, **F3**, **Shift+F3** | Microsoft: search and replace is Ctrl+H; next result is F3. Enter and Shift+Enter in the find bar also step. |
| ⌥⌘F Search Entries | **Ctrl+E**, also Ctrl+Shift+F | Ctrl+E moves to the search box in Explorer, Mail and Edge. |
| ⌘E, ⌘J (Use Selection for Find, Jump to Selection) | none | No Windows convention. |
| ⇧⌘⌫ Delete All in Recently Deleted | Ctrl+Shift+Delete | |
| ⌘⌫ / Delete (delete in the list) | **Delete** | Shift+Delete means permanent deletion in Windows. In Recently Deleted both ask to delete permanently; elsewhere Shift+Delete is not bound, because the app has no permanent delete outside Recently Deleted. Ctrl+Backspace deletes a word in text and is not bound in lists. |
| Rename… (no shortcut) | **F2** renames the focused journal | Microsoft: F2 renames an item. |
| ⌥⌘N New Journal… | **Ctrl+Shift+J** | Ctrl+Shift+N is New blank entry, the "new secondary item" of Microsoft's list. |
| ⌃⌘L Lock My Journal | **Ctrl+L** | Used by password managers; Win+L is the system lock and is untouched. |
| ⌃⌘S Show/Hide Sidebar | Ctrl+Shift+B | No standard exists; provisional. |
| ⇧⌘D Show Editor Only | Ctrl+Shift+D | |
| ⌥⌘↑, ⌥⌘↓ Previous, Next Entry | **Alt+Up, Alt+Down** | Ctrl+Alt+arrows have been display-driver hotkeys; Alt+Up and Alt+Down are unused in text. |
| ⌥⌘U View Source / View Preview | Ctrl+Shift+U | Ctrl+U is Underline. |
| ⌘+ ⌘− ⌘0 Zoom | Ctrl+Plus (also Ctrl+=), Ctrl+Minus, Ctrl+0; Ctrl+mouse wheel and touchpad pinch zoom the editor text between 12 and 30 | Microsoft's list. Mouse-wheel zoom is a Windows convention added to the commands. |
| ⌃⌘F Enter Full Screen | **F11** | |
| ⌘? Help | **F1** | |
| ⇧⌘X Strikethrough | Ctrl+Shift+X | |
| ⌥⌘C Inline Code | Ctrl+Shift+C | |
| ⌥⌘0 to ⌥⌘6 Paragraph, Headings | **Ctrl+Shift+0 to Ctrl+Shift+6** | Not Word's Ctrl+Alt+digit: that is AltGr+digit on many layouts (rule 3). The digit row keys are free in this set (lists are 7, 8 and 9). Ctrl+Shift alone only switches the input language when released without another key. |
| ⇧⌘7 / ⇧⌘9 Bulleted, Numbered | **Ctrl+Shift+8 / Ctrl+Shift+7** | The set used by Google Docs and Slack; Word's single Ctrl+Shift+L for bullets would be an orphan. |
| ⇧⌘L Checklist | Ctrl+Shift+9 | |
| ⇧⌘U Mark as Checked / Unchecked | Ctrl+Shift+Enter | The same chord as the iPad's text shortcut (⇧⌘Return). |
| ⌘' Block Quote | Ctrl+Shift+Q | An apostrophe key is awkward on many layouts. |
| ⌘] ⌘[ Indent | **Ctrl+M / Ctrl+Shift+M** | Word's indent keys; brackets need AltGr on many layouts. Tab and Shift+Tab in a list item, code or a table stay as on the Mac. |
| ⌘K Link | Ctrl+K | |
| ⌥⇧⌘V Paste and Match Style | Ctrl+Shift+V | The common "paste as plain text" chord. |
| Esc closes sheets and popovers; Return is the default button | Esc cancels a dialog and closes a flyout; **Enter** is the default button except where Apple uses ⌘Return | See [8](#8-dialogs). |
| ⌘Return (Connect, Merge journals (the connect flow's step), Add Device approve) | **Ctrl+Enter** | These steps have no default button, so Enter cannot choose them before the person has read; Ctrl+Enter is a `KeyboardAccelerator` on the page or dialog. Merge into (one journal into another) is a different command and has a normal default button. |

### 7.2 Additions

| Shortcut | Does | Why |
| --- | --- | --- |
| Ctrl+S | Finishes saving the open entry now, silently (no message). If the save fails the normal failure notice appears | People press it by habit; autosave stays quiet and nothing new is saved or shown. This is a hidden accelerator without a menu item. **Decision needed** (D27). |
| F6, Shift+F6 | Move between the navigation pane, the list, the formatting bar (when shown) and the editor | Microsoft's list assigns them to "next UI pane". |
| Alt+Left | Back on every page with a back button: the stacked layout, Settings pages, the task pages (Connect, Turn on encryption, Import archive) and the review, history and Image descriptions pages. Not in dialogs. A page with unsaved work or a running action asks first, by its own file's rule | Windows back convention. |
| Esc | **Not Back.** Esc dismisses transient surfaces only (a dialog, a flyout, a drop-down, the find bar, the search box) and cancels a drag; it never leaves a page, and it is not handled while an input method composes. On the pages that replace an Apple sheet, Cancel is a button | Back is Alt+Left and the back button in Windows; Esc as Back collides with "Esc cancels the open drop-down or dialog" and with IME composition |
| Esc in the search box | Clears the search, then leaves it | |

### 7.3 Keys in lists, dialogs and choosers

| Apple context | Windows |
| --- | --- |
| Entries list: ↑/↓ move and open; Delete or ⌘⌫ delete | `ListView`: ↑/↓ move and open the entry (selection follows focus), Home, End, Page Up/Down; Delete deletes; Shift+Delete in Recently Deleted deletes permanently; type-ahead jumps by title |
| Sidebar: ↑/↓ choose a collection; Esc cancels a drag | `NavigationView`: ↑/↓, Home, End; F2 renames; Esc cancels a drag |
| Template chooser: type to filter, ↑/↓, Return creates, Esc closes (not while an input method is composing) | A flyout with a filter box and a list: type to filter, ↑/↓, Enter chooses, Esc closes unless the input method is composing |
| Sheets: Return = default button, Esc = Cancel; Restore has no Return | `ContentDialog`: Enter = `DefaultButton` where set, Esc = the close button; Restore Journal and Restore Entry set no default button |
| Lock screen: Return = Unlock with {method} | Enter on the focused Unlock button; it takes focus when the lock screen appears |
| Create library: Return moves from Master Password to Verify, then creates | Enter in the first field moves to the second; Enter in the second field creates |

Sources: [Keyboard accelerators](https://learn.microsoft.com/en-us/windows/apps/develop/input/keyboard-accelerators), [Keyboard accessibility](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/keyboard-accessibility), [Keys and keyboard shortcuts (style guide)](https://learn.microsoft.com/en-us/style-guide/a-z-word-list-term-collections/term-collections/keys-keyboard-shortcuts).

## 8 Dialogs

| Apple | Windows | Why |
| --- | --- | --- |
| Alert (title, message, buttons) and sheet (a window-attached form with Cancel and a default button) | `ContentDialog` for both: a title (optional), content, and up to three buttons. Short forms (Change Date, Move Entry, Merge Into, Add Link, New Journal, Rename, Save as Template, passwords) live in the content area | `ContentDialog` is Windows' modal surface for confirmations, questions and short forms. Larger or multi-step content follows [9](#9-sheets-popovers-and-notices). |

### 8.1 Rules

1. **One dialog at a time per window.** A second `ContentDialog` opened while one is showing throws. So: a dialog service shows requests one after another, and **a dialog never opens another dialog.** Errors that arise inside a dialog show inline in its content (an `InfoBar`); a confirmation inside a short flow replaces the dialog's content or closes the dialog and opens the next. A flow with more than two steps or with progress is not a dialog at all but a task page ([9](#9-sheets-popovers-and-notices)). The Apple app layers alerts over sheets; mapping files must restate any such step as one of these.
2. **Set `XamlRoot`** to the window's content root before showing; otherwise it throws.
3. **Buttons and their order.** The affirmative actions are the leftmost buttons, and the safe action is the rightmost. Windows names them `PrimaryButton` (left), `SecondaryButton` (middle) and `CloseButton` (right). Apple puts Cancel on the left and the default on the right.

   | Apple alert or sheet | Windows buttons |
   | --- | --- |
   | A form with Cancel and a default action (Move, Merge into, Save, Create, Change) | Primary = the action's verb, as `DefaultButton` (Enter chooses it; it takes the accent style because it is the default button). Close = Cancel (`common.cancel`; Esc chooses it) |
   | A destructive confirmation (Delete Journal, Delete Permanently, Delete All, Stop Syncing, Erase, Revoke Access). One exception: the Erase warning when journals would be lost puts Export archive… first and as the default, with Erase second ([screens/settings-erase](screens/settings-erase.md), D44) | Primary = the verb that names the action (for example `settings.sync.stopSyncing.confirm`, `settings.erase.alert.erase`). Close = `common.cancel`. **No default button, or Close as the default**, so Enter never chooses the destructive action. The title is a question (`settings.sync.stopSyncing.title`); the content explains what stays and what goes |
   | An information or error alert with OK (`common.ok`) | Close only, labelled `common.ok`. The title is left out when it would only be `common.alertTitle`, because a Windows dialog title is the main instruction, and the message alone is clearer. Different by design |
   | An alert with a retry (Try Again, Keep Open) | Primary = `common.tryAgain` (or the retry verb), Close = the dismissing choice. Nothing is lost by dismissing |
   | Steps where Return must not be enough (Connect, Merge journals (the connect flow's step), Approve a device; ⌘Return) | No default button. Ctrl+Enter is a `KeyboardAccelerator` that clicks Primary; Enter does nothing unless focus is on a button. **`PrimaryButtonStyle` is set to the accent style explicitly**: the accent treatment is otherwise a side effect of being the default button, and these would show a neutral Primary next to Cancel |
   | Restore Journal and Restore Entry (no Return shortcut) | No default button |

4. **Casing and wording.** Button labels are sentence case, except "OK", which stays "OK" ([12](#12-copy-casing-ellipses-and-vocabulary)). Buttons name the response ("Delete", "Stop syncing"), not "Yes" or "No".
5. **Locking closes every dialog.** When the library locks, dialogs hide with no result (the Apple "every sheet and prompt closes" rule), and anything a swipe or a pending delete had removed comes back. The system's own Windows Security prompt is not a `ContentDialog` and is cancelled by the lock.
6. **Size.** The default dialog is at most 548 epx wide and 756 tall; flows that need more raise `ContentDialogMaxWidth` (up to 640) and scroll inside. At small widths a dialog fills the window width. No fixed heights anywhere: text size and display scaling grow content.
7. **Focus.** Focus starts on the first focusable control in the content, or on the default button. A dialog with no default button and no input control (a destructive or irreversible confirmation, a preview step) starts on the Close button, so a stray Enter or Space never chooses the Primary action; closing returns focus to the control that opened it, or, when that control is gone, to the list or the editor. Narrator reads the title and content on open.
8. **Not for validation.** An error tied to one field (wrong password, name taken) shows inline next to the field, not as a new dialog.
9. **Commands while a dialog is open.** Accelerators declared on window-level elements can still fire while a `ContentDialog` is open, so every command checks a modal-state flag as well as its enabled rule, and nothing acts on the library behind a dialog ([7](#7-keyboard-shortcuts), rule 7).

Sources: [Dialog controls](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs), [Dialogs and flyouts](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/).

## 9 Sheets, popovers and notices

| Apple surface | Windows control | When |
| --- | --- | --- |
| Short sheet | `ContentDialog` ([8](#8-dialogs)) | One screen of content: a few fields, a list of choices, a confirmation, or a short flow of at most two steps (Move entry, Rename, Change date, Link, Merge into, Create library with its two steps, the erase warnings) |
| Multi-step sheet with progress or more than two steps (Connect to a Server, Turn On Encryption, Import Archive) | **A task page** in the window's content area, like the review and history pages: the back button and the step's title as the page heading (no breadcrumb, because the steps are not places), the step's content in a column of at most 640 epx, a footer row with the step's buttons (the primary action first, then Cancel, the order of [8.1](#81-rules)), and the Apple rules for Cancel (withdraws requests, gives up unused access, discards a staged copy). The modal guarantee is kept by disabling the navigation pane, the menu bar's commands and the command bars while the page runs; closing the window follows the rule in [3](#3-windows-and-instances). Esc is not Back. A step that has an unfinished typed value asks before Back by its own file's rule | A ten-step flow with progress, a back arrow in the content, changing buttons, a disabled close, a title per step and focus managed by hand is a page's job, not a dialog's: Microsoft's dialog guidance is for blocking questions and short forms, and Windows Settings uses pages for its own pairing flows. It also removes the "dialog cannot open a dialog" workaround for Add another device |
| Add Device (the approving side) | A `ContentDialog` whose content swaps between states (showing the code, entering a code, waiting, confirming, finished). It has states rather than steps: one primary action per state, no back arrow, a title that stays `settings.addDevice.title` | The approval is one question with a code to show; it stays within the dialog guidance |
| Large review screens (Version History with side-by-side comparison, Review Changes for entries, journals and deletions, Image Descriptions, Journal Version History, Changes to Review) | A page in the window's content area, with a `BreadcrumbBar` header and a back button; the library panes are replaced and return exactly as they were. The page saves first, as the Apple sheet does | Comparisons need the width, which a dialog does not have; Windows 11 uses pages for this kind of task |
| Popover (Formatting; Template chooser) | Formatting is not a popover on Windows: a toggleable formatting bar plus a selection mini-toolbar ([4.2](#42-command-bars), [format-sheet](screens/format-sheet.md)). The Template chooser is a `Flyout` anchored to the control that opened it; light dismiss; Esc closes; focus moves to the first control and returns on close. In the small layout the flyout fills the width | Windows' anchored transient surface for a chooser; a formatting popover is Apple's idiom, and a bar costs one click per bold, not two |
| Menu popovers (picker menus with a chevron: journal and version pickers) | `ComboBox` or `DropDownButton` with a `MenuFlyout` | Native pickers |
| Notices above the writing (writing paused, recovery, conflict, save failure, image import) | `InfoBar`, inline above the editor, in the Apple order | Inline, non-modal, persistent status |
| Coaching or first-run tips | Not used. `TeachingTip` is for transient teaching moments and the product has none | Quiet product; nothing to teach by popup |
| Another window (Settings window on the Mac) | A page in the main window ([10](#10-settings)) | Windows 11 apps keep settings in the app window |

### 9.1 Notices

| Notice | Severity | Closable | Action |
| --- | --- | --- | --- |
| Writing paused ([flows/save-failure](../../flows/save-failure.md), connecting, encrypting) | Informational | No; closes when the state ends | None. The Mac's Show Connection and Show Progress buttons are not needed because the dialog is modal over the only window |
| Recovery notice (an entry in Recently Deleted or deleted with its journal) | Informational | No | `restore`, `restore-with-journal`, `restore-and-move`, `try-syncing-again` as `ActionButton` and a second link in the content |
| Conflict notice (changes to review) | Warning | No; closes when resolved | `review-changes` |
| Save failure notice | Error | No; closes when the save succeeds | Try Again |
| Image import notice (images being read) | Informational with an indeterminate `ProgressBar` in the content | No | Stop (`editor.imageImport.stop`) |
| Editing note ("This entry can't be edited normally") | Not an `InfoBar`: secondary text under the title, as Apple | n/a | None |

Rules:

- An `InfoBar` must not flash on and off. Debounce states that change quickly (half a second) before showing or closing one.
- Narrator announces an `InfoBar` when it opens. Changing the text of an open bar is not announced, so close and reopen it, or raise a notification ([11](#11-progress-and-announcements)). The one exception is the bar on the Sync page, which is updated in place so that a background change never speaks ([messages](messages.md), Narrator notifications).
- Severity is never colour alone: the bar carries an icon and its title or message states the problem.
- States that stop the person from continuing (sync needs sign-in, library cannot open) use the same bars on the page they belong to; only a blocking choice uses a dialog.

Sources: [InfoBar](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobar), [Flyouts](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/flyouts), [TeachingTip](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/teaching-tip), [BreadcrumbBar](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/breadcrumbbar).

## 10 Settings

**Recommendation: Settings is a page inside the main window in the style of Windows 11 Settings, not a separate window.** **Decision needed** (D26).

| Apple | Windows | Why |
| --- | --- | --- |
| Mac: a Settings window with five tabs, opened with ⌘, and independent of the journal window; iPhone and iPad: a sheet with a list of panes and an About section | The navigation pane's built-in Settings item (gear, E713, the last item, pinned), File ▸ Settings and Ctrl+, open a Settings page that fills the content area. It lists the six panes as clickable `SettingsCard` rows (icon, name, chevron) followed by an About group; a pane opens as a sub-page with a `BreadcrumbBar` ("Settings > Privacy") above its cards | The Windows 11 Settings app, Photos, Microsoft Store and Notepad do this. One window is simpler than two, and a page can use the whole window |
| Panes: General, Sync, Privacy, Backup, Agent Access (since 1.1; Devices is a section of Sync) | The same five, in the same order. This table and the Settings mapping pages still describe six panes with Devices as its own: open question C27 | The first pane is General everywhere |
| Erase Journals and Settings is its own last section on iPhone and iPad; the last group of General on the Mac | The last group of General, as on the Mac. Not on the Settings home page | A destructive action does not belong on a landing page; Windows 11 keeps Reset inside Recovery |
| About is a section on iPhone and iPad; the Mac has it in the Help menu | An About group at the foot of the Settings home page (version, Privacy Policy, Support, Source Code, Rate My Journal), and Help ▸ About My Journal opens it. Windows apps show About in Settings | Both Windows convention and parity with iPhone |
| Section headers and footers in grouped forms | A header is a sub-heading `TextBlock` (Body Strong, heading level 2) above its cards. A footer that is one line becomes the card's `Description`; a longer footer is secondary text under the group | Windows 11 Settings layout |
| Switch rows, pickers, buttons, link rows | `SettingsCard` with `ToggleSwitch` (On and Off labels), `ComboBox`, `Button` (accent style for the one primary action on a page), and an `IsClickEnabled` card with an external-link or chevron action icon for **navigation and links** that leave the card's page. **Every action that does something has a real `Button` in the card**, including destructive ones (Erase journals and settings, Stop syncing, Delete all): a clickable card with no button looks like a heading and invites an accidental click, and Windows Settings uses a card with a button (Reset PC, Restart now). No red; the confirmation dialog protects the action | Standard Windows 11 patterns; Microsoft's guidance: buttons initiate an immediate action |
| A group with a dependent setting (App Lock and Lock when inactive) | `SettingsExpander`: the App Lock toggle in the header; Lock when inactive in the expanded part. While the toggle is off the expander stays and its items are visible but disabled (`IsEnabled` false) with an explaining description; it never swaps to a plain card | Microsoft: show the same settings regardless of context and disable with an explanation; a swap loses focus, re-announces and jumps |
| Lists (devices, agents, changes to review) | A `SettingsExpander` or a list of cards; each row's actions in the row's trailing area and in its context menu | |
| Sheets opened from Settings (Connect to a Server, Add Device, Turn On Encryption…) | Connect, Turn on encryption and Import archive are task pages that replace the Settings page for their duration (Back returns to where they started); Add Device is a `ContentDialog` over the Settings page ([9](#9-sheets-popovers-and-notices)) | |

Rules:

- The page's content is at most 1000 epx wide, left-aligned with a 24 epx margin (12 at small width), and wraps card content under 600 epx as the toolkit does. No Done button: Back (Alt+Left, the back button, the breadcrumb) returns to the library with the collection and entry as they were. Opening Settings saves the open entry first (the built-in item's `ItemInvoked` handler does it before navigating).
- Opening Settings "at a pane" (from Sync Status or a notice) navigates straight to that pane's page, with Back leading to the Settings home page.
- Settings is never reachable while locked; the lock screen replaces the window ([13](#13-device-authentication-and-app-lock)).
- Erasing returns the window to the first-launch screen ([screens/settings](../../screens/settings.md), After Erase).
- Pane-specific mapping files describe each pane's cards; they follow the headers and footers in the spec.

Sources: [SettingsCard](https://learn.microsoft.com/en-us/dotnet/communitytoolkit/windows/settingscontrols/settingscard), [SettingsExpander](https://learn.microsoft.com/en-us/dotnet/communitytoolkit/windows/settingscontrols/settingsexpander), [Toggle controls](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/toggles), [BreadcrumbBar](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/breadcrumbbar).

## 11 Progress and announcements

| Apple | Windows | Why |
| --- | --- | --- |
| Spinner for short waits ("Syncing…", "Checking…") | **A ring means the app is blocked while it waits; a bar is non-modal** (Microsoft's progress guidance). Where the app is blocked on the answer (a dialog or task page waiting on the server, a loader alone on a page) a `ProgressRing`, indeterminate, at least 20 × 20 epx (the documented minimum; the welcome page's loader may be 32 epx). Where the page stays usable (the inline "Syncing…" and "Checking…" in a Settings row) a small indeterminate `ProgressBar` (about 80 epx wide) beside the text, or the plain text alone. The text stays visible at least half a second | Standard Windows indicators, used for what they mean |
| Progress for counted work (export, import, encrypting) | Determinate `ProgressBar` with the step text above; indeterminate `ProgressBar` along the top of a dialog while the length is unknown. The dialog's buttons are disabled while it runs, except Cancel where the Apple flow allows it | Standard |
| Normal saving and syncing show nothing | Unchanged: no spinner or message in the toolbar or title bar while the library syncs | Quiet product rule |
| VoiceOver announcements (`messages.announce.*`, sync results, undo results) | A notification raised on the automation peer of the root content element (`Window` is not a `UIElement` and has no peer of its own): `AutomationPeer.RaiseNotificationEvent` with kind `ActionCompleted`, `ActionAborted` or `Other`, and `ImportantMostRecent` processing for results (`MostRecent` for routine ones, `ImportantAll` where nothing may be cut, such as "You can't stop this now"). A visually hidden `TextBlock` with `AutomationProperties.LiveSetting` set to Polite (Assertive for errors) is the fallback where the peer is not reachable | Narrator announces notification events; nothing needs to appear on screen |
| VoiceOver focus moves after an action (after unlock to the journals; after cancel back to Unlock) | Move keyboard focus programmatically with `Control.Focus(FocusState.Programmatic)`; Narrator follows focus | Windows has no separate screen-reader cursor to move |

## 12 Copy: casing, ellipses and vocabulary

The spec copy ([copy/en.json](../../copy/en.json)) is written in Apple's idiom. Windows has its own: the Microsoft Writing Style Guide uses sentence-style capitalization for UI labels, button names, titles and headings, keeps capitals for proper nouns and product names, says "select" for choosing an item, "close" for apps, and uses an ellipsis only where more input is needed. A Windows app with Apple title case looks wrong beside Windows' own settings, menus and dialogs, so Windows copy differs where the idiom requires it. Nothing in `copy/en.json` has been changed: this section proposes the rule, and the owner approves it first (**Decision needed**, D21).

### 12.1 Casing

The catalog has 1,135 keys. By a rough count, about 340 are short strings in Apple title case (settings 112, library 103, messages 52, editor 48, common 28). Full sentences, footers and explanations are already sentence case, except for the Title Case labels some of them name (see Labels and features inside sentences, below). The Mac already has sentence-case variants for form labels inside Settings (`settings.general.defaultJournal`), which shows the pattern works.

Options considered:

| Option | Verdict |
| --- | --- |
| A. Keep Apple casing on Windows | Rejected: the app would not look as if Microsoft built it |
| B. Hand-write a variant for every affected key | Works, but about 340 strings can drift when the default changes |
| C. Generate sentence case at build time from the default text | No drift, but invisible in review and wrong at the edges (proper nouns, product terms) |
| **D. Store explicit `sentence` variants in the catalog, generated by a tool from a written rule, and have the checker fail when a stored variant differs from the rule's output (except for a short, reviewed exceptions list)** | **Recommended.** The catalog stays complete and reviewable in diffs; nothing drifts silently; exceptions are visible |

**The variant is named for the casing, not for the platform.** Android's Material guidance is also sentence case and the Apple catalogue is Title Case, so the list of about 340 strings is stored once, as a `sentence` variant that Windows and Android share, and a second, `android`-named copy of it is never generated, which would invite the two to drift. A platform-named variant (`windows`, later `android`) exists only where the words differ, not the casing ("Windows Hello", "this PC", "select", a dropped ellipsis), and is written in sentence case itself. On a platform the most specific variant wins: its own, then `sentence` where its convention is sentence case, then `mac` on the Mac, then `default`.

The shapes are `{"default": "Try Again", "sentence": "Try again"}`, `{"default": …, "mac": …, "sentence": …}` where a key already has a Mac variant, and `{"default": "Unlock with {method}", "windows": "Unlock with Windows Hello"}` for vocabulary. The checker accepts them (and `android`). Plural objects (`one`, `other`) carry no variants today, and none of the affected strings is a plural.

**The rule.** For a string in an affected category (below): keep the first word and the first word after a sentence-ending mark; lower-case every other word, except:

- the product name "My Journal", and the names Markdown, Windows, Windows Hello, Microsoft Store, GitHub, Tailscale, Claude Code, MCP, PIN, QR, HTTPS and URL;
- initialisms and "OK";
- placeholders such as {host}, {name}, {count}, and any journal, device or agent name the person typed.

Feature names are not product names under Microsoft style, so they are lower-cased: "App lock", "Master password", "Recovery key", "Agent access", "Recently deleted", "Version history". (Microsoft keeps "Windows Hello" because it is a brand.) A colon followed by a full sentence keeps its capital.

**Labels and features inside sentences (B27).** A feature name inside a sentence is lower case ("turn on app lock", "Couldn’t turn on app lock"); only a capital at the start of the text stays. A sentence that names a command or a place as an instruction uses the label exactly as it is written on Windows ("select Try again", "stays in Recently deleted", "use Export archive"), and a label that continues a phrase is lower case ("from this device"). About 40 catalog sentences name such a label, so the "sentences are not affected" rule below has this exception; [copy-proposals](copy-proposals.md) lists them.

**Categories affected** (by the role of the copy key):

| Category | Examples (default → Windows) |
| --- | --- |
| Command labels in menus, toolbars and context menus (`library.menu.*`, `library.toolbar.*`, `library.entryActions.*`, `library.journalActions.*`) | "Bulleted List" → "Bulleted list"; "Move Entry…" → "Move entry…"; "Show Editor Only" → "Show editor only" |
| Button labels (`common.*` verbs and `settings.*` buttons) | "Try Again" → "Try again"; "Connect to a Server…" → "Connect to a server…"; "Reconnect…" is unchanged |
| Dialog and sheet titles written as titles (not as questions) | "Erase Journals and Settings?" → "Erase journals and settings?"; "Stop syncing with {host}?" is already correct |
| Page, pane and section titles and headers (`settings.pane.*`, `*.header`, `common.journals`) | "Agent Access" → "Agent access"; "App Lock" → "App lock" |
| Collection and list names (`library.journals.*`, `common.recentlyDeleted`, `common.unavailableJournals`) | "Recently Deleted" → "Recently deleted" |
| Field labels (`common.masterPassword`, `common.name`, `common.serverAddress`) | "Master Password" → "Master password" |
| Status and error titles (`messages.*.title`, alerts) | "Couldn’t Turn On App Lock" → "Couldn’t turn on app lock" |
| Accessibility labels and hints derived from the above | Follow their visible text |

**Not affected:** sentences, footers, explanations and messages (except for the labels they name, above); plural count strings; the product name; file and folder names (`settings.backup.archiveFilename`, `settings.backup.markdownFolderName`), which stay identical on every platform so exports sort and open the same; and anything the person typed.

### 12.2 Ellipsis

Windows menus and buttons use an ellipsis when the command opens a dialog or page that asks for a choice or input before it acts, as Save as… does. A command that only asks for confirmation, opens a settings page or hands over to the system has none. The Mac and iOS put one on confirmations as well ("Delete Permanently…"). This is a Windows convention, not a casing one, so the rows below are `windows` variants (written in sentence case) that drop it from:

| Key | Default | Windows |
| --- | --- | --- |
| `library.entryActions.deletePermanently`, `library.menu.file.deleteAll`, `library.recentlyDeleted.deleteAll` | Delete Permanently…, Delete All in Recently Deleted…, Delete All | Delete permanently, Delete all in Recently deleted, Delete all |
| `library.journalActions.deleteJournal` | Delete Journal… | Delete journal |
| `settings.sync.stopSyncing`, `settings.erase.button` | Stop Syncing…, Erase Journals and Settings… | Stop syncing, Erase journals and settings |
| `settings.devices.revoke`, `library.journalHistory.restoreSettings`, `messages.syncStatus.settings` | Revoke Access…, Restore Settings…, Sync Settings… | Revoke access, Restore settings, Sync settings (each only asks for confirmation, shows a comparison or opens a settings page) |
| `messages.conflict.journal.keepVersion`, `messages.conflict.deletion.keepDeletion`, `messages.conflict.keepThisDevice`, `messages.conflict.keepOtherDevice` | Keep Version…, Keep Deletion…, Keep Version from This Device…, Keep Version from Other Device… | Keep version, Keep deletion, Keep version from this device, Keep version from other device (each opens a confirmation) |
| `common.share` | Share… | Share |
| the Settings item | Settings… | Settings |

Everything else that asks for input keeps its ellipsis: New journal…, Rename…, Merge into…, Move entry…, Change date…, Save as template…, Image descriptions…, Version history…, Import archive…, Export archive…, Export as Markdown…, Connect to a server…, Sign in…, Change password…, Turn on encryption…, Link…, Image…, New entry from template…, Keep entry…, Keep entry as copy…, Save image as…. "Syncing…" and similar progress text keep theirs.

### 12.3 Vocabulary

Strings that name Apple features, keys or devices need a Windows wording. Each row is a proposed `windows` variant (vocabulary), written in sentence case.

| Apple wording | Windows wording | Keys |
| --- | --- | --- |
| Face ID, Touch ID, Optic ID, Passcode, Login Password | "Windows Hello" (the system prompt chooses face, fingerprint or PIN) | `library.lock.method.*`, `library.lock.phrase.*`, `settings.lock.unlockWith`, `settings.privacy.appLock.require` |
| "set a passcode for this {device} in Settings" | "set up Windows Hello in Settings > Accounts > Sign-in options" | `settings.privacy.appLock.noPasscode`, `settings.lock.turnedOff.passcodeRemoved` |
| "App Lock now uses … instead of a PIN" | Not shown: Windows never had an app PIN | `settings.lock.pinRetired`, `settings.lock.turnedOff.pinRetired` |
| Mac, iPhone, iPad as the current device | "this PC" ("this device" where the type is unknown) | `library.lock.device.*`, `messages.save.mac.title`, `messages.writingPaused.*`, `settings.agents.thisMac`, `settings.agents.reach.local`, `settings.privacy.appLock.footerInactive`, `settings.privacy.appLock.footerSleepOnly` (`settings.addDevice.enterCodeInstead.footer` names the other device, so it says "a computer", B28) |
| Mac-only states (the former Mac server) | Not shown | `settings.sync.footer.formerMacServer`, `settings.sync.footer.learnMore`, `settings.erase.footerFormerServer` |
| Quit and reopen My Journal | "Close My Journal and open it again" (Microsoft style: "close" for apps; "Exit" only as a menu label) | `messages.library.cannotOpen` |
| "choose" an item in the UI | "select" | `settings.addDevice.scanInstructions`, `settings.sync.stopSyncing.message`, `settings.connect.addThisDevice.instructions`, `settings.connect.scanCode.footer`, and about fifteen more (B26) |
| "Close this sheet" | "Close this dialog" | `messages.entry.dateChanged` |
| Sidebar, Sidebar and List | Navigation pane; "Show editor only" and "Show all panes" | `library.menu.view.showSidebarAndList`, `library.toolbar.editorOnly.*`, `library.moveEntry.renameExplanation` |
| Shortcut glyphs in labels and tooltips (⇧⌘D, ⌘Return) | Removed: WinUI adds the accelerator to tooltips and menus and Narrator reads it | `library.toolbar.editorOnly.help`, `library.toolbar.editorOnly.helpActive`, `settings.connect.addThisDevice.connectHelp`, `settings.connect.addThisDevice.connectHint`, `settings.connect.merge.help`, `settings.connect.merge.hint` |
| Key name "Delete" (the Backspace key) | "Backspace" | `settings.general.formatAsYouType.footer` |
| "Settings ▸ Privacy" | "Settings > Privacy" | `settings.lock.turnedOff.passcodeRemoved` and the other keys that use ▸ |
| Writing pane called "Writing" | "General" (now the catalog's text on every platform) | `settings.pane.general` |
| Authentication reasons in lower case for the Mac's "My Journal is trying to…" | The default (capitalised) form: Windows shows the text as a message | `settings.addDevice.authReason`, `settings.backup.markdownReason`, `settings.erase.authReason`, `settings.privacy.appLock.reason.*` |
| iCloud as a cause of slow images | "They may still be downloading. Try again later." | `editor.imageImport.cause.unavailable`, `messages.image.unavailable` |
| Photos, camera, photo library | Not shown: see [26](#26-camera-photos-and-images) | `editor.insertImage.photoLibrary`, `editor.insertImage.takePhoto`, `editor.insertImage.cameraOff.*`, `editor.image.saveToPhotos`, `editor.image.photosOff.*`, `editor.announce.savedToPhotos`, `editor.image.saveToPhotosFailed`, `editor.permission.*` |
| Local Network permission | Not shown: Windows has no such prompt ([32](#32-local-network-and-servers)) | `settings.connect.nearby.denied` |

### 12.4 Other copy rules

- "OK" and "Cancel" keep their English wording and capitals; other dialog buttons are specific verbs in sentence case ([8](#8-dialogs)).
- Plain language, no exclamation marks, no marketing words: unchanged.
- Windows instruction text names a path with ">" ("Settings > Sync"), keys with "+" ("Ctrl+Enter") and key names in sentence case ("Backspace", "Enter", "Esc").
- Apostrophes and quotes stay typographic (’ “ ”); "…" stays the ellipsis character.
- Until the owner approves the casing rule, mapping files write labels as the default text and say "sentence case on Windows" (the `sentence` variant).

## 13 Device authentication and App Lock

App Lock is an interface lock and nothing more. Apple's rule applies: only the system's authentication, nothing of the app's own, and it changes nothing about how the journals are encrypted ([flows/app-lock](../../flows/app-lock.md)).

| Apple | Windows |
| --- | --- |
| Face ID, Touch ID, Optic ID, or the device passcode or login password, through the Local Authentication framework | Windows Hello (face, fingerprint or PIN) through `UserConsentVerifier`. A desktop app asks with `UserConsentVerifierInterop.RequestVerificationForWindowAsync(hwnd, message)`, with the library window's handle; `CheckAvailabilityAsync` tells whether it can. The desktop call needs Windows 11 build 22000 or later, which is why that is the app's minimum ([1](#1-target-and-toolkit)) |
| Reason text is the prompt's message (`settings.privacy.appLock.reason.*`) | The same text is the message of the Windows Security prompt, capitalised as a sentence |
| Passcode or password fallback | The Windows Hello prompt offers the PIN itself when a biometric fails. The app never has its own PIN or password prompt for this. A Hello PIN can be set up on any account, with or without biometric hardware |
| The method name follows the device | One name: "Windows Hello" |

**Availability and results**

| `UserConsentVerifier` result | What the app does |
| --- | --- |
| Available, then Verified | Success |
| Canceled | Nothing; the lock screen stays; Unlock with Windows Hello asks again |
| NotConfiguredForUser, DeviceNotPresent | App Lock cannot be turned on: the switch is dimmed and its footer says how to set up Windows Hello (a link opens `ms-settings:signinoptions`). Where a rule says "a device without a passcode continues without it" (Add Device, export, erase), these results continue without authentication. **When App Lock is already on, it pauses** (below) |
| DisabledByPolicy | As above, with its own footer: an organization policy turns the prompt off (new copy, proposed with D25). When App Lock is already on, it pauses (below) |
| RetriesExhausted, DeviceBusy, anything else | `settings.lock.failed`, and Use {credential} when the journals have a password |

**App Lock pauses; a person is never locked out of journals that have no password.** App Lock is an interface lock, not encryption, and an organisation policy or a Remote Desktop session must not be able to lock someone out of data on their own PC. So when App Lock is on and Windows Hello is NotConfiguredForUser, DeviceNotPresent or DisabledByPolicy at launch, at unlock or when a trigger would lock, the app does not show the lock page: the journals open, App Lock is paused for this session, and a persistent warning `InfoBar` at the top of the window says so and why (with an Open Sign-in options link where the person can fix it). It resumes by itself when Hello is available again (checked when the window is activated and before every lock). The transient results DeviceBusy and RetriesExhausted keep the lock page with Try again. The Apple rule (Hello removed turns App Lock off with an alert) is not copied: pausing keeps the protection the person chose and makes its absence visible instead of silent. **Decision needed** (D42): this is the review's recommendation and the draft default; the alternative is the lock page that stays (fail closed), which can lock a person out. **Decision needed** (D25): this version supports only Windows Hello. A PC account with only a password cannot use App Lock. The Windows Security password prompt (`CredUIPromptForWindowsCredentials`) could cover those accounts but would hand the app the typed password to verify, which the spec's "only the system's authentication" rule avoids; it is not recommended.

**When it locks (Windows)**

| Trigger | Mechanism |
| --- | --- |
| Launch | Always, when App Lock is on |
| Lock My Journal (File menu, Ctrl+L, Settings ▸ Privacy) | Command |
| Lock when inactive (5, 15, 30 minutes, 1 hour, Never; default 30), as on the Mac | A timer reset by input to My Journal's windows: key presses, clicks, wheel and touch, pointer movement only while the window is active, menus, editor changes. Not a global hook and not the system-wide idle time, because syncing and other apps must not count either way ([flows/app-lock](../../flows/app-lock.md), What counts as use) |
| The display turns off, the lid closes, the PC sleeps, the screen locks (Win+L), the user is switched or the session disconnects | **Display and lid notifications first, not a heartbeat:** `RegisterPowerSettingNotification` for `GUID_CONSOLE_DISPLAY_STATE` (lock when the display turns off, not when it comes back) and `GUID_LIDSWITCH_STATE_CHANGE`, plus `WM_WTSSESSION_CHANGE` and the power-broadcast message. Modern Standby sends no suspend message and throttles the app, so a timer cannot be the trigger; a 15-second heartbeat that notices a gap stays only as a backstop ([flows/app-lock](flows/app-lock.md)) |
| The window loses focus | Does not lock (desktop windows lose focus constantly), and nothing covers the window either: other apps snap beside it all day. App Lock, the inactivity timer and capture exclusion do the protecting ([20](#20-screen-capture-and-window-privacy)) |

**Known cost: two prompts after Win+L.** After Win+L and signing in, the person has just proved who they are to Windows, then proves it again to the app. The spec says a screen lock locks, so this version does it as written; an option to skip the second prompt after a session lock (not after the timer or Ctrl+L) is D54.

**The lock screen is a page, not an overlay.** Locking replaces the window's content with the lock page and releases the journal views, so the UI Automation tree, Narrator and screen magnifiers cannot read journal content while locked ([screens/lock-screen](../../screens/lock-screen.md)). Dialogs hide ([8](#8-dialogs)). Locking first saves the open entry, for about two seconds at most.

**Prompting** happens automatically once per lock when the window is active, and only after the window is in the foreground, because the Windows Security prompt can open behind an inactive app. The lock page's default button is Unlock with Windows Hello and takes focus.

Sources: [UserConsentVerifier](https://learn.microsoft.com/en-us/uwp/api/windows.security.credentials.ui.userconsentverifier), [Retrieve a window handle](https://learn.microsoft.com/en-us/windows/apps/develop/ui-input/retrieve-hwnd).

## 14 Secure storage

What Apple keeps in the Keychain: the library's key and this device's server credentials, as "when unlocked, this device only" items. App Lock is not a key ([architecture](../../../docs/architecture.md)).

**Recommendation: protect those secrets with the Windows Data Protection API (DPAPI, current-user scope), stored as a small file in the app's local, non-roaming data folder, behind one `ISecretStore` interface** (read, write and remove by account name, like the Apple `SecretStore`). Hardening with a TPM-backed key is a spike, not the baseline.

| Option | Verdict | Reasons |
| --- | --- | --- |
| **DPAPI, current user** (`ProtectedData`, or `CryptProtectData`) | **Use** | Bound to this PC and this Windows user; no prompt; works packaged and unpackaged; not roamed or synced when the blob is in local app data. Comparable to Apple's "when unlocked, this device only" |
| Credential Locker (`PasswordVault`) | Not for the device key | Gives per-app isolation for packaged apps, but holds only 20 credentials and may roam with the Microsoft account, which a device-only key must never do. Revisit in the spike if roaming can be switched off |
| Windows Hello key credentials (`KeyCredentialManager`) | Not as the wrapping key | It creates a TPM-backed RSA key that signs data after a Hello gesture; it cannot encrypt, wrap or export a secret, and the signatures are not documented as repeatable, so a key cannot be derived from them. Fine for proving presence, which `UserConsentVerifier` already does |
| TPM-backed non-exportable key (CNG, Microsoft Platform Crypto Provider) wrapping the DPAPI secret | Spike | Stops offline copying of the profile from yielding the key. Adds failure modes (no TPM, TPM cleared, virtual machines), all of which land in the same recovery path below |

**Threat notes** (to be carried into the security documentation, per [AGENTS.md](../../../AGENTS.md)):

- A process running as the same Windows user can ask DPAPI to unprotect the blob. Classic desktop apps have no per-app key isolation on Windows. App Lock does not change this, which the spec already says; do not describe App Lock as protecting data at rest.
- A stolen powered-off disk is protected by device encryption (BitLocker) and, beyond that, by DPAPI's dependence on the user's sign-in secret. The app does not check or promise BitLocker.
- The secret is unusable after: restoring the profile on another PC, resetting the Windows account's password with an administrator tool, reinstalling Windows, or removing the app's data. Windows PCs are replaced, reset and migrated more often than Macs are restored, so the **device key unavailable** path ([screens/lock-screen](../../screens/lock-screen.md), `missing-device-key-unlock`) is a first-class path: the master password or recovery key unlocks and the secret is saved again, with `messages.library.deviceKeyUnavailable`.
- The blob lives in per-user local data, never in Documents, a roaming profile or a OneDrive folder. It is removed by Erase and by uninstall.
- Secrets never go to logs, crash text or the clipboard history ([15](#15-clipboard)). Buffers holding keys are cleared after use, which in .NET is reliable only with pinned byte arrays cleared by `CryptographicOperations.ZeroMemory`; a secret is never held in a `string`.
- DPAPI is called with an application-specific entropy value, and the blob is written with an atomic replace (write a temporary file, then replace). Backups of the app's local folder by third-party tools carry the blob, but it is unusable on another PC or account, which is the documented device-key-unavailable path.
- The master password and recovery key are never stored by the app.

Sources: [ProtectedData](https://learn.microsoft.com/en-us/dotnet/api/system.security.cryptography.protecteddata), [CryptProtectData](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata), [Credential Locker](https://learn.microsoft.com/en-us/windows/apps/develop/security/credential-locker), [KeyCredentialManager](https://learn.microsoft.com/en-us/uwp/api/windows.security.credentials.keycredentialmanager).

## 15 Clipboard

| Apple | Windows | Why |
| --- | --- | --- |
| Copying a recovery key or a pairing code: the copied value is removed after two minutes (`settings.recoveryKey.copiedNote`) | Copy with `Clipboard.SetContentWithOptions` and `ClipboardContentOptions` set to `IsAllowedInHistory = false` and `IsRoamable = false`, then clear the clipboard after two minutes only if it still holds the value | Windows clipboard history (Win+V) and cloud clipboard would otherwise keep and sync a secret |
| Copy the MCP address, the server address | Plain copy | Not secrets |
| Paste an image | Ctrl+V of a bitmap, including a Snipping Tool capture (Win+Shift+S), starts the insert-image flow | The Windows replacement for the Photos library |

Source: [ClipboardContentOptions](https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.datatransfer.clipboardcontentoptions).

## 16 Files and pickers

**An archive is one file on Windows (draft default of D29, from the review).** [protocol/archive.md](../../../protocol/archive.md) defines a `.journalarchive` as a directory package. Apple treats such a package as one document; Windows does not: Explorer shows a folder, a `FileOpenPicker` cannot choose one, a `FileSavePicker` cannot create one, and a file type association applies to files only. A folder holding a SQLite file and its images is also easy to copy partly, to sync half-way through OneDrive, to break with path-length limits and to hand to someone as 300 loose files, and nothing stops a half-copied folder from looking valid. A person could not double-click it, email it, upload it to a share or drop it in a cloud folder as one object, and the import would have to guess whether a folder is complete. So the draft default is **a protocol change, made now while it is cheapest: one file on every platform**, a ZIP container (or an equivalent single-file package) with the manifest, a content hash and the same checks as today. It restores the Open and Save pickers, drag and drop of one object, a `.journalarchive` file association through the package manifest, and cross-platform restores (a Windows archive opens on Apple), and it removes the folder picker rules, the " (2)" folder naming and the "folder is not an archive" error. The protocol file is outside this folder, so the change is the owner's decision (**Decision needed**, D29); the mapping files follow the file route. **If the owner declines**, the folder route is the fallback, with one added safeguard: the manifest lists every file with its hash and import verifies all of them before showing the preview, so a half-copied folder cannot look valid ([flows/import-archive](flows/import-archive.md), Fallback).

| Task | Windows | Notes |
| --- | --- | --- |
| Import Archive | `FileOpenPicker` filtered to `.journalarchive` ("My Journal archive"), started in Documents; the system's own Open button | [flows/import-archive](flows/import-archive.md) |
| Export Archive | `FileSavePicker` with the suggested name `settings.backup.archiveFilename` and the file type list "My Journal archive"; the picker's own replace prompt covers an existing file. The picker creates an empty file and the app writes into it; a failed or cancelled write removes the empty or partial file the app created | [flows/export-archive](flows/export-archive.md) |
| Export as Markdown | `FolderPicker` (the export is many files, a folder by nature); the app creates the `settings.backup.markdownFolderName` folder inside it, adding " (2)", " (3)"… when the name exists, and never overwrites or merges. The commit button reads a Windows-only string (B36) | [flows/export-markdown](flows/export-markdown.md) |
| Insert Image ▸ choose a file | `FileOpenPicker`, images filtered to the formats in [flows/insert-image](../../flows/insert-image.md), start in Pictures | |
| Save Image As; Save Recovery Key | `FileSavePicker` with the suggested name (`editor.image.fileName` plus the extension) and a type list | The recovery key screen is not offered on Windows (D11) |
| Drag and drop | Image files into the editor; a `.journalarchive` file dropped on the window starts Import Archive after unlocking | |

Rules:

- Desktop windows must tell the picker which window owns it (`WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd)`); where the Windows App SDK offers window-ID-based pickers, prefer them. Pickers do not work in an elevated process; the app never asks to run elevated.
- The app asks for no broad file access. It reads and writes only what the person picked. Packaged apps can write to a picked location without extra capability. An unpackaged build (a development or portable copy) can reach any file the user can, but it uses the same pickers and never reads or writes outside what was picked; it has no package identity, so the manifest file association, the Store rating prompt and Store checks are off in it.
- **File names.** Windows forbids `< > : " / \ | ? *`, control characters, the names CON, PRN, AUX, NUL, COM1 to COM9 and LPT1 to LPT9, and trailing dots or spaces, and paths are limited unless long paths are enabled. Markdown export turns entry titles into file names, so it needs Windows-safe naming rules with a test for each: replace forbidden characters, avoid reserved names and trailing dots, shorten long titles, and add a number for duplicates. Written once in the export mapping.
- Files the app writes use LF line endings, as on every platform, so archives and exports are the same everywhere.
- **No warning about synced folders.** Documents is often redirected to OneDrive, which then uploads what is saved there. The app shows no dialog or note before writing an export, a Markdown folder or an archive into a OneDrive folder or any other synced location: where the person saves it, and what a sync client then does with it, is the person's decision and risk (owner decision, 2026-10-07; D46 and B37 are settled).
- File type: `.journalarchive` is shown as "My Journal archive" and registered in the package manifest ([19](#19-single-instance-and-activation)).

Sources: [Retrieve a window handle](https://learn.microsoft.com/en-us/windows/apps/develop/ui-input/retrieve-hwnd), [Display WinRT UI objects](https://learn.microsoft.com/en-us/windows/apps/develop/ui/display-ui-objects).

## 17 App data, backups and erasing

| Apple | Windows | Why |
| --- | --- | --- |
| Library folders, configuration and the database in the app's sandbox container; secrets in the Keychain | The packaged app's local folder (`ApplicationData.Current.LocalFolder`, under the user's local app data, in a folder named for the package). Library folders, `configuration.json`, the database and images live there. Device-only preferences (window position, list width, last collection and entry, rating timestamps) are in local settings. Secrets: [14](#14-secure-storage) | Non-roaming, per user, removed with the package. Never Roaming, Documents or a OneDrive-synced folder |
| Export Archive is the only backup the app supports | Same. Windows Backup, File History and OneDrive folder backup do not include per-app local data, so nothing else protects a library that exists only on this PC | Say nothing new in the UI; the Backup pane already explains archives |
| Erase Journals and Settings removes the library, configuration, secrets, App Lock and preferences | The same, plus the window placement and list width; temporary export files are always deleted when an export ends | Parity; the lists are in [flows/erase](../../flows/erase.md) |
| Deleting the app removes its data | Uninstalling the package removes its local data too (`LocalState`), including journals that exist only on this PC. Packaging cannot show a prompt at uninstall. Draft default of D22 (the review's recommendation): the Store listing says so, and the Backup page shows a gentle line, "Last exported: {date}" (or that nothing was exported yet) while the library exists only on this PC, which serves the data-safety rule better than a Store sentence alone | Never losing content silently is a product rule |

Rules: one process opens the library (single instance, [19](#19-single-instance-and-activation)); the database and its write-ahead log live in the local folder; a file that is locked or cannot be written (for example by security software) is a save failure with the normal notice.

## 18 Packaging, distribution and updates

**Recommendation: ship one MSIX package through the Microsoft Store, for x64 and Arm64, and make it installable with winget from the msstore source. Add a GitHub-hosted MSIX only once a certificate Windows trusts exists.** **Decision needed** (D22).

| Topic | Windows | Reason |
| --- | --- | --- |
| Packaging | Packaged (MSIX), framework-dependent Windows App SDK for the Store build | New WinUI 3 apps are packaged by default; identity is needed for the Store rating API and clean uninstall, and for a manifest file type association if D29 makes the archive a single file. Unpackaged and "external location" packages exist but add nothing the product needs |
| Store | Microsoft Store listing with Store signing and updates | The Store signs the package and updates it; the app has no updater of its own and no background service |
| winget | The Store listing is installable with `winget install` from the msstore source; a community manifest pointing at a GitHub MSIX is optional later | Command-line install for people who use it |
| Direct download | **Not in version 1 unless a trusted certificate exists.** A signed MSIX bundle on the GitHub releases page needs a code-signing certificate that Windows trusts; the Store build is signed by the Store. Azure Artifact Signing (formerly Trusted Signing) issues public-trust certificates to individuals only in the United States and Canada, and to organisations in a list of regions that includes the EU (eligibility is confirmed on its quickstart before relying on it), so an individual elsewhere plans Store-only. The `ms-appinstaller:` web protocol has been disabled by default since December 2023: a GitHub-hosted `.appinstaller` works only as a downloaded file opened locally | A direct download outside the Store cannot be installed without a trusted certificate |
| Versions | Four-part package version; the Store reserves the last part, so releases use Major.Minor.Build.0 | Store rule |
| Architectures | x64 and Arm64; no 32-bit build. Every native dependency (SQLite, the crypto library, the QR library, a WebView2 loader if Spike B wins) must exist for both, which the engine spike states so a Store submission does not fail late | Arm64 PCs (including Copilot+ PCs) are mainstream |
| Updates | The Store updates silently. Where a message tells the person to update My Journal, a Windows-only link "Get updates" beside it opens the Microsoft Store's updates page (D51) | The Apple messages say "Update My Journal"; nothing downloads inside the app |
| Store identity checks | `Package.Current.SignatureKind` tells a Store install from a sideload, for the rating rule ([28](#28-rating)) | |

Sources: [Packaging overview](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/packaging/), [Choose a distribution path](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/choose-distribution-path).

## 19 Single instance and activation

| Apple | Windows | Why |
| --- | --- | --- |
| One app instance per library (system-enforced) | The app is single-instance: `AppInstance.FindOrRegisterForKey` in a custom `Main` (with the generated entry point turned off) that runs **before any XAML is created**, redirecting a second launch's activation to the first instance and bringing its window to the front. A second launch while the first is locked cannot bypass the lock: the redirected activation arrives at the lock page and the held request waits for unlocking | Two processes on one SQLite library, two sync loops and two secret stores must never happen. WinUI apps are multi-instance by default |
| Open an archive from Finder or Files | A file type association for `.journalarchive` in the package manifest ("My Journal archive", with an icon); the first instance receives a File activation. While locked, the app holds the file path (not its content) and starts [flows/import-archive](../../flows/import-archive.md) after unlocking. If another modal flow is open, it comes to the front and the import starts when that flow ends. A path given on the command line is handled the same way. (This is the file route of D29; the folder fallback has no association and imports a folder dropped on the window.) | Double-clicking a backup should open the import where the platform allows it, and a backup is as sensitive as the journals |
| No jump lists or recent documents | The taskbar jump list has at most the task New entry, which waits for unlocking when the app is locked; never recent entries or journal names. Do not add the app's documents to Recent Items | Journal titles are private; the window title and thumbnails follow [20](#20-screen-capture-and-window-privacy) |
| No notifications or badges | None in version 1 | Quiet product |
| No login item | The app does not start with Windows | Not needed; sync runs while the app is open |

Sources: [Single-instanced WinUI apps](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/applifecycle/applifecycle-single-instance), [Rich activation](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/applifecycle/applifecycle-rich-activation).

## 20 Screen capture and window privacy

Apple covers every window, including sheets, popovers and alerts, whenever App Lock is on and the app is not active, so the app switcher never shows journals. Windows has no app-switcher snapshot, but it has more places that show a window's pixels: taskbar thumbnails, Alt+Tab, Task View, screenshots, screen sharing and remote sessions, and Recall on Copilot+ PCs.

**The Windows app does not cover its window when it loses focus** (D28; the review's recommendation, now the draft default). On the Mac the cover protects an app-switcher snapshot and is accepted behaviour. On Windows, windows sit side by side and lose focus all day: snapped beside a document the person is reading, on a second monitor, behind a Windows Hello prompt for another app. A cover would blank the journal every time focus moves, nothing in Notepad, OneNote, Mail or Photos does that, a topmost cover the size of the window would sit over whatever other app is in front of it, and it needs special cases for the Hello prompt, the Store rating dialog and every picker. What it would protect (thumbnails, Alt+Tab, Task View) is only partly reachable. The protection comes from App Lock, which locks on launch, Ctrl+L, the inactivity timer, Win+L, user switch, disconnect, display off, lid and sleep ([13](#13-device-authentication-and-app-lock)), and from capture exclusion below. If the owner wants a cover anyway, the alternative is an opt-in Privacy setting ("Hide when not in front"), not topmost, and only for a minimised or inactive window that is not snapped beside the active one.

| Surface | What the app does |
| --- | --- |
| The window while another window is active | Nothing: it stays readable |
| Window title in the taskbar, Alt+Tab, Task View, Narrator and window pickers | "My Journal" in every state, never a journal name ([2](#2-app-shell-and-window)) |
| Taskbar thumbnails, Alt+Tab, Task View | Show the window as it is: the lock page, which holds no journal content, while locked; the journal while unlocked, which the inactivity timer, Win+L and display off protect when the person steps away. Whether capture exclusion also blanks thumbnails is observed in the spike, not promised |
| Screenshots, screen sharing, remote sessions, Recall | `SetWindowDisplayAffinity` on every top-level window of the app (see below). Draft default of D28: on, with a Settings > Privacy switch to allow capture (B33), **pending the accessibility spike below** |

**The flag.** Microsoft's Recall developer guidance says apps can keep their content out of Recall with `SetWindowDisplayAffinity`, and its example uses `WDA_MONITOR`: the window's content is shown only on a monitor and appears with no content everywhere else. `WDA_EXCLUDEFROMCAPTURE` (Windows 10 version 2004 and later) makes the window not appear in captures at all. Both are documented; neither is a security feature or DRM, neither stops a photograph of the screen, and both work only with desktop composition. The draft default is `WDA_MONITOR`, the one Microsoft's Recall page names, and the spike compares it with `WDA_EXCLUDEFROMCAPTURE` on a Copilot+ PC: Recall snapshots, the Snipping Tool, screen sharing in Teams and Zoom, Remote Desktop and Quick Assist. The affinity is per top-level window: each window the app creates, and each popup window XAML creates for a flyout or menu that extends beyond the window's bounds, sets it. It also blocks the person's own screenshots and screen sharing, which is why the switch exists and why the Store listing says so.

**Accessibility check before "on by default".** Screen magnifiers and screen readers that capture the screen (third-party magnifiers such as ZoomText, some OCR and remote-assistance tools) may see an empty window, which would be an accessibility defect for the people this mapping serves. The spike runs Windows Magnifier, Narrator and Quick Assist against each constant. If any of them fails, the default becomes off, with the switch and a Store listing note. While a QR code or check code is on screen the whole window is excluded whatever the setting says ([flows/pair-device](flows/pair-device.md)).

Rules: capture exclusion never removes or changes content, and it applies to every top-level window of the app. When the setting is off, no window sets the affinity.

Sources: [SetWindowDisplayAffinity](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowdisplayaffinity), [Recall developer guidance](https://learn.microsoft.com/en-us/windows/apps/develop/windows-integration/recall/).

## 21 Theming and contrast

| Apple | Windows | Why |
| --- | --- | --- |
| Follows the system appearance; no in-app theme | Same: the app follows the system app mode (light or dark) through the default requested theme; there is no theme setting | Product direction, and Windows users expect it |
| System accent colour for controls and links | The user's accent colour (`SystemAccentColor` resources and `AccentButtonStyle`) for the one primary action per surface, toggles, selection, links and focus. No custom accent | "Restrained action accents" |
| Increased contrast | Contrast themes (Aquatic, Desert, Dusk, Night sky): every brush is a theme resource that maps to the system colours; nothing is a hard-coded colour; controls, icons, borders, selection and the editor's own drawing (checkboxes, quote bars, code backgrounds, rules, table lines) use the system text, background, hotlink and highlight colours; meaning never rests on colour alone. Mica and the translucent pane fall back to solid | Required by Windows; tested in all four themes |
| Reduce transparency | Mica and acrylic fall back to solid when Transparency effects is off; nothing in the design relies on translucency to be readable | |
| Reduce motion | `UISettings.AnimationsEnabled` false means no transitions, no animated progress beyond the indeterminate indicator, no animated list changes | |

Rules: ask the system for colours (`ThemeResource`), never test the theme name. Images in entries are never inverted for dark mode. The QR code is always dark on a white tile ([29](#29-qr-codes-and-add-device)).

Sources: [Mica](https://learn.microsoft.com/en-us/windows/apps/design/style/mica), [Color](https://learn.microsoft.com/en-us/windows/apps/design/style/color), [Contrast themes](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/high-contrast-themes).

## 22 Typography

Fluent 2 on Windows uses Segoe UI Variable, with the type ramp as theme text styles. The editor keeps the Apple measure (default 16 epx, Zoom 12 to 30, text column at most 760 epx, 3 epx line spacing and 10 epx after a paragraph, from [screens/entry-editor](../../screens/entry-editor.md)).

| Apple text style | Windows style (size/line height, weight) | Used for |
| --- | --- | --- |
| Large Title | `TitleTextBlockStyle` (28/36, SemiBold) | Page headers: Settings, pane page headers |
| Title 1 bold | The editor's title: 1.75 × the body size, SemiBold | Entry title |
| Headline | `BodyStrongTextBlockStyle` (14/20, SemiBold) | List row titles, card headers, sub-headings |
| Body | `BodyTextBlockStyle` (14/20, Regular) | Chrome text, descriptions, list previews |
| Editor body | 16 epx × Zoom, Regular | Entry text |
| Heading 1, 2, 3, 4 to 6 in entries | 1.4, 1.2, 1.1 and 1.0 × the body size, SemiBold | As Apple |
| Subheadline, Callout | `BodyTextBlockStyle` | |
| Footnote, Caption | `CaptionTextBlockStyle` (12/16, Regular) | Footers, dates, counts, secondary text |
| Monospaced | Cascadia Mono, Consolas as fallback | Code, source view |

Rules:

- Apple's bold is Fluent's SemiBold: Segoe UI Variable is used at Regular and SemiBold. Different by design.
- Use the theme text styles and font resources, never a font name. Nothing is smaller than 12 epx.
- The system **Text size** setting (100% to 225%) scales text automatically in standard controls, and WinUI text controls, `RichEditBox` included, already apply it through `IsTextScaleFactorEnabled` (true by default). **The editor scales once, never twice**: it keeps `IsTextScaleFactorEnabled` true and treats Zoom as a relative factor on top of the system size, as the iPad scales the Dynamic Type size; multiplying by `UISettings.TextScaleFactor` as well would double-scale the default size, and the character sizes the app sets may or may not be scaled by the control. The alternative is `IsTextScaleFactorEnabled` false on the editor with the app multiplying by `UISettings.TextScaleFactor` itself (and, in a `WebView2` editor, the CSS size multiplied once). The spike tests sizes at 225% and picks one of the two; the Zoom commands still work on top. Layouts reflow rather than truncate ([2.2](#22-layout-by-window-width)).
- Secondary text uses `TextFillColorSecondaryBrush`, disabled text the disabled brush; neither is used below the contrast the theme guarantees.

Source: [Typography](https://learn.microsoft.com/en-us/windows/apps/design/style/typography).

## 23 Icons

Segoe Fluent Icons (the system symbol font on Windows 11; Segoe MDL2 Assets is the Windows 10 fallback, which `SymbolThemeFontFamily` selects automatically). Use `FontIcon` or `SymbolIcon`, size 16 epx in menus and command bars, 20 in navigation and list rows, 48 for the large lock and success symbols. Icons are decorative (`AutomationProperties.AccessibilityView="Raw"`) when text is shown beside them; an icon-only button gets a name and a tooltip. Icons use the neutral foreground; the accent colour is for selected and toggled states only.

Every symbol the Apple app uses (found with a search of `apps/apple` for symbol names) and its Windows icon. Codes are Unicode code points in Segoe Fluent Icons.

| SF Symbol | Used for | Segoe Fluent Icons |
| --- | --- | --- |
| `lock` | Lock screen, lock items | Lock (E72E) |
| `lock.shield` | Encryption, Turn On Encryption | ShieldLock (F5B4) |
| `key` | Choosing a master password | Gap: Fluent UI System Icons "key" |
| `gearshape` | Settings; Writing and General pane | Settings (E713) |
| `square.and.pencil` | New Entry, New Entry In, Writing pane | Add (E710) for New entry; Edit (E70F) for the General pane |
| `folder.badge.plus` | New Journal | NewFolder (E8F4) |
| `book.closed` | A journal; journal labels; empty state | Library (E8F1) |
| `tray.full` | All Entries | List (EA37) |
| `doc.on.doc` | Templates; the template link; Copy | TwoPage (E89A) for Templates and the link; Copy (E8C8) for Copy |
| `trash` | Recently Deleted; Delete; Delete Journal | Delete (E74D) |
| `exclamationmark.folder` | Unavailable Journals | Folder (E8B7) with an attention `InfoBadge` |
| `pencil` | Rename | Rename (E8AC) |
| `doc.text` | Default Template | Document (E8A5) |
| `arrow.triangle.merge` | Merge Into | Gap: Fluent UI System Icons "merge" (MergeCall EA3C is a phone icon) |
| `clock.arrow.circlepath` | Version History | History (E81C) |
| `folder` | Move Entry; choose a file | MoveToFolder (E8DE) for Move; OpenFile (E8E5) for choose a file |
| `calendar` | Change Date | Calendar (E787) |
| `doc.badge.plus` | Save as Template | SaveCopy (EA35) |
| `pin`, `pin.slash` | Pin Entry, Unpin Entry | Pin (E718), Unpin (E77A) |
| `arrow.uturn.backward` | Restore | Undo (E7A7) |
| `ellipsis`, `ellipsis.circle` | Journal Actions, Entry Actions, overflow | More (E712) |
| `magnifyingglass` | Search, Find in Entry | Search (E721) |
| `checkmark` | Done; a chosen item | CheckMark (E73E) |
| `checkmark.circle` | Success states | Completed (E930) |
| `checkmark.square.fill`, `square` | Checklist boxes | The native `CheckBox` (CheckboxComposite E73A, Checkbox E739) |
| `xmark` | Close | Cancel (E711) |
| `minus` | Mixed selection | Remove (E738) or the indeterminate check box (E73C) |
| `textformat` | Formatting | Font (E8D2) |
| `list.bullet` | Bulleted List | BulletedList (E8FD) |
| `list.number` | Numbered List | Gap: Fluent UI System Icons "text number list" |
| `checklist` | Checklist | CheckList (E9D5) |
| `text.quote` | Block Quote | LeftDoubleQuote (E9B2) |
| `increase.indent`, `decrease.indent` | Indent | Gap: Fluent UI System Icons "text indent increase" and "decrease" |
| `photo` | Insert Image; image unavailable | Picture (E8B9) |
| `photo.on.rectangle` | Photo Library | Not offered ([26](#26-camera-photos-and-images)) |
| `camera` | Take Photo | Not offered; Camera (E722) if added later |
| `doc.richtext` | View Preview | Preview (E8FF) |
| `chevron.left.forwardslash.chevron.right` | View Source | Code (E943) |
| `exclamationmark.icloud` | Sync Status | SyncError (EA6A) |
| `exclamationmark.circle` | Errors; changes need review | Error (E783) |
| `chevron.right` | Disclosure on pane rows | ChevronRight (E76C), the `SettingsCard` default |
| `chevron.up.chevron.down` | Pickers | The `ComboBox` chevron |
| `rectangle.center.inset.filled` | Editor Only | Not used: Show editor only is a View-menu item without an icon, so there is no ClosePane and OpenPane glyph to swap |
| `arrow.triangle.2.circlepath` | Sync pane | Sync (E895) |
| `laptopcomputer.and.iphone` | Devices pane | Devices (E772) |
| `hand.raised` | Privacy pane | Shield (EA18) |
| `externaldrive` | Backup pane | SaveLocal (E78C) |
| `person.badge.key` | Agent Access pane | Robot (E99A) |
| `qrcode.viewfinder` | Scan Code | QRCode (ED14); not offered ([29](#29-qr-codes-and-add-device)) |
| `text.below.photo` | Image Descriptions | Gap: Fluent UI System Icons "image alt text" |
| `square.and.arrow.up` | Share | Share (E72D) |
| `square.and.arrow.down` | Save Image | SaveAs (E792) |
| `scissors`, `doc.on.clipboard` | Cut, Paste | Cut (E8C6), Paste (E77F) |

Also used by the Windows mapping, with no SF Symbol: the formatting bar's Bold (E8DD), Italic (E8DB), Underline (E8DC) and Strikethrough (EDE0), Undo and Redo (E7A7, E7A6), Zoom In and Zoom Out (E8A3, E71F), Full Screen (E740), Help (E897), Link (E71B), Export (EDE1), Import (E8B5), Save (E74E), Favorite (E734) for Rate My Journal, Previous and Next entry (Up E74A, Down E74B), Reveal password (the `PasswordBox` button).

**Gaps.** Segoe Fluent Icons has no numbered list, indent, outdent, merge, key or image-alt-text glyph. Use the Fluent UI System Icons for those (Microsoft's open-source SVG set, MIT licence) as embedded `PathIcon` or vector assets. That is a new dependency and needs a documented reason in the project that adds it.

Source: [Segoe Fluent Icons](https://learn.microsoft.com/en-us/windows/apps/design/style/segoe-fluent-icons-font).

## 24 Accessibility

The Apple rules ("VoiceOver, keyboard navigation, text sizing, reduced motion, increased contrast") become the following, and every mapping file's Accessibility section lists only what is specific to its screen.

| Area | Windows rule |
| --- | --- |
| Screen reader | **Narrator**, through UI Automation. Every control has a name (`AutomationProperties.Name` or a visible label with `LabeledBy`), a role from the control type, and its state. The names are the spec's accessibility copy keys. Decorative icons are hidden from the tree |
| Structure | The title and section headers have `AutomationProperties.HeadingLevel`; the navigation pane, entry list, editor and search box are landmarks (`AutomationProperties.LandmarkType`: Navigation, Main, Search); lists report position and size, including month groups |
| Editor | Exposes the UI Automation text pattern, the value and the selection; list markers and checkboxes are drawn, so they must be exposed as list items and toggle controls; images carry their description as the name. Spelling errors are exposed. **A ship gate, not a spike item**: the editor does not ship without a Narrator walkthrough script (a list, a checklist, a heading, an image with its description, a table) that passes on a real PC. The text pattern of `RichEditBox` exposes text and formatting runs, not drawn markers or overlay check boxes, so Spike A budgets a custom automation peer (a `RichEditBox` subclass supplying a derived `RichEditBoxAutomationPeer`); a `WebView2` editor starts from Chromium's tree, which already has list, check box, heading and table roles. See the entry-editor mapping |
| Announcements | Notification events and live regions ([11](#11-progress-and-announcements)); never a sound or a message that appears only visually |
| Keyboard | Everything is reachable without a pointer: Alt for the menu bar, Shift+F10 or the Menu key for context menus, F6 between panes, Tab and arrows inside controls, Esc closes transient UI and returns focus to its opener. No keyboard trap: Tab inserts a tab in lists, code and tables as the spec says, so F6 and Shift+F6 always leave the editor |
| Focus | Visible focus on every focusable element (the default focus visual, never disabled), correct in contrast themes. Focus never lands on a hidden column or pane; after a layout change it moves to the list or the editor |
| Access keys | Menu bar and toolbar access keys as in [4](#4-menus-and-toolbars) |
| Text size and scale | 100% to 225% text size and display scales up to 500% reflow the layout ([2.2](#22-layout-by-window-width)); nothing essential is truncated; dialogs and pages scroll. Mouse and keyboard targets are the controls' defaults (a default button is 32 epx tall); touch targets are at least 40 × 40 epx, which the touch-density templates give where they exist and the app sets explicitly where they do not |
| Contrast and colour | Contrast themes work in every state ([21](#21-theming-and-contrast)); no meaning by colour alone; text and icons meet the contrast of the theme's brushes |
| Motion | Honours the Animation effects setting |
| Voice and input | Text controls work with Windows voice typing (Win+H), the emoji panel (Win+.), the handwriting panel and input methods through the Text Services Framework ([25](#25-text-input-and-spelling)) |
| Languages | The `Language` of the content is set so Narrator speaks it correctly |
| Right to left | Right-to-left and bidirectional text are not part of version 1's languages and nothing blocks them: `FlowDirection` follows the content's language, back and indent glyphs and list markers mirror, and the caret order is the control's. A short test list is added when a right-to-left language ships |

Testing: Narrator with the keyboard only; the editor's Narrator walkthrough script on a real PC; each of the four contrast themes; text size at 100% and 225%; display scale 100% and 200%, including dragging the window between monitors of different scale (overlays and caret rectangles stay aligned); the Accessibility Insights for Windows checks. The tooling is a test lane, not a replacement for the design gate in [AGENTS.md](../../../AGENTS.md).

Sources: [Accessibility overview](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/accessibility-overview), [Basic accessibility information](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/basic-accessibility-information), [Keyboard accessibility](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/keyboard-accessibility), [Focus navigation](https://learn.microsoft.com/en-us/windows/apps/design/input/focus-navigation), [Text scaling](https://learn.microsoft.com/en-us/windows/apps/design/input/text-scaling), [Accessibility testing](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/accessibility-testing).

## 25 Text input and spelling

| Apple | Windows | Why |
| --- | --- | --- |
| System spelling and grammar, substitutions and corrections (`text-editing-system`); code and source stay literal (SP-1, SP-2) | The title and body use the Windows spell checker (`IsSpellCheckEnabled`) and follow Settings > Time & language > Typing (highlight misspelled words, autocorrect). There is no in-app spelling setting. Windows text controls have no system-wide smart-quote or dash substitution, so there is nothing to follow there; Markdown as you type is the app's own. Code blocks, inline code and source view turn spelling and text suggestions off, which a spike must confirm per range ([1](#1-target-and-toolkit)) | AGENTS.md: respect the system's spelling and correction preferences |
| Dictation, Emoji and Symbols | Voice typing (Win+H), emoji panel (Win+.), clipboard history (Win+V), handwriting panel: system features, nothing to implement beyond a correct text control | |
| Input methods compose text | The editor handles composition (Text Services Framework): no Markdown shortcut or format-as-you-type while composing, and Esc does not close a flyout or chooser while composing | Spec rule for the template chooser |
| Password fields with AutoFill | `PasswordBox`. Where the spec has a Show Password switch, and in the dialogs that set a new password twice (Change password, Set new password), the reveal control is a `CheckBox` that sets `PasswordRevealMode` ([Show password](./screens/settings.md#show-password), D41); a secure field without a switch in the spec (the lock page, Check your password, Open archive) keeps the built-in reveal button, which Alt+F8 also operates. Windows has no system AutoFill for native app fields, so the spec's password-autofill note does not apply | |
| Keyboard type per field | `InputScope`: Url for server addresses, Number for the nine-digit and two-digit codes, Password for passwords; the editor uses the default | The touch keyboard adapts |

## 26 Camera, photos and images

| Apple | Windows | Why |
| --- | --- | --- |
| Insert Image ▸ Photo Library (`insert-image-photo-library`) | Not offered. Windows has no photo-library API for apps; the Pictures folder is reached with Choose File | A library to browse does not exist on Windows |
| Insert Image ▸ Take Photo (`insert-image-take-photo`), only with a usable camera | Not offered in version 1. Desktop PCs often have no suitable camera; the Windows Camera app, the Snipping Tool (Win+Shift+S) and paste or drag cover the need. A later version may offer it as an in-app capture dialog, only when a camera is present and the Camera privacy setting allows it. **Decision needed** (D24) | Keeps the first release small and the camera permission out |
| Insert Image ▸ Choose File | **Image…**: `FileOpenPicker` starting in Pictures. Also paste (a bitmap or file from the clipboard) and drag and drop from Explorer or a browser | Windows idiom |
| Save to Photos | Not offered; Save Image As… (`FileSavePicker`) | |
| Share | Windows Share ([27](#27-sharing)) | |
| HEIC and other formats | Formats follow [flows/insert-image](../../flows/insert-image.md). HEIC and HEIF need the HEIF codecs Windows installs from the Store; a file that cannot be decoded takes the existing unreadable-image path | |
| Picture size from its resolution | An image's size comes from its resolution metadata when it has one, otherwise 96 dpi, scaled to fit the text width, and decoded at the display's pixel size so it stays sharp at high scale | |
| Image descriptions | The description is the picture's UI Automation name and the picture's tooltip is not set (descriptions may be private) | |

## 27 Sharing

| Apple | Windows | Why |
| --- | --- | --- |
| Share (`image-share`): the system share sheet with the original file, named `editor.image.fileName` plus its extension | The Windows Share UI: `IDataTransferManagerInterop.GetForWindow(hwnd)` and `ShowShareUIForWindow(hwnd)` for a desktop window. The data package holds the original file, written to a temporary file named as on Apple; failure shows `editor.image.shareFailed` | The documented desktop pattern for WinUI 3 |
| Share the MCP address (iPhone and iPad) | Not offered; Copy only, as on the Mac | A desktop |
| Receiving shares or file shares from other apps | Not offered | Not in the spec |

Source: [Share content from your app](https://learn.microsoft.com/en-us/windows/apps/develop/windows-integration/integrate-sharesheet-send).

## 28 Rating

| Apple | Windows | Why |
| --- | --- | --- |
| Rate My Journal (`help-rate`, `about-rate`): opens the App Store review page | Opens the Store review page for the app: `ms-windows-store://review/?ProductId=` followed by the Store product ID. Hidden in builds that are not from the Store (`Package.Current.SignatureKind`) | Documented Store link |
| The platform's own rating prompt, asked at a natural pause by the rules in [flows/rating-request](../../flows/rating-request.md) | `StoreContext.RequestRateAndReviewAppAsync()`, called on the UI thread after initialising the `StoreContext` with the window handle. The Store shows its own dialog, and unlike the Apple prompt it is not throttled by the system, so the app's own rules (writing on five days, 120 days apart) are the only limit. The request is recorded whether or not anything shows. A failure is ignored silently | Store rule: the app shows no rating prompt of its own, and it never sorts feedback by star rating |

Sources: [Request ratings and reviews](https://learn.microsoft.com/en-us/windows/uwp/monetize/request-ratings-and-reviews), [Launch the Microsoft Store app](https://learn.microsoft.com/en-us/windows/uwp/launch-resume/launch-store-app), [RequestRateAndReviewAppAsync](https://learn.microsoft.com/en-us/uwp/api/windows.services.store.storecontext.requestrateandreviewappasync).

## 29 QR codes and Add Device

| Apple | Windows | Why |
| --- | --- | --- |
| Add Device on the approving device shows a QR code (`settings.addDevice.scanInstructions`) that a new device scans | Show it. The code is generated with a small QR library and drawn as a bitmap on a white tile with its quiet zone, dark on light in every theme (a QR code inverted in dark mode or a contrast theme does not scan), at least 200 epx square. Below it, **Enter Code Instead** (`add-device-enter-code`) is always one step away | A code that cannot be scanned must still be usable another way |
| A new device shows a nine-digit code (Add This Device) that the approving device types, then both compare a check code | Same on Windows, as the new device and as the approving device. The digits are selectable text with a Copy button, copied with the clipboard options in [15](#15-clipboard) | Pairing by typing needs no camera |
| Scan Code on iPhone and iPad (`connect-scan-code`, `scan-cancel`, `scan-open-settings`) | **Not offered in version 1.** Windows has no built-in camera barcode scanner for desktop apps; scanning needs `MediaCapture`, the Webcam capability and a decoder library, and many PCs have no camera. A Windows PC joining a server uses the typed-code path (Add This Device); a Windows PC that approves can show its QR code or take the typed code. Full capability is kept: pairing never needs a camera. **Decision needed** (D24) | |
| Camera permission alert | Not shown. If a scanner is added: Settings > Privacy & security > Camera, opened with `ms-settings:privacy-webcam` | |

## 30 Sync, lifecycle and power

Windows desktop apps keep running while open; there is no background-task budget like iOS's, and the app does not run when closed (version 1). The pace and rules are those of [flows/sync-recovery](../../flows/sync-recovery.md); only the triggers differ.

| Spec trigger | Windows source |
| --- | --- |
| "Active app" pace (every 3 seconds) and "open, another app active" pace (every 30 seconds) | The window's activation state; a minimised window counts as inactive |
| At once when the app becomes active or returns from the background | The window is activated, the PC resumes from sleep, the session unlocks |
| At once when the network returns | `NetworkInformation.NetworkStatusChanged` (or the .NET network-change event); the waiting retry runs immediately |
| After a pause in writing, and on leaving an entry | Same |
| Up to 3 seconds of sending on quit | On window close and at end of session, the app flushes writing for up to 3 seconds, then closes |
| iOS background time for saving | Not needed: the app is not suspended; at sign-out or shutdown the app holds shutdown briefly while a save finishes ([3](#3-windows-and-instances)) |
| Background sync when closed | Not offered. A packaged app could use a background task or a start-up task, but a journal gains nothing from syncing unseen, and the app would run without a window. Changes from other devices arrive the next time it opens |
| Metered connections | Not treated specially in version 1; a mapping may add a pause for large image transfers on metered networks |

Source: [NetworkInformation.NetworkStatusChanged](https://learn.microsoft.com/en-us/uwp/api/windows.networking.connectivity.networkinformation.networkstatuschanged).

## 31 Dates, time zones and formats

| Topic | Windows |
| --- | --- |
| Date, time and number formats | The user's regional format (Settings > Time & language > Language & region). Use `DateTimeFormatter` or the current .NET culture, which follows it; the 12 or 24 hour clock and the calendar come from the same setting. Never hard-code a pattern for people |
| Calendar systems | Entry times are instants; display uses the user's calendar (Gregorian, Hijri, Buddhist and others), and Change Date uses `CalendarDatePicker` alone, which honours the calendar and the first day of the week (the spec's Change Date is date only: the entry keeps its time of day, so there is no `TimePicker`) |
| Time zone | Entries are grouped and shown in the local time zone, including "Yesterday" and the month headers. The app refreshes when the zone, the clock or the regional format changes (`WM_TIMECHANGE` and `WM_SETTINGCHANGE`) and at local midnight |
| Relative words | "Just now", "Yesterday at {time}" and "{day} at {time}" ([copy/en.json](../../copy/en.json): `settings.sync.lastSynced.*`) are built in the app; the time part uses the formatter |
| File names with a date | `{date}` in archive and export names uses the same fixed form on every platform, not the regional format, so files sort ([copy/en.json](../../copy/en.json): `settings.backup.archiveFilename`) |
| Plurals and numbers | Pluralisation uses the culture's rules, not only one and other, once a second language ships |

## 32 Local network and servers

| Apple | Windows | Why |
| --- | --- | --- |
| Bonjour discovery behind the Local Network permission (`settings.connect.nearby`, with `settings.connect.nearby.denied`) | DNS-SD discovery with `DnssdServiceWatcher`. A full-trust packaged desktop app needs no permission prompt or capability; Windows Defender Firewall can still block replies on some networks, in which case discovery simply finds nothing and the person types the address. `settings.connect.nearby.denied` is not shown | No OS permission exists to ask for |
| Certificates | The Windows certificate store; a server with a private certificate authority needs that authority installed as trusted. The messages for an invalid certificate are unchanged | |
| Proxies | The system proxy settings apply through the standard HTTP stack | |
| HTTPS only in pairing codes in release builds | Same | |

## 33 Summary of departures from the Apple app

Each row is "different by design" unless a decision is pending; the reasons are in the section named.

| Departure | Section |
| --- | --- |
| Custom title bar, Mica, `NavigationView` shell with the built-in Settings item; window title always "My Journal", never a journal name | [2](#2-app-shell-and-window) |
| Narrower layouts and a lower minimum window size; text-scale-driven layout step | [2.2](#22-layout-by-window-width) |
| One window; closing the window ends the app; no Window menu | [3](#3-windows-and-instances) |
| Menu bar (File, Edit, Format, View, Help) plus command bars, hidden on the lock and first-launch pages; a toggleable formatting bar and a selection mini-toolbar instead of a popover; Show editor only and View source are menu-only; Sync status in the title bar; Settings and Exit under File; About under Help | [4](#4-menus-and-toolbars) |
| Shortcut set: Ctrl+Y, F2, F3, F1, F11, Ctrl+H, Ctrl+E, Ctrl+Shift+digits for headings, no Ctrl+Alt chords at all; Esc never Back; hidden Ctrl+S | [7](#7-keyboard-shortcuts) |
| ContentDialog button order; no dialog on a dialog; error dialogs without the generic title | [8](#8-dialogs) |
| Pages instead of sheets for large reviews and for the multi-step flows (connect, turn on encryption, import); `InfoBar` notices | [9](#9-sheets-popovers-and-notices) |
| Settings as a page in the main window, About inside it, General instead of Writing | [10](#10-settings) |
| Sentence case, ellipsis rule and Windows vocabulary variants | [12](#12-copy-casing-ellipses-and-vocabulary) |
| Windows 11 (build 22000) only; Windows Hello only; no PIN; App Lock pauses when Hello cannot be used; lock on session lock, display off, lid and sleep; lock page replaces the window | [13](#13-device-authentication-and-app-lock) |
| DPAPI for secrets; device key unavailable is a first-class path | [14](#14-secure-storage) |
| Clipboard history exclusion for secrets | [15](#15-clipboard) |
| Windows-safe file names; a folder picker for Markdown; one-file archives with the Open and Save pickers (D29) | [16](#16-files-and-pickers) |
| Single instance; a `.journalarchive` file association (D29) | [19](#19-single-instance-and-activation) |
| No cover on deactivation; capture exclusion with a Privacy switch, pending an accessibility spike | [20](#20-screen-capture-and-window-privacy) |
| SemiBold instead of bold; Cascadia Mono; text scale applied once in the editor | [22](#22-typography) |
| No Photo Library, Take Photo, Save to Photos, Scan Code, Local Network prompt | [26](#26-camera-photos-and-images), [29](#29-qr-codes-and-add-device), [32](#32-local-network-and-servers) |
| No background sync when closed | [30](#30-sync-lifecycle-and-power) |

## 34 Open questions

Everything open about the Windows mapping is in [open-questions.md](../../open-questions.md), sections B and D. Section D, D20 to D54. After the independent review ([review-2026-10-06.md](review-2026-10-06.md)) every question below has a drafted default that follows the reviewer's recommendation where the reviewer gave a reason; the owner can still change any of them.

- **Platform decisions (D20 to D28):** D20 menu model, formatting bar and the chrome of the lock and first-launch pages, D21 sentence case (a `sentence` variant shared with Android) and Windows vocabulary, D22 Windows 11 as a requirement, distribution and uninstall data loss, D23 closing the window ends the app, D24 camera, photo library and Scan Code absent in version 1, D25 Windows Hello only and organization policy, D26 Settings as an in-app page with About and Erase placement, D27 shortcut set and the hidden Ctrl+S, D28 screen capture exclusion (no cover on deactivation).
- **Needs the owner (D29 to D54, from the mapping files and the review):** D29 the archive as one file, D34 text keys the spec does not define, D35 spell check in code, D37 find and replace, D38 counts in the navigation pane, D39 Back with unsaved descriptions, D40 text without key presses, D41 Show password control, D42 App lock when Hello cannot be used, D43 device key that cannot be saved again, D44 Erase warning buttons, D45 device name, D47 where Sync status lives, D48 failed save while typing, D49 Sync page message surface, D50 side-by-side reviews, D51 update link, D52 journal review entry point, D53 the rating request, D54 a second prompt after Win+L.
- **Technical spikes, with a decision attached:** D30 the editor control (Spike A and Spike B in parallel), D31 the undo model, D32 how Narrator reads what the editor draws (a ship gate), D36 the clipboard format.

Windows copy questions are B26 to B41; the rows themselves are in [copy-proposals.md](copy-proposals.md).

Other technical spikes the mapping files depend on, which are not product questions:

1. **The journals list in the navigation pane**: a `ListView` in the pane's custom content with drag and keyboard reordering, sharing one selection with the `NavigationView` items, with the `SplitView` fallback ([2.1](#21-controls)).
2. **The shell's keyboard and title bar:** the three accelerator behaviours of [7](#7-keyboard-shortcuts) (rule 7), Alt access to the `MenuBar` inside the `TitleBar` and its drag regions, and every accelerator on the four keyboard layouts.
3. **Capture exclusion and accessibility** ([20](#20-screen-capture-and-window-privacy)): both flags on a Copilot+ PC, with Windows Magnifier, Narrator and Quick Assist.
4. **TPM-wrapped secret** and **Credential Locker roaming** ([14](#14-secure-storage)).
5. **Window-ID-based pickers** in the Windows App SDK version in use ([16](#16-files-and-pickers)).
6. **First-build checks of claims no document settles:** Remote Desktop behaviour of `UserConsentVerifier`, the capabilities `DnssdServiceWatcher` needs for a packaged full-trust app, and how `RichEditBox` applies the system text scale to character formats ([22](#22-typography)).

## Sources

All checked on 2026-10-06.

- Title bar: [customization](https://learn.microsoft.com/en-us/windows/apps/develop/title-bar), [control](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/title-bar), [design](https://learn.microsoft.com/en-us/windows/apps/design/basics/titlebar-design). Materials: [Mica](https://learn.microsoft.com/en-us/windows/apps/design/style/mica).
- Navigation and layout: [NavigationView](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/navigationview), [breakpoints](https://learn.microsoft.com/en-us/windows/apps/design/layout/screen-sizes-and-breakpoints-for-responsive-design), [BreadcrumbBar](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/breadcrumbbar).
- Commands: [menus and menu bar](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/menus), [command bar](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/command-bar), [swipe](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/swipe), [keyboard accelerators](https://learn.microsoft.com/en-us/windows/apps/develop/input/keyboard-accelerators), [access keys](https://learn.microsoft.com/en-us/windows/apps/develop/input/access-keys).
- Surfaces: [dialogs](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs), [flyouts](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/flyouts), [InfoBar](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobar), [progress](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/progress-controls), [SettingsCard](https://learn.microsoft.com/en-us/dotnet/communitytoolkit/windows/settingscontrols/settingscard).
- Writing: [capitalization](https://learn.microsoft.com/en-us/style-guide/capitalization), [ellipses](https://learn.microsoft.com/en-us/style-guide/punctuation/ellipses), [describing interactions with UI](https://learn.microsoft.com/en-us/style-guide/procedures-instructions/describing-interactions-with-ui), [keys and keyboard shortcuts](https://learn.microsoft.com/en-us/style-guide/a-z-word-list-term-collections/term-collections/keys-keyboard-shortcuts).
- Security and platform: [UserConsentVerifier](https://learn.microsoft.com/en-us/uwp/api/windows.security.credentials.ui.userconsentverifier), [KeyCredentialManager](https://learn.microsoft.com/en-us/uwp/api/windows.security.credentials.keycredentialmanager), [ProtectedData](https://learn.microsoft.com/en-us/dotnet/api/system.security.cryptography.protecteddata), [SetWindowDisplayAffinity](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowdisplayaffinity), [Recall](https://learn.microsoft.com/en-us/windows/apps/develop/windows-integration/recall/), [packaging](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/packaging/), [single instance](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/applifecycle/applifecycle-single-instance), [Store ratings](https://learn.microsoft.com/en-us/windows/uwp/monetize/request-ratings-and-reviews).
- Design: [typography](https://learn.microsoft.com/en-us/windows/apps/design/style/typography), [Segoe Fluent Icons](https://learn.microsoft.com/en-us/windows/apps/design/style/segoe-fluent-icons-font), [accessibility](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/accessibility-overview), [contrast themes](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/high-contrast-themes), [text scaling](https://learn.microsoft.com/en-us/windows/apps/design/input/text-scaling).
