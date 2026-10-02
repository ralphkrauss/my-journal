# Readable export text fidelity

## Problem and scope

The HTML readable export applies preserved whitespace only to paragraphs. Headings, subheadings, list items and the entry title collapse repeated spaces and embedded newlines in browser rendering. Long unbroken text can also overflow a narrow viewport. These are document-fidelity defects; no app navigation or export-sheet changes are proposed.

## Proposed rendering

Keep the current neutral, system-font HTML document, date, title, semantic headings/lists, inline formatting, embedded images, color-scheme rules and content security policy. Apply `white-space: pre-wrap` to h1, h2, h3, p and li. Apply `overflow-wrap: anywhere` to the body so long links or words fit narrow windows without deleting characters. Preserve ordinary list indentation and existing spacing. No new copy, controls, external resources, scripts or fonts. Empty blocks retain their existing br behavior.

## Accessibility and verification

Semantic HTML and text remain selectable and readable by assistive technology. Native browser zoom and preferred color scheme continue to work. Verify a synthetic export containing repeated spaces, embedded newlines, headings/subheadings, lists, styled runs, a long link and an embedded PNG in an actual browser at narrow and wide widths. Check that the complete text and link/image attributes survive export, no horizontal document overflow occurs at narrow width, and repeated spaces/newlines are rendered consistently. Existing unsafe-markup and unknown-field export tests remain required. This does not claim live screen-reader verification.
