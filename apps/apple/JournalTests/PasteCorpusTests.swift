import JournalCore
import Network
import SwiftUI
import UniformTypeIdentifiers
import XCTest
import os

@testable import Journal

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// What another app puts on the pasteboard. PasteCorpus holds what common apps copy: web pages from Safari and
/// Chrome, Mail, Notes, Pages, TextEdit, Google Docs, Word, Xcode and VS Code.
struct PasteSample {
    let name: String
    var rtf: Data?
    var rtfd: Data?
    var html: Data?
    var plain: String?

    init(name: String, rtf: Data? = nil, rtfd: Data? = nil, html: Data? = nil, plain: String? = nil) {
        self.name = name
        self.rtf = rtf
        self.rtfd = rtfd
        self.html = html
        self.plain = plain
    }

    static func html(_ page: String, plain: String = "") -> PasteSample {
        PasteSample(name: page, html: Data(("<meta charset=\"utf-8\">" + page).utf8), plain: plain)
    }

    static func corpus(_ name: String) throws -> PasteSample {
        let bundle = Bundle(for: PasteCorpusTests.self)
        func data(_ type: String) -> Data? {
            bundle.url(forResource: name, withExtension: type).flatMap { try? Data(contentsOf: $0) }
        }
        let sample = PasteSample(
            name: name, rtf: data("rtf"), rtfd: data("flatrtfd"), html: data("html"),
            plain: data("txt").map { String(decoding: $0, as: UTF8.self) })
        XCTAssertTrue(sample.rtf != nil || sample.html != nil || sample.plain != nil, "No corpus files for \(name)")
        return sample
    }

    #if os(macOS)
        func write(to board: NSPasteboard) {
            board.clearContents()
            let types: [(NSPasteboard.PasteboardType, Data?)] = [
                (.rtfd, rtfd), (.rtf, rtf), (.html, html), (.string, plain.map { Data($0.utf8) }),
            ]
            board.declareTypes(types.filter { $0.1 != nil }.map(\.0), owner: nil)
            for (type, data) in types {
                if let data { board.setData(data, forType: type) }
            }
        }
    #else
        func write(to board: UIPasteboard) {
            var item: [String: Any] = [:]
            if let rtfd { item[UTType.flatRTFD.identifier] = rtfd }
            if let rtf { item[UTType.rtf.identifier] = rtf }
            if let html { item[UTType.html.identifier] = html }
            if let plain { item[UTType.utf8PlainText.identifier] = plain }
            board.setItems([item])
        }
    #endif
}

extension EditorHarness {
    /// Pastes the sample as the Paste command does, from a pasteboard of the test's own, so no system paste prompt
    /// can appear.
    func paste(_ sample: PasteSample) {
        #if os(macOS)
            let board = NSPasteboard(name: NSPasteboard.Name("PasteCorpus-" + UUID().uuidString))
            defer { board.releaseGlobally() }
            sample.write(to: board)
            if !view.pasteJournalContent(from: board) {
                XCTAssertTrue(view.readSelection(from: board), sample.name)
            }
        #else
            let board = UIPasteboard.withUniqueName()
            defer { UIPasteboard.remove(withName: board.name) }
            sample.write(to: board)
            XCTAssertTrue(view.pasteJournalContent(from: board), sample.name)
        #endif
        settle()
    }

    /// The entry's blocks as "kind: text", with a numbered item's number and a nested item's level.
    var blockSummary: [String] {
        document.blocks.filter { $0.kind != "paragraph" || !$0.runs.isEmpty }.map(Self.summary)
    }

    static func summary(_ block: DocumentBlock) -> String {
        var kind = block.kind
        if let number = block.listNumber { kind += " \(number)" }
        if let level = block.listIndents?.count, level > 0 { kind += " >\(level)" }
        if let table = block.table {
            let rows = table.rows.map { $0.map { $0.map(\.text).joined() }.joined(separator: "|") }
            return kind + ": " + rows.joined(separator: " / ")
        }
        let text = block.runs.map(\.text).joined()
        // Code keeps the line break that ends it.
        return kind + ": " + (block.kind == "codeBlock" && text.hasSuffix("\n") ? String(text.dropLast()) : text)
    }
}

/// Text pasted from other apps arrives as the entry's own blocks, without their fonts, colours or spacing, loads
/// nothing, and is one step that undo takes back.
@MainActor final class PasteCorpusTests: XCTestCase {
    private static let article = [
        "heading: Learning to rest", "paragraph: By Sam Lee · 4 min read",
        "paragraph: Most of us treat rest as a reward. It works better as a habit. Here is what helped me, with notes "
            + "from a 2024 study.",
        "subheading: What changed", "bullet: Short walks after lunch", "bullet: No email after 7 pm",
        "bullet >1: Phone in another room", "bullet: Reading on paper", "numbered 1: Pick one habit",
        "numbered 2: Keep it for two weeks",
        // Neither Safari's RTF nor UIKit's reading of a page marks its quotation, so it is a plain paragraph.
        "paragraph: Rest is not idleness.", "paragraph: To check your screen time, run defaults read in Terminal:",
        "codeBlock: let minutes = 30\nprint(minutes)", "paragraph: Thanks for reading.",
    ]
    #if os(macOS)
        private static let table = [
            "paragraph: Training plan:", "table: Day|Distance|Notes / Monday|5 km|Easy / Wednesday|8 km|Tempo",
            "paragraph: Rest on Sunday.",
        ]
    #else
        // UIKit reads a table as a paragraph for each cell, so its plain text is pasted, a row on each line.
        private static let table = [
            "paragraph: Training plan:", "paragraph: Day\tDistance\tNotes", "paragraph: Monday\t5 km\tEasy",
            "paragraph: Wednesday\t8 km\tTempo", "paragraph: Rest on Sunday.",
        ]
    #endif
    private static let expected: [String: [String]] = [
        "safari-article": article,
        "chrome-article": article,
        "safari-table": table,
        "safari-international": [
            "paragraph: Family dinner 👨‍👩‍👧‍👦 🇧🇪 🎉 — café, naïve, Zoë", "paragraph: مرحبا بكم في المجلة",
            "paragraph: שלום, זה יומן", "paragraph: 今日はとても良い天気でした。", "bullet: 中文项目", "bullet: 한국어 항목",
        ],
        "mail-reply": [
            "paragraph: Hi Alex,", "paragraph: Thursday works for me. I’ll bring the printed agenda.",
            "paragraph: Ralph", "paragraph: On 30 Sep 2026, at 18:02, Alex Kim <alex@example.com> wrote:",
            "paragraph: Can we meet on Thursday at 10?", "paragraph: – Alex",
        ],
        "apple-notes": [
            "heading: Weekend plans", "subheading: Saturday", "bullet: Farmers market", "bullet: Call Mum",
            "bullet >1: Bring the tote bag", "bullet: Bike tyres", "numbered 1: Clean the kitchen",
            "numbered 2: Water the plants", "task: Book the train", "checked: Pay the rent",
            "paragraph: Body text after the list.", "codeBlock: ssh home.local\nuptime",
        ],
        "pages": [
            "heading: Project Brief", "subheading: Goals",
            "paragraph: We want fewer meetings and clearer notes. Underlined, struck and Times words.",
            "numbered 3: Third point", "numbered 4: Fourth point", "paragraph: Small print",
        ],
        "textedit": [
            "paragraph: Shopping: milk, eggs", "bullet: Apples", "bullet: Pears", "bullet >1: Conference pears",
            "paragraph: Done.",
        ],
        "google-docs": [
            "heading: Weekly review", "paragraph: Shipped the sync fix and wrote the notes.", "subheading: Next week",
            "bullet: Plan Q4", "bullet >1: Draft budget", "bullet: Hire a designer", "numbered 1: Review PRs",
            "numbered 2: Ship beta", "paragraph: Written in a hurry.",
        ],
        "word": [
            "subheading: Meeting notes", "paragraph: Attendees: Ana, Ben, Chloé.", "bullet: Budget approved",
            "bullet: Launch moved to November", "numbered 1: Send the minutes", "paragraph: Next meeting: Friday",
        ],
        "xcode": [
            "codeBlock: import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n"
                + "        Text(\"Hello\")\n    }\n}"
        ],
        "vscode": ["codeBlock: import os\n\ndef greet(name):\n    return f\"Hello, {name}\""],
        // Markdown copied as plain text stays the text it is, line by line.
        "markdown": [
            "paragraph: # Packing list", "paragraph: - [ ] Passport", "paragraph: - [x] Charger",
            "paragraph: - Socks *(wool)*", "paragraph: 1. Book taxi", "paragraph: 2. Check in",
            "paragraph: > Travel light.", "paragraph: ```", "paragraph: flight = \"BA 389\"", "paragraph: ```",
        ],
    ]

    func testTextFromCommonAppsBecomesCleanEntryBlocks() throws {
        for (name, blocks) in Self.expected.sorted(by: { $0.key < $1.key }) {
            let harness = EditorHarness(markdown: "")
            defer { harness.close() }
            harness.paste(try PasteSample.corpus(name))
            XCTAssertEqual(harness.blockSummary, blocks, name)
            Self.assertClean(harness, name)
        }
    }

    /// Links keep their web or email address and lose the underline every app draws them with; a link to part of
    /// the page it came from, or to a script, keeps only its text. Inline code stays code.
    func testLinksAndInlineCodeFromAWebPage() throws {
        let harness = EditorHarness(markdown: "")
        defer { harness.close() }
        harness.paste(try PasteSample.corpus("safari-article"))
        let runs = harness.document.blocks.flatMap(\.runs)
        let links = runs.filter { $0.link != nil }
        XCTAssertEqual(links.map(\.text), ["Sam Lee", "a 2024 study"])
        XCTAssertEqual(links.map(\.link), ["https://example.com/authors/sam", "https://example.org/study"])
        XCTAssertFalse(runs.contains { $0.underline })
        XCTAssertEqual(runs.filter(\.code).map(\.text), ["defaults read"])
        let page = EditorHarness(markdown: "")
        defer { page.close() }
        page.paste(
            .html(
                "<p><a href=\"#notes\">Notes</a>, <a href=\"/about\">about</a>, <a href=\"javascript:alert(1)\">run</a>"
                    + " and <a href=\"mailto:ana@example.com\">Ana</a></p>"))
        let pageRuns = page.document.blocks.flatMap(\.runs)
        XCTAssertEqual(pageRuns.map(\.text).joined(), "Notes, about, run and Ana")
        XCTAssertEqual(pageRuns.compactMap(\.link), ["mailto:ana@example.com"])
        XCTAssertFalse(pageRuns.contains { $0.underline })
    }

    /// Pictures copied with text arrive where they were, as the entry's own images, with no empty line beside them.
    func testPicturesCopiedWithTextArriveWhereTheyWere() throws {
        let stored = UUID()
        let received = Received()
        let harness = EditorHarness(JournalDocument()) { data in
            received.data.append(data)
            return DocumentBlock(kind: "image", attachmentID: stored, imageDescription: "", mediaType: "image/png")
        }
        defer { harness.close() }
        harness.paste(try PasteSample.corpus("safari-images"))
        harness.wait { harness.document.references(to: stored) == 1 }
        XCTAssertEqual(
            harness.blockSummary,
            [
                "subheading: Morning walk", "paragraph: The light on the river was lovely.", "image: ",
                "bullet: Took the long way", "bullet: Saw a heron",
            ])
        XCTAssertEqual(received.data.count, 1)
        XCTAssertFalse(harness.document.markdown.contains("\u{FFFC}"))
        // The picture is part of the paste, which one Undo takes back.
        harness.undoManager?.undo()
        harness.settle()
        XCTAssertEqual(harness.blockSummary, [])
    }

    /// A picture that finishes importing after editing ended still arrives, and leaves undo as it was. Its undo
    /// manager changed meanwhile, which once stopped the app.
    func testPictureImportedAfterEditingEndsStillArrives() throws {
        let stored = UUID()
        let harness = EditorHarness(JournalDocument()) { _ in
            try? await Task.sleep(nanoseconds: 200_000_000)
            return DocumentBlock(kind: "image", attachmentID: stored, imageDescription: "", mediaType: "image/png")
        }
        defer { harness.close() }
        harness.paste(try PasteSample.corpus("safari-images"))
        #if os(macOS)
            XCTAssertTrue(harness.window.makeFirstResponder(nil))
        #else
            XCTAssertTrue(harness.view.resignFirstResponder())
        #endif
        harness.wait { harness.document.references(to: stored) == 1 }
        XCTAssertEqual(harness.document.references(to: stored), 1, harness.document.markdown)
    }

    #if os(macOS)
        /// Paste and Match Style pastes the plain text, whose lines continue the list they land in.
        func testPasteAndMatchStylePastesThePlainText() throws {
            let harness = EditorHarness(markdown: "- Milk\n- Bread")
            defer { harness.close() }
            harness.caret(at: 6)
            let board = NSPasteboard(name: NSPasteboard.Name("PasteCorpus-" + UUID().uuidString))
            defer { board.releaseGlobally() }
            PasteSample.html("<h1>Eggs</h1><p>Jam</p>", plain: " and eggs\nJam").write(to: board)
            // The type the text view's Paste and Match Style reads.
            XCTAssertTrue(harness.view.readSelection(from: board, type: .init("NSStringWithLinksPboardType")))
            XCTAssertEqual(harness.blockSummary, ["bullet: Milk and eggs", "bullet: Jam", "bullet: Bread"])
        }
    #endif

    /// Pasting a web page loads nothing it refers to: no pictures, style sheets or frames.
    func testPastingAWebPageLoadsNothingItRefersTo() throws {
        let server = try RequestCounter()
        defer { server.stop() }
        let address = "http://127.0.0.1:\(server.port)"
        let pages = [
            "<h2>Trip</h2><p>Day one</p><img src=\"\(address)/photo.png\"><ul><li>Pack</li></ul>"
                + "<link rel=\"stylesheet\" href=\"\(address)/style.css\">",
            "<p style=\"background: url(\(address)/back.png)\">Day two</p><iframe src=\"\(address)/frame\"></iframe>",
        ]
        var pasted: [[String]] = []
        for (page, plain) in zip(pages, ["Trip\nDay one\nPack", "Day two"]) {
            let harness = EditorHarness(markdown: "")
            defer { harness.close() }
            harness.paste(.html(page, plain: plain))
            harness.settle(0.5)
            pasted.append(harness.blockSummary)
        }
        XCTAssertEqual(server.requests, 0)
        // A page's pictures are left out; a page that refers to anything else is pasted as its plain text.
        XCTAssertEqual(pasted, [["subheading: Trip", "paragraph: Day one", "bullet: Pack"], ["paragraph: Day two"]])
    }

    /// Pasted text joins the paragraph it lands in, and the rest of that paragraph follows it on its own line when
    /// the copied text ended with one. The caret ends after the pasted text, and undo restores the entry and caret.
    func testPastingIntoAnEntryKeepsWhatWasAroundItAndUndoRestoresIt() throws {
        let list = PasteSample.html("<p>One <b>two</b></p><ul><li>three</li><li>four</li></ul>")
        let answerLine = JournalDocument(blocks: [
            DocumentBlock(kind: "heading", runs: [TextRun("Today")]), DocumentBlock(),
            DocumentBlock(runs: [TextRun("Later")]),
        ])
        let cases: [(String, JournalDocument, (EditorHarness) -> Void, PasteSample, [String], String)] = [
            (
                "blocks within a paragraph", JournalDocument(markdown: "Hello world"), { $0.caret(at: 6) }, list,
                ["paragraph: Hello One two", "bullet: three", "bullet: four", "paragraph: world"], "four\n|world"
            ),
            (
                "words within a paragraph", JournalDocument(markdown: "Hello world"), { $0.caret(at: 6) },
                .html("<span style=\"color:red;font-family:Georgia\">dear</span>"), ["paragraph: Hello dearworld"],
                "dear|world"
            ),
            (
                "lines at the end of a list item", JournalDocument(markdown: "- Milk\n- Bread"), { $0.caret(at: 6) },
                PasteSample(name: "plain", plain: " and eggs\nButter\nJam"),
                ["bullet: Milk and eggs", "bullet: Butter", "bullet: Jam", "bullet: Bread"], "Jam|\n"
            ),
            (
                "a line on an empty line", answerLine, { $0.caret(at: ("Today\n" as NSString).length) },
                .html("<p>Walked to work</p>"), ["heading: Today", "paragraph: Walked to work", "paragraph: Later"],
                "work|\nLater"
            ),
            (
                "words replacing a selection", JournalDocument(markdown: "Hello world again"), { $0.select("world") },
                PasteSample(name: "plain", plain: "there"), ["paragraph: Hello there again"], "there| again"
            ),
            (
                "blocks into code", JournalDocument(markdown: "```\nlet a = 1\n```\n\nAfter"), { $0.caret(at: 5) },
                list, ["codeBlock: let aOne two\nthree\nfour = 1", "paragraph: After"], "four| = 1"
            ),
        ]
        for (name, document, place, sample, blocks, caret) in cases {
            let harness = EditorHarness(document)
            defer { harness.close() }
            place(harness)
            let before = harness.document.markdown
            let selection = harness.selection
            harness.paste(sample)
            XCTAssertEqual(harness.blockSummary, blocks, name)
            XCTAssertEqual(Self.caretContext(harness, like: caret), caret, name)
            Self.assertClean(harness, name)
            harness.undoManager?.undo()
            harness.settle()
            XCTAssertEqual(harness.document.markdown, before, name)
            XCTAssertEqual(harness.selection, selection, name)
        }
    }

    /// Text joining a heading takes the heading's size, as typing there does, and leaves no empty line behind.
    func testTextPastedIntoAHeadingTakesItsSize() throws {
        let harness = EditorHarness(markdown: "# Title\n\nBody")
        defer { harness.close() }
        harness.caret(at: 5)
        harness.paste(.html("<p>of the day</p><p>More</p>"))
        XCTAssertEqual(harness.blockSummary, ["heading: Titleof the day", "paragraph: More", "paragraph: Body"])
        Self.assertClean(harness, "heading")
    }

    // MARK: - Checks

    /// The text around the caret as "before|after", with as many characters on each side as `expected` has.
    private static func caretContext(_ harness: EditorHarness, like expected: String) -> String {
        let parts = expected.components(separatedBy: "|")
        let text = harness.text.string as NSString
        let location = harness.selection.location
        let before = text.substring(to: location).suffix(parts[0].count)
        let after = text.substring(from: location).prefix(parts.count > 1 ? parts[1].count : 0)
        return before + "|" + after
    }

    /// The pasted text looks exactly as the same entry does when it is opened again: no fonts, colours,
    /// backgrounds or underlines of the app it came from. Its Markdown reads back as the same blocks.
    private static func assertClean(
        _ harness: EditorHarness, _ name: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let reopened = EditorHarness(harness.document)
        defer { reopened.close() }
        let pasted = harness.text
        XCTAssertEqual(pasted.string, reopened.text.string, name, file: file, line: line)
        guard pasted.string == reopened.text.string else { return }
        let keys: [NSAttributedString.Key] = [
            .font, .foregroundColor, .backgroundColor, .underlineStyle, .strikethroughStyle, .link,
        ]
        var index = 0
        while index < pasted.length {
            var range = NSRange()
            let mine = pasted.attributes(
                at: index, longestEffectiveRange: &range, in: NSRange(location: index, length: pasted.length - index))
            let theirs = reopened.text.attributes(at: index, effectiveRange: nil)
            for key in keys where describe(mine[key]) != describe(theirs[key]) {
                let text = (pasted.string as NSString).substring(with: range)
                XCTFail("\(name): \(key.rawValue) of “\(text)” is \(describe(mine[key]))", file: file, line: line)
            }
            index = NSMaxRange(range)
        }
        let markdown = harness.document.markdown
        let read = JournalDocument(markdown: markdown).blocks.filter { $0.kind != "paragraph" || !$0.runs.isEmpty }
        XCTAssertEqual(read.map(EditorHarness.summary), harness.blockSummary, name, file: file, line: line)
        XCTAssertFalse(markdown.contains("\u{FFFC}"), name, file: file, line: line)
    }

    private static func describe(_ value: Any?) -> String {
        guard let value else { return "none" }
        if let font = value as? PlatformFont { return "\(font.fontName) \(font.pointSize)" }
        return "\(value)"
    }
}

/// A local web server that only counts the connections made to it.
final class RequestCounter {
    private let listener: NWListener
    private let count: OSAllocatedUnfairLock<Int>
    let port: UInt16

    init() throws {
        let count = OSAllocatedUnfairLock(initialState: 0)
        self.count = count
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.newConnectionHandler = { connection in
            count.withLock { $0 += 1 }
            connection.cancel()
        }
        listener.start(queue: DispatchQueue(label: "RequestCounter"))
        _ = ready.wait(timeout: .now() + 5)
        guard let port = listener.port?.rawValue else { throw URLError(.cannotConnectToHost) }
        self.port = port
    }

    var requests: Int { count.withLock { $0 } }
    func stop() { listener.cancel() }
}
