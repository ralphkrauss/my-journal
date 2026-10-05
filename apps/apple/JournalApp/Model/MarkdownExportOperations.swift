import Foundation
import JournalCore

/// Export as Markdown (docs/design/client-only-mac-lists-markdown-2026-10-05.md §3).
extension AppModel {
    /// Writes the library as Markdown into a new `markdown-<UUID>` folder in the data folder, excluded from backups,
    /// for the save dialog to copy. Removes it if anything fails or the journals lock meanwhile.
    func prepareMarkdownExport() async throws -> (folder: URL, summary: MarkdownExportSummary) {
        let session = vaultSessionID
        try validateVaultSession(session)
        guard let store else { throw JournalError.locked }
        let destination = directory.appendingPathComponent(
            ArchiveExportLeftovers.markdownPrefix + UUID().uuidString.lowercased(), isDirectory: true)
        do {
            let saved = await finishPendingSave()
            try validateVaultSession(session)
            guard saved else { throw JournalError.server("Save your changes before exporting your journals.") }
            let summary = try await MarkdownExport.write(store: store, to: destination)
            var excluded = URLResourceValues()
            excluded.isExcludedFromBackup = true
            var folder = destination
            try folder.setResourceValues(excluded)
            try validateVaultSession(session)
            return (destination, summary)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            try validateVaultSession(session)
            throw error
        }
    }

    /// The reason the device's authentication gives before journals leave the app as readable files.
    var markdownExportReason: String {
        configuration?.encrypted == false
            ? "Export your journals as Markdown files" : "Export your journals as files that aren’t encrypted"
    }
}

/// One Markdown export at a time, as `ArchiveExport` does for archives: asks for the device's authentication when
/// App Lock is on, prepares the folder, hands it to the save dialog, and removes it once the dialog closes.
@MainActor final class MarkdownExportController: ObservableObject {
    static let saveFailure = "Couldn’t save the files. Try again, or choose another location."

    @Published private(set) var document: JournalFile?
    /// Shown only when preparing takes a noticeable time.
    @Published private(set) var showsProgress = false
    @Published var error: String?
    /// What the saved folder left out, shown under the button after saving.
    @Published private(set) var note: String?
    @Published var presenting = false
    private var operation: Task<Void, Never>?
    private var summary: MarkdownExportSummary?
    /// Where the system save dialog writes its copy under the suggested name (see `ArchiveExport`).
    private let dialogFolder: URL

    init(dialogFolder: URL = FileManager.default.temporaryDirectory) {
        self.dialogFolder = dialogFolder
    }

    var busy: Bool { operation != nil || presenting }

    func start(with model: AppModel) {
        guard !busy else { return }
        discard()
        error = nil
        note = nil
        let session = model.vaultSessionID
        operation = Task { await run(model, session: session) }
    }

    /// The save dialog's result. Cancelling isn't a failure.
    func finish(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            note = summary.flatMap(Self.note)
        case .failure(let failure):
            if (failure as? CocoaError)?.code != .userCancelled { error = Self.saveFailure }
        }
        discard()
    }

    /// Stops preparing and closes the dialog, for example when the app locks.
    func cancel() {
        operation?.cancel()
        presenting = false
        discard()
    }

    private func discard() {
        summary = nil
        guard let document else { return }
        if let package = document.package { try? FileManager.default.removeItem(at: package) }
        if let filename = document.filename { removeDialogCopy(named: filename) }
        self.document = nil
    }

    private func run(_ model: AppModel, session: UUID) async {
        defer { operation = nil }
        if model.appLockOn {
            guard await model.authenticateDeviceOwner(reason: model.markdownExportReason) else { return }
        }
        let progress = Task { [weak self] in
            try? await Task.sleep(for: ArchiveExport.progressDelay)
            if !Task.isCancelled { self?.showsProgress = true }
        }
        defer {
            progress.cancel()
            showsProgress = false
        }
        let filename = MarkdownExport.folderName()
        do {
            try model.validateVaultSession(session)
            let (folder, summary) = try await model.prepareMarkdownExport()
            guard !Task.isCancelled, (try? model.validateVaultSession(session)) != nil else {
                try? FileManager.default.removeItem(at: folder)
                return
            }
            removeDialogCopy(named: filename)
            self.summary = summary
            document = JournalFile(package: folder, filename: filename)
            presenting = true
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), (try? model.validateVaultSession(session)) != nil
            else { return }
            self.error = Self.message(for: error)
        }
    }

    static func message(for failure: Error) -> String {
        let code = (failure as NSError).code
        let domain = (failure as NSError).domain
        if case JournalError.server(let message) = failure { return message }
        if (domain == NSCocoaErrorDomain && code == NSFileWriteOutOfSpaceError)
            || (domain == NSPOSIXErrorDomain && code == Int(ENOSPC))
        {
            return "There isn’t enough space to export your journals. Free up space, then try again."
        }
        return "Couldn’t export your journals. Try again."
    }

    /// What was left out and what to do about it, or nil when everything was included.
    static func note(_ summary: MarkdownExportSummary) -> String? {
        var sentences: [String] = []
        if summary.imagesNotDownloaded > 0 {
            sentences.append(
                summary.imagesNotDownloaded == 1
                    ? "1 image wasn’t included because it hasn’t downloaded yet. Export again after syncing."
                    : "\(summary.imagesNotDownloaded) images weren’t included because they haven’t downloaded yet. Export again after syncing."
            )
        }
        if summary.imagesUnreadable > 0 {
            sentences.append(
                summary.imagesUnreadable == 1
                    ? "1 image wasn’t included because it couldn’t be read."
                    : "\(summary.imagesUnreadable) images weren’t included because they couldn’t be read.")
        }
        if summary.itemsUnreadable > 0 {
            sentences.append(
                summary.itemsUnreadable == 1
                    ? "1 entry wasn’t included because it was made with a newer version of My Journal. Update My Journal, then export again."
                    : "\(summary.itemsUnreadable) entries weren’t included because they were made with a newer version of My Journal. Update My Journal, then export again."
            )
        }
        if summary.itemsWithOtherVersions > 0 {
            sentences.append(
                summary.itemsWithOtherVersions == 1
                    ? "1 entry has another version that wasn’t included. Choose a version, then export again."
                    : "\(summary.itemsWithOtherVersions) entries have another version that wasn’t included. Choose a version for each, then export again."
            )
        }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    private func removeDialogCopy(named filename: String) {
        let copy = dialogFolder.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: copy.path) { try? FileManager.default.removeItem(at: copy) }
    }
}
