import Combine
import Foundation
import JournalCore

extension AppModel {
    func validateVaultSession(_ session: UUID) throws {
        try Task.checkCancellation()
        // The lock screen of a missing device key offers Import Archive….
        guard session == vaultSessionID, !locked || libraryProblem == .needsKey, !replacingVault else {
            throw CancellationError()
        }
    }
}

extension AppModel {
    func inspectArchive(_ source: URL, phrase: String) async throws -> VaultArchive.Restored {
        let session = vaultSessionID
        try validateVaultSession(session)
        let destination = directory.appendingPathComponent("import-" + UUID().uuidString.lowercased())
        var restored: VaultArchive.Restored?
        do {
            let result = try await VaultArchive.restore(from: source, to: destination, phrase: phrase)
            restored = result
            try validateVaultSession(session)
            return result
        } catch {
            if let restored { await discardImportedCopy(restored) }
            try validateVaultSession(session)
            throw error
        }
    }

}

extension AppModel {
    func discardImportedCopy(_ restored: VaultArchive.Restored) async {
        let path = await restored.store.directory
        // Compare filesystem locations, not URL directory hints (a trailing slash changes URL equality).
        guard
            path.deletingLastPathComponent().resolvingSymlinksInPath().path == directory.resolvingSymlinksInPath().path,
            path.lastPathComponent.hasPrefix("import-"), configuration?.storageFolder != path.lastPathComponent
        else { return }
        try? await restored.store.close()
        try? FileManager.default.removeItem(at: path)
    }
}

extension AppModel {
    /// `messages.export.archiveSaved`: after an archive was saved, the password it needs.
    var archiveSavedMessage: String? {
        guard let configuration else { return nil }
        return "Archive saved. Keep your \(configuration.credentialName.lowercased()) with it."
    }

    func prepareArchive() async throws -> URL {
        let session = vaultSessionID
        try validateVaultSession(session)
        guard let store, let configuration, let masterKey else { throw JournalError.locked }
        let destination = directory.appendingPathComponent(ArchiveFileType.stagedFilename())
        var created = false
        do {
            let saved = await finishPendingSave()
            try validateVaultSession(session)
            guard saved else { throw JournalError.saveRequired }
            // The writer removes what it created when it fails; only a finished archive is this function's to remove.
            try await VaultArchive.exportFile(
                store: store, recovery: configuration.recovery, key: masterKey, to: destination)
            created = true
            try validateVaultSession(session)
            return destination
        } catch {
            if created { try? FileManager.default.removeItem(at: destination) }
            try validateVaultSession(session)
            throw error
        }
    }
}

/// One archive export at a time: prepares an archive file, hands it to the save dialog, and removes it once the dialog
/// closes. Presses while an archive is being prepared or the dialog is open do nothing.
@MainActor final class ArchiveExport: ObservableObject {
    static let progressDelay = Duration.milliseconds(300)
    static let saveFailure = "Couldn’t save the archive. Try again, or choose another location."
    static let noSpace = "There isn’t enough space to export the archive. Free up space, then try again."
    /// Said when the device's authentication, asked for before an export, failed rather than was cancelled.
    static let verificationFailure = "Couldn’t verify it’s you. Try again."

    @Published private(set) var document: JournalFile?
    /// Shown only when preparing takes a noticeable time, so a small library doesn't flash a progress state.
    @Published private(set) var showsProgress = false
    @Published var error: String?
    /// The save dialog saved the archive; the Export row says to keep the password with it until the next export.
    @Published private(set) var saved = false
    /// Bound to the save dialog. A cancelled dialog doesn't report back, so its staged file is removed when the next
    /// export starts or the controls go away, never while the dialog may still be writing it.
    @Published var presenting = false
    private var operation: Task<Void, Never>?
    /// Where the system save dialog writes its copy of the document under the suggested name. iPhone and iPad keep
    /// that copy when the dialog is cancelled, and the next export with the same name then fails.
    private let dialogFolder: URL

    init(dialogFolder: URL = FileManager.default.temporaryDirectory) {
        self.dialogFolder = dialogFolder
    }

    var busy: Bool { operation != nil || presenting }

    func start(with model: AppModel) {
        guard !busy else { return }
        discard()
        error = nil
        saved = false
        let session = model.vaultSessionID
        operation = Task { await prepare(model, session: session) }
    }

    /// Waits until the current archive is prepared (or preparing stops).
    func finishPreparing() async {
        await operation?.value
    }

    /// The save dialog's result. Cancelling isn't a failure.
    func finish(_ result: Result<URL, Error>) {
        switch result {
        case .success: saved = true
        case .failure(let failure):
            if (failure as? CocoaError)?.code != .userCancelled {
                error = Self.isOutOfSpace(failure) ? Self.noSpace : Self.saveFailure
            }
        }
        discard()
    }

    /// Stops preparing and closes the dialog, for example when the app locks.
    func cancel() {
        operation?.cancel()
        presenting = false
        discard()
    }

    /// Removes the staged archive and the save dialog's leftover copy of it.
    private func discard() {
        guard let document else { return }
        if let staged = document.staged { try? FileManager.default.removeItem(at: staged) }
        if let filename = document.filename { removeDialogCopy(named: filename) }
        self.document = nil
    }

    /// Whether a failure says the volume is full: the writer's own check (`ArchiveError.notEnoughSpace`, before
    /// anything is written) or the system running out of room while writing or while the save dialog copies the file.
    static func isOutOfSpace(_ failure: Error) -> Bool {
        if (failure as? ArchiveError) == .notEnoughSpace { return true }
        let code = (failure as NSError).code
        let domain = (failure as NSError).domain
        return (domain == NSCocoaErrorDomain && code == NSFileWriteOutOfSpaceError)
            || (domain == NSPOSIXErrorDomain && code == Int(ENOSPC))
    }

    static func message(for failure: Error) -> String {
        if case JournalError.server(let message) = failure { return message }
        if isOutOfSpace(failure) { return noSpace }
        return "Couldn’t export the archive. Try again."
    }

    private func prepare(_ model: AppModel, session: UUID) async {
        defer { operation = nil }
        let progress = Task { [weak self] in
            try? await Task.sleep(for: Self.progressDelay)
            if !Task.isCancelled { self?.showsProgress = true }
        }
        defer {
            progress.cancel()
            showsProgress = false
        }
        let filename = ArchiveFileType.filename()
        do {
            try model.validateVaultSession(session)
            let url = try await model.prepareArchive()
            guard !Task.isCancelled, (try? model.validateVaultSession(session)) != nil
            else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            removeDialogCopy(named: filename)
            document = JournalFile(staged: url, filename: filename)
            presenting = true
        } catch {
            guard !Task.isCancelled, !(error is CancellationError),
                (try? model.validateVaultSession(session)) != nil
            else { return }
            self.error = Self.message(for: error)
        }
    }

    private func removeDialogCopy(named filename: String) {
        let copy = dialogFolder.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: copy.path) { try? FileManager.default.removeItem(at: copy) }
    }
}

/// Removes what an export or a restore left behind when the save dialog was cancelled or the app quit meanwhile:
/// - in the data folder, the staged archive `export-<UUID>.journalbackup` (a file; a `.journalarchive` folder, from 1.0), Markdown
///   folders named `markdown-<UUID>`, and, when the library folders are known, a restore's staging folder
///   `import-<UUID>` that no configuration names;
/// - in the app's own temporary folder, the save dialog's `Journal Archive <yyyy-MM-dd>.journalbackup` (a file; a
///   `.journalarchive` folder, from 1.0) and `Journal Markdown <yyyy-MM-dd>` copies, and the export's database copy `export-<UUID>.sqlite`.
/// Links are never followed or removed, and nothing else is touched.
enum ArchiveExportLeftovers {
    @MainActor private static var removed = false
    /// Export as Markdown's folder while it is prepared (MarkdownExportOperations.swift).
    static let markdownPrefix = "markdown-"
    /// A restore or import extracts here (`AppModel.inspectArchive`). It becomes the library's folder when the archive is
    /// installed, so a folder a configuration names is never leftover.
    static let restoreStagingPrefix = "import-"

    private enum Kind { case folder, file }

    /// Once per launch, before any window can start an export. `libraryFolders` are the folders of the data folder that
    /// belong to a library (`AppModel.libraryFolderNames`); nil while that can't be told, which leaves restore staging
    /// alone.
    @MainActor static func removeAtLaunch(dataDirectory: URL, libraryFolders: Set<String>?) async {
        guard !removed else { return }
        removed = true
        let temporary = FileManager.default.temporaryDirectory
        await Task.detached(priority: .utility) {
            remove(dataDirectory: dataDirectory, temporaryDirectory: temporary, libraryFolders: libraryFolders)
        }.value
    }

    static func remove(dataDirectory: URL, temporaryDirectory: URL, libraryFolders: Set<String>? = nil) {
        removeItems(in: dataDirectory, of: .folder, where: isStagedExport)
        removeItems(in: dataDirectory, of: .file, where: isStagedArchive)
        removeItems(in: temporaryDirectory, of: .folder, where: isDialogCopy)
        removeItems(in: temporaryDirectory, of: .file) { isDialogArchive($0) || isSnapshotDatabase($0) }
        if let libraryFolders {
            removeItems(in: dataDirectory, of: .folder) { isRestoreStaging($0) && !libraryFolders.contains($0) }
        }
    }

    static func isStagedExport(_ name: String) -> Bool {
        if name.hasPrefix(markdownPrefix) {
            return UUID(uuidString: String(name.dropFirst(markdownPrefix.count))) != nil
        }
        return isStagedArchive(name)
    }

    static func isStagedArchive(_ name: String) -> Bool {
        guard name.hasPrefix("export-"), let suffix = ArchiveFileType.archiveSuffix(of: name) else { return false }
        let identifier = name.dropFirst("export-".count).dropLast(suffix.count)
        return UUID(uuidString: String(identifier)) != nil
    }

    static func isDialogCopy(_ name: String) -> Bool {
        if name.hasPrefix("Journal Markdown ") {
            return isDate(name.dropFirst("Journal Markdown ".count))
        }
        return isDialogArchive(name)
    }

    static func isDialogArchive(_ name: String) -> Bool {
        guard name.hasPrefix("Journal Archive "), let suffix = ArchiveFileType.archiveSuffix(of: name) else {
            return false
        }
        return isDate(name.dropFirst("Journal Archive ".count).dropLast(suffix.count))
    }

    /// The copy of the database an archive export makes in the temporary folder (`FileArchive.export`).
    static func isSnapshotDatabase(_ name: String) -> Bool {
        guard name.hasPrefix("export-"), name.hasSuffix(".sqlite") else { return false }
        return UUID(uuidString: String(name.dropFirst("export-".count).dropLast(".sqlite".count))) != nil
    }

    static func isRestoreStaging(_ name: String) -> Bool {
        name.hasPrefix(restoreStagingPrefix)
            && UUID(uuidString: String(name.dropFirst(restoreStagingPrefix.count))) != nil
    }

    private static func isDate(_ date: Substring) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(date)).map { formatter.string(from: $0) == date } ?? false
    }

    /// Only items of one kind directly inside `folder` whose names match; never links or anything deeper.
    private static func removeItems(in folder: URL, of kind: Kind, where matches: (String) -> Bool) {
        let manager = FileManager.default
        guard
            let items = try? manager.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        else { return }
        for item in items where matches(item.lastPathComponent) {
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isSymbolicLink != true else { continue }
            switch kind {
            case .folder: guard values?.isDirectory == true else { continue }
            case .file: guard values?.isRegularFile == true else { continue }
            }
            try? manager.removeItem(at: item)
        }
    }
}

extension AppModel {
    /// The folders of the data folder that a library the configuration names uses: the current one and the earlier
    /// libraries waiting to be removed. nil while the settings can't be read, because then no folder can be called
    /// leftover.
    var libraryFolderNames: Set<String>? {
        guard libraryProblem != .settingsUnread else { return nil }
        guard let configuration else { return [] }
        var names = Set<String>()
        if let folder = configuration.storageFolder { names.insert(folder) }
        for library in configuration.supersededLibraries ?? [] {
            if let folder = library.storageFolder { names.insert(folder) }
        }
        return names
    }
}
