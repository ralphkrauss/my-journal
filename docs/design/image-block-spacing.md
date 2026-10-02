# Space below images

Proposal for independent review before implementation. Owner report, 2026-09-28: an image inserted in an entry sits too close to the text below it on Mac, iPhone and iPad; the space above it looks right.

## Problem

Every text block uses the editor's paragraph style: 3 points of line spacing and 10 points after the paragraph. An image block is one attachment character followed by the line break that ends the block. Only the line break carries the paragraph style; the attachment has none, and the text system styles a paragraph by its first character, so the picture's line gets no line or paragraph spacing. Measured in the Mac editor with an image between two paragraphs: 10 points between the paragraph above and the picture, 0 points between the picture and the next paragraph. The iPhone App Store capture shows the same (the heading below the coffee photo touches it).

## Design

The picture's line gets the same paragraph style as a plain paragraph (3 points of line spacing, 10 points after), so an image is spaced like any other block: the next block starts as far below the picture as the picture starts below the block before it. This applies wherever an image block is shown: opening an entry, inserting an image (Insert Image, paste, drop), images that finish loading, the placeholder shown while an image loads or is unavailable, read-only views that use the same editor (version history, Recently Deleted), light and dark appearance, and every text size (the spacing is in points, like the text blocks' spacing).

- No new control, copy, menu or setting. Selection, the caret beside the picture, VoiceOver labels ("Image", the description, "Loading Image.") and keyboard navigation are unchanged.
- Nested images (an image inside a list item or quote in the Markdown) keep their current full-width, unindented placement; only the vertical spacing changes.
- Stored Markdown, sync, export and the document model are unchanged; the style exists only on screen.
- Inline images inside a paragraph are already styled with their paragraph and are unchanged.
- An entry that ends with an image gets the same space after it as one that ends with a paragraph (both carry 10 points after the last line).
- Reduced motion, increased contrast and reduced transparency aren't affected (static spacing only).

## Verification

A test in the shared editor tests (run on Mac and iOS) lays out an image between a paragraph and a heading as opened, and an image inserted in the middle of a paragraph, and requires the same room below the picture's line as above it (fails before the change: 0 vs 10 points), with the picture filling its line apart from the line spacing. Screenshots on iPhone, iPad and Mac in light and dark, before and after, through the App Store capture pipeline; the Writing and MobileParity UI test classes.
