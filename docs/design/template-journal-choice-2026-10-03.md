# Choosing the journal for a new entry from the Templates list

Status: current, built 2026-10-03. Reviewed twice by an independent design agent; the outcome is recorded at the end.

Supersedes: the last bullet of default-journal.md's "Rule" (a template's menu "names and uses the Default Journal"), and the "Which journal" rule and the "New Entry in “‹Journal›”" copy of new-entry-template-suggestion.md, for templates started from the Templates list or File ▸ New Entry from Template… outside a journal. Those sections now point here.

## Request

Owner: "When you use a template from the Templates list, it should allow me to choose the journal where to use that template. Now it's defaulting to the default journal, which is pretty inconvenient."

## Every way to start an entry from a template today

| Place | Where the entry goes today | Changes? |
| --- | --- | --- |
| **Templates list:** a template row's context menu (long press on iPhone and iPad, right-click or Control-click on the Mac). Item "New Entry from Template", or "New Entry in “‹journal›”" when there are several journals. | The Default Journal (Settings), because no journal is shown in Templates (default-journal.md). | **Yes**: this is the request. |
| **An open template's Entry Actions:** the "…" in the iPhone and iPad editor, and Entry Actions in the Mac toolbar. The same item, from the same catalog. | The Default Journal. | **Yes**, the same as the row. |
| **"use a template" in an empty entry** (the body placeholder's link, and the Mac's "Use a Template…" popover). | The entry that is open, in its journal: the template fills its body. If the body stopped being empty before the choice (writing continued meanwhile), a new entry is created instead, where New Entry would put it: in All Entries that is the Default Journal, not the open entry's journal. | No. The entry already belongs to a journal. The rare fallback is noted as a known limit; it can file in the open entry's journal in a later fix. |
| **File ▸ New Entry from Template…** (Mac and iPad menu bar). A chooser sheet of templates. | The journal shown; elsewhere (Templates, All Entries, Recently Deleted, Unavailable Journals, nothing selected), the Default Journal, silently. | **Yes, outside a journal:** the sheet gets a Journal picker (below). Inside a journal, unchanged. |
| **New Entry** (⌘N) in a journal whose Default Template is set, or with a template selected on the Mac or iPad. | That journal; outside a journal the Default Journal with its Default Template, not the selected template. | No. It's New Entry's rule (default-journal.md). |

## Design

### The menu item

In a template's context menu and in its Entry Actions, the first item depends on the journals in use:

- **Two or more journals:** a submenu, **New Entry In**, with the symbol `square.and.pencil`. Its items are journal names. The suggested journal (below) comes first, then a separator, then every other journal in use in the order of the sidebar (the person's order, journal-order.md). This is the layout of Finder's "Open With" submenu: the likely choice first, the rest below.
- **One journal:** a plain item, **New Entry from Template**, which creates the entry in that journal, as today. A submenu with one choice would be a needless step.
- **No journal in use:** the plain item **New Entry from Template**, disabled. This is deliberate: the state is rare (every journal deleted), a template can only start an entry in a journal, and New Journal is in the toolbar and the File menu. New Entry, which opens New Journal in this state, is unchanged.

The item stays first in the menu, followed by the separator that's there today, as in the current catalog.

Names: a journal without a name is listed as "Untitled Journal". Names are not truncated in menus; the system wraps or truncates very long names as for any menu item. Two journals normally can't share a name (journal-name-uniqueness.md), but they can briefly after offline renames, so each item is identified by its journal's ID, never by its title.

The item is **hidden** for a template in Recently Deleted or in a format this version can't edit, and **disabled** while the template has changes to review, while saving is blocked (after a save failure), and while My Journal is locked or replacing its library, as today.

### The suggested journal

The first item of the submenu, in this order:

1. **The journal whose Default Template is this template.** If several journals use it, the first of them in the sidebar order.
2. Otherwise **the journal last opened** on this device, if it's in use: the journal relaunching would reopen (`lastJournalID`). In All Entries that is the open entry's journal; showing Templates or Recently Deleted doesn't change it. All Mac windows share it.
3. Otherwise **the Default Journal** (Settings ▸ Default Journal, or its fallback: the oldest journal in use).

The suggestion is only an order: nothing is preselected or checked, and choosing is one tap or click either way. There is no checkmark, because a checkmark in a menu means a current state (as in Default Template ▸), and nothing here is a state.

### Choosing a journal

- The entry is created in the chosen journal from the template as it is now (edits to an open template are saved first, as today). It always creates a new entry in the journal that was picked: it doesn't resolve New Entry's journal again, and it never fills an open empty entry.
- The app then shows the entry inside its journal, as New Entry from Template does today: the sidebar selects the journal, the list shows it, the entry opens with its title focused, and VoiceOver focus moves to the title. On iPhone the stack becomes the journal's entries and the entry, so Back leads to the journal the entry was filed in.
- The choice isn't remembered as a setting. Opening the new entry makes its journal the last opened one, so the next template without a Default Template suggests it first (rule 2). That gives "the journal I'm working in" without another setting.
- No confirmation, no message.

### Errors and changes while choosing

- **The chosen journal disappeared between opening the menu and choosing** (moved to Recently Deleted on another device, merged, made unavailable by a sync): nothing is created, and the error alert names it: **"“‹Journal›” is no longer available."** (as Merge Into… says it). The menu is rebuilt from the current journals the next time it opens.
- **The template disappeared or has changes to review:** the existing messages apply: "This template is no longer available." and "Review the changes to this template first."
- **Saving this entry fails:** the existing error alert, as for New Entry. (While saving is blocked from an earlier failure, the item is disabled, as listed above.)
- **Locked or replacing the library:** the item is disabled, as today.

### File ▸ New Entry from Template… outside a journal

The picker belongs to this command only (the sheet `templateChooserPresented` opens). The "use a template" chooser of an empty entry, as a sheet on iPhone and in compact width or as the Mac popover, never shows it: that chooser fills the open entry.

Opened from a journal, the chooser is unchanged: the entry goes to that journal. Opened anywhere else (Templates, All Entries, Recently Deleted, Unavailable Journals, nothing selected) with two or more journals in use, the sheet gains a **Journal** row at the top, so the person sees and can change where the entry goes before choosing a template:

- **Layout, both platforms:** a labelled row above the search field, pinned with it: "Journal" on the leading side and a menu picker showing the journal on the trailing side, like Settings ▸ Default Journal. On the Mac it reads "Journal:" with a pop-up button, as the Save panel's "Where:", above the search field with a divider; the sheet grows by one row.
- **Options:** journals in use in the sidebar order; "Untitled Journal" for one without a name.
- **Initial value:** the journal last opened on this device if it's in use, else the Default Journal: the owner's suggested order without its first step, since no template is chosen yet. It doesn't change as the highlight moves between templates.
- Choosing a template (click, Return, or tap) creates the entry in the picked journal. The picker doesn't close the sheet.
- **Filling in place:** if the open entry is this session's untouched new entry and it's in the picked journal, the template fills it, as today. Otherwise a new entry is created in the picked journal; the untouched entry is discarded on leaving, as today.
- **Where it shows:** as New Entry from Template, the new entry opens in its journal. From All Entries the list stays on All Entries, with the entry's journal label, as New Entry does there.
- **The picked journal disappears** while the sheet is open (a sync): the picker keeps it, so a quick Return can't misfile the entry. Choosing a template then creates nothing and the sheet shows **"“‹Journal›” is no longer available. Choose another journal."**, and only then the picker switches to the Default Journal.
- With one journal, or inside a journal, there is no picker. With no journal in use, the command is disabled, as today. The in-journal message when the shown journal goes away becomes **"This journal is no longer available. Close this and choose a journal."** (no "window": on iPad it's a sheet).
- **Keyboard:** the search field keeps the initial focus and Return creates from the highlighted template. Shift-Tab from the search field reaches the picker on iPad with a keyboard; on the Mac, Tab and Shift-Tab reach pop-up buttons only with Keyboard Navigation turned on in System Settings, as for any pop-up button. Order: picker, search field, list, Cancel.
- **VoiceOver:** "Journal, ‹name›, pop-up button" (Mac; the label has no colon for VoiceOver) or "Journal, ‹name›, button" (iPad).

## Copy

| Element | Copy |
| --- | --- |
| Submenu (two or more journals) | **New Entry In** |
| Submenu items | journal names; "Untitled Journal" for a journal without a name |
| Single item (one journal, or none) | **New Entry from Template** |
| Journal gone (alert) | **“‹Journal›” is no longer available.** |
| Picker in File ▸ New Entry from Template… outside a journal | **Journal** (Mac label "Journal:", VoiceOver "Journal") |
| Picked journal gone (inline, in the chooser) | **“‹Journal›” is no longer available. Choose another journal.** |
| Shown journal gone (inline, in the chooser) | **This journal is no longer available. Close this and choose a journal.** |

"New Entry In" ends with its preposition, capitalized as Apple capitalizes the last word of a title (Finder's "Open With"). The single item keeps today's label. The former "New Entry in “‹journal›”" label goes away.

## Accessibility

- Standard SwiftUI `Menu` in the context menu and an `NSMenu` submenu in the Mac toolbar (the shared `MenuAction` catalog). VoiceOver reads "New Entry In, menu"; each item reads its journal name. Full Keyboard Access and the Mac's keyboard menu navigation work as for any submenu.
- The separator after the suggested journal is a menu divider, which VoiceOver skips.
- Dynamic Type, Increase Contrast and Reduce Transparency come from the system menus.

## Platforms

- **iPhone:** long press on a template row, or "…" in an open template: the context menu shows **New Entry In ▸**; iOS 26 opens the submenu in place.
- **iPad:** the same, with a pointer too. In regular width the sidebar selects the journal afterwards.
- **Mac:** right-click or Control-click a template row, or Entry Actions in the toolbar with a template open.

## Tests

- **Model:** the suggestion order: a journal using the template as its Default Template wins over the last journal; without one, the last journal opened wins; without that, the Default Journal. With Templates shown and the Default Journal set to A, creating in B puts one entry in B with the template's text and shows B. A chosen journal that is no longer in use creates nothing and reports the error.
- **iOS UI, one journey:** on the Templates list, long press a template, choose New Entry In ▸ a journal other than the Default Journal; the new entry opens with the template's text, and Back leads to the chosen journal (iPhone). This replaces the assertion in `PreReleaseUITests.testNewEntryFromTheTemplatesScreen` that expected "New Entry from Template" with several journals.
- No tests for the menu's composition beyond that journey.

## Review outcome

An independent design agent reviewed the proposal twice, given the requirements and the proposal only.

**First review: approve with required changes.**
- File ▸ New Entry from Template… outside a journal still filed silently in the Default Journal, the owner's complaint by another route. Adopted: a Journal picker in that sheet.
- The proposal contradicted default-journal.md and new-entry-template-suggestion.md. Adopted: a Supersedes line; those sections point here.
- The no-journal state: kept disabled, recorded as deliberate.
- The "journal gone" alert now names the journal; "last opened" is defined; hidden and disabled states and focus after choosing are listed; menu items are identified by journal ID; the chosen-journal path never fills an open entry; the empty-entry fallback is described; a model test was added. The submenu was judged the right weight over a sheet.

**Second review, of the picker: approve with required changes; no further review needed with the layout adopted.**
- The picker belongs to the File menu command only, never to the "use a template" chooser.
- Fill-in-place applies only when the untouched entry is in the picked journal.
- A picked journal that disappears is kept and reported inline, not silently replaced.
- The picker is a labelled row at the top on both platforms (a bottom toolbar would hide its label and sit under the keyboard on iPad).
- The initial value is the last opened journal, else the Default Journal; All Entries stays in view; the Mac keyboard and VoiceOver details were corrected; "window" was removed from the iPad message.
