# Native image-description Form proposal review

Date: 2026-09-20. Independent preimplementation review of `image-description-native-form.md`, with direct inspection of the latest settled-event screenshot referenced in the keyboard review. No Form implementation or new geometry evidence reviewed.

## Outcome

**Approved for implementation and actual native verification.** A grouped iOS Form with separate preview and field rows is a suitable native layout for these per-image settings. It gives the focused control its own row and delegates keyboard-aware row positioning to the native container, while removing the custom scroll coordination that has not solved the defect. The proposal preserves the existing editing, cancellation, stale-state, copy, save and lock contracts and keeps the Mac path bounded.

Use individual native rows for explanation, preview, field, and each actionable recovery control. Do not reconstruct the entire content as one large VStack inside a single Form row: that would lose the focused-row advantage. In particular, keep Copy, Reload and Try Again as separate button rows rather than multiple automatic-style buttons inside one tappable row. Section headers provide image order; each field must retain its explicit ordinal accessibility label when the preview/header scrolls out of view. Unavailable previews remain informative content, not disabled editing controls.

The existing exact copy, Cancel/Done toolbar, system surfaces and typography are appropriate. Plain native field treatment within the row avoids redundant rounded borders. Permit explanatory/error text to wrap and scroll, and announce actionable state changes as already reviewed. No automatic focus, selection, keyboard notifications, timed delays, or per-character scrolling should be added. Retaining focus identity solely to clear it on lock is appropriate. Avoid nesting another scrolling container around the Form.

## Preservation and verification

Treat this as a layout-only change: no duplicate draft/model state, no changed save ordering, no new clipboard writes, no automatic reload, and no dropped fields during list-row reuse. Stable image block IDs must continue to identify local descriptions and repeated attachment uses separately. Committed-state handling and lock reconciliation remain authoritative.

Native Form is a plausible correction, not proof of adequate keyboard geometry. The current defect stays open until an actual largest-text/dark keyboard capture shows the full current line and caret after continued input beyond the visible line range. Inspect editing earlier text, full-value save/relaunch equality, Copy, and normal-size layout. A targeted passing persistence test alone is insufficient. Read the pending geometry capture when available so remaining failures can be tied to actual row, viewport, and keyboard bounds rather than another timing guess.

No further proposal revision is needed before implementing this design. After implementation, inspect source and the real settled keyboard state before calling the visual issue resolved. Offscreen Mac builds/renders and form accessibility labels do not establish interactive Mac or main-editor inline VoiceOver behavior.

## New geometry evidence before implementation

The parent subsequently supplied `artifacts/image-geometry-previews/B4D36295-A1C1-482D-B858-422D47DB6B98.txt`: the reported focused field ends at y539, the system input/prediction surface starts at y539, and the keyboard-key element starts lower at y583. The prior test gesture derived from keyboard.minY minus 30 could therefore start inside the prediction surface rather than the outer content. Verify a normal outer-content scroll using the full input-surface bounds and a margin outside the field before concluding that the current container cannot expose it. The screenshots establish occlusion at their captured positions, not a proven inability to scroll. Approval of this Form proposal permits the layout change but does not require implementing it if corrected interaction evidence resolves the issue in the existing native controls.
