# macOS live acceptance: independent visual review

## Scope and method

On 2026-09-21, selected the exact disposable acceptance app through CUA at `artifacts/mac-input-acceptance/Journal Acceptance.app` (parent identifies bundle `org.privatejournal.inputacceptance`). Read its actual accessibility tree and captured its current Personal window. The menu bar identifies Journal Acceptance. The parent describes this as a current-build copy with an isolated vault; this inspection did not independently compare executable hashes or inspect storage isolation.

The reviewer performed no typing, clicks, menu opening, navigation, edits, or system-setting changes. The parent temporarily selected macOS Dark and was notified immediately after observation that inspection was complete so Auto could be restored. This record does not itself verify restoration.

## Directly observed presentation

The full window presents a familiar macOS split layout: a journal/navigation sidebar, a dated entry list, and the writing editor. This provides the requested timeline/editor pair with an additional visible collapsible sidebar; it does not replace writing with a dashboard. The Personal journal is selected, and its selected entry is clearly distinguished in the middle column. The right editor occupies the largest column and keeps the page quiet, with a short title above the body and ample space below.

The title “Native editing check” and both body sentences are fully readable. The first line visibly retains the misspelling `teh`, straight quotes, and two hyphens; the second sentence, “Today I finished the writing check.”, is visibly bold. The body accessibility value also distinguishes that bold sentence. The selected timeline preview shows matching text without leaking formatting syntax into the visible preview. This confirms current displayed content/style only, not how it was entered or persisted.

Neutral dark surfaces and clear column separators provide native hierarchy without competing accent colors in the writing area. Toolbar actions sit above the content: sidebar toggle, new entry/options, Formatting, Insert Image, Entry Actions, and Search Personal. AX exposes descriptive labels/help for these controls, an editable title field with Title placeholder, and an editable Entry text area. The screenshot contains subdued window/toolbar chrome, so it is not a measured contrast or enabled-state audit. The editor text is readable and no content overlaps or clips in this window.

The sidebar groups Personal, Templates, Archived, and Recently Deleted in familiar navigation rows, with New Journal… and Manage Journals… actions below. These are understandable and outside the writing column. The presentation is consistent with the requested Notes-like native conventions at this size. Hide Sidebar is exposed in AX, but collapsing it was intentionally not exercised. The snapshot contains only one entry, so it does not establish timeline scanning quality with a long list.

## Parent-reported interactions and limits

The parent reports independently exercising the current disabled correction/substitution settings, typing misspelling/straight quotes/dashes unchanged, Tab from title to body, the visual Bold popover, keyboard undo/redo, entry context menu, Change Date cancellation, and quit/relaunch retention of title/body/bold. Those interactions were not performed or watched by this reviewer. The final visible text supports the resulting appearance, not the full event sequence or persistence guarantees.

No VoiceOver traversal, keyboard navigation, selection/composition, dynamic text sizing, reduced motion/transparency, increased contrast, window resizing, sidebar collapse, long content, empty/loading/offline/error states, image insertion, templates, conflict recovery, or alternative appearance was tested here. AX exposure is useful evidence but does not establish VoiceOver reading order or operability. This is a visual check of the current native window, not a substitute for focused behavior tests or a fresh package/source match.

## Disposition

Accepted for the observed dark-mode macOS writing surface and current title/body formatting. No material layout, readability, native-convention, copy, or action-placement blocker was found in this bounded read-only inspection. Broader interaction acceptance remains supported only by the parent's reported checks and separately recorded tests. No production code changed and no reviewer tests were rerun.

## Bounded Settings navigation investigation

Subsequently selected the same exact acceptance app with its Sync Settings window open. Independently read AX and the actual screenshot. Sync, Devices, Privacy, and Journals labels are tightly abutting above their icons in a compact toolbar group beside Done. The body shows Server, “Your journals are saved on this device.”, Use This Mac…, and Connect to a Server…. AX exposes each tab-like toolbar item as a container with text/image children and toolbar movement/removal actions; no press/select action or selected tab role is exposed in the returned tree.

Clicked the screenshot-observed Privacy icon location and then Journals icon location through CUA; after each, AX still showed the Sync window and same body, with focus on the window. A bounded alternate keyboard attempt using Control-F5 likewise showed no AX/focus change. No forms, menus, access grants, fixture edits, or settings changes were made, and the window was left intact for the parent.

This independently reproduces the failed automated navigation but does not conclusively distinguish an application hit-testing defect from CUA delivery/activation or accessibility limitations for these toolbar items. Do not report confirmed physical-mouse failure or a passed Settings navigation route. The crowded label spacing is directly visible and the missing selectable semantics in returned AX are concrete concerns. The parent reports ordinary tagged TabView selection with no discovered reset; that source was not independently reviewed in this UI-only investigation. If a correction is needed, prefer native selectable Settings controls with distinct labels and adequate spacing; do not add a custom navigation system merely to satisfy automation. Confirm the actual cause with a single physical/native-control check or focused navigation harness, and apply the design gate before a material UI change. No further retry loop was performed.

The subsequent Settings investigation and parent-reported successful sheet route are recorded separately in [mac-settings-navigation-review.md](mac-settings-navigation-review.md). The evidence does not establish physical navigation failure or justify a production change by itself.
