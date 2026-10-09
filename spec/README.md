# Product specification

This folder describes what My Journal is, independent of any platform: every screen, flow, state, message and command, with the exact copy. Each platform client implements it in its own native idiom: Apple (iPhone, iPad, Mac) today, Windows and Android to come. Each platform's folder under `platforms/` adds how that platform implements it, with screenshots, so any feature can be ported at any time by an agent that cannot run the other clients. `docs/design/` keeps the history and the reviews behind each decision; this folder holds only the outcome. When a design is approved, its outcome updates the spec in the same change.

No platform is the reference for the whole product. **Each feature's reference is the platform that shipped it first**, recorded in `parity.yaml` (`reference:`). A port starts from the spec, the reference platform's implementation notes and screenshots, and its own platform's notes. Where the spec and an implementation disagree, one of them has a bug: the spec is fixed or the implementation is, and the owner decides which. Nobody silently follows the implementation or silently rewrites the spec.

## Spec-first workflow

A new feature or a change to an existing one is specified in the same change as its code, on whichever platform it originates (a feature can start on Windows or Android and be ported to Apple):

1. **Update the spec.** Screens, flows, `messages.md`, `commands.md`, copy keys in `copy/en.json` and the feature's entry in `parity.yaml` (`reference:` is the originating platform; its status is `shipped` or `partial` once the code lands, `planned` for the others). Put each unresolved question in `open-questions.md`.
2. **Record the implementation** in the originating platform's folder under `platforms/`: controls, layout, shortcuts, source files, and screenshots of the running UI. Screenshots come from a script (`platforms/README.md`), never by hand.
3. **Pass the design gate** (root `AGENTS.md`) before the UI is built, and run `python3 spec/tools/check-spec.py` before reporting the change done.
4. **Ports follow.** Another platform reads the spec, the reference platform's notes, screenshots and source, and writes its own notes under `platforms/<platform>/`. It may differ in presentation where its platform's convention requires, with the reason under "Different by design"; it may not change behaviour, data rules or copy keys without changing the spec first. A change a port wants to make to the spec goes through the owner, and when accepted every platform's notes are updated.
5. **Shared contracts are separate.** Anything that crosses platforms on the wire or on disk lives in `../protocol/` with conformance fixtures; changing one needs a version bump (root `AGENTS.md`).

## Layout

| Path | Contents |
| --- | --- |
| `screens/<id>.md` | One file per screen, pane, sheet or window: purpose, content, actions, states, copy keys, accessibility. Neutral words only; no platform controls. |
| `flows/<id>.md` | Multi-step tasks with every branch, error and message, for example connecting to a server or adding a device. |
| `messages.md` | Messages that come from the model layer rather than one screen (sync states, save failures, conflicts, unavailable content): when each appears, where, and what the person can do. |
| `commands.md` | Every command (menu item, toolbar action, context-menu action, swipe action, keyboard shortcut) as a platform-neutral id with its name (copy keys), scope, when it is enabled and what it does. One section per area: menu bar, toolbars and context menus, editor, Settings. Each platform places the same command ids (placement, shortcut, notes) in its own `commands.md` under `platforms/`. |
| `copy/en.json` | Every user-facing string, by key: one catalog for all areas. |
| `copy/same-wording.json` | The groups of keys that share one English text on purpose, and why. |
| `parity.yaml` | Each feature's reference platform (`reference:`) and its status per platform, with links to its screens and flows. |
| `open-questions.md` | Every open question in the spec, in one place: likely app bugs, copy inconsistencies, design records lagging the code, and product questions for the owner. |
| `tools/check-spec.py` | The consistency checker; see Checking the spec. |
| `platforms/` | One folder per platform (`apple/`, `windows/`, later `android/`), each describing how that platform implements the spec: controls, layout, gestures, shortcuts, wording differences, "different by design" adaptations with reasons, source files and screenshots. `platforms/README.md` says what a platform folder contains and how to add one. Every platform folder has `README.md`, `platform.md` (the conventions every page follows), `index.md` (every screen and flow with its page and status) and one file per page in `screens/`, `flows/` and `messages.md`; every platform also has `commands.md` (one row for every command id of this folder's `commands.md`: where the platform places it and its shortcut). Screenshots live in `platforms/<platform>/screenshots/`. |

## Who owns what

Where two files cover the same behaviour, each has one scope and links to the other instead of repeating it:

| Topic | Owner | Linked from |
| --- | --- | --- |
| Saving that works; finishing a save before leaving, locking or quitting | `flows/save-entry.md` | `flows/save-failure.md` |
| A save that fails: alert, notice, Try Again, what is blocked, and writing paused while the library is replaced | `flows/save-failure.md` | `flows/save-entry.md` |
| Sync states, their messages, automatic sync pace and what stops it | `flows/sync-recovery.md` | `flows/reconnect-to-server.md` |
| Reconnect…, step by step | `flows/reconnect-to-server.md` | `flows/sync-recovery.md` |
| Where changes to review are signalled, the Changes to Review list, and the unsupported review form | `screens/conflict-review.md` | `screens/entry-conflict.md` |
| The entry and template review form | `screens/entry-conflict.md` | `screens/conflict-review.md` |
| What the device settles itself (journals, permanent deletions), the Changed on Two Devices list, and what each entry choice does | `flows/resolve-conflict.md` (the list itself: `screens/settings-sync.md`) | both screens |
| The lock screen | `screens/lock-screen.md` | everything else |
| Version history of entries and templates (journals have none) | `screens/version-history.md` | `screens/journals.md` |
| How a platform implements or presents a screen or flow (controls, shortcuts, wording differences, source files, screenshots) | `platforms/<platform>/` | the spec file's Platform notes |

## Writing a screen or flow file

Start with a front-matter block:

```yaml
---
id: settings-sync            # kebab-case, matches the file name
title: Settings ▸ Sync
features: [sync-connect, sync-now, stop-syncing]   # parity.yaml feature ids (messages.md has them too)
sources:                     # where the reference platform's implementation and decisions live
  - apps/apple/JournalApp/Views/SettingsView.swift
  - docs/design/client-only-mac-lists-markdown-2026-10-05.md
---
```

Then use these sections, in order. Leave a section out only when it doesn't apply.

1. **Purpose**: one or two sentences.
2. **Entry points**: how people get here.
3. **Content**: what is shown, in order, as neutral elements: "list of journals", "primary action", "secondary text", "destructive action". Name the copy key for every piece of text: `common.connectToServer`.
4. **Actions**: each action, what it does, when it is enabled, and what happens afterwards. Name the command id from `commands.md` (a table column headed `Command` may hold only command ids).
5. **States**: empty, loading, offline, error, locked, read-only, busy, and any others, each with its copy keys.
6. **Rules**: behaviour a client must keep, such as ordering, validation, limits, what is saved when, and what is never lost.
7. **Accessibility**: labels, announcements, focus order, text sizes, and reduced motion.
8. **Platform notes (Apple)**: where iPhone, iPad and Mac differ today, and why. The detailed Apple implementation notes belong in `platforms/apple/`; this section is the short neutral summary.
9. **Open questions**: a one-line pointer to `open-questions.md`, or "None". Put each new question in `open-questions.md` (section A, B, C or D) with the spec and code files involved, not in the screen or flow file. Don't silently "fix" the spec.

Describe behaviour as people see it, in neutral words:

- "Shows the journal's entries, newest first" is right; "a List with a ForEach" is not.
- "Destructive confirmation" is right; "an alert with role .destructive" is not.

## Copy keys

- **Key format:** keys are dotted, lowercase-first camelCase and stable: `<area>.<screen>.<element>`, for example `settings.sync.footer.notConnected`. Areas: `common`, `library`, `messages`, `settings`, `editor`.
- **Value:** the exact English text as shipped, including typographic quotes (’ “ ”) and the ellipsis character (…).
- **Placeholders:** use `{name}`, for example `"{count} images weren’t included…"`.
- **Plurals:** use `{"one": "…", "other": "…"}`.
- **Platform variants:** where the Apple app shows different text on iPhone and Mac, use `{"default": "…", "mac": "…"}`, and explain why in the screen file. Two more kinds of variant are proposed for the other platforms. A **casing variant**, `sentence`, holds the same wording in sentence case (`{"default": "Try Again", "sentence": "Try again"}`); Windows and Android share it, because both follow the sentence-case convention, so the list is stored once and is named for the casing, not for a platform. A **vocabulary variant**, `windows` or `android`, holds a platform's own words (Windows Hello for Face ID, “this PC” for “this Mac”), written in the casing that platform uses. A key can carry several (`{"default": …, "mac": …, "sentence": …, "windows": …}`); the most specific wins on a platform: its own variant, then `sentence` on a sentence-case platform, then `mac` on the Mac, then `default`. Variants other than `mac` are proposed in a mapping file's Copy differences section and recorded in `open-questions.md` first; none are in the catalog until the owner approves them (`platforms/windows/platform.md`, section 12).
- **One key per text and role:** before adding a key, search `copy/en.json` for the same text. A string used in more than one area, or on more than one screen in the same role (a button label, a title, a message), has one key, under `common.*` when it crosses areas (`common.cancel`, `common.restore`, `common.journalGone`). Reuse it rather than adding a second key.
- **Same text, different role:** an announcement, an undo step name, an accessibility label, a title and a button may share wording by coincidence and keep separate keys, because platforms word them differently. Each such group is listed in `copy/same-wording.json` with its reason; the checker warns about any other duplicate wording.
- **Different wording for one situation:** if two keys word the same situation differently, keep both and record it in `open-questions.md`, section B; don't pick one silently.
- **The catalog:** one JSON object, keys sorted. Each entry is `"key": {"text": "…", "context": "where and when it appears"}`. Plurals and variants put their object in `text`. Prefix references such as `messages.sync.action.*` in a spec file mean "all keys under this prefix".

## Command ids

Command ids are kebab-case (`new-entry`, `format-bold`, `delete-all-recently-deleted`) and defined once, in the first column of a table headed `id` in `commands.md`. A table in a screen or flow may have a `Command` column that names them; the checker rejects an unknown id. A row for several related ids lists them together (`undo`, `redo`); `format-*` and `window-*` stand for the groups named in their rows.

## Platform folders

A platform page (`platforms/<platform>/screens/<id>.md`, `flows/<id>.md` or `messages.md`) says how one platform presents a screen or flow. It never changes what the spec says: behaviour, states, rules and copy keys come from the spec file, and the page adds the platform's controls, layout, commands and shortcuts, copy differences, accessibility, the reasons for each place it differs, and, once implemented, the source files and screenshots. Windows calls its pages mapping files, Apple calls them implementation notes; the structure is the same. Start with `platforms/README.md`, then the platform's own `README.md` and `platform.md`: the Windows foundation is in `platforms/windows/`, and the Apple conventions are in `platforms/apple/`.

A Windows (or other non-Apple) page's front matter:

```yaml
---
id: settings-sync              # the spec page's id and this file's name
title: Settings ▸ Sync (Windows)
spec: screens/settings-sync.md # the spec page it maps, relative to spec/
features: [sync-connect, sync-now]   # parity.yaml ids, a subset of the spec page's features
status: draft                  # draft, reviewed or done
screenshots:                   # optional until implemented: files under screenshots/<device>/<id>-<state>.png
  - screenshots/desktop/settings-sync-connected.png
---
```

Required sections, in order: Controls, Layout (at each window width), Commands and shortcuts, Copy differences, Accessibility, Different by design, Open questions. After implementation, add Implementation (source files and notes a porter needs) and Screenshots. Apple's pages use the sections in `platforms/apple/README.md` (they add Source files and Screenshots, and replace Different by design with the differences between iPhone, iPad and Mac). A platform's `commands.md` has exactly one row for every command id defined here, and its `index.md` lists every screen, flow and `messages` page once. The checker enforces all of this, and that every screenshot a page lists exists and is named for its page.

## Feature ids

Feature ids are kebab-case (`export-markdown`, `app-lock`, `pin-entry`). Each one is defined once in `parity.yaml` and appears in the `features:` front matter of every screen or flow that specifies it.

`parity.yaml` holds one entry per feature:

```yaml
export-markdown:
  title: "Export as Markdown, the journals and images as Markdown files in a folder"
  specs: [screens/settings-backup.md, flows/export-markdown.md]
  reference: apple
  apple: shipped
  apple-notes: "Where iPhone, iPad and Mac differ."
  windows: planned
  android: planned
```

- `reference`: the platform that shipped the feature first (`apple`, `windows` or `android`); it is the working reference when another platform ports the feature. Every entry has one; today all are `apple`. A feature that originates on Windows or Android is added with that platform as `reference` and the status `planned` or `partial` until it ships. Changing `reference` is the owner's decision.
- Status per platform (`apple`, `windows`, `android`): `shipped`, `partial` (some of the feature exists; the notes say what is missing), `planned`, `different-by-design` or `not-applicable`. The last two need a `<platform>-reason`. `apple` covers iPhone, iPad and Mac; the notes say where they differ.
- A platform that doesn't have the feature yet starts as `planned`. Update the status in the same change that ships a feature on a platform.
- **Removed features:** Export Entry (`export-entry`) and Archive (`archive-entry`) were removed by owner decision. They stay in `parity.yaml`, marked `not-applicable` on every platform with the reason, so nobody rebuilds them; no screen or flow lists them.

## Checking the spec

Run the checker after every change to this folder:

```sh
python3 spec/tools/check-spec.py
```

It needs only Python 3 (PyYAML is used for a second opinion when installed). It exits with status 1 when it finds errors:

- `copy/en.json` doesn't parse, has duplicate or unsorted keys, or a malformed entry.
- A copy key named in any spec file doesn't exist (`messages.sync.action.*` counts when the prefix exists).
- A command id is defined twice, or a `Command` column or backticked kebab-case word names an id that doesn't exist.
- A feature id in a front matter isn't in `parity.yaml`, or `parity.yaml` breaks its structure.
- A relative link, a `screens/…` or `flows/…` path, or an anchor doesn't resolve.
- A screen or flow has no front matter or an `id` that differs from its file name.
- A `parity.yaml` entry has no valid `reference:` (apple, windows or android), or its reference platform is `not-applicable` on a feature that isn't removed.
- A platform page has a bad front matter (`id`, `title`, `spec`, `features`, `status`, and for Apple `devices`), lacks a required section, isn't in its platform's `index.md` with a matching status, or the platform's `commands.md` misses a command id, defines one twice or lets two app-wide or editor-wide shortcuts collide.
- A screenshot a platform page lists doesn't exist, isn't named `screenshots/<device>/<page id>-<state>.png`, uses a device the platform doesn't define, or is listed by two pages.
- A spec file contains a home path, an e-mail address or a personal name (this folder is public).

It prints warnings, which don't fail the run, for screenshots no page lists, copy keys no file references, duplicate wording `copy/same-wording.json` doesn't explain, features no screen lists, and `sources:` files that don't exist in the repository.
