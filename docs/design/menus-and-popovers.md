# Menus and popovers: instant open, clean close — 2026-09-30

Status: **revision 3**, approved for implementation; **implemented 2026-09-30** (see “Implementation record”). Revision 1 was approved with required changes; revision 2 was approved with two small required changes, applied here without a further review round (see “Design review” at the end).

## Owner report and decisions

Owner report (Mac, “maybe also iOS”): the dropdowns from the text-style button and the template button are slow and laggy compared with the ⋯ menus and with Notes’ **Aa**. Clicking the text-style button a second time starts the close animation, the panel then flashes open again, and only then closes. All such surfaces must feel as fast as Notes’ Aa and the ⋯ menu.

Later owner input, binding for this design:

1. Notes’ Aa on macOS is a **popover** with custom content (B/I/U/S row, paragraph styles drawn in their own style, a checkmark on the current style). It “feels like a native menu but it’s full custom”. So the fix is not “turn everything into NSMenu”; it is to make our popovers behave as well as Notes’ popover.
2. iOS is in scope as a first-class target: the keyboard-toolbar Aa, the iPhone/iPad formatting presentation and the template chooser. Styling is a very common action while writing: it must feel instant, keep the keyboard and selection, and have no glitches.
3. **No animation.** The formatting popover on the Mac and its iOS equivalent appear and disappear without animation (“in the Notes app they even removed the animation … when you are writing you just want to style it”). The same applies to the other writing-time panels (template chooser, link editor) unless there is a strong platform reason; such exceptions are recorded below.

## Summary

| # | Surface | Platform | Today’s mechanism | Why it feels slow | Reopen flash |
| --- | --- | --- | --- | --- | --- |
| M1 | **Formatting** toolbar button | Mac | `NSPopover` (`.applicationDefined`, animated) from `ToolbarPopover`, a **new** `NSHostingController(FormattingPopover)` per open, custom local event monitor | 0.5 s popover animation each way; 25–45 ms to build the SwiftUI content on every open; opening, every B/I/U tap and closing publish on `EditorActions`, which re-renders the whole window and the menu bar | **Yes** (reproduced, root cause below) |
| M2 | **Templates…** toolbar button | Mac | Same `ToolbarPopover` with `TemplateChooserView` (SwiftUI `List` + `NSSearchField`) | Same animation and build cost; the chooser observes all of `AppModel`, so any model change re-renders it while open | **Yes** (same code path) |
| M3 | File ▸ New Entry from Template… | Mac | SwiftUI `.sheet` with `TemplateChooserView` | System sheet animation | No |
| M4 | Link editor (⌘K, Insert ▸ Link…) | Mac, iOS | SwiftUI `.sheet` (`NavigationStack` + grouped `Form`) | System sheet animation; on the Mac it follows the Formatting popover’s close animation | No |
| M5 | More Headings, Insert (inside Formatting) | Mac, iOS | SwiftUI `Menu` → native menu | Native, fast | No |
| M6 | Journal Actions ⋯, Entry Actions ⋯, Sync Status | Mac | `NSMenuToolbarItem` + `NSMenu` filled in `menuNeedsUpdate` | Native, fast — **the reference** | No |
| M7 | Context menus (entry rows, sidebar, table cells), Format menu bar menu | Mac, iOS | Native `NSMenu`/`UIMenu` | Fast | No |
| M8 | Version and destination pickers (history, conflicts), settings pickers | Mac, iOS | SwiftUI `Menu`+`Picker` / pop-up buttons → native menus | Fast | No |
| M9 | Change Date, confirmation dialogs | Mac, iOS | Sheets / system dialogs | Not writing-time; unchanged | No |
| I1 | **Formatting** (keyboard-toolbar Aa, bottom-bar Aa) | iPhone, iPad compact | `MobileFormattingPresenter`: `UIHostingController` page sheet with a custom “fitted” detent | ~200 ms before anything moves; ~380 ms sheet animation, then ~400 ms more motion as the sheet re-fits its height; dims the entry and takes focus from the text (keyboard goes down and comes back); every B/I/U tap re-renders the whole navigation stack | n/a (the sheet covers the button) |
| I2 | Formatting | iPad regular width | Same presenter, `UIPopover` 300×520, animated | Same latency chain and animation | Possible: the accessory’s Aa is in the keyboard’s window, outside the popover’s dismissal area (guarded in D6) |
| I3 | **Templates…** (list bottom bar) | iPhone | SwiftUI `.sheet` (`.medium`/`.large`), `NavigationStack`, `List`, auto-focused `UISearchBar` | ~150 ms before anything moves, ~400 ms open, ~550 ms close | No |
| I4 | Templates… | iPad regular width | SwiftUI `.popover` from `EntryCreationActions` | Popover animation | No |
| I5 | Insert Image, ⋯ menus, Sync Status, table-cell menus | iOS | Native `UIMenu` | Fast | No |
| — | `iconHelp` | Mac, iOS | Tooltip helper, not a popover | — | — |

`EntryCreationActions`’ Mac `.popover` branch can’t be reached (the Mac toolbar is AppKit), so this work removes it and leaves one Mac template presentation.

## What Notes does

- **macOS Notes Aa.** Notes’ binary contains `closeStylePopoverIfNecessary`, `ICMTextStylesCollectionView`, `ICMTextStylesBIUSCollectionViewItem`, `ICMTextStylesNamedStyleCollectionViewItem` and `ICStyleMenuButtonCell`: an AppKit `NSPopover` with an AppKit collection view, shown with `showRelativeToRect:ofView:preferredEdge:` and a configured `behavior`. The owner observes it appears and disappears without animation. Its content is ready immediately and nothing else in the window redraws when it opens.
- **iOS Notes Aa.** The keyboard-toolbar Aa opens the Format panel (title “Format”, close button) where the keyboard was. The note stays visible and undimmed above it with the selection shown, styles apply live, and closing brings the keyboard back. Notes opens this panel from a keyboard-toolbar button ([Apple developer forum](https://developer.apple.com/forums/thread/768408)). The panel-replaces-keyboard detail comes from product knowledge; the Notes app isn’t on the simulator, so confirm it on the owner’s iPhone before implementation. The system panel (`UITextFormattingViewController`, iOS 18) can’t be used as is: our deployment target is iOS 16 and our styles (task lists, inline code, code blocks, Insert) differ.
- **HIG.** A popover suits “a small amount of information or functionality”; it “generally closes when people click or tap outside its bounds or select an item”; “Show one popover at a time”; “Avoid displaying popovers in compact views … use … a sheet instead” ([Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers)). A pull-down button presents “commands or items that are directly related to the button’s action” ([Pull-down buttons](https://developer.apple.com/design/human-interface-guidelines/pull-down-buttons)). Formatting needs live toggle state and stays open while toggling, so a popover (Mac, iPad) and a keyboard-area panel (iPhone) are right. Menus stay menus.

## Measurements

All in `scratchpad` harnesses or on the test simulator; nothing was committed.

**macOS 26, AppKit harness with the verbatim `ToolbarPopover` and verbatim `FormattingPopover` (stubbed `EditorActions`):**

| Measurement | Result |
| --- | --- |
| `NSPopover` open, animated (default), `show` → `popoverDidShow` | 512–549 ms (same with plain AppKit content) |
| `NSPopover` close, animated, `close` → `popoverDidClose` | 531–545 ms |
| Same with `animates = false` | open 11 ms, close 1 ms |
| New `NSHostingController(FormattingPopover)` + show, first open | 44–45 ms main thread (Debug and Release alike) |
| Same, later opens (what the app does every time) | 24–26 ms; longest main-thread gap during open 26–30 ms |
| Reused popover and hosting controller | 13–14 ms; no gap over 17 ms |

The real app adds a full-window SwiftUI update on open, per style tap and on close (see R3). I could not measure that in the running app: the owner’s instance of the dev app is running, and the computer-use tools address the app by bundle identifier, so they can’t be pointed safely at a second instance. The verification plan measures it.

**iPhone 17 simulator, iOS 26.5, current Debug build, hardware keyboard (simctl video, frame timing):**

| Step | Result |
| --- | --- |
| Tap Aa → first sheet movement | ~200 ms. Before the sheet, the bottom bar first shifts as the entry stops editing |
| Sheet open animation | ~380 ms, then ~400 ms of further motion (detent re-fit, entry scroll) |
| Tap **B** in the sheet | screen keeps changing for ~600 ms; the sheet grew by ~12 pt |
| Close (X) | ~450 ms; caret returns only after close |
| Templates… → first movement / open / close | ~150 ms / ~400 ms / ~550 ms |

The entry is dimmed and shows no caret while the sheet is up. The keyboard bounce (down on open, up on close) follows from the text view losing focus and `finishPresentation()` refocusing it. The software keyboard couldn’t be turned on in this simulator from the background; the owner’s iPhone check covers it.

## Root causes

**R1 — Default popover animation.** Every AppKit popover animates for about 0.5 s each way on macOS 26. Our menus are instant. Owner decision: no animation.

**R2 — Content built on every open.** `ToolbarPopover.toggle` creates a new `NSPopover` and a new `NSHostingController` each time. SwiftUI builds and lays out the whole view graph during the first animation frames, which costs 25–45 ms and drops frames. iOS builds two hosting controllers per open (`estimatedHeight` builds a measuring copy).

**R3 — Opening and styling re-render the whole window.** `captureFormatting()` assigns three `@Published` properties of `EditorActions` (`formattingState`, `linkText`, `sourceMode`; the last is assigned even when unchanged). `performFormatting` assigns `formattingState` again on every B/I/U tap, and the popover’s `onDisappear` → `finishPresentation()` → `.focus` does so on close. `RootView` observes `EditorActions`, so each change re-evaluates the root body. On the Mac that rebuilds the toolbar configuration and pushes new `AnyView`-erased sidebar, list and detail roots into their hosting controllers. `AppCommands`, `EntryHeaderView` and `EntryTitleEditor` observe it too, so the whole menu bar is re-evaluated as well. Only the formatting surface reads `formattingState`.

**R4 — Extra hops before presenting (iOS).** Aa sets `requestFormatting` (publish) → `RootView.onValueChange` sets `formatting = true` and resets `requestFormatting` (publish) → another root update → `MobileFormattingPresenter.updateUIViewController` → build, measure, present. After presenting, `fit(rowsBottom:)` corrects the estimate with `sheet.animateChanges { invalidateDetents() }`, a second visible motion.

**R5 — Modal sheet takes focus (iPhone).** A page sheet over the editor dims the entry, ends editing (keyboard down), and editing resumes on close (keyboard up). The entry’s selection isn’t visible while styles are applied.

**R6 — The reopen flash (Mac), reproduced exactly.** With the popover open, a second click on its toolbar item:

1. **mouse-down:** the local monitor sees a toolbar click, sets `toolbarClickPending` and schedules `close()` with `DispatchQueue.main.async`;
2. **while the button tracks the mouse**, AppKit runs the main queue (event-tracking mode is a common mode), so `close()` runs before mouse-up: the popover starts animating out and `popover` becomes nil — *“the closing animation starts”*;
3. **mouse-up:** the item’s action calls `toggle`, sees no popover and **shows a new one** — *“flashes open again”*;
4. ~0.5 s later the **old** popover’s `popoverDidClose` arrives. The handler doesn’t check which popover closed and closes the **new** one — *“before finally fully closing”*.

Harness log with 30, 90 and 150 ms clicks: `monitor → async close() fires (during button tracking) → ACTION → SHOW new popover → didClose (old) → close() (new)`. **Templates…** has the same path: its `isShown` check runs at mouse-up, after step 2.

**R7 — Minor chooser costs.** `TemplateChooserView.choices` is O(n²) (a `filter` inside `map`) and is evaluated several times per render. The view observes all of `AppModel`, so sync status and other changes re-render it while open.

## Design

Principles for every writing-time panel:

- **No animation.**
- **Content ready before it’s shown.**
- **Opening, styling and closing don’t touch window-level state.**
- **Commands follow the live selection** while the panel is shown.
- **One click opens; the next click on the same control closes**, with no reopening.
- **Escape closes.**
- **Focus goes back only when the person dismissed the panel itself.** An outside click leaves focus where the person put it.

Menus (M5–M8, I5) stay native menus, unchanged.

### D1 — Mac popover controller (M1, M2)

Replace `ToolbarPopover` (keep the type name):

- **One `NSPopover` per toolbar item per window**, created with the toolbar, with `animates = false` and `behavior = .transient`. Transient is what Notes and the system use: AppKit closes the popover when the person clicks anywhere outside it (text, list, sidebar, search field, another toolbar item, another window), and the click still reaches what was clicked. Opening a submenu from inside it (More Headings, Insert) doesn’t close it.
- **Same-click guard (fixes R6)**, as a small pure value type, `PopoverClickGuard`, with no AppKit state:
  - `popoverWillClose` records the mouse-down that closed the popover, if any.
  - The toolbar button (`PopoverButton`) reports the mouse-down it receives itself.
  - The button's action does nothing when the popover closed on that very same mouse-down (same event number and timestamp). That is the second click on the button.
  - A click elsewhere that closed it, followed quickly by a click on the button, still opens it: they are different mouse-downs. Keyboard, menu and VoiceOver activation always toggle.
  - Each click is decided once.
  - *Implementation change from revision 3:* recording "only a mouse-down inside this item's view" by comparing positions was replaced by the button reporting its own mouse-down. This meets the same requirement without comparing coordinates, which also works when the toolbar is in its own full-screen window. The harness below shows AppKit hands the popover and the button the same event.
- **Delegate identity.** Every delegate callback checks `notification.object === popover`.
- **How it was opened** decides key focus. It counts as opened with the mouse only when the button itself received the mouse-down of this click (not a possibly stale `NSApp.currentEvent`):
  - *With the mouse*: the text stays key, as in Notes, and the popover doesn't become key.
  - *Otherwise* (Space with Full Keyboard Access, an accessibility press, the overflow menu): keyboard-opened. The popover's window becomes key. Focus goes to **Bold** (Formatting) or to the search field (Templates…), and an accessibility focus-changed notification is posted.
  - *With VoiceOver running*: always keyboard-opened.
- **Close reason** is recorded when closing starts and handled in `popoverDidClose`, not in SwiftUI `onDisappear`:
  - *Outside click* (transient close during a mouse-down that isn’t on this item): nothing is refocused or restored. The click puts focus and selection where the person clicked.
  - *Escape, a second click on the item, or a row that closes the popover* (a paragraph style, list, indent, Insert item): focus returns to where it came from. If opened with the mouse, the text is still key with its live selection, so nothing changes. If opened by keyboard or VoiceOver, focus returns to the Formatting or Templates… item, and VoiceOver is told.
  - *Programmatic* (entry changed, editing unavailable, window locked or closed): no refocus.
- **Escape.** First the standard route: `cancelOperation(_:)` from the key popover (keyboard-opened, and Templates… with its search field). When the text stays key (mouse-opened Formatting), the editor’s text view, and the Mac table-cell text view (`TableCellTextView`), handle `cancelOperation(_:)` while a formatting popover is shown by closing it. They don’t do this while an input method is composing. There is no app-wide key monitor.
- Shown with `show(relativeTo: toolbarItem)`, so an item in the toolbar overflow still gets a correctly placed popover, with the arrow on the button.

### D2 — A live formatting session, ready in advance (M1, I1, I2; fixes R2, R3)

- **`FormattingSession: ObservableObject`**, one per window/scene, owned by `EditorActions` as a plain (not `@Published`) property. It publishes only:
  - `state: FormattingState`, the styles at the current selection;
  - `isPresented: Bool`, whether the popover or panel is shown. It drives Aa’s selected appearance on iOS.
  
  Only `FormattingPopover` and the Aa buttons (`WritingAccessory`’s bar and the iOS bottom-bar Aa) observe it. `RootView`, `AppCommands` and the editor views don’t, so nothing window-level re-renders on open, per command or on close. `EditorActions` stops publishing `formattingState`. `sourceMode` is assigned only when it changes. `linkText` is filled only when the link editor opens.
- **Commands apply to the current selection.** Today `formattingSession()` in `Editor/NativeEditor.swift` captures the range, generation and document at open, resets the selection to that range for each command, and drops commands after any edit. While the popover or panel is shown, this changes:
  - Each command acts on the text view’s **current** selection in whichever text view has focus (body or table cell), at the time of the command, provided the same entry is open and editable.
  - Edits made meanwhile (typing, ⌘B from the menu bar, undo) no longer void the session.
  - One exception stays: **Insert ▸ Image…** records its insertion point when chosen, as now. An image that finishes importing after further writing still goes where it was placed, using the existing `TextRanges.insertionPoint` adjustment.
  - If no text view has focus when a command runs, the last selection is used, as today.
- **State stays current.** While the session is presented, the editor coordinators refresh `session.state` from `selectionStyle` on every selection change (`textViewDidChangeSelection`) and text change (`textDidChange`), in the body and in table cells. This covers ⌘B/⌘I/⌘U and heading shortcuts from the menu bar or a hardware keyboard while the Mac popover or iOS panel is open. The refresh is coalesced to once per run-loop turn and only publishes when the state differs.
- **Mac:** the Formatting popover’s `NSHostingController` is created once per window when the toolbar is installed, and reused. Opening sets `isPresented`, refreshes `state` and shows the popover; nothing is rebuilt. It is 250 pt wide. Its height is the rows’ height at the current text size, measured once and remeasured only when the rows change (task row, indent row, Exit Code Block). The rows don’t scroll at the default text size, so the Mac drops the scroll-indicator flash on appear.
- **iOS:** the panel’s hosting controller is created once per scene and reused. The separate measuring controller is removed.
- `TemplateChooserView` computes its choices once per template change (O(n)), detecting duplicate titles with a dictionary. It observes a small `TemplateChooserModel` (templates, journal availability, search text, highlight, error, busy) that the presenter owns, not all of `AppModel`.

### D3 — Mac Formatting popover (M1)

Layout, content and copy are **unchanged**:
- a B / I / U / S / `<>` row (accessibility labels Bold, Italic, Underline, Strikethrough, Inline Code; value On, Off or Mixed); divider;
- Heading 1, Heading 2, Heading 3, Paragraph, each drawn in its style, with a checkmark on the current one;
- Mark as Complete / Mark as Incomplete when the selection has tasks;
- More Headings ▸ Heading 4–6; divider;
- Bulleted List, Numbered List, Task List, Block Quote;
- Decrease Indent / Increase Indent when applicable;
- Exit Code Block in a code block;
- Insert ▸ Code Block, Horizontal Rule, Table, Link…, Image….

Behavior:
- Click **Formatting** → the popover is on screen in the next frame, without animation, with the arrow on the button. The text stays key.
- B/I/U/S/`<>` apply to the current selection and the popover **stays open**. Selecting other text with the keyboard (Shift-arrows) while it’s open updates the checkmarks and toggle states.
- A paragraph style, a list style, an indent action or an Insert item applies and closes the popover (close reason: row).
- Click **Formatting** again or press Escape → closes at once, with no reopening. Click elsewhere → closes, and that click takes effect normally.
- **Tooltips** stay the plain names (Bold, Italic, …), as today. A version showing the menu-bar shortcut was considered. It was dropped because the shortcuts aren’t defined in one shared table, and duplicating them would let them drift.

### D4 — Mac Templates… popover (M2)

Amended 30 September 2026: the Templates… toolbar button (M2) and the list-bar Templates… (I3, I4) were replaced by “Use a Template…” in a fresh entry ([new-entry-template-suggestion](new-entry-template-suggestion.md)). It opens the same chooser with the same no-animation, focus and Escape behavior, anchored to the suggestion.

Uses D1: no animation, transient, same-click guard, close reasons, Escape through `cancelOperation`. Its hosting controller is **created once and reused**. On every open the chooser model resets: search text empty, highlight none, error cleared, list scrolled to the top. The search field then takes focus, so the popover is key in this case, also when opened with the mouse, because typing is its purpose.

Content and copy are unchanged:
- the search field “Search Templates”, and rows with the template names;
- Up/Down move the highlight, and Return creates;
- empty states “No Templates” / “No Results”;
- errors “This template is no longer available. Choose another template.” and “This journal is no longer available. Close this window and choose a journal.”;
- a progress indicator while creating.

### D5 — iPhone Formatting panel in place of the keyboard (I1)

While entry text is being edited, **Aa shows the Format panel where the keyboard is**, as Notes and Mail do. The panel is the focused text view’s input view: the text keeps focus, the caret or selection stays visible and undimmed, and commands apply live to the current selection (D2).

- **Layout:** today’s sheet content, with the “Format” title centered and the close button trailing (iOS 26 system close button, accessibility label “Close”; earlier iOS: **Close**). Rows are 44 pt and scroll inside the panel when they don’t fit. The keyboard-toolbar bar (Aa, Insert Image, View Source) stays above the panel, and Aa shows as selected while the panel is open.
- **Before swapping**, the editor commits marked text with the existing `commitComposition(before:)`, so an input method’s composition isn’t lost. Opening the panel ends dictation, as switching to any other input view does; nothing typed is lost.
- **Which text view:** the swap applies to whatever is first responder:
  - The body text view and table cells (`InlineTableGridIOS` gives each cell its own `WritingAccessory`) all answer `inputView` from the shared session: the panel while `session.isPresented`, otherwise nil (the keyboard). Their Aa buttons observe the same session.
  - Moving focus between the body and a cell while the panel is open keeps the panel.
  - The title field isn’t formattable: Aa is disabled while it has focus. If focus moves to the title while the panel is open, the panel closes and the keyboard shows.
- **Height:**
  - With a software keyboard, the last reported keyboard height for the current orientation, so the entry doesn’t reflow. Keyboard frames include the input accessory bar, which stays above the panel, so the stored height excludes the accessory’s height.
  - With a hardware keyboard, or when no keyboard height is known yet for this orientation (first open from reading, or the first time in landscape), the rows’ fitted height, capped at 50 % of the window height in portrait and 60 % in landscape, where the rows scroll.
  - The panel sizes itself (`UIInputView` with `allowsSelfSizing`), and the height is recomputed on open and on rotation.
- **Rotation while open:** the panel stays open. Its height is recomputed for the new orientation as above and applied with `reloadInputViews()` without animation. Selection and scroll position are kept.
- **Open/close:** set or clear the session flag, then call `reloadInputViews()` inside `UIView.performWithoutAnimation`.
  - **Fallback:** if the system still slides the input view in or out, accept the system transition and record it as a platform exception to the no-animation decision. Don’t fake the swap with a separate overlay window.
  - Tap **Aa** again, the close button, or Escape (hardware keyboard) → the keyboard returns with the current selection. These are the panel’s dismiss path; nothing depends on SwiftUI `onDisappear`.
  - A paragraph, list or indent choice applies and returns the keyboard. B/I/U/S/`<>` keep the panel open. Insert ▸ Link… / Image… return the keyboard, then open the link editor or photo picker, as now.
- **Hardware keyboard:** the panel shows at the bottom. Typing goes into the text; the panel stays until closed.
- **Not editing** (Aa in the bottom bar while reading): editing starts at the remembered selection, or at the end of the entry, and the panel is shown at once in place of the keyboard. There is no separate sheet.
- **Entry position:** the entry’s bottom inset follows the keyboard frame, which the input view changes exactly as the keyboard does. The system keeps the caret above the panel, so `revealSelection` / `restoreRevealedSelection` and the sheet-specific scrolling are removed.
- **Owner check:** confirm on the iPhone that Notes’ Format panel keeps its keyboard toolbar row visible above it, and that it replaces the keyboard rather than covering it. Adjust only if Notes differs.

### D6 — iPad Formatting (I2)

In regular width, below accessibility text sizes, keep the popover anchored to the Aa that was used (keyboard accessory or bottom bar). Present and dismiss with `animated: false`, with the prebuilt content from D2.

- **Same-tap guard.** The accessory’s Aa is in the keyboard’s window, outside the popover’s dismissal area. A tap there can both dismiss the popover and trigger Aa. The guard is minimal: `presentationControllerWillDismiss` records the current time, and an Aa action within a short interval after it (0.35 s) does nothing. If the popover is still shown when Aa acts, Aa closes it (dismiss path, focus unchanged: the text kept it).
- **Taps in the text.** The focused text view is in the popover’s `passthroughViews`, so a tap in the text places the caret in one tap. Passthrough taps don’t dismiss, so the popover is **dismissed explicitly when the selection changes by a touch in the text**. Selection changes made by a formatting command don’t dismiss it (the session marks commands in progress).
- **Size class changes while open** (Split View, Stage Manager, rotation into compact): close the popover and restore the keyboard. The person opens the D5 panel again if wanted; there is no automatic hand-over.
- At accessibility text sizes, or in compact width, use D5.
- *Deferred decision:* whether to use the popover at all widths except accessibility sizes. Decide after testing on an iPad.

### D7 — Template chooser on iOS (I3, I4)

Content and copy are unchanged (“Choose a Template”, Cancel/close, “Search Templates”, rows, empty states, errors). Present without animation: set the presentation flag in a `Transaction` with `disablesAnimations = true` for both the iPhone sheet and the iPad popover, and dismiss the same way. The iPhone sheet keeps its `.medium`/`.large` detents and grabber: it’s a list the person may want to expand. The search field still takes focus. The keyboard’s own slide-in is system behavior and can’t be removed (recorded exception).

### D8 — Link editor (M4, iOS)

Content and copy are unchanged: title “Add Link”, fields “Text” and “Link”, **Cancel** and **Add Link**, and “Enter a valid web or email address.” when the address is invalid. Present without animation using the same `Transaction` approach; on iOS this is expected to work.

**Possible exception (Mac):** SwiftUI’s `.sheet` on macOS is an AppKit window sheet. If the transaction doesn’t suppress its slide, keep the system sheet animation rather than replacing the sheet with a custom window: a window-modal sheet’s attachment is its native affordance, and ⌘K is less frequent than styling. Record the outcome.

On the Mac the sheet opens only after the Formatting popover has closed, which D1 makes immediate, so the two presentations no longer overlap. The link applies to the selection current when Link… was chosen.

### D9 — File ▸ New Entry from Template… (M3)

It stays a sheet (a menu command with no anchor), with copy unchanged. It gets the same no-animation treatment as D8, with the same Mac exception if AppKit won’t suppress the slide.

### Unchanged by design

All native menus (M5–M8, I5), Change Date and confirmation dialogs (M9, not writing-time; system animation kept).

## Accessibility

- **VoiceOver, Mac.** The Formatting and Templates… items keep their labels.
  - Opened by VoiceOver or Full Keyboard Access: the popover becomes key, focus goes to Bold (Formatting) or the search field (Templates…), and a focus-changed notification is posted, so VoiceOver announces “Bold, off, button” or “Search Templates, search field”.
  - Closed with Escape, the item or a closing row: focus returns to the toolbar item.
  - Opened with the mouse while VoiceOver is off: the text stays key. The popover stays reachable to VoiceOver as a window.
  - Toggle state is exposed as a value (On/Off/Mixed); the current paragraph style has the Selected trait.
- **Keyboard, Mac.** With Full Keyboard Access, Tab reaches the toolbar item and Space opens the popover as key. Inside, Tab moves through the controls, Space/Return activates, and Escape closes and returns focus to the item. Opened with the mouse, the popover isn’t key; the keyboard keeps typing into the entry and Escape closes the popover. The menu-bar Format menu keeps every command with its shortcut.
- **VoiceOver, iOS.** When the Format panel appears, VoiceOver focus goes to the “Format” heading (screen-changed notification). Closing returns focus to the text at the caret. The panel is reachable by swiping. Aa exposes the Selected trait while the panel is open.
- **Keyboard, iOS/iPadOS.** Escape closes the panel or popover. The Format commands (⌘B, ⌘I, ⌘U, headings) work without opening it, and update the panel if it’s open.
- **Reduce Motion, increased contrast, reduced transparency, text size.** No animations remain in these panels. Popover and panel materials are system ones. Rows use Dynamic Type on iOS and scroll when they don’t fit; on the Mac the height follows the rows.

## States

- **Not editable** (locked, conflict, trash, source-only entry where rich styles don’t apply): Formatting is disabled, as today. If editing becomes unavailable while the panel or popover is open, it closes without refocusing.
- **Entry changes while open** (sync replaces or removes the entry, another entry selected): the panel or popover closes and applies nothing. This is the existing rule on the Mac and a new check on iOS.
- **Saving and sync:** unaffected and quiet; styling edits the draft like typing.
- **Templates offline or errors:** unchanged copy (see D4).

## Verification plan

1. **Mac, real UI.** Build the team-signed dev app. When the owner’s running instance can be quit, or with the owner’s help, run it against an isolated data directory. Check:
   - Formatting and Templates… appear on the click, like the ⋯ menu, and close at once;
   - a second click closes with no flash, at slow and fast click speeds, and with keyboard-opened popovers;
   - clicking the text closes it and places the caret there (no old selection restored);
   - clicking the sidebar or search closes it and focus stays there;
   - Escape;
   - Shift-arrow selection with the popover open updates the checkmarks;
   - B/I/U and ⌘B while open (popover stays, text and state update);
   - a heading closes it;
   - Insert ▸ Link…;
   - Full Keyboard Access and VoiceOver open, move through and close (focus back on the item).
   
   Screenshots in light, dark and larger text. The owner confirms the feel next to Notes.
2. **Mac, measured.** Add a formatting step to the opt-in `JournalMeasurements` heavy-library run (`scripts/measure-app.sh`). Measure main-thread busy time from the Formatting action to the popover being on screen, per B/I/U tap, and on close, before and after. Target in Release: ≤ 16 ms for open and per tap; stretch goal ≤ 8 ms (one 120 Hz frame). Use Instruments’ SwiftUI template for a before/after count of `RootView` and `AppCommands` body evaluations: **zero** caused by opening, styling or closing.
3. **iOS, real UI (one simulator, then the owner’s iPhone).** Record with `simctl io recordVideo` and compare frame times as in Measurements. Check:
   - Aa → panel fully shown within one frame of the tap’s highlight, with no further motion;
   - caret or selection visible;
   - B applies live;
   - moving the selection while the panel is open retargets the commands;
   - close returns the keyboard with the current selection and no bounce (software keyboard on);
   - repeated Aa taps;
   - a table cell;
   - rotation while open;
   - a hardware keyboard;
   - opening from reading.
   
   On iPad (regular width), check the popover: a second Aa tap closes without reopening, a tap in the text moves the caret and closes it, and a Split View resize closes it and restores the keyboard. Check the template chooser without presentation animation. At the largest accessibility text size in dark mode, the panel scrolls and nothing clips. Do a VoiceOver pass on the panel.
4. **Regression tests (meaningful only):**
   - *`PopoverClickGuard`* (new, pure unit tests, no windows): the click whose mouse-down closed the popover doesn't reopen it; a click elsewhere followed quickly by a click on the button opens it; keyboard or VoiceOver activation always toggles; each click is decided once. The real-window second-click check stays in manual verification (step 1), so the automated test doesn’t depend on window-server timing.
   - *Formatting doesn’t republish the window* (new, small): capturing formatting and applying Bold through the session changes the text and `session.state`, and sends **no** `EditorActions.objectWillChange`. This guards the main lag cause (R3) against someone re-adding `@Published`.
   - *Commands follow the live selection* (extend `FormattingRuntimeTests`, which already drive the real editor): open a session, move the selection, apply Bold. The new range is bold and the original isn’t. Type a character, then apply Italic: it still applies, where today’s session drops it. `session.state` reflects the new selection.
   - *iOS panel, focus and selection* (extend an existing writing UI test): while editing, select word A, tap Aa, move the selection to word B, tap Bold. Assert B is bold and A isn’t. Close; assert the text view still has focus and the caret or selection is where the person last put it (on B).
   - No tests of popover layout, labels or animation flags.

## Design review

**Revision 1 → approved with required changes** (independent design reviewer, 2026-09-30). The reviewer confirmed the flash root cause (R6) against the code, and agreed with a non-animated `NSPopover` on the Mac and a panel in place of the keyboard on iPhone. Required changes and where revision 2 addresses them:

| # | Required change | Revision 2 |
| --- | --- | --- |
| 1 | Commands follow the live selection; the session state refreshes on selection and text changes, including ⌘B while the popover is open | D2 (current selection, image exception, coalesced refresh), D3, tests |
| 2 | Closing and focus depend on the trigger: an outside click doesn’t restore the selection or take focus; Escape, the button again, Close or a closing row do; driven by `popoverDidClose` or the panel’s dismiss path, not `onDisappear` | D1 (close reasons), D5 (dismiss path), D6 |
| 3 | Mouse-opened popovers leave the text key; Full Keyboard Access or VoiceOver opens make the popover key, focus Bold and post the notification; closing returns to the item; fix the accessibility claims | D1 (how it was opened), Accessibility |
| 4 | Specify the iOS input-view swap: commit marked text, dictation, every first responder including table cells, height sources, rotation, the animation fallback, and the keyboard-frame inset replacing reveal/restore | D5 |
| 5 | iPad: same-tap guard for the accessory Aa, explicit dismissal on selection change with passthrough, close on size-class change | D6 |
| 6 | “Aa selected” and “panel open” live on the session, not `EditorActions`’ `@Published` | D2 (`isPresented`), D5 |
| 7 | Mac Templates: reuse the hosting controller, reset search and highlight on open | D4 |
| 8 | Non-flaky Mac toggle test: pure guard type with unit tests; real-window check stays manual | D1, verification 4 |
| 9 | Extend the iOS UI test: move the selection while open, bold the new word, check the caret after closing | Verification 4 |

Optional suggestions adopted:
- tooltips built from the Format menu’s key-equivalent definition, or dropped (D3);
- Escape through the standard `cancelOperation(_:)` instead of a key monitor (D1);
- 120 Hz (8 ms) as a stretch goal (verification 2);
- the owner checks that Notes keeps the toolbar row above its Format panel (D5);
- the iPad popover at all widths is left as a decision after device testing (D6);
- removal of the unreachable Mac `.popover` branch in `EntryCreationActions` (Summary).

**Revision 2 → approved with two required changes** (re-review, 2026-09-30; no further round):

| # | Required change | Revision 3 |
| --- | --- | --- |
| 1 | The guard’s timestamp fallback could swallow “click the text, then quickly click Formatting” | D1: only a mouse-down inside the item’s view is recorded; new unit test |
| 2 | Don’t infer the opening method from a stale `NSApp.currentEvent`; always key with VoiceOver | D1: mouse-opened only for a fresh mouse-up on the item; VoiceOver always key |

Optional notes adopted:
- the iOS panel height excludes the accessory bar (D5);
- the Mac `TableCellTextView` handles `cancelOperation(_:)` too (D1);
- the iPad same-tap guard uses the current time and stays minimal (D6);
- tooltips are dropped, since no shared shortcut table exists (D3).

## Implementation notes (for the author, not the reviewer)

- `ToolbarPopover` is in `Views/MacFormattingButton.swift`, its callers in `Views/Mac/JournalToolbarController.swift`, and the configuration closures in `Views/Mac/RootView+MacWindow.swift`.
- The iOS presenter `Views/MobileFormattingPresenter.swift` becomes the input-view panel. The Aa buttons are in `Editor/WritingAccessory.swift` and `RootView.mobileFormattingButton`. The per-cell accessory is in `Editor/InlineTableGridIOS.swift`.
- The formatting sessions are `formattingSession()` in `Editor/NativeEditor.swift` (Mac and iOS) and `cellFormattingSession` in `Editor/TableCellFormatting.swift`. State lives in `EditorActions` in `Editor/RichText.swift`, and the reveal/restore helpers are in `Editor/SelectionReveal.swift`.
- The harnesses used for the measurements were throwaway and have been deleted.

## Implementation record (2026-09-30)

### Changed

| Area | Files |
| --- | --- |
| Session state, live selection | `Editor/RichText.swift` (`FormattingSession`, `EditorActions`), `Editor/FormattingState.swift` (Equatable), `Editor/NativeEditor.swift`, `Editor/NativeTextView.swift`, `Editor/EditorSession.swift`, `Editor/InlineTableGridIOS.swift`, `Editor/InlineTableGridMac.swift` |
| Mac popovers | `Views/MacFormattingButton.swift` (`ToolbarPopover`, `PopoverButton`), new `Views/PopoverClickGuard.swift`, `Views/Mac/JournalToolbarController.swift`, `Views/Mac/RootView+MacWindow.swift` |
| Formatting contents | `Views/FormattingPopover.swift` (no `EditorActions` observation; compact iOS header; Mac sized to its rows) |
| iPhone panel, iPad popover | `Views/MobileFormattingPresenter.swift` (rewritten), `Editor/WritingAccessory.swift`, `Views/RootView.swift` |
| Templates, link editor | `Views/TemplateChooserView.swift`, `Views/TemplateSearchField.swift`, `Views/EntryCreationActions.swift` (iOS only now), `Views/LinkEditorView.swift`, `AppCommands.swift` |
| Tests | new `JournalTests/PopoverClickGuardTests.swift`, new `JournalTests/FormattingSessionTests.swift`, `JournalUITests/PreReleaseUITests.swift` (new panel test; Format sheet tests adapted), `JournalTests/EntryActionTests.swift`, `JournalTests/PasswordOnboardingTests.swift` (previews use the new initializer) |

### Deviations and open points

- **iPhone panel height — owner decision 2026-09-30: option (b).** The Format panel is exactly the keyboard's height, without its accessory bar, for the current orientation, so the entry doesn't move and the line being styled stays visible above the Aa bar. The rows scroll, with the scroll indicator flashing when they don't all fit; VoiceOver scrolls them as any scroll view, and the largest text size scrolls the same way. Without an on-screen keyboard (hardware keyboard, or none shown yet in that orientation) it is as tall as its rows, up to 40 % of the window in portrait and 50 % in landscape. **This reverses the earlier rule that every Format option shows without scrolling on iPhone** (`pre-release-ui-2026-09-27.md` §5). The UI test now checks that the bar above the panel stays where the keyboard's was and that scrolling reaches Insert.
- **The template chooser still observes `AppModel`.** Its choices are now O(n) and it is reused on the Mac, but the small view-model from D2 wasn't introduced: the chooser needs the model's `newEntry(template:)`, error and journal list, and the cost while it is open is small.
- **`Editor/SelectionReveal.swift`** (the sheet's reveal/restore scrolling) is no longer used. I didn't delete a file I didn't create; delete it with the owner's go-ahead.
- **Mac toolbar items** for Formatting and Templates… are now button views (like Editor Only), with an overflow-menu entry. Their look in the toolbar is unchanged in screenshots.
- **Tooltips** stay the plain names; there is no shared shortcut table (D3).
- **iPad**: the popover is sized to its rows, and any selection change that isn't a formatting command closes it. That includes hardware-keyboard selection, as a tap in the text does.

### Verification done

- **Mac (team-signed dev build, isolated library):**
  - The popover opens without animation, sized to its rows.
  - B/I/U apply while it stays open, and the toggle state updates live.
  - Escape (through the text view's `cancelOperation`) closes it, with the selection kept and bold applied.
  - Templates… opens with the search field focused, Escape closes it, and it reopens with the search cleared.
  - Main-thread time from the action to the next run-loop turn: 41–48 ms the first time (content creation, Debug), 8–12 ms afterwards; a style command takes 2.8 ms.
  - The second-click check with real mouse input wasn't possible: background input is synthetic (every click reports event number 3, timestamp 0 and a closing mouse-down different from the button's), and full-screen control was interrupted by the owner's own use.
  - The shipped `ToolbarPopover`/`PopoverButton`/`PopoverClickGuard` code was compiled into an AppKit harness with events posted through `NSApplication`. A second click closes the popover (slow and fast), no second popover is created, and a click in the text followed within 50 ms by a click on the button opens it.
  - **The owner should confirm the second click on real hardware.**
- **iPhone 17 simulator (dedicated device, software keyboard):**
  - The panel replaces the keyboard without animation, in one frame of screen recording, where the old sheet started about 200 ms after the tap and then took about 780 ms.
  - Measured from Aa to the rendered transaction in the Debug build: 113 ms the first time (building the panel), 44–49 ms afterwards. A style command takes 6–11 ms.
  - The text keeps keyboard focus throughout. The new UI test covers moving the selection while the panel is open and the caret after closing.
  - Checked in light, dark and the largest text size (the panel scrolls; the close glyph now has a fixed size), plus the table-cell flow in `FeedbackWorkflowUITests`.
- **iPad Air 11-inch simulator:**
  - The popover points at Aa and keeps the keyboard.
  - The same UI test passes with the popover (moving the selection closes it; Close restores).
  - Before/after screenshots of the header: the bulky header was ours — a `NavigationStack` with a toolbar close button inside the popover — and is now a compact title row with a small close button.
- **Not verified:** VoiceOver and Full Keyboard Access on the Mac (they can't be turned on here), and iPhone landscape rotation while the panel is open. The link editor's and New Entry from Template…'s no-animation presentation on the Mac isn't verified: the SwiftUI transaction may not suppress AppKit's sheet slide.


### Follow-up fixes (owner feedback, 2026-09-30)

- **iPad popover top gap.** About 40 pt of blank space above “Format” was our bug: the hosting controller added the popover's top safe area as padding. It now ignores the safe area (`safeAreaRegions = []`, iOS 16.4 and later), so the title row sits as close to the top as the sides. With the space recovered, every row fits in the popover above the keyboard.
- **Two formatting controls on iPad.** The keyboard's shortcut bar showed the system's B/I/U and text-format (Aa) buttons next to our Aa. That is the system's text formatting, offered because the entry allows attributed-text editing. As in Notes, only our Formatting shows now: the shortcut bar's trailing group is removed for the entry text and table cells. Undo, redo and paste stay.
- Screenshots: `scratchpad/ipad-format-header.png` (before and after), `scratchpad/iphone-format-height.png` (the height options the owner chose from), `scratchpad/iphone-panel-portrait.png` and `scratchpad/iphone-panel-landscape.png` (the chosen keyboard-height panel).
