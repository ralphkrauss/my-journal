import XCTest

@testable import JournalCore

/// Saving an edit reads back only the Markdown around it. In a long entry, edits next to lists, headings and quotes
/// must still read back as the blocks the editor had.
final class LongEntryEditTests: XCTestCase {
    private func shape(_ document: JournalDocument) -> [String] {
        document.blocks.map { $0.kind + ": " + $0.runs.map(\.text).joined() }
    }

    func testEditsInTheMiddleOfALongEntryReadBackAsWritten() {
        let before = (0..<30).map { "Paragraph \($0) of the morning." }.joined(separator: "\n\n")
        let after = (30..<60).map { "Paragraph \($0) of the evening." }.joined(separator: "\n\n")
        let lists = "Intro:\n- first\n- second\n\n-   wide\n    - nested\n\n> A quote\n\n## A heading\nText under it"
        var document = JournalDocument(markdown: before + "\n\n" + lists + "\n\n" + after)
        let middle = document.blocks.firstIndex { $0.kind == "bullet" } ?? 0
        let nested = document.blocks.firstIndex { $0.runs.map(\.text).joined() == "nested" } ?? 0
        let edits: [(inout [DocumentBlock]) -> Void] = [
            { $0.insert(DocumentBlock(kind: "paragraph", runs: [TextRun("New")]), at: nested + 1) },
            { $0[middle - 1].runs.append(TextRun(" typed")) },
            { $0[middle - 1].kind = "heading" },
            { $0.insert(DocumentBlock(kind: "paragraph", runs: [TextRun("Between items")]), at: middle + 1) },
            { $0[middle + 3].kind = "bullet" },
            { $0[middle + 4].runs.append(TextRun(" more")) },
            { $0.remove(at: middle + 2) },
        ]
        for (step, edit) in edits.enumerated() {
            var edited = document
            edit(&edited.blocks)
            document = document.applyingRichEdit(edited)
            XCTAssertEqual(
                shape(JournalDocument(markdown: document.markdown)), shape(edited), "After edit \(step)")
        }
        XCTAssertTrue(document.markdown.hasPrefix(before), "Text far from the edits keeps its bytes")
        XCTAssertTrue(document.markdown.hasSuffix(after))
    }

    /// A block added after a nested item at the end of a long entry: only the item's parent, well before the edit,
    /// shows how the added text must be written to stay a block of its own.
    func testABlockAddedAfterANestedItemAtTheEndOfALongEntryStaysSeparate() {
        let before = (0..<30).map { "Paragraph \($0) of the morning." }.joined(separator: "\n\n")
        let document = JournalDocument(markdown: before + "\n\n-   wide\n    - nested\n")
        var edited = document
        edited.blocks.append(DocumentBlock(kind: "paragraph", runs: [TextRun("New")]))
        let saved = document.applyingRichEdit(edited)
        XCTAssertEqual(shape(JournalDocument(markdown: saved.markdown)), shape(edited))
    }

    /// Edits in a long list read back only the items around them. Whatever is typed into an item, and however items
    /// are added, removed, nested or changed in kind, the saved Markdown reads back as the blocks the editor had.
    func testRandomEditsInALongListReadBackAsWritten() {
        var state: UInt64 = 41
        func random(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        let kinds = ["bullet", "numbered", "task", "checked"]
        let texts = [
            "milk", "1. not a number", "- not a bullet", "# not a heading", "> not a quote", "**bold**", "x",
            "  spaced",
        ]
        var lines: [String] = []
        for index in 0..<200 {
            switch index % 4 {
            case 0: lines.append("- [ ] Task \(index)")
            case 1: lines.append("- Bullet \(index)")
            case 2: lines.append("  - Nested \(index)")
            default: lines.append("- [x] Done \(index)")
            }
        }
        var document = JournalDocument(markdown: "Intro\n\n" + lines.joined(separator: "\n") + "\n\nAfter")
        for step in 0..<300 {
            var edited = document
            let index = 1 + random(edited.blocks.count - 2)
            switch random(5) {
            case 0: edited.blocks[index].runs = [TextRun(texts[random(texts.count)])]
            case 1: edited.blocks[index].kind = kinds[random(kinds.count)]
            case 2:
                edited.blocks.insert(
                    DocumentBlock(kind: kinds[random(kinds.count)], runs: [TextRun(texts[random(texts.count)])]),
                    at: index)
            case 3: edited.blocks.remove(at: index)
            default: edited.blocks[index].runs.append(TextRun(" typed"))
            }
            document = document.applyingRichEdit(edited)
            XCTAssertEqual(shape(JournalDocument(markdown: document.markdown)), shape(edited), "After edit \(step)")
            if shape(JournalDocument(markdown: document.markdown)) != shape(edited) { return }
        }
    }
}
