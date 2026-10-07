import JournalCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let journalArchive = UTType(exportedAs: "org.privatejournal.archive", conformingTo: .package)
}

struct JournalFile: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .journalArchive] }
    let bytes: Data?
    let package: URL?
    /// The name a package is saved under. iPhone and iPad suggest the package's own name, not the default one.
    let filename: String?
    init(bytes: Data) {
        self.bytes = bytes
        package = nil
        filename = nil
    }
    init(package: URL, filename: String) {
        bytes = nil
        self.package = package
        self.filename = filename
    }
    init(configuration: ReadConfiguration) throws {
        bytes = configuration.file.regularFileContents
        package = nil
        filename = nil
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if let package {
            let wrapper = try FileWrapper(url: package, options: [])
            if let filename {
                wrapper.filename = filename
                wrapper.preferredFilename = filename
            }
            return wrapper
        }
        guard let bytes else { throw JournalError.invalidData }
        return FileWrapper(regularFileWithContents: bytes)
    }
    /// "Journal Archive 2026-09-27.journalarchive": the date tells backups apart, as in a screenshot's name.
    static func archiveFilename(on date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Journal Archive \(formatter.string(from: date)).journalarchive"
    }
}

struct SaveRecoveryKeyButton: View {
    let key: String
    @State private var exporting = false
    @State private var error: String?
    var body: some View {
        Button("Save Recovery Key…") { exporting = true }
            .fileExporter(
                isPresented: $exporting, document: JournalFile(bytes: Data((key + "\n").utf8)), contentType: .plainText,
                defaultFilename: "Journal Recovery Key.txt"
            ) { result in
                if case .failure = result { error = "Couldn’t save the key. Try again, or choose another location." }
            }
            .alert(
                "Couldn’t Save Recovery Key",
                isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
    }
}
