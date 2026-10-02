# Entry title accessibility

## Problem

Largest-text iPhone captures show the single-line title truncating (for example, “An offline reflection”) while its complete value remains stored. The writing surface should allow reading/editing that value with native text selection and without introducing another permanent toolbar action. Preserve the quiet date-free header and separate rich-text body.

## Proposed behavior

On iOS, use the native SwiftUI vertically growing TextField with label “Title”, plain style and the current semantic bold title font. Allow one through two visible lines; longer titles scroll within the native field during selection/editing. Preserve the full title string, ordinary autosave, native spelling/correction and selection. Do not shrink the text or impose a character limit. No new buttons or copy. Empty titles retain the “Title” placeholder. Read-only recovered/conflicted entries retain the existing editability rules.

The two-line cap keeps writing reachable at large text sizes. The title region must also respect a maximum of one third of the currently available editor height (which changes with the keyboard); verify that native vertical scrolling exposes the remainder rather than clipping it. Keep existing horizontal margins. The existing recovery notice can occupy at most half the available height, so inspect a recovered/read-only entry as well as a normal editor for body starvation. If SwiftUI does not scroll correctly under the height constraint, revise this design before implementation rather than accept clipped content.

macOS retains the existing native single-line field for this bounded change; live desktop accessibility still requires verification when the Mac is unlocked. No claim that this fixes every desktop title-size concern.

## Verification

Inspect actual iPhone normal/largest text, dark mode, title longer than two lines, keyboard-visible editing, and the title/body after relaunch. Confirm the entire stored value and that users can reach its beginning/end with native selection. Confirm body editing remains reachable with the keyboard, the title accessibility name/value remain complete, and the existing entry actions/formatting flow passes. Adapt UI-test queries to the native accessibility element type if multiline TextField exposes a text view; do not change product labels solely for tests. Avoid a new composition-only unit test.

## Review request

Independent review must assess whether the bounded multiline field and height limit give an intuitive native reading/editing experience at large sizes, especially with recovery notices and keyboard. Identify design changes needed before implementation.

## Revision 2 — shared header budget

Replace the separate iOS notice/title height caps with a single header region containing recovery notice, conflict notice, title and unsupported-format notice in their existing order. Its content is naturally sized, measured without duplicating controls, and its visible height is `min(intrinsic content height, available height / 2)`. One native ScrollView owns overflow. Short ordinary titles therefore consume only their current natural height; long titles/notices remain readable by scrolling the header. At least the other half remains available to the body before existing save-failure status. Keep the title at the existing margins, use the native scroll indicator and no new framing/background for the overall header. Existing recovery notice keeps its own background but does not introduce a nested scroller in this header.

For editable entries use one vertically expanding TextField, semantic title font and plain style, with no internal line cap; the surrounding header scrolls overflow. Return uses native Next and the existing editor focus command to begin body writing. Do not silently strip characters from pasted/stored titles. Preserve the single field instance across keyboard height changes: measure content height with a preference, constrain the scroll container, and do not switch between duplicate controls with ViewThatFits.

For noneditable entries use selectable Text of the full title (or the existing “Title” placeholder for an empty value), with wrapping and accessibility label “Title”/full value. It participates in the same header scroll area, so disabled text-field gestures are unnecessary. Body retains its existing read-only behavior. Mac stays unchanged in this bounded implementation.

When an unsaved-error notice is present, include it in the header overflow region so it cannot cover the remaining body; its current Export Entry… action and exact error copy remain. The header height cap is computed from the current GeometryReader viewport after keyboard avoidance, not the screen dimensions. No font scaling down or fixed minimum height that overflows a small viewport. Header/body remain separate native scroll areas, with accessible identity “Entry header” for the header region. Avoid an explicit accessibility grouping that hides its child controls.

Verify normal and largest text with keyboard, ordinary and overflow titles, read-only recovery and unsaved state. Confirm focus/caret reachability when typing at the end of a long title; if the native outer scrolling does not reveal the caret, revise before shipping. The layout should require no sheet solely to read an entry title.

## Revision 3 — observed submit behavior

The first largest-text test shows SwiftUI's vertical TextField inserting a newline when Next is pressed, without invoking the desired body-focus transition. Replace only the editable title control with a small native UITextView wrapper, retaining the reviewed shared header geometry and typography. It grows to its full fitting height with internal scrolling disabled, uses the OS preferred title font with bold trait and system spelling/correction defaults, and exposes Title as its accessibility name. Empty text uses the existing Title placeholder overlay, hidden from accessibility and hit testing.

Its delegate handles a keyboard newline as submit: invoke the existing body focus command and refuse insertion of that keyboard newline. Native paste is explicitly distinguished by a scoped flag around UITextView.paste so pasted newlines are retained, including a pasted single newline. Other replacements and existing text are unchanged. The wrapper updates external text without replacing the control or resetting selection on each keystroke; retain native undo/selection. No new actions or copy. Verify the actual keyboard transition and caret in the same required UI checks. This replaces the proposed SwiftUI field's ineffective onSubmit handling.

## Native paste correction — 2026-09-21

A hosted real UITextView test demonstrates that a paste containing only a newline invokes submit and loses the pasted newline. The paste override's synchronous guard ends before UIKit finishes loading the clipboard item.

Keep the approved appearance and Next behavior. Use UITextPasteDelegate's final insertion callback, scoped to the actual native text replacement, instead of guarding the initial paste request. Replace the provided UITextRange through UIKit's text-input API with the loaded plain string (titles are plain text), preserving selection and native undo; retain the delegate binding update. Do not read or manually load clipboard contents in production. No new copy, controls, or permissions. Verify multiline and newline-only actual paste, bound contents, no submission, and native undo. Marked-text and cross-entry undo still require separate evidence.
