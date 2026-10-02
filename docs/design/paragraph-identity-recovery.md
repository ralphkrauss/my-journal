# Paragraph identity after native prefix replacement

## Observed problem

The hosted iOS appearance/writing test replaces “Paragraph 18” at the beginning of an existing paragraph using native insertText, changes light→dark→light, then undoes/redoes. Text, selection, focus, viewport and appearance checks pass. Undo restores the exact original document. Redo reproduces the text but generates a different block ID. Evidence: /tmp/journal-appearance-writing.log, ImageViewportTests line154. The remaining paragraph text still carries the original journalBlockID; the new prefix does not. RichText.textDocument reads identity from only the first character.

## Proposed behavior and implementation

Preserve an existing paragraph's identity when replacing its prefix leaves attributed text from that paragraph. In textDocument, find the first valid journalBlockID across that paragraph's native attributed content range (excluding terminators), using the first character when valid and falling back to remaining attributes. Keep the existing fresh-ID behavior for a paragraph without any valid identity and existing duplicate-ID normalization for split paragraphs. Do not infer identity from another paragraph, image or neighboring record. No text/format/attachment mutation or text-storage replacement, selection change, extra undo action, or UI/copy change.

This bounded correction does not claim stable IDs for an entirely new paragraph before its representation is rendered, nor redesign split/join identity policy. The appearance test should continue requiring exact draft preservation across appearance and exact original/edited documents across undo/redo. Add a small cross-platform native attributed-text regression only if needed to establish fallback cannot borrow identity across paragraph boundaries; avoid asserting internal call sequences.

## Review and verification

Independent review before production change. Validate the first-ID selection against split/join behavior, images and malformed values. Run the failing native test and affected rich-text tests, strict format/lint and Apple checks if production changes. Inspect the two actual hosted-editor captures; distinguish hosted trait changes from System Settings interaction and VoiceOver. Packages would need refresh after a production correction; do not claim existing package manifests cover later sources.
