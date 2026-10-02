# Independent Notes alignment audit — 2026-09-22

## Scope and verdict

Reviewed all four user-supplied Notes photos, current navigation, editing, setup, template, sidebar, and Settings source, and the retained iPhone/iPad final captures and Mac offscreen renders reviewed on September 21. This is an independent audit, not approval of a new implementation proposal. No builds, simulator changes, live Mac operations, or implementation edits were performed. Previous acceptance was explicitly bounded to the earlier design; it does not establish compliance with these new requirements.

The current phone and tablet experience needs a structural revision. Native-looking controls alone do not reproduce the requested navigation or writing behavior. The strongest existing pieces to retain are quiet autosave, an uncluttered writing surface, unified title/body scrolling on iOS, explicit plaintext disclosure, scoped agent permission controls, and preservation of document history. macOS should receive targeted changes rather than the phone layout.

Evidence: Notes photo 1 shows a collection screen with counts, disclosure rows, bottom search and compose; photo 2 shows a separate titled entries screen with dense grouped rows and the same bottom actions; photo 3 shows reading with entry actions separated from writing controls; photo 4 shows an active editor with a top checkmark and formatting immediately above the keyboard. The photos are iPhone references, not evidence of a particular iPad arrangement. Their yellow accent, cloud account grouping, scanning/drawing features, and exact glass rendering are not requirements to copy. The user's explicit date-first row request takes precedence over the title-first Notes example.

## Material findings and required interaction outcomes

### P1 — Phone hierarchy is missing

`RootView.swift:151` uses a two-column iOS split with the entry list as the first column. Its journal selector (`:184`) combines journals, creation, management, templates, archive, deletion, and unavailable content in one menu. There is no separate Journals root and no All Entries destination in `JournalSidebarView.swift`. This prevents the requested Journals → Entries → Entry progression and makes scope difficult to inspect.

Use a native phone navigation stack: **Journals** root → selected journal or **All Entries** list → entry. Tapping a journal pushes its entries, tapping a row pushes the editor, and native Back/swipe-back returns one level while retaining query, list position, and selection. Journals should expose counts and full-row disclosure targets. Put infrequent management in appropriate menus or Edit state; do not make a journal selector menu substitute for the root screen. Preserve Templates, Archived, Recently Deleted, and unavailable recovery as explicit reachable collections. Do not silently change a failed-to-save draft when navigating.

### P1 — Writing actions are detached from the keyboard and Done is absent

`RootView.swift:568` keeps Formatting and Insert Image in the top detail toolbar on iOS. `JournalWritingView.swift` manages scrolling but has no keyboard accessory configuration. Retained screenshots show the body keyboard with no writing accessory and no top Done checkmark. This materially differs from the supplied editing reference.

While title or body editing is active, show a top trailing checkmark with accessible label **Done**. It ends editing and dismisses the keyboard; it neither closes the entry nor suggests that saving occurs only on Done. Show a native keyboard-adjacent accessory with Formatting, Checklist, Table, and Attachment routes that are actually supported. Do not add inert drawing/scanning controls. Capture the body selection before presenting formatting or attachment UI, restore the correct entry/selection on return, and never focus an old entry after Back, lock, or selection change. Title focus must not apply paragraph formatting to the title. Reading and editing need explicit, coherent action placements; controls must remain reachable with a hardware keyboard and floating iPad keyboard. Preserve native selection, spelling, autocorrection, undo, and IME composition.

### P1 — Forced Markdown source mode contradicts the revised product requirement

`RootView.swift:456` explains forced source mode; `MarkdownEditing.swift:43` refuses a return to formatted presentation for documents requiring source. Native editor initialization also selects that mode. The prior source-only fallback was deliberately approved under an older scope. It is now insufficient.

A full formatted CommonMark/GFM experience needs explicit native behavior for nested lists/quotes, task states, fenced and indented code, tables, links/reference links, strikethrough, rules, images, and escaped text. The nested list in Notes photo 3 is a concrete acceptance case. Inserting a table or code block must keep the entry formatted. Define table cell selection/editing, row/column controls, keyboard traversal, narrow-width overflow, and accessible reading order; define list indentation/outdent, Return continuation/exit, and task toggling. Merely rendering the syntax or wrapping a read-only preview around a source editor does not meet an editable formatted-writing claim.

Keep optional Markdown source under an explicit command, preserving canonical content and a coherent undo chain. Raw HTML must remain inert and preserved; supporting formatted Markdown does not authorize script execution or silent remote media fetching. Define safe visible representation for unsupported HTML rather than forcing the entire document into source. A parser/renderer redesign must retain unchanged source, attachment identity, conflicts, history, and failed-save recovery. The later proposal needs an exact capability matrix and meaningful round-trip/edit/undo checks before implementation approval.

### P1 — All Entries needs real scope and creation rules

Current entry rows (`RootView.swift:316`) show journal names only in Archived. Sidebar destinations do not include All Entries. Adding only a visual All Entries label would leave filtering, search, badges, and compose ambiguous.

All Entries should aggregate live, unarchived entries from live journals, with an explicit policy for any different scope. Each row needs a readable journal badge/name, including search results. Do not use color as the only journal identity. Search from Journals should span that intended global scope; search within a journal should remain scoped and identify it. Compose in All Entries/Journals must use a clearly defined destination, not a hidden stale selected-journal value. The proposal should choose a visible destination picker or a clearly disclosed remembered destination and handle deletion/conflicts before creation.

### P2 — Rows are too tall and metadata is poorly prioritized

`entryRow` uses a minimum height of 82 points plus vertical padding, separate date/title, and two preview lines; retained Mac renders make the resulting sparse list particularly clear. This prevents the requested compact date-first scan.

Use localized date as the leading information, a one-line title, and a restrained preview; All Entries adds a compact journal label. Avoid an empty preview reserving space. At normal text, dense rows should permit useful scanning; at larger text, grow naturally instead of fixing height or truncating all identifying information. Keep conflict status distinct and accessible. Preview text must describe formatted content, not expose Markdown delimiters. Group headings must not repeat date information unnecessarily.

### P2 — iPad currently enlarges the phone's journal-menu model

The regular-width screenshot has entries/editor and the same journal menu rather than the requested adaptive collection hierarchy. Use a native collapsible Journals sidebar, entries column, and writing detail when space permits; prioritize entries + editor at intermediate widths and the same push hierarchy as phone at compact widths. Base behavior on available size, not device name or orientation. Preserve the active entry, draft, focus, and list scope through resizing. Never leave the writer permanently squeezed by three columns. Popovers need correct anchors; compact presentations need sheets. Inspect portrait, landscape, narrow multitasking, keyboard-visible, and large-text states after implementation.

### P2 — Search and compose placement does not express the requested Notes pattern

`listToolbar` puts creation, templates, and Settings together at the top, while `.searchable` uses automatic placement. Place Search and a distinct compose control in a native bottom toolbar on the phone's Journals and Entries screens. Ensure list content scrolls clear of it. Use system toolbar/search APIs appropriate to the deployment OS rather than reproducing glass with custom overlays. Define Search focus, cancel, empty results (**No Results** / **Clear Search**), and retained query on Back. Templates should be a secondary creation route rather than another equally prominent top-level compose icon.

### P2 — Setup and templates need a simpler, precise journey

Welcome already offers local creation and later sync; keep that useful separation. `CreateJournalView` has a sound explicit encryption choice and warning, but terminology alternates between journal, library, and product. Define the minimum local setup sequence and exact title/action copy; avoid adding server, agent, template, or recovery configuration to ordinary first writing. Retain a single secure password field and password-manager support when encryption is chosen, and genuinely passwordless continuation otherwise. Creation failure must remain in context with retry and must not expose a half-created library.

The native name-only template picker is a useful foundation. Simplification should preserve template identity and clear destination, search, Cancel, and the appropriate creation action. No prose previews or default-heading clutter. Duplicate-name UUID suffixes in `TemplateChooserView` are technically unique but not meaningful names; the proposal should choose concise human-readable disambiguation. Retain unavailable-template recovery and guard against a destination changing while the picker is open. Mac combo-box keyboard acceptance still requires live verification.

### P2 — Agent controls are buried in Privacy

`SettingsView` places agent grants and recent activity after app lock and archives in Privacy; iOS adds a Mac-only explanatory section there. Give **Agent Access** its own Settings destination on Mac and a separate explanatory destination on iOS if unsupported there. Keep Privacy focused on encryption, lock, and recovery/backup organization. Preserve explicit journal scope, read-only status, visible revocation, and consequences of prior reads. Moving the UI must not broaden authorization. Settings navigation and empty/error states should remain native and concise.

## Targeted macOS corrections

Retain the native three-column structure and collapsible sidebar; do not transplant the phone's bottom bars. Add All Entries and compact date-first rows with journal identification. Keep creation controls with the entries column and formatting with the editor, with clear native overflow at narrow widths. Source places the Mac title in a fixed 32-point field (`RootView.swift:449`); inspect long titles and configured text sizes, and avoid clipping or a detached oversized title area. Keep direct Settings access and Cmd-comma consistent. Move Agent Access to its own Settings pane. Formatting submenus need discoverable native submenu affordances. Template selection, full-row pointer targets, keyboard focus, and window chrome require live inspection: the retained offscreen navigation image has a blank sidebar and absent toolbar, so it cannot verify those behaviors. No claim that these omitted render regions prove a live defect is made.

## Acceptance gate for the forthcoming proposal

Specify exact normal/empty/loading/offline/save-failure/conflict states, action labels, navigation and editing focus, All Entries scope/destination, and the rich editing matrix. Preserve quiet successful local saving and syncing. An offline banner must not dominate writing merely because no server exists. Actionable failures should retain the draft and offer retry/export without mislabeling local saving as completed sync.

Require 44-point touch targets, labeled icon controls, Dynamic Type, VoiceOver order and selection announcements, sufficient contrast, Reduce Motion/Transparency, native keyboard navigation, and no color-only state. Inspect actual phone/tablet UI with keyboard, long titles, many journals, empty lists, cross-journal search, and largest supported text; inspect live Mac windows separately. Behavioral tests should focus on save/navigation preservation, scope correctness, formatting selection/undo, lossless rich editing, and accessibility-relevant failure states rather than routine view composition.

No revised implementation design is approved by this audit. The author should provide the concrete proposal for independent review before frontend implementation.

## Actual iPhone implementation review — 22 September 2026

Independently inspected all eight PNG captures in `artifacts/notes-navigation-iphone-picker-evidence/manifest.json` and its issue-description text. The parent reports the workflow passing through passwordless creation, navigation, template activation, writing, Done, Settings, and retained content after relaunch. This review did not rerun the test; screenshots establish the visible states, not every behavior. Structured-table work is still pending and is not assessed as complete.

**Disposition: materially improved hierarchy and picker, but actual-UI acceptance remains open for the toolbar and scope-label defects below.**

### P1 — Duplicate bottom toolbar after Done

`3D5C779B-593E-4B05-BC8E-664B50D768D7.png` shows two complete, identical stacked sets of Formatting/Image/Source and Compose/Templates at the bottom after keyboard dismissal. This is a visible ownership/lifecycle defect, not the intended editing-versus-reading distinction. Keep exactly one reading toolbar after Done, one accessory while the software keyboard is active, and the defined single fallback with hardware/floating keyboard. Recheck repeated editing/Done, presentation dismissal, and Back; fixing only the initial state is insufficient.

The manifest's issue attachment reports: “Adding 'UIKitToolbar' as a subview of UIHostingController.view is not supported and may result in a broken view hierarchy.” This is a runtime hierarchy diagnostic, not proof of a failed test assertion and not independent proof of the duplicate's cause. Nevertheless it needs resolving while correcting toolbar ownership; avoid layering a manually hosted toolbar on top of SwiftUI's own toolbar container.

### P2 — All Entries falsely labels search as Default

`D268A70D-DE36-4272-814A-6DF67273B779.png` has the large All Entries title and a Default journal label on the row, but its search field says **Search Default**. Correct the placeholder to **Search All Entries** and verify actual results use global scope across at least two journals. A single-journal fixture cannot establish this. Keep current collection scope independent of the remembered creation destination.

### P2 — Bottom action order and missing upper actions deviate from the proposal

Journals (`1423DB95-4AB6-4C35-BD45-BED8FB30AA36.png`) places compose and templates before search inside a shared bottom pill, while Entries (`98C34359-FDF3-4CC3-A40E-39651FEDC8E2.png`) has search followed by a compose/templates group with templates outermost. Keep search leading and the primary compose action trailing consistently; templates is secondary. The system's native materials are appropriate, but differing ownership/order is not the requested Notes pattern.

The Default entries screenshot has no top journal More action. The entry screenshots have More (and Done while editing) but no Share/export action. Restore those approved routes rather than relying only on a hidden long-press or a different screen. The accessory shows Formatting, Checklist, Table, Image and Source; Undo/Redo and the planned Insert link route are not visible. If these are still pending, keep them on the completion list; if available by an overflow/menu, show that discoverable route in subsequent evidence. No requirement to add unsupported Notes drawing/scanning buttons.

### P2 — Remaining density and Settings cleanup

The All Entries row uses four separate lines (date, journal, title, preview). It is readable but still unnecessarily tall for a compact list; combine date and journal metadata on one line where space permits, allowing natural expansion for large text. The Default journal root row has no count, including zero; show the approved live-entry count consistently. The peer Agent Access Settings row is present and fits correctly, but Journals remains as a redundant Settings route despite the approved removal. Remove it only after the journal More/context management actions are available.

### Accepted bounded observations

The separate Journals, Default entries, and entry screens now read as a native hierarchy. The template picker (`4F468284-012C-4ADE-A3FC-8D2B16E07DD7.png`) is an appropriate compact sheet with focused search, a visible Close icon, name-only choices, and all four results reachable above the keyboard. It avoids the previous heading/preview/Create clutter. Its row spacing could be tighter, but no clipping or material layout problem is evident. Immediate activation, keyboard result navigation, VoiceOver, no-results/retry states, and outside/Escape behavior need behavioral evidence rather than inference from this image.

The keyboard-visible editor has a top Done checkmark and writing actions next to the keyboard; Done's captured result has no keyboard. The fixture inserts its text at the start of an existing template heading, so the bold “A useful note. What I worked on” is not sufficient evidence of an unintended formatting bug. Use an ordinary paragraph fixture as well when validating body typing. The setup sheet has clear hierarchy, complete stored-encryption explanation, distinct actions, and a complete plaintext warning without gray form boxes. This normal-text/light setup capture is visually accepted. Agent Access is visibly a peer Settings section.

No largest-text/dark, multi-journal global scope, hardware/floating keyboard, iPad, failure-safe Back, or final Mac interaction acceptance is implied by this screenshot review. No implementation or builds were performed.

## iPad source and actual-capture review — 22 September 2026

Read current RootView, CompactJournalNavigation, JournalSidebarView, TemplateChooserView, TemplateSearchField, EntryCreationActions, and JournalSearchResults. Independently inspected Journals, Template picker, Editing above keyboard, Reading after Done, and All Entries after relaunch in `artifacts/notes-ipad-resumed-evidence/manifest.json`. The parent reports this workflow passing; no execution was repeated by this reviewer. Scope is normal-text/light portrait iPad plus source inspection, not large text, multitasking, landscape, or VoiceOver acceptance.

### Confirmed visible improvements

The iPad reading capture now has one bottom action group in the entries column and one in detail, rather than duplicate stacked controls. Templates precedes trailing Compose. Share and entry More are in the detail toolbar; journal More is above its list. Editing shows Done and a full accessory including Formatting, Checklist, Table, Insert, Undo, Redo, and Source. All Entries has the correct search label and compact date/journal metadata on one line; journal counts are visible in the sidebar. These close the corresponding visible defects for this captured iPad state, not automatically for every phone/resize state. The source likewise includes corrected global placeholder, Share, journal More, counts, and compact metadata.

### P2 — Template density and adaptation

The iPad picker is bounded and searchable, but each name occupies substantially more space than its 44-point target requires. The fourth result sits against the bottom curved edge while default list top/row spacing consumes the available height. Use a plain native list with approximately 44–48-point normal-text rows, minimal extra vertical row inset, and no grouped-list top margin; permit wrapped names and Dynamic Type to increase height naturally. Keep a bounded scrollable popover rather than enlarging it merely to accommodate padding. Four ordinary names should fit comfortably below the search row.

Source currently forces a 320-by-360 frame on every iPad via device idiom, even when the hosting window is compact. Size by the presentation context instead: fixed bounded dimensions only for a regular anchored popover, flexible sheet content in compact windows. The root's alternate template sheet route must obey the same policy. The current screenshot includes Close although the picker is visually a regular popover, consistent with an incorrect inherited size-class decision; passing explicit presentation context from the owning root addresses that ambiguity.

### P2 — Resize must preserve route intent, not reopen stale selection

The current horizontal-size-class handler always sets compact navigation to entries/selected entry. Returning to Journals does not necessarily clear model.selectedID; therefore resizing can reopen an entry the person deliberately left. Preserve the semantic visible route (Journals, entries, or editor) independently of persisted selection. Update that intent on regular-width navigation as well: restoring an old compact entry path after choosing another regular-width entry would create the inverse stale-route bug. Stable IDs must be reconciled with current live/recovery state without dropping a failed draft.

`openRegularCollection` also unconditionally changes visibility to doubleColumn. This hides the Journals sidebar even in a roomy user-expanded layout. Retain explicit user visibility and allow the native balanced split to adapt to available width. Portrait overlay dismissal is appropriate, but must not become an unconditional landscape sidebar collapse.

### P2 — Keyboard and popover ownership need the actual window/control

Docked-keyboard detection uses screen bounds and the first foreground scene. That can misclassify Stage Manager/Split View keyboards and show both accessory/fallback controls or hide the required fallback. Convert keyboard geometry into the owning app window's coordinates and compare against that window, not a different foreground scene or the full display. Preserve the hardware/floating fallback and Done independently of keyboard height.

Formatting's regular-width popover is attached to the root Group, not its invoking Aa control. Anchor a toolbar invocation to that button and a native accessory invocation to its actual view/rect; compact remains an adaptive sheet. Root-sized anchoring is not established as correct by the provided captures, which do not show formatting open.

### P2 — Template keyboard selection lacks an accessible selected state

The current selected template row is expressed solely by accent background. Add selected accessibility state and ensure arrow navigation exposes the active result while search remains focused; the visual highlight is not sufficient VoiceOver feedback. Search autofocus is implemented once on window attachment and guards marked-text arrow handling, which is appropriate. Source review does not establish Escape dismissal on every presentation; retain that behavioral check.

### Other concrete route-state cleanup

New Journal Cancel does not reset `createAfterJournal`. Cancelling a no-journal Compose route can therefore leave a later ordinary New Journal action creating an unintended entry. Clear the pending creation intent on cancellation/dismissal as well as success. Root global search opens a result through `openEntry` without first establishing an All Entries route/scope; Back currently constructs an entries route using the old collection. Define and retain a coherent return to the search results or global entries, rather than an unrelated selected journal. These are interaction defects inferred from current source and require focused reproduction, not claims of observed data loss.

### Review of proposed corrections

Approved within the existing design: native balanced split with preserved visibility, route-intent retention across size changes, owning-window keyboard geometry, control-anchored formatting, context-driven template sizing, plain compact template rows, and explicit selected accessibility state. Do not replace these with arbitrary device/orientation thresholds or a frozen old compact path. macOS scope remains confined to anchoring its Aa popover to the real button and the previously approved targeted corrections; no new desktop redesign is requested. Actual follow-up should cover the affected popover, compact/regular round trip, and keyboard states. No implementation or builds were performed by this reviewer.

## iPhone toolbar-visibility and formatting follow-up — 22 September 2026

Independently inspected Reading after Done, Formatting choices, Editing above keyboard, and Template picker PNGs from `artifacts/notes-iphone-table-flow-evidence/manifest.json`, plus the two issue-description attachments. No tests or UI actions were rerun.

**The toolbar artifact remains open.** `B46D5817-F3C8-479B-AF86-6472CCF24A74.png` visibly shows an empty glass capsule immediately above the populated reading toolbar after Done. The earlier duplicate controls are gone, but an orphaned toolbar surface still occupies an extra row. This supplied run therefore does not substantiate a completed fix, despite the reported stable-content/visibility implementation change. Keep only one reading toolbar surface and recheck repeated editing/Done and formatting-sheet dismissal. The issue attachment still records the unsupported UIKitToolbar-as-UIHostingController-subview diagnostic; its cause remains for implementation investigation.

The formatting capture (`E1B753AF-0AD7-4C82-B2ED-E5248D03216A.png`) presents native sheet chrome, readable marks/styles/list groups, visible Bold selection and Body check, with lower content continuing past the current detent. No new material normal-size layout defect is visible. Static imagery does not establish that the paragraph/mark states match the exact captured editing selection or that every lower command is reachable; this remains a behavior check. The prior optional More Headings submenu-affordance observation persists.

The keyboard-visible writing capture has one complete accessory and a top Done action, with the caret and ordinary body text clear of the keyboard. The template capture (`D62E7257-1DA6-426E-B530-FB8144A89467.png`) now uses compact plain rows: all four names fit comfortably above the keyboard, search is focused, and Close remains visible. The prior picker-density finding is closed for this normal-size iPhone capture; no iPad/large-text closure is implied.

The manifest separately records “Neither element nor any descendant has keyboard focus” during synthesized app-level typing. That is a test failure requiring investigation, but this review does not infer broken native cell input, loss of content, or table accessibility correctness from it alone. No table screenshot was among the four named PNGs reviewed here, and no structured-editor acceptance is given.

## iPhone reading-inset verification — 22 September 2026

Independently inspected `artifacts/notes-iphone-reading-inset-evidence/2B42618F-00DC-4F44-8FE6-A4357457F7E0.png`. **The duplicated/empty reading-toolbar surface is absent in this captured normal-text/light after-Done state.** One bottom capsule contains Formatting/Image/Source at the leading side and Templates/Compose at the trailing side, with compose outermost. The bar is clear of the writing shown, and top Back/Share/More remain intact. This closes the specific visible ghost-toolbar finding for this capture. Repeated transitions, long-document final-line scrolling, large text, and iPad remain separate verification cases.

The parent reports moving native table-cell editors to a sibling overlay within JournalWritingView while retaining placement and controls. That is consistent with the approved structured native-cell approach if the grid remains aligned and clipped to its inline attachment during scrolling, exposes correct cell accessibility order, and preserves the shared document undo/focus contract. The change is not verified by this reading screenshot, which contains no table. No inference about the unresolved XCTest cell-focus failure or full structured-editor acceptance is made. No implementation or tests were performed by this reviewer.

## Latest iPhone navigation and table evidence — 22 September 2026

Independently inspected all eleven named PNGs in `artifacts/notes-iphone-table-accessibility-evidence/manifest.json`, then read the relevant table section of FeedbackWorkflowUITests and insertion literals in WritingAccessory/FormattingPopover. No tests or live UI actions were performed.

**The captured normal-text/light navigation, setup, picker, Settings, and reading toolbar are visually accepted within their bounded scope.** Journals and entries now have consistent leading search/trailing templates-compose placement, counts, and the appropriate top actions. All Entries has the correct scope label and a journal indicator alongside date. Settings has Agent Access as a peer and no redundant Journals destination. The name-only picker is compact and includes focused search and Close. The reading bar remains a single capsule without a ghost surface; Share/More and keyboard-visible Done are present. Formatting's shown controls fit the initial sheet detent, with lower contents scrolling beyond it. This does not establish the behavior of every formatting command or large-text accessibility.

Two actionable structured-table interaction deviations remain:

1. **P2 — A new table inserts placeholder wording as real content.** `C46ED958-BF5E-47C0-A2EA-7397D45B14BA.png` shows **ProjectColumn** after typing Project in the first header. Both insertion routes seed literal Column text; the test taps the header and types without replacing it. A new table should start with empty editable header cells, using nonpersistent accessible placeholders if needed. Alternatively, if seeded text is intentional, initial cell focus must select it for replacement. Do not require every person to delete boilerplate to name a column. Check both accessory and Aa insertion routes and source serialization.

2. **P2 — Viewing source and returning to preview re-enters editing at the body end.** Test source explicitly calls Done, then View Source, then View Preview. `B862D61D-7C9E-4C6A-8658-A5E9740F0C8D.png` shows the keyboard reopened and caret at the end of the body, with the table partly above the visible content edge. Inspect mode-transition focus/selection restoration: changing representation after Done should preserve reading intent and a meaningful scroll anchor rather than unconditionally activating the body at its end. When switching during editing, restore the corresponding logical selection where possible; do not conflate a source/preview command with an explicit request to start writing elsewhere.

The native table editing image otherwise shows an aligned two-column header/data-row grid, a visible caret within the first header, clear distinction between header and data row, and retained surrounding text. The preview image still shows the typed header content and a grid rather than forced raw source. These are useful observations, but no comprehensive table editing, long-cell wrapping, wide-table scrolling, shared undo, VoiceOver, source preservation, or shortcut-safety acceptance follows from these short fixtures. The parent's current structural shortcut fixes require their own behavioral verification. Dark/largest text, latest iPad, and live Mac remain outside this capture set.

## Bounded iPhone table corrections verified — 22 September 2026

Independently inspected `artifacts/notes-iphone-final-workflows-evidence/A94C4BE0-3105-4C2F-B5E1-9DB34D764744.png` and `70853B96-355F-44CE-ACDE-5D413FE6175A.png`. **Both preceding table findings are closed for the captured normal-text/light workflow.** Editing shows exactly Project in the first header, with the other header empty and a clear native caret. After the reported Done → source → preview sequence, the grid and surrounding writing remain visible at a sensible reading position, with no keyboard, no Done editing control, and one reading bar. No literal Column boilerplate or forced end-of-body edit state remains in these images.

The parent reports the end-to-end workflow passing with assertions for the exact Project header and absent keyboard after the round trip. Those execution results are attributed to the parent; the reviewer independently verifies the visible outcome only. Full structured editing, long/wide tables, large text, VoiceOver, and shared undo remain subject to their separate evidence. No implementation or tests were performed by this reviewer.


## iPad portrait correction and complete named-capture review — 22 September 2026

Independently inspected all eleven named PNGs in `artifacts/notes-ipad-portrait-correction-evidence/manifest.json`; raw snapshots and video were excluded. No implementation, builds, tests, simulator operations, or live UI actions were performed by this reviewer.

**No new material visual blocker appears in this normal-text/light portrait set.** The Journals capture (`23BCC735-4A7D-4172-AB16-75B36A8D6B6C.png`) shows a readable title, New Journal and native sidebar toggle without overflow, collection counts, and Settings in its own final sidebar section. Entries (`BCE67FB6-65F3-4B57-B043-E7DF7EA7F8A0.png`) shows the overlay dismissed and entries/detail exposed. This closes the visible portrait obstruction in the captured resulting state; the parent reports the one-tap selection flow. It does not establish roomy landscape visibility retention.

Template picker (`4B0F5A46-0C5D-4ED0-87CE-AC1353F346DF.png`) is a bounded popover above the keyboard with search and four comfortably fitting plain name rows. No redundant Close appears in this regular presentation. Its placement is coherent near the list actions, though the screenshot alone does not expose an arrow proving its exact anchor. Formatting choices (`7F066065-5781-4EAD-92A3-157247FF430A.png`) visibly points to the native accessory Aa control, closing the demonstrated root-anchor concern for this invocation. Lower formatting content continues near the popover's scroll boundary; reachability remains a behavior check. The optional More Headings submenu-affordance observation remains nonblocking.

Editing above keyboard (`734B30E4-DD7F-48A9-A56B-EA5100F66BAA.png`) shows one complete app accessory, a clear writing caret, and top Done. The additional iPad system shortcut strip is native OS chrome. Reading after Done (`68064A03-5BD6-4CEB-93CE-4E78AF14D008.png`) has no keyboard or Done and exactly one detail reading capsule, plus the separate list creation capsule. No duplicate or ghost surface is visible. The detail capsule is unnecessarily wide for its three centered actions; an intrinsic-width centered regular-iPad refinement is approved separately as nonblocking polish.

Native table editing (`2483AA9C-5B36-4A39-91A5-7251FAB78D72.png`) shows exactly Project in the first header, an empty second header/data cells, aligned grid, caret, keyboard/accessory, and Done. Table after preview switch (`6C9A3620-052B-4DAD-9DBE-681D4667F73E.png`) retains the grid and surrounding writing with no keyboard or Done and one reading bar. The earlier literal Column and unwanted return-to-editing findings remain closed in these iPad captures.

Settings sections (`9B0CC93F-E148-4BCB-BB64-923A2299BCB5.png`) presents readable Sync, Devices, Privacy, and Agent Access rows in a native sheet with Done. All Entries after relaunch (`401393C2-2922-4D28-AAEA-EF7E10BFF0A9.png`) has the correct Search All Entries scope, a compact date/journal-badge line, title/preview, and appropriate empty detail. Encryption choice (`C0D6D4C9-B3EC-43D6-820F-ED151556B510.png`) shows the full stored-encryption explanation, both choices, warning, and Cancel without clipping.

The parent reports that the main workflow through the table source/preview round trip passes and that a subsequent new-entry-focus failure is being corrected. Those reports are not independently executed results; this capture review does not establish a complete test pass or verify that focus correction. Dark appearance, largest text, latest landscape/resize behavior, hardware/floating keyboards, VoiceOver, long/wide tables, and shared undo remain outside this evidence set.


## iPad focus-workflow follow-up — 22 September 2026

Independently inspected the three requested PNGs in `artifacts/notes-ipad-focus-final-evidence`. Reading (`E63448A0-EC79-4CBA-AF95-A0EE32569DDA.png`) and checklist (`AC31A77E-19B1-4923-960F-6D5509E0BAF3.png`) now show the approved intrinsic-width three-action capsule centered in the detail, without duplicate surfaces, keyboard, or Done. Its spacing is balanced and leaves writing primary. **The regular-iPad reading-bar refinement is visually accepted in these normal-text/light portrait states.** The checklist has a clear checked blue control beside Review the day, with the Checklist title and matching list entry. Static imagery establishes the visible checked state, not its serialization or accessible activation behavior.

Landscape (`3FED9AE2-CC73-436B-83A9-FA2B23E89E92.png`) visibly retains Journals alongside All Entries and the selected checklist detail, supporting the reported three-column result. However, the supplied image renders with a large black band and the right-hand detail/toolbar clipped, consistent with a capture during rotation. It does not establish complete settled landscape layout. A settled full-window landscape capture remains useful; no app defect is inferred solely from this capture artifact.

The parent reports the complete iPad workflow passing, including second-entry title replacement, native checkbox activation serialized as `[x]`, Done/source/preview keyboard state, and portrait-to-landscape selection with sidebar retained. This supersedes the earlier parent-reported pending focus failure, but remains attributed execution evidence rather than a reviewer-run test. Dark/largest-text checks are reported in progress and are not accepted by this light capture set. No implementation, builds, tests, or live UI actions were performed by this reviewer.


## Largest-text iPad navigation failure — 22 September 2026

Independently inspected `artifacts/notes-ipad-dark-final-evidence/navigation-state.png`. **P1 — Journal navigation is unreadable at the captured accessibility text size.** In the narrow regular sidebar, the All Entries and selected journal labels have effectively disappeared beside oversized icon/count/disclosure content. Templates and Archived break into short fragments over many lines; the section heading also wraps awkwardly. This is a concrete accessibility usability failure, not merely a cosmetic difference. The parent reports the largest-Dynamic-Type dark navigation test failing; that execution outcome is attributed to the parent.

The independently reviewed correction is approved before implementation: use the existing full-width stacked route at accessibility sizes, wrapping names and secondary counts, with decorative row icons/chevrons omitted and system text size preserved. Standard text retains its reviewed split layout. This audit records the failure and proposal approval only; closure requires actual corrected captures and relevant navigation checks.


## Accessibility navigation and template-search source audit — 22 September 2026

Read the current RootView, CompactJournalNavigation, TemplateChooserView, TemplateSearchField, and the relevant EntryCreationActions presentation route against the approved review. This is source inspection only; no code changes, builds, tests, or UI operations were performed.

**P2 — Template search still has a fixed-height, unconfigured Dynamic Type boundary.** `TemplateChooserView.swift:31` imposes `.frame(height: 44)` on the UIKit search wrapper. `TemplateSearchField.swift` sets placeholder, style, delegate and text-input preferences but does not assign a preferred text-style font or enable `adjustsFontForContentSizeCategory` on its search text field. The new accessibility-size sheet removes the fixed-width popover problem, yet the search control has not been made to honor the selected text size with sufficient height. Minimal correction: use the preferred body font with automatic content-size adjustment, and derive the search row height from native fitting/font metrics with 44 points as a minimum rather than an exact cap. Recompute on content-size changes. Verify the largest-size search field, clear button and Close while the keyboard is visible; do not simply enlarge the entire template popover or cap the font.

The route adaptation itself is consistent with the approved architecture: `usesStackedNavigation` depends on compact size class or accessibility Dynamic Type; navigationPath and columnVisibility live in RootView outside either presentation branch. Both existing-entry navigation and successful collection changes update that persistent path, and no new size-change callback forcibly resets it. Template presentation now receives `anchored: !usesStackedNavigation`; the alternate root sheet remains unanchored. The reviewed files contain no additional definite Dynamic Type route-reset defect. This is not behavioral acceptance: switching text size in both directions with an active/pending draft, and returning to Journals before a split/stack round trip, still requires actual checks. Those checks should also establish that editor reconstruction does not lose active composition or leave stale editing/accessory state.

## Settled iPad landscape follow-up — 22 September 2026

Independently inspected `artifacts/notes-ipad-settled-evidence/C9EE7ABB-5AB4-4A82-84F7-115F1AA5CF0A.png`. **The settled normal-text/light landscape layout is visually accepted within this capture's scope.** Journals, the selected Default journal's entries, and the Checklist detail are all fully visible. There is no black rotation band or clipped right-hand toolbar. The selected journal and entry remain clear, Search Default matches the visible list scope, counts and date-first rows are readable, and the checked Review the day item remains visible in the editor. The independent list creation capsule and intrinsic-width centered reading capsule each appear once; Share and More fit at the upper right. No keyboard or Done editing control is present. This closes the earlier incomplete landscape-capture evidence, without inferring additional interaction behavior from a still image.

The parent reports the complete workflow passing; that remains attributed execution evidence. The parent also reports the template search correction implemented with a preferred body font, automatic content-size adjustment, and a scaled height with a 44-point minimum. This landscape capture does not contain that control and does not close its largest-text verification requirement. The latest accessibility stacked-route capture is pending separate review. No implementation, builds, tests, simulator operations, or live UI actions were performed by this reviewer.

## Corrected largest-text/dark iPad capture review — 22 September 2026

Independently inspected all thirteen named PNGs in `artifacts/notes-ipad-ax-corrected-evidence/manifest.json` and the issue-description attachment. No implementation, builds, tests, simulator operations, or live UI actions were performed.

**The previous unreadable largest-text journal navigation finding is closed for this captured stacked presentation.** Journals (`BC7F9BE5-5D26-40E7-BB0F-75DCD96E3505.png`) uses the full available width: All Entries, Default, Templates, Archived, and Recently Deleted are readable, with counts on a separate line and no narrow-column fragmentation. Entries and All Entries after relaunch show clear collection titles, matching search scope, and a readable date/journal/title row. The largest-text landscape checklist (`5DCB6FEF-636A-45B4-A095-A0E8281EF418.png`) appropriately remains stacked, with Back, Share, More, the checklist, and one reading capsule fully visible. It is settled without the prior rotation artifact. This is bounded visual acceptance of the accessibility-size route, not proof of in-session text-size switching or draft preservation across route reconstruction.

**The template-search font/height finding is visually closed for the shown keyboard-visible state.** Template picker (`75715BE4-A77B-4376-BDF4-C4A3108BBD6B.png`) now has visibly enlarged Search Templates text, sufficient vertical room, a clear control, and a separate reachable Close action above the keyboard. The result names remain readable. Workday Log crosses the current sheet's lower scroll boundary; this is not by itself a clipped fixed-height row or inaccessible result. The parent reports the complete workflow passing, which supplies attributed activation evidence. A static image cannot independently prove scrolling every result, clear-button behavior, or VoiceOver naming.

Formatting (`07E1D46E-1318-4B2E-9D30-2FC5BA226CAE.png`) shows large readable marks, styles, selected Body, and list commands in a native sheet. Lower commands extend below its current scroll boundary; no definite layout blocker is visible, and full command reachability remains a behavior check. The existing nonblocking More Headings submenu-affordance observation persists. Keyboard editing (`D2CCA72A-0A43-4C66-9C80-D2CE8F3A9251.png`) shows a clear body caret, top Done, and a single app accessory above the native iPad shortcut strip. Reading after Done (`F1D27587-942E-41D4-B7D5-6A24B533A578.png`) shows no keyboard or Done and one reading capsule without a duplicate/ghost surface. Text and headings wrap naturally at the selected size. These captures do not independently establish final-line scrolling with the largest text.

Native table editing shows exactly Project, a clear caret within the first header, an aligned two-column grid, surrounding content, and the keyboard accessory. The subsequent preview preserves the grid and text with keyboard/Done absent. The completed checklist is readable and checked in portrait and landscape. No recurrence of the seeded Column text or forced source/preview editing state is visible. Long/wide tables, editing multiline cells, shared undo, and VoiceOver table order remain outside these short fixtures.

Settings presents all four destinations and Done without clipping. The encryption-choice capture shows a readable heading and opening explanation but its choices and remaining explanation are below the current scroll viewport. It therefore cannot by itself verify the entire encryption disclosure; the reported passing setup workflow is execution evidence attributed to the parent.

No new material visual blocker is established by these captures. The issue attachment still contains the unsupported UIKitToolbar-as-UIHostingController-subview diagnostic. This remains an implementation diagnostic to account for, not evidence of a new visible duplicate or a failed assertion in this reported passing run. The capture review does not waive the separate VoiceOver, hardware/floating keyboard, size-change preservation, and live macOS verification requirements.

## Latest normal iPhone workflow reconciliation — 22 September 2026

Independently inspected the twelve named PNGs and issue-description text associated with FeedbackWorkflowUITests in `artifacts/notes-iphone-complete-evidence/manifest.json`. The separate History and deletion test captures were not part of this requested image review. No code, builds, tests, simulator operations, or live UI actions were performed.

**The latest normal-text/light iPhone main workflow remains visually accepted within its captured scope, with no new material visual blocker.** Journals and Entries retain the clear push hierarchy, readable collection counts, scoped leading search, trailing Templates/Compose, and appropriate upper actions. All Entries after relaunch identifies Default alongside the date, preserves the title/preview, and correctly says Search All Entries. Settings presents Sync, Devices, Privacy, and Agent Access without a redundant journal-management destination. The encryption-choice sheet shows its complete explanation, both actions, plaintext-access warning, and Cancel without clipping.

The template picker has readable name-only rows, focused search, and Close, with all four choices fitting above the keyboard. Formatting shows the approved marks/style/list structure with visible selection and a scroll boundary below Checklist; no lower-command reachability is inferred from the initial detent. The parent reports correcting the remaining indentation text row to call the previously approved icon helper. Those lower indentation controls are outside the supplied formatting viewport, so this is an attributed implementation correction, not independent visual verification of that row.

Keyboard editing shows one complete app accessory and top Done, with the caret and entered text visible. After Done (`59336013-5EC7-4E40-802B-FC2A6B8DE384.png`) and after the table source/preview round trip (`A21DF1AB-CD20-415A-8205-452F50571C2A.png`), no keyboard or Done remains, and exactly one reading capsule is visible without a ghost surface. Native table editing contains exactly Project in the first header with a clear caret and aligned grid; preview retains the table and surrounding writing. The final checklist has a visible checked control and clean reading state. These images are consistent with the previously accepted normal iPad and corrected largest-text iPad states; no earlier toolbar or seeded-table finding is reopened.

The parent reports the main workflow and History workflow passing. The deletion workflow reportedly failed only on a stale retention-note text assertion, which has been corrected and is rerunning; this review does not independently certify that diagnosis or the rerun. The main workflow issue attachment still contains the UIKitToolbar hierarchy diagnostic already recorded above, without a corresponding visible duplicate in these captures.

The Mac placeholder omission is an intentional response to the user's request for a clean, unclipped editor, as clarified by the parent. No restoration is requested by this review; no Mac visual acceptance is inferred from mobile evidence. Existing verification boundaries for VoiceOver, keyboard variants, changing text size with drafts, and comprehensive structured editing remain unchanged.

## Final supplied largest-text/dark iPhone main and recovery review — 22 September 2026

Independently inspected all eighteen named main-workflow/recovery PNGs and both issue-description texts in `artifacts/notes-iphone-dark-verified-evidence/manifest.json`. No builds, code edits, tests, simulator actions, or live UI operations were performed. The parent reports both Feedback and journal deletion/restoration/relaunch workflows passing, including explicit horizontal scrolling to reach Source and New Entry; those are attributed execution results.

**Reading, editing, picker, and recovery captures are accepted within their visible scope; one P2 entry-row accessibility issue remains.**

### P2 — Largest-text entry identification remains constrained

All Entries after relaunch (`0986431B-9A84-49F7-826F-FBF8F82B89DA.png`) still places the date and journal badge beside each other. The short journal name Default breaks as De-/fault beside a decorative book icon, while both the entry title and preview truncate. Recently Deleted similarly truncates the entry's identifying title (`A0E2F5C0-5284-4D2D-A865-5A2464B3890F.png`). This does not block tapping the single fixture, but it weakens identification and comparison with multiple entries at the very size intended to improve readability. The previously requested natural row growth is not fully satisfied on this phone width.

Approved bounded correction: at accessibility text sizes, place the date then the journal name on separate full-width lines, omit the decorative journal icon, and permit the entry title to wrap to its natural height. The preview may remain bounded. Keep the compact date/journal metadata row and one-line title at normal text sizes. Apply the shared entry-row correction consistently to All Entries and recovery lists, without changing navigation or text size. Verify a corrected largest-text capture before closing this finding.

### Accepted observations and limits

The reading bar is an intentional horizontal-scrolling fallback. After Done (`445C7F01-34C1-4883-AA9F-4ADA5BFB1947.png`) it visibly exposes Image, Source, Templates, and Compose, with Aa beyond the opposite edge; other reading images show the leading Aa/Image/Source side. This is consistent with the reported scroll-to-action check. No duplicate/ghost surface, keyboard, or Done remains in reading states. An action outside the current horizontal viewport is not itself a layout defect.

Journals now has readable full-width names and separate counts. Collections below the initial viewport need vertical scrolling, as expected at this size. The native bottom search placeholder truncates at this extreme size, but the magnifier and separate creation actions remain visible; actual search scope and accessible naming are not established by that abbreviated placeholder. Template search and Close fit above the keyboard, all four names are readable with natural wrapping, and Formatting shows enlarged readable initial commands with lower content continuing beyond the sheet viewport. The new indentation icons are still outside the supplied formatting crop and are not independently verified here.

Body editing shows a clear caret above the keyboard and one complete app accessory with Done. Native table editing shows Project and a caret in the visible header cell; preview retains it without re-entering editing. Only the first wide cell is shown at this text size, so horizontal table reachability is not independently verified. Checklist text wraps readably beside its checked control. Settings labels wrap without losing their meaning. The encryption-choice capture shows the beginning of its scrollable explanation, not its lower action/disclosure region.

Deletion and restoration sheets identify Default and the local entry count. Paired initial/scrolled captures demonstrate readable explanations and reachable Delete Journal/Restore Journal actions, with Cancel retained. The complete retention note is visible after scrolling: deleted items remain until restored or permanently deleted. These observations accept the visible recovery layout; the passing reopen and persistence behavior remains attributed to the parent. Both issue-description texts retain the previously recorded UIKitToolbar hierarchy diagnostic, with no corresponding visible duplicate in these captures.

This review does not establish VoiceOver traversal, hardware/floating keyboard behavior, in-session text-size changes with pending drafts, complete table navigation, or final Apple-lane results. Apart from the bounded entry-row correction above, no further material visual issue is established by this evidence set.

## Accessibility entry-row proposal review — 22 September 2026

Independently read the concrete Accessibility entry rows section appended to `notes-alignment-revision.md` before implementation. **Approved.** The accessibility-only vertical date/journal metadata, omission of the decorative book icon, and natural-height wrapping title directly address the observed identification failure. A single preview line is a reasonable density tradeoff once the full title remains available. Keeping the conflict indicator with the date preserves important state, and retaining full-row actions and the combined accessibility label avoids introducing fragmented navigation. The shared title treatment should include Recently Deleted, while journal-name metadata remains in the collections where it is relevant. Normal text and macOS need no adjustment. This approval is for the proposal; close the actual-UI finding only after inspecting the corrected largest-text row. No implementation was performed by this reviewer.

## Accessibility entry-row actual correction — 22 September 2026

Independently inspected `artifacts/notes-iphone-entry-rows-evidence/55B36DCA-0E2B-4E42-9175-BA3B24575951.png`. **The P2 entry-identification finding is closed for the corrected largest-text/dark All Entries capture.** The date and Default now occupy separate full-width lines, the decorative book icon is absent, and A focused workday appears in full across two naturally wrapping lines. The single preview remains bounded as approved. Nothing overlaps or clips the identifying content; the taller row is the intended accessibility tradeoff. No new material issue is visible in this capture.

The parent reports the full workflow passing again. That execution result is attributed, not independently rerun. This image verifies the shared row's All Entries presentation; it does not separately depict Recently Deleted, a long journal name, conflict state, or VoiceOver traversal. No builds, source edits, tests, or live UI operations were performed by this reviewer.
