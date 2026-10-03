# Mac journal window on AppKit split view and toolbar

**Status:** approved with required changes (independent design review, 29 September 2026). The required changes and the owner's decisions are incorporated below; §6 records the review outcome. Implementation starts with the Phase 1 spike.

**Owner request (29 September 2026):** "fix it properly we can't have these half baked solutions we need proper macos tooling for this. And also the interaction is weird when you open close the side panel. the new journal icon should not be there when it's closed. Just copy the notes app it's simple".

## Problem

The Mac window is a SwiftUI three-column `NavigationSplitView`. Each column adds its own toolbar content with `.toolbar`, and SwiftUI turns that into the window's `NSToolbar`. Four problems follow from that, and none of them can be fixed from SwiftUI:

- **Section boundary in the wrong place.** With the sidebar collapsed, SwiftUI puts the boundary between the list's and the editor's toolbar sections at a fixed x (about 432 pt), whatever the list's real width. Items spill over the divider, and a short stray separator shows next to the editor's Formatting group.
- **New Journal stays when the sidebar is closed.** The sidebar's New Journal toolbar button remains visible with the sidebar collapsed.
- **`.detailOnly` is ignored.** macOS ignores it in a three-column split view. Editor only therefore squeezes the list to 0 pt (`ListColumnWidth`) while hiding the sidebar.
- **Workarounds.** Transitions flash the » overflow chevron. The workarounds pile up: a 360 pt list minimum while the sidebar is hidden, a search width computed from a measured `detailWidth`, a `detailWidth` reset on every layout change, and `ToolbarSpacer` tuning.

Notes and Mail don't show these problems because they are built on `NSSplitViewController` and an `NSToolbar` with tracking separators. This proposal moves the Mac window's *frame* (split view and toolbar) to those AppKit classes. The column *contents* stay in SwiftUI.

## 1. Research

**AppKit facilities (Apple documentation):**

- [`NSSplitViewController`](https://developer.apple.com/documentation/appkit/nssplitviewcontroller) with [`NSSplitViewItem`](https://developer.apple.com/documentation/appkit/nssplitviewitem) behaviors:
  - `init(sidebarWithViewController:)`, `init(contentListWithViewController:)` and `init(viewController:)` (detail).
  - Each item has `isCollapsed`, `canCollapse`, `canCollapseFromWindowResize` (macOS 14), `minimumThickness`, `maximumThickness`, `preferredThicknessFraction`, `holdingPriority` and `titlebarSeparatorStyle`.
  - `allowsFullHeightLayout` defaults to true for sidebars.
  - `toggleSidebar(_:)` is the standard action. It animates the collapse and validates the View menu's Show/Hide Sidebar title.
- **Toolbar separators.**
  - [`NSToolbarItem.Identifier.sidebarTrackingSeparator`](https://developer.apple.com/documentation/appkit/nstoolbaritem/identifier/sidebartrackingseparator) (macOS 11) "visually aligns itself with the sidebar divider of a vertical split view in the same window".
  - [`NSTrackingSeparatorToolbarItem(identifier:splitView:dividerIndex:)`](https://developer.apple.com/documentation/appkit/nstrackingseparatortoolbaritem) (macOS 11) does the same for any other divider. Its purpose is keeping toolbar items "above the content that they target".
  - `.toggleSidebar` is the standard sidebar button.
  - **Toolbars that share an identifier are synchronized.** AppKit keeps every `NSToolbar` with the same identifier in the same configuration, in every window of the app, and autosaves that configuration. A second journal window hiding its title or removing its list items would change the first window too.
  - AppKit places the window title at the leading edge of the section after the sidebar separator. Mail shows the mailbox name there, above the message list.
- [`NSSearchToolbarItem`](https://developer.apple.com/documentation/appkit/nssearchtoolbaritem) (macOS 11) is the native toolbar search:
  - When space is short it collapses to a button and expands when clicked.
  - `beginSearchInteraction()` focuses it, and `preferredWidthForSearchField` sets its width.
  - `searchField` can be replaced, so our `FocusReportingSearchField` can be kept.
- **Other APIs:**
  - [`NSPopover.show(relativeTo: NSToolbarItem)`](https://developer.apple.com/documentation/appkit/nspopover/show(relativeto:)) (macOS 14) anchors a popover to a toolbar item, including one that has moved into the overflow menu.
  - `NSToolbarItem.isHidden` needs macOS 15.
  - `NSHostingController.sceneBridgingOptions` (macOS 14) defaults to `[]` for a controller that isn't the window's `contentViewController`, so the hosted columns don't write to the window's toolbar or title.
- **Liquid Glass on macOS 26.** Sources: [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) and [WWDC25 session 310, "Build an AppKit app with the new design"](https://developer.apple.com/videos/play/wwdc2025/310/).
  - Standard `NSToolbar`, `NSSplitView` and control items adopt glass automatically.
  - AppKit groups adjacent toolbar buttons on one piece of glass, and a search field or pop-up gets its own. Spacers or `NSToolbarItemGroup` split the groups.
  - `isBordered = false` removes glass from non-interactive items.
  - Sidebars from `NSSplitViewController` float as a pane of glass. Remove any `NSVisualEffectView` behind them.
  - `NSSplitViewItemAccessoryViewController` (top or bottom of one split) gets the scroll edge effect.
  - "Use `NSToolbarItem.isHidden`" (hide the whole item, never just its view) and "remove empty toolbar items".

**Apple Notes** (Notes User Guide for [macOS 15](https://support.apple.com/guide/notes/add-and-remove-folders-apd558a85438/4.12/mac/15.0) and [macOS 26](https://support.apple.com/guide/notes/add-and-remove-folders-apd558a85438/4.13/mac/26), [View your notes](https://support.apple.com/guide/notes/view-your-notes-apd8b73d28be/mac)):

- **Layout.** Folders are in the sidebar on the left, the note list is in the middle, and the note is on the right. View › Show/Hide Sidebar toggles the sidebar. The note list can't be hidden; Show Editor Only is our addition, modelled on Bear.
- **New Folder.**
  - The macOS 15 guide says "Choose File > New Folder, or click New Folder at the bottom of the sidebar."
  - The macOS 26 guide only says "Click File > New Folder."
  - Neither version puts New Folder in the toolbar. The only control in the sidebar's toolbar section is the sidebar button next to the window buttons.
  - That button follows the window buttons when the sidebar collapses, so anything else in that section would stay behind. That's exactly our New Journal bug.
  - Finder and Notes use ⇧⌘N for New Folder. In My Journal ⇧⌘N is already New Blank Entry, so New Journal keeps ⌥⌘N.
- **List section.** The view switch (List/Gallery) and Delete.
- **Editor section.** New Note at its leading edge, then Format (Aa), checklist, table and media. Share, lock and search are at the trailing end, with search last.
- **Customization.** Notes allows toolbar customization.

**Notes 26 on the owner's Mac** (screenshots from the owner, 29 September 2026; these supersede the guides above where they differ):

- **Sidebar open.** The sidebar's toolbar section holds the window buttons, then one glass capsule with New Folder and the sidebar button.
- **List section.** At its leading edge a two-line title: the folder name in bold (for example "All iCloud") over a secondary count ("634 notes"). A circular "…" button sits at the section's trailing edge.
- **Editor section.** New Note (compose) at its leading edge in a capsule of its own; the formatting capsule (Aa, checklist, table, attachment) in the centre; [Share …] at the trailing end, then a wide search field, last.
- **Sidebar closed.** New Folder disappears with the sidebar. The capsule beside the window buttons holds only the sidebar button, followed by the two-line title and "…", then the editor section. Notes shows a thin native line at the list/editor boundary of the toolbar.
- There's no New Folder button at the bottom of the sidebar.

## 2. Architecture

**Scene shell stays SwiftUI.** `WindowGroup(id: "journal")`, `.commands`, `Settings`, `@SceneStorage`, `scenePhase`, `openWindow`, `WindowCloseGuard`, and every sheet and alert in `RootView` stay as they are. Only `RootView.mainNavigation` changes on macOS: it shows `MacJournalWindow` (an `NSViewControllerRepresentable`) instead of `macSplitView`. iOS and iPadOS code paths are untouched.

**`JournalSplitViewController: NSSplitViewController`** (new, `Views/Mac/`). It has three items, each hosting an existing SwiftUI column in an `NSHostingController`:

| Item | Content | Min | Preferred | Max | Collapse |
|---|---|---|---|---|---|
| `sidebarWithViewController` | `JournalSidebarView` | 210 | 230 | 320 | by user and by window resize |
| `contentListWithViewController` | the entry list (`sidebar` today) | 360 | 360 | 460 | only by Show Editor Only; dragging stops at the minimum |
| `viewController` (detail) | `detail` | 440 (with the divider) | rest | — | never |

*Values as implemented (§7): the Phase 1 measurements raised the list minimum from 300 to 360.*

- **Holding priorities.** The detail has the lowest holding priority, so window resizing goes to the editor.
- **Window size.** The window's minimum content width becomes 801 (list, divider and detail; 740 was proposed before the Phase 1 measurements, §7). A narrower window collapses the sidebar, as Notes does, instead of squeezing a column or overflowing the toolbar. `JournalApp`'s `.frame(minWidth: 930)` becomes `minWidth: 801`.
- **Which column gives way, in order,** as the window narrows with all columns shown:
  1. The detail shrinks, down to 440.
  2. The list shrinks, down to 360. The sidebar keeps its width.
  3. Below 1011 (210 + 360 + 440 and a divider) the sidebar collapses. The controller does this itself from the window's width; the list never collapses from a resize, and the detail never goes below 440, so the toolbar never overflows.
  4. The window can't be narrower than 801 in any layout, including editor only, so the minimum doesn't change with the layout.
- **Widening again** doesn't bring the sidebar back by itself. Showing the sidebar in a window narrower than 1011 widens the window, as AppKit does for a sidebar. In full screen the screen is always wide enough: every supported display is at least 1024 pt wide.
- **List minimum.** It is one constant for both layouts. With the sidebar hidden, the list's toolbar section holds the window buttons, the sidebar button, the two-line title and "…", and AppKit needs about 355 pt for them; narrower, the section and every item after it moved past the divider (measured in Phase 1). One constant keeps the list's width when the sidebar hides.
- **Separators and safe area.** `titlebarSeparatorStyle = .none` for every item, as already decided. `automaticallyAdjustsSafeAreaInsets` stays false: the list sits beside the sidebar, as in Notes, not under it.
- **Full height under the titlebar.** The window keeps SwiftUI's full-size content view, and the representable ignores the top safe area (`.ignoresSafeArea()`), so the split view starts at the window's top edge. The sidebar is then full height, as in Notes, and the tracking separators line up with the real dividers. The list and detail keep their own top safe area inset for the toolbar.
- **No split view autosave.** `NSSplitView` autosave also restores collapsed states, which would restore a layout behind `SceneStorage`'s back. Instead the sidebar and list widths are kept per window with the layout in `@SceneStorage("windowColumns")`, reported when a divider drag ends. Widths and collapsed states are applied when the controller's view is created, before the window is shown, without animation, so a restored window never flashes another layout at launch.
- **Environment.** Each hosting controller's root view gets `.environmentObject(model)` and `.environmentObject(editor)`, because the environment doesn't cross into a separate hosting controller.
- **Column content (implementation change, smaller than the extraction first proposed).** `RootView` keeps building the three columns (`JournalSidebarView`, `listedSidebar`, `detail`) and hands them to the representable, which sets each hosting controller's `rootView` on every update. Their state stays in `RootView` `@State`, so sheets, alerts and row actions are unchanged, and the iPad code isn't touched. The list keeps its `Isolated` comparison, so an update that doesn't change the list costs no more than today. Extracting `EntryListColumn` and `EditorColumn` structs is left for a later refactor.
- **Scene bridging.** Every column's `sceneBridgingOptions = []`, and Mac column views must not use `.toolbar` or `.navigationTitle`.

**`JournalToolbarController: NSObject, NSToolbarDelegate`** (new). It owns one toolbar per window:

- **Toolbar setup.**
  - **A unique identifier per window**, `"JournalWindow-‹UUID›"`, with `autosavesConfiguration = false`. Toolbars sharing an identifier are synchronized across windows (§1), so one window's layout would otherwise rearrange the others. `NSToolbarItem.isHidden` would also avoid this, but needs macOS 15.
  - `displayMode = .iconOnly`, `allowsUserCustomization = false` (as today).
  - The unified style comes from the `.windowToolbarStyle(.unified(showsTitle: true))` scene modifier, so SwiftUI owns it and doesn't reset it on an update. The controller sets `window.title` and `titleVisibility`; the spike checks that SwiftUI never overwrites them.
  - It is installed in `viewDidAppear` and removed in `dismantleNSViewController`, so the locked, welcome and recovery screens have no toolbar, as today.
- **Items.**
  - They are native `NSToolbarItem`s with SF Symbol images and target/action, never `NSHostingView` wrappers, so macOS 26 glass grouping and the overflow menu behave natively.
  - Menus are `NSMenuToolbarItem` with `showsIndicator = false`.
  - A small `ToolbarState` observer (Combine on `AppModel`, `EditorActions` and `JournalWindowState`) updates `isEnabled`, images, tooltips and labels. It inserts or removes the conditional items listed in §3.
  - Insert and remove are used rather than `isHidden`, so one path works from macOS 14 onward.
- **Entry Actions menu.** It is built in `menuNeedsUpdate` from a new `EntryActionCatalog`: titles, symbols, enabled state, destructive role and handler. The row context menu in SwiftUI uses the same catalog, so the two can't drift.
- **Journal Actions menu** (the list section's "…"). Built the same way from the journal actions the sidebar row's context menu offers.
- **Popovers.**
  - Formatting and Templates… open with `NSPopover.show(relativeTo: item)`, using `FormattingPopover` and `TemplateChooserView` in `NSHostingController`.
  - The existing Escape and outside-click behavior is kept: the popover closes at once on Escape even with text in its field, from pre-release-ui-2026-09-27.
  - `FormattingAnchor`'s view anchor goes.
- **Search.** `NSSearchToolbarItem` whose `searchField` is the existing `FocusReportingSearchField`.
  - The `MacJournalSearchField` delegate logic moves into the controller.
  - `preferredWidthForSearchField = 200` (§3).
  - Search Entries (⌥⌘F) calls `beginSearchInteraction()`.
  - `searchFieldWidth` and `detailWidth` measuring go.

**Editor only, natively.** `WindowColumns` is rewritten as `enum Layout { case all, sidebarHidden, editorOnly(returnTo: all | sidebarHidden) }` with the same rules as today.

- **Entering** remembers the layout. **Leaving** through the Editor Only toggle, ⇧⌘D, search or New Journal restores it.
- **Show/Hide Sidebar always ends in a plain layout.** ⌃⌘S and the sidebar button toggle between all columns and sidebar hidden. In editor only they end in **all columns**: the user asked for the sidebar, and a restored "sidebar hidden" would show nothing they asked for. Only the Editor Only toggle and ⇧⌘D restore the remembered layout.
- **Applying a layout.** The split view controller sets `isCollapsed` on the sidebar and list items: through `animator()` in one `NSAnimationContext` group, or directly when `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` is on.
- **Reduce Motion on every path.** `toggleSidebar(_:)` is overridden, so the menu command, ⌃⌘S and the sidebar button all go through the same layout code, which skips the animation with Reduce Motion on. The standard implementation would always animate.
- **Collapse by the system.** Each split item's `isCollapsed` is observed with key-value observing. A collapse the split view does itself (window resize, divider drag) updates the layout; a change the controller is applying is ignored. `splitViewDidResizeSubviews` isn't used: it fires for every resize and doesn't say what collapsed.
- **Storage and migration.** `@SceneStorage("windowColumns")` keeps its key. Old raw values migrate: `all,*` → `all`, `doubleColumn,*` → `sidebarHidden`, `detailOnly,X` → `editorOnly(returnTo: X)`.
- **What goes away.** `.detailOnly`, `splitViewVisibility`, `columnVisibility` and `ListColumnWidth` go. `EditorOnlyCommand` and its `focusedSceneValue` stay in `RootView`, calling into `JournalWindowState`.

**Commands, focus and accessibility:**

- **Menus.**
  - Show/Hide Sidebar (`SidebarCommands`) sends `toggleSidebar:` through the responder chain.
  - Toolbar views aren't in the split view controller's chain, so the window-delegate proxy that `WindowCloseGuard` already installs forwards `toggleSidebar:` (and validation) to the controller. The menu then works while the search field has focus.
  - Show Editor Only, Previous/Next Entry, New Journal and Search Entries keep their current focused-value and model plumbing.
- **Focus.**
  - Before a column collapses, if the first responder is inside it, focus moves to the list, or to the editor in editor only (today's rule).
  - The key-view loop runs sidebar → list → editor. The toolbar is reached with ⌃F5/Full Keyboard Access, as usual.
- **VoiceOver.** Collapsed split items are hidden views, so VoiceOver and Tab skip them without the `accessibilityHidden` hack. Every toolbar item has a label equal to its title. Editor Only is an `NSButton` toggle that reports its on/off value.
- **Windows.** `allowsAutomaticWindowTabbing = false` and the missing New Window command already give one journal window. Each restored window gets its own controllers and `JournalWindowState`, so nothing is global.

**Replaced vs kept:**

| File | Replaced (macOS only) | Kept |
|---|---|---|
| `RootView.swift` | `macSplitView`, `detailWidth` GeometryReader, `.toolbarBackground`, the `onChange` width reset, the list `.navigationTitle` on Mac | Scene body, sheets and alerts, the iOS and iPad split view and stacks. The column builders move to structs and are still used by iOS. |
| `RootView+Toolbar.swift` | `searchFieldWidth`, `sidebarHidden`, the Mac branches of `listToolbar` and `mainToolbar`, `editorOnlyButton` | iOS branches, `searchPrompt`, `sourceModeButton`, `insertImageButton`, `syncMenu` (iOS), `entryMenu` (iOS, now from the catalog) |
| `EditorOnlyLayout.swift` | `columnVisibility`, `ListColumnWidth` | `EditorOnlyCommand`, `focusedSceneValue`, `showsEmptyListInEditor`, `leaveEditorOnly` triggers |
| `WindowColumns.swift` | the `NavigationSplitViewVisibility` model | Its rules, re-expressed as `Layout`, plus raw-value migration |
| `MacJournalSearchField.swift`, `MacFormattingButton.swift` | the `NSViewRepresentable` wrappers | `FocusReportingSearchField`, the popover content and event monitor |
| `JournalSidebarView.swift` | the SwiftUI Mac toolbar New Journal (now a native sidebar-section item) | iPad toolbar New Journal (unchanged) |

## 3. Notes-parity interaction spec

Revised on 29 September 2026 to follow the owner's Notes 26 screenshots (§1), which supersede the first reviewed version of this section. The toolbar in each layout, leading to trailing. `|` marks a tracking separator, and `[a b]` is one glass group on macOS 26.

**All columns:**

- **Sidebar section:** the window buttons, then [New Journal, Toggle Sidebar] over the sidebar.
  - New Journal: symbol `folder.badge.plus`, label and tooltip "New Journal", ⌥⌘N in the File menu. It opens the existing New Journal alert.
- **List section:**
  - At the leading edge, `window.title` and `window.subtitle`, which AppKit draws as a two-line title in the unified toolbar (no custom item):
    - title: the collection ("‹Journal name›", "Untitled Journal" for a journal without a name, "All Entries", "Templates", "Recently Deleted" or "Unavailable Journals"), truncated with an ellipsis when long;
    - subtitle: the collection's count, not the search results', formatted for the locale with plural rules: "1 entry" / "1,234 entries" (a journal, All Entries, Unavailable Journals), "1 template" / "3 templates" (Templates), "1 item" / "5 items" (Recently Deleted);
    - empty: "No Entries", "No Templates" or "No Items", matching the list's empty state;
    - while the library is still opening, no subtitle, never a wrong "0 entries".
    - VoiceOver reads the window title; the spike checks what it reads for the subtitle.
  - A flexible space, then Journal Actions ("…", `ellipsis`, as Entry Actions and the iPad's Journal Actions), a menu at the section's trailing edge, always enabled:
    - "New Journal…" first, useful once the sidebar and its button are hidden;
    - for a journal, a separator and then its actions: Rename…, Default Template ▸, Version History…, a separator, Delete Journal… — the same actions as the journal row's context menu, from one catalog.
    - The item stays in place in every collection, so nothing moves when you change collections.
- **Editor section:**
  - [New Entry, Templates…] at the leading edge (`square.and.pencil`, `doc.on.doc`). New Entry is Notes' compose button. Templates… stays visible beside it (owner decision feedback-stabilization-2026-09-23 §3) rather than moving into a menu. **Amended 30 September 2026** by [new-entry-template-suggestion](new-entry-template-suggestion.md): New Entry only; templates are offered by “Use a Template…” inside a fresh entry, and the width budget below shrinks by one item.
  - A flexible space, [Formatting, Insert Image], and a flexible space. The flexible spaces put the group midway between the leading and trailing groups, not at the section's exact centre.
  - Sync Status, only while sync is pending or failing (unchanged condition), in the place of Notes' Share. Adjacent buttons share glass, so it joins the trailing capsule when it appears, as Share does in Notes, and the Formatting group shifts by half its width. That's intended; the screenshots check it.
  - [Editor Only, View Source/View Preview, Entry Actions].
  - Search, last, as in Notes, with the placeholder "Search ‹Journal›" and friends, unchanged. `preferredWidthForSearchField = 200`.

**Editor section width budget.** [New Entry, Templates…] about 76 pt, [Formatting, Insert Image] about 76, [Editor Only, View Source, Entry Actions] about 108, gaps between groups about 40, Sync Status about 40 when shown: about 300–340 pt without Search. With the default 1100-pt window and all columns the detail is about 570 pt, which leaves room for the 200-pt field, so Search is expanded at ordinary sizes. From about 500 pt down to the 440 minimum, `NSSearchToolbarItem` shows a button that expands into the remaining width when clicked (about 100–140 pt). The spike checks that expanding it at a 440-pt detail puts nothing in the overflow menu; if it does, the detail minimum (and the window minimum with it) rises until it doesn't.

The editor section has no title, as in Notes: the entry's title is in the editor.

**Sidebar hidden:** the window buttons, then [Toggle Sidebar], then the list section as above, then `|` and the editor section.

- New Journal disappears with the sidebar, as Notes' New Folder does. If AppKit doesn't hide sidebar-section items itself (checked in the spike), the item is removed at the moment the collapse starts and inserted again when the expansion has finished, so it never rides beside the window buttons and never passes through the overflow menu. It stays available in the File menu (⌥⌘N) and in the sidebar's context menus.
- The sidebar separator disappears with the sidebar, and the list separator stays on the real divider at any list width.
- **Nothing else moves.** No other item changes group, placement or column, so nothing is rebuilt mid-animation.

**Editor only:** the window buttons, then [Toggle Sidebar], then the editor section.

- The title, subtitle and Journal Actions are removed or hidden *before* the columns collapse, and added *after* they expand again. They never ride over the editor or pass through the overflow menu.
- The title is hidden with `titleVisibility = .hidden`. The window title stays set, for the Window menu and Mission Control.
- Editor Only shows as on, with the tooltip "Show Sidebar and List (⇧⌘D)". Otherwise the tooltip is "Show Editor Only (⇧⌘D)".
- Toggle Sidebar (and ⌃⌘S) leaves the mode and shows all columns. Editor Only and ⇧⌘D restore the remembered layout.

**Search last, and Editor Only's position.** With Search last, Editor Only sits a search field's width from the trailing edge. `NSSearchToolbarItem` collapses to a button when the editor section is short of room, so at the narrowest editor widths Editor Only moves right by the field's width. This follows Notes' order; the earlier owner-approved order (Search before the trailing group, so Editor Only stays under the pointer) is superseded by the owner's request to follow Notes exactly.

**New Journal elsewhere.** File › New Journal… stays, with ⌥⌘N: ⇧⌘N (Notes' and Finder's New Folder) is New Blank Entry here. The menu title gains the ellipsis because it opens the name alert. The journal rows' context menu gains "New Journal…" first, followed by a separator, and the context menu of the sidebar's empty area offers "New Journal…". There's no button at the bottom of the sidebar, as in Notes 26.

**Animation:**

- The sidebar uses `NSSplitViewController`'s collapse animation. Editor only animates both items in one group.
- With Reduce Motion on, there's no animation, for Show/Hide Sidebar (menu, ⌃⌘S, button) as well as editor only.
- AppKit widens the window if a column can't fit when it returns (§2, *Which column gives way*). The detail never goes below 440, so there's no overflow chevron.

**Differing from Notes:**

- **Templates…** beside New Entry (owner decision above). Removed on 30 September 2026 ([new-entry-template-suggestion](new-entry-template-suggestion.md)).
- **Editor Only and View Source** are additions in the trailing group; Notes has Share and "…" there.
- **Customization.** Toolbar customization stays off.

## 4. Risks

| Risk | Mitigation or check |
|---|---|
| SwiftUI's scene bridging replaces or clears `window.toolbar` (title changes, sheets, lock/unlock) | No `.toolbar` or `.navigationTitle` in the Mac tree. The Phase 1 spike exercises every sheet, alert, lock and relaunch. **Fallback:** an AppKit `NSWindowController` for the journal window. That's a bigger change: `SceneStorage`, `openWindow` and `scenePhase` would need AppKit equivalents. |
| Programmatic collapse of a content-list item while dividers must not collapse it | Spike: `canCollapse = false` plus programmatic `isCollapsed`. If AppKit refuses, set `canCollapse` true only during the transition. |
| Tracking separator on a collapsed divider (editor only) | Spike, and remove the list items first (§3). |
| Popover and sheet anchoring from toolbar items, and the Templates popover's Escape behavior | `show(relativeTo:)`, with a manual check. |
| Glass grouping differs from the mockup, or a hosted control loses glass | Native items only. Screenshots on macOS 26 in light, dark, Increase Contrast and Reduce Transparency. |
| Commands lose the focused scene value or `toggleSidebar:` when focus is in the toolbar | Spike checks every View menu item with focus in each column and in search. |
| State in two places (autosave and `SceneStorage`) | No split view autosave. Widths and layout live in `SceneStorage` and are applied before the window shows, without animation. |
| Toolbars synchronized across windows | A unique toolbar identifier per window, `autosavesConfiguration = false`. The spike opens two windows in different layouts. |
| SwiftUI overwriting `window.title`, `toolbarStyle` or `titleVisibility` | The style comes from `.windowToolbarStyle`; the spike checks title and title visibility after updates, sheets and lock/unlock. |
| Deployment target | `show(relativeTo:)`, `sceneBridgingOptions` and `canCollapseFromWindowResize` need **macOS 14**; the app targeted 13. **Owner decision:** the Mac app now requires macOS 14. The bundled server already needed it (.NET 10), and a native split view and toolbar can't be built on macOS 13 without the view-anchored workarounds this change removes. Recorded in the CHANGELOG. |

## 5. Plan and verification

**Phases:**

0. **Reference and review.**
   - Screenshots of Notes on macOS 26 at its narrowest window, with the sidebar shown and hidden, taken when the Mac has capacity.
   - Independent design review of this document.
   - Owner decisions on the deployment target and on New Journal if Notes 26 differs.
1. **Spike** in the real `WindowGroup`, with placeholder columns, answering every "Spike" row in §4. **Exit criteria,** all of which must hold:
   - Zero toolbar reassignment across the scenarios (sheets, alerts, lock/unlock, relaunch).
   - The split view extends under the titlebar (full-size content, `.ignoresSafeArea()`): the sidebar is full height, and the separators line up with the dividers.
   - `sidebarTrackingSeparator` tracks the sidebar divider although the split view controller isn't the window's `contentViewController`.
   - SwiftUI doesn't overwrite `window.title`, `toolbarStyle` or `titleVisibility` on updates.
   - Entering and leaving full screen, and locking and unlocking, keep the toolbar and its items.
   - Two windows in different layouts don't change each other's toolbar.
   - No overflow chevron in any frame of showing and hiding the sidebar (with New Journal leaving and returning), editor only on and off, and expanding a collapsed Search at a 440-pt detail.
   - AppKit puts the two-line title (`title` and `subtitle`) in the list section, not the sidebar section, with all columns and with the sidebar hidden, and the unified style's title setting doesn't erase the subtitle.
   - Otherwise, take the `NSWindowController` fallback and re-review.
2. **Columns.** The split view controller, the column extraction, `JournalWindowState` and the environment plumbing. Delete the Mac `NavigationSplitView`.
3. **Toolbar.** The toolbar controller, `EntryActionCatalog`, search, popovers, sync status.
4. **Layout.** The `Layout` rewrite with migration, editor only, focus and restoration.
5. **Cleanup.**
   - The sidebar's New Journal.
   - Remove the dead hacks, which §2 lists.
   - Mark editor-only.md's "Toolbar at narrow widths" section as superseded.
   - Run `mise exec -- scripts/format.sh` and the Apple `scripts/check.sh` lanes.

**Manual verification on the Mac (screenshots, and recordings for transitions):**

- **Window sizes:** minimum (801, and 1011 with the sidebar), 1100 and full screen.
- **Each layout:** all columns, sidebar hidden, editor only. Check that no item crosses a divider, there's no stray separator, and no » chevron appears in any frame of show/hide sidebar, editor only on/off, or a live window resize.
- **Content variations:** a 60-character journal name, Sync Status pending and failing, an empty journal, Recently Deleted.
- **Appearance:** light and dark, Increase Contrast, Reduce Transparency, and Reduce Motion (no animation).
- **Keyboard:** ⌃⌘S (in editor only it shows all columns), ⇧⌘D, ⌥⌘F in editor only, ⌥⌘↑/↓, ⌥⌘N in editor only, Tab loop, and Escape in both popovers.
- **Windows:** two windows in different layouts, full screen enter and exit.
- **VoiceOver:** walk the toolbar, and confirm that collapsed columns can't be reached.
- **Lifecycle:** quit and relaunch in each layout, then lock and unlock (no toolbar while locked).
- **iPad:** screenshot comparison unchanged, and iOS UI tests pass.

**Tests to add or change (only where behavior can regress):**

- `EditorOnlyTests`:
  - Keep the layout rules against `Layout`.
  - Add the raw-value migration: an updated app must restore a window saved in each old format.
- **`JournalWindowLayoutTests`** (in-process AppKit window, as `EditorOnlyTests` does today, with fast placeholder columns). For each layout at the minimum window width:
  - each section holds the expected items: the items between the tracking separators in `toolbar.items` match the layout (item membership per section). A frame check (every visible item inside its section) is added only if toolbar item geometry proves stable in an in-process test; otherwise it stays a screenshot check;
  - New Journal is in the sidebar section with the sidebar shown, not in the toolbar while the sidebar is collapsed (hidden or removed), and back once `toggleSidebar` has finished;
  - Journal Actions is absent in editor only and present, even for a collection that isn't a journal, in the other layouts;
  - `toggleSidebar(nil)` from editor only ends in all columns, whatever layout was remembered; Editor Only off restores the remembered layout;
  - a collapse the window's width causes (narrower than 1011) updates the layout;
  - `beginSearchInteraction` from editor only leaves the mode.
- `EntryActionCatalog`: the toolbar menu and the row context menu offer the same enabled actions for the same entry, with a deleted, a template and a conflicted entry. This protects the menus from drifting apart.
- No tests for toolbar item creation, glass styling or constants.

## 6. Review outcome

The independent design review (29 September 2026) **approved the proposal with required changes**. All of them are incorporated above:

1. **Toolbar synchronization.** Toolbars with the same identifier stay in sync across windows. Each window's toolbar gets its own identifier, without autosave (§2). `isHidden` would need macOS 15.
2. **Show/Hide Sidebar.** ⌃⌘S and the sidebar button always end in all columns from editor only; only Editor Only and ⇧⌘D restore the remembered layout (§2, §3).
3. **Restoration.** No split view autosave restoring collapsed states behind `SceneStorage`; the saved layout and widths are applied before the window shows, without animation (§2).
4. **Spike exit criteria** now include the full-height split view under the titlebar, the sidebar tracking separator without being the window's content view controller, SwiftUI not overwriting title, style or title visibility (the style comes from `.windowToolbarStyle`), and full screen and lock/unlock keeping the toolbar (§5).
5. **System collapses** are observed through each item's `isCollapsed` with key-value observing, not `splitViewDidResizeSubviews` (§2).
6. **Narrow windows.** The order in which columns give way is specified; the detail never goes below 440 and the sidebar collapses first (§2).
7. **Reduce Motion** applies to the standard `toggleSidebar:` path too (§2, §3).
8. **Toolbar geometry test** only if stable; otherwise item membership per section (§5).

**Owner decisions after the review:** the Mac app requires macOS 14 (§4). New Journal keeps ⌥⌘N because ⇧⌘N is New Blank Entry (§3).

**Revision after the owner's Notes 26 screenshots (29 September 2026).** The owner asked to follow Notes 26 exactly. §1 records the screenshots, and §3 was rewritten: New Journal joins the sidebar button in the sidebar section and leaves with the sidebar (instead of a button at the bottom of the sidebar); the list section shows a two-line title with the count and a Journal Actions "…"; New Entry and Templates… move to the editor section's leading edge; Search moves last. This revision gets its own independent review before implementation; its outcome is recorded below.

**Review of the Notes 26 revision (independent design review, 29 September 2026): approved with required changes,** all incorporated in §3 and §5:

1. Editor section width budget stated; Search 200 pt so it's expanded at ordinary sizes; expanding a collapsed Search at a 440-pt detail added to the no-chevron checks.
2. New Journal returns when the sidebar expansion has finished, not as it starts; "no chevron in any frame" is a spike exit criterion.
3. Journal Actions is always enabled: "New Journal…" first, then a journal's actions.
4. Subtitle states: locale-formatted plural counts, "No Entries"/"No Templates"/"No Items" when empty, nothing while opening, "Untitled Journal".
5. Journal Actions uses `ellipsis`, like the other "…" menus.
6. The two-line title is `window.title` and `window.subtitle`; the spike checks its section and that the unified style doesn't erase the subtitle.

Optional findings taken: Sync Status joining the trailing glass (recorded), "centred" defined, "New Journal…" first in the row menu and "New Journal…" in the File menu, two more membership tests. Not taken: a different Templates… symbol (the approved `doc.on.doc` stays); a VoiceOver announcement of the count (the spike checks what VoiceOver reads first).

## 7. Implementation notes (29 September 2026)

**Phase 1 spike: passed.** Evidence came from a temporary in-process test that drove the app's own `WindowGroup` window (its real scene, `SceneStorage` and toolbar style), resized it and captured it with its window image; numbers come from the toolbar item and divider frames.

- The split view extends under the titlebar with a full-height glass sidebar; `sidebarTrackingSeparator` tracks the sidebar divider although the split view controller is embedded in SwiftUI's content, not the window's content view controller.
- SwiftUI didn't replace the toolbar or reset the title visibility across sheets, lock and unlock (the toolbar is removed while locked and a new one installed after unlocking), relaunch of the controller, and a second window in another layout (each toolbar has its own identifier).
- No overflow chevron and no item past a divider in the captured frames of show/hide sidebar, editor only on/off, and window widths 801, 930, 1100 and 1280 — except as noted below.
- Not verified in the spike: entering full screen (the test app isn't active, so AppKit doesn't enter full screen), and the View menu's Show/Hide Sidebar and Show Editor Only titles (they validate against the key window, which an inactive test app doesn't have). Both need a manual check.

**Changes from the design, found while implementing:**

- **Title and subtitle through SwiftUI.** SwiftUI owns the title of a `WindowGroup` window and shows its own, empty subtitle over `window.subtitle`, so the title and count use `navigationTitle` and `navigationSubtitle` on the root of the columns. With `navigationSubtitle` in `RootView`'s body, resolving the view's generic type crashed in the Swift runtime on macOS 26.3; the Mac columns are type-erased (`AnyView`) to avoid it. Title visibility (hidden in editor only) is still set on the window, and SwiftUI leaves it.
- **Sidebar collapse on narrow windows** is the controller's own: `canCollapseFromWindowResize` also collapsed the sidebar while SwiftUI first sized the columns, and the split view otherwise kept every minimum and overflowed the window. The representable takes the proposed size, and the controller hides the sidebar when the window is narrower than 1011.
- **Minimums:** list 360 (above), detail 440 with the divider, which also fits Sync Status with a collapsed search field; window 801.
- **List separator** stays while the list collapses or expands, so the editor's items follow the divider, and is removed in editor only, where it would otherwise stand alone among the editor's items.
- **macOS 14 target.** Raising the deployment target deprecates `onChange(of:perform:)` (88 uses in 40 files, errors with warnings as errors), while its replacement needs iOS 17. `View.onValueChange(of:perform:)` uses the new form on the Mac and the old one on iOS; the call sites were renamed mechanically.
- **Column content** is built by `RootView` (§2), not extracted.
- **Entry and journal actions** are described once (`MenuAction`) and shown as SwiftUI context menus and as AppKit toolbar menus. Because both come from one source, the separate catalog test proposed in §5 would only compare the source with itself and wasn't added.

**Open points for the owner or lead:**

- The window's minimum width is 801, not 740 (list 360 because of AppKit's toolbar section, detail 440 for the editor's items).
- Clicking the collapsed search field at the narrowest widths expands it (about 208 pt), and AppKit moves the trailing items into the » menu while the field is expanded; they return when search ends. Avoiding that needs a detail of about 600 pt (window about 960). Native `NSSearchToolbarItem` behavior; not changed.


## 8. Sidebar toolbar icons in dark mode (3 October 2026)

**Problem.** After the system switches from light to dark (Auto appearance), New Journal and Toggle Sidebar in the
sidebar's toolbar section stay drawn for a light background: near-black on the dark sidebar. On macOS 26, AppKit gives
toolbar items over a scroll view's top edge an explicit appearance computed from the content beneath that edge (the
scroll-edge effect). For the SwiftUI sidebar `List` it recomputes about 0.45 s after the switch from a stale sample and
not again until the sidebar scrolls. An AppKit source-list sidebar, as in Notes, never gets an explicit appearance, so
its items simply follow the window.

**Design.** The sidebar list hides its top scroll-edge effect (`.scrollEdgeEffectHidden(true, for: .top)`, macOS only),
so the items over it follow the window's appearance as in Notes. Nothing else changes: same layout, items, copy and
accessibility. The visible difference is that sidebar rows scrolling under the toolbar are no longer softened by the
edge fade; rows simply pass under the toolbar as in an AppKit sidebar. The entries list and editor keep their edge
effects. The owner chose this over re-triggering AppKit's sample after appearance changes, which has no public API.

**Verification.** In dark mode, switching light → dark with the window key and with it in the background leaves both
icons light; scrolling the sidebar under the toolbar looks like Notes; light mode, Increase Contrast and Reduce
Transparency are unchanged.

**Review outcome.** An independent design review approved the change with conditions:
- keep the modifier macOS-only, with a comment saying why it's there (done);
- try `.scrollEdgeEffectStyle(.hard, for: .top)` once in dark mode, and keep hiding the effect if the bug persists with it;
- widen the dark-mode verification: a long, scrolled journal list with rows under both icons; switching in both
  directions, including while scrolled; the sidebar collapsed and expanded again; the window in the background and in
  full screen; Increase Contrast and Reduce Transparency in both appearances; VoiceOver and focus rings on both items;
  before and after screenshots.

The dark-mode checks wait until the system is in dark mode, since the fault only appears on a switch to dark.
