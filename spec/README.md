# Product specification

This folder describes what My Journal is today, independent of any platform: every screen, flow, state, message and command, with the exact copy. Each platform client implements it in its own native idiom: Apple today, and Windows and Android to come. `docs/design/` keeps the history and the reviews behind each decision; this folder holds only the outcome. When a design is approved, its outcome updates the spec in the same change.

The Apple app is the reference implementation. Where the spec and the Apple app disagree, one of them has a bug, and it gets fixed.

## Layout

| Path | Contents |
| --- | --- |
| `screens/<id>.md` | One file per screen, pane, sheet or window: purpose, content, actions, states, copy keys, accessibility. Neutral words only; no platform controls. |
| `flows/<id>.md` | Multi-step tasks with every branch, error and message, for example connecting to a server or adding a device. |
| `messages.md` | Messages that come from the model layer rather than one screen (sync states, save failures, conflicts, unavailable content): when each appears, where, and what the person can do. |
| `commands.md` | Every command (menu item, toolbar action, context-menu action, swipe action, keyboard shortcut), where it appears on each Apple platform, and when it is enabled. One section per area: menu bar, toolbars and context menus, editor, Settings. |
| `copy/en.json` | Every user-facing string, by key: one catalog for all areas. |
| `copy/same-wording.json` | The groups of keys that share one English text on purpose, and why. |
| `parity.yaml` | Each feature's status per platform, with links to its screens and flows. |
| `open-questions.md` | Every open question in the spec, in one place: likely app bugs, copy inconsistencies, design records lagging the code, and product questions for the owner. |
| `tools/check-spec.py` | The consistency checker; see Checking the spec. |
| `mappings/<platform>/` | How one platform presents the spec: controls, gestures, shortcuts, wording differences, and "different by design" adaptations with reasons. Apple is the reference implementation and has no mapping folder; `mappings/windows/` is the first (see Platform mappings below). Each platform folder has `README.md` (what a mapping file is), `platform.md` (the conventions every mapping follows), `commands.md` (every command id's placement and shortcut), `index.md` (every screen and flow with its mapping file and status) and one file per page in `screens/`, `flows/` and `messages.md`. |

## Who owns what

Where two files cover the same behaviour, each has one scope and links to the other instead of repeating it:

| Topic | Owner | Linked from |
| --- | --- | --- |
| Saving that works; finishing a save before leaving, locking or quitting | `flows/save-entry.md` | `flows/save-failure.md` |
| A save that fails: alert, notice, Try Again, what is blocked, and writing paused while the library is replaced | `flows/save-failure.md` | `flows/save-entry.md` |
| Sync states, their messages, automatic sync pace and what stops it | `flows/sync-recovery.md` | `flows/reconnect-to-server.md` |
| Set Up Server Again…, Connect Again…, Sign In…, step by step | `flows/reconnect-to-server.md` | `flows/sync-recovery.md` |
| Where changes to review are signalled, the Changes to Review list, and the journal, deletion and unsupported review forms | `screens/conflict-review.md` | `screens/entry-conflict.md` |
| The entry and template review form | `screens/entry-conflict.md` | `screens/conflict-review.md` |
| What each conflict choice does | `flows/resolve-conflict.md` | both screens |
| The lock screen | `screens/lock-screen.md` | everything else |
| Version history of entries and templates; of journals | `screens/version-history.md`; `screens/journal-history.md` | each other |
| How a platform presents a screen or flow (controls, shortcuts, wording differences) | `mappings/<platform>/` | the spec file's Platform notes |

## Writing a screen or flow file

Start with a front-matter block:

```yaml
---
id: settings-sync            # kebab-case, matches the file name
title: Settings ▸ Sync
features: [sync-connect, sync-now, stop-syncing]   # parity.yaml feature ids (messages.md has them too)
sources:                     # where the reference implementation and decisions live
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
8. **Platform notes (Apple)**: where iPhone, iPad and Mac differ today, and why. Platform mappings build on these notes.
9. **Open questions**: a one-line pointer to `open-questions.md`, or "None". Put each new question in `open-questions.md` (section A, B, C or D) with the spec and code files involved, not in the screen or flow file. Don't silently "fix" the spec.

Describe behaviour as people see it, in neutral words:

- "Shows the journal's entries, newest first" is right; "a List with a ForEach" is not.
- "Destructive confirmation" is right; "an alert with role .destructive" is not.

## Copy keys

- **Key format:** keys are dotted, lowercase-first camelCase and stable: `<area>.<screen>.<element>`, for example `settings.sync.footer.notConnected`. Areas: `common`, `library`, `messages`, `settings`, `editor`.
- **Value:** the exact English text as shipped, including typographic quotes (’ “ ”) and the ellipsis character (…).
- **Placeholders:** use `{name}`, for example `"{count} images weren’t included…"`.
- **Plurals:** use `{"one": "…", "other": "…"}`.
- **Platform variants:** where the Apple app shows different text on iPhone and Mac, use `{"default": "…", "mac": "…"}`, and explain why in the screen file. Two more kinds of variant are proposed for the other platforms. A **casing variant**, `sentence`, holds the same wording in sentence case (`{"default": "Try Again", "sentence": "Try again"}`); Windows and Android share it, because both follow the sentence-case convention, so the list is stored once and is named for the casing, not for a platform. A **vocabulary variant**, `windows` or `android`, holds a platform's own words (Windows Hello for Face ID, “this PC” for “this Mac”), written in the casing that platform uses. A key can carry several (`{"default": …, "mac": …, "sentence": …, "windows": …}`); the most specific wins on a platform: its own variant, then `sentence` on a sentence-case platform, then `mac` on the Mac, then `default`. Variants other than `mac` are proposed in a mapping file's Copy differences section and recorded in `open-questions.md` first; none are in the catalog until the owner approves them (`mappings/windows/platform.md`, section 12).
- **One key per text and role:** before adding a key, search `copy/en.json` for the same text. A string used in more than one area, or on more than one screen in the same role (a button label, a title, a message), has one key, under `common.*` when it crosses areas (`common.cancel`, `common.restore`, `common.journalGone`). Reuse it rather than adding a second key.
- **Same text, different role:** an announcement, an undo step name, an accessibility label, a title and a button may share wording by coincidence and keep separate keys, because platforms word them differently. Each such group is listed in `copy/same-wording.json` with its reason; the checker warns about any other duplicate wording.
- **Different wording for one situation:** if two keys word the same situation differently, keep both and record it in `open-questions.md`, section B; don't pick one silently.
- **The catalog:** one JSON object, keys sorted. Each entry is `"key": {"text": "…", "context": "where and when it appears"}`. Plurals and variants put their object in `text`. Prefix references such as `messages.sync.action.*` in a spec file mean "all keys under this prefix".

## Command ids

Command ids are kebab-case (`new-entry`, `format-bold`, `delete-all-recently-deleted`) and defined once, in the first column of a table headed `id` in `commands.md`. A table in a screen or flow may have a `Command` column that names them; the checker rejects an unknown id. A row for several related ids lists them together (`undo`, `redo`); `format-*` and `window-*` stand for the groups named in their rows.

## Platform mappings

A mapping file says how one platform presents a screen or flow. It never changes what the spec says: behaviour, states, rules and copy keys come from the spec file, and the mapping adds the platform's controls, layout at each window width, commands and shortcuts, copy differences, accessibility, and the reasons for each place it differs. The Windows foundation is in `mappings/windows/`: start with its `README.md`, then `platform.md`.

A mapping file's front matter:

```yaml
---
id: settings-sync              # the spec page's id and this file's name
title: Settings ▸ Sync (Windows)
spec: screens/settings-sync.md # the spec page it maps, relative to spec/
features: [sync-connect, sync-now]   # parity.yaml ids, a subset of the spec page's features
status: draft                  # draft, reviewed or done
---
```

Required sections, in order: Controls, Layout at each window width, Commands and shortcuts, Copy differences, Accessibility, Different by design, Open questions. A platform's `commands.md` has exactly one row for every command id defined here, and its `index.md` lists every screen, flow and `messages` page once. The checker enforces all of this.

## Feature ids

Feature ids are kebab-case (`export-markdown`, `app-lock`, `pin-entry`). Each one is defined once in `parity.yaml` and appears in the `features:` front matter of every screen or flow that specifies it.

`parity.yaml` holds one entry per feature:

```yaml
export-markdown:
  title: "Export as Markdown, the journals and images as Markdown files in a folder"
  specs: [screens/settings-backup.md, flows/export-markdown.md]
  apple: shipped
  apple-notes: "Where iPhone, iPad and Mac differ."
  windows: planned
  android: planned
```

- Status per platform (`apple`, `windows`, `android`): `shipped`, `partial` (some of the feature exists; the notes say what is missing), `planned`, `different-by-design` or `not-applicable`. The last two need a `<platform>-reason`. `apple` covers iPhone, iPad and Mac; the notes say where they differ.
- Windows and Android start as `planned`. Update the status in the same change that ships a feature on a platform.
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
- A platform mapping has a bad front matter (`id`, `title`, `spec`, `features`, `status`), lacks a required section, isn't in its platform's `index.md` with a matching status, or the platform's `commands.md` misses a command id, defines one twice or lets two app-wide or editor-wide shortcuts collide.
- A spec file contains a home path, an e-mail address or a personal name (this folder is public).

It prints warnings, which don't fail the run, for copy keys no file references, duplicate wording `copy/same-wording.json` doesn't explain, features no screen lists, and `sources:` files that don't exist in the repository.
