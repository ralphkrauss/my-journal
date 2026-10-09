---
id: welcome
title: Welcome, first launch (Windows)
spec: screens/welcome.md
features: [create-library, connect-from-welcome, import-archive-from-welcome, launch-states]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/buttons
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/progress-controls
  - https://learn.microsoft.com/en-us/windows/apps/design/basics/titlebar-design
---

# Welcome, first launch (Windows)

The first page on a PC without a library. It offers three ways in: start a new library here, join an existing one through a server, or start from a backup archive. Behaviour, the launch precedence and copy keys are the spec's [welcome](../../../screens/welcome.md); the paths it opens are [create-library](../flows/create-library.md), the Connect task page ([connect-to-server](../../../flows/connect-to-server.md)) and [import-archive](../flows/import-archive.md).

## Controls

The page fills the content area under the title bar; there is no navigation pane, no list and no editor. The title bar and the Mica backdrop are the shell's ([library-window](library-window.md)); **the menu bar and the pane button are not shown on this page** (a row of disabled menus on a first-run page is noise and tells Narrator the app has content): the title bar holds the icon, the name, one More button whose flyout has Settings, Help and Exit, and the caption buttons. The window title is `library.app.name`.

What the window shows at launch, in the spec's order of precedence, as the `Frame` of the window's content:

1. Reading the configuration: a loading page.
2. A library exists and is locked: the lock page ([platform.md, 13](../platform.md#13-device-authentication-and-app-lock), [screens/lock-screen](../../../screens/lock-screen.md)).
3. No library: this page.
4. A library from an early build whose recovery key is not confirmed: not applicable on Windows ([recovery-key](recovery-key.md)).
5. Otherwise the library window.

| Spec element | Windows control | Notes |
| --- | --- | --- |
| Loading | Centred `ProgressRing` (indeterminate, 32 epx) above `library.app.loading`, `Body`, secondary | Blocks the window, so a ring, not a bar ([11](../platform.md#11-progress-and-announcements)). No other control is shown. Narrator reads the text; the ring is hidden from the tree |
| Decorative symbol | `FontIcon` Library (E8F1), 48 epx, neutral foreground, `AutomationProperties.AccessibilityView` Raw | The closed book of the spec |
| Title | `TextBlock`, `TitleTextBlockStyle`, heading level 1: `library.welcome.title` | |
| Message | `TextBlock`, `BodyTextBlockStyle`, secondary: `library.welcome.message` | |
| Primary action | `Button` with `AccentButtonStyle`: `library.welcome.start`, the first focus and the default of the page | Opens [create-library](../flows/create-library.md) |
| Secondary action | A standard `Button`: `common.connectToServer` | Opens the Connect task page ([connect-to-server](connect-to-server.md)) |
| Plain action | A standard `Button`: `common.importArchive` | Opens the archive file picker, then the Import archive task page ([import-archive](../flows/import-archive.md)) |
| Error | A `ContentDialog` (Close `common.ok`, no title, content the error) over the page | A failure opening the configuration. [8.1](../platform.md#81-rules) |

The three buttons are one column of equal width (280 epx), centred under the message. Their spacing is 8 epx; the primary one is accent-coloured, the other two are neutral.

Rules of the spec that Windows keeps: nothing is created until the person chooses an action; this page writes nothing.

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large, medium and small | A centred column at most 480 epx wide, vertically centred in the content area, with 24 epx margins (12 at small width). Buttons fill the column width at small width. The page scrolls vertically when it does not fit | Identical on iPhone, iPad and Mac |
| 200% text size or more | The column keeps its width limit, text wraps, the page scrolls, every action stays reachable | Scrolling at accessibility sizes |

The page is the same at every window width, so no layout step applies. The minimum window size is the shell's (360 × 420 epx).

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `connect-to-server` | The page's button | none | Always |
| `import-archive` | The page's button | none | Always: it stays enabled with no library |
| `open-settings` | The More button's flyout; Ctrl+, | as in commands.md | Enabled here; there is no navigation pane on this page. The Settings page opens in the main window and Back returns to this page |
| `quit` | The More button's flyout; the Close button | Alt+F4 | Always |

The commands that need a library (New entry, Use a template…, New journal…, Export archive…, Export journals as Markdown…, Search entries, Pin entry and Lock My Journal) are not reachable on this page because the menu bar is not shown; the shortcuts do nothing. Keyboard: the first Tab stop is Start a journal and has focus when the page appears; Enter chooses the focused button; Tab goes Start, Connect, Import. A `.journalarchive` file dragged onto the window or opened from Explorer starts the import ([import-archive](../flows/import-archive.md)).

## Copy differences

Sentence case on the three actions ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)):

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `library.welcome.start` | Start a Journal | Start a journal | casing |
| `common.connectToServer` | Connect to a Server… | Connect to a server… | casing |
| `common.importArchive` | Import Archive… | Import archive… | casing |

The title and message are unchanged. The ellipses stay: each opens a page or picker that asks for input.

## Accessibility

- The reading and tab order is title, message, Start a journal, Connect to a server…, Import archive…; the symbol is decorative and hidden from the tree.
- Narrator reads the page when it appears: the heading, then the first focus (Start a journal, a button with its name). Nothing is announced while loading except the loading text.
- The page works with the keyboard alone and at 225% text size (it scrolls). In contrast themes the accent button uses the system's accent-button colours and the neutral buttons keep their borders.
- Reduced motion: the page appears without a transition.

## Different by design

- **Three buttons, not a link and a plain action.** Apple's secondary action is a link styled in the accent colour; on Windows a hyperlink navigates and a button acts, so all three are buttons, the one primary action accented.
- **No pane, no recovery-key step.** The page has no navigation pane because there is nothing to navigate to, and the early-build recovery key state does not exist on Windows.
- **No menu bar here.** The Mac keeps its menu bar with most items disabled; Windows shows the title bar's More button instead, with Settings, Help and Exit.
- **Dropping an archive file onto the window**, or opening one from Explorer, starts the import from here through the `.journalarchive` file association ([import-archive](../flows/import-archive.md), D29).

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D29 (the archive as one file), D20 (menu bar hidden on first-run and lock pages).
