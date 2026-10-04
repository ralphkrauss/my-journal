import JournalCore
import SwiftUI
import XCTest

@testable import Journal

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// List items and quotes hold only what the person wrote; their markers are drawn (docs/design/list-markers-2026-10-03.md).
/// Build 13 stored "☐\t", "•\t" or "❯\t" before each item's text, so the keyboard read them before the caret and
/// didn't capitalize a new item, and VoiceOver read them aloud.
@MainActor
final class ListItemEditingTests: XCTestCase {
    func testANewItemStartsALineForTheKeyboard() throws {
        for (shortcut, kind) in [("[] ", "task"), ("- ", "bullet"), ("1. ", "numbered"), ("> ", "quote")] {
            let harness = EditorHarness(markdown: "")
            defer { harness.close() }
            harness.type(shortcut)
            // The shortcut converts the line just after the space, as between key presses.
            harness.wait { harness.document.blocks.first?.kind == kind }
            harness.type("First")
            harness.pressReturn()
            // Exactly what was written, with its line breaks: the new item's own line break follows the caret.
            XCTAssertEqual(harness.text.string, "First\n\n", kind)
            let caret = harness.selection
            XCTAssertEqual(caret, NSRange(location: 6, length: 0), kind)
            #if os(iOS)
                // What the keyboard reads before the caret: a line start, as on any new line.
                let view = harness.view
                let position = try XCTUnwrap(view.selectedTextRange?.start, kind)
                let before = try XCTUnwrap(view.textRange(from: view.beginningOfDocument, to: position), kind)
                XCTAssertEqual(view.text(in: before), "First\n", kind)
                XCTAssertTrue(
                    view.tokenizer.isPosition(position, atBoundary: .paragraph, inDirection: .storage(.backward)), kind)
            #else
                XCTAssertEqual((harness.text.string as NSString).substring(to: caret.location), "First\n", kind)
            #endif
            XCTAssertEqual(harness.document.blocks.map(\.kind), [kind, kind], "The new item is saved, empty.")
            harness.type("Second")
            XCTAssertEqual(harness.document.blocks.map(\.kind), [kind, kind], kind)
            XCTAssertEqual(harness.document.blocks.map { $0.runs.map(\.text).joined() }, ["First", "Second"], kind)
        }
    }

    /// Entries are shown and read back unchanged, whatever list or quote they end with: the last item's own line
    /// break is never read as an empty paragraph after it, and an empty paragraph after a list stays.
    func testEntriesEndingInListsReadBackExactly() throws {
        var nested = DocumentBlock(kind: "bullet", runs: [TextRun("Nested")])
        nested.markdownPrefix = "  "
        nested.markdownContinuation = "    "
        nested.listIndents = [2]
        var quoted = DocumentBlock(kind: "bullet", runs: [TextRun("In a quote")])
        quoted.markdownPrefix = "> "
        quoted.markdownContinuation = ">   "
        let item = DocumentBlock(kind: "bullet", runs: [TextRun("Item")])
        let endings: [[DocumentBlock]] = [
            [item], [item, DocumentBlock(kind: "bullet")], [item, DocumentBlock()],
            [DocumentBlock(kind: "task", runs: [TextRun("Open")])], [DocumentBlock(kind: "checked")],
            [DocumentBlock(kind: "numbered", runs: [TextRun("One")])],
            [DocumentBlock(kind: "quote", runs: [TextRun("Q")])],
            [DocumentBlock(kind: "quote")], [item, nested], [quoted], [DocumentBlock(kind: "task"), item],
        ]
        for blocks in endings {
            let original = JournalDocument(blocks: [DocumentBlock(runs: [TextRun("Before")])] + blocks)
            let read = RichText.document(RichText.render(original, size: 17, images: [:]))
            // An empty paragraph's identity isn't kept, as before; every item's is.
            let identities = { (blocks: [DocumentBlock]) in
                blocks.filter { $0.kind != "paragraph" || !$0.runs.isEmpty }.map(\.id)
            }
            XCTAssertEqual(identities(read.blocks), identities(original.blocks), original.markdown)
            XCTAssertEqual(read.blocks.map(\.kind), original.blocks.map(\.kind), original.markdown)
            XCTAssertEqual(
                read.blocks.map { $0.runs.map(\.text).joined() }, original.blocks.map { $0.runs.map(\.text).joined() },
                original.markdown)
            XCTAssertEqual(
                MarkdownEditing.read(RichText.render(original, size: 17, images: [:]), previous: original).markdown,
                original.markdown)
        }
    }

    func testTheLastItemKeepsItsOwnLineBreak() throws {
        let harness = EditorHarness(markdown: "- [ ] Milk\n- [ ] Eggs")
        defer { harness.close() }
        let length = harness.text.length
        // A tap below the text, or ⌘↓: writing continues in the last item.
        harness.caret(at: length)
        XCTAssertEqual(harness.selection, NSRange(location: length - 1, length: 0))
        // Deleting all of its text leaves the empty item, not a plain line.
        harness.select("Eggs")
        harness.deleteBackward()
        XCTAssertEqual(harness.document.blocks.map(\.kind), ["task", "task"])
        harness.type("Bread")
        XCTAssertEqual(harness.document.markdown.trimmingCharacters(in: .newlines), "- [ ] Milk\n- [ ] Bread")
        // Forward delete at the end of the last item has nothing after it to delete.
        harness.caret(at: harness.text.length - 1)
        harness.forwardDelete()
        XCTAssertEqual(harness.document.blocks.map(\.kind), ["task", "task"])
        XCTAssertTrue(ListMarkers.hasOwnEnd(harness.text))
    }

    func testAPictureAtTheEndOfAListComesAndGoesCleanly() throws {
        let harness = EditorHarness(markdown: "Errands\n\n- Milk")
        defer { harness.close() }
        let before = harness.document.markdown
        harness.caret(at: harness.text.length)
        harness.coordinator.perform(
            .image(DocumentBlock(kind: "image", attachmentID: UUID(), imageDescription: "", mediaType: "image/png")))
        XCTAssertEqual(harness.document.blocks.map(\.kind), ["paragraph", "bullet", "image", "paragraph"])
        harness.undoManager?.undo()
        harness.settle()
        XCTAssertEqual(harness.document.markdown, before)
        XCTAssertTrue(ListMarkers.hasOwnEnd(harness.text))
    }

    #if os(macOS)
        func testTypingOnTheEmptyLineAfterAListWritesAPlainLine() throws {
            let harness = EditorHarness(markdown: "- [ ] Milk")
            defer { harness.close() }
            harness.caret(at: harness.text.length)
            harness.pressReturn()
            harness.pressReturn()
            XCTAssertEqual(harness.document.blocks.map(\.kind), ["task", "paragraph"])
            // Away and back: the text system would take the item's attributes from the line break before the line.
            harness.caret(at: 0)
            harness.caret(at: harness.text.length)
            harness.type("Plain")
            XCTAssertEqual(harness.document.blocks.map(\.kind), ["task", "paragraph"])
            XCTAssertEqual(harness.document.blocks.last?.runs.map(\.text).joined(), "Plain")
        }
    #endif

    /// Splitting items and joining lines change text outside what is typed; undo and redo restore it exactly, with
    /// each item's identity, number and checked state.
    func testUndoAndRedoRestoreSplitAndJoinedItemsExactly() throws {
        let cases: [(String, String, (EditorHarness) -> Void)] = [
            ("Return in a checked item", "- [x] Done well\n- [ ] Next", { $0.caret(at: 4) }),
            ("Return in a numbered item", "1. One\n2. Two", { $0.caret(at: 3) }),
            ("Return at the end of the last item", "- Milk\n- Eggs", { $0.caret(at: $0.text.length) }),
            ("Return at the start of a checked item", "- [x] Done", { $0.caret(at: 0) }),
        ]
        for (name, markdown, place) in cases {
            try checkUndoAndRedo(name, JournalDocument(markdown: markdown)) { harness in
                place(harness)
                harness.pressReturn()
            }
        }
        let joins: [(String, String, (EditorHarness) -> Void)] = [
            ("a checked item onto a bullet", "- Milk\n- [x] Eggs", { $0.select(NSRange(location: 4, length: 1)) }),
            ("a paragraph onto an item", "- Milk\n\nPlain", { $0.caret(at: ("Milk\n" as NSString).length) }),
            ("across items", "- [ ] One\n- [x] Two\n1. Three", { $0.select(NSRange(location: 2, length: 7)) }),
        ]
        for (name, markdown, place) in joins {
            try checkUndoAndRedo("Joining " + name, JournalDocument(markdown: markdown)) { harness in
                place(harness)
                harness.deleteBackward()
            }
        }
        let emptyLast = JournalDocument(blocks: [
            DocumentBlock(kind: "bullet", runs: [TextRun("Milk")]), DocumentBlock(kind: "bullet"),
        ])
        try checkUndoAndRedo("Return on an empty last item", emptyLast) { harness in
            harness.caret(at: harness.text.length)
            harness.pressReturn()
        }
    }

    func testReturnContinuesItemsWithTheirOwnIdentityNumberAndState() throws {
        let harness = EditorHarness(markdown: "- [x] Done\n\n1. One\n2. Two")
        defer { harness.close() }
        harness.caret(at: ("Done" as NSString).length)
        harness.pressReturn()
        harness.type("Next")
        harness.caret(at: (harness.text.string as NSString).range(of: "One").upperBound)
        harness.pressReturn()
        harness.type("Between")
        let blocks = harness.document.blocks
        XCTAssertEqual(blocks.map(\.kind), ["checked", "task", "numbered", "numbered", "numbered"])
        XCTAssertEqual(blocks[3].listNumber, 2, "The new item's number follows the one it continues.")
        XCTAssertEqual(Set(blocks.map(\.id)).count, blocks.count, "Every item has an identity of its own.")
        // Return at the start of a checked item leaves it checked, with a new empty item above it.
        harness.caret(at: 0)
        harness.pressReturn()
        XCTAssertEqual(harness.document.blocks.prefix(2).map(\.kind), ["task", "checked"])
        XCTAssertEqual(harness.document.blocks[1].id, blocks[0].id)
    }

    /// Dictation's “new line” and other inserted text with line breaks continue the list as Return does.
    func testLinesInsertedIntoAnItemBecomeItemsOfTheList() throws {
        let harness = EditorHarness(markdown: "1. One")
        defer { harness.close() }
        harness.caret(at: ("One" as NSString).length)
        harness.insertTyped(" more\nTwo\nThree")
        let blocks = harness.document.blocks
        XCTAssertEqual(blocks.map { $0.runs.map(\.text).joined() }, ["One more", "Two", "Three"])
        XCTAssertEqual(blocks.map(\.kind), ["numbered", "numbered", "numbered"])
        XCTAssertEqual(blocks.dropFirst().map(\.listNumber), [2, 3])
        XCTAssertEqual(Set(blocks.map(\.id)).count, 3)
    }

    /// Text pasted into a list item joins it, and its further lines continue the list; an empty item, the last one
    /// included, stays an item and gains no empty line after it.
    func testPastingIntoItemsKeepsThemItems() throws {
        let milk = DocumentBlock(kind: "task", runs: [TextRun("Milk")])
        let eggs = DocumentBlock(kind: "task", runs: [TextRun("Eggs")])
        for blocks in [[milk, DocumentBlock(kind: "task"), eggs], [milk, DocumentBlock(kind: "task")]] {
            let harness = EditorHarness(JournalDocument(blocks: blocks))
            defer { harness.close() }
            harness.caret(at: ("Milk\n" as NSString).length)
            harness.paste(PasteSample(name: "plain", plain: "Bread"))
            XCTAssertEqual(harness.blockSummary.prefix(2), ["task: Milk", "task: Bread"], "\(blocks.count)")
            XCTAssertFalse(harness.document.blocks.contains { $0.kind == "paragraph" }, "\(blocks.count)")
        }
        let end = EditorHarness(markdown: "- Milk")
        defer { end.close() }
        end.caret(at: end.text.length)
        end.paste(PasteSample(name: "plain", plain: " and bread"))
        XCTAssertEqual(end.blockSummary, ["bullet: Milk and bread"])
        XCTAssertEqual(end.document.blocks.count, 1, "No empty line after the list.")
        XCTAssertTrue(ListMarkers.hasOwnEnd(end.text))
        let start = EditorHarness(markdown: "- [ ] Milk\n- [ ] Eggs")
        defer { start.close() }
        start.caret(at: ("Milk\n" as NSString).length)
        start.paste(PasteSample(name: "plain", plain: "Bread\nButter"))
        XCTAssertEqual(start.blockSummary, ["task: Milk", "task: Bread", "task: ButterEggs"])
    }

    /// The next item continues the formatting where Return was pressed, not the item's first word.
    func testReturnContinuesTheFormattingAtTheCaret() throws {
        let harness = EditorHarness(markdown: "- **Note:** buy milk")
        defer { harness.close() }
        harness.caret(at: ("Note: buy milk" as NSString).length)
        harness.pressReturn()
        harness.type("eggs")
        let next = try XCTUnwrap(harness.document.blocks.last)
        XCTAssertEqual(next.kind, "bullet")
        XCTAssertEqual(next.runs.map(\.text).joined(), "eggs")
        XCTAssertFalse(next.runs.contains { $0.bold }, "The first word's bold isn't carried into the next item.")
    }

    /// Text with line breaks inserted into an item keeps its links and formatting; its lines continue the list.
    func testFormattedLinesInsertedIntoAnItemKeepTheirFormatting() throws {
        let harness = EditorHarness(markdown: "- Milk")
        defer { harness.close() }
        harness.caret(at: 4)
        let inserted = NSMutableAttributedString(string: " and ")
        inserted.append(
            NSAttributedString(string: "eggs", attributes: [.link: try XCTUnwrap(URL(string: "https://example.com"))]))
        inserted.append(NSAttributedString(string: "\nBread"))
        harness.insertForeign(inserted)
        XCTAssertEqual(harness.document.blocks.first?.runs.last?.link, "https://example.com", harness.document.markdown)
        XCTAssertEqual(harness.document.blocks.map(\.kind), ["bullet", "bullet"])
    }

    /// Deleting from a paragraph into the last item, or Select All and Delete, leaves the caret in the text.
    func testDeletingIntoTheLastItemKeepsTheCaretInTheText() throws {
        let harness = EditorHarness(markdown: "Plain\n\n- Milk")
        defer { harness.close() }
        harness.caret(at: 5)
        harness.forwardDelete()
        XCTAssertEqual(harness.text.string, "PlainMilk")
        XCTAssertEqual(harness.selection, NSRange(location: 5, length: 0))
        XCTAssertEqual(harness.document.blocks.map(\.kind), ["paragraph"])
        let empty = EditorHarness(JournalDocument(blocks: [DocumentBlock(kind: "task")]))
        defer { empty.close() }
        empty.select(NSRange(location: 0, length: empty.text.length))
        empty.deleteBackward()
        XCTAssertEqual(empty.text.length, 0, "Select All and Delete removes an entry's only, empty item.")
    }

    /// Typing at the start of a line after a list continues that line, with its own indent.
    func testTypingAtTheStartOfALineAfterAListKeepsItsIndent() throws {
        let harness = EditorHarness(markdown: "- Milk\n\nPlain")
        defer { harness.close() }
        harness.caret(at: ("Milk\n" as NSString).length)
        harness.type("A")
        let style = harness.text.attribute(.paragraphStyle, at: ("Milk\n" as NSString).length, effectiveRange: nil)
        XCTAssertEqual((style as? NSParagraphStyle)?.firstLineHeadIndent ?? 0, 0)
        XCTAssertEqual(harness.document.blocks.map(\.kind), ["bullet", "paragraph"])
    }

    /// An input method composing at the start of an empty item keeps the item, its indent and its own line break.
    func testComposingInAnEmptyItemKeepsTheItem() throws {
        let milk = DocumentBlock(kind: "task", runs: [TextRun("Milk")])
        for blocks in [
            [milk, DocumentBlock(kind: "task"), DocumentBlock(kind: "task", runs: [TextRun("Eggs")])],
            [milk, DocumentBlock(kind: "task")],
        ] {
            let markdown = JournalDocument(blocks: blocks).markdown
            let harness = EditorHarness(JournalDocument(blocks: blocks))
            defer { harness.close() }
            harness.caret(at: ("Milk\n" as NSString).length)
            harness.compose("に")
            harness.compose("日本")
            harness.view.unmarkText()
            harness.settle()
            XCTAssertEqual(harness.document.blocks.map(\.kind).prefix(2), ["task", "task"], markdown)
            XCTAssertEqual(harness.document.blocks[1].runs.map(\.text).joined(), "日本", markdown)
            let style =
                harness.text.attribute(
                    .paragraphStyle, at: ("Milk\n" as NSString).length, effectiveRange: nil) as? NSParagraphStyle
            XCTAssertEqual(style?.headIndent, RichText.listColumn(size: 17), markdown)
        }
    }

    /// Other apps get lists as TextEdit and Pages write them: each item starts with its marker and a tab, in a list.
    func testOtherAppsGetListsWithTheirMarkers() throws {
        let harness = EditorHarness(markdown: "- [ ] Buy milk\n- [x] Call\n- Point\n1. First")
        defer { harness.close() }
        let shared = RichText.otherAppsText(harness.text, range: NSRange(location: 0, length: harness.text.length))
        XCTAssertEqual(shared.string, "☐\tBuy milk\n☑\tCall\n•\tPoint\n1.\tFirst")
        let rtf = try XCTUnwrap(
            try? shared.data(
                from: NSRange(location: 0, length: shared.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]))
        let read = try NSAttributedString(
            data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        let style = read.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.textLists.first?.markerFormat, .box)
        // A selection from inside an item's text has no marker: its formatting belongs to the start of its line.
        let inside = RichText.otherAppsText(harness.text, range: NSRange(location: 4, length: 4))
        XCTAssertEqual(inside.string, "milk")
    }

    /// List items and quotes carry what they are as accessibility text attributes, which the text views hand on to
    /// VoiceOver with the text, as the markers are drawn rather than written; the text itself, all the keyboard reads,
    /// stays as written. This holds for the item's text typed later, too.
    func testListLinesCarryTheirAccessibilityAttributes() throws {
        let harness = EditorHarness(
            markdown: "- Bread\n\n1. First\n2. Second\n\n- [ ] Milk\n- [x] Eggs\n  - [ ] Nested\n\n> Quoted\n\nPlain")
        defer { harness.close() }
        harness.caret(at: (harness.text.string as NSString).range(of: "Nested").upperBound)
        harness.pressReturn()
        harness.type("Typed")
        let source = harness.text.string as NSString
        #if os(macOS)
            let expected: [(String, String?, Int)] = [
                ("Bread", "•", 0), ("First", "1.", 0), ("Second", "2.", 0), ("Milk", "Checkbox, unchecked", 0),
                ("Eggs", "Checkbox, checked", 0), ("Nested", "Checkbox, unchecked", 1),
                ("Typed", "Checkbox, unchecked", 1),
                ("Plain", nil, 0),
            ]
            for (word, prefix, level) in expected {
                let read = try XCTUnwrap(harness.view.accessibilityAttributedString(for: source.range(of: word)), word)
                XCTAssertEqual(read.string, word, "Only the written text")
                let attributes = read.attributes(at: 0, effectiveRange: nil)
                XCTAssertEqual((attributes[.accessibilityListItemPrefix] as? NSAttributedString)?.string, prefix, word)
                if prefix != nil { XCTAssertEqual(attributes[.accessibilityListItemLevel] as? Int, level, word) }
            }
            let quote = try XCTUnwrap(harness.view.accessibilityAttributedString(for: source.range(of: "Quoted")))
            XCTAssertEqual(
                quote.attribute(.accessibilityCustomText, at: 0, effectiveRange: nil) as? [String], ["Quote"])
        #else
            let view = harness.view
            for (word, announcement) in [
                ("Bread", "Bullet"), ("Second", "2."), ("Milk", "Checkbox, unchecked"), ("Eggs", "Checkbox, checked"),
                ("Typed", "Checkbox, unchecked"), ("Quoted", "Quote"), ("Plain", nil),
            ] as [(String, String?)] {
                let line = source.range(of: word)
                let start = try XCTUnwrap(view.position(from: view.beginningOfDocument, offset: line.location))
                let end = try XCTUnwrap(view.position(from: start, offset: line.length))
                let range = try XCTUnwrap(view.textRange(from: start, to: end))
                let read = view.attributedText(in: range)
                XCTAssertEqual(read.string, view.text(in: range), "Only the written text, as the keyboard reads it")
                XCTAssertEqual(read.string, word)
                let custom = read.attribute(.accessibilityTextCustom, at: 0, effectiveRange: nil) as? [String]
                XCTAssertEqual(custom, announcement.map { [$0] }, word)
            }
        #endif
    }

    /// Every numbered item announces the number it shows, whether it was opened, typed with the shortcut or added
    /// with Return in the middle of the list.
    func testNumberedItemsAnnounceTheNumberTheyShow() throws {
        let harness = EditorHarness(markdown: "1. One\n2. Three\n\nAfter")
        defer { harness.close() }
        harness.caret(at: ("One" as NSString).length)
        harness.pressReturn()
        harness.type("Two")
        harness.caret(at: harness.text.length)
        harness.pressReturn()
        harness.type("4. ")
        harness.wait { harness.document.blocks.last?.kind == "numbered" }
        harness.type("Four")
        let text = harness.text
        let source = text.string as NSString
        var numbered = 0
        var position = 0
        while position < text.length {
            let paragraph = source.paragraphRange(for: NSRange(location: position, length: 0))
            position = NSMaxRange(paragraph)
            guard text.attribute(.journalKind, at: paragraph.location, effectiveRange: nil) as? String == "numbered"
            else {
                continue
            }
            numbered += 1
            let shown = try XCTUnwrap(
                text.attribute(.journalListNumber, at: paragraph.location, effectiveRange: nil) as? Int)
            #if os(macOS)
                let announced =
                    (text.attribute(.accessibilityListItemPrefix, at: paragraph.location, effectiveRange: nil)
                    as? NSAttributedString)?.string
            #else
                let announced =
                    (text.attribute(.accessibilityTextCustom, at: paragraph.location, effectiveRange: nil)
                    as? [String])?.first
            #endif
            XCTAssertEqual(announced, "\(shown).", source.substring(with: paragraph))
        }
        XCTAssertEqual(numbered, 4)
    }

    /// The empty item a Return left at the end stays an item when the item above it is checked or indented: the
    /// change above doesn't take the empty item's own line break.
    func testChangingTheItemAboveAnEmptyLastItemKeepsIt() throws {
        for (markdown, key, kinds) in [
            ("- [ ] Milk", StructuredKeyboard.Key.toggleTask, ["checked", "task"]),
            ("- Milk\n- Eggs", .indent, ["bullet", "bullet", "bullet"]),
        ] {
            let harness = EditorHarness(markdown: markdown)
            defer { harness.close() }
            harness.caret(at: harness.text.length)
            harness.pressReturn()
            harness.caret(at: harness.text.length - 2)
            XCTAssertTrue(harness.coordinator.performStructuralKey(key), markdown)
            XCTAssertEqual(harness.document.blocks.map(\.kind), kinds, markdown)
            XCTAssertTrue(ListMarkers.hasOwnEnd(harness.text), markdown)
        }
    }

    /// Undo puts back deleted items exactly as they were: their identity, kind and checked state, and the lines after
    /// them stay what they were. The lines that come back aren't new items continuing the list.
    func testUndoingADeletionAcrossItemsBringsThemBackAsTheyWere() throws {
        try checkUndoAndRedo(
            "Select All and Delete", JournalDocument(markdown: "# Groceries\n\n- [x] Milk\n- [x] Eggs\n\nNotes"),
            exactMarkdown: false
        ) { harness in
            harness.select(NSRange(location: 0, length: harness.text.length))
            harness.deleteBackward()
        }
        try checkUndoAndRedo(
            "Deleting across checked items", JournalDocument(markdown: "- [x] One\n- [ ] Two\n- [x] Three\n\nAfter")
        ) { harness in
            harness.select(NSRange(location: 2, length: 8))
            harness.deleteBackward()
        }
    }

    /// Return over a whole selected line, as a triple-click selects it with its line break, doesn't turn the next line
    /// into an item of the list.
    func testReturnOverAWholeSelectedLineLeavesTheNextLineAlone() throws {
        let harness = EditorHarness(markdown: "- Milk\n\n## Eggs")
        defer { harness.close() }
        harness.select(NSRange(location: 0, length: ("Milk\n" as NSString).length))
        harness.pressReturn()
        XCTAssertEqual(harness.document.blocks.last?.kind, "subheading")
        XCTAssertEqual(harness.document.blocks.last?.runs.map(\.text).joined(), "Eggs")
    }

    /// A list style chosen for an empty line in the Format panel keeps one identity for the item while it's typed,
    /// so it's read as one block rather than a new one at each key.
    func testAListStyleChosenForAnEmptyLineKeepsItsIdentityWhileTyping() throws {
        let harness = EditorHarness(
            JournalDocument(blocks: [
                DocumentBlock(runs: [TextRun("A")]), DocumentBlock(), DocumentBlock(runs: [TextRun("B")]),
            ]))
        defer { harness.close() }
        harness.caret(at: 2)
        harness.coordinator.perform(.paragraph("task"))
        harness.type("Milk")
        let identity = harness.document.blocks[1].id
        harness.type("s")
        XCTAssertEqual(harness.document.blocks[1].kind, "task")
        XCTAssertEqual(harness.document.blocks[1].id, identity)
    }

    /// Typing over a selection that joins lines takes the paragraph where the selection starts, as TextEdit and Notes
    /// do: a plain line typed into from above stays plain, and an item typed over into a paragraph stays an item. The
    /// last item's attributes and its own line break don't stay on the rest of the line. Undo restores it exactly.
    func testTypingOverLinesTakesTheLineWhereTheSelectionStarts() throws {
        let cases: [(String, String, NSRange, [String])] = [
            ("into the last item", "Plain line\n\n- [x] Done", NSRange(location: 6, length: 7), ["paragraph"]),
            ("from a line's start", "Plain line\n\n- [x] Done", NSRange(location: 0, length: 13), ["paragraph"]),
            ("from an item", "- [x] Done\n\nPlain line", NSRange(location: 2, length: 7), ["checked"]),
        ]
        for (name, markdown, selection, kinds) in cases {
            let harness = EditorHarness(markdown: markdown)
            defer { harness.close() }
            harness.select(selection)
            harness.type("X")
            XCTAssertEqual(harness.document.blocks.map(\.kind), kinds, name)
            XCTAssertFalse(ListMarkers.hasOwnEnd(harness.text) && kinds == ["paragraph"], name)
            harness.caret(at: harness.text.length - (ListMarkers.hasOwnEnd(harness.text) ? 1 : 0))
            harness.pressReturn()
            harness.type("Y")
            XCTAssertEqual(
                harness.document.blocks.map(\.kind), kinds + [kinds == ["paragraph"] ? "paragraph" : "task"], name)
            try checkUndoAndRedo("Typing " + name, JournalDocument(markdown: markdown)) { harness in
                harness.select(selection)
                harness.type("X")
            }
        }
    }

    /// An input method composing over a selection across lines composes there; the text system replaces the selection.
    func testComposingOverLinesStillComposes() throws {
        let harness = EditorHarness(markdown: "Plain line\n\n- [x] Done")
        defer { harness.close() }
        harness.select(NSRange(location: 6, length: 7))
        harness.compose("に")
        XCTAssertTrue(harness.isComposing)
        harness.compose("日本")
        harness.view.unmarkText()
        harness.settle()
        XCTAssertTrue(harness.document.text.contains("Plain 日本ne"))
    }

    /// An empty item with an item nested under it is shown and saved as it is: typing elsewhere leaves its Markdown
    /// unchanged, and typing into it fills the empty item, not the nested one.
    func testAnEmptyItemAboveANestedItemReadsBackUnchanged() throws {
        for markdown in ["- Before\n- \n  - Nested\n- After", "1. Before\n2. \n   - Nested\n3. After"] {
            let harness = EditorHarness(markdown: markdown)
            defer { harness.close() }
            let kinds = harness.document.blocks.map(\.kind)
            XCTAssertEqual(kinds.count, 4, markdown)
            harness.select("After")
            harness.caret(at: NSMaxRange(harness.selection))
            harness.type("!")
            XCTAssertEqual(harness.document.markdown, markdown + "!", markdown)
            let empty = (harness.text.string as NSString).range(of: "Before\n").upperBound
            harness.caret(at: empty)
            harness.type("Filled")
            XCTAssertEqual(
                harness.document.blocks.map { $0.runs.map(\.text).joined() }, ["Before", "Filled", "Nested", "After!"])
            XCTAssertEqual(harness.document.blocks.map(\.kind), kinds, markdown)
            XCTAssertEqual(JournalDocument(markdown: harness.document.markdown).blocks.map(\.kind), kinds, markdown)
        }
    }

    // MARK: - Helpers

    /// Each block but empty paragraphs, whose identity isn't kept: its identity, kind, number and text.
    private static func items(_ document: JournalDocument) -> [String] {
        document.blocks.filter { $0.kind != "paragraph" || !$0.runs.isEmpty }.map {
            "\($0.id) \($0.kind) \($0.listNumber.map(String.init) ?? "-") \($0.runs.map(\.text).joined())"
        }
    }

    /// With `exactMarkdown` off, only what the blocks are is compared: text read back whole (after Select All) is
    /// written with the usual spacing between items.
    private func checkUndoAndRedo(
        _ name: String, _ document: JournalDocument, exactMarkdown: Bool = true, edit: (EditorHarness) -> Void
    ) throws {
        let harness = EditorHarness(document)
        defer { harness.close() }
        let undo = try XCTUnwrap(harness.undoManager)
        harness.settle()
        undo.groupsByEvent = false
        while undo.groupingLevel > 0 { undo.endUndoGrouping() }
        undo.removeAllActions()
        let before = harness.document
        undo.beginUndoGrouping()
        edit(harness)
        undo.endUndoGrouping()
        let after = harness.document
        XCTAssertNotEqual(after, before, name)
        undo.undo()
        harness.settle()
        XCTAssertEqual(Self.items(harness.document), Self.items(before), name)
        if exactMarkdown { XCTAssertEqual(harness.document.markdown, before.markdown, name) }
        undo.redo()
        harness.settle()
        XCTAssertEqual(Self.items(harness.document), Self.items(after), name)
        if exactMarkdown { XCTAssertEqual(harness.document.markdown, after.markdown, name) }
    }
}

extension EditorHarness {
    /// Deletes forward, as fn-Delete does.
    func forwardDelete() {
        #if os(macOS)
            view.doCommand(by: #selector(NSResponder.deleteForward(_:)))
        #else
            let range = selection.length > 0 ? selection : NSRange(location: selection.location, length: 1)
            guard NSMaxRange(range) <= text.length,
                coordinator.textView(view, shouldChangeTextIn: range, replacementText: "")
            else { return }
            view.textStorage.replaceCharacters(in: range, with: "")
            view.selectedRange = NSRange(location: range.location, length: 0)
            coordinator.textViewDidChange(view)
        #endif
    }
    /// Inserts text as one piece, as dictation does, with the delegate's chance to handle it.
    func insertTyped(_ string: String) {
        #if os(macOS)
            view.insertText(string, replacementRange: view.selectedRange())
        #else
            if coordinator.textView(view, shouldChangeTextIn: view.selectedRange, replacementText: string) {
                view.insertText(string)
            }
        #endif
    }
}
