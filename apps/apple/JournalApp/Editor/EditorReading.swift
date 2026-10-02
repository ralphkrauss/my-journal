import JournalCore
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// What the editor knows about the text since it last read it, so that typing in one paragraph reads that paragraph
/// rather than the whole entry again. Reading a long entry on every keystroke made typing lag.
struct EditorReading {
    /// The blocks the text read as when it was last read.
    var blocks: [DocumentBlock]?
    /// Edits of the text since then.
    var edits = 0
    /// The only edit since then, in the text as it is now, when it neither added nor removed a line break.
    var plainEdit: NSRange?
    /// A change the text system announced, before making it: where, in the text as it was, and whether it added or
    /// removed a line break.
    var announced: (range: NSRange, length: Int, breaksLines: Bool)?

    static let lineBreaks = CharacterSet(charactersIn: "\n\r\u{2028}\u{2029}\u{85}")

    static func breaksLines(_ text: String) -> Bool { text.rangeOfCharacter(from: lineBreaks) != nil }
}

extension NativeEditor.Coordinator {
    /// Called before the text system replaces `range` with `replacement`, once the editor allowed it.
    func announceChange(in range: NSRange, replacement: String) {
        #if os(macOS)
            let text = view?.textStorage?.string ?? ""
        #else
            let text = view?.textStorage.string ?? ""
        #endif
        let old = text as NSString
        let breaks =
            NSMaxRange(range) > old.length || EditorReading.breaksLines(replacement)
            || EditorReading.breaksLines(old.substring(with: range))
        reading.announced = (range, (replacement as NSString).length, breaks)
    }

    nonisolated func textStorage(
        _ textStorage: NSTextStorage, didProcessEditing editedMask: TextStorageEdits, range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        // The editor's text storage is only ever edited on the main thread; this is its own delegate.
        MainActor.assumeIsolated { noteEdit(editedMask, range: editedRange, delta: delta) }
    }

    private func noteEdit(_ mask: TextStorageEdits, range: NSRange, delta: Int) {
        reading.edits += 1
        let announced = reading.announced
        reading.announced = nil
        guard let announced, !announced.breaksLines, mask.contains(.editedCharacters),
            range.location == announced.range.location, delta == announced.length - announced.range.length
        else {
            reading.plainEdit = nil
            return
        }
        reading.plainEdit = range
    }

    /// The text read into blocks, as `RichText.document` reads it. After one edit within a paragraph that holds only
    /// text, only that paragraph is read again.
    func readBlocks(_ storage: NSTextStorage) -> [DocumentBlock] {
        let blocks = readEditedParagraph(storage) ?? RichText.document(storage).blocks
        reading.blocks = blocks
        reading.edits = 0
        reading.plainEdit = nil
        return blocks
    }

    private func readEditedParagraph(_ storage: NSTextStorage) -> [DocumentBlock]? {
        guard reading.edits == 1, let edit = reading.plainEdit, var blocks = reading.blocks,
            NSMaxRange(edit) <= storage.length,
            !EditorReading.breaksLines((storage.string as NSString).substring(with: edit)),
            let block = RichText.plainParagraph(storage, containing: edit)
        else { return nil }
        let matching = blocks.indices.filter { blocks[$0].id == block.id }
        guard matching.count == 1, let index = matching.first else { return nil }
        blocks[index] = block
        return blocks
    }

    /// The document after an edit, as `MarkdownEditing.read` reads it.
    func readEdit(_ storage: NSTextStorage) -> JournalDocument {
        let previous = rendered ?? parent.document
        guard !showsSource else {
            reading = EditorReading()
            return previous.replacingMarkdown(storage.string)
        }
        return previous.applyingRichEdit(JournalDocument(blocks: readBlocks(storage)))
    }
}

extension RichText {
    /// The block a paragraph with only text reads as, the way `document` reads it: nil when the paragraph has an
    /// image, a table or code, is empty, or reads as more than one block.
    static func plainParagraph(_ text: NSAttributedString, containing edit: NSRange) -> DocumentBlock? {
        let source = text.string as NSString
        let paragraph = source.paragraphRange(for: edit)
        var end = NSMaxRange(paragraph)
        // As `document` does, only these end a paragraph's text.
        while end > paragraph.location,
            ["\n", "\r"].contains(source.substring(with: NSRange(location: end - 1, length: 1)))
        {
            end -= 1
        }
        let content = NSRange(location: paragraph.location, length: end - paragraph.location)
        guard content.length > 0 else { return nil }
        var special = false
        for key in [NSAttributedString.Key.attachment, .journalStructuredBlock] {
            text.enumerateAttribute(key, in: paragraph) { value, _, stop in
                if value != nil {
                    special = true
                    stop.pointee = true
                }
            }
        }
        guard !special else { return nil }
        let blocks = textDocument(text.attributedSubstring(from: content)).blocks
        guard blocks.count == 1, let block = blocks.first, !identity(block.id, isUsedOutside: paragraph, in: text)
        else {
            return nil
        }
        return block
    }

    /// Whether other text carries the same block identity, as both halves of a paragraph split with Return do until
    /// the text is read whole, which gives the second half an identity of its own.
    private static func identity(_ id: UUID, isUsedOutside paragraph: NSRange, in text: NSAttributedString) -> Bool {
        var used = false
        for range in [
            NSRange(location: 0, length: paragraph.location),
            NSRange(location: NSMaxRange(paragraph), length: text.length - NSMaxRange(paragraph)),
        ] where range.length > 0 {
            text.enumerateAttribute(.journalBlockID, in: range) { found, _, stop in
                if (found as? String).flatMap(UUID.init(uuidString:)) == id {
                    used = true
                    stop.pointee = true
                }
            }
        }
        return used
    }
}
