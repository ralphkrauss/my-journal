import XCTest

@testable import JournalCore

/// protocol/conformance/markdown: how the reference reader sees each construct of the stored Markdown, what the
/// reference writer writes for it, that the stored text always survives unchanged, and which images it refers to.
final class ConformanceMarkdownTests: XCTestCase {
    private static let documentsPath = "markdown/documents-v1.json"
    private static let imagesPath = "markdown/images-v1.json"

    private static func runs(_ runs: [TextRun]) -> [[String: Any]] {
        runs.map { run in
            var result: [String: Any] = ["text": run.text]
            let flags: [(String, Bool)] = [
                ("bold", run.bold), ("italic", run.italic), ("underline", run.underline),
                ("strikethrough", run.strikethrough), ("code", run.code), ("html", run.rawHTML),
            ]
            for (name, set) in flags where set { result[name] = true }
            if let link = run.link { result["link"] = link }
            if let title = run.linkTitle { result["linkTitle"] = title }
            if let kind = run.breakKind { result["break"] = kind }
            if let source = run.imageSource { result["image"] = source }
            if let title = run.imageTitle { result["imageTitle"] = title }
            return result
        }
    }

    private static let headings = [
        "heading": 1, "subheading": 2, "heading3": 3, "heading4": 4, "heading5": 5, "heading6": 6,
    ]

    /// One block in the neutral vocabulary: paragraph, heading with a level, quote, list item, code block, html,
    /// table, image and rule.
    static func neutral(_ block: DocumentBlock) -> [String: Any] {
        var result: [String: Any] = [:]
        if let level = headings[block.kind] {
            result["kind"] = "heading"
            result["level"] = level
        } else if ["bullet", "numbered", "task", "checked"].contains(block.kind) {
            result["kind"] = "listItem"
            result["list"] =
                ["bullet": "bullet", "numbered": "numbered", "task": "task", "checked": "task"][block.kind]
            if block.kind == "task" { result["checked"] = false }
            if block.kind == "checked" { result["checked"] = true }
            result["depth"] = block.listIndents?.count ?? 0
            if let number = block.listNumber { result["number"] = number }
        } else {
            result["kind"] = block.kind
        }
        if block.kind == "image" {
            result["attachment"] = block.attachmentID?.uuidString.lowercased() ?? NSNull()
            result["description"] = block.imageDescription ?? ""
        } else if let table = block.table {
            result["alignments"] = table.alignments.map { $0 ?? "none" }
            result["rows"] = table.rows.map { row in row.map { $0.map(\.text).joined() } }
        } else {
            result["runs"] = runs(block.runs)
            if let language = block.codeLanguage { result["language"] = language }
        }
        return result
    }

    private static func reading(_ markdown: String) -> [String: Any] {
        let document = JournalDocument(markdown: markdown, metadata: nil, freshIdentities: false)
        let blocks = document.blocks.map(neutral)
        var result: [String: Any] = [
            "blocks": blocks, "requiresSource": document.requiresMarkdownSource,
            "keepsText": document.markdown == markdown,
        ]
        // The writer's spelling of the same blocks, which reads back as the same blocks.
        let canonical = document.requiresMarkdownSource ? nil : JournalDocument(blocks: document.blocks).markdown
        let reread = canonical.map { JournalDocument(markdown: $0, metadata: nil, freshIdentities: false) }
        let agrees = reread.map { $0.blocks.map(neutral) }.map { (try? Conformance.same($0, blocks)) ?? false }
        result["canonical"] = canonical.map { $0 as Any } ?? NSNull()
        result["canonicalReadsBackAsTheSameBlocks"] = agrees ?? NSNull()
        return result
    }

    private static func documentsFixture() throws -> [String: Any] {
        try Conformance.fixture(documentsPath) {
            let documents = ConformanceMarkdownCases.documents.map { sample -> [String: Any] in
                [
                    "name": sample.name, "note": sample.note, "markdown": sample.markdown,
                    "expected": reading(sample.markdown),
                ]
            }
            return [
                "corpusVersion": 1,
                "purpose":
                    "Stored Markdown (protocol/records.md, Markdown) and how the reference reader and writer treat each construct. See README.md in this folder.",
                "documents": documents,
            ]
        }
    }

    func testEveryConstructReadsAndWritesAsTheFixtureSays() throws {
        let fixture = try Self.documentsFixture()
        let documents = try XCTUnwrap(fixture["documents"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(documents.count, 20)
        for document in documents {
            let name = try XCTUnwrap(document["name"] as? String)
            let markdown = try XCTUnwrap(document["markdown"] as? String)
            XCTAssertTrue(try Conformance.same(Self.reading(markdown), try XCTUnwrap(document["expected"])), name)
        }
    }

    /// The contract other clients rely on: whatever the reader makes of a body, the stored text comes back exactly,
    /// and the writer's spelling reads back as the same blocks.
    func testStoredTextAlwaysSurvivesAndTheWritersSpellingReadsBackTheSame() throws {
        let fixture = try Self.documentsFixture()
        let documents = try XCTUnwrap(fixture["documents"] as? [[String: Any]])
        for document in documents {
            let name = try XCTUnwrap(document["name"] as? String)
            let expected = try XCTUnwrap(document["expected"] as? [String: Any])
            XCTAssertEqual(expected["keepsText"] as? Bool, true, name)
            if expected["canonical"] is String {
                XCTAssertEqual(expected["canonicalReadsBackAsTheSameBlocks"] as? Bool, true, name)
            }
        }
    }

    private static func imageReading(_ markdown: String) -> [String: Any] {
        let ids = MarkdownAttachments.imageIDs(in: markdown).map { $0.uuidString.lowercased() }
        var result: [String: Any] = ["imageIDs": ids]
        guard let id = MarkdownAttachments.imageIDs(in: markdown).first else { return result }
        let name = id.uuidString.lowercased()
        let rewritten = try? MarkdownAttachments.rewrite(markdown, paths: [id: "attachments/\(name).png"])
        result["rewrittenToPng"] = rewritten.map { $0 as Any } ?? NSNull()
        return result
    }

    private static func imagesFixture() throws -> [String: Any] {
        try Conformance.fixture(imagesPath) {
            let cases = ConformanceMarkdownCases.images.map { sample -> [String: Any] in
                [
                    "name": sample.name, "note": sample.note, "markdown": sample.markdown,
                    "expected": imageReading(sample.markdown),
                ]
            }
            return [
                "corpusVersion": 1,
                "purpose":
                    "Image references (protocol/records.md, Images): which attachments a body refers to, and the body with the first one pointed at attachments/<id>.png as Export as Markdown does (protocol/markdown-export.md). Null: the reference can't be rewritten alone.",
                "cases": cases,
            ]
        }
    }

    func testImageReferencesAreOnlyTheExactAttachmentPath() throws {
        let fixture = try Self.imagesFixture()
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 15)
        for sample in cases {
            let name = try XCTUnwrap(sample["name"] as? String)
            let markdown = try XCTUnwrap(sample["markdown"] as? String)
            XCTAssertTrue(try Conformance.same(Self.imageReading(markdown), try XCTUnwrap(sample["expected"])), name)
        }
    }
}
