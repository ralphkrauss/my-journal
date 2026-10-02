# Writing and onboarding revision — independent review

Date: 2026-09-21
Proposal: `docs/design/markdown-writing-revision.md`
Verdict: revise the material points below before implementing the affected flows. No frontend code, builds, simulators, or live Mac interactions were used in this review.

## Requirements and accepted direction

Reviewed the proposal and current AGENTS.md against the supplied newest requirements: explanatory encryption choice, genuinely passwordless skip, no Generate/Copy buttons, native icon-only creation toolbar, Notes-like formatting, canonical CommonMark/GFM writing with explicit keyboard commands, destructive journal controls, direct Settings toolbar shortcut, and searchable name-only template selection. These requirements supersede the earlier password-generation and template-preview designs.

The two-step encryption choice, directly explained plaintext alternative, single secure password field, native toolbars, direct gear, explicit command invocation, and destructive-action restraint are appropriate. Do not reintroduce a confirmation password or password-generation controls. The proposed ordinary-typing behavior is especially clear: no slash interception, Markdown replacement, unsolicited popup, or interference with IME composition. The updated template picker removes the confusing destination heading and previews as requested. Keeping regular iPad anchored and compact iPad/iPhone in a sheet is appropriate.

## Material findings

### 1. Complete the passwordless credential and recovery journey

“Explain this in the connection/recovery screens” is not yet a concrete design. A passwordless library cannot reuse a generic password/recovery-key form or imply that an archive credential controls readable files. Define exact entry points, labels, and copy for: creating locally while offline; connecting that library to a new server; pairing to an existing passwordless server; losing the last authorized device; restoring its archive; and app-lock fallback if the user later enables a PIN. Legacy encrypted and older password-protected plaintext libraries must keep their original credential prompts.

Specify whether administrator recovery is actually available in this build. Do not direct a stranded user toward an unspecified reset procedure. A useful distinction is “Your entries aren’t encrypted. To connect this device, approve it from another device or contact your server administrator.” Archive restoration should explicitly require no password for the new plaintext format, while server access still requires authorization. Restoring a readable archive must never implicitly restore server authorization from a publicly readable secret.

Also finish the password step's visible states: “Use at least 12 characters.”; initial hidden field and Show/Hide Password; Back retains transient input, whereas Cancel exits and clears it; exact failure copy and safe retry after partial creation. State that a password is not a backup and recovery also requires another device, server data, or an archive. The opening “only you can read them” should describe encrypted stored content rather than suggest an unlocked device or exported readable document is protected against every reader. Suggested concise opening: “Encrypt your journal files to protect your writing. Your master password lets you restore a backup or connect another device.” Pair this with the existing password-manager guidance and a short loss-of-access explanation.

### 2. Turn the Markdown promise into a concrete native editing contract

Canonical Markdown plus a rich editor is a major document-model change, not solely a styling change. The proposal leaves two incompatible fallback options open (“visible source block” or “keep the document in source mode”) and does not identify which supported constructs are natively editable, rendered read-only, or source-only. Resolve that before implementation. Include an explicit matrix for headings/marks, code, nested lists/tasks, quotes, tables, rules, links/images, safe underline extension, and unknown syntax. A table may be edited in source as proposed, but full dialect support must not be claimed if tables or nesting are flattened or simply disappear from the formatted view.

Specify actual user controls on Mac and touch: exact source/formatted mode labels and placement, mode-switch focus/caret behavior, and what happens to selection and undo. “Available from Format” is not a complete touch path. For a document that requires source mode, give exact explanatory copy and an actionable source control; never switch modes while the user is typing. For a preserved block, define its visible boundary and whether it can be moved/deleted as one explicit operation. Editing an adjacent paragraph must not rewrite or erase that block.

Define the underline syntax and attachment URL form as part of the versioned contract, rather than an unspecified safe extension. Raw HTML remains inert; distinguish preserving its text from rendering/executing it. Remote image URLs must remain represented and discoverable without fetching. Syntax commands must be well-defined inside code fences, escaped text, and mixed/nested selections; when unsafe, keep the source unchanged and explain the unavailable command. Keep ordinary typing and composition fully native.

### 3. Make preservation and conversion boundaries testable

“Converted only at a deliberate successful save” is ambiguous in an autosaving journal. Specify the trigger, for example the first actual body edit or formatting command in a legacy document, rather than opening it, changing its date, or syncing. Conversion must preserve the legacy original in history atomically with the new version and must leave the old document intact if persistence fails. Define what the user sees when a legacy construct cannot be converted losslessly; do not silently approximate it.

Use source-authoritative editing so opening/saving without edits preserves exact source, and editing one region preserves unrelated unknown syntax, code whitespace, reference links, and attachment references. State how legacy and Markdown versions appear in conflict review, history, restoration, export, and template creation. Stable record identities and metadata alone do not establish preservation of the document itself. Old-client refusal must be checked against the actual document/version boundary rather than assumed from the proposal.

The proposed tests are directionally useful. Add explicit mode-switch-without-edit, edit-adjacent-to-unknown-block, failed-conversion-save, and mixed legacy/new conflict/history restoration cases. Use focused parser/store/editor tests; a broad simulator matrix is unnecessary for these data guarantees. These are meaningful no-loss boundaries, not coverage targets.

### 4. Specify formatting and command-picker interaction before building it

“Orderly native groups/submenus” leaves the actual Notes-like layout undefined while expanding the control set substantially. Provide the exact top-level groups and which commands open submenus. Keep frequent bold/italic/underline, paragraph styles, and lists directly discoverable; less frequent table/rule/code insertion can use an Insert group. Define the command picker's title, search placeholder, no-results state, selection/Return behavior, Escape dismissal, and explicit touch-accessible entry point. No command should mutate text merely because it is highlighted.

Record shortcut collision handling across Mac and external iPad keyboards. Native text/navigation/IME shortcuts must win in text fields; formatting commands apply only to the active valid editor session. Whole-row targets and captured selection still apply to every submenu/picker route. At large text, describe expansion/scrolling and dismissal rather than relying on a fixed-height Notes imitation.

### 5. Resolve template ambiguities without restoring previews

The NSComboBox must reject arbitrary typed strings even when they equal a stale template name, and bind acceptance to a live template identity. Explain whether Return first commits the highlighted dropdown item or immediately creates the entry; one Return must not accidentally do both when the user is still searching. Define keyboard focus, no-match recovery, and template/destination disappearance between selection and Create with exact copy.

“Duplicate names remain distinct by identity internally” does not let a person distinguish them. Choose a minimal collision policy consistent with the name-only request—for example a short disambiguating suffix only for colliding names, plus accessible detail—without reinstating prose preview cards or silently renaming existing templates. Also document that ordinary New Entry can still use a default template; removing Blank Entry from this picker should not change that behavior by accident.

## Actual-UI acceptance and scope

After these revisions, re-review the affected proposal. Then inspect one isolated Mac build at normal/narrow widths, native toolbar overflow and column ownership, onboarding branches, template search/keyboard behavior, formatting/menu/picker state, and source/rich transitions. Inspect compact/regular touch routes and large text, including keyboard-visible states. Verify destructive controls by label/role and that Return cannot trigger deletion. Source inspection does not establish native hit targets or menu behavior.

Preserve the requested “another build for feedback” as the delivery outcome after fixes and meaningful checks. Do not call this complete solely because the model parses Markdown or screenshots look native.

## Prior Mac coordinate evidence clarification

The parent subsequently reports that coordinate clicks on both far-right row space and the visible Body text did nothing, while accessibility activation worked and coordinate activation of the toolbar worked. Consequently the prior failure cannot be attributed specifically to row width; automation dispatch into the separate NSPopover window remains a possible explanation. Explicit max-width labels are still consistent with the approved full-row design, but neither that source change nor accessibility activation alone establishes physical pointer hit testing. This clarification supersedes any inference that the earlier coordinate result proved a narrow-label hitbox defect. No live interaction was independently observed by this reviewer.

## Clarification re-review — 2026-09-21

Independently reread the appended Review clarifications. They supersede the earlier alternatives and resolve the substantial specification gaps: passwordless local/server/archive/app-lock routes are concrete; the one-time administrator code has an explicit route and failure boundary; legacy credentials are preserved; a whole-document source fallback replaces ambiguous partial rich rendering; conversion has an actual edit/transaction trigger; formatting groups and command search are defined; and template selection is identity-backed with explicit Return, collision, invalidation, and destination behavior. These are practical boundaries for an isolated feedback build. No new feature scope is requested.

**One material correction remains before implementing mode switching:** the proposed clearing of view-local undo at an explicit mode transition would silently remove the user's ability to undo preceding writing. Merely looking at Markdown source is not consent to lose edit history. Preserve the entry's edit history through source/formatted transitions, or retain and restore the relevant history on return with a coherent chain of edits across modes. Switching modes without editing must never destroy undo/redo. Include the meaningful sequence edit → switch → switch back → undo, and an edit on each side of a transition. This corrects an interaction consequence of the existing scope; it does not require a new user confirmation.

All other reviewed directions are approved for implementation subject to the stated preservation/security behaviors and later actual-UI acceptance. Existing source-of-truth and transactional tests must substantiate the promises; design review is not protocol or cryptographic verification.

Two delivery clarifications are non-blocking: the matrix provides complete dialect *source editing*, with simple constructs editable in formatted mode. It does not provide full rendered CommonMark/GFM styling for tables, nested lists, multiline fenced code, reference links, or remote images. Describe that accurately in the feedback build and completion report; do not claim those source-only constructs are rendered richly. Also present one clear current-mode control on touch so the Source/Formatted labels in the prose do not become redundant controls.

No frontend implementation, builds, simulators, or live Mac operations were performed in this re-review.

## Final preimplementation verdict — 2026-09-21

**Approved for implementation.** Independently verified the revised mode-transition paragraph: a shared native editor/storage and preserved undo manager retain coherent per-entry history, while undoable representation changes restore both presentation and document. Switching modes alone no longer drops prior edits. This resolves the final material design concern; the edit/switch/undo and cross-mode edit sequences remain required behavioral checks.

No material preimplementation findings remain in the reviewed proposal. The source-only construct limits remain explicit and must be disclosed accurately in the working feedback build. This closes the design gate, not the implementation or actual-UI acceptance gate. No frontend code, builds, simulators, or live Mac state were changed by the reviewer.

## Actual touch UI review — 2026-09-21

**Accepted within the observed normal-text, light-appearance iPhone and regular-width iPad scope; no material visual blocker found.** Independently inspected all eight screenshots listed in each of `artifacts/markdown-review/ipad-final/manifest.json` and `artifacts/markdown-review/iphone-final/manifest.json`, and read the two feedback workflow tests. The parent reports both workflows passing on each device and the native Markdown editor tests passing on iPhone; those execution results are parent-reported, not independently rerun by this reviewer.

The iPad template chooser is now a bounded anchored popover with the short Templates title, native search, name-only choices, clear selection, and Cancel/Create. The iPhone sheet fits the same title and actions without truncation and exposes native search at the bottom. Neither adds the unwanted Default heading or prose previews. Writing retains a complete editable title/body, with the iPad two-column layout and compact iPhone toolbar keeping the page quiet. Settings uses the intended navigation list, Privacy has contextual encryption/app-lock information, and current-journal settings has one Default Template picker and a red Delete Journal action. The encryption-choice sheet contains the complete approved explanation and plaintext warning, distinct Use Encryption and Continue Without Encryption actions, and no password or generation controls.

Find Format opens a native Format Text sheet with Cancel/Apply, search, and a visible filtered Quote result. The iPhone capture includes the keyboard and caret in search without covering the result or actions. The iPad result is selected visibly and fits comfortably. Formatting groups fit the iPad popover; the iPhone's initial detent exposes the upper groups with more content below its scroll boundary. The subsequent captured command sheet and parent-reported passing workflow support reaching Find Format, but the static initial sheet alone does not establish every lower-row interaction. Test source types into command search without explicitly tapping it, supporting the intended autofocus path when combined with the reported pass; its final body-text assertion does not itself establish that Quote changed paragraph semantics.

Minor observations do not block this feedback build: template checkmarks appear in primary black rather than the proposed accent, although selection is unambiguous; More Headings and Insert could communicate their submenu behavior more clearly with native indicators. The earlier iPad Privacy keyboard observation persists despite no PIN tap in the workflow, while the iPhone Privacy capture has no keyboard. These captures do not identify the iPad first responder or establish an unintended-edit defect. Privacy still names the product Journal in one app-lock sentence.

This acceptance does not establish VoiceOver behavior, largest text sizes for the revised command picker, hardware-arrow scrolling after the parent's latest change, source/rich undo semantics, full rendered CommonMark/GFM support, or live Mac window behavior. Whole-document source-only handling of complex constructs remains the approved limit and must be described honestly. No frontend code, build, simulator, or live Mac operation was performed by this reviewer.

## Mac offscreen native-render review — 2026-09-21

Independently inspected Formatting, Template picker, and Encryption choice from `PasswordOnboardingTests`, plus Three-column navigation from `EntryActionTests`, as listed in `artifacts/markdown-review/mac-rendered/manifest.json`. Read their capture call sites. These are native view renders at fixed sizes, not screenshots of an interactive application window.

**No material visual defect found in the rendered controls.** Formatting shows all approved top-level groups, Markdown Source, and Find Format without clipping at the supplied 250-by-470-point capture size. The earlier optional submenu-indicator observation also applies here. The template control is a readable native combo box with the Template label and Choose a template placeholder; the captured closed state cannot establish filtering, identity-backed selection, dropdown behavior, or Return handling. Encryption-choice explanatory text, both explicit actions, and the full plaintext warning fit without truncation, and no password field is present at this step.

The navigation render shows a readable dated entry list, a visibly selected entry, and the matching editor title and empty-body placeholder. Its left sidebar is blank and window toolbars are absent; it therefore cannot establish the final three-column navigation, journal selector, creation/Settings toolbar placement, or narrow-window overflow. Likewise, the template and onboarding renders omit surrounding window/sheet actions. Those omissions limit this evidence and are not independently established defects in the live application.

This closes the requested offscreen-content inspection only. Live Mac toolbar ownership, physical pointer targets, focus, menu/command presentation, complete window chrome, and keyboard interaction remain unverified while the Mac is locked. The parent reports successful compilation and 68 core, 51 Mac, and 24 backend tests; no tests were rerun by this reviewer, and those results do not replace the missing live visual/interaction evidence. No implementation change is requested on the basis of these renders.
