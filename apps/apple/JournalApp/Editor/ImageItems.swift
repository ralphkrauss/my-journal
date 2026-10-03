import ImageIO
import JournalCore
import SwiftUI
import UniformTypeIdentifiers

/// A picture in an entry's text, for acting on it: copying, sharing, saving and deleting it
/// (docs/design/image-actions-ios-2026-10-03.md). Shared by iPhone, iPad and the Mac.
struct ImageItem: Equatable {
    /// The attachment character's position in the text.
    let index: Int
    let block: DocumentBlock
    /// A picture inside a line of text rather than on a line of its own.
    let inline: Bool

    var attachmentID: UUID? { block.attachmentID }
    var description: String { (block.imageDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The stored file's type: what its bytes are, or else the media type recorded when it was added.
    func type(of data: Data) -> UTType {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
            let identifier = CGImageSourceGetType(source), let type = UTType(identifier as String)
        {
            return type
        }
        return recordedType ?? .image
    }

    /// The media type recorded when the picture was added, before its bytes are read.
    var recordedType: UTType? { block.mediaType.flatMap { UTType(mimeType: $0) } }

    /// The name a shared file gets: “Image” with the type's extension. Not the description, which may be private
    /// and would travel with the file.
    static func fileName(for type: UTType) -> String {
        "Image" + (type.preferredFilenameExtension.map { "." + $0 } ?? "")
    }

    /// The picture at `index`, if the character there is one of the entry's pictures.
    static func at(_ index: Int, in text: NSAttributedString) -> ImageItem? {
        guard index >= 0, index < text.length, text.attribute(.attachment, at: index, effectiveRange: nil) != nil
        else { return nil }
        if let data = text.attribute(.journalImage, at: index, effectiveRange: nil) as? Data,
            let block = try? JournalCoding.decoder().decode(DocumentBlock.self, from: data), block.kind == "image"
        {
            return ImageItem(index: index, block: block, inline: false)
        }
        if let data = text.attribute(.journalInlineImage, at: index, effectiveRange: nil) as? Data,
            let run = try? JournalCoding.decoder().decode(TextRun.self, from: data)
        {
            let block = DocumentBlock(
                kind: "image", attachmentID: run.imageAttachmentID, imageDescription: run.text,
                mediaType: run.imageMediaType)
            return ImageItem(index: index, block: block, inline: true)
        }
        return nil
    }

    /// The picture alone in `range`, as when a tap selected it.
    static func selected(_ range: NSRange, in text: NSAttributedString) -> ImageItem? {
        guard range.length == 1 else { return nil }
        return at(range.location, in: text)
    }

    /// What removing the picture removes: a picture on its own line goes with that line; one inside a line, alone.
    func deletionRange(in text: NSString) -> NSRange {
        guard !inline else { return NSRange(location: index, length: 1) }
        let line = text.paragraphRange(for: NSRange(location: index, length: 0))
        // The last line has no break of its own; the break before it goes instead, so no empty line is left.
        if NSMaxRange(line) == text.length, !text.substring(with: line).hasSuffix("\n"), line.location > 0 {
            return NSRange(location: line.location - 1, length: line.length + 1)
        }
        return line
    }

    /// The image as other apps paste it: the stored file under its own type, and a JPEG copy of a HEIC or HEIF
    /// image for apps that don't take those.
    static func pasteboardRepresentations(of data: Data, type: UTType) -> [String: Data] {
        var result = [type.identifier: data]
        if type.conforms(to: .heic) || type.conforms(to: .heif), let jpeg = jpeg(from: data) {
            result[UTType.jpeg.identifier] = jpeg
        }
        return result
    }

    private static func jpeg(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        CGImageDestinationAddImageFromSource(destination, source, 0, options)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

/// What the editor needs from the app to act on a picture: reading its stored original, saying what went wrong,
/// and opening Image Descriptions where the entry offers it.
struct ImageActionSupport {
    /// The stored original of an attachment, read from the encrypted store; nil when it can't be read.
    var original: @MainActor (UUID) async -> Data?
    /// Shows a failure in the app's error alert.
    var report: @MainActor (String) -> Void
    /// Opens Image Descriptions; nil where the entry doesn't offer it.
    var describe: (@MainActor () -> Void)?
}
