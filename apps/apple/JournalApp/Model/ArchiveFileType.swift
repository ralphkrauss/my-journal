import Foundation
import UniformTypeIdentifiers

/// The archive's file types, in one place in code. The same identifiers and extensions are declared in `project.yml`
/// (`targetTemplates.ArchiveFileType`, which both apps use). A change to any of them is a change to a public contract:
/// installed apps and every archive already saved depend on them (docs/architecture.md, Compatibility rules).
///
/// There are two types (docs/design/1-1-archive-v2.md, 6.2, rung (c)):
/// - the **archive file**, `org.privatejournal.archive.file` with the extension `journalbackup`, which 1.1 writes. It
///   conforms to `public.data`: Files greys out a regular file typed as a package in the import picker;
/// - the **archive package**, `org.privatejournal.archive` with the extension `journalarchive`, which is what 1.0
///   saved (a folder). It stays declared so those archives still import and open from Files and the Finder.
///
/// Import accepts both, and the archive code tells a file from a folder by what the picked item is, never by name.
enum ArchiveFileType {
    /// The type identifier of the archive file, declared by the app (`UTExportedTypeDeclarations`).
    static let fileIdentifier = "org.privatejournal.archive.file"
    /// The extension of a saved archive file, in lower case and without a dot.
    static let filenameExtension = "journalbackup"
    /// The type identifier of the 1.0 archive folder, still declared.
    static let packageIdentifier = "org.privatejournal.archive"
    /// The extension of a 1.0 archive folder.
    static let packageExtension = "journalarchive"

    /// What the save dialog is given. Declared in the Info.plist as data; `conformingTo` only matters if the declaration
    /// is missing.
    static let archiveFile = UTType(exportedAs: fileIdentifier, conformingTo: .data)
    /// Declared in the Info.plist as a package, because 1.0 saved a folder.
    static let archivePackage = UTType(exportedAs: packageIdentifier, conformingTo: .package)
    /// Every type a picker offers as an archive.
    static var importTypes: [UTType] { [archiveFile, archivePackage] }

    /// Every extension that names an archive, for the system's open requests and the launch cleaner.
    static let extensions = [filenameExtension, packageExtension]

    /// Whether `url` names an archive by its extension, for the system's open requests. The archive code itself
    /// never decides by extension.
    static func isArchive(_ url: URL) -> Bool {
        url.isFileURL && extensions.contains(url.pathExtension.lowercased())
    }

    /// "Journal Archive 2026-09-27.journalbackup": the date tells backups apart, as in a screenshot's name.
    static func filename(on date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Journal Archive \(formatter.string(from: date)).\(filenameExtension)"
    }

    /// The staged export in the data folder: `export-<UUID>.journalbackup`.
    static func stagedFilename(_ identifier: UUID = UUID()) -> String {
        "export-\(identifier.uuidString).\(filenameExtension)"
    }

    /// The extension at the end of `name` that names an archive, if any, with its dot.
    static func archiveSuffix(of name: String) -> String? {
        extensions.map { "." + $0 }.first { name.hasSuffix($0) }
    }
}
