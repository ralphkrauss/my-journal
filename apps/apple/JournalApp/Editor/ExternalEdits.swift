import JournalCore
import SwiftUI

/// A change to the open entry from elsewhere, such as a sync, can arrive while the person is composing text with an
/// input method. The editor keeps the composition and applies both edits, block by block.
enum ExternalEdits {
    /// The edits made in the editor since `base` (what it last showed), applied on top of `remote` (the entry as it is
    /// now). When both sides changed the same block, or the documents can't be matched block by block, the editor's
    /// version is kept; the other version remains in the entry's history.
    static func rebase(local: JournalDocument, base: JournalDocument, remote: JournalDocument) -> JournalDocument {
        if remote == base { return local }
        if local == base { return remote }
        guard !local.requiresMarkdownSource, !base.requiresMarkdownSource, !remote.requiresMarkdownSource,
            let blocks = rebasedBlocks(local: local.blocks, base: base.blocks, remote: remote.blocks)
        else { return local }
        return remote.applyingRichEdit(JournalDocument(blocks: blocks))
    }

    private static func rebasedBlocks(local: [DocumentBlock], base: [DocumentBlock], remote: [DocumentBlock])
        -> [DocumentBlock]?
    {
        let original = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let kept = Set(local.map(\.id))
        var result = remote
        for block in local {
            guard let before = original[block.id], block != before else { continue }
            // The same block also changed elsewhere, or was removed there.
            guard let index = result.firstIndex(where: { $0.id == block.id }), result[index] == before else {
                return nil
            }
            result[index] = block
        }
        for before in base where !kept.contains(before.id) {
            guard let index = result.firstIndex(where: { $0.id == before.id }) else { continue }
            guard result[index] == before else { return nil }
            result.remove(at: index)
        }
        var previous: UUID?
        for block in local {
            defer { previous = block.id }
            guard original[block.id] == nil else { continue }
            guard let anchor = previous else {
                result.insert(block, at: 0)
                continue
            }
            guard let index = result.firstIndex(where: { $0.id == anchor }) else { return nil }
            result.insert(block, at: index + 1)
        }
        return result
    }
}

/// Keeps a position in the text meaningful while the text changes around it.
enum TextRanges {
    /// Where the end of `range`, chosen in `old`, is in `new`, as a caret: at the same place, ahead of anything typed
    /// there since, or after text that replaced it, so nothing written in the meantime is overwritten.
    static func insertionPoint(following range: NSRange, from old: String, to new: String) -> NSRange {
        let before = old as NSString
        let after = new as NSString
        let shared = min(before.length, after.length)
        var prefix = 0
        while prefix < shared, before.character(at: prefix) == after.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < shared - prefix,
            before.character(at: before.length - 1 - suffix) == after.character(at: after.length - 1 - suffix)
        {
            suffix += 1
        }
        let location = NSMaxRange(range)
        let mapped: Int
        if location <= prefix {
            mapped = location
        } else if location >= before.length - suffix {
            mapped = location + after.length - before.length
        } else {
            mapped = after.length - suffix
        }
        return NSRange(location: min(max(0, mapped), after.length), length: 0)
    }
}
