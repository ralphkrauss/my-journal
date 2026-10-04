import JournalCore
import SwiftUI

extension NativeEditor.Coordinator {
    /// Pastes text from another app at the selection, as one undo step. As in any editor, its first paragraph joins
    /// the paragraph it is pasted into and the rest of that paragraph follows it: on a line of its own when the copied
    /// text ended with a line break, else joined to the last pasted line. Pasting never leaves an empty line behind.
    /// Pictures copied with the text are imported first, so they arrive with it.
    func paste(_ fragment: PastedFragment) {
        guard !fragment.pictures.isEmpty, !showsSource else {
            insert(fragment)
            return
        }
        guard let view, parent.editable else { return }
        #if os(macOS)
            var selection = view.selectedRange()
        #else
            var selection = view.selectedRange
        #endif
        let id = parent.itemID
        let generation = sessionGeneration
        let text = currentText
        let handler = parent.imageHandler
        let places = fragment.blocks.indices.filter { fragment.pictureBlocks.contains(fragment.blocks[$0].id) }
        Task { [weak self] in
            var imported = fragment
            for (place, picture) in zip(places, fragment.pictures) {
                if let data = await InsertedText.imageData(of: picture), let image = await handler(data) {
                    imported.blocks[place] = image
                }
            }
            // A picture that can't be read is left out, with the line it would have taken.
            imported.blocks.removeAll { imported.pictureBlocks.contains($0.id) }
            guard let self, self.parent.itemID == id, self.parent.editable else { return }
            if self.sessionGeneration != generation {
                // Writing went on meanwhile; the paste goes where it was made.
                selection = TextRanges.insertionPoint(following: selection, from: text, to: self.currentText)
            }
            self.select(selection)
            self.insert(imported)
        }
    }

    private var currentText: String {
        #if os(macOS)
            view?.string ?? ""
        #else
            view?.text ?? ""
        #endif
    }

    private func select(_ range: NSRange) {
        #if os(macOS)
            view?.setSelectedRange(range)
        #else
            view?.selectedRange = range
        #endif
    }

    private func insert(_ fragment: PastedFragment) {
        guard let view, parent.editable else { return }
        #if os(macOS)
            guard !view.hasMarkedText(), let storage = view.textStorage else { return }
            let selection = view.selectedRange()
        #else
            guard view.markedTextRange == nil else { return }
            let storage = view.textStorage
            let selection = view.selectedRange
        #endif
        guard !showsSource else {
            replace(MarkdownEditing.render(fragment.markdown, size: parent.fontSize), range: selection)
            return
        }
        guard NSMaxRange(selection) <= storage.length, !fragment.blocks.isEmpty else { return }
        let source = storage.string as NSString
        let paragraph = source.paragraphRange(for: NSRange(location: selection.location, length: 0))
        let attributes = RichText.paragraphAttributes(storage, in: paragraph) ?? [:]
        if ["codeBlock", "html"].contains(attributes[.journalKind] as? String) {
            // Code takes only text, which stays part of it.
            replace(NSAttributedString(string: fragment.text, attributes: attributes), range: selection, adopting: true)
            return
        }
        let item = ListMarkers.itemKinds.contains(attributes[.journalKind] as? String ?? "")
        let end = NSMaxRange(selection)
        let separatorFollows = end < source.length && source.character(at: end) == 0x0A
        let restIsEmpty = end == source.length || separatorFollows
        if item, fragment.isPlain, pasteLines(fragment, into: storage, at: selection, restIsEmpty: restIsEmpty) {
            return
        }
        let text = rendered(fragment, continuing: attributes)
        let lineStart = selection.location == 0 || source.character(at: selection.location - 1) == 0x0A
        let single = fragment.blocks.count == 1 && fragment.blocks[0].kind == "paragraph"
        // A single line fills an empty line it is pasted on, such as a template's answer line.
        let joined = !lineStart || single && (!fragment.endsWithBreak || restIsEmpty)
        if joined { RichText.joinParagraph(text) }
        var range = selection
        var caret = text.length
        let ownEnd = separatorFollows && end == source.length - 1 && ListMarkers.hasOwnEnd(storage)
        if item, joined, restIsEmpty {
            // The pasted line joins the list item or quote, which keeps its own line break.
        } else if ownEnd, restIsEmpty {
            // The pasted blocks take the place of the empty last item, line break and all; the text's new last
            // paragraph gets a line break of its own if it is an item (ListEditing.swift).
            range.length += 1
        } else if separatorFollows || fragment.endsWithBreak && !restIsEmpty {
            text.append(NSAttributedString(string: "\n", attributes: Self.lineBreakAttributes(text)))
            if separatorFollows && restIsEmpty {
                // The pasted text ends the paragraph in place of its own line break, so no empty line is left.
                range.length += 1
            } else {
                caret += 1
            }
        }
        replace(text, range: range, adopting: true)
        let location = NSRange(location: range.location + caret, length: 0)
        select(location)
        view.scrollRangeToVisible(location)
    }

    /// Plain lines pasted into a list item or quote: the first joins it, each further line is the next item, and the
    /// rest of the item follows the last, as typing them does. False when the selection isn't in an item.
    private func pasteLines(
        _ fragment: PastedFragment, into storage: NSAttributedString, at selection: NSRange, restIsEmpty: Bool
    ) -> Bool {
        var lines = fragment.blocks.map { $0.runs.map(\.text).joined() }
        // A copied line break ends the last line before the rest of the item, never an empty item of its own.
        if fragment.endsWithBreak, !restIsEmpty { lines.append("") }
        guard let view, !lines.isEmpty,
            let action = RichText.itemLines(
                storage, range: selection, lines: lines,
                typing: RichText.attributes(kind: "paragraph", size: parent.fontSize),
                size: parent.fontSize)
        else { return false }
        replace(action.replacement, range: action.range)
        let caret = NSRange(location: action.caret ?? NSMaxRange(action.range), length: 0)
        select(caret)
        view.scrollRangeToVisible(caret)
        return true
    }

    /// The pasted blocks as the entry shows them. Plain lines pasted into a list continue it, as typing them does.
    private func rendered(_ fragment: PastedFragment, continuing attributes: [NSAttributedString.Key: Any])
        -> NSMutableAttributedString
    {
        var blocks = fragment.blocks
        let target = (attributes[.journalBlockMetadata] as? Data).flatMap {
            try? JournalCoding.decoder().decode(DocumentBlock.self, from: $0)
        }
        if fragment.isPlain, let target, ["bullet", "numbered", "task", "checked", "quote"].contains(target.kind) {
            for index in blocks.indices.dropFirst() {
                var item = target
                item.id = UUID()
                item.kind = target.kind == "checked" ? "task" : target.kind
                item.runs = blocks[index].runs
                item.listNumber = target.listNumber.map { $0 + index }
                blocks[index] = item
            }
        }
        return NSMutableAttributedString(
            attributedString: RichText.render(
                JournalDocument(blocks: blocks), size: parent.fontSize, images: parent.images, layout: imageLayout,
                endsText: false))
    }

    /// The paragraph attributes of the pasted text's last line, for the line break that ends it.
    private static func lineBreakAttributes(_ text: NSAttributedString) -> [NSAttributedString.Key: Any] {
        guard text.length > 0 else { return [:] }
        let kept: Set<NSAttributedString.Key> = [
            .font, .foregroundColor, .paragraphStyle, .journalKind, .journalBlockID, .journalBlockMetadata,
            .journalStructuredBlock,
        ]
        return text.attributes(at: text.length - 1, effectiveRange: nil).filter { kept.contains($0.key) }
    }
}
