# Template initial insertion review

## Independent proposal review — 2026-09-21

**Approved for implementation with the ownership checks below.** Read `template-initial-insertion.md` against the observed writing-workflow defect and the project's native/minimal/accessibility requirements. No production source was changed and no new execution evidence was inspected.

The proposed interaction is appropriately narrow: initialize selection once in the first genuinely empty paragraph of a newly template-created entry, leave focus with the user, and let the existing native Next action transfer focus. Plain paragraph typing attributes address accidental heading-style inheritance. A direct body tap remains authoritative. Returning from the title preserves subsequent native selection instead of repeatedly jumping to an answer slot. This fixes the observed question-template path without adding template UI, guessing from prose or mutating user content.

Blank entries, existing entries, and templates with no empty paragraph retain their existing behavior. That fallback is conservative and understandable: no arbitrary answer location or new paragraph is fabricated. Multiple prompt/answer templates start at their first prepared answer slot; whitespace-only paragraphs are content. All prompts, image references and formatting remain intact. The model-owned consumed state surviving native-view recreation is important, as view-local flags alone would replay the jump.

### Implementation conditions

- Make the one-shot request available before the new item's first native render, keyed to the exact entry and empty paragraph block. Consume atomically so layout/render callbacks cannot apply it twice; keep consumption separate from document mutations or undo registration.
- Validate that the target still exists as an empty ordinary paragraph in the current document. Resolve by attributed block identity, using UTF-16/native attributed offsets. End-of-document is valid only for that exact trailing empty target, not as a generic fallback for failed lookup. If ownership or target validation fails, discard the request without guessing a position.
- Clear unconsumed ownership when leaving the entry, locking or replacing its store/vault. Do not reinstate requests after relaunch, refresh, appearance/font changes, image arrival or native-view recreation. Explicit user selection remains authoritative after initialization.
- Set ordinary paragraph typing attributes after assigning the selection; do not focus automatically, replace the attributed string solely to move the caret, or add an undo step/document change for selection initialization.

These checks complete the implementation boundary without changing the proposed interaction. No further design revision is required before implementation.

### Acceptance evidence

Use meaningful native tests for trailing and nonterminal empty paragraphs, including an image before the target, and invalid/changed target ownership. Verify initial position/style, unchanged document/template, consumption across native recreation and subsequent selection preservation. The everyday iOS route should check prompt-first then answer-paragraph order and style, rather than only the presence of both strings or the first block being a heading. Inspect the normal/largest keyboard-focused path and persisted result. macOS/iOS native tests do not imply interactive Mac, VoiceOver, physical-device or minimum-OS acceptance. Actual implementation/source and rendered review remain pending.

## Initial implementation and normal-size rendered review — 2026-09-21

**Normal visible behavior accepted; creation ownership finding pending the correction below.** Independently inspected `InitialEditorInsertion.swift`, both native editor branches, model request lifetime, main-editor-only wiring, native test source and everyday writing UI test source. Inspected `/tmp/journal-template-writing-normal.log` and all four captures indexed in `artifacts/template-writing-normal/manifest.json`; no tests were independently rerun for this review.

The request identifies the precise new entry and genuinely empty paragraph. Consumption precedes target validation, resolves attributed block identity, and permits an end offset only for the exact trailing empty block. Both native branches apply it on the initial render, reset paragraph typing attributes after setting selection, and do not request focus or mutate the document. Model lifetime retains consumed state across native recreation and clears the request on entry departure, locking and store replacement. Preview editors receive no request.

The inspected native test exercises trailing/nonterminal answer slots and an image before the target, paragraph attributes, later selection through a font update, consumed-request recreation, unchanged documents, and changed/removed-target rejection. Recreation proves no replay; it does not prove arbitrary native selection survives recreation. The log records both native tests passing and the writing route passing in 50.541 seconds, with `TEST SUCCEEDED`.

All four normal captures show the intended quiet native UI: the initial template opens without a keyboard, Work search lists Monday review with question then answer, Personal search lists its own Garden notes, and the relaunched entry retains the prompt above a plain answer. Source assertions additionally check the exact heading/answer block sequence, plain answer runs, unchanged original template and Personal document, and the expected two entries. This closes the original visible answer-before-heading/bold-answer defect at normal size. The focused-body keyboard frame and largest text size remain pending subsequent captures.

### P2 — creation must retain ownership across every suspension

The initial implementation could resume `newEntry` after saving or refreshing and recreate a draft/insertion request after lock, store replacement or navigation. Clearing the request in setters was insufficient against later publication. The first correction adds an operation UUID, captured store/journal/selection, cancellation checks and publication checks after save and refresh, and invalidates the token on navigation and vault transitions. That closes those later publication paths.

One gap remains in the inspected correction: the token/context are assigned only after the first `await flush()`. A navigation or vault transition during that suspension can finish before the old operation resumes, letting it capture the new context and create there. Capture the ownership context and operation token before this initial suspension and validate the same context immediately afterward. This is an implementation ownership correction, not a change to the reviewed interaction design.

Interactive Mac, VoiceOver, physical-device and minimum-OS behavior are not established by this evidence. Await final ownership source correction and normal/largest focused-body captures for the bounded final verdict.

## Creation ownership correction — 2026-09-21

**P2 closed by source inspection.** Re-read the corrected `AppModel.newEntry`: it now captures store, journal and selected entry, installs its operation UUID, and defines the ownership predicate before the initial flush. It checks that predicate immediately after flush and again after save and refresh. Navigation/vault invalidation therefore cannot be forgotten by recapturing context after the first suspension. Cancellation and stale-error guards remain present; no new source finding arose in this focused correction review. This is source evidence, not a forced asynchronous race test. Final normal/largest focused-body visual evidence remains pending.

## Final normal/largest rendered and state review — 2026-09-21

**Accepted within the inspected iOS scope; no remaining finding for this template insertion change.** Independently inspected both final manifests and all ten screenshots in `artifacts/template-writing-normal-final` and `artifacts/template-writing-large-final`, plus `/tmp/journal-template-writing-normal-final.log` and `/tmp/journal-template-writing-large-final.log`. The normal log records both native insertion tests passing and the writing route passing in 49.857 seconds; the largest route passes in 50.105 seconds. Both logs end with `TEST SUCCEEDED`. These are inspected execution records, not reviewer reruns. The broader Apple lane was still running when this review was written and receives no acceptance claim here.

The normal focused-body capture (`602D8282-AF51-444C-B7DB-7624FC875070.png`) shows the original heading followed by the plain answer, with the caret on its following paragraph and the native keyboard open. The largest dark capture (`1540215E-8721-4117-9DDB-5FF461112638.png`) shows the full wrapped plain answer and visible caret above the keyboard. The body has scrolled to keep that caret visible: the prompt is partly outside the body viewport, while the separate title remains visible. This frame does not establish simultaneous full-prompt visibility; the initial and relaunched largest frames establish the complete prompt and prompt-before-answer order without clipping the document content itself.

Both final relaunch captures show the heading intact above the ordinary paragraph answer. Initial captures show no automatic keyboard. The Work and Personal search captures show the appropriate journal/result; at largest size the row title is ellipsized and the keyboard/search surface obscures the excerpt, so these frames alone do not establish complete row-copy readability. The passing route's inspected assertions establish result isolation and the exact persisted document state described in the earlier review. No search-layout redesign is approved or required by this narrowly scoped insertion change.

Together with the corrected creation ownership source, this closes the original template-answer insertion defect and the focused-body visual evidence gap. Direct-tap behavior follows the native selection implementation but was not separately driven in these routes. Interactive Mac, VoiceOver, physical-device/minimum-OS behavior and forced asynchronous ownership races remain outside this acceptance boundary.
