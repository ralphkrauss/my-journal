# Windows mappings

How the Windows app presents each screen and flow of the spec: WinUI 3 and the Windows App SDK, Fluent 2, C#. The Apple app is the reference implementation of the product; a Windows mapping says which Windows controls, gestures and shortcuts do the same job, what the Windows wording is where Windows convention requires another string, and where Windows differs on purpose and why. The goal is a Windows app that has the same features, the same pages and the same copy as the Apple app, and feels as if Microsoft built it.

Where the spec and a mapping disagree about behaviour, the spec is right and the mapping has a bug. Where Windows convention and the Apple presentation disagree about presentation, the mapping follows Windows and says so under Different by design. Product rules are never traded for convention: data safety, quiet saving and syncing, plain copy, no exclamation marks, nothing silently discarded, nothing of the journals shown while locked.

## Files

| Path | Contents |
| --- | --- |
| [platform.md](platform.md) | The conventions every mapping follows, each with the Apple equivalent and the reason: shell and window, menus, dialogs, keyboard, copy casing, App Lock, secure storage, packaging, icons, accessibility and more. Start here |
| [commands.md](commands.md) | Every command id of [commands.md](../../commands.md) with its Windows placement, shortcut and scope. One row per id; the checker verifies it |
| [index.md](index.md) | Every screen, flow and `messages` page of the spec, its mapping file and its status, in three batches |
| [copy-proposals.md](copy-proposals.md) | Every proposed Windows wording in one table (key, default text, proposed text, category, rule or question), for the owner to review. Nothing in it is in `copy/en.json` yet |
| [review-2026-10-06.md](review-2026-10-06.md) | The independent design review of this whole folder: the verdict and, for every finding, whether it was adopted, changed or declined and why |
| `screens/<id>.md` | The mapping of one spec screen |
| `flows/<id>.md` | The mapping of one spec flow |
| `messages.md` | The mapping of [messages.md](../../messages.md) |

Folders mirror the spec's, because a screen and a flow can share an id (`connect-to-server`). A mapping's `id` is the file name and the spec page's id.

## Writing a mapping file

Start with a front-matter block:

```yaml
---
id: settings-sync              # the spec page's id and this file's name
title: Settings ▸ Sync (Windows)
spec: screens/settings-sync.md # the spec page this maps, relative to spec/; screens/<id>.md, flows/<id>.md or messages.md
features: [sync-connect, sync-now, stop-syncing]   # parity.yaml ids; a subset of the spec page's own features
status: draft                  # draft, reviewed or done (index.md also has todo for files not written yet)
sources:                       # optional: Microsoft pages this file relies on beyond platform.md
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobar
---
```

Then these sections, in this order. A section that does not apply says "Not applicable." and why, so the checker and the reader can see it was considered.

1. **Controls.** What the page is made of, element by element, in the order of the spec's Content section: the WinUI control, the copy keys it shows, its states. Name the control exactly (`SettingsCard`, `ContentDialog`, `InfoBar`), the properties that matter (`DefaultButton`, `IsClosable`, `InputScope`), and the Fluent type style and icon where they are not the defaults ([platform.md, 22 and 23](platform.md#22-typography)). Say which elements are empty-state, loading, offline and error states and which control shows each.
2. **Layout at each window width.** What the page does in the large (1008 epx and up), medium (641 to 1007) and small (640 and down) layouts, and what changes with text scaling ([platform.md, 2.2](platform.md#22-layout-by-window-width)). For a dialog: its width and how it scrolls. Say which Apple layout each one corresponds to (Mac, iPad, iPhone).
3. **Commands and shortcuts.** A table with the columns `Command`, `Placement`, `Shortcut` and `Enabled when`, one row per command the page uses. `Command` holds only command ids from [commands.md](../../commands.md). Placement and shortcut repeat [commands.md](commands.md) only where this page adds something; otherwise write "as in commands.md". Add any keyboard behaviour of the page (focus order, Enter and Esc in dialogs, arrow keys in lists).
4. **Copy differences.** Only where Windows wording conventions require a string different from the spec's ([platform.md, 12](platform.md#12-copy-casing-ellipses-and-vocabulary)). For each: the copy key, the default text, the proposed Windows text, and the category (casing, ellipsis, vocabulary, shortcut text, removed). Casing differences are `sentence` variants, named for the casing and shared with Android (`{"default": …, "sentence": …}`); every other category is a `windows` variant, written in sentence case itself (`{"default": …, "windows": …}`), because only the words differ there. A difference is proposed as a catalog variant and recorded in [open-questions.md](../../open-questions.md), section B or D; **never change a string silently**, and never edit [copy/en.json](../../copy/en.json) from a mapping. Every difference also gets a row in [copy-proposals.md](copy-proposals.md), the single list the owner reviews. Once the owner approves the casing rule (D21) and a row's question, the tool that writes the `sentence` and `windows` variants applies the approved rows, the mapping files' tables shrink to links, and the proposals file is deleted; the steps are in "Applying the proposals" there. If the page has none, write "None. Sentence case applies as in platform.md, 12."
5. **Accessibility.** What is specific to this page beyond [platform.md, 24](platform.md#24-accessibility): the UI Automation name, role and `HelpText` of each control, headings and landmarks, the order of focus and where it goes after each action, which changes are announced and how (notification event or live region), and how the page behaves with Narrator, with the keyboard only, in the four contrast themes and at 225% text size.
6. **Different by design.** Each place where this page differs from the Apple presentation, as a short list: what Apple does, what Windows does, and the reason. No difference without a reason. Features that are not offered on Windows appear here with their reason; the owner decides whether [parity.yaml](../../parity.yaml) marks them `different-by-design` or `not-applicable`.
7. **Open questions.** A one-line pointer to [open-questions.md](../../open-questions.md), or "None". Put each new question there (section A, B, C or D) with the spec and code files involved, not in the mapping file. Do not silently decide what is the owner's to decide.

Rules for authors:

- Link to [platform.md](platform.md) instead of repeating a convention; the mapping records only what is specific to its page.
- Describe controls and behaviour, not code. A short XAML or C# fragment is fine when it is the clearest way to say which property to set; never paste implementation.
- Use the spec's copy keys, not copies of the text. Quote an English string only in Copy differences.
- Prefer native WinUI controls and Windows conventions to copying Apple; keep the product rule and change only the presentation.
- Name Microsoft guidance by link, from learn.microsoft.com, with the date it was checked when it matters.
- No personal names, host names or home paths: this folder is public.
- Reference apps for "feels like Windows" are Settings, Notepad, Photos, Mail and Outlook, and the WinUI Gallery. Dev Home is not a reference: Microsoft retired it in May 2025.

## The design gate

A mapping is design work in the sense of [AGENTS.md](../../../AGENTS.md): before the screen is implemented, an independent design agent reviews the mapping (the requirements and the proposal, not the author's defence), the findings are addressed and the outcome is recorded, and after implementation the running UI is inspected against the mapping. `status` follows it: `draft` when written, `reviewed` after the review, `done` after the implementation has been checked. [index.md](index.md) shows each page's status.

## Design review

The whole folder had its independent design review on 2026-10-06, and the findings are addressed. **Verdict:** unusually thorough and mostly well grounded (the shell, Settings as cards, `InfoBar` notices, one dialog at a time, sentence case, Windows Hello through the desktop interop, DPAPI behind `ISecretStore`, clipboard-history exclusion, Windows-safe file names all match Microsoft guidance), but not ready for implementation until five things were settled: the editor plan (two spikes in parallel with written criteria), the privacy cover (dropped), the heading shortcuts (Ctrl+Shift+digit instead of Ctrl+Alt+digit, which is AltGr), formatting (a toggleable bar and a selection mini-toolbar instead of a flyout) and App Lock's lock-out hole (it pauses) together with Windows 11 as a requirement. [review-2026-10-06.md](review-2026-10-06.md) records, finding by finding, what was adopted, changed or declined and why, and lists the pages that need a second review because they were substantially revised. Pages whose findings are all resolved are `reviewed`; the others stay `draft` ([index.md](index.md)).

## Checking

```sh
python3 spec/tools/check-spec.py
```

For this folder the checker verifies that:

- every mapping file has a front matter whose `id` is its file name, a `title`, a `spec` that is the spec page it maps, `features` that exist in `parity.yaml` and are listed by that spec page, and a `status`;
- every required section is present, in order;
- every command id named in a `Command` column exists, and every copy key and page id named anywhere exists;
- [commands.md](commands.md) has exactly one row for each command id of the spec, and no app-wide or editor-wide shortcut is used twice;
- [index.md](index.md) lists every screen, flow and `messages` page once, with the right file name and a status that matches the file.
