import ImageIO
import JournalCore
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Pictures decoded at the size they are shown rather than at the photo's full resolution: a 12-megapixel photo takes
/// about 48 MB decoded, while the editor shows it a few hundred points wide. Each editor keeps its own, only for the
/// pictures of the entry it shows.
@MainActor final class ImageThumbnails {
    private struct Key: Hashable {
        let id: UUID
        let bytes: Int
        let pixels: Int
    }
    private var decoded: [Key: CGImage] = [:]

    /// Forgets pictures that are no longer shown, such as those of another entry or of a locked journal.
    func keep(_ images: [UUID: Data]) {
        decoded = decoded.filter { images[$0.key.id]?.count == $0.key.bytes }
    }

    /// The picture at no more than `pixels` along its longer side. Sizes are rounded up so that resizing a window
    /// reuses the picture decoded before.
    func image(_ id: UUID, data: Data, pixels: Int) -> CGImage? {
        let key = Key(id: id, bytes: data.count, pixels: (max(1, pixels) + 255) / 256 * 256)
        if let image = decoded[key] { return image }
        let image = Self.decode(data, pixels: key.pixels)
        decoded[key] = image
        return image
    }

    nonisolated static func decode(_ data: Data, pixels: Int) -> CGImage? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true, kCGImageSourceThumbnailMaxPixelSize: pixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The picture's size in points, as the platform would give it, read from its metadata without decoding it.
    nonisolated static func pointSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue, width > 0, height > 0
        else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let pixels = orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        #if os(macOS)
            // As NSImage does, a picture made for a Retina screen is half as many points as pixels.
            let dpi = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
            let points = 72 / (dpi > 0 ? dpi : 72)
            return CGSize(width: pixels.width * points, height: pixels.height * points)
        #else
            return pixels
        #endif
    }
}

/// An image attachment that records what it shows, so refreshing the entry replaces only pictures that changed.
final class JournalImageAttachment: NSTextAttachment {
    var shows: ImageAppearance?
}

struct ImageAppearance: Equatable {
    let id: UUID?
    let bytes: Int?
    let loading: Bool
    let remote: Bool
    let width: CGFloat
    let description: String
    let placeholder: PlatformColor?
}
