import JournalCore
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

@MainActor
enum ImagePresentation {
    static func placeholderColor(in view: JournalTextView) -> PlatformColor {
        #if os(macOS)
            var color = NSColor.secondaryLabelColor
            view.effectiveAppearance.performAsCurrentDrawingAppearance {
                color = NSColor(cgColor: NSColor.secondaryLabelColor.cgColor) ?? .gray
            }
            return color
        #else
            return UIColor.secondaryLabel.resolvedColor(with: view.traitCollection)
        #endif
    }

    static func attachment(
        _ block: DocumentBlock, images: [UUID: Data], loading: Set<UUID>, size: CGFloat, width: CGFloat,
        placeholderColor: PlatformColor? = nil, remote: Bool = false, scale: CGFloat = 2,
        thumbnails: ImageThumbnails? = nil
    )
        -> NSTextAttachment
    {
        let attachment = JournalImageAttachment()
        let description = block.imageDescription ?? ""
        let pending = block.attachmentID.map { loading.contains($0) } == true
        let status = remote ? "Remote image" : pending ? "Loading Image…" : "Image unavailable"
        let label =
            (remote ? "Remote image. Not downloaded." : pending ? "Loading Image." : "Image unavailable.")
            + (description.isEmpty ? "" : " \(description)")
        let availableWidth = max(40, width)
        attachment.shows = appearance(
            block, images: images, loading: loading, width: width, placeholderColor: placeholderColor, remote: remote)
        if let id = block.attachmentID, let bytes = images[id],
            let picture = picture(id, data: bytes, width: availableWidth, scale: scale, thumbnails: thumbnails)
        {
            #if os(macOS)
                let image = NSImage(cgImage: picture.image, size: picture.size)
                image.accessibilityDescription = description.isEmpty ? "Image" : description
                attachment.attachmentCell = JournalImageCell(imageCell: image)
            #else
                attachment.image = UIImage(cgImage: picture.image)
                attachment.bounds = CGRect(origin: .zero, size: picture.size)
                attachment.accessibilityLabel = description.isEmpty ? "Image" : description
            #endif
            return attachment
        }
        #if os(macOS)
            let text = NSAttributedString(
                string: status,
                attributes: [
                    .font: NSFont.systemFont(ofSize: size),
                    .foregroundColor: placeholderColor ?? NSColor.secondaryLabelColor,
                ])
            let bounds = text.boundingRect(
                with: NSSize(width: availableWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading])
            let image = NSImage(size: NSSize(width: availableWidth, height: ceil(bounds.height) + 12))
            image.lockFocus()
            text.draw(
                with: NSRect(x: 0, y: 6, width: availableWidth, height: ceil(bounds.height)),
                options: [.usesLineFragmentOrigin, .usesFontLeading])
            image.unlockFocus()
            image.accessibilityDescription = label
            attachment.attachmentCell = JournalImageCell(imageCell: image)
        #else
            let text = NSAttributedString(
                string: status,
                attributes: [
                    .font: UIFont.systemFont(ofSize: size),
                    .foregroundColor: placeholderColor ?? UIColor.secondaryLabel,
                ])
            let bounds = text.boundingRect(
                with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            let dimensions = CGSize(width: availableWidth, height: ceil(bounds.height) + 12)
            attachment.image = UIGraphicsImageRenderer(size: dimensions).image { _ in
                text.draw(
                    with: CGRect(x: 0, y: 6, width: availableWidth, height: ceil(bounds.height)),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            }
            attachment.bounds = CGRect(origin: .zero, size: dimensions)
            attachment.accessibilityLabel = label
        #endif
        return attachment
    }

    /// A picture decoded at the pixel size it is shown at, and that size in points: its own size, or narrower to fit.
    private static func picture(
        _ id: UUID, data: Data, width: CGFloat, scale: CGFloat, thumbnails: ImageThumbnails?
    ) -> (image: CGImage, size: CGSize)? {
        guard let natural = ImageThumbnails.pointSize(of: data) else { return nil }
        let ratio = min(1, width / natural.width)
        let size = CGSize(width: natural.width * ratio, height: natural.height * ratio)
        let pixels = Int(ceil(max(size.width, size.height) * max(1, scale)))
        let image = thumbnails?.image(id, data: data, pixels: pixels) ?? ImageThumbnails.decode(data, pixels: pixels)
        return image.map { ($0, size) }
    }

    /// What an image block looks like with these images, so an unchanged picture keeps its attachment.
    static func appearance(
        _ block: DocumentBlock, images: [UUID: Data], loading: Set<UUID>, width: CGFloat,
        placeholderColor: PlatformColor?, remote: Bool = false
    ) -> ImageAppearance {
        let bytes = block.attachmentID.flatMap { images[$0]?.count }
        return ImageAppearance(
            id: block.attachmentID, bytes: bytes, loading: block.attachmentID.map(loading.contains) == true,
            remote: remote, width: max(40, width), description: block.imageDescription ?? "",
            placeholder: bytes == nil ? placeholderColor : nil)
    }

    /// Shows the images as they are now, replacing only attachments whose picture, size or state changed.
    static func update(
        _ storage: NSMutableAttributedString, images: [UUID: Data], size: CGFloat, layout: RichText.ImageLayout
    ) {
        var replacements: [(NSRange, DocumentBlock)] = []
        storage.enumerateAttribute(.journalImage, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let bytes = value as? Data,
                let block = try? JournalCoding.decoder().decode(DocumentBlock.self, from: bytes)
            {
                replacements += attachmentCharacters(storage, in: range).map { ($0, block) }
            }
        }
        storage.beginEditing()
        storage.enumerateAttribute(.journalInlineImage, in: NSRange(location: 0, length: storage.length)) {
            value, range, _ in
            guard let data = value as? Data, let run = try? JournalCoding.decoder().decode(TextRun.self, from: data)
            else { return }
            for character in attachmentCharacters(storage, in: range) {
                let current = storage.attribute(.attachment, at: character.location, effectiveRange: nil)
                if let shown = (current as? JournalImageAttachment)?.shows,
                    shown == RichText.inlineAppearance(run, images: images)
                {
                    continue
                }
                if let attachment = RichText.inlineImage(run, size: size, images: images, layout: layout).attribute(
                    .attachment, at: 0, effectiveRange: nil)
                {
                    storage.addAttribute(.attachment, value: attachment, range: character)
                }
            }
        }
        for (range, block) in replacements {
            let current = storage.attribute(.attachment, at: range.location, effectiveRange: nil)
            let wanted = appearance(
                block, images: images, loading: layout.loading, width: layout.width,
                placeholderColor: layout.placeholderColor)
            if (current as? JournalImageAttachment)?.shows == wanted { continue }
            storage.addAttribute(
                .attachment,
                value: attachment(
                    block, images: images, loading: layout.loading, size: size, width: layout.width,
                    placeholderColor: layout.placeholderColor, scale: layout.scale, thumbnails: layout.thumbnails),
                range: range)
        }
        storage.endEditing()
    }

    /// The attachment characters in `range`; text that picked up an image's attributes never becomes a picture.
    private static func attachmentCharacters(_ storage: NSAttributedString, in range: NSRange) -> [NSRange] {
        let characters = storage.string as NSString
        return (range.location..<NSMaxRange(range)).filter { characters.character(at: $0) == 0xFFFC }.map {
            NSRange(location: $0, length: 1)
        }
    }

    static func visibleAnchor(
        _ storage: NSTextStorage, layout: NSLayoutManager, container: NSTextContainer, viewport: CGRect
    ) -> Int? {
        // Laying out up to the visible part is enough, however long the entry is.
        layout.ensureLayout(forBoundingRect: viewport, in: container)
        let glyphs = layout.glyphRange(forBoundingRect: viewport, in: container)
        guard glyphs.length > 0 else { return nil }
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        for index in characters.location..<NSMaxRange(characters) where index < storage.length {
            if storage.attribute(.attachment, at: index, effectiveRange: nil) == nil { return index }
        }
        return nil
    }

    static func anchorY(_ index: Int?, layout: NSLayoutManager, container: NSTextContainer) -> CGFloat? {
        guard let index else { return nil }
        let character = NSRange(location: index, length: 1)
        layout.ensureLayout(forCharacterRange: character)
        let glyphs = layout.glyphRange(forCharacterRange: character, actualCharacterRange: nil)
        return layout.boundingRect(forGlyphRange: glyphs, in: container).minY
    }
}
