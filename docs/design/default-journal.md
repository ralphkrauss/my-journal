# Default Journal and New Entry outside a journal

Status: current, 2026-09-30. Implemented and checked on an iPhone 17 simulator; the Mac pane was not inspected on screen. Replaces the "oldest journal still in use" rule of feedback-stabilization-2026-09-23.md ("Default journal for New Entry") and the "Which journal" rule of new-entry-template-suggestion.md.

## Problem

Owner report: after deleting items in Recently Deleted on iPhone and swiping back to the Journals screen, New Entry was dimmed and did nothing until a journal was opened. Cause: the iPhone keeps the last collection (Recently Deleted) in the model after going back, and New Entry was disabled whenever Recently Deleted was the model's collection, even on the Journals screen. The Mac toolbar and File ▸ New Entry (⌘N) were disabled in Recently Deleted for the same reason.

Owner rule (verbatim in substance): "in the settings I can choose my default journal (by default that is Default) and if no journal is selected (this is also possible on the Mac) then that is where the entry gets created."

## Rule

- **A journal is shown** (its entries list is the current collection, `destination == .journal`): New Entry creates the entry there. Unchanged. The rule follows what is on screen, not the remembered `selectedJournalID`, which survives in Templates, Recently Deleted and on the iPhone Journals screen.
- **Anywhere else**: the Journals screen on iPhone, All Entries, Templates, Recently Deleted, Unavailable Journals, and no selection on the Mac or iPad: New Entry creates the entry in the **Default Journal**. The last journal shown before Templates or Recently Deleted no longer counts.
- New Entry is never disabled only because no journal is shown. It is still disabled while locked, while the library is being replaced, and while saving is blocked, as today. This covers every path: the iPhone Journals screen's and entries list's New Entry button, the Mac toolbar's New Entry, File ▸ New Entry (⌘N), New Blank Entry (⇧⌘N) and New Entry from Template…. All of them were disabled in Recently Deleted.
- The iPhone Journals screen's button already knows it is outside a journal (it always uses the Default Journal and opens it first). The model doesn't need to know that screen is showing.
- After creating, the app shows the entry inside its journal, as New Entry from Template does: the sidebar selects the journal, the list shows it, the title is focused. On iPhone the stack becomes [journal, entry], so Back shows where the entry was filed. From All Entries the entry stays in All Entries with its journal label (unchanged).
- New Entry from Template in a template's menu follows the same rule, so from Templates it names and uses the Default Journal ("New Entry in “‹Default Journal›”" when there are several journals).

## Setting

- **Place:** Settings ▸ General on the Mac, Settings ▸ Writing on iPhone and iPad, as a new first section above Format Markdown as You Type. Notes' Default Account and Reminders' Default List are the model.
- **Control:** a standard menu picker.
  - Label: **Default Journal** on iPhone and iPad; **Default journal** on the Mac, matching the sentence case of the pane's toggle.
  - Options: every journal in use (not in Recently Deleted, not unavailable), in sidebar order, by name; "Untitled Journal" for a journal without a name.
  - Footer: **Used for new entries you create outside a journal.**
- **Initial value:** nothing is stored until the person chooses. No stored choice means the oldest journal in use, which is the journal created with the library (normally "Default"). Existing configurations load unchanged (the field is optional).
- **Hidden** when there is no journal in use. With one journal it is shown with that one option, so the setting is discoverable.
- **If saving the choice fails:** the picker returns to the previous journal and an alert says "Couldn’t save the default journal."
- **Stored per device** in the local configuration (next to the last opened journal), not synced. The default is a device preference, like Notes' default account; syncing it would need a protocol change for a library-level setting, which isn't justified yet. A journal's own Default Template is a different setting and is unchanged.

## When the Default Journal goes away

- Moved to Recently Deleted, deleted permanently, removed by sync, or unavailable: New Entry uses the oldest journal still in use, and the picker shows that journal. The stored choice is kept, so restoring the journal makes it the default again (the same rule as a journal's Default Template in Recently Deleted).
- Choosing a journal in the picker replaces the stored choice. Known limit: while the fallback is shown, choosing that same journal changes nothing, so restoring the old journal later makes it the default again.
- **No journal in use at all:** New Entry opens New Journal, and the entry is created in the new journal (unchanged). The Settings section is hidden.

## Copy

- Picker label: "Default Journal"
- Footer: "Used for new entries you create outside a journal."
- Save failure alert: "Couldn’t save the default journal."
- No confirmation.

## Accessibility

- Standard `Picker` in a `Form`: VoiceOver reads "Default Journal, ‹name›, pop-up button" (Mac) or "Default Journal, ‹name›, button" (iOS menu); keyboard and Full Keyboard Access work as for any system picker. Long journal names truncate in the control and are full in the menu. Dynamic Type and Increase Contrast come from the system control.
- New Entry keeps its label and shortcut; it only changes from disabled to enabled in the states above.

## Tests

- **Model (isolated store):** with a chosen Default Journal and Recently Deleted shown after another journal was open, New Entry is allowed and creates in the Default Journal and shows that journal; with nothing selected (Mac) it also goes there; after the Default Journal is deleted, New Entry uses the oldest remaining journal, and restoring it makes it the default again.
- **iOS UI:** delete a journal, delete it permanently in Recently Deleted, go back to Journals: New Entry is enabled and opens a new entry. This is the owner's sequence; it failed before the fix.
- No test for the picker's composition.

## Open owner decision

Per device or synced: the owner said "in the settings I can choose my default journal". This design stores it per device, as Notes does with its default account. If the owner expects the choice to follow him to other devices, it needs a library-level synced setting (a protocol change).

## Review outcome

An independent design review approved this with required changes, all applied above: the rule follows the shown collection rather than `selectedJournalID`; every New Entry path is covered; footer copy changed from "New entries go here when no journal is selected." ("selected" doesn't fit the iPhone); Mac label in sentence case; save-failure behavior defined; per-device storage listed as an owner decision. Optional suggestions adopted: no stored value until chosen; optional field; the fallback edge case is accepted and documented.
