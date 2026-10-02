import CryptoKit
import Foundation

extension TextRun {
    public var imageAttachmentID: UUID? {
        guard let imageSource, imageSource.hasPrefix("attachments/") else { return nil }
        return UUID(uuidString: String(imageSource.dropFirst("attachments/".count)))
    }
}

extension JournalDocument {
    public var imageBlocks: [DocumentBlock] {
        var result = blocks.filter { $0.kind == "image" }
        for block in blocks {
            for (index, run) in block.runs.enumerated() where run.imageSource != nil {
                result.append(Self.imageBlock(run, parent: block.id, path: "run/\(index)"))
            }
            for (row, cells) in (block.table?.rows ?? []).enumerated() {
                for (column, runs) in cells.enumerated() {
                    for (index, run) in runs.enumerated() where run.imageSource != nil {
                        result.append(Self.imageBlock(run, parent: block.id, path: "cell/\(row)/\(column)/\(index)"))
                    }
                }
            }
        }
        return result
    }
    public func updatingImageDescriptions(_ descriptions: [UUID: String]) -> JournalDocument {
        var updated = self
        for index in updated.blocks.indices {
            let id = updated.blocks[index].id
            if updated.blocks[index].kind == "image" {
                updated.blocks[index].imageDescription = descriptions[id]
            }
            updated.blocks[index].runs = Self.describe(
                updated.blocks[index].runs, parent: id, path: "run", descriptions: descriptions)
            if var table = updated.blocks[index].table {
                for row in table.rows.indices {
                    for column in table.rows[row].indices {
                        table.rows[row][column] = Self.describe(
                            table.rows[row][column], parent: id, path: "cell/\(row)/\(column)",
                            descriptions: descriptions)
                    }
                }
                updated.blocks[index].table = table
            }
        }
        return applyingRichEdit(updated)
    }
    private static func describe(_ runs: [TextRun], parent: UUID, path: String, descriptions: [UUID: String])
        -> [TextRun]
    {
        runs.enumerated().map { index, run in
            guard run.imageSource != nil,
                let description = descriptions[imageIdentity(parent, path: path + "/\(index)")]
            else { return run }
            var result = run
            result.text = description
            return result
        }
    }
    private static func imageBlock(_ run: TextRun, parent: UUID, path: String) -> DocumentBlock {
        var result = DocumentBlock(
            kind: "image", attachmentID: run.imageAttachmentID, imageDescription: run.text,
            mediaType: run.imageMediaType)
        result.id = imageIdentity(parent, path: path)
        // Retain the complete source in the optimistic comparison, including remote URL and title.
        result.runs = [run]
        return result
    }
    private static func imageIdentity(_ parent: UUID, path: String) -> UUID {
        // A stable UI identity for this occurrence, not an attachment identity or security token.
        derivedIdentity(parent.uuidString + "/" + path)
    }
    /// A stable identity derived from `seed`; equal seeds give equal identities.
    static func derivedIdentity(_ seed: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(seed.utf8)))
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }
    /// Includes inline and table-cell references so sync, backup and garbage collection retain every image.
    public var attachmentIDs: [UUID] {
        Array(Set(blocks.compactMap(\.attachmentID) + imageRuns.compactMap(\.imageAttachmentID)))
    }
    var imageRuns: [TextRun] {
        blocks.flatMap { $0.runs + ($0.table?.rows.flatMap { $0.flatMap { $0 } } ?? []) }
            .filter { $0.imageSource != nil }
    }
    mutating func mapImageRuns(_ transform: (TextRun) -> TextRun) {
        var updated = blocks
        Self.mapImageRuns(in: &updated, transform)
        blocks = updated
    }
    static func mapImageRuns(in blocks: inout [DocumentBlock], _ transform: (TextRun) -> TextRun) {
        for index in blocks.indices {
            blocks[index].runs = blocks[index].runs.map { $0.imageSource == nil ? $0 : transform($0) }
            if var table = blocks[index].table {
                table.rows = table.rows.map { $0.map { $0.map { $0.imageSource == nil ? $0 : transform($0) } } }
                blocks[index].table = table
            }
        }
    }
}
