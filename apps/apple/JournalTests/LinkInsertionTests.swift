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
