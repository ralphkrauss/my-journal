import ImageIO
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Chooses what a paste or drop inserts, and keeps pictures as the files they were: a photo stays the JPEG or HEIC
/// it came as instead of becoming a much larger PNG or TIFF.
enum PastedImages {
    /// The entry's own Markdown for copied text, so copy and paste within the journal keeps images, tables and lists.
    static let markdownType = "org.myjournal.markdown"

    /// An image to import, as the pasteboard or a drop offered it.
    enum Source: Sendable {
        /// An image file's own bytes, kept as they are.
        case original(Data)
        /// An image file on disk, read when it is imported.
        case file(URL)
        /// A bitmap without a file of its own, such as TIFF, encoded once when it is imported.
        case bitmap(Data)
        /// A picture offered only as an image object.
        case picture(CGImage)
    }

    /// Image types whose bytes are kept as they are, most compact first.
    static let originalTypes: [UTType] = [.heic, .heif, .jpeg, .png, .gif]

    /// The bytes to import, read and encoded away from the main thread.
    static func data(for source: Source) async -> Data? {
        switch source {
        case .original(let data): return data
        case .file(let url):
            return await Task.detached(priority: .userInitiated) { try? Data(contentsOf: url) }.value
        case .bitmap(let data):
            return await Task.detached(priority: .userInitiated) { encodeBitmap(data) }.value
        case .picture(let image):
            return await Task.detached(priority: .userInitiated) { encode(image: image) }.value
        }
    }

    private static func encodeBitmap(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return encode(image: image)
    }

    /// JPEG for opaque pictures, PNG when transparency matters.
    private static func encode(image: CGImage) -> Data? {
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let type = opaque ? UTType.jpeg : UTType.png
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, type.identifier as CFString, 1, nil) else {
            return nil
        }
        let options = opaque ? [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary : nil
        CGImageDestinationAddImage(destination, image, options)
        return CGImageDestinationFinalize(destination) ? result as Data : nil
    }

    /// Text that is only a web address, as browsers offer alongside a copied picture.
    static func isAddressOnly(_ text: String?) -> Bool {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
            !text.contains(where: \.isWhitespace), let url = URL(string: text)
        else { return false }
        return ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "")
    }

    static func isImageFile(_ url: URL) -> Bool {
        guard url.isFileURL, let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }
}

#if os(macOS)
    extension NSPasteboard.PasteboardType {
        static let journalMarkdown = Self(PastedImages.markdownType)
    }

    extension PastedImages {
        static let readableImageTypes: [NSPasteboard.PasteboardType] =
            originalTypes.map { NSPasteboard.PasteboardType($0.identifier) } + [.tiff]

        /// The images to insert, or none when the pasteboard holds text to paste instead. Text from word processors
        /// and spreadsheets comes with a picture of itself, which is not what the person copied.
        static func images(on board: NSPasteboard) -> [Source] {
            let files =
                (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            if !files.isEmpty { return files.filter(isImageFile).map(Source.file) }
            let text: [NSPasteboard.PasteboardType] = [.rtf, .rtfd, .html]
            guard board.availableType(from: text) == nil,
                board.string(forType: .string) == nil || isAddressOnly(board.string(forType: .string))
            else { return [] }
            return (board.pasteboardItems ?? []).compactMap(source)
        }

        private static func source(_ item: NSPasteboardItem) -> Source? {
            for type in originalTypes {
                if let data = item.data(forType: NSPasteboard.PasteboardType(type.identifier)) {
                    return .original(data)
                }
            }
            return item.data(forType: .tiff).map(Source.bitmap)
        }
    }
#else
    extension PastedImages {
        /// The images to insert, or none when the pasteboard holds text to paste instead. Text from word processors
        /// and spreadsheets comes with a picture of itself, which is not what the person copied.
        static func images(on board: UIPasteboard) -> [Source] {
            let text = [UTType.rtf, .rtfd, .flatRTFD, .html].map(\.identifier)
            guard board.hasImages, !board.contains(pasteboardTypes: text),
                !board.hasStrings || isAddressOnly(board.string)
            else { return [] }
            let originals = (0..<board.numberOfItems).compactMap { original(on: board, item: $0) }
            guard originals.isEmpty else { return originals }
            return (board.images ?? []).compactMap(picture)
        }

        private static func original(on board: UIPasteboard, item: Int) -> Source? {
            for type in originalTypes {
                if let data = board.data(forPasteboardType: type.identifier, inItemSet: IndexSet(integer: item))?.first
                {
                    return .original(data)
                }
            }
            return nil
        }

        /// Drawing applies the picture's orientation, which its bitmap alone doesn't carry.
        static func picture(_ image: UIImage) -> Source? {
            let format = UIGraphicsImageRendererFormat.preferred()
            format.scale = image.scale
            let drawn = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in image.draw(at: .zero) }
            return drawn.cgImage.map(Source.picture)
        }
    }
#endif
