# Start writing in a template's answer space

## Observed problem

The native everyday-writing route creates an entry from a template containing a heading question followed by an empty paragraph. After entering a title, keyboard Next focuses the native body at offset zero. The answer precedes the question. Captures and independent review in writing-workflow-review.md confirm the usability problem. No content was lost, but the initial writing position is wrong for a question template.

## Interaction

Only when creating a new entry from a default or explicitly selected template, initialize its body selection at the first existing empty paragraph block (all run text empty). Keep body typing attributes as ordinary paragraph text. Do not focus the body automatically or move focus away from the title. The existing Next action then focuses this already-positioned native editor; direct tapping still chooses the user's own insertion point.

This is a one-time selection initialization, not a document change or a rule applied every time the body receives focus. Returning to the title and pressing Next again preserves the user's later selection. Subsequent model refreshes, image arrivals, font/appearance changes and body edits must not reapply it. The request must also remain consumed if SwiftUI recreates the native editor. Leaving the entry or locking cancels an unconsumed request; app relaunch never recreates it.

Blank entries and templates without an empty paragraph keep existing initial behavior. Do not insert an extra paragraph, infer answers from question wording, change a template, change opening behavior for existing entries, or add UI/copy. Empty paragraph blocks between multiple prompts are valid targets; whitespace-only text is content and is not an empty block. Preserve all prompt text, formatting and image references.

## Implementation boundary

Use a MainActor-owned one-shot request keyed by new entry ID and chosen empty block ID, passed only to the main editor. Consume it on that item's first native render. Resolve the offset against attributed block IDs; a trailing empty block has no attributed character, so its valid insertion offset is the end of the rendered document. This avoids counting raw Unicode characters or guessing list/image marker widths. Reset plain typing attributes after assigning the initial selection, because native selection changes may inherit the preceding heading's font.

## Accessibility and verification

No new controls, labels or focus announcement. Continue native text sizing, spelling and keyboard behavior. Verify actual macOS/iOS native selection, body typing style and one-time consumption across updates/recreation, including a blank block after an image and a nonterminal answer block. Update the meaningful iOS writing route to require question first, then answer in a paragraph, template unchanged, journal-scoped search and exact retained writing after relaunch. Inspect normal and largest-text actual captures; no VoiceOver or physical/minimum-OS claim from these checks.
