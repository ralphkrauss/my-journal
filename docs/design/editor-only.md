# Editor only (focused writing on the Mac)

The owner asked for a focused writing mode on the Mac. The editor takes the full width of the window, and the journal sidebar and entry list are hidden. This isn't macOS full screen.

## Research summary

Sources:

- **Apple HIG:**
  - [Split views](https://developer.apple.com/design/human-interface-guidelines/split-views)
  - [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
  - [The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)
  - [Going full screen](https://developer.apple.com/design/human-interface-guidelines/going-full-screen)
  - [Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards)
- **Apple documentation:** [NavigationSplitViewVisibility](https://developer.apple.com/documentation/swiftui/navigationsplitviewvisibility)
- **Other writing apps:**
  - [Ulysses shortcuts](https://help.ulysses.app/keyboard-shortcuts-mac-ipad)
  - [Bear: hide the sidebar and note list](https://bear.app/faq/hide-the-sidebar-and-note-list-on-mac-and-ipad/)
  - [iA Writer Focus Mode](https://ia.net/writer/support/editor/focus-mode/focus-mode-mac)
  - [Craft Focus Mode](https://www.24letters.net/blog/focus-mode-in-craft)
  - [Day One Mac shortcuts](https://dayoneapp.com/guides/day-one-for-mac/keyboard-shortcuts/)
  - [Things sidebar](https://culturedcode.com/things/support/articles/3238254/)
  - [Notes shortcuts](https://support.apple.com/guide/notes/keyboard-shortcuts-and-gestures-apd46c25187e/mac)
  - [Mail shortcuts](https://support.apple.com/guide/mail/keyboard-shortcuts-mlhlb94f262b/mac)

**What these apps have in common:**
- A View-menu command with a keyboard shortcut, often also a toolbar button, enters and leaves the mode.
- Esc doesn't leave the mode, and neither does hovering at an edge.
- The toolbar stays.
- The text keeps a readable width, centred, rather than stretching to the window.
- System full screen stays a separate, independent control.

**Apple guidance:**
- On split views: let people hide other panes to reduce distractions, and provide more than one way to reveal them, including a menu command with a shortcut.
- On menus: show/hide titles describe the action the command will take.

**Naming.** "Focus Mode" is avoided: it collides with the system Focus feature, and in iA Writer it means dimming other sentences. Bear's wording, "Show Editor Only", is plain, describes the result, and follows the Show/Hide pattern of the View menu.

## Design

Revision 2 incorporates the design review.

- **Command:** View › **Show Editor Only** ⇧⌘D, placed directly after Show/Hide Sidebar (`SidebarCommands`) and before Enter Full Screen.
  - While active it reads **Show Sidebar and List**, with the same shortcut.
  - It's disabled when no library is open.
- **Toolbar button (owner request, design-reviewed):**
  - A toggle at the trailing end of the editor toolbar, ordered [Editor Only] [View Source `</>`] [… More]. The editor's trailing edge is the window's trailing edge, so the button stays under the pointer when the columns hide and return.
  - Symbol `rectangle.center.inset.filled`, with no full-screen arrows. It uses `.toggleStyle(.button)`, highlighted while on.
  - Label "Editor Only". Tooltip "Show Editor Only (⇧⌘D)" or "Show Sidebar and List (⇧⌘D)".
  - Room for it: the detail column's minimum width is now 440 pt, the window's minimum 930 pt, and the search field allows for the extra button.
- **State:**
  - The mode is `columnVisibility == .detailOnly`.
  - Entering it remembers the layout it replaced, such as all columns or the list only. Leaving restores that layout, by the command or by any control that reveals a column (Show Sidebar ⌃⌘S or the toolbar's sidebar button).
  - Both the mode and the remembered layout are restored per window with `@SceneStorage`. New windows start with all columns.
  - If macOS keeps showing the content column for `.detailOnly` in a three-column split view, the implementation must still hide both columns. The build must show this in screenshots.
- **Layout:**
  - The editor keeps its maximum readable width (760 pt), centred.
  - The toolbar stays: formatting, image, source, search.
  - Entering and leaving use the standard split-view animation, with no animation when Reduce Motion is on. Keyboard focus stays in the editor.
  - There are no extra VoiceOver announcements; the changing menu title conveys the state, as with Show/Hide Sidebar.
- **Search:** focusing the search field or Search Entries (⌥⌘F) leaves the mode, restoring the previous layout. Search filters the list, and the list must be visible to show results.
- **New Journal (⌥⌘N):** leaves the mode, restoring the previous layout, so the new journal is visible in the sidebar.
- **Previous Entry ⌥⌘↑ / Next Entry ⌥⌘↓ (View menu, below the editor-only command):**
  - They move through the current list in its visible order, including any filter or search, without revealing the list.
  - The open draft is saved first, exactly as selecting another row saves it.
  - They're disabled at either end, while locked, and when the list is empty.
  - VoiceOver hears the new entry through the normal focus change to its title. There's no extra announcement.
  - They work with the list visible too. ⌘↑ and ⌘↓ stay text navigation.
- **New Entry (⌘N):** creates and opens the entry, and the mode stays on.
- **The open entry is deleted or moved away:** the next entry opens, as the list already does. With none left, the editor shows "No Entries" and a **New Entry** button, as in the list's empty state, and the mode stays on.
- **Full screen:** stays independent and combines with the mode.
- **iPad:** not in this change.

## Review

- **Revision 1:** approved with required changes. The revision addressed them:
  - search leaves the mode;
  - the previous layout is restored;
  - no toolbar button;
  - Show Sidebar restores the layout;
  - Previous/Next is specified;
  - New Journal leaves the mode;
  - no announcements;
  - the sources are in this document.
- **Re-review:** not required. Verification needs screenshots with both columns hidden.

## Toolbar at narrow widths (owner report, 2026-09-29)

*Superseded by [mac-window-appkit.md](mac-window-appkit.md): the Mac window now uses AppKit's split view and toolbar, and the workarounds below were removed.*

**What went wrong.** With the sidebar hidden and the window at its minimum width, the Templates and New Entry capsule spilled over the divider between the list and the editor. AppKit ends the list's toolbar section about 9 pt past the column divider when the sidebar is collapsed, and it aligns trailing items to that section edge.

**The fix:**

- **Button placement.** Templates and New Entry now use `.navigation` placement, beside the journal title, in both states. Items that change placement are rebuilt part way through the sidebar animation, so keeping one placement avoids that.
- **List width.** The list's minimum width rises from 280 to 360 pt while the sidebar is hidden, so the window buttons, both capsules and a truncated title fit inside it.
- **Search field.** It starts from its smallest width whenever columns change, so the editor's toolbar doesn't overflow while its new width is measured.
- **Editor column.** The minimum is 440 pt, and the window's minimum is 930 pt. That leaves room for the Editor Only button and the sync status.

**Verified on the Mac** at the minimum width in each state: sidebar shown, sidebar hidden, editor only, and with a long journal name.

**Remaining known artifact.** At the minimum width, the » overflow chevron can flash for a couple of frames while the sidebar slides in. SwiftUI squeezes the editor column below its minimum during the animation. It doesn't happen once the window has room.
