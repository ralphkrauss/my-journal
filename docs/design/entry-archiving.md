# Entry archiving — proposal

Implements the user's requested reversible Archive action on entry context menus. This is separate from encrypted archive files and from Recently Deleted. Keep the familiar three-column Mac / stacked iOS navigation and quiet editor.

## Interaction and placement

Live, supported entries in a live journal offer “Archive Entry” in their context menu and Entry Actions menu, near Move Entry and above destructive Delete Entry. Archived entries offer “Unarchive Entry” in the same position. These reversible actions need no confirmation. Finish current saves, target the captured entry, update only its archive state, then refresh the relevant list. Archive removes the entry from the ordinary journal list without changing its date, title, body, journal membership or history. The editor returns to the existing empty state if the selected row leaves the current collection. No new persistent writing toolbar button.

Add “Archived” to the high-level Mac journal sidebar and iOS Journal selector, after journals/templates and before Recently Deleted. This collection contains archived entries from all supported live journals, grouped by month using the existing entry-list layout. Search in this collection searches its archived entries. Ordinary journal lists/search omit archived entries. Existing journal navigation remains unchanged. Empty state: “No Archived Entries”, secondary “Entries you archive appear here.” The search field says “Search Archived Entries”. Entry rows retain date/title previews; do not add badges to ordinary writing surfaces.

Archived entries remain editable and exportable, with the same native editor, formatting, links/images and version history. Moving an archived entry preserves its archived status and it stays accessible in Archived. Unarchive returns it to its original journal, selects that journal/entry, and clears collection/search navigation to make the result visible. If the journal is deleted, missing, unsupported or conflicted, existing Recently Deleted/Unavailable recovery takes precedence; no archive toggle is offered there.

Deleting an archived entry moves it to Recently Deleted using the same reversible deletion path. In Recently Deleted, a directly archived entry's Restore action is labeled “Restore and Unarchive”; it returns to the original live journal with archive state cleared. Restore and Move also clears archive state so the recovered entry appears in the explicitly chosen journal. Journal restoration preserves archived status of inherited children, since it restores the journal rather than individually recovering entries. Permanent deletion includes archived children in the same current-membership scope, and markers retain no archive state.

## Data and background behavior

Optional portable `archivedAt` is allowed only for entries. It syncs with the encrypted entry and survives backups, lossless archives/import, history and explicit conflict recovery. Older clients preserve unfamiliar fields as unsupported. Normal conflict rules retain concurrent content rather than choosing silently. The archive-state patch reads the latest supported record inside a transaction, validates expected archive state and availability/conflicts, preserves all unrelated newer fields, and queues sync through existing immutable outbox handling.

Explicit recovery from a permanent-deletion conflict (Keep Entry/Copy) clears archive state because the user chooses a destination and expects the recovered entry there. Historical copies likewise open as active entries; originals/historical versions retain their state. Templates cannot carry archive state. Scoped agent queries include archived entries in the granted journals and expose their archive status so agents do not silently lose historical context; existing scope, lock, unsupported and deleted boundaries remain.

## Failure, accessibility and verification

No routine save/sync toast. Local save failure retains draft/export escape path. Stale archive state or unavailable/conflicted target refuses the patch with a concise actionable message; refresh does not secretly retry it. After durable commit, reconcile retained draft before lock/quit flush; a refresh failure says “The entry was archived, but Journal couldn’t update the view. Reopen Journal to continue.” Use unarchived equivalent. Never tell the user to repeat a completed mutation.

Native system labels/icons, keyboard context menu and full wrapping text at accessibility sizes. Use archivebox for the collection/menu icon only where the existing sidebar/menu style already uses icons. All surfaces adapt to appearance/text size; no new custom palette or controls.

Verify useful real-store archive patch/content preservation, sync/conflict/retry and recovery semantics; native lock/save/selection boundaries; actual archive → collection → edit → unarchive → relaunch, and archived-entry deletion/recovery. Independent design review precedes implementation and actual normal/largest-text UI inspection follows it.

## Revision 2 — integration clarifications

Archived rows show the current journal name as secondary context (Untitled Journal fallback), also in their VoiceOver description. “Original journal” above means the current membership, including a move made while archived. Disable New Entry and creation options while Archived is selected; keyboard creation commands follow the same rule. The user chooses a journal through existing navigation before creating an entry.

Archiving a nonselected context-menu row preserves the existing editor/draft and collection. This action captures the target without selecting it first, settles the current draft, and patches only that target. Only a selected entry leaving the displayed collection clears its editor. Unarchiving from Archived deliberately opens the chosen entry in its current journal so its resulting location is clear.

Import preview counts remain disjoint: required “N entries in journals”, conditional “N in Archived” when nonzero, required “N in Recently Deleted”, and conditional “N in Unavailable”. Compute all counts from the same atomic lifecycle snapshot; deleted/unavailable parents take precedence over archive state. Histories/conflicts are not extra current entries.

When individually restoring an archived entry also requires restoring its deleted parent, keep the existing explicit parent-restoration confirmation and add “This entry will also be unarchived.” The final action is “Restore and Unarchive”. Only the selected entry clears archive state; inherited siblings retain their archive state while the parent is restored. Whole-journal Restore preserves every child's archive state. Restore and Move clears only the selected entry's archive state. Each operation revalidates its existing captured recovery scope, preserving unrelated content and sibling archive state.

Add “Archived entries are included.” to the agent grant/scope explanation. Archive status is organization, not access revocation; no new permission prompt is introduced. Use “This entry’s archive status changed. Review it before trying again.” for stale expected state, with existing accurate unavailable/conflict reasons for those cases.

## Revision 3 — concrete entry and parent recovery

Adopt the minimal refinement from the independent native integration review in `entry-archiving-review.md` without changing its scope or copy. Reuse JournalLifecycleView with a captured-entry mode titled “Restore Entry”, identifying entry title/date and parent name/count. Offer Restore and Unarchive… (or Restore…) only for an entry whose supported, conflict-free parent is deleted. Keep Restore and Move… as a separate individual recovery route. Use the exact parent-restoration explanation, selected-entry unarchive disclosure, final Restore/Restore and Unarchive labels and committed-refresh failure copy recorded in that review.

Prepare and validate one immutable recovery scope binding the captured entry identity, current parent and archive/deletion state, parent identity/state and current child membership. Restore parent and selected entry atomically while preserving all siblings and unrelated current content. Refuse changed scope and require fresh review if the parent was already restored. Do not compose two independent saves. Whole-journal restoration remains a distinct action preserving archive state. Cancel/lock guards, selected-entry export after save failure, Done after durable commit, and native accessibility behavior follow the reviewed refinement.

## Largest-text recovery notice refinement

Actual native screenshots show the inline recovery notice truncates both its explanation and the distinguishing words in Restore and Unarchive / Restore and Move. Preserve the same copy/actions and normal-size layout. At accessibility text sizes use a native vertical ScrollView containing the recovery notice, with fully wrapping text/button labels (`fixedSize(horizontal: false, vertical: true)`). Let it share available editor height with the existing flexible writing surface. Do not cap or shrink system text. Verify that the notice is independently scrollable, all recovery choices are fully readable/reachable, and writing remains available below. If intrinsic layout cannot reliably share space, use at most half the available editor height for the scrollable notice rather than a fixed point height. Independent review precedes implementation.

Independent refinement accepted: use an explicit maximum of half the editor content height (excluding toolbar). The notice keeps intrinsic height when it fits, otherwise scrolls vertically with native indicators. Keep leading alignment, full-width action label hit areas and natural accessibility order; supported retry/review/export content wraps too. Verify complete distinguishing action labels in scrolled screenshots. Ordinary sizes remain inline.

## Entry/parent recovery failure states

Independent source review approved these bounded refinements. Entry-specific unavailable preparation uses “This entry or journal is no longer available for restoration.” with Try Syncing Again when configured and archive export; retry refreshes/reprepares only. Unsupported preparation shows update guidance plus archive export, not repeated mutation attempts. Clear stale captured plans and parent display.

If the parent has already been restored, show the existing specific error and “Review Entry”, not Try Again for parent restoration. Review Entry settles saves, reads one fresh store snapshot, validates captured entry/store/lock/selection ownership, then selects that exact latest entry in its effective collection and dismisses the confirmation without a restoration mutation or whole-journal navigation. A vanished target gives truthful unavailable feedback and never selects a replacement. Refresh/read failure keeps visible error with Review Entry and Cancel available. Cancellation guards apply after awaits. These refinements require source re-review and useful failure verification.
