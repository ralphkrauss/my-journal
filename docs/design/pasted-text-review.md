# Review: pasting text from other apps

An independent design agent reviewed [pasted-text.md](pasted-text.md) against the requirements (owner decision 6, native conventions, accessibility, copy), without the implementation. Outcome of each material finding:

| Finding | Outcome |
| --- | --- |
| Paste and Match Style is needed as a way out of wrong guesses. | Already in the Mac Edit menu; it read the text view's own way and could leave text the entry didn't save. It now pastes the plain text, whose lines take the style of the line they land in. Recorded in the design. |
| Pages with frames, background pictures or media fell back to plain text. | Changed: those references are removed and the page keeps its structure. Plain text is pasted only if something that could be loaded remains. |
| Size alone promotes lead paragraphs and pull quotes to headings. | Changed: only paragraphs of up to 100 characters can be headings. Pasted text has no semantic heading marks once read, so size stays the signal; a paste in one size has no headings. |
| Monospaced text alone becomes code (fixed-width Mail). | Kept: code editors, Terminal and Notes copy code this way, and fixed-width Mail is an opt-in setting. Recorded as a known limit. |
| Pictures imported later were a separate undo step. | Changed: pictures are imported before the text is inserted, so they arrive with it in one undo step. (Filling them in afterwards was tried first; iOS discards the undo history when text changes outside an undo step.) |
| Web pictures are dropped without notice. | Kept for privacy (nothing is loaded); recorded in the design and reported to the owner. Alt text isn't added, since it is often a file name. |
| Blank lines in plain text. | Kept as written; now stated in the design. |

Minor findings: a list pasted on an empty line stays a list (first block's kind wins); Word lists keep their starting number; checklist ticks are kept; the quote, iPhone table and web picture limits are reported to the owner rather than left in a footnote; highlights are listed under "Left out".
