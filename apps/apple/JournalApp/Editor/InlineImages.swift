import JournalCore
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

extension NSAttributedString.Key {
    static let journalInlineImage = Self("JournalInlineImage")
}

extension RichText {
    /// Images within a line of text are shown small, at most 120 points wide and 80 points high.
    static func inlineImage(_ run: TextRun, size: CGFloat, images: [UUID: Data], layout: ImageLayout = .init())
        -> NSAttributedString
    {
        let attachment = ImagePresentation.attachment(
            inlineBlock(run), images: images, loading: [], size: size, width: 120,
            remote: run.imageAttachmentID == nil, scale: layout.scale, thumbnails: layout.thumbnails)
        #if os(macOS)
            if let cell = attachment.attachmentCell as? NSTextAttachmentCell, let image = cell.image,
                image.size.height > 80
            {
                image.size = CGSize(width: image.size.width * 80 / image.size.height, height: 80)
            }
        #else
            if attachment.bounds.height > 80 {
                attachment.bounds.size = CGSize(
                    width: attachment.bounds.width * 80 / attachment.bounds.height, height: 80)
            }
        #endif
        let result = NSMutableAttributedString(attachment: attachment)
        if let data = try? JournalCoding.encoder().encode(run) {
            result.addAttribute(.journalInlineImage, value: data, range: NSRange(location: 0, length: result.length))
        }
        return result
    }
    static func inlineAppearance(_ run: TextRun, images: [UUID: Data]) -> ImageAppearance {
        ImagePresentation.appearance(
            inlineBlock(run), images: images, loading: [], width: 120, placeholderColor: nil,
            remote: run.imageAttachmentID == nil)
    }
    private static func inlineBlock(_ run: TextRun) -> DocumentBlock {
        DocumentBlock(
            kind: "image", attachmentID: run.imageAttachmentID, imageDescription: run.text,
            mediaType: run.imageMediaType)
    }
}
