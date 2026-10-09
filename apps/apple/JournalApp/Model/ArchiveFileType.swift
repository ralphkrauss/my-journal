import Foundation
import UniformTypeIdentifiers

/// The archive's file type, in one place in code. The same identifier and extension are declared in `project.yml`
/// (`targetTemplates.ArchiveFileType`, which both apps use). A change to either is a change to a public contract:
/// installed 1.0 apps and every archive already saved depend on them (docs/architecture.md, Compatibility rules).
///
/// The 1.0 archive was a folder ending in `.journalarchive`, and 1.1 saves one regular file under the same extension
/// (docs/design/1-1-archive-v2.md, 6.2, rung (a)). Import accepts both: the archive code tells them apart by what the
/// picked item is, never by name.
enum ArchiveFileType {
    /// The type identifier declared by the app (`UTExportedTypeDeclarations`).
    static let identifier = "org.privatejournal.archive"
    /// The extension of a saved archive, in lower case and without a dot.
    static let filenameExtension = "journalarchive"

    /// Declared in the Info.plist as a package, because 1.0 saved a folder. `conformingTo` only matters if the
    /// declaration is missing.
    static let journalArchive = UTType(exportedAs: identifier, conformingTo: .package)
    /// Every type a picker offers as an archive. A second type, if the file type decision adds one, goes here.
    static var importTypes: [UTType] { [journalArchive] }

    /// Whether `url` names an archive by its extension, for the system's open requests. The archive code itself
    /// never decides by extension.
    static func isArchive(_ url: URL) -> Bool {
        url.isFileURL && url.pathExtension.lowercased() == filenameExtension
    }

    /// "Journal Archive 2026-09-27.journalarchive": the date tells backups apart, as in a screenshot's name.
    static func filename(on date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Journal Archive \(formatter.string(from: date)).\(filenameExtension)"
    }

    /// The staged export in the data folder: `export-<UUID>.journalarchive`.
    static func stagedFilename(_ identifier: UUID = UUID()) -> String {
        "export-\(identifier.uuidString).\(filenameExtension)"
    }
}
