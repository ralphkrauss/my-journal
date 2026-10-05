import CoreGraphics
import ImageIO
import Markdown
import UniformTypeIdentifiers
import XCTest

@testable import JournalCore

/// Export as Markdown must give other apps a folder they can open: every entry once, its images where its links
/// point, names every file system accepts, and nothing left out without being counted (protocol/markdown-export.md).
final class MarkdownExportTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let zone = TimeZone(identifier: "Europe/Brussels") ?? .current
    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func testALibraryBecomesFoldersOfMarkdownFilesWhoseImagesResolve() async throws {
        let store = try JournalStore(directory: root.appendingPathComponent("library"), key: VaultCrypto.generateKey())
        let personal = try await store.save(JournalItem(kind: "journal", title: "Personal"))
        let work = try await store.save(JournalItem(kind: "journal", title: "Work: Q4/Plans"))
        let gone = try await store.save(JournalItem(kind: "journal", title: "Deleted journal"))
        let photo = try await store.addAttachment(try image(.png))
        let inline = try await store.addAttachment(try image(.jpeg))
        let referenced = try await store.addAttachment(try image(.gif))
        let notDownloaded = UUID()
        let markdown = """
            Morning *walk*.

            ![The bay](attachments/\(photo.uuidString.lowercased()))

            Text with ![a cup](attachments/\(inline.uuidString.lowercased())) inside, and `attachments/\(inline.uuidString.lowercased())` in code.

            ![A map][map]

            ![Still downloading](attachments/\(notDownloaded.uuidString.lowercased()))

            - [ ] Call the bank
            - [x] Water plants

            [map]: attachments/\(referenced.uuidString.lowercased())
            """
        var entry = JournalItem(
            kind: "entry", journalID: personal.id, title: "Morning pages",
            document: JournalDocument(markdown: markdown),
            date: date("2026-10-05T07:12:00+02:00"))
        entry = try await store.save(entry)
        try await store.setPinned(true, entry: entry.id)
        var archived = JournalItem(
            kind: "entry", journalID: personal.id, document: JournalDocument(markdown: "Quiet day\nNothing else"),
            date: date("2026-10-04T21:00:00+02:00"))
        archived.archivedAt = date("2026-10-05T08:00:00+02:00")
        try await store.save(archived)
        try await store.save(
            JournalItem(
                kind: "entry", journalID: work.id, title: "Plan",
                // The same image, still downloading, in another journal: counted once.
                document: JournalDocument(
                    markdown: "Ship it\n\n![](attachments/\(notDownloaded.uuidString.lowercased()))"),
                date: date("2026-10-03T10:00:00+02:00")))
        try await addDeletedItemsAndATemplate(to: store, journal: personal, deletedJournal: gone)

        let folder = root.appendingPathComponent("Journal Markdown 2026-10-05")
        let summary = try await MarkdownExport.write(store: store, to: folder, timeZone: zone)
        try await store.close()

        XCTAssertEqual(summary.imagesNotDownloaded, 1)
        XCTAssertEqual(summary.imagesUnreadable, 0)
        XCTAssertEqual(try names(folder), [".journal-export.json", "Personal", "Templates", "Work- Q4-Plans"])
        let manifest =
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: folder.appendingPathComponent(".journal-export.json"))) as? [String: Any]
        XCTAssertEqual(manifest?["format"] as? String, "my-journal-markdown")
        XCTAssertEqual(manifest?["version"] as? Int, 1)
        XCTAssertEqual(
            try names(folder.appendingPathComponent("Personal")),
            ["2026-10-04 Quiet day.md", "2026-10-05 Morning pages.md", "attachments"])
        XCTAssertEqual(try names(folder.appendingPathComponent("Work- Q4-Plans")), ["2026-10-03 Plan.md"])
        XCTAssertEqual(try names(folder.appendingPathComponent("Templates")), ["Weekly review.md", "attachments"])

        let morning = try String(
            contentsOf: folder.appendingPathComponent("Personal/2026-10-05 Morning pages.md"), encoding: .utf8)
        XCTAssertTrue(
            morning.hasPrefix(
                """
                ---
                title: "Morning pages"
                date: 2026-10-05T07:12:00+02:00
                """), morning)
        XCTAssertTrue(morning.contains("journal: \"Personal\"\njournal_id: \(personal.id.uuidString.lowercased())\n"))
        XCTAssertTrue(morning.contains("\npinned: true\n---\n\n# Morning pages\n\nMorning *walk*."), morning)
        XCTAssertFalse(morning.contains("archived:"))
        // Each image link points at a file beside the entry, except the image that never downloaded.
        let sources = imageSources(morning)
        XCTAssertEqual(sources.count, 4)
        for source in sources where !source.contains(notDownloaded.uuidString.lowercased()) {
            XCTAssertTrue(source.hasPrefix("attachments/") && source.contains("."), source)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: folder.appendingPathComponent("Personal/" + source).path),
                source)
        }
        XCTAssertTrue(morning.contains("`attachments/\(inline.uuidString.lowercased())` in code"), "code is text")
        XCTAssertTrue(morning.contains("- [ ] Call the bank\n- [x] Water plants"))
        // Apart from the image paths and the title, the file reads as the entry does.
        XCTAssertEqual(
            blockKinds(body(of: morning).replacingOccurrences(of: "# Morning pages\n\n", with: "")),
            blockKinds(markdown))

        let quiet = try String(
            contentsOf: folder.appendingPathComponent("Personal/2026-10-04 Quiet day.md"), encoding: .utf8)
        XCTAssertFalse(quiet.contains("title:"), "No title is invented from the first line")
        XCTAssertTrue(quiet.contains("\narchived: true\n"))
        XCTAssertFalse(quiet.contains("\n# "))
        let template = try String(
            contentsOf: folder.appendingPathComponent("Templates/Weekly review.md"), encoding: .utf8)
        XCTAssertFalse(template.contains("date:"))
        XCTAssertFalse(template.contains("journal:"))
        XCTAssertTrue(template.contains("\nkind: template\n"))
        XCTAssertEqual(imageSources(template).count, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: folder.appendingPathComponent("Templates/" + (imageSources(template).first ?? "")).path))
    }

    func testPhotosOtherAppsCantShowBecomeJPEGOrPNG() throws {
        for (type, transparent, expected) in [
            (UTType.heic, false, UTType.jpeg), (.tiff, false, .jpeg), (.tiff, true, .png), (.png, true, .png),
            (.jpeg, false, .jpeg),
        ] {
            let original = try image(type, transparent: transparent)
            let portable = try XCTUnwrap(PortableImage(original), "\(type)")
            let source = try XCTUnwrap(CGImageSourceCreateWithData(portable.data as CFData, nil))
            XCTAssertEqual(CGImageSourceGetType(source) as String?, expected.identifier, "\(type)")
            XCTAssertEqual(portable.fileExtension, expected == .png ? "png" : "jpg")
            if type == expected { XCTAssertEqual(portable.data, original, "\(type) keeps its bytes") }
        }
        XCTAssertNil(PortableImage(Data("not an image".utf8)))
    }

    func testNamesAreSafeEverywhereAndShortInBytes() {
        XCTAssertEqual(ExportName.safe("Work: Q4/Plans?", fallback: "x"), "Work- Q4-Plans-")
        XCTAssertEqual(ExportName.safe("#tag [draft] ^1 | a\\b", fallback: "x"), "-tag -draft- -1 - a-b")
        XCTAssertEqual(ExportName.safe("..hidden.", fallback: "x"), "hidden")
        XCTAssertEqual(ExportName.safe("  \n ", fallback: "Untitled"), "Untitled")
        XCTAssertEqual(ExportName.safe("Line one\nline two", fallback: "x"), "Line one line two")
        for reserved in ["nul", "CON", "Lpt9", "COM¹"] {
            XCTAssertEqual(ExportName.safe(reserved, fallback: "x"), reserved + "-", reserved)
        }
        // Windows treats the part before the first dot as the device name.
        XCTAssertEqual(ExportName.safe("com1.notes", fallback: "x"), "com1-.notes")
        XCTAssertEqual(ExportName.safe("CON.txt", fallback: "x"), "CON-.txt")
        // APFS refuses noncharacters and unassigned code points; direction overrides disguise names.
        XCTAssertEqual(ExportName.safe("odd\u{FFFF}\u{FFFE}\u{1FFFF}\u{0378}", fallback: "x"), "odd----")
        XCTAssertEqual(ExportName.safe("gpj\u{202E}.exe", fallback: "x"), "gpj-.exe")
        XCTAssertEqual(ExportName.safe("console", fallback: "x"), "console")
        let emoji = ExportName.safe(String(repeating: "👩‍👩‍👧‍👦", count: 40), fallback: "x")
        XCTAssertLessThanOrEqual(emoji.utf8.count, ExportName.maximumBytes)
        XCTAssertTrue(emoji.allSatisfy { $0 == "👩‍👩‍👧‍👦" }, "Cut between whole characters")
        let japanese = ExportName.safe(String(repeating: "日記", count: 80), fallback: "x")
        XCTAssertEqual(japanese.count, 40)
        XCTAssertEqual(ExportName.safe(String(repeating: "a", count: 99), fallback: "x").count, 60)
        XCTAssertEqual(ExportName.safe("Cafe\u{301}", fallback: "x"), "Café".precomposedStringWithCanonicalMapping)
    }

    func testTheSameLibraryGetsTheSameNamesEveryTime() {
        let journal = JournalItem(kind: "journal", title: "Trips")
        let same = date("2026-10-05T09:00:00+02:00")
        let entries = (0..<3).map { _ in
            JournalItem(kind: "entry", journalID: journal.id, title: "Paris", date: same)
        }
        let other = JournalItem(kind: "journal", title: "trips")
        let templates = [
            JournalItem(kind: "template", title: "nul"), JournalItem(kind: "template", title: ""),
            JournalItem(kind: "template", title: ""),
        ]
        let titled = JournalItem(kind: "journal", title: "Templates")
        let items = [journal, other, titled] + entries + templates
        let first = MarkdownExportPlan(items: items, pinned: [], ranks: [:], timeZone: zone)
        let second = MarkdownExportPlan(items: items.reversed(), pinned: [], ranks: [:], timeZone: zone)
        func layout(_ plan: MarkdownExportPlan) -> [String: [String]] {
            Dictionary(uniqueKeysWithValues: plan.folders.map { ($0.name, $0.files.map(\.name)) })
        }
        XCTAssertEqual(layout(first), layout(second))
        let names = Set(first.folders.map(\.name))
        XCTAssertTrue(names.isSuperset(of: ["Templates", "Templates 2"]), "\(names)")
        XCTAssertTrue(names.contains("Trips 2") || names.contains("trips 2"), "\(names)")
        let trips = first.folders.first { $0.journal?.id == journal.id }
        let ordered = entries.sorted { $0.id.uuidString < $1.id.uuidString }
        XCTAssertEqual(
            trips?.files.map(\.item.id), ordered.map(\.id), "Same date: ordered by id, so numbering is stable")
        XCTAssertEqual(trips?.files.map(\.name), ["2026-10-05 Paris", "2026-10-05 Paris 2", "2026-10-05 Paris 3"])
        let templateNames = first.folders.first { $0.name == "Templates 2" }?.files.map(\.name)
        XCTAssertEqual(templateNames, ["Untitled Template", "Untitled Template 2", "nul-"])
    }

    func testNamesThatAPFSConsidersTheSameAreNumbered() {
        let journal = JournalItem(kind: "journal", title: "Notes")
        let day = date("2026-10-05T09:00:00+02:00")
        let titles = ["Straße", "STRASSE", "ﬀ", "FF", "ς", "Σ"]
        let entries = titles.map { JournalItem(kind: "entry", journalID: journal.id, title: $0, date: day) }
        let plan = MarkdownExportPlan(items: [journal] + entries, pinned: [], ranks: [:], timeZone: zone)
        let names = plan.folders.first?.files.map(\.name) ?? []
        XCTAssertEqual(names.filter { $0.hasSuffix(" 2") }.count, 3, "\(names)")
    }

    func testADeletedJournalsEntriesStayInRecentlyDeleted() {
        var secret = JournalItem(kind: "journal", title: "Secret")
        secret.deletedAt = Date()
        let kept = JournalItem(kind: "journal", title: "Kept")
        // Deleting a journal marks only the journal; its entries are deleted with it.
        let entry = JournalItem(kind: "entry", journalID: secret.id, title: "Private thoughts")
        let orphan = JournalItem(kind: "entry", journalID: UUID(), title: "Journal never synced")
        let plan = MarkdownExportPlan(items: [secret, kept, entry, orphan], pinned: [], ranks: [:], timeZone: zone)
        let exported = plan.folders.flatMap(\.files).map(\.item.title)
        XCTAssertEqual(exported, ["Journal never synced"])
        XCTAssertEqual(plan.folders.map(\.name), ["Kept", "Other Entries"])
    }

    func testAnImageWhoseReferenceALinkSharesStillResolves() {
        let first = UUID()
        let shared = UUID()
        let stored = """
            ![first](attachments/\(first.uuidString.lowercased()))

            ![second][pic] and [open it][pic]

            [pic]: attachments/\(shared.uuidString.lowercased())
            """
        let paths = [
            first: "attachments/\(first.uuidString.lowercased()).png",
            shared: "attachments/\(shared.uuidString.lowercased()).jpg",
        ]
        let result = MarkdownExport.body(stored, paths: paths)
        XCTAssertEqual(result.unlinked, [shared], "Only the shared reference keeps its link")
        XCTAssertTrue(result.text.contains("(attachments/\(first.uuidString.lowercased()).png)"), result.text)
        XCTAssertTrue(result.text.hasSuffix("[pic]: attachments/\(shared.uuidString.lowercased())"), result.text)
    }

    func testFrontMatterAndTitlesAreEscaped() {
        XCTAssertEqual(MarkdownExport.yamlString("A \"quote\" \\ and\nnew\tline"), #""A \"quote\" \\ and\nnew\tline""#)
        XCTAssertEqual(MarkdownExport.yamlString("bell\u{7}"), #""bell\u0007""#)
        XCTAssertEqual(MarkdownExport.yamlString("x\u{FFFF}\u{10FFFF}"), #""x\uFFFF\U0010FFFF""#)
        XCTAssertEqual(
            MarkdownExport.headingText("*Draft* #1 [x] <b> & co &amp; ![i]"),
            ##"\*Draft\* \#1 \[x\] \<b\> & co \&amp; \!\[i\]"##)
        // Read back, the heading is the title's text with no formatting.
        for title in ["*Draft* #1 [x] <b> &amp; ![i](x)", "1. Not a list", "- Not a bullet", "Ends with #"] {
            let heading = Document(parsing: "# " + MarkdownExport.headingText(title)).child(at: 0) as? Heading
            XCTAssertEqual(heading?.plainText, title, title)
            XCTAssertEqual(heading?.childCount, 1, "Only text: \(title)")
        }
    }

    func testContentANewerVersionWroteIsKeptOrCounted() {
        let journal = JournalItem(kind: "journal", title: "Notes")
        var shown = JournalItem(kind: "entry", journalID: journal.id, title: "From a newer app")
        shown.document = JournalDocument(markdown: "Kept ==exactly== as {written}\r\n")
        shown.document.version = JournalDocument.unfamiliarVersion
        shown.preservedJSON = Data("{}".utf8)
        var unreadable = PortableRecord.unreadable(Data("{\"title\":\"Sealed\"}".utf8), id: UUID(), kind: "entry")
        unreadable.journalID = journal.id
        let plan = MarkdownExportPlan(items: [journal, shown, unreadable], pinned: [], ranks: [:], timeZone: zone)
        XCTAssertEqual(plan.unreadable, 1)
        let folder = try? XCTUnwrap(plan.folders.first)
        XCTAssertEqual(folder?.files.map(\.item.id), [shown.id])
        guard let folder, let file = folder.files.first else { return }
        let text = MarkdownExport.markdown(
            file, folder: folder, body: file.item.document.markdown, timeZone: zone)
        XCTAssertTrue(text.hasSuffix("\n\nKept ==exactly== as {written}\n"), text)
    }

    // MARK: Helpers

    /// An entry and a journal in Recently Deleted, which aren't exported, and a template with an image.
    private func addDeletedItemsAndATemplate(
        to store: JournalStore, journal: JournalItem, deletedJournal: JournalItem
    ) async throws {
        var deleted = JournalItem(kind: "entry", journalID: journal.id, title: "Removed")
        deleted.deletedAt = Date()
        try await store.save(deleted)
        var removedJournal = deletedJournal
        removedJournal.deletedAt = Date()
        try await store.save(removedJournal)
        let templatePhoto = try await store.addAttachment(try image(.png))
        try await store.save(
            JournalItem(
                kind: "template", title: "Weekly review",
                document: JournalDocument(
                    markdown: "## Wins\n\n![](attachments/\(templatePhoto.uuidString.lowercased()))")))
    }

    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text) ?? Date(timeIntervalSince1970: 0)
    }

    private func names(_ folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    private func body(of file: String) -> String {
        guard let end = file.range(of: "\n---\n") else { return file }
        return String(file[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func imageSources(_ markdown: String) -> [String] {
        var sources: [String] = []
        func visit(_ node: Markup) {
            if let image = node as? Markdown.Image, let source = image.source { sources.append(source) }
            for child in node.children { visit(child) }
        }
        visit(Document(parsing: body(of: markdown)))
        return sources
    }

    private func blockKinds(_ markdown: String) -> [String] {
        Document(parsing: markdown).children.map { String(describing: type(of: $0)) }
    }

    private func image(_ type: UTType, transparent: Bool = false) throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let info = transparent ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: info.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: transparent ? 0.5 : 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let picture = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil), "\(type)")
        CGImageDestinationAddImage(destination, picture, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
