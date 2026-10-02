import Foundation
import JournalCore

@MainActor
final class InitialEditorInsertion {
    let itemID: UUID
    private let blockID: UUID
    private var consumed = false

    init?(item: JournalItem, fromTemplate: Bool) {
        guard fromTemplate,
            let block = item.document.blocks.first(where: Self.isEmptyParagraph)
        else { return nil }
        itemID = item.id
        blockID = block.id
    }

    /// Whether the open entry shows the answer line now, still empty, and the caret hasn't gone there yet.
    func isPending(itemID: UUID, document: JournalDocument) -> Bool {
        !consumed && self.itemID == itemID
            && document.blocks.contains { $0.id == blockID && Self.isEmptyParagraph($0) }
    }

    func consume(itemID: UUID, document: JournalDocument, text: NSAttributedString) -> Int? {
        guard !consumed, self.itemID == itemID else { return nil }
        consumed = true
        guard let block = document.blocks.first(where: { $0.id == blockID }), Self.isEmptyParagraph(block) else {
            return nil
        }
        var offset: Int?
        text.enumerateAttribute(.journalBlockID, in: NSRange(location: 0, length: text.length)) { value, range, stop in
            if value as? String == blockID.uuidString {
                offset = range.location
                stop.pointee = true
            }
        }
        if let offset { return offset }
        return document.blocks.last?.id == blockID ? text.length : nil
    }

    private static func isEmptyParagraph(_ block: DocumentBlock) -> Bool {
        block.kind == "paragraph" && block.runs.allSatisfy { $0.text.isEmpty }
    }
}
