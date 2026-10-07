import JournalCore
import XCTest

@testable import Journal

@MainActor
final class LinkInsertionTests: XCTestCase {
    func testAddingLinkPreservesMixedSelectionFormattingAndSupportsNewDisplayText() throws {
        let document = JournalDocument(blocks: [DocumentBlock(runs: [TextRun("Bold", bold: true), TextRun(" plain")])])
        let source = RichText.render(document, size: 17, images: [:])
        let state = FormattingState(text: source, range: NSRange(location: 0, length: source.length), typing: [:])
        XCTAssertEqual(state.bold, .mixed)
        XCTAssertEqual(state.italic, .off)
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let linked = LinkInsertion.text(
            source, selection: NSRange(location: 0, length: source.length), address: url.absoluteString,
            displayText: source.string, attributes: [:], url: url)
        let restored = RichText.document(linked)
        XCTAssertEqual(restored.blocks[0].runs.map(\.text), ["Bold", " plain"])
        XCTAssertTrue(restored.blocks[0].runs[0].bold)
        XCTAssertFalse(restored.blocks[0].runs[1].bold)
        XCTAssertTrue(restored.blocks[0].runs.allSatisfy { $0.link == url.absoluteString })
        let inserted = LinkInsertion.text(
            source, selection: NSRange(location: source.length, length: 0), address: url.absoluteString,
            displayText: "Useful resource", attributes: RichText.attributes(kind: "paragraph", size: 17), url: url)
        XCTAssertEqual(inserted.string, "Useful resource")
        XCTAssertEqual(inserted.attribute(.link, at: 0, effectiveRange: nil) as? URL, url)
    }
    /// Add Link enables its button for a scheme in any case, so the editor has to insert that link.
    func testAddLinkInsertsAddressesWhoseSchemeIsNotLowercase() throws {
        for (address, expected) in [
            ("HTTPS://example.com/Path", "https://example.com/Path"),
            ("Http://example.com", "http://example.com"),
            ("MailTo:someone@example.com", "mailto:someone@example.com"),
        ] {
            let harness = EditorHarness(markdown: "Target words")
            defer { harness.close() }
            harness.select("Target")
            harness.actions.captureFormatting()
            harness.actions.performFormatting(.link(address))
            let runs = try XCTUnwrap(harness.document.blocks.first?.runs)
            XCTAssertEqual(runs.first?.text, "Target", address)
            XCTAssertEqual(runs.first?.link, expected, address)
            XCTAssertEqual(runs.last?.link, nil, address)
        }
    }
    /// Like Notes, Add Link completes an email address or a host typed without a scheme.
    func testAddLinkCompletesEmailAndWebAddressesWithoutAScheme() throws {
        for (address, expected) in [
            ("name@example.com", "mailto:name@example.com"),
            ("www.apple.com", "https://www.apple.com"),
            (" example.com/path?q=1 ", "https://example.com/path?q=1"),
        ] {
            let harness = EditorHarness(markdown: "Target words")
            defer { harness.close() }
            harness.select("Target")
            harness.actions.captureFormatting()
            harness.actions.performFormatting(.link(address))
            XCTAssertEqual(harness.document.blocks.first?.runs.first?.link, expected, address)
        }
        for invalid in [
            "not a link", "localhost", "e.g", "name@host", "@example.com", "javascript:alert(1)", "tel:123",
        ] {
            XCTAssertNil(LinkAddress.url(invalid), invalid)
        }
    }

    // MARK: Editing and removing a link (docs/design/build-18-fixes-2026-10-06.md §2.4)

    private func linked(_ harness: EditorHarness, _ word: String) throws -> EditableLink {
        harness.select(word)
        harness.actions.captureFormatting()
        return try XCTUnwrap(LinkEditing.link(in: harness.text, selection: harness.selection), word)
    }
    private func runs(_ harness: EditorHarness) -> [TextRun] { harness.document.blocks.flatMap(\.runs) }

    func testChangingOnlyTheAddressKeepsTheTextAndItsFormatting() throws {
        let document = JournalDocument(blocks: [
            DocumentBlock(runs: [
                TextRun("See "), TextRun("the bold", bold: true, link: "https://old.example"), TextRun(" end"),
            ])
        ])
        let harness = EditorHarness(document)
        defer { harness.close() }
        harness.caret(at: ("See the" as NSString).length)
        let link = try XCTUnwrap(LinkEditing.link(in: harness.text, selection: harness.selection))
        XCTAssertEqual(link.address, "https://old.example")
        XCTAssertEqual(link.text, "the bold")
        XCTAssertTrue(link.editsText)
        harness.actions.captureFormatting()
        harness.actions.performFormatting(.editLink(link, address: "new.example", text: nil))
        let edited = runs(harness)
        XCTAssertEqual(edited.map(\.text), ["See ", "the bold", " end"])
        XCTAssertEqual(edited.map(\.link), [nil, "https://new.example", nil])
        XCTAssertTrue(edited[1].bold)
    }

    func testChangingTheTextKeepsTheLinkAndTheFirstCharactersFormatting() throws {
        let document = JournalDocument(blocks: [
            DocumentBlock(runs: [
                TextRun("Open "), TextRun("bold", bold: true, link: "https://example.com"),
                TextRun(" and plain", link: "https://example.com"),
            ])
        ])
        let harness = EditorHarness(document)
        defer { harness.close() }
        let link = try linked(harness, "bold")
        XCTAssertEqual(link.text, "bold and plain", "One address over differently formatted words is one link.")
        harness.actions.performFormatting(.editLink(link, address: "https://example.com", text: "Renamed"))
        let edited = runs(harness)
        XCTAssertEqual(edited.map(\.text), ["Open ", "Renamed"])
        XCTAssertEqual(edited.last?.link, "https://example.com")
        XCTAssertEqual(edited.last?.bold, true, "The text is formatted as the link's first character was.")
    }

    /// A link around a picture can change its address, never its characters, so the picture can't be dropped.
    func testALinkAroundAnInlineImageKeepsTheImageWhenItsAddressChanges() throws {
        let document = JournalDocument(
            markdown: "Before [![A view](https://example.com/view.png)](https://old.example) after")
        let harness = EditorHarness(document)
        defer { harness.close() }
        let imageRuns = runs(harness).filter { $0.imageSource != nil }
        XCTAssertEqual(imageRuns.count, 1, harness.document.markdown)
        let attachment = (harness.text.string as NSString).range(of: "\u{FFFC}")
        XCTAssertNotEqual(attachment.location, NSNotFound)
        harness.select(attachment)
        let link = try XCTUnwrap(LinkEditing.link(in: harness.text, selection: harness.selection))
        XCTAssertFalse(link.editsText, "The Text row isn't shown for a link that holds a picture.")
        harness.actions.captureFormatting()
        harness.actions.performFormatting(.editLink(link, address: "https://new.example", text: "Dropped"))
        let after = runs(harness)
        XCTAssertEqual(after.filter { $0.imageSource != nil }.count, 1, harness.document.markdown)
        XCTAssertEqual(after.first { $0.imageSource != nil }?.link, "https://new.example", harness.document.markdown)
        XCTAssertFalse(harness.document.markdown.contains("Dropped"), harness.document.markdown)
    }

    func testRemovingALinkKeepsItsTextAndFormattingAndIsOneUndoStep() throws {
        let document = JournalDocument(blocks: [
            DocumentBlock(runs: [
                TextRun("One "), TextRun("two", bold: true, link: "https://example.com"), TextRun(" three"),
            ])
        ])
        let harness = EditorHarness(document)
        defer { harness.close() }
        let undo = try XCTUnwrap(harness.undoManager)
        harness.settle()
        undo.removeAllActions()
        // A selection that covers only part of the link removes the whole link.
        harness.select(NSRange(location: 5, length: 1))
        harness.actions.perform(.removeLink(nil))
        let removed = runs(harness)
        XCTAssertEqual(removed.map(\.text).joined(), "One two three")
        XCTAssertTrue(removed.allSatisfy { $0.link == nil })
        XCTAssertEqual(removed.first { $0.text.contains("two") }?.bold, true)
        XCTAssertEqual(harness.selection, NSRange(location: 5, length: 1), "The selection stays where it was.")
        XCTAssertEqual(undo.undoActionName, "Remove Link")
        undo.undo()
        harness.settle()
        XCTAssertEqual(runs(harness).filter { $0.link != nil }.map(\.text), ["two"])
    }

    func testASelectionAcrossLinksOffersAddLinkAndRemovesEveryLinkItTouches() throws {
        let document = JournalDocument(blocks: [
            DocumentBlock(runs: [
                TextRun("a", link: "https://one.example"), TextRun(" and "),
                TextRun("b", link: "https://two.example"), TextRun(" plain"),
            ])
        ])
        let harness = EditorHarness(document)
        defer { harness.close() }
        let across = NSRange(location: 0, length: 7)
        XCTAssertNil(LinkEditing.link(in: harness.text, selection: across), "No single link to edit.")
        XCTAssertEqual(
            LinkEditing.availability(harness.text, selection: across), LinkAvailability(edit: false, remove: true))
        XCTAssertEqual(LinkEditing.ranges(in: harness.text, touching: across).count, 2)
        harness.select(across)
        harness.actions.perform(.removeLink(nil))
        XCTAssertTrue(runs(harness).allSatisfy { $0.link == nil })
        XCTAssertEqual(runs(harness).map(\.text).joined(), "a and b plain")
        XCTAssertEqual(
            LinkEditing.availability(harness.text, selection: NSRange(location: 10, length: 0)), LinkAvailability())
    }

    /// The character before the caret decides first, so the caret at the end of a link is in it, and after a link's
    /// own text a new link can't be started without typing something first.
    func testACaretAtEitherEndOfALinkIsInIt() throws {
        let document = JournalDocument(blocks: [
            DocumentBlock(runs: [TextRun("go "), TextRun("here", link: "https://example.com"), TextRun(" now")])
        ])
        let harness = EditorHarness(document)
        defer { harness.close() }
        for location in [3, 5, 7] {
            XCTAssertEqual(
                LinkEditing.link(in: harness.text, selection: NSRange(location: location, length: 0))?.text, "here",
                "\(location)")
        }
        XCTAssertNil(LinkEditing.link(in: harness.text, selection: NSRange(location: 2, length: 0)))
        XCTAssertNil(LinkEditing.link(in: harness.text, selection: NSRange(location: 8, length: 0)))
    }

    /// An email link is shown as typed, without “mailto:”; one whose address the app doesn't open is kept as text,
    /// shown as it is, and can still be removed.
    func testEmailAndInertLinksAreShownAsTheyAreAndCanBeRemoved() throws {
        let document = JournalDocument(blocks: [
            DocumentBlock(runs: [
                TextRun("write "), TextRun("me", link: "mailto:me@example.com"), TextRun(" or "),
                TextRun("call", link: "tel:123"),
            ])
        ])
        let harness = EditorHarness(document)
        defer { harness.close() }
        let mail = try linked(harness, "me")
        XCTAssertEqual(mail.address, "me@example.com")
        let call = try linked(harness, "call")
        XCTAssertEqual(call.address, "tel:123")
        XCTAssertNil(LinkAddress.url(call.address), "Done stays dimmed until the address is corrected.")
        harness.actions.perform(.removeLink(nil))
        XCTAssertEqual(runs(harness).filter { $0.link != nil }.map(\.text), ["me"])
        XCTAssertEqual(runs(harness).map(\.text).joined(), "write me or call")
    }

    #if os(iOS)
        /// ⌘K opens Add Link with the selected text as the link's text. (The UI test presses ⌘K without a selection,
        /// since a tap to select shows the edit menu, which takes the next keys.)
        func testCommandKOpensAddLinkWithTheSelectedText() throws {
            let harness = EditorHarness(markdown: "Some words to select")
            defer { harness.close() }
            harness.select("words")
            let commandK = try XCTUnwrap(
                harness.view.keyCommands?.first { $0.input == "k" && $0.modifierFlags == .command })
            let command = try XCTUnwrap(KeyboardFormatting.command(for: commandK))
            harness.view.keyboardFormatting?(command)
            XCTAssertTrue(harness.actions.requestLink)
            XCTAssertEqual(harness.actions.linkText, "words")
        }
    #endif
}
