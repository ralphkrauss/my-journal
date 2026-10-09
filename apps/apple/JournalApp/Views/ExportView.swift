import JournalCore
import SwiftUI
import UniformTypeIdentifiers

/// What the save dialog writes: bytes in memory (a recovery key), or a staged item already on disk. An archive is a
/// staged regular file and a Markdown export a staged folder. The wrapper refers to the staged item, so a large
/// archive is never held in memory.
struct JournalFile: FileDocument {
    static var readableContentTypes: [UTType] { [.data] + ArchiveFileType.importTypes }
    let bytes: Data?
    let staged: URL?
    /// The name a staged item is saved under. iPhone and iPad suggest the item's own name, not the default one.
    let filename: String?
    init(bytes: Data) {
        self.bytes = bytes
        staged = nil
        filename = nil
    }
    init(staged: URL, filename: String) {
        bytes = nil
        self.staged = staged
        self.filename = filename
    }
    init(configuration: ReadConfiguration) throws {
        bytes = configuration.file.regularFileContents
        staged = nil
        filename = nil
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if let staged {
            let wrapper = try FileWrapper(url: staged, options: [])
            if let filename {
                wrapper.filename = filename
                wrapper.preferredFilename = filename
            }
            return wrapper
        }
        guard let bytes else { throw JournalError.invalidData }
        return FileWrapper(regularFileWithContents: bytes)
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
