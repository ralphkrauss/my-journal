import XCTest

@testable import JournalCore

/// Stored Markdown must keep every word and image reference, and a rich edit may only rewrite the blocks it changed.
final class MarkdownFidelityTests: XCTestCase {
    private static let image = "attachments/00000000-0000-0000-0000-000000000001"

    /// Shapes people write, including ones the writer spells differently. Parsing and writing must keep every
    /// block, and an edit must leave every other block's bytes alone.
    private static let samples = [
        "# Heading\n\nParagraph with **bold**, *italic*, ~~struck~~, <u>underlined</u> and `code`.\n",
        "- One\n\n  - Nested\n\n- [ ] Open task\n\n- [x] Done task\n\n3. Third\n",
        "| Name | Value |\n| :--- | ---: |\n| a\\|b | [link](<https://example.com/a_(b)>) |\n",
        "````swift\nlet fence = \"```\"\n````\n\n<details>\n<summary>More</summary>\n</details>\n",
        "See [the docs](https://example.com/a_(b) \"Title\") and ![Sketch](\(image) \"Plan\").\n",
        "Café, naïve, e\u{301}, 👩‍👩‍👧 and \\*️⃣\\*️⃣\n\n> שלום **עולם** مرحبا\n\n![Photo](\(image))\n\n---\n",
        "Heading\nacross lines\n===\n\nOne line\\\n\\\nafter an empty line\n",
        "- a\n- b\n  - nested\n- c\n", "* star\n* list\n", "-   wide\n    - nested\n", "1) one\n2) two\n",
        "1. [ ] ordered task\n2. [x] done\n", "a\r\n\r\nb\r\n\r\n- c\r\n- d\r\n", "a\rb\n\nc\n\nd",
        "| A |\n|---|\n| x \\| y |\n", "# Title ##\nBody\n", "> a\n>\n> b\n", "Text   \nwith trailing spaces\n",
        "[ref]: https://example.com\n\nUse [the link][ref].\n", "- [ ] ![Receipt](\(image))\n- [x] Paid\n",
        "Intro:\n- item\n", "1. a\n2. b\n3. c\n", "- a\n---\n", "Intro\n| A | B |\n|---|---|\n| c | d |\n\nAfter\n",
        "[r]: https://example.com\nUse [the link][r].\n\nMore [again][r].\n",
    ]

    private func reopen(_ document: JournalDocument) throws -> JournalDocument {
        try JournalCoding.decoder().decode(JournalDocument.self, from: JournalCoding.encoder().encode(document))
    }

    /// What a reader sees: each block's kind, list depth and content, without empty paragraphs.
    private func visible(_ document: JournalDocument, depth: Bool = true) -> [String] {
        document.blocks.compactMap { block in
            let runs = block.runs.map { run in run.imageSource.map { "![\(run.text)](\($0))" } ?? run.text }.joined()
            // A paragraph holding only an image reads back as an image block.
            let only = block.runs.count == 1 && block.kind == "paragraph" ? block.runs.first : nil
            let inline = only.flatMap { run in run.imageAttachmentID.map { "\($0): \(run.text)" } }
            let image = block.attachmentID.map { "\($0): \(block.imageDescription ?? "")" } ?? inline
            let content = block.table?.text ?? image ?? runs
            if content.isEmpty && ["paragraph", "quote"].contains(block.kind) { return nil }
            let kind = inline == nil ? block.kind : "image"
            return "\(kind) \(depth ? block.listIndents?.count ?? 0 : 0): \(content)"
        }
    }

    /// Whether the next block is nested inside this one, so removing or restyling it would move that child.
    private func hasChildren(_ document: JournalDocument, _ index: Int) -> Bool {
        index + 1 < document.blocks.count
            && (document.blocks[index + 1].listIndents?.count ?? 0) > (document.blocks[index].listIndents?.count ?? 0)
    }

    /// Types `text` at the end of a block, as the editor's next rich edit would report it.
    private func typing(_ text: String, into index: Int, of document: JournalDocument) -> JournalDocument {
        var edited = document
        var block = edited.blocks[index]
        if var table = block.table, table.rows.count > 1 {
            table.replaceCell(row: 1, column: 0, runs: table.rows[1][0] + [TextRun(text)])
            block.table = table
        } else if let last = block.runs.lastIndex(where: { $0.imageSource == nil && $0.breakKind == nil }) {
            let current = block.runs[last].text
            let trimmed = current.hasSuffix("\n") ? String(current.dropLast()) : current
            block.runs[last].text = trimmed + text + (trimmed == current ? "" : "\n")
        } else {
            block.runs.append(TextRun(text))
        }
        edited.blocks[index] = block
        return document.applyingRichEdit(edited)
    }

    private func restyled(_ document: JournalDocument, block index: Int, as kind: String) -> JournalDocument {
        var edited = document
        // Like Format > Body, restyling leaves tables, images and code alone.
        guard edited.blocks[index].table == nil, !["image", "codeBlock", "html"].contains(edited.blocks[index].kind)
        else { return document }
        edited.blocks[index].kind = kind
        if !["bullet", "numbered", "task", "checked"].contains(kind) {
            // Format > Body and Shift-Tab on a top-level item drop the list structure, as the editor does.
            edited.blocks[index].markdownPrefix = nil
            edited.blocks[index].markdownContinuation = nil
            edited.blocks[index].listIndents = nil
            edited.blocks[index].listNumber = nil
        }
        return document.applyingRichEdit(edited)
    }

    func testStyleChangeBesideSingleNewlineMarkdownKeepsBlocksApartWhileTyping() throws {
        let cases: [(source: String, index: Int, kind: String)] = [
            ("- a\n- b\n- c", 1, "paragraph"), ("# Title\nBody", 0, "paragraph"), ("Intro:\n- item", 1, "paragraph"),
            ("1. a\n2. b\n3. c", 0, "paragraph"), ("- a\n---\n", 0, "paragraph"), ("# Title ##\nBody", 0, "paragraph"),
            ("> a\n> b\n\nAfter", 0, "bullet"),
        ]
        for (source, index, kind) in cases {
            var document = restyled(try reopen(JournalDocument(markdown: source)), block: index, as: kind)
            XCTAssertEqual(visible(try reopen(document)), visible(document), source)
            for letter in ["x", "y"] {
                document = typing(letter, into: index, of: document)
                XCTAssertEqual(visible(try reopen(document)), visible(document), source + " then " + letter)
            }
        }
    }

    func testTextTypedIntoAReopenedEmptyQuoteStaysSeparate() throws {
        let original = JournalDocument(blocks: [DocumentBlock(kind: "quote"), DocumentBlock(runs: [TextRun("After")])])
        let document = typing("Text", into: 0, of: try reopen(original))
        XCTAssertEqual(visible(try reopen(document)), ["paragraph 0: Text", "paragraph 0: After"])
        XCTAssertEqual(
            visible(try reopen(typing("!", into: 0, of: document))), ["paragraph 0: Text!", "paragraph 0: After"])
    }

    func testCanonicalMarkdownIsWrittenBackByteForByte() throws {
        for source in Self.samples {
            let document = JournalDocument(markdown: source)
            XCTAssertFalse(document.requiresMarkdownSource, source)
            XCTAssertEqual(try reopen(document), document, source)
            // Writing the blocks gives the canonical spelling, which keeps what a reader sees and reads back exactly.
            let canonical = JournalDocument(blocks: document.blocks).markdown
            let reread = JournalDocument(markdown: canonical)
            XCTAssertEqual(visible(reread), visible(document), canonical)
            XCTAssertEqual(JournalDocument(blocks: reread.blocks).markdown, canonical)
        }
    }

    func testEditingOneBlockRewritesOnlyThatBlock() throws {
        for source in Self.samples {
            let document = try reopen(JournalDocument(markdown: source))
            let original = try XCTUnwrap(document.markdownBlockSegments, source)
            for index in document.blocks.indices where !document.blocks[index].runs.isEmpty {
                let edited = typing("!", into: index, of: document)
                let segments = try XCTUnwrap(edited.markdownBlockSegments, source)
                for other in segments.indices where other != index {
                    XCTAssertEqual(segments[other], original[other], "\(source) block \(index)")
                }
                XCTAssertEqual(visible(try reopen(edited)), visible(edited), "\(source) block \(index)")
            }
        }
    }

    func testStructuralEditsKeepEveryOtherBlockIntact() throws {
        for source in Self.samples {
            let document = try reopen(JournalDocument(markdown: source))
            // Moving a nested block out of its parent is the editor's job, so parents are left in place here.
            for index in document.blocks.indices where !hasChildren(document, index) {
                var inserted = document
                inserted.blocks.insert(DocumentBlock(runs: [TextRun("New")]), at: index + 1)
                var removed = document
                removed.blocks.remove(at: index)
                let edits = [
                    document.applyingRichEdit(inserted), document.applyingRichEdit(removed),
                    restyled(document, block: index, as: "paragraph"), restyled(document, block: index, as: "bullet"),
                ]
                for edited in edits {
                    XCTAssertEqual(visible(try reopen(edited), depth: false), visible(edited, depth: false), source)
                }
            }
        }
    }

    /// An empty item directly before an item nested under it stays an empty item of its own: written as its marker
    /// alone on its line, read back as an item with the nested list below it, as CommonMark and other apps read it.
    /// Content on the marker's own line ("- - text") still reads as one nested item.
    func testAnEmptyItemBeforeANestedItemKeepsItsPlace() throws {
        for kind in ["bullet", "numbered", "task", "checked"] {
            var nested = DocumentBlock(kind: "bullet", runs: [TextRun("Nested")])
            nested.listIndents = [kind == "numbered" ? 3 : 2]
            nested.markdownPrefix = kind == "numbered" ? "   " : "  "
            let blocks = [
                DocumentBlock(kind: kind, runs: [TextRun("Before")]), DocumentBlock(kind: kind), nested,
                DocumentBlock(kind: kind, runs: [TextRun("After")]),
            ]
            let markdown = JournalDocument(blocks: blocks).markdown
            let read = JournalDocument(markdown: markdown)
            XCTAssertEqual(
                read.blocks.map { "\($0.kind) \($0.listIndents ?? []) \($0.runs.map(\.text).joined())" },
                ["\(kind) [] Before", "\(kind) [] ", "bullet \(nested.listIndents ?? []) Nested", "\(kind) [] After"],
                markdown.debugDescription)
            XCTAssertEqual(read.markdown, markdown, "Written back byte for byte")
        }
        // Emptying an item of a loose list, above its nested item.
        let loose = JournalDocument(markdown: "- One\n\n- Two\n\n  - Nested\n\n- Three\n")
        var emptied = loose
        emptied.blocks[1].runs = []
        let saved = loose.applyingRichEdit(emptied)
        XCTAssertEqual(
            JournalDocument(markdown: saved.markdown).blocks.map {
                "\($0.kind) \($0.listIndents ?? []) \($0.runs.map(\.text).joined())"
            },
            ["bullet [] One", "bullet [] ", "bullet [2] Nested", "bullet [] Three"], saved.markdown.debugDescription)
        let sameLine = JournalDocument(markdown: "- - Nested")
        XCTAssertEqual(sameLine.blocks.map(\.kind), ["bullet"])
        XCTAssertEqual(sameLine.markdown, "- - Nested")
    }

    func testRewrittenListItemsKeepTheirMarkerAndIndentation() {
        let cases = [
            ("* star\n* list\n* end\n", 1, "* star\n* list!\n* end\n"),
            ("-   wide\n    - nested\n", 1, "-   wide\n    - nested!\n"),
            ("1) one\n2) two\n", 1, "1) one\n2) two!\n"),
            ("1. [ ] ordered task\n2. [x] done\n", 1, "1. [ ] ordered task\n2. [x] done!\n"),
            ("9. i\n10. j\n", 1, "9. i\n10. j!\n"),
        ]
        for (source, index, expected) in cases {
            XCTAssertEqual(typing("!", into: index, of: JournalDocument(markdown: source)).markdown, expected)
        }
    }

    func testMarksWithEdgeSpacesOrPunctuationBesideWordsSurviveReopening() throws {
        var code = TextRun("code", bold: true)
        code.code = true
        var struck = TextRun("x", bold: true)
        struck.strikethrough = true
        let cases: [[TextRun]] = [
            [TextRun("I am"), TextRun(" very", bold: true)], [TextRun("very ", bold: true), TextRun("happy")],
            [TextRun("a"), TextRun("(very)", italic: true), TextRun("b")], [TextRun("a"), struck, TextRun("b")],
            [TextRun("a"), code, TextRun("b")], [TextRun("a"), TextRun("*", italic: true), TextRun("b")],
            [TextRun("Wow!"), TextRun("site", link: "https://example.com")],
        ]
        // A space beside bold or italic text may be written outside the marks; every other character keeps them.
        func marks(_ runs: [TextRun]) -> [String] {
            runs.flatMap { run in
                run.text.map { character in
                    let mark = character == " " ? "" : "\(run.bold) \(run.italic)"
                    return "\(character) \(mark) \(run.strikethrough) \(run.code) \(run.link ?? "")"
                }
            }
        }
        for runs in cases {
            let document = try reopen(JournalDocument(blocks: [DocumentBlock(runs: runs)]))
            let markdown = JournalDocument(blocks: [DocumentBlock(runs: runs)]).markdown
            XCTAssertEqual(marks(document.blocks.flatMap(\.runs)), marks(runs), markdown)
        }
    }

    func testSpacesBesideFormattedTextStayReadableInTheSource() throws {
        let cases: [([TextRun], String)] = [
            ([TextRun("Plain "), TextRun("bold", bold: true), TextRun(" after")], "Plain **bold** after"),
            ([TextRun("Some "), TextRun("very ", bold: true), TextRun("happy")], "Some **very** happy"),
            (
                [TextRun("see "), TextRun("a link", link: "https://example.com"), TextRun(".")],
                "see [a link](<https://example.com>)."
            ),
            (
                [TextRun("an "), TextRun("underlined", underline: true), TextRun(", "), TextRun("x", italic: true)],
                "an <u>underlined</u>, *x*"
            ),
            ([TextRun("a "), TextRun(" both ", bold: true, underline: true), TextRun("b")], "a <u> **both** </u>b"),
            // At a line's edges the parser would strip a space, so it is still written as a reference there.
            ([TextRun(" lead "), TextRun("bold ", bold: true)], "&#32;lead **bold&#32;**"),
        ]
        for (runs, expected) in cases {
            let document = JournalDocument(blocks: [DocumentBlock(runs: runs)])
            XCTAssertEqual(document.markdown, expected + "\n\n")
            let reopened = try reopen(document)
            XCTAssertEqual(reopened.text, document.text, expected)
            XCTAssertFalse(reopened.requiresMarkdownSource, expected)
        }
        // Source written before this change keeps reading the same.
        let stored = JournalDocument(markdown: "Plain&#32;**bold**&#32;after\n\nsee&#32;[<u>a link</u>](<https://e.x>)")
        XCTAssertEqual(stored.blocks[0].runs.map(\.text), ["Plain ", "bold", " after"])
        XCTAssertEqual(stored.blocks[0].runs.map(\.bold), [false, true, false])
        XCTAssertEqual(stored.blocks[1].runs.map(\.text), ["see ", "a link"])
    }

    func testSyntaxInsideEmojiAndTableCellsStaysLiteral() throws {
        var backtick = TextRun("a`\u{301}b")
        backtick.code = true
        var pictured = TextRun("p|q")
        pictured.imageSource = Self.image
        let rows: [[[TextRun]]] = [
            [[TextRun("Head")]], [[TextRun("x", link: "https://example.com/a|b"), TextRun(" and "), pictured]],
        ]
        var table = DocumentBlock(kind: "table")
        table.table = DocumentTable(rows: rows, alignments: [])
        let blocks = [DocumentBlock(runs: [TextRun("Rating *️⃣*️⃣*️⃣ ")]), DocumentBlock(runs: [backtick]), table]
        let document = try reopen(JournalDocument(blocks: blocks))
        XCTAssertEqual(document.blocks.map(\.kind), ["paragraph", "paragraph", "table"])
        XCTAssertEqual(document.blocks[0].runs.map(\.text), ["Rating *️⃣*️⃣*️⃣ "])
        XCTAssertEqual(document.blocks[1].runs.map(\.text), ["a`\u{301}b"])
        let cell = try XCTUnwrap(document.blocks[2].table?.rows[1][0])
        XCTAssertEqual(cell.map(\.text), ["x", " and ", "p|q"])
        XCTAssertEqual(cell.first?.link, "https://example.com/a|b")
        XCTAssertEqual(document.attachmentIDs.count, 1)
    }

    func testImageOnlyListItemsKeepTheirImageWhenTickedOrEdited() throws {
        let id = try XCTUnwrap(UUID(uuidString: String(Self.image.dropFirst("attachments/".count))))
        let document = try reopen(
            JournalDocument(markdown: "- [ ] ![Receipt](\(Self.image))\n- ![Sketch](\(Self.image))\n"))
        XCTAssertEqual(document.blocks.map(\.kind), ["task", "bullet"])
        XCTAssertEqual(document.imageBlocks.map(\.imageDescription), ["Receipt", "Sketch"])
        var ticked = document
        ticked.blocks[0].kind = "checked"
        for updated in [document.applyingRichEdit(ticked), typing(" today", into: 1, of: document)] {
            let reopened = try reopen(updated)
            XCTAssertEqual(reopened.attachmentIDs, [id])
            XCTAssertEqual(reopened.imageBlocks.map(\.imageDescription), ["Receipt", "Sketch"])
            XCTAssertEqual(visible(reopened), visible(updated))
        }
    }

    func testImageDescriptionsWithBlankLinesKeepTheImageReference() throws {
        let id = try XCTUnwrap(UUID(uuidString: String(Self.image.dropFirst("attachments/".count))))
        let source =
            "![Old](\(Self.image))\n\nInline ![Old](\(Self.image)) image.\n\n| Picture |\n| --- |\n| ![Old](\(Self.image)) |\n"
        let document = try reopen(JournalDocument(markdown: source))
        let descriptions = Dictionary(
            uniqueKeysWithValues: document.imageBlocks.map { ($0.id, "First line\n\nSecond line\r\nThird") })
        let updated = try reopen(document.updatingImageDescriptions(descriptions))
        XCTAssertEqual(updated.attachmentIDs, [id])
        XCTAssertEqual(updated.blocks.map(\.kind), ["image", "paragraph", "table"])
        XCTAssertEqual(
            updated.imageBlocks.map(\.imageDescription), Array(repeating: "First line Second line Third", count: 3))
    }

    func testDocumentsWithoutStoredIdentitiesDecodeToEqualValues() throws {
        let stored = UUID()
        let bodies = [
            ##"{"version":2,"markdown":"# Title\n\n![Photo](\##(Self.image))\n\nInline ![p](\##(Self.image))"}"##,
            #"{"version":2,"markdown":"One\n\nTwo\n\nThree","metadata":{"blockIDs":["\#(stored)"],"imageTypes":{}}}"#,
        ]
        for body in bodies {
            let first = try JournalCoding.decoder().decode(JournalDocument.self, from: Data(body.utf8))
            let second = try JournalCoding.decoder().decode(JournalDocument.self, from: Data(body.utf8))
            XCTAssertEqual(first, second, body)
            XCTAssertEqual(first.imageBlocks, second.imageBlocks, body)
            XCTAssertEqual(Set(first.blocks.map(\.id)).count, first.blocks.count, body)
        }
        let short = try JournalCoding.decoder().decode(JournalDocument.self, from: Data(bodies[1].utf8))
        XCTAssertEqual(short.blocks.first?.id, stored)
        let source = short.replacingMarkdown("Two\n\nThree\n\nFour")
        XCTAssertEqual(Set(source.blocks.map(\.id)).count, 3)
        XCTAssertEqual(source, short.replacingMarkdown("Two\n\nThree\n\nFour"))
    }

    func testLoneCarriageReturnsAndCRLFKeepBlockBoundaries() throws {
        let lone = try reopen(JournalDocument(markdown: "a\rb\n\nc\n\nd"))
        XCTAssertEqual(visible(lone), ["paragraph 0: a\nb", "paragraph 0: c", "paragraph 0: d"])
        XCTAssertEqual(typing("!", into: 1, of: lone).markdown, "a\rb\n\nc!\n\nd")
        XCTAssertEqual(typing("!", into: 0, of: lone).markdown, "a\nb!\n\nc\n\nd")
        let crlf = try reopen(JournalDocument(markdown: "a\r\n\r\nb\r\n\r\nc\r\n"))
        var removed = crlf
        removed.blocks.remove(at: 1)
        XCTAssertEqual(crlf.applyingRichEdit(removed).markdown, "a\r\n\r\nc\r\n")
        let inserted = crlf.insertingMarkdown("---\n", after: crlf.blocks.first?.id)
        XCTAssertEqual(inserted.text, "a\r\n\r\n---\n\n\nb\r\n\r\nc\r\n")
    }

    func testImportRemappingKeepsTextAndRemapsEveryImage() throws {
        let first = UUID()
        let second = UUID()
        let replacements = [first: UUID(), second: UUID()]
        func path(_ id: UUID) -> String { "attachments/" + id.uuidString.lowercased() }
        func source(_ one: String, _ two: String, code: String) -> String {
            "para\n   ![x](\(one)) and\n  more ![y](\(two)) end\n\na\rb ![z](\(one)) c\n\n![Referenced][r]\n\n"
                + "[r]: \(two)\n\n`\(code)`\n"
        }
        var document = try reopen(JournalDocument(markdown: source(path(first), path(second), code: path(first))))
        try document.remapAttachments(replacements)
        let mapped = try [XCTUnwrap(replacements[first]), XCTUnwrap(replacements[second])]
        XCTAssertEqual(document.markdown, source(path(mapped[0]), path(mapped[1]), code: path(first)))
        XCTAssertEqual(Set(document.attachmentIDs), Set(mapped))
    }

    func testParagraphInterruptedByTableOpensAndKeepsBoth() throws {
        // The parser gives such a paragraph no source position; reading it used to stop the app.
        let body = #"{"version":2,"markdown":"Intro\n| A | B |\n|---|---|\n| c | d |"}"#
        let document = try JournalCoding.decoder().decode(JournalDocument.self, from: Data(body.utf8))
        XCTAssertEqual(visible(document), ["paragraph 0: Intro", "table 0: A\tB\nc\td"])
        XCTAssertEqual(
            visible(try reopen(typing("!", into: 0, of: document))), ["paragraph 0: Intro!", "table 0: A\tB\nc\td"])
    }

    func testReferenceDefinitionAboveAParagraphSurvivesItsRewriteAndRemoval() throws {
        let document = try reopen(
            JournalDocument(markdown: "First.\n\n[r]: https://example.com\nUse [it][r].\n\nAgain [it][r].\n"))
        var removed = document
        removed.blocks.remove(at: 1)
        for edited in [typing("!", into: 1, of: document), document.applyingRichEdit(removed)] {
            XCTAssertEqual(try reopen(edited).blocks.last?.runs.first { $0.link != nil }?.link, "https://example.com")
        }
    }

    func testUnfamiliarDocumentShapesArePreservedReadOnly() throws {
        let shapes = [
            #"{"version":3,"blocks":{"future":true}}"#,
            #"{"version":2,"markdown":"Text","metadata":{"blockIDs":["not-a-uuid"],"imageTypes":{}}}"#,
            #"{"version":2,"markdown":"Text","metadata":{"blockIDs":[],"imageTypes":{"a":1}}}"#,
            #"{"version":2,"body":"Text"}"#, #"{"version":1,"blocks":[{"kind":"paragraph"}]}"#,
        ]
        for shape in shapes {
            let json =
                #"{"date":"2026-01-01T00:00:00Z","deletedWithJournal":false,"document":\#(shape),"#
                + #""id":"\#(UUID())","kind":"entry","modifiedAt":"2026-01-01T00:00:00Z","title":""}"#
            let item = try PortableRecord.decode(Data(json.utf8))
            XCTAssertFalse(item.document.isEditable, shape)
            XCTAssertEqual(try PortableRecord.encode(item), Data(json.utf8), shape)
        }
        let partial = #"{"version":2,"markdown":"Text","metadata":{"blockIDs":[]}}"#
        let document = try JournalCoding.decoder().decode(JournalDocument.self, from: Data(partial.utf8))
        XCTAssertTrue(document.isEditable)
        XCTAssertEqual(document.text, "Text")
    }
}
