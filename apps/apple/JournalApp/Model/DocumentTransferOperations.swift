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
    func prepareArchive() async throws -> URL {
        let session = vaultSessionID
        try validateVaultSession(session)
        guard let store, let configuration, let masterKey else { throw JournalError.locked }
        let destination = directory.appendingPathComponent("export-" + UUID().uuidString + ".journalarchive")
        var created = false
        do {
            let saved = await finishPendingSave()
            try validateVaultSession(session)
            guard saved else { throw JournalError.server("Save your changes before exporting an archive.") }
            try await VaultArchive.export(
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

/// One archive export at a time: prepares a package, hands it to the save dialog, and removes it once the dialog
/// closes. Presses while an archive is being prepared or the dialog is open do nothing.
@MainActor final class ArchiveExport: ObservableObject {
    static let progressDelay = Duration.milliseconds(300)
    static let saveFailure = "Couldn’t save the archive. Try again, or choose another location."
    /// Said when the device's authentication, asked for before an export, failed rather than was cancelled.
    static let verificationFailure = "Couldn’t verify it’s you. Try again."

    @Published private(set) var document: JournalFile?
    /// Shown only when preparing takes a noticeable time, so a small library doesn't flash a progress state.
    @Published private(set) var showsProgress = false
    @Published var error: String?
    /// Bound to the save dialog. A cancelled dialog doesn't report back, so its package is removed when the next
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
        let session = model.vaultSessionID
        operation = Task { await prepare(model, session: session) }
    }

    /// Waits until the current archive is prepared (or preparing stops).
    func finishPreparing() async {
        await operation?.value
    }

    /// The save dialog's result. Cancelling isn't a failure.
    func finish(_ result: Result<URL, Error>) {
        if case .failure(let failure) = result, (failure as? CocoaError)?.code != .userCancelled {
            error = Self.saveFailure
        }
        discard()
    }

    /// Stops preparing and closes the dialog, for example when the app locks.
    func cancel() {
        operation?.cancel()
        presenting = false
        discard()
    }

    /// Removes the prepared package and the save dialog's leftover copy of it.
    private func discard() {
        guard let document else { return }
        if let package = document.package { try? FileManager.default.removeItem(at: package) }
        if let filename = document.filename { removeDialogCopy(named: filename) }
        self.document = nil
    }

    static func message(for failure: Error) -> String {
        let code = (failure as NSError).code
        let domain = (failure as NSError).domain
        if case JournalError.server(let message) = failure { return message }
        if (domain == NSCocoaErrorDomain && code == NSFileWriteOutOfSpaceError)
            || (domain == NSPOSIXErrorDomain && code == Int(ENOSPC))
        {
            return "There isn’t enough space to export the archive. Free up space, then try again."
        }
        return "Couldn’t export the archive. Try again."
    }

    /// An archive of a library that isn't encrypted holds readable entries, images and earlier versions, and
    /// restoring needs no password, so with App Lock on the device's authentication comes first, as for Markdown
    /// (docs/design/build-18-fixes-2026-10-06.md §3.1). An encrypted archive needs the recovery credential instead.
    private func confirmOwner(_ model: AppModel) async -> Bool {
        guard model.appLockOn, model.configuration?.encrypted == false else { return true }
        switch await model.checkDeviceOwner(reason: "Export an archive of your journals") {
        case .approved: return true
        case .cancelled: return false
        case .failed:
            error = Self.verificationFailure
            return false
        }
    }

    private func prepare(_ model: AppModel, session: UUID) async {
        defer { operation = nil }
        guard await confirmOwner(model) else { return }
        let progress = Task { [weak self] in
            try? await Task.sleep(for: Self.progressDelay)
            if !Task.isCancelled { self?.showsProgress = true }
        }
        defer {
            progress.cancel()
            showsProgress = false
        }
        let filename = JournalFile.archiveFilename()
        do {
            try model.validateVaultSession(session)
            let url = try await model.prepareArchive()
            guard !Task.isCancelled, (try? model.validateVaultSession(session)) != nil else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            removeDialogCopy(named: filename)
            document = JournalFile(package: url, filename: filename)
            presenting = true
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), (try? model.validateVaultSession(session)) != nil
            else { return }
            self.error = Self.message(for: error)
        }
    }

    private func removeDialogCopy(named filename: String) {
        let copy = dialogFolder.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: copy.path) { try? FileManager.default.removeItem(at: copy) }
    }
}

/// Removes export copies left behind when the save dialog was cancelled or the app quit during an export: packages
/// named `export-<UUID>.journalarchive` and Markdown folders named `markdown-<UUID>` in the data folder, and the save
/// dialog's `Journal Archive <yyyy-MM-dd>.journalarchive` and `Journal Markdown <yyyy-MM-dd>` copies in the app's own
/// temporary folder. Nothing else is touched.
enum ArchiveExportLeftovers {
    @MainActor private static var removed = false
    /// Export as Markdown's folder while it is prepared (MarkdownExportOperations.swift).
    static let markdownPrefix = "markdown-"

    /// Once per launch, before any window can start an export.
    @MainActor static func removeAtLaunch(dataDirectory: URL) async {
        guard !removed else { return }
        removed = true
        let temporary = FileManager.default.temporaryDirectory
        await Task.detached(priority: .utility) {
            remove(dataDirectory: dataDirectory, temporaryDirectory: temporary)
        }.value
    }

    static func remove(dataDirectory: URL, temporaryDirectory: URL) {
        removePackages(in: dataDirectory, where: isStagedExport)
        removePackages(in: temporaryDirectory, where: isDialogCopy)
    }

    static func isStagedExport(_ name: String) -> Bool {
        if name.hasPrefix(markdownPrefix) {
            return UUID(uuidString: String(name.dropFirst(markdownPrefix.count))) != nil
        }
        guard name.hasPrefix("export-"), name.hasSuffix(".journalarchive") else { return false }
        let identifier = name.dropFirst("export-".count).dropLast(".journalarchive".count)
        return UUID(uuidString: String(identifier)) != nil
    }

    static func isDialogCopy(_ name: String) -> Bool {
        if name.hasPrefix("Journal Markdown ") {
            return isDate(name.dropFirst("Journal Markdown ".count))
        }
        guard name.hasPrefix("Journal Archive "), name.hasSuffix(".journalarchive") else { return false }
        return isDate(name.dropFirst("Journal Archive ".count).dropLast(".journalarchive".count))
    }

    private static func isDate(_ date: Substring) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(date)).map { formatter.string(from: $0) == date } ?? false
    }

    /// Only packages (folders) directly inside `folder` whose names match; never files, links or anything deeper.
    private static func removePackages(in folder: URL, where matches: (String) -> Bool) {
        let manager = FileManager.default
        guard
            let items = try? manager.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        else { return }
        for item in items where matches(item.lastPathComponent) {
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            try? manager.removeItem(at: item)
        }
    }
}
