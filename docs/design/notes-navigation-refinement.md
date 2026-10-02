# Writing and navigation refinement

User feedback, 2026-09-20, supersedes the earlier two-pane macOS navigation proposal. References: user-supplied Apple Notes screenshots of the formatting popover, note context menu, and three-column window. These are visual references, not requests to duplicate every Notes feature.

## Layout

macOS uses a native three-column NavigationSplitView: journals/collections in the sidebar; entries in the content column; writing in the detail column. Only high-level navigation receives sidebar styling. The entry list uses an inset list and an ordinary content background, visually level with the editor. Use system separators, adaptive backgrounds and the native sidebar toggle; no custom floating cards. Default window approximately 1100 × 720, resizable, allowing the sidebar to collapse for writing. Retain the readable editor width.

Sidebar: Journals section with named journals, followed by Templates, Recently Deleted, and Unavailable Journals (only when populated or selected). New Journal and Manage Journals are navigation actions at the bottom. Highlight the active destination. Choosing one must preserve the existing pending-save protection. The content title is the selected journal or collection; search applies to it. iOS retains its compact navigation and journal selector in this pass.

Remove the always-visible date picker entirely. The entry date stays visible in the entry list. The editor begins with its title and writing surface.

## Formatting

Replace the text-only formatting dropdown with an Aa button opening a native popover. First row: visually bold B, italic I, underlined U, with accessible labels Bold, Italic, Underline. Below a divider, show Body, Heading and Subheading in representative type sizes/weights, then Bulleted List and Numbered List with familiar symbols. Link… below a divider. Only supported document styles are shown; no inert highlight, strike-through or other unimplemented options copied from the screenshot.

Formatting acts on the editor selection preserved before the popover opened; opening controls must not lose the range or format the title. Paragraph styles close the popover; inline styles can be applied consecutively. Keyboard equivalents remain in the macOS Format menu. Do not indicate selected formatting until it can be derived accurately from the native text selection, including mixed selections. Disable formatting when no editable body is available. Constrain width, allow scrolling at large text sizes, use semantic fonts, native focus, labels and adequate hit targets.

## Action placement

The content row owns its context menu, even when it is not the selected entry. Opening a menu does not change selection. Choosing an action first safely saves the current draft and selects the captured row ID; abort if saving fails, the target disappears, or the vault locks. Never accidentally act on another selected entry.

Ordinary entry menu, grouped by purpose:
- Change Date…; Move Entry…
- Save as Template…; Version History…; Export Entry…
- Delete Entry (destructive, moves to Recently Deleted)

Templates omit Change Date and Move; use Delete Template. Recovery entries offer Version History and Export, with restoration through the existing reviewed recovery flow. Unsupported records cannot be edited. Known conflicts keep their review notice and existing safety guards. No permanent-delete action until its storage/sync safeguards are complete.

Change Date opens a small sheet titled Change Date with a labeled Date picker and Cancel / Save. Edits stay local to the sheet until Save; Cancel has no effect. Capture entry identity and original date; if target/date changes externally, refuse stale submission with “This entry changed. Close this window and try again.” Preserve pending body changes, standard sync/conflict behavior, cancellation and lock protection. No date control remains in the editor header.

Editor toolbar: New Entry, Formatting, Insert Image, Entry Actions. Entry Actions mirrors the selected row's applicable actions and includes Image Descriptions when images exist. Separate creation options (New Blank Entry / New Entry from Template) from entry actions. Settings and Lock belong to app/global navigation, not the entry menu; preserve native macOS Settings and Lock menu commands and offer accessible global navigation controls on iOS. Sync status appears only when actionable.

Archiving is not currently a defined record lifecycle. Do not label Delete or encrypted archive export as Archive. Track the requested Archive action explicitly as follow-up requiring a reversible archive state, synced semantics, and a discoverable Archived collection; no dead placeholder menu item.

## States and verification

Retain existing empty/search/recovery/conflict/offline notices. Ordinary save and sync remain quiet. Menus must work via right-click, keyboard and VoiceOver, with iOS long-press plus the toolbar alternative. Dismiss sheets/popovers on lock or selection replacement. Test actual native layouts in light/dark and large text, plus targeted behaviors: non-selected row targeting, save failure preventing target switch, date cancel/save, selection-preserving formatting. Avoid snapshot composition tests or trivial menu-label tests. Inspect actual macOS rendering and iOS simulator UI after implementation, documenting any unavailable interactive desktop verification.

## Revision 2 — concrete placements and ownership

New Entry remains a single-click compose button. An adjacent chevron menu labeled New Entry Options contains New Blank Entry and New Entry from Template (submenu, disabled when no templates). These are creation controls at the leading edge of the editor toolbar on macOS. On iOS the entry-list toolbar contains New Entry and New Entry Options plus a Journal menu containing Settings… and Lock Journal. Detail has formatting, image insertion and Entry Actions; standard Back returns to the list and its global controls. No Settings/Lock duplication in the detail toolbar. Mac global actions remain in native app menus; New Journal… and Manage Journals… are final rows inside the scrolling sidebar, always reachable at short heights.

Export Entry for the already-selected draft bypasses save-first navigation: export retains the exact unsaved draft, including after a failed save. Actions on another row still stop on failed pending save. Read-only unsupported content permits history/export only. Templates omit Save as Template and use Delete Template.

Change Date captures identity/date after pending autosave settles. Save uses a transactional date-only patch of the latest eligible record, checks lifecycle/conflicts and expected date, and preserves unrelated title/body changes. Do not flush an outdated full-record snapshot over unseen store changes. Unsettled local edits block commit and remain available to retry/export. A stale date displays “This entry’s date changed. Close this sheet and try again.” Other unavailable/conflicted/unsupported cases use their contextual error. Disable Save/Cancel during the owned commit, reconcile durable changes before lock/refresh, retain input on failure, and dismiss on success (even if subsequent display refresh fails, report refresh failure separately). Cancel before commit has no mutation.

Formatting sessions capture exact body identity/range before presentation, remain bound through the Link prompt, and are invalidated on selection replacement/lock. Inline commands retain their updated selection/typing attributes. Paragraph selection/dismissal returns focus to the body. Compact iOS sheet adaptation includes Done; macOS Escape/outside click dismisses the native popover.

## Revision 3 — Change Date on iOS (owner decision, 1 October 2026)

Owner decision 3 in [owner-decisions-2026-10-01.md](owner-decisions-2026-10-01.md): on iOS the Change Date sheet puts Cancel and Save in the navigation bar, as iOS sheets do. It now matches Image Descriptions and Change Password: a navigation stack with the inline title Change Date, Cancel as the cancellation action and Save as the confirmation action. The Date picker sits in a grouped form section, and an error appears as that section's footer. The in-content title, divider and bottom button row are gone on iOS; the Mac sheet keeps them (bold title, Date picker, Cancel left and Save as the default button on the right). Copy, Escape/Return shortcuts, the labelled stacked picker at accessibility text sizes, disabling both buttons while saving, Save disabled after a failed draft save, swipe-to-dismiss blocked while saving, and dismissal on lock or selection change are unchanged. A new error is announced to VoiceOver on both platforms.

Independent review: approved with changes. Adopted: grouped form with the error as its footer; VoiceOver announcement of errors. Not adopted: a progress indicator in place of Save, because the commit is a brief local action already defined as needing no progress (pre-release-ui-2026-09-27.md); a graphical calendar and disabling Save until the date changes, which change behaviour beyond the owner decision and are left for the owner. The iOS UI test now finds the title, Cancel and Save inside the sheet's navigation bar.
