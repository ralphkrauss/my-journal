import JournalCore
import SwiftUI

/// Structural shortcuts only consume keys inside the block where they have a defined meaning.
@MainActor enum StructuredKeyboard {
    enum Key { case indent, outdent, down, toggleTask }
    static func edit(
        _ key: Key, text: NSAttributedString, selection: NSRange, size: CGFloat, images: [UUID: Data] = [:]
    ) -> MarkdownEditing.Edit? {
        guard text.length > 0, selection.location >= 0, selection.length >= 0,
            NSMaxRange(selection) <= text.length, !MarkdownEditing.isSource(text)
        else { return nil }
        let position = min(selection.location, text.length - 1)
        let kind = text.attribute(.journalKind, at: position, effectiveRange: nil) as? String ?? "paragraph"
        if kind == "codeBlock" { return code(key, text: text, selection: selection, size: size) }
        guard key != .down else { return nil }
        let source = text.string as NSString
        let range = source.paragraphRange(for: selection)
        let result = NSMutableAttributedString(attributedString: text.attributedSubstring(from: range))
        var items: [(NSRange, DocumentBlock)] = []
        var offset = range.location
        while offset < NSMaxRange(range) {
            let paragraph = source.paragraphRange(for: NSRange(location: offset, length: 0))
            let paragraphKind = text.attribute(.journalKind, at: offset, effectiveRange: nil) as? String ?? ""
            if ["bullet", "numbered", "task", "checked"].contains(paragraphKind),
                let block = RichText.document(text.attributedSubstring(from: paragraph)).blocks.first,
                key != .toggleTask || ["task", "checked"].contains(block.kind)
            {
                items.append((paragraph, block))
            }
            offset = NSMaxRange(paragraph)
        }
        guard !items.isEmpty else { return nil }
        let complete = !items.allSatisfy { $0.1.kind == "checked" }
        for (paragraph, original) in items.reversed() {
            var block = original
            change(&block, key: key, complete: complete)
            let replacement = RichText.paragraphReplacement(
                [block], replacing: paragraph, in: text, size: size, images: images
            ).text
            result.replaceCharacters(
                in: NSRange(location: paragraph.location - range.location, length: paragraph.length), with: replacement)
        }
        let caret = max(
            range.location, min(range.location + result.length, selection.location + result.length - range.length))
        let updatedSelection =
            selection.length == 0
            ? NSRange(location: caret, length: 0) : NSRange(location: range.location, length: result.length)
        return MarkdownEditing.Edit(text: result, range: range, selection: updatedSelection)
    }

    static func change(_ block: inout DocumentBlock, key: Key, complete: Bool) {
        switch key {
        case .indent:
            let width = block.kind == "numbered" ? "\(block.listNumber ?? 1). ".count : 2
            block.markdownPrefix = (block.markdownPrefix ?? "") + String(repeating: " ", count: width)
            block.markdownContinuation = (block.markdownContinuation ?? "  ") + String(repeating: " ", count: width)
            block.listIndents = (block.listIndents ?? []) + [width]
        case .outdent:
            if let width = block.listIndents?.popLast() {
                block.markdownPrefix = String((block.markdownPrefix ?? "").dropLast(width))
                block.markdownContinuation = String((block.markdownContinuation ?? "").dropLast(width))
            } else {
                block.kind = "paragraph"
                block.markdownPrefix = nil
                block.markdownContinuation = nil
                block.listNumber = nil
            }
        case .toggleTask: block.kind = complete ? "checked" : "task"
        case .down: break
        }
    }
    private static func code(_ key: Key, text: NSAttributedString, selection: NSRange, size: CGFloat) -> MarkdownEditing
        .Edit?
    {
        let source = text.string as NSString
        let position = min(selection.location, text.length - 1)
        var block = NSRange()
        guard
            text.attribute(
                .journalStructuredBlock, at: position, longestEffectiveRange: &block,
                in: NSRange(location: 0, length: text.length)) != nil
        else { return nil }
        guard selection.location >= block.location, NSMaxRange(selection) <= NSMaxRange(block) else { return nil }
        let attributes = text.attributes(at: position, effectiveRange: nil)
        switch key {
        case .indent:
            if selection.length == 0 {
                return MarkdownEditing.Edit(
                    text: NSAttributedString(string: "\t", attributes: attributes), range: selection)
            }
            return codeLines(key, text: text, selection: selection, block: block)
        case .outdent:
            return codeLines(key, text: text, selection: selection, block: block)
        case .down:
            let end = NSMaxRange(block)
            let boundary =
                end < text.length && source.substring(with: NSRange(location: end - 1, length: 1)) == "\n"
                ? end - 1 : end
            guard selection.length == 0, selection.location == boundary else { return nil }
            if end < text.length {
                return MarkdownEditing.Edit(
                    text: NSAttributedString(), range: NSRange(location: end, length: 0),
                    selection: NSRange(location: end, length: 0))
            }
            return MarkdownEditing.Edit(
                text: NSAttributedString(string: "\n", attributes: RichText.attributes(kind: "paragraph", size: size)),
                range: NSRange(location: end, length: 0), selection: NSRange(location: end + 1, length: 0))
        case .toggleTask: return nil
        }
    }
    private static func codeLines(_ key: Key, text: NSAttributedString, selection: NSRange, block: NSRange)
        -> MarkdownEditing.Edit?
    {
        let source = text.string as NSString
        let range = NSIntersectionRange(source.paragraphRange(for: selection), block)
        let result = NSMutableAttributedString(attributedString: text.attributedSubstring(from: range))
        var lines: [NSRange] = []
        var offset = range.location
        while offset < NSMaxRange(range) {
            let line = NSIntersectionRange(source.paragraphRange(for: NSRange(location: offset, length: 0)), range)
            lines.append(line)
            offset = NSMaxRange(line)
        }
        var removed = 0
        for line in lines.reversed() {
            let location = line.location - range.location
            if key == .indent {
                result.insert(
                    NSAttributedString(
                        string: "\t", attributes: text.attributes(at: line.location, effectiveRange: nil)), at: location
                )
            } else {
                let value = source.substring(with: line)
                let count = value.hasPrefix("\t") ? 1 : value.prefix(4).prefix(while: { $0 == " " }).count
                result.deleteCharacters(in: NSRange(location: location, length: count))
                removed += count
            }
        }
        guard key == .indent || removed > 0 else { return nil }
        let updatedSelection =
            selection.length == 0
            ? NSRange(location: max(range.location, selection.location - removed), length: 0)
            : NSRange(location: range.location, length: result.length)
        return MarkdownEditing.Edit(text: result, range: range, selection: updatedSelection)
    }

}

extension NativeEditor.Coordinator {
    @discardableResult func performStructuralKey(_ key: StructuredKeyboard.Key) -> Bool {
        guard let view, parent.editable, !editingSource else { return false }
        #if os(macOS)
            guard !view.hasMarkedText(), let text = view.textStorage else { return false }
            let selection = view.selectedRange()
        #else
            guard view.markedTextRange == nil else { return false }
            let text = view.textStorage
            let selection = view.selectedRange
        #endif
        guard
            let edit = StructuredKeyboard.edit(
                key, text: text, selection: selection, size: parent.fontSize, images: parent.images)
        else {
            return false
        }
        if edit.range.length > 0 || edit.text.length > 0 { replace(edit.text, range: edit.range) }
        #if os(macOS)
            if let selection = edit.selection { view.setSelectedRange(selection) }
        #else
            if let selection = edit.selection { view.selectedRange = selection }
        #endif
        if edit.text.length > 0 {
            view.typingAttributes = edit.text.attributes(at: edit.text.length - 1, effectiveRange: nil).filter {
                $0.key != .journalOwnEnd
            }
        }
        return true
    }
}

extension RichText {
    static func paragraphContentRange(_ text: String, selection: NSRange) -> NSRange {
        let source = text as NSString
        var range = source.paragraphRange(for: selection)
        while range.length > 0,
            ["\n", "\r"].contains(source.substring(with: NSRange(location: NSMaxRange(range) - 1, length: 1)))
        {
            range.length -= 1
        }
        return range
    }
    static func restyling(_ document: JournalDocument, kind: String) -> JournalDocument {
        var result = document
        for index in result.blocks.indices {
            guard result.blocks[index].table == nil,
                !["image", "codeBlock", "html"].contains(result.blocks[index].kind)
            else { continue }
            result.blocks[index].kind = kind
            if !["bullet", "numbered", "task", "checked"].contains(kind) {
                result.blocks[index].markdownPrefix = nil
                result.blocks[index].markdownContinuation = nil
                result.blocks[index].listIndents = nil
                result.blocks[index].listNumber = nil
            }
        }
        return result
    }
}
