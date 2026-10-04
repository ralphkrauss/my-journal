import JournalCore
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

#if os(macOS)
    typealias TextStorageEdits = NSTextStorageEditActions
#else
    typealias TextStorageEdits = NSTextStorage.EditActions
#endif

/// Text that the system inserts — typing, input methods, dictation, paste and drop — joins the block it lands in and
/// looks like the rest of the entry. UIKit keeps only standard attributes when typing, and pasted text brings its own
/// fonts and colours, so both are adopted here before the text is read.
extension NativeEditor.Coordinator: NSTextStorageDelegate {
    nonisolated func textStorage(
        _ textStorage: NSTextStorage, willProcessEditing editedMask: TextStorageEdits, range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters), editedRange.length > 0 else { return }
        // The editor's text storage is only ever edited on the main thread; this is its own delegate.
        MainActor.assumeIsolated { adoptInsertedText(in: editedRange) }
    }

    private func adoptInsertedText(in range: NSRange) {
        guard let storage = view?.textStorage, !replacingText, NSMaxRange(range) <= storage.length else { return }
        if showsSource {
            InsertedText.adoptSource(storage, range: range, size: parent.fontSize)
            return
        }
        let ownBlocks = checkingOwnReplacement ? [] : RichText.linesWithTheirOwnBlocks(storage, inserted: range)
        InsertedText.adopt(storage, range: range, size: parent.fontSize)
        if !checkingOwnReplacement {
            RichText.continueInsertedLines(storage, inserted: range, size: parent.fontSize, keeping: ownBlocks)
        }
        if InsertedText.containsForeignAttachment(storage, in: range) {
            DispatchQueue.main.async { [weak self] in self?.importForeignImages() }
        }
    }

    /// Images pasted or dropped as rich text arrive as attachments of their own. Each is imported like any other
    /// image and then replaces its attachment; one that isn't a readable image is removed, and the import reports why.
    func importForeignImages() {
        guard let view, parent.editable else { return }
        #if os(macOS)
            guard let storage = view.textStorage else { return }
        #else
            let storage = view.textStorage
        #endif
        let id = parent.itemID
        let handler = parent.imageHandler
        for attachment in InsertedText.foreignAttachments(storage)
        where importingAttachments.insert(ObjectIdentifier(attachment)).inserted {
            Task { [weak self] in
                var block: DocumentBlock?
                if let data = await InsertedText.imageData(of: attachment) { block = await handler(data) }
                self?.finishImport(attachment, block: block, itemID: id)
            }
        }
    }

    private func finishImport(_ attachment: NSTextAttachment, block: DocumentBlock?, itemID: UUID) {
        importingAttachments.remove(ObjectIdentifier(attachment))
        guard let view, parent.itemID == itemID, parent.editable else { return }
        #if os(macOS)
            guard let storage = view.textStorage else { return }
        #else
            let storage = view.textStorage
        #endif
        guard let range = InsertedText.location(of: attachment, in: storage) else { return }
        replace(NSAttributedString(), range: range)
        guard let block else { return }
        #if os(macOS)
            view.setSelectedRange(NSRange(location: range.location, length: 0))
        #else
            view.selectedRange = NSRange(location: range.location, length: 0)
        #endif
        perform(.image(block))
    }
}

@MainActor enum InsertedText {
    /// Attributes that place text in its block. Inserted text takes them from the block it lands in.
    private static let blockKeys: [NSAttributedString.Key] =
        [
            .journalKind, .journalBlockID, .journalBlockMetadata, .journalStructuredBlock, .journalListNumber,
            .journalListColumn,
        ] + ListAccessibility.keys

    /// In the Markdown source everything is plain monospaced text.
    static func adoptSource(_ storage: NSTextStorage, range: NSRange, size: CGFloat) {
        let source = MarkdownEditing.attributes(size: size)
        let monospaced = source[.font] as? PlatformFont
        storage.enumerateAttributes(in: range) { attributes, part, _ in
            guard attributes[.journalSource] as? Bool != true else { return }
            if (attributes[.font] as? PlatformFont)?.fontName == monospaced?.fontName {
                storage.addAttributes(source, range: part)
            } else {
                storage.setAttributes(source, range: part)
            }
        }
    }

    static func adopt(_ storage: NSTextStorage, range: NSRange, size: CGFloat) {
        let text = storage.string as NSString
        var start = range.location
        // Each paragraph of the inserted text joins the block of the paragraph it is in.
        while start < NSMaxRange(range) {
            let paragraph = text.paragraphRange(for: NSRange(location: start, length: 0))
            let piece = NSIntersectionRange(paragraph, NSRange(location: start, length: NSMaxRange(range) - start))
            adopt(storage, piece: piece, paragraph: paragraph, inserted: range, size: size)
            start = max(NSMaxRange(piece), start + 1)
        }
    }

    private static func adopt(
        _ storage: NSTextStorage, piece: NSRange, paragraph: NSRange, inserted: NSRange, size: CGFloat
    ) {
        var context = blockContext(storage, paragraph: paragraph, inserted: inserted)
        if let before = piece.location > paragraph.location ? piece.location - 1 : nil,
            !NSLocationInRange(before, inserted),
            storage.attribute(.journalMarker, at: before, effectiveRange: nil) == nil
        {
            // Typing continues inline code, as it does on the Mac.
            context[.journalCode] = storage.attribute(.journalCode, at: before, effectiveRange: nil)
        }
        storage.enumerateAttributes(in: piece) { attributes, part, _ in
            guard attributes[.attachment] == nil, attributes[.journalMarker] == nil else { return }
            var adopted = attributes
            let joins = attributes[.journalKind] == nil
            if joins {
                for (key, value) in context { adopted[key] = value }
            }
            let kind = adopted[.journalKind] as? String ?? "paragraph"
            if isForeign(adopted, kind: kind, size: size) {
                adopted = ownAttributes(from: adopted, kind: kind, size: size)
            } else if HiddenMarkers.isInvisible(adopted) {
                adopted = HiddenMarkers.typingAttributes(adopted, size: size)
            } else if !joins {
                return
            } else {
                // Text joining a heading, or leaving one, takes the size of the block it joins.
                adopted[.font] = RichText.attributes(kind: kind, size: size, run: foreignRun(adopted))[.font]
            }
            storage.setAttributes(adopted, range: part)
        }
    }

    /// The block attributes of the paragraph's own text, or of a new paragraph when it has none. Text never joins an
    /// image, table or rule.
    private static func blockContext(_ storage: NSTextStorage, paragraph: NSRange, inserted: NSRange)
        -> [NSAttributedString.Key: Any]
    {
        var owner: [NSAttributedString.Key: Any]?
        storage.enumerateAttribute(.journalKind, in: paragraph) { value, part, stop in
            guard value != nil, let outside = firstIndex(of: part, outside: inserted) else { return }
            owner = storage.attributes(at: outside, effectiveRange: nil)
            stop.pointee = true
        }
        guard let owner, !["image", "table", "rule"].contains(owner[.journalKind] as? String ?? "") else {
            return [.journalKind: "paragraph", .journalBlockID: UUID().uuidString]
        }
        var context = owner.filter { blockKeys.contains($0.key) }
        // A line's indent is its paragraph style, which text typed at its start on iOS would otherwise bring from the
        // line before, such as a list item's.
        context[.paragraphStyle] = owner[.paragraphStyle]
        return context
    }

    private static func firstIndex(of range: NSRange, outside inserted: NSRange) -> Int? {
        if range.location < inserted.location || range.location >= NSMaxRange(inserted) { return range.location }
        return NSMaxRange(range) > NSMaxRange(inserted) ? NSMaxRange(inserted) : nil
    }

    /// Text in another font or colour than the editor's own, as text pasted from a web page or document is.
    private static func isForeign(_ attributes: [NSAttributedString.Key: Any], kind: String, size: CGFloat) -> Bool {
        if let color = attributes[.foregroundColor] as? PlatformColor, color != PlatformColor.labelColorCompat,
            color.cgColor.alpha > 0
        {
            return true
        }
        guard let font = attributes[.font] as? PlatformFont else { return false }
        let own = RichText.attributes(kind: kind, size: size)[.font] as? PlatformFont
        let code = PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular)
        return font.familyName != own?.familyName && font.familyName != code.familyName
            || abs(font.pointSize - (own?.pointSize ?? size)) > 0.5 && abs(font.pointSize - size) > 0.5
    }

    /// The editor's own attributes for foreign text, keeping what Markdown can express: bold, italic, underline,
    /// strikethrough and links.
    private static func ownAttributes(from attributes: [NSAttributedString.Key: Any], kind: String, size: CGFloat)
        -> [NSAttributedString.Key: Any]
    {
        var result = RichText.attributes(kind: kind, size: size, run: foreignRun(attributes))
        for key in blockKeys { result[key] = attributes[key] }
        return result
    }

    /// The formatting of text from another app that Markdown can express. Links arrive underlined, as every app
    /// draws them; that underline is how a link looks, not formatting of its own.
    static func foreignRun(_ attributes: [NSAttributedString.Key: Any], text: String = "") -> TextRun {
        let font = attributes[.font] as? PlatformFont
        #if os(macOS)
            let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
            let bold = traits.contains(.boldFontMask)
            let italic = traits.contains(.italicFontMask)
        #else
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let bold = traits.contains(.traitBold)
            let italic = traits.contains(.traitItalic)
        #endif
        let linked = attributes[.link] != nil
        let link = webLink((attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String)
        let underlined = (attributes[.underlineStyle] as? Int ?? 0) != 0
        var run = TextRun(text, bold: bold, italic: italic, underline: underlined && !linked, link: link)
        run.strikethrough = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
        run.code = (attributes[.journalCode] as? Int ?? 0) != 0
        return run
    }

    /// A link from another app that opens a web page or writes an email. A page's links to its own parts, or to
    /// anything else, would go nowhere from the journal; their text is kept without the link.
    private static func webLink(_ address: String?) -> String? {
        guard let address, ["http:", "https:", "mailto:"].contains(where: address.lowercased().hasPrefix) else {
            return nil
        }
        return LinkAddress.url(address)?.absoluteString
    }

    static func containsForeignAttachment(_ storage: NSAttributedString, in range: NSRange) -> Bool {
        var found = false
        storage.enumerateAttribute(.attachment, in: range) { value, part, stop in
            guard value != nil, isForeignAttachment(storage, at: part.location) else { return }
            found = true
            stop.pointee = true
        }
        return found
    }

    static func foreignAttachments(_ storage: NSAttributedString) -> [NSTextAttachment] {
        var result: [NSTextAttachment] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, part, _ in
            guard let attachment = value as? NSTextAttachment, isForeignAttachment(storage, at: part.location) else {
                return
            }
            result.append(attachment)
        }
        return result
    }

    private static func isForeignAttachment(_ storage: NSAttributedString, at index: Int) -> Bool {
        let attributes = storage.attributes(at: index, effectiveRange: nil)
        return attributes[.journalImage] == nil && attributes[.journalTable] == nil
            && attributes[.journalInlineImage] == nil
    }

    static func location(of attachment: NSTextAttachment, in storage: NSAttributedString) -> NSRange? {
        var result: NSRange?
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, part, stop in
            guard (value as? NSTextAttachment) === attachment else { return }
            result = NSRange(location: part.location, length: 1)
            stop.pointee = true
        }
        return result
    }

    /// The attachment's original image file when it has one, else its picture encoded once.
    static func imageData(of attachment: NSTextAttachment) async -> Data? {
        if let contents = attachment.contents { return contents }
        if let file = attachment.fileWrapper, file.isRegularFile, let contents = file.regularFileContents {
            return contents
        }
        #if os(macOS)
            guard let image = attachment.image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            return await PastedImages.data(for: .picture(image))
        #else
            guard let image = attachment.image, let source = PastedImages.picture(image) else { return nil }
            return await PastedImages.data(for: source)
        #endif
    }
}
