# Fewer lines in the Mac entries list

Status: reviewed 2026-10-04 (outcome below), built the same day. Mac only; iOS and iPadOS are unchanged. Only the entries list is in scope; other places with too many lines can be raised separately.

## Request

Owner, on build 14's Mac entries list: "We have way too many dividers in the app. There's probably a small improvement that we can do here: we don't show the divider at the last item of the list. Also, the 'Pinned' title is bugged because it seems to have the divider plus the line from the general layout. So we have two lines drawn on top of each other (on macOS). On iOS this is not a problem because we use a different design style."

## The list today (build 14, reproduced 2026-10-04)

The entries column is a SwiftUI `List` in the `.inset` style (RootView.swift), with one section per month and a Pinned section first. In Recently Deleted the sections are Journals, Templates and Entries ‹month›, below the Recently Deleted bar with Delete All….

Captured in light and dark from a team-signed scratch build (own bundle ID, scratch library):

- A line under every section header ("Pinned", "October 2026", "Journals"…).
- A line after the last row of every section, so two lines frame each header: one above it, from the previous section's last row, and one below it.
- At the top of the list, the Pinned header floats while the list scrolls. Its line is drawn across the whole column, right under the toolbar area, where it reads as a second line on the column's top edge.

## Design

As in Notes and Mail on macOS 26:

- **Between rows only.** Rows in a section are separated by the hairline separator they have today, starting at the row's text (unchanged). The last row of a section has no line below it, whether a section follows or the list ends.
- **Plain section headers.** "Pinned", the months, and Recently Deleted's Journals, Templates and Entries are secondary bold text, as today, with the system's spacing above them and no line below. The space before a header separates the sections.
- **Top edge.** The header's own line no longer doubles the line AppKit draws under a header floating at the top of the column, so one hairline remains there (see Implementation). The column keeps the window's existing top edge treatment (no titlebar separator; feedback-stabilization-2026-09-23.md).
- **Where:** every list the entries column shows on the Mac: a journal, All Entries, Templates, Recently Deleted (below its bar with Delete All…, which keeps its own layout), Unavailable Journals, and search results, which are the same list filtered.
- **Following changes:** which row is last is worked out from the list as it is drawn, so it follows pinning and unpinning, deleting and restoring, a date change that moves an entry to another month, sync, and search filtering.
- **The Recently Deleted bar** keeps its layout; no line of the list meets a line of the bar.
- **Selected rows:** the system's selection highlight and its hiding of separators beside the selected row are unchanged.
- **Unchanged:** selection highlight, row content and height, context menus, the sidebar and Settings, and every iOS and iPadOS list.

Copy: none changes.

## Accessibility

- Separators are decorative; VoiceOver reads the same rows and headers as before.
- With Increase Contrast, the remaining separators follow the system's stronger separator colour. Section grouping is still carried by the header text and the space above it, which don't depend on colour.
- Dynamic Type doesn't apply on the Mac; the list's text size setting is unchanged.

## States

Empty lists show the existing empty-state text (no separators to draw). A one-row section shows no lines at all. Search with no results is unchanged.

## Implementation

SwiftUI's list separator modifiers, on the Mac only (MacListSeparators.swift): `listRowSeparator(.hidden)` on each section header, and `listRowSeparator(.hidden, edges: .bottom)` on the last row of each section. Checked on macOS 26 in captures:

- `listSectionSeparator(.hidden)` has no effect in a Mac `.inset` list, so it isn't used. The line under a header is the header row's own separator, which `listRowSeparator(.hidden)` on the header view removes.
- The first section's header floats at the top of the column (also before scrolling), and AppKit draws a full-width hairline under a floating header. Before, the header's own line was drawn on top of it: the doubled line the owner saw. Now only AppKit's hairline is left. It goes away only if headers stop floating (`floatsGroupRows` on SwiftUI's private outline view, confirmed in a capture), which would mean reaching into SwiftUI's AppKit views, and headers would scroll away with their rows. A softer top scroll edge (`scrollEdgeEffectStyle(.soft, for: .top)`) doesn't remove it. **Decided (4 October 2026):** the hairline stays and headers keep floating.

## Tests

None: there is no behaviour beyond drawing. Verified with before and after captures of the top of the list (at rest and scrolled), a section change and the end of the list, in light and dark, on the Mac; after unpinning (which changes the last row of Pinned and of a month), with a search that leaves a one-row section, with a selected row, and in Recently Deleted; and a look at the iPhone list to confirm it is unchanged.

## Review outcome

An independent design agent approved with required changes, all adopted: the last-row rule follows list changes and is verified after unpinning and with a filtering search; the SwiftUI modifiers are checked on the Mac before relying on them; the Recently Deleted bar and selected rows are checked; the scope is stated. The reviewer also asked that the floating header stay opaque with Reduce Transparency; the floating header's background is the system's and isn't changed here, and the setting isn't switched on this shared Mac, so that remains to be seen by hand.

After implementation the top-edge rule was narrowed, as recorded under Implementation: the doubled line is gone, and AppKit's single hairline under a floating header remains, as decided on 4 October 2026.

