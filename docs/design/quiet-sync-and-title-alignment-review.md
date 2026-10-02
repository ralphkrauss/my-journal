# Review: quiet Sync Status and title alignment

Independent design review (2026-10-02) of the first draft of
[quiet-sync-and-title-alignment.md](quiet-sync-and-title-alignment.md). The reviewer had the owner's requests, the
owner's decision, the project's direction and the proposal; it read the code and built nothing.

**Verdict: approve with required changes.** The visibility rule, the exclamation mark only, the unchanged menu, Settings
as the place for pending state, aligning at the letter's origin and moving the title rather than the body were
accepted.

## Findings and outcome

| Finding | Severity | Outcome |
|---|---|---|
| On macOS 26 neighbouring toolbar items share a glass group; an empty place next to Editor Only could draw as an empty segment. Use one persistent item of the button's width, hide its contents, and verify; if a gap shows, move it outside the group | Must fix | Verified in the toolbar's view hierarchy: the first implementation's empty place was inside Editor Only's glass. Now the item is unbordered while empty (no glass), bordered while shown, and a fixed space keeps it out of Editor Only's group. Item positions are identical in both states (test) |
| Overflow behaviour unspecified | Must fix | The overflow menu item is hidden while empty and shows "Sync Status" with the submenu while shown; lowest visibility priority; the ~50 points of width it costs are accepted |
| Local-only people get a permanent gap | Should fix | The place exists only while the library syncs with a server |
| Possible flicker during Try Again; when is the 24 hours checked | Should fix | Stated: it changes only when a sync finishes; the long wait is checked after every sync, including retries and activation |
| A refused record's mark could stay forever | Should fix | Kept as an attention state: its message names the fix ("Edit it to try again."), and editing it clears the mark once it syncs |
| Long wait never fires when the connection never synced | Should fix | Measured from the first failure when there's no Last Synced; tested |
| "Locked app, no connection" merged two states | Should fix | Split: locked removes the toolbar; no server has no place |
| iPhone and iPad attention only inside the … menu | Consider | Unchanged; noted for the owner |
| Better native placement (sidebar, as Mail) | Consider | Not taken: it would vanish in editor-only mode |
| The Mac derivation relied on the text field's undocumented 2-point inset | Should fix | Measured: SwiftUI lays the field out by its alignment rect, which puts its text exactly at the layout edge, so no inset term is used. The regression test guards it |
| A literal 5 on iOS | Should fix | `EntryTextInset` is shared by the editor and the header, for the editable and read-only title |
| View Source missing | Should fix | Added to the rule and the Mac test |
| Notices now ~5 points off the text edge; check side bearings by eye | Consider | Stated in the rule; checked in screenshots |

Re-review: the revisions tighten the same approach rather than change it, so implementation went ahead; the actual
UI was then inspected (screenshots and the toolbar's view hierarchy).
