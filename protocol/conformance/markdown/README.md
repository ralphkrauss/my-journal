# markdown

The stored Markdown body ([Markdown and Images](../../records.md#markdown) in the records contract). A client's editor may represent a body in blocks; what is stored is the Markdown text, and unchanged blocks keep their bytes.

| File | Covers | Produced by |
| --- | --- | --- |
| `documents-v1.json` | 24 bodies, one per construct: headings, marks, lists, tasks, quotes, code, rules, tables, links, reference links, images, line breaks, HTML, escapes, Unicode, CRLF and CR line endings, blank lines | Expected values from the Swift reader and writer |
| `images-v1.json` | 18 bodies with image references: which attachments they refer to and the body with the first one pointed at `attachments/<id>.png` as Export as Markdown does | Swift |

## Documents (`documents-v1.json`)

`expected` has:

- `keepsText`: always `true`. Whatever a client makes of a body, the text it stores is the text it read, byte for byte (including CRLF, CR, trailing spaces, blank lines and reference definitions), until a block is edited. This is the rule other clients must pass.
- `blocks`: how the reference reader sees the body in a neutral vocabulary: `paragraph`, `heading` (`level` 1 to 6), `quote`, `listItem` (`list` of `bullet`, `numbered` or `task`; `checked`, `depth`, `number`), `codeBlock` (`language`), `html`, `table` (`alignments`, cell texts), `image` (`attachment` and `description`) and `rule`. A block's `runs` are its inline pieces: `text` and the members that are set among `bold`, `italic`, `underline` (the inert `<u>`), `strikethrough`, `code`, `html`, `link`, `linkTitle`, `break` (`soft` or `hard`), `image` and `imageTitle`. A client with its own editor model must read the same structure; it needn't use these names.
- `requiresSource`: whether the reference reader found content it can't show in blocks; such a body is edited as Markdown source.
- `canonical`: the Markdown the reference writer writes for those blocks, or `null`. A client's writer needn't match it byte for byte, but what it writes must read back as the same `blocks` (`canonicalReadsBackAsTheSameBlocks`). Note the writer's spelling is not the stored text: it separates list items with blank lines and writes reference links inline.

## Image references (`images-v1.json`)

An image refers to an attachment only when its destination is exactly `attachments/` and a UUID. `expected.imageIDs` lists the attachments a body refers to, in order of first appearance, each once. Paths quoted in code, links to an attachment path, `./attachments/…`, a query, a fragment, a file extension, percent-encoding, another directory name, another host and names that aren't UUIDs are not image references. `rewrittenToPng` is the body with the first referenced attachment written as `attachments/<id>.png`, or `null` when that image shares a reference definition with a text link and so can't be rewritten alone.
