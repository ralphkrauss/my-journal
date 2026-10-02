import JournalCore
import SwiftUI
import XCTest

@testable import Journal

/// Typing reads only the paragraph it changes. What the editor reads must still be what reading the whole text gives.
@MainActor final class EditorReadingTests: XCTestCase {
    /// What was read, apart from the identities empty paragraphs get anew on each whole reading.
    private func content(_ blocks: [DocumentBlock]?) -> [DocumentBlock] {
        (blocks ?? []).map { block in
            var block = block
            block.id = UUID(uuid: UUID_NULL)
            return block
        }
    }
    private func assertReadsAsWhole(_ harness: EditorHarness, _ message: String) {
        XCTAssertEqual(
            content(harness.coordinator.reading.blocks), content(RichText.document(harness.text).blocks), message)
    }

    private static let entry = """
        # Morning

        A paragraph with **bold**, *italic* and a [link](https://example.com).

        - First item
        - Second item

        - [ ] A task
        - [x] A done task

        > A quote

        ```
        let code = 1
        ```

        | A | B |
        | --- | --- |
        | 1 | 2 |

        Last paragraph
        """

    /// Every kind of paragraph, typed into and deleted from, saves as reading the whole text afterwards does.
    func testTypingInEachParagraphSavesWhatReadingTheWholeTextGives() throws {
        let harness = EditorHarness(markdown: Self.entry)
        defer { harness.close() }
        for target in ["Morning", "paragraph with", "italic", "Second item", "A task", "done", "quote", "code", "Last"]
        {
            harness.select(target)
            harness.caret(at: NSMaxRange(harness.selection))
            harness.type(" more")
            assertReadsAsWhole(harness, "After typing in “\(target)”")
            harness.deleteBackward()
            harness.type("s")
            assertReadsAsWhole(harness, "After deleting in “\(target)”")
        }
        XCTAssertTrue(harness.document.markdown.contains("Morning mors"))
    }

    /// Line breaks change which paragraphs there are: splitting and joining them reads the whole text again.
    func testSplittingAndJoiningParagraphsSavesWhatReadingTheWholeTextGives() throws {
        let harness = EditorHarness(markdown: "One two\n\nThree four\n\n- Item")
        defer { harness.close() }
        harness.type("a")
        harness.select("two")
        harness.caret(at: harness.selection.location)
        harness.pressReturn()
        harness.type("x")
        assertReadsAsWhole(harness, "After splitting a paragraph")
        harness.select("Three")
        harness.caret(at: harness.selection.location)
        harness.deleteBackward()
        harness.type("y")
        assertReadsAsWhole(harness, "After joining paragraphs")
        XCTAssertTrue(harness.document.text.contains("One \nxtwoyThree four"))
    }

    /// Typing, deleting and pressing Return at many places, in an order that is the same on every run: after every
    /// key, what the editor read is what reading the whole text gives.
    func testManyEditsAtChangingPlacesReadAsTheWholeText() throws {
        let harness = EditorHarness(markdown: Self.entry)
        defer { harness.close() }
        var state: UInt64 = 7
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(max(1, bound)))
        }
        for step in 0..<150 {
            let length = harness.text.length
            harness.caret(at: next(length + 1))
            switch next(10) {
            case 0: harness.pressReturn()
            case 1, 2: harness.deleteBackward()
            default: harness.type(["a", "b", " ", "c"][next(4)])
            }
            assertReadsAsWhole(harness, "After step \(step)")
        }
    }
}
