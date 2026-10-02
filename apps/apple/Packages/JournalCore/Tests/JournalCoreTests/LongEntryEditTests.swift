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
}
