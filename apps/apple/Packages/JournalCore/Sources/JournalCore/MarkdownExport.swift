import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What an export left out, for the note after saving.
public struct MarkdownExportSummary: Equatable, Sendable {
    /// Images that haven't downloaded to this device yet.
    public var imagesNotDownloaded = 0
    /// Images whose files couldn't be read or recognized.
    public var imagesUnreadable = 0
    /// Entries and templates made with a newer version, which this version can't read.
    public var itemsUnreadable = 0
    /// Exported entries and templates with another version from a conflict, which isn't exported.
    public var itemsWithOtherVersions = 0
    public init() {}
}

/// Export as Markdown (protocol/markdown-export.md): a folder per journal, a Markdown file with YAML front matter
/// per entry, and each journal's images in its `attachments` folder, for other apps to open.
public enum MarkdownExport {
    /// Raised when the layout or the front matter keys change.
    static let formatVersion = 1
    static let manifestName = ".journal-export.json"
    /// The files are readable journals, so on iPhone and iPad they can't be read while the device is locked.
    private static var writing: Data.WritingOptions {
        #if os(iOS)
            return [.withoutOverwriting, .completeFileProtection]
        #else
            return [.withoutOverwriting]
        #endif
    }

    /// The folder's name in the save dialog, as `Journal Markdown 2026-10-05`.
    public static func folderName(date: Date = Date(), timeZone: TimeZone = .current) -> String {
        "Journal Markdown " + day(date, timeZone: timeZone)
    }

    /// Writes the library into `folder`, which must not exist yet. Removes what it wrote if it fails or is cancelled.
    public static func write(store: JournalStore, to folder: URL, timeZone: TimeZone = .current) async throws
        -> MarkdownExportSummary
    {
        let snapshot = try await store.viewSnapshot()
        let items = snapshot.items
        let arrangement = snapshot.library
        let conflicted = snapshot.conflictedIDs
        let plan = MarkdownExportPlan(
            items: items, pinned: arrangement.pinned, ranks: arrangement.ranks, timeZone: timeZone)
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        do {
            try manifest(date: Date()).write(
                to: folder.appendingPathComponent(manifestName), options: writing)
            var summary = MarkdownExportSummary()
            summary.itemsUnreadable = plan.unreadable
            var missing = MissingImages()
            for group in plan.folders {
                try Task.checkCancellation()
                let directory = folder.appendingPathComponent(group.name, isDirectory: true)
                try manager.createDirectory(at: directory, withIntermediateDirectories: false)
                var written: [UUID: String] = [:]
                for file in group.files {
                    try Task.checkCancellation()
                    if conflicted.contains(file.item.id) { summary.itemsWithOtherVersions += 1 }
                    let paths = try await images(
                        file.item, in: directory, store: store, written: &written, missing: &missing)
                    let linked = body(file.item.document.markdown, paths: paths)
                    // Links that can't be rewritten still find their image under its bare name.
                    for id in linked.unlinked {
                        guard let path = paths[id] else { continue }
                        let bare = directory.appendingPathComponent("attachments/" + id.uuidString.lowercased())
                        if !manager.fileExists(atPath: bare.path) {
                            try manager.copyItem(at: directory.appendingPathComponent(path), to: bare)
                        }
                    }
                    let text = markdown(file, folder: group, body: linked.text, timeZone: timeZone)
                    try Data(text.utf8).write(
                        to: directory.appendingPathComponent(file.name + ".md"), options: writing)
                }
            }
            summary.imagesNotDownloaded = missing.notDownloaded.count
            summary.imagesUnreadable = missing.unreadable.count
            return summary
        } catch {
            try? manager.removeItem(at: folder)
            throw error
        }
    }

    /// `.journal-export.json`: which format and version the folder follows.
    static func manifest(date: Date) throws -> Data {
        struct Manifest: Encodable {
            let format: String
            let version: Int
            let exported: String
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(
            Manifest(
                format: "my-journal-markdown", version: formatVersion,
                exported: timestamp(date, timeZone: TimeZone(identifier: "UTC") ?? .current)))
    }

    /// Images left out, each counted once however many entries use it.
    private struct MissingImages {
        var notDownloaded: Set<UUID> = []
        var unreadable: Set<UUID> = []
        func contains(_ id: UUID) -> Bool { notDownloaded.contains(id) || unreadable.contains(id) }
    }

    /// Writes the images `item` refers to into the folder's `attachments`, once per folder, and returns the relative
    /// path for each image written.
    private static func images(
        _ item: JournalItem, in directory: URL, store: JournalStore, written: inout [UUID: String],
        missing: inout MissingImages
    ) async throws -> [UUID: String] {
        var paths: [UUID: String] = [:]
        for id in MarkdownAttachments.imageIDs(in: item.document.markdown) where !missing.contains(id) {
            if let path = written[id] {
                paths[id] = path
                continue
            }
            let data: Data
            do { data = try await store.attachment(id) } catch {
                if await store.hasAttachmentFile(id) {
                    missing.unreadable.insert(id)
                } else {
                    missing.notDownloaded.insert(id)
                }
                continue
            }
            guard let image = PortableImage(data) else {
                missing.unreadable.insert(id)
                continue
            }
            let attachments = directory.appendingPathComponent("attachments", isDirectory: true)
            try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
            let name = id.uuidString.lowercased() + "." + image.fileExtension
            try image.data.write(to: attachments.appendingPathComponent(name), options: writing)
            let path = "attachments/" + name
            written[id] = path
            paths[id] = path
        }
        return paths
    }

    /// The entry's Markdown with its images pointed at the exported files. An image whose reference can't be changed
    /// alone, such as a reference definition a link shares, keeps its link and is listed in `unlinked`.
    static func body(_ stored: String, paths: [UUID: String]) -> (text: String, unlinked: [UUID]) {
        if let all = try? MarkdownAttachments.rewrite(stored, paths: paths) { return (all, []) }
        var text = stored
        var unlinked: [UUID] = []
        for (id, path) in paths.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            if let one = try? MarkdownAttachments.rewrite(text, paths: [id: path]) {
                text = one
            } else {
                unlinked.append(id)
            }
        }
        return (text, unlinked)
    }

    /// The file's text: front matter, the title as a heading, then `body`.
    static func markdown(
        _ file: MarkdownExportPlan.File, folder: MarkdownExportPlan.Folder, body: String, timeZone: TimeZone
    ) -> String {
        let item = file.item
        var lines = ["---"]
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { lines.append("title: " + yamlString(title)) }
        if item.kind == "entry" { lines.append("date: " + timestamp(item.date, timeZone: timeZone)) }
        lines.append("modified: " + timestamp(item.modifiedAt, timeZone: timeZone))
        if item.kind == "entry", let journal = folder.journal {
            lines.append("journal: " + yamlString(journal.title))
            lines.append("journal_id: " + journal.id.uuidString.lowercased())
        }
        lines.append("id: " + item.id.uuidString.lowercased())
        if item.kind == "entry" && item.archivedAt != nil { lines.append("archived: true") }
        if file.pinned { lines.append("pinned: true") }
        if item.kind == "template" { lines.append("kind: template") }
        lines.append("---")
        var text = lines.joined(separator: "\n") + "\n"
        if !title.isEmpty { text += "\n# " + headingText(title) + "\n" }
        let normalized = body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text += "\n" + normalized
            if !normalized.hasSuffix("\n") { text += "\n" }
        }
        return text
    }

    /// A double-quoted YAML scalar.
    static func yamlString(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{2028}", "\u{2029}", "\u{85}":
                result += String(format: "\\u%04X", scalar.value)
            default:
                // YAML refuses control characters and noncharacters written as they are, but reads them escaped.
                let category = scalar.properties.generalCategory
                if category == .control || category == .unassigned || category == .surrogate {
                    result += String(format: scalar.value > 0xFFFF ? "\\U%08X" : "\\u%04X", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }

    /// A title as the text of an ATX heading: one line, with the characters that would format it escaped.
    static func headingText(_ title: String) -> String {
        let characters = Array(title.components(separatedBy: .newlines).joined(separator: " "))
        var result = ""
        for (index, character) in characters.enumerated() {
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            switch character {
            case "\\", "`", "*", "_", "[", "]", "<", ">", "#", "|", "~":
                result += "\\" + String(character)
            case "&" where next.map { $0.isLetter || $0 == "#" } == true:
                result += "\\&"
            case "!" where next == "[":
                result += "\\!"
            default:
                result.append(character)
            }
        }
        return result
    }

    static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func day(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// An image as other apps can show it: JPEG, PNG, GIF and WebP keep their bytes; HEIC, HEIF and TIFF, which most
/// Markdown apps can't show, become JPEG, or PNG when they have transparency, keeping orientation and metadata.
struct PortableImage {
    let data: Data
    let fileExtension: String

    private static let kept: [String: String] = [
        UTType.jpeg.identifier: "jpg", UTType.png.identifier: "png", UTType.gif.identifier: "gif",
        UTType.webP.identifier: "webp",
    ]

    init?(_ original: Data) {
        guard let source = CGImageSourceCreateWithData(original as CFData, nil),
            let type = CGImageSourceGetType(source) as String?, CGImageSourceGetCount(source) > 0
        else { return nil }
        if let fileExtension = Self.kept[type] {
            data = original
            self.fileExtension = fileExtension
            return
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let transparent = properties?[kCGImagePropertyHasAlpha] as? Bool ?? false
        let target = transparent ? UTType.png : UTType.jpeg
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(output, target.identifier as CFString, 1, nil)
        else { return nil }
        let options: [CFString: Any] = transparent ? [:] : [kCGImageDestinationLossyCompressionQuality: 0.9]
        CGImageDestinationAddImageFromSource(destination, source, 0, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        data = output as Data
        fileExtension = transparent ? "png" : "jpg"
    }
}
