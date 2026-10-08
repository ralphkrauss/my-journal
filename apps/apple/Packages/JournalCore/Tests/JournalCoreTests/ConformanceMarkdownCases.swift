import Foundation

/// The Markdown bodies of protocol/conformance/markdown/documents-v1.json, one per construct the format supports.
enum ConformanceMarkdownCases {
    static let photo = "01234567-89ab-4cde-8fab-0123456789ab"
    static let cup = "fedcba98-7654-4321-8fed-cba987654321"

    /// A name, a note and the stored Markdown.
    static let documents: [(name: String, note: String, markdown: String)] = [
        ("empty", "No text at all.", ""),
        (
            "text-without-final-newline",
            "The final line ending is part of the text, so it is neither added nor removed.", "Just text"
        ),
        (
            "headings", "ATX headings of every level; a closing sequence of hashes is syntax.",
            "# Title\n\n## Section\n\n### Three\n\n###### Six ##\n\nBody.\n"
        ),
        (
            "setext-headings", "Underlined headings keep their spelling until edited.",
            "Heading\n=======\n\nSub\n---\n\nBody\n"
        ),
        (
            "inline-marks", "Bold, italic, both, strikethrough, underline (inert HTML) and code.",
            "Plain **bold**, *italic*, ***both***, ~~struck~~, <u>underlined</u> and `code`.\n"
        ),
        (
            "emphasis-separator", "An inert comment keeps adjacent emphasis apart without adding visible text.",
            "**bold**<!-- -->*italic*\n"
        ),
        (
            "bullet-lists", "Bullet lists, nesting and the markers other editors use.",
            "- One\n- Two\n  - Nested\n- Three\n\n* Star\n* List\n"
        ),
        (
            "ordered-lists", "Ordered lists keep their first number and their delimiter.",
            "7. Seven\n8. Eight\n\n1) one\n2) two\n"
        ),
        ("task-lists", "GFM task items, open and done.", "- [ ] Open task\n- [x] Done task\n"),
        ("quote", "A single-paragraph quote.", "> Quoted *text*\n"),
        (
            "code-fence", "A fenced block with a language and a longer fence.",
            "```swift\nlet x = 1\n```\n\n````\n```\n````\n"
        ),
        ("thematic-break", "A rule between paragraphs.", "Above\n\n---\n\nBelow\n"),
        (
            "table", "A GFM table with alignments, a pipe in a cell and a link in a cell.",
            "| Name | Value |\n| :--- | ---: |\n| a\\|b | [link](<https://example.com/a_(b)>) |\n"
        ),
        (
            "links", "Inline link with a title, angle-bracket destination and an autolink.",
            "See [the docs](https://example.com/a_(b) \"Title\"), [y](https://example.com/path?q=1&r=2) and <https://example.com>.\n"
        ),
        (
            "reference-links", "A reference definition keeps its place and its title.",
            "[site]: https://example.com \"A title\"\n\nUse [the link][site] and [again][site].\n"
        ),
        (
            "images", "A block image, an inline image with a title and a remote image (never loaded).",
            "![Photo](attachments/\(photo))\n\nInline ![a cup](attachments/\(cup) \"Title\") here.\n\n![Remote](https://example.com/a.png)\n"
        ),
        ("line-breaks", "A hard break (two spaces or a backslash) and a soft break.", "One  \nTwo\\\nThree\nsoft\n"),
        (
            "html", "Raw HTML is shown as source text and never run.",
            "<details>\n<summary>More</summary>\n</details>\n\nInline <b>html</b> stays text.\n"
        ),
        (
            "escapes", "Backslash escapes are literal text.",
            "\\*not bold\\* and 1\\. not a list and \\# not a heading\n"
        ),
        (
            "unicode",
            "Composed and decomposed characters, an emoji sequence and right-to-left text are kept as written.",
            "Café, cafe\u{301}, 👩‍👩‍👧 and 日記\n\n> שלום **עולם** مرحبا\n"
        ),
        ("crlf", "Windows line endings are kept.", "a\r\n\r\nb\r\n\r\n- c\r\n- d\r\n"),
        ("cr-only", "Old Mac line endings are kept.", "a\rb\n\nc\n\nd"),
        (
            "leading-and-trailing-space", "Blank lines and trailing spaces are kept.",
            "\n\n  Indented start\n\nText   \nmore\n\n\n"
        ),
        (
            "nested-list-with-paragraph", "A list item that holds a nested list and a second paragraph.",
            "[site]: https://example.com \"A title\"\n\n7. First\n   - Nested **item**\n\n   Continued paragraph.\n\nLast [link][site].\n"
        ),
    ]

    /// Image references: the Markdown, then nothing else; the expected values come from the reference reader.
    static let images: [(name: String, note: String, markdown: String)] = [
        ("block-image", "An image on its own line.", "![Photo](attachments/\(photo))\n"),
        (
            "inline-image-with-title", "An image inside text, with a title.",
            "Text ![a cup](attachments/\(cup) \"Title\") text\n"
        ),
        (
            "two-references-to-one-image", "Listed once, in order of first appearance.",
            "![a](attachments/\(photo)) ![b](attachments/\(cup)) ![c](attachments/\(photo))\n"
        ),
        ("image-in-link", "An image inside a link.", "[![Photo](attachments/\(photo))](https://example.com)\n"),
        (
            "image-in-table-cell", "An image in a table cell.",
            "| Picture |\n| --- |\n| ![Photo](attachments/\(photo)) |\n"
        ),
        (
            "reference-definition", "An image reached through a reference definition.",
            "![Map][map]\n\n[map]: attachments/\(photo)\n"
        ),
        (
            "reference-definition-shared-with-a-link",
            "The definition is also used by a text link, so it can't be rewritten alone.",
            "![Map][map] and [open it][map]\n\n[map]: attachments/\(photo)\n"
        ),
        ("code-span", "A path quoted in code is text.", "`attachments/\(photo)`\n"),
        ("code-block", "A path in a fenced block is text.", "```\n![x](attachments/\(photo))\n```\n"),
        ("link-not-image", "A link to an attachment path is not an image.", "[file](attachments/\(photo))\n"),
        ("relative-prefix", "Only the exact path counts: no ./ prefix.", "![x](./attachments/\(photo))\n"),
        ("query", "No query.", "![x](attachments/\(photo)?size=large)\n"),
        ("fragment", "No fragment.", "![x](attachments/\(photo)#top)\n"),
        ("file-extension", "No suffix.", "![x](attachments/\(photo).png)\n"),
        ("percent-encoding", "No percent-encoding.", "![x](attachments/%30\(photo.dropFirst()))\n"),
        ("upper-case-path", "The directory name is lower case.", "![x](ATTACHMENTS/\(photo))\n"),
        ("not-a-uuid", "A name that isn't a UUID.", "![x](attachments/photo.png)\n"),
        ("remote-image", "A remote image is not an attachment.", "![x](https://example.com/attachments/\(photo))\n"),
    ]
}
