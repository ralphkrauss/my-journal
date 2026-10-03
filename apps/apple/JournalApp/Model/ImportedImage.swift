import Foundation
import ImageIO
import JournalCore
import UniformTypeIdentifiers

extension AppModel {
    /// Stores an image for the open entry and returns its block, or nil when it couldn't be stored (the error alert
    /// says why) or the entry, library or lock changed meanwhile.
    func addImage(_ data: Data) async -> DocumentBlock? {
        do {
            return try await importImage(data)
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// Stores an image for the open entry and returns its block; nil when the entry, library or lock changed
    /// meanwhile, and an error only while they haven't. With `showing`, the editor gets the picture at once instead of
    /// reading it back from the store.
    func importImage(_ data: Data, showing: Bool = true) async throws -> DocumentBlock? {
        guard let store, let entryID = draft?.id, !locked, !replacingVault else { return nil }
        let generation = imageInsertionGeneration
        func current() -> Bool {
            !Task.isCancelled && imageInsertionGeneration == generation && self.store === store
                && draft?.id == entryID && !locked && !replacingVault
        }
        do {
            guard data.count <= ImportedImage.maximumBytes else { throw ImportedImage.Problem.tooLarge }
            // Where the photo was taken is removed before anything is stored.
            let image = try await Task.detached { try ImportedImage.prepare(data) }.value
            let id = try await store.addAttachment(image.data)
            guard current() else { return nil }
            if showing { imageLoader.prime(image.data, id: id, documentID: entryID, store: store) }
            return DocumentBlock(kind: "image", attachmentID: id, imageDescription: "", mediaType: image.mediaType)
        } catch {
            guard current() else { return nil }
            throw error
        }
    }
}

enum ImportedImage {
    /// The bytes to store for an image being added (from Photos, the camera, Files, pasting or dropping) and their
    /// media type. Where the photo was taken is removed: GPS coordinates and place names. Where the format allows,
    /// the image data is copied unchanged; otherwise it's encoded again without loss where the format has none.
    /// Orientation, capture time and other metadata are kept, and an image without location is stored as it was.
    static func prepare(_ data: Data) throws -> (data: Data, mediaType: String) {
        let type = try mediaType(for: data)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), Location.found(in: source) else {
            return (data, type)
        }
        guard let cleaned = Location.copyWithout(source) ?? Location.encodeWithout(source) else {
            throw ImportError.unreadable
        }
        return (cleaned, try mediaType(for: cleaned))
    }

    static func mediaType(for data: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetCount(source) > 0,
            CGImageSourceGetStatus(source) == .statusComplete,
            let identifier = CGImageSourceGetType(source),
            let type = UTType(identifier as String), type.conforms(to: .image),
            let mediaType = type.preferredMIMEType
        else { throw ImportError.unreadable }
        return mediaType
    }

    private enum ImportError: LocalizedError {
        case unreadable
        var errorDescription: String? { "This file couldn’t be read as an image." }
    }

    /// The largest image the store keeps (its encrypted copy has 28 bytes more).
    static let maximumBytes = 25 * 1024 * 1024 - 28

    /// Why an image couldn't be added, for one message about several images.
    enum Problem: LocalizedError, Equatable {
        case tooLarge
        case unreadable
        /// The photo library couldn't provide the photo, such as an iCloud original that isn't downloaded.
        case unavailable

        var errorDescription: String? {
            switch self {
            case .tooLarge: return "Choose an image smaller than 25 MB."
            case .unreadable: return "This file couldn’t be read as an image."
            case .unavailable:
                return "The image couldn’t be added. It may still be downloading from iCloud. Try again later."
            }
        }

        /// The cause of a failure, as one message about several images names it.
        static func of(_ error: Error) -> Problem {
            if let problem = error as? Problem { return problem }
            return .unreadable
        }
    }

    /// Location metadata: EXIF GPS, and the IPTC place fields as ImageIO presents them in XMP and IIM.
    private enum Location {
        static let places: Set<String> = [
            "photoshop:City", "photoshop:State", "photoshop:Country", "Iptc4xmpCore:Location",
            "Iptc4xmpCore:CountryCode", "Iptc4xmpExt:LocationCreated", "Iptc4xmpExt:LocationShown",
        ]
        static var placeKeys: [CFString] {
            [
                kCGImagePropertyIPTCCity, kCGImagePropertyIPTCSubLocation, kCGImagePropertyIPTCProvinceState,
                kCGImagePropertyIPTCCountryPrimaryLocationName, kCGImagePropertyIPTCCountryPrimaryLocationCode,
            ]
        }

        static func found(in source: CGImageSource) -> Bool {
            (0..<CGImageSourceGetCount(source)).contains { index in
                let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
                let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
                let metadata = CGImageSourceCopyMetadataAtIndex(source, index, nil)
                return properties[kCGImagePropertyGPSDictionary] != nil || placeKeys.contains { iptc[$0] != nil }
                    || !(metadata.map { paths(in: $0) } ?? []).isEmpty
            }
        }

        /// The paths of the top-level location tags in `metadata`.
        static func paths(in metadata: CGImageMetadata) -> [String] {
            var paths: [String] = []
            CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, nil) { path, tag in
                let prefix = CGImageMetadataTagCopyPrefix(tag).map { $0 as String } ?? ""
                let name = CGImageMetadataTagCopyName(tag).map { $0 as String } ?? ""
                if (prefix == "exif" && name.hasPrefix("GPS")) || places.contains(prefix + ":" + name) {
                    paths.append(path as String)
                }
                return true
            }
            return paths
        }

        static func metadataWithout(_ source: CGImageSource, at index: Int) -> CGImageMetadata? {
            guard let metadata = CGImageSourceCopyMetadataAtIndex(source, index, nil),
                let cleaned = CGImageMetadataCreateMutableCopy(metadata)
            else { return nil }
            for path in paths(in: metadata) { CGImageMetadataRemoveTagWithPath(cleaned, nil, path as CFString) }
            return cleaned
        }

        /// Copies the image data unchanged with the cleaned metadata, where ImageIO supports that for the format.
        static func copyWithout(_ source: CGImageSource) -> Data? {
            guard let type = CGImageSourceGetType(source) else { return nil }
            let output = NSMutableData()
            guard
                let destination = CGImageDestinationCreateWithData(output, type, CGImageSourceGetCount(source), nil)
            else { return nil }
            // Without replacement metadata some formats would drop all of it, including the orientation.
            guard let metadata = metadataWithout(source, at: 0) else { return nil }
            let options: [CFString: Any] = [
                kCGImageMetadataShouldExcludeGPS: true, kCGImageDestinationMetadata: metadata,
                kCGImageDestinationMergeMetadata: false,
            ]
            guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil) else {
                return nil
            }
            return verified(output as Data)
        }

        /// Encodes each image again with its cleaned metadata: in the same format when ImageIO can write it, as PNG
        /// otherwise. Formats without loss, such as PNG, keep every pixel.
        static func encodeWithout(_ source: CGImageSource) -> Data? {
            let count = CGImageSourceGetCount(source)
            let writable = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
            let type = CGImageSourceGetType(source).flatMap { writable.contains($0 as String) ? $0 : nil }
            let output = NSMutableData()
            guard
                let destination = CGImageDestinationCreateWithData(
                    output, type ?? (UTType.png.identifier as CFString), count, nil)
            else { return nil }
            for index in 0..<count {
                guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
                let options = [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary
                CGImageDestinationAddImageAndMetadata(
                    destination, image, metadataWithout(source, at: index), options)
            }
            guard CGImageDestinationFinalize(destination) else { return nil }
            return verified(output as Data)
        }

        static func verified(_ data: Data) -> Data? {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
                !found(in: source)
            else { return nil }
            return data
        }
    }
}
