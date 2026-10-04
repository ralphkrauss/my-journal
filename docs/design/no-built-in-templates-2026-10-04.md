# New libraries start without templates

Status: current, built 2026-10-04. Reviewed by an independent design agent; revision 2 addresses the review, whose
outcome is recorded at the end. The owner confirmed keeping the templates existing libraries already have on 4 October
2026.

Amends: join-with-local-journals.md §2.3 rule 1 and §2.6 (built-in templates), sync-health-and-recovery.md §3.3 (built-ins
in a merge), and screens.md's list of built-ins.

## Request

Owner: "Can you also remove the default templates that are part of the build? By default there should be no system
templates, only templates created by the user."

## What changes

### Creating a library

Up to build 14, every new library got four templates: Daily Reflection, Gratitude, Workday Log and Weekly Reflection.
From now on a new library has one journal, "Default", and no templates, on the Mac, iPhone and iPad, whichever way
it's created: first launch, Start a Journal (with or without encryption), setting up a server, joining one, and a
library an archive is imported into. All of these go through one function (`NewVault.prepare`).

The only ways to get a template stay the same: **Save as Template…** in an entry's actions, and **Restore as New
Template** in a template's Version History.

### Libraries that already have the old templates

**Decision (confirmed by the owner on 4 October 2026): templates already in a library stay, including ones nobody edited.**
They're not deleted, hidden or marked. Once a library has them, they're the person's data: someone may use one as a journal's Default Template or
rely on it without ever editing it, and nothing tells an unedited template from a deliberately kept one. Removing them
would silently discard content, which AGENTS.md rules out.

To remove one: in Templates, choose **Delete Template** (context menu, Entry Actions, or Delete ⌫), then in Recently
Deleted choose **Delete Permanently…** for it, or **Delete All** to empty Recently Deleted. The same applies on every
device; deletions sync.

### Compatibility with libraries made by builds 12–14

The code that recognises the old templates (`BuiltInTemplates.shipped`, `isUnedited`) stays, pinned and append-only.
Only creating them goes.

- **Nothing written yet.** A library counts as untouched when connecting (no Merge step, "Your journals will download
  to this device.") if it has one journal named "Default", no entries, nothing in Recently Deleted, no change to
  review, and every template, if any, is an unedited old one. So both a fresh library from build 14 (four unedited
  templates) and a fresh library from this build (none) are untouched. This rule doesn't change; only the tests do.
- **Merging two libraries** (join-with-local-journals.md §2.3, rule 1, amended). Rule 1 assumed the server always had
  its own copy of each old template. It no longer may: a server set up by this build has none. New rule 1:

  > **Built-in and never edited, with no earlier versions or change awaiting review, and the server has a template of
  > that name:** not imported; it points at the server's template (the identical one, else the oldest of that name),
  > even when the server's copy was edited. **If the server has that name only in Recently Deleted,** it isn't
  > imported when a deleted copy there has the same text; otherwise it's imported into Recently Deleted, with the
  > server template's deletion date, so a deletion isn't undone and nothing is lost.

  An unedited old template whose name the server doesn't have at all now falls through to rule 5 and is **added**,
  like any other template. A journal whose Default Template it is follows it to its new identity, also into Recently
  Deleted, where New Entry starts blank and the Journals sheet shows "Unavailable Template", as for any deleted
  default template. So:

  | This device | Server | Result |
  | --- | --- | --- |
  | Old templates, unedited | Old templates, unedited | Each once (the server's) |
  | Old templates, unedited | None (set up by this build) | Each once (this device's, added) |
  | None | Old templates | Each once (the server's) |
  | None | None | None |
  | Old template, unedited | Same name, edited | The server's edited one; no review |
  | Old template, unedited | Same name and text, only in Recently Deleted | Still deleted; nothing added |
  | Old template, unedited | Same name, other text, only in Recently Deleted | Still deleted: the device's copy joins it there |
  | Two devices with old templates, one after the other | None | Each once: the first adds them, the second matches |

  Previously the second row dropped the device's templates on the Merge path; now they're kept.

  Known limits:

  - **Nothing written replaces.** A fresh library from build 14 (only the four unedited templates) joining a server
    set up by this build takes the replace path, as before: its four templates aren't kept. That's accepted: such a
    library has no entries and no Default Template set, so nothing depends on them, and its owner hasn't used them.
  - **Deleted permanently can't be matched.** A permanently deleted template keeps no name, so if the server's copies
    were deleted permanently (or with Delete All), a later merge of an older library with entries brings its unedited
    templates back as live templates. Nothing is lost; the person can delete them again.
  - **Older builds merging.** A device still on build 12–14 merging into a server set up by this build runs the old
    rule 1 and leaves out its unedited templates. Older builds can't change; TestFlight devices update.
- **The same library rejoining** keeps identities, as before; nothing is added twice.

### Templates screen with no templates

Today the empty Templates list shows only "No Templates". It gains one line that says how to make one:

```
            No Templates
 To create a template, open an entry and
       choose Save as Template.
```

- **Layout.** Centred in the list column (the Mac content column; the iPhone Templates screen; the iPad list), as the
  other empty lists are. Title as today (body font, secondary color). The second line is `.callout`,
  secondary color, centred, wrapping, with the column's standard horizontal padding (16 pt). No
  symbol, no button: there's no template to act on, and the command lives on entries.
- **Copy.** Title: **No Templates**. Description: **To create a template, open an entry and choose Save as
  Template.** ("Save as Template" without the ellipsis in running text, as the guide's sentence style.)
- **When it shows.** Only for Templates with an empty search. A search with no match keeps "No Results" and **Clear
  Search**. Recently Deleted, entries and Unavailable keep their own states.
- **Editor Only.** When the list is hidden (Mac View ▸ Show Editor Only) and Templates is empty, the detail column
  shows the same two lines, as it shows other empty states there.
- **Accessibility.** VoiceOver reads the title and the description as one element, as `ContentUnavailableView` does. Both scale with
  Dynamic Type (Mac text size and iOS Dynamic Type up to the accessibility sizes) and wrap rather than truncate. No
  color carries meaning; Increase Contrast uses the system's secondary color.
- **Loading / offline / errors.** None: the list is local. While the library is opening, the list shows nothing, as
  today (the empty state needs the library to be ready, as for other collections).

### The editor's "use a template" link and the chooser

Already conditional: the empty body shows "Start writing or [symbol] use a template" only while at least one editable
template exists, and "Start writing…" otherwise (`TemplateSuggestion.resolve`). No change; the chooser is never
offered empty. If the last template disappears while the chooser is open (deleted on another device), the chooser
shows "No Templates", as today.

### New Entry from Template

- **File ▸ New Entry from Template…** (Mac and iPad menu bar, iPad ⌘ overlay): already disabled when there are no
  templates. Stays in the menu, disabled, as macOS keeps unavailable commands visible.
- **New Entry In ▸ / New Entry from Template** in a template's menu: only exists on a template. No change.

### A journal's Default Template with no templates

Three places set it: the journal's context menu in the sidebar and the Mac toolbar's Journal Actions (submenu
**Default Template**), the iPhone and iPad Journal Actions menu (submenu), and the Journals sheet (picker **Default
Template**). With no templates, each would offer only "Blank Entry", already checked.

- **One rule for all three:** the menu or picker is **disabled** while there are no templates and the journal has no
  Default Template set. It stays visible: a command that can't do anything now is dimmed rather than removed, so
  the person still learns the setting exists. If the journal still refers to a template that's gone (in Recently
  Deleted), it stays enabled, so the person can choose Blank Entry (the picker shows "Unavailable Template" then, as
  today).
- No extra explanation: the Templates screen explains how to make one; a disabled control with a self-describing
  label needs no footer.
- VoiceOver reads the disabled submenu or picker as dimmed, with its current value for the picker.

## What doesn't change

- New Entry (⌘N) and New Blank Entry: without a Default Template both start an empty entry.
- Templates in Recently Deleted, Version History, archives, export, sync, agent access (agents never see templates).

## Updated elsewhere

- Probes (`scripts/test-sync-health.sh`): the "another library" row now merges a library with the old templates into
  one without them, and checks each old template once. The encrypted variant keeps two libraries with old templates.
- Measurement and screenshot libraries create their templates explicitly as the person's own.
- UI tests that used the old templates create a template in their own setup.
- The guide, App Store listing and age-rating notes, screens.md, join-with-local-journals.md and
  sync-health-and-recovery.md no longer say templates are included or always skipped.
- **Not changed:** the chooser emptied while it's open (the last template deleted on another device) keeps showing
  "No Templates"; it's rare and the chooser belongs to the template sheet being changed separately. There's no New
  Template command; making a template from scratch could be a later owner decision.

## Review

**Revision 1: approved with required changes** (independent design agent, 2026-10-04). Applied in revision 2:

1. Rule 1 brought back templates the person deleted on the server: an unedited built-in whose name the server has
   only in Recently Deleted is now imported into Recently Deleted. Permanently deleted names can't be matched; listed
   as a known limit.
2. A fresh build-14 library joining a server from this build takes the replace path and its templates aren't kept:
   stated and accepted explicitly.
3. Keeping existing built-ins is an interpretation: marked as needing the owner's confirmation.

Suggestions applied: the mixed-version limit and the sequential-merge row (with a test), a better reason for dimming
than Open Recent, one enable rule for the menus and the picker, VoiceOver reading the empty state as one element, and
the extra docs. Suggestions not applied: the copy alternative "…in an entry's actions" (the reviewer found either
fine; "open an entry" names the place for someone who hasn't used the actions menu yet), and changing the emptied
chooser (see above).

**Revision 2: approved** (re-review, 2026-10-04). Its suggestions were applied: a built-in whose server copy in
Recently Deleted has the same text isn't added a second time, the Default Template following a built-in into Recently
Deleted is noted, and the sequential-merge test covers the Recently Deleted cases.

## Owner decisions (4 October 2026)

The owner accepted both recommendations:
- Templates already in a library stay, including unedited built-ins. The owner removes them by hand if they want to.
- The new merge rule stands. A device's unedited built-in is added when the server has no template of that name,
  skipped when the server has one, and goes into Recently Deleted when the server's copy is there.
