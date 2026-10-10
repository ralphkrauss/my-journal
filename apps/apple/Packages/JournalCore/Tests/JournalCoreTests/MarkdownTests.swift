import XCTest

@testable import JournalCore

final class MarkdownTests: XCTestCase {
    func testInlineImagesSurviveEditsRemappingAndPortableEncoding() throws {
        let image = UUID()
        let replacement = UUID()
        let source =
            "Before ![Diagram](attachments/" + image.uuidString.lowercased()
            + " \"Title\") after.\n\n| Picture |\n| --- |\n| ![Remote](https://example.com/private.png) |"
        let document = JournalDocument(markdown: source)
        XCTAssertFalse(document.requiresMarkdownSource)
        XCTAssertEqual(document.attachmentIDs, [image])
        var edited = document
        edited.blocks[0].runs[0].text = "Changed "
        var updated = document.applyingRichEdit(edited)
        XCTAssertTrue(updated.markdown.contains("Title"))
        XCTAssertTrue(updated.markdown.contains("private.png"))
        try updated.remapAttachments([image: replacement])
        XCTAssertEqual(updated.attachmentIDs, [replacement])
        let reopened = try JournalCoding.decoder().decode(
            JournalDocument.self, from: JournalCoding.encoder().encode(updated))
        XCTAssertEqual(reopened.attachmentIDs, [replacement])
        XCTAssertFalse(reopened.requiresMarkdownSource)
    }
    func testRaggedTableStructuralEditsDoNotDropCellsOrCrash() {
        var table = DocumentTable(rows: [[[TextRun("A")], [TextRun("B")]], [[TextRun("C")]]], alignments: [])
        XCTAssertTrue(table.apply(.addColumn, row: 0, column: 1))
        XCTAssertEqual(table.rows.map(\.count), [3, 3])
        XCTAssertEqual(table.rows[1][0].first?.text, "C")
        XCTAssertTrue(table.apply(.deleteColumn, row: 0, column: 1))
        XCTAssertEqual(table.rows.map(\.count), [2, 2])
    }
    func testRichDocumentRoundTripKeepsMarksImagesAndWhitespace() throws {
        let image = DocumentBlock(
            kind: "image", attachmentID: UUID(), imageDescription: "Sketch", mediaType: "image/png")
        let document = JournalDocument(blocks: [
            DocumentBlock(runs: [TextRun(" Keep these words ", bold: true)]), DocumentBlock(), image,
        ])
        let decoded = try JournalCoding.decoder().decode(
            JournalDocument.self, from: JournalCoding.encoder().encode(document))
        XCTAssertFalse(decoded.requiresMarkdownSource)
        XCTAssertEqual(decoded, document)
    }
    func testAdjacentMarksPunctuationAndCodeKeepEveryCharacter() throws {
        var code = TextRun("a`b")
        code.code = true
        let cases: [[TextRun]] = [
            [TextRun("bold", bold: true), TextRun("both", bold: true, italic: true), TextRun("italic", italic: true)],
            [TextRun("A", bold: true), TextRun("B", bold: true)],
            [TextRun("**literal** [link] & <> _ # 1. "), code],
            [TextRun("under", underline: true), TextRun("lined", underline: true)],
        ]
        for runs in cases {
            let document = JournalDocument(blocks: [DocumentBlock(runs: runs)])
            let decoded = try JournalCoding.decoder().decode(
                JournalDocument.self, from: JournalCoding.encoder().encode(document))
            XCTAssertFalse(decoded.requiresMarkdownSource, document.markdown)
            XCTAssertEqual(decoded.text, document.text, document.markdown)
            let expected = runs.flatMap { run in
                run.text.map { "\($0):\(run.bold):\(run.italic):\(run.underline):\(run.code)" }
            }
            let actual = decoded.blocks.flatMap(\.runs).flatMap { run in
                run.text.map { "\($0):\(run.bold):\(run.italic):\(run.underline):\(run.code)" }
            }
            XCTAssertEqual(actual, expected, document.markdown)
        }
    }
    func testPunctuationIsEscapedOnlyWhereMarkdownWouldReadItAsSyntax() throws {
        let readable = "Before unchanged. It's 5-6 (maybe)! C# and snake_case, a + b = c, 3.5 > 2."
        XCTAssertEqual(JournalDocument(blocks: [DocumentBlock(runs: [TextRun(readable)])]).markdown, readable + "\n\n")
        let literal = [
            "# not a heading", "- not a list", "+ not a list", "1. not ordered", "12) not ordered", "> not a quote",
            "---", "===", "Closing #", "Heading ##", "*stars* and _under_ and ~tilde~", "[link](x) ![image](y)",
            "<b>html</b> &amp; &#32;", "back\\slash `code` | pipe", "under_ score_ _", "1.5 stays", "-5 stays",
        ]
        for kind in ["paragraph", "heading", "bullet", "quote"] {
            for text in literal {
                var line = TextRun("\n")
                line.breakKind = "soft"
                // ATX headings are single lines; other blocks also check a line start after a soft break.
                let runs = kind == "heading" ? [TextRun(text)] : [TextRun(text), line, TextRun(text)]
                let block = DocumentBlock(kind: kind, runs: runs)
                let document = JournalDocument(blocks: [block])
                let reopened = JournalDocument(markdown: document.markdown)
                XCTAssertFalse(reopened.requiresMarkdownSource, document.markdown)
                XCTAssertEqual(reopened.blocks.map(\.kind), [kind], document.markdown)
                XCTAssertEqual(reopened.text, document.text, document.markdown)
                XCTAssertFalse(reopened.blocks.flatMap(\.runs).contains { $0.bold || $0.italic || $0.link != nil })
            }
        }
    }
    func testComplexSourceRemainsExactAndKeepsImageReferences() throws {
        let id = UUID()
        let markdown =
            "| A | B |\n| --- | --- |\n| **X** | Y |\n\n![Sketch](attachments/\(id.uuidString.lowercased()))\n\n<script>never run</script>\n"
        let document = JournalDocument(markdown: markdown)
        XCTAssertFalse(document.requiresMarkdownSource)
        let decoded = try JournalCoding.decoder().decode(
            JournalDocument.self, from: JournalCoding.encoder().encode(document))
        XCTAssertEqual(decoded.markdown, markdown)
        XCTAssertEqual(decoded.blocks.compactMap(\.attachmentID), [id])
    }
    func testTableCellEditsKeepAlignmentMarksPipesAndSurroundingSource() throws {
        let original = JournalDocument(
            markdown: "Before.\n\n| Name | Value |\n| :--- | ---: |\n| **A** | `x` |\n\nAfter.")
        XCTAssertFalse(original.requiresMarkdownSource)
        var edited = original
        var table = try XCTUnwrap(edited.blocks[1].table)
        var code = TextRun("a|b")
        code.code = true
        table.replaceCell(row: 1, column: 1, runs: [code, TextRun(" next\nline")])
        edited.blocks[1].table = table
        let updated = original.applyingRichEdit(edited)
        let decoded = try JournalCoding.decoder().decode(
            JournalDocument.self, from: JournalCoding.encoder().encode(updated))
        let restored = try XCTUnwrap(decoded.blocks[1].table)
        XCTAssertEqual(restored.alignments, ["left", "right"])
        XCTAssertEqual(restored.rows[1][1].map(\.text).joined(), "a|b next line")
        XCTAssertTrue(restored.rows[1][1][0].code)
        XCTAssertTrue(restored.rows[1][0][0].bold)
        XCTAssertTrue(decoded.markdown.hasPrefix("Before.\n\n"))
        XCTAssertTrue(decoded.markdown.hasSuffix("After."))
    }
    func testNestedListsAndReferenceLinksKeepMeaningAfterEditingAndReopening() throws {
        let source =
            "[site]: https://example.com \"A title\"\n\n7. First\n   - Nested **item**\n\n   Continued paragraph.\n\nLast [link][site]."
        let original = JournalDocument(markdown: source)
        XCTAssertFalse(original.requiresMarkdownSource)
        XCTAssertEqual(original.blocks[0].listNumber, 7)
        XCTAssertEqual(original.blocks[1].listIndents, [3])
        XCTAssertEqual(original.blocks.last?.runs.first { $0.link != nil }?.linkTitle, "A title")
        var edited = original
        edited.blocks[0].runs = [TextRun("Changed")]
        let updated = original.applyingRichEdit(edited)
        let reopened = try JournalCoding.decoder().decode(
            JournalDocument.self, from: JournalCoding.encoder().encode(updated))
        XCTAssertEqual(reopened.blocks[0].listNumber, 7)
        XCTAssertEqual(reopened.blocks[1].listIndents, [3])
        XCTAssertTrue(reopened.text.contains("Continued paragraph."))
        XCTAssertEqual(reopened.blocks.last?.runs.first { $0.link != nil }?.link, "https://example.com")
        XCTAssertTrue(reopened.markdown.hasPrefix("[site]: https://example.com"))
    }
    func testEditingBeforeReferenceDefinitionDoesNotBreakUntouchedLink() {
        let original = JournalDocument(markdown: "First.\n\n[ref]: https://example.com\n\nUse [this][ref].")
        var edited = original
        edited.blocks[0].runs = [TextRun("Changed.")]
        let updated = original.applyingRichEdit(edited)
        let parsed = JournalDocument(markdown: updated.markdown)
        XCTAssertEqual(parsed.blocks.last?.runs.first { $0.link != nil }?.link, "https://example.com")
        edited.blocks.removeFirst()
        let deleted = original.applyingRichEdit(edited)
        XCTAssertEqual(
            JournalDocument(markdown: deleted.markdown).blocks.last?.runs.first { $0.link != nil }?.link,
            "https://example.com")
    }
    func testRemappingImageDoesNotRewriteCodeOrOrdinaryText() throws {
        let old = UUID(), new = UUID()
        let path = "attachments/" + old.uuidString.lowercased()
        var document = JournalDocument(markdown: "![Sketch](" + path + ")\n\n`" + path + "`\n")
        try document.remapAttachments([old: new])
        XCTAssertTrue(document.markdown.contains("![Sketch](attachments/" + new.uuidString.lowercased() + ")"))
        XCTAssertTrue(document.markdown.contains("`" + path + "`"))
    }
    func testRichEditPreservesUntouchedMarkdownAndLegacyDecode() throws {
        let original = JournalDocument(markdown: "Heading\n=======\n\nA **bold** word.\n")
        XCTAssertFalse(original.requiresMarkdownSource)
        var edit = original
        edit.blocks[1].runs = [TextRun("Changed")]
        let updated = original.applyingRichEdit(edit)
        XCTAssertTrue(updated.markdown.hasPrefix("Heading\n=======\n\n"))
        let legacy = Data(
            #"{"version":1,"blocks":[{"id":"00000000-0000-0000-0000-000000000001","kind":"paragraph","runs":[{"text":"Older","bold":false,"italic":false,"underline":false}]}]}"#
                .utf8)
        let document = try JournalCoding.decoder().decode(JournalDocument.self, from: legacy)
        XCTAssertEqual(document.version, 1)
        XCTAssertEqual(document.applyingRichEdit(document).version, 1)
        var changed = document
        changed.blocks[0].runs[0].text = "Newer"
        XCTAssertEqual(document.applyingRichEdit(changed).version, 2)
    }
    func testInsertingBlockSyntaxPreservesSurroundingParagraphs() {
        let original = JournalDocument(markdown: "First paragraph.\n\nLast paragraph.")
        for syntax in ["---\n", "```\n\n```\n", "| A | B |\n| --- | --- |\n| X | Y |\n"] {
            let insertion = original.insertingMarkdown(syntax, after: original.blocks.first?.id)
            XCTAssertEqual(insertion.text, "First paragraph.\n\n" + syntax + "\n\nLast paragraph.")
            XCTAssertEqual(insertion.caret, ("First paragraph.\n\n" + syntax).utf16.count)
        }
        var edited = original
        edited.blocks.append(DocumentBlock(runs: [TextRun("Added paragraph.")]))
        let updated = original.applyingRichEdit(edited)
        XCTAssertEqual(JournalDocument(markdown: updated.markdown).blocks.count, 3)
        XCTAssertTrue(updated.markdown.hasPrefix(original.markdown + "\n\n"))
        XCTAssertEqual(
            JournalDocument(markdown: updated.markdown).blocks.last?.runs.map(\.text).joined(), "Added paragraph.")
    }

}
