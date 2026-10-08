# Apple implementation notes

How the Apple apps present each screen and flow of the spec: one SwiftUI source tree with AppKit and UIKit text editing, shipped on iPhone, iPad and Mac. An implementation note says which controls and layout do each job, where iPhone, iPad and Mac differ, which source files implement it, and what it looks like (with screenshots). Apple shipped the first versions of most features, so for those features it is the reference platform (`reference: apple` in [parity.yaml](../../parity.yaml)); it is not the reference for features that originate elsewhere, and where a note and the spec disagree, one has a bug and the owner decides which is fixed ([spec/README.md](../../README.md)).

The notes exist so that an agent on Windows or Android, which cannot run the Apple apps or take their screenshots, can port a feature from the spec, the note, the screenshots and the source files. Write for that reader: name the control, name the file, say what is not obvious.

Status: the folder structure and conventions are defined; the pages are written from the source and the running apps, in the order of [index.md](index.md), and the screenshots they list are produced by the capture script `design/spec-screenshots/capture.sh` (see `design/spec-screenshots/README.md`). Until a page exists its row in the index is `todo`; a page is `draft` until it has been checked against the current source and its screenshots.

## Files

| Path | Contents |
| --- | --- |
| [platform.md](platform.md) | The conventions every Apple page follows: devices and layouts, shell and windows, menus, sheets and alerts, keyboard, copy variants, App Lock, secure storage, packaging, accessibility and more. Start here |
| [commands.md](commands.md) | Where every command of the spec's [commands.md](../../commands.md) appears on iPhone, iPad and Mac, its shortcut and what differs. One row for each command id |
| [index.md](index.md) | Every screen, flow and `messages` page of the spec, its Apple page and its status |
| `screens/<id>.md` | The implementation note of one spec screen |
| `flows/<id>.md` | The implementation note of one spec flow |
| `messages.md` | The note for [messages.md](../../messages.md) |
| [screenshots/](screenshots/README.md) | Captures by device: `screenshots/<device>/<id>-<state>.png` |

What a command means, its scope and when it is enabled are defined in the spec's [commands.md](../../commands.md); the Apple file holds only where the Apple apps place it and how it is invoked. A page's Commands and shortcuts section links to the command ids and adds only what the page adds (focus order, Return and Escape in sheets); pages in `screens/` and `flows/` link the placements as `[commands.md](../commands.md)`.

Folders mirror the spec's, because a screen and a flow can share an id (`connect-to-server`). A page's `id` is its file name and the spec page's id.

## Writing a page

Start with a front-matter block:

```yaml
---
id: settings-sync              # the spec page's id and this file's name
title: Settings ▸ Sync (Apple)
spec: screens/settings-sync.md # the spec page this describes, relative to spec/
features: [sync-connect, sync-now]   # parity.yaml ids; a subset of the spec page's own features
devices: [iphone, ipad, mac]   # where the page exists: any of iphone, ipad, mac
status: draft                  # draft or verified
sources:                       # repository paths of the code that implements it, and the design records
  - apps/apple/JournalApp/Views/SettingsView.swift
  - apps/apple/JournalApp/Views/SyncNowRows.swift
screenshots:                   # files under screenshots/, named <device>/<id>-<state>.png
  - screenshots/mac/settings-sync-connected.png
  - screenshots/iphone/settings-sync-connected.png
---
```

`status` is `draft` when the page is written from the source, and `verified` when it was checked against the current source and the screenshots were captured from the running apps by the capture script ([platforms/README.md](../README.md), Screenshots). A change to the UI that touches a verified page sets it back to `draft` until the page and its screenshots are updated, which belongs in the same change as the code.

Then these sections, in this order. A section that does not apply says "Not applicable." and why, so the reader and the checker can see it was considered.

1. **Controls.** What the page is made of, element by element, in the order of the spec's Content section: the SwiftUI view or AppKit/UIKit control (`List`, `Form`, `NavigationSplitView`, `Table`, `.sheet`, `.alert`, `NSTextView`), the copy keys it shows and its states. Name the type exactly and the modifiers that matter (`.listStyle(.sidebar)`, `.keyboardShortcut`, `.toolbar` placement, `role: .destructive`). Say which elements are the empty, loading, offline and error states and which control shows each. Name the model type that feeds the page (`AppModel` extension, store, sync engine).
2. **Layout.** What the page does on each device: iPhone (compact width, stacked navigation), iPad (regular width, split view, landscape and portrait, Stage Manager and Slide Over widths) and Mac (window, sidebar, toolbar, Settings window). Name the size classes or conditions that switch layouts, and what changes with Dynamic Type.
3. **Commands and shortcuts.** A table with the columns `Command`, `Placement`, `Shortcut` and `Enabled when`, one row per command the page uses. `Command` holds only command ids from the spec's [commands.md](../../commands.md), which defines them. Placement and shortcut repeat the Apple [commands.md](commands.md) only where the page adds something; otherwise write "as in commands.md", linked as `../commands.md` from a page in `screens/` or `flows/`. Add keyboard behaviour of the page (focus order, Return and Escape in sheets, arrow keys in lists, hardware keyboard on iPad).
4. **Copy differences.** The `mac` variants and any other place where Apple's text differs from the spec's default text, with the copy key and the reason. If none, "None."
5. **Accessibility.** What is specific to this page beyond [platform.md](platform.md): VoiceOver labels, hints, traits and custom actions, headings and rotor use, focus after each action, announcements, behaviour at the largest accessibility text size, with Reduce Motion, Increase Contrast and Reduce Transparency, with Voice Control and Full Keyboard Access.
6. **Differences between iPhone, iPad and Mac.** Each place the page differs between devices, as a short list: what each device does and why. A difference without a reason is a bug in the page. This is where "iPhone and iPad only" and "Mac only" features are explained.
7. **Screenshots.** One line per screenshot in the front matter: the file as a Markdown image, and what state it shows. Put each in a short table or list, grouped by device. A page with no screenshots starts this section with "None." and the reason (for example, a message-only page, or not captured yet).
8. **Source files.** The files that implement the page, grouped as view, model and core, with one line on what each does for this page, so a porter knows where to read first. Keep it to the files a porter needs; link design records in `docs/design/` for the reasoning and the review outcome.
9. **Open questions.** A one-line pointer to [open-questions.md](../../open-questions.md), or "None." Put each new question there (section A, B, C or D) with the spec and code files involved. Do not silently decide what is the owner's to decide.

Rules for authors:

- Link to [platform.md](platform.md) instead of repeating a convention; the page records only what is specific to it.
- Describe controls and behaviour, not code. A short Swift fragment is fine when it is the clearest way to say which modifier or type to use; never paste implementation. Point at the file instead.
- Use the spec's copy keys, not copies of the text. Quote an English string only in Copy differences.
- Record what the code does today, including where it falls short of the spec, as a pointer to a question in [open-questions.md](../../open-questions.md); the owner decides which side is fixed.
- No personal names, host names or home paths: this folder is public. Screenshots show only the seeded sample library.

## The design gate

An implementation note is documentation of shipped behaviour and needs no design review of its own. A change to the Apple UI does: the design gate in the root [AGENTS.md](../../../AGENTS.md) and [apps/apple/AGENTS.md](../../../apps/apple/AGENTS.md) applies before the change is implemented, and the note and screenshots are updated with the change.

## Checking

```sh
python3 spec/tools/check-spec.py
```

For this folder the checker verifies that every page's front matter has an `id` equal to its file name, a `title`, a `spec` that is the spec page it describes, `features` that exist in [parity.yaml](../../parity.yaml) and are listed by that spec page, `devices` from `iphone`, `ipad` and `mac`, and a `status`; that the sections above are present in order; that every command id and copy key named exists; that [commands.md](commands.md) has exactly one row for every command id of the spec's [commands.md](../../commands.md); that [index.md](index.md) lists every screen, flow and `messages` page once with the status the file has; and that every screenshot a page lists is named `screenshots/<device>/<id>-<state>.png` for its own page and device, exists, and is listed by no other page. It warns about screenshots no page lists, and about `sources:` files that do not exist.
