# Space below images review

## Independent proposal review — 2026-09-28

**Approved with conditions.** The reviewer checked the proposal against `RichText.blocks`, `ImagePresentation.update`, both `.image` insertion paths, the pasted/dropped image import and the before screenshot. The diagnosis is correct: only the line break after the picture carried the paragraph style, so the picture's line got no spacing. The fix is a paragraph style only: no UI or copy, stored Markdown untouched. `ImagePresentation.update` replaces only the attachment, so the style survives an image finishing loading, a placeholder being replaced, and undo/redo. The app uses TextKit 1 throughout, so a layout-manager test reflects real rendering.

Material findings:

1. The test measured line fragments, not the visible picture. If the attachment's line held a default font's descent below the picture, equal measured gaps could still look unequal, most at large text sizes. Measure the drawn picture, or make the descent predictable, and check by eye at small and large text sizes.
2. The owner's case, a heading right below a photo, wasn't tested, nor inserting in the middle of a paragraph.

Minor: the claim that an entry ending with an image is unchanged needed checking or rewording; the fixed 10/3-point spacing doesn't scale with text size, which matches body paragraphs and is fine for this fix; unindented nested images match current behavior; nothing changes for accessibility; include dark mode and a large text size in the screenshots.

## Resolution

1. The test now also requires the picture's line to be exactly the picture's drawn height plus the line spacing, on Mac and iOS: the line holds no hidden descent (measured 140 points for a 140-point picture before the change, 143 with the 3-point line spacing after it). Visible check in the captures below.
2. The opened case has a heading right below the image; a second case inserts an image in the middle of a paragraph. Both require 10 points above and below; before the change both measure 0 points below.

The last-block claim is reworded: an entry ending with an image gets the same 10 points after it as one ending with a paragraph. Spacing that scales with text size is left for a later, separate change.

## Implementation evidence — 2026-09-28

- `EditorChangeTests.testAnImageLeavesAsMuchRoomBelowItAsAbove` passes on Mac (JournalMacTests, 145 tests) and on the iPhone 17 Pro Max simulator (JournalIOSTests, 144 tests); without the change it fails on the Mac with 0 points below against 10 above. `WritingWorkflowUITests` and `MobileParityUITests` pass on iPhone.
- Inspected the App Store captures before (previous set) and after, on iPhone, iPad and Mac, light and dark: the heading below the photo in "Slow Sunday" and the checklist below the photo in "Porto, day two" now sit as far below the picture as the paragraph above it; in "Bread, attempt four" on iPad the table no longer touches the photo.
- Inspected the iPhone editor at the Accessibility Large text size, light and dark: the picture keeps a clear margin above and below. The spacing stays at 10 points, like the body paragraphs.
