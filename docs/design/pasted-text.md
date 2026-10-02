# Pasting text from other apps

Owner decision 6 (1 October 2026): keep lists, headings, quotes and code when pasting formatted text, but only if it works without glitches, checked against common sources with screenshots. This record describes the behaviour that was checked. There is no new control or copy; it changes what Paste (⌘V, Edit ▸ Paste, the iOS edit menu) and drops of text do in the entry body.

## What arrives

Text from another app becomes the entry's own blocks, in the entry's own fonts, sizes and colours, as in Notes:

- Headings (short paragraphs, up to 100 characters, set clearly larger than the text around them), bulleted, numbered and nested lists, Notes checklists, code (text set entirely in a monospaced font, including its blank lines), tables (Mac), bold, italic, underline (not a link's), strikethrough, inline code (monospaced words) and web or email links.
- Left out: fonts, sizes, colours, highlights (Markdown has none), the empty lines other apps use for spacing (the entry spaces its own paragraphs), links to part of a web page or to scripts (their text stays), and list bullets or numbers written as text (Word), which become list items.
- Pictures copied with text (Safari, Notes, Pages on the Mac; apps other than browsers on iPhone) are imported first and arrive with the text, where they were, as the entry's own images.
- Nothing a web page refers to is loaded, for privacy: its pictures, media, frames, scripts, style sheets and background pictures are left out and the rest keeps its structure. If anything that could be loaded remains, the page's plain text is pasted.
- Plain text, including Markdown, is pasted as written, one paragraph per line, including its empty lines. Markdown characters stay characters, as typed addresses stay plain text (owner decision 2).
- Text set entirely in a monospaced font is code, which is what code editors, Terminal and Notes' monostyled text copy. Mail set to show plain-text messages in a fixed-width font copies them the same way, so such a message arrives as code.
- Quotations from web pages and Mail arrive as plain paragraphs: Safari's RTF and the iPhone's reading of a page don't mark them. On iPhone a copied table arrives as its plain text, a row on each line, and pictures copied together with a web page's text are left out.

## Where it goes

- The first pasted paragraph joins the paragraph at the insertion point, as in every editor; the rest of that paragraph follows the pasted text on its own line when the copied text ended with a line break, and otherwise continues the last pasted line.
- Pasting on an empty line, such as a template's answer line, fills it; no empty line is left behind. Pasting at the end of a paragraph leaves no empty line either.
- Lines of plain text pasted into a list item continue the list, as typing them with Return does. Anything pasted into a code block becomes code text in that block.
- Text joining a heading takes the heading's size.
- The insertion point ends after the pasted text and is scrolled into view. One Undo restores the entry and the selection exactly, pictures included. Should writing go on while pictures import, the paste goes where it was made.
- Paste and Match Style (Mac Edit menu, ⌥⇧⌘V) pastes the plain text, whose lines take the style of the line they land in.
- In the Markdown source (View Source), formatted text is inserted as Markdown and plain text as it is.

## Accessibility

No new controls. VoiceOver reads pasted blocks as it reads typed ones (headings, list items, code). Pasted text follows the entry's Dynamic Type size, Increase Contrast and Dark Mode because none of the source's fonts or colours are kept.

## Review

[pasted-text-review.md](pasted-text-review.md) records the independent review and what changed.
