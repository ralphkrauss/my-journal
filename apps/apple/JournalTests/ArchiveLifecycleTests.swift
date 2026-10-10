import CryptoKit
import JournalCore
import SwiftUI
import XCTest

@testable import Journal

@MainActor
final class ArchiveLifecycleTests: XCTestCase {
    func testAdditiveImportFlushesDraftAndPreservesDestinationRecoveryAndLockSettings() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = AppModel(directory: root.appendingPathComponent("source"))
        let destination = AppModel(directory: root.appendingPathComponent("destination"))
        addTeardownBlock { @MainActor in
            for model in [source, destination] {
                let originalAccount =
                    "master-"
                    + SHA256.hash(data: Data(model.directory.path.utf8))
                    .map { String(format: "%02x", $0) }.joined()
                try? Keychain.remove(originalAccount)
                if let account = model.configuration?.keyID { try? Keychain.remove(account) }
            }
            try? FileManager.default.removeItem(at: root)
        }
        addTeardownBlock { @MainActor in
            _ = await source.finishPendingSave()
            _ = await destination.finishPendingSave()
            try await source.store?.close()
            try await destination.store?.close()
        }
        await source.start()
        let phrase = AppModel.testPassword
        source.confirmRecovery()
        let archive = try await source.prepareArchive()
        await destination.start()
        destination.confirmRecovery()
        await destination.turnOnAppLockForTesting()
        let original = try XCTUnwrap(destination.configuration)
        await destination.newEntry()
        var draft = try XCTUnwrap(destination.draft)
        draft.title = "Last edit before import"
        destination.updateDraft(draft)
        let restored = try await destination.inspectArchive(archive, phrase: phrase)
        try await destination.installArchive(restored)
        let inspectionPath = await restored.store.directory
        await destination.discardImportedCopy(restored)
        XCTAssertFalse(FileManager.default.fileExists(atPath: inspectionPath.path))
        XCTAssertEqual(destination.configuration?.appLock, true, "Importing keeps App Lock on.")
        XCTAssertEqual(destination.configuration?.connectionKeyID, original.connectionKeyID)
        XCTAssertEqual(
            try JournalCoding.encoder().encode(destination.configuration?.recovery),
            try JournalCoding.encoder().encode(original.recovery))
        XCTAssertEqual(destination.journals.count, 2)
        XCTAssertEqual(destination.items.first { $0.id == draft.id }?.title, draft.title)
        let reopened = AppModel(directory: destination.directory)
        addTeardownBlock { @MainActor in
            _ = await reopened.finishPendingSave()
            try await reopened.store?.close()
        }
        await reopened.load()
        XCTAssertTrue(reopened.locked)
        await reopened.unlockForTesting()
        XCTAssertFalse(reopened.locked)
        XCTAssertEqual(reopened.items.first { $0.id == draft.id }?.title, draft.title)
    }
    func testFailedArchiveCommitKeepsCurrentVaultAndRemovesOnlyItsStaging() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = AppModel(directory: root.appendingPathComponent("source"))
        let destination = AppModel(directory: root.appendingPathComponent("destination"))
        addTeardownBlock { @MainActor in
            for model in [source, destination] {
                let account =
                    "master-"
                    + SHA256.hash(data: Data(model.directory.path.utf8))
                    .map { String(format: "%02x", $0) }.joined()
                try? Keychain.remove(account)
                if let current = model.configuration?.keyID { try? Keychain.remove(current) }
            }
            try? FileManager.default.removeItem(at: root)
        }
        addTeardownBlock { @MainActor in
            _ = await source.finishPendingSave()
            _ = await destination.finishPendingSave()
            try await source.store?.close()
            try await destination.store?.close()
        }
        await source.start()
        let phrase = AppModel.testPassword
        source.confirmRecovery()
        let sourceStore = try XCTUnwrap(source.store)
        let journalID = try XCTUnwrap(source.journals.first?.id)
        let live = JournalItem(kind: "entry", journalID: journalID, title: "Live entry")
        var deleted = JournalItem(kind: "entry", journalID: journalID, title: "Deleted entry")
        deleted.deletedAt = Date()
        let missing = JournalItem(kind: "entry", journalID: UUID(), title: "Missing journal")
        for item in [live, deleted, missing] { try await sourceStore.save(item) }
        let archive = try await source.prepareArchive()
        await destination.start()
        destination.confirmRecovery()
        await destination.newEntry()
        let original = try XCTUnwrap(destination.configuration)
        let oldIDs = Set(destination.items.map(\.id))
        var draft = try XCTUnwrap(destination.draft)
        draft.title = "Keep the final draft"
        destination.updateDraft(draft)
        let restored = try await destination.inspectArchive(archive, phrase: phrase)
        let summary = ArchiveSummary(snapshot: try await restored.store.lifecycleSnapshot())
        XCTAssertEqual(summary.entries, 1)
        XCTAssertEqual(summary.recentlyDeleted, 1)
        XCTAssertEqual(summary.unavailable, 1)
        await capturePreview(summary)
        let sourcePath = await restored.store.directory
        let keep = destination.directory.appendingPathComponent("vault-unrelated")
        try FileManager.default.createDirectory(at: keep, withIntermediateDirectories: true)
        let marker = Data("Keep unrelated files".utf8)
        try marker.write(to: keep.appendingPathComponent("marker"))
        let configURL = destination.directory.appendingPathComponent("configuration.json")
        let configBackup = destination.directory.appendingPathComponent("configuration.saved.json")
        try FileManager.default.moveItem(at: configURL, to: configBackup)
        try FileManager.default.createDirectory(at: configURL, withIntermediateDirectories: false)
        do {
            try await destination.installArchive(restored)
            XCTFail("A failed configuration write must not install the staged vault.")
        } catch {}
        XCTAssertEqual(destination.configuration?.storageFolder, original.storageFolder)
        XCTAssertEqual(destination.configuration?.keyID, original.keyID)
        XCTAssertFalse(destination.replacingVault)
        XCTAssertEqual(destination.draft?.id, draft.id)
        XCTAssertEqual(destination.draft?.title, draft.title)
        let currentStore = try XCTUnwrap(destination.store)
        let currentItems = try await currentStore.items()
        XCTAssertEqual(Set(currentItems.map(\.id)), oldIDs)
        XCTAssertEqual(currentItems.first { $0.id == draft.id }?.title, draft.title)
        let folders = try FileManager.default.contentsOfDirectory(
            at: destination.directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(
            Set(folders.map(\.lastPathComponent).filter { $0.hasPrefix("vault-") }),
            Set([keep.lastPathComponent, try XCTUnwrap(original.storageFolder)]))
        XCTAssertEqual(try Data(contentsOf: keep.appendingPathComponent("marker")), marker)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourcePath.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
        try FileManager.default.removeItem(at: configURL)
        try FileManager.default.moveItem(at: configBackup, to: configURL)
        try await destination.installArchive(restored)
        XCTAssertEqual(destination.journals.count, 2)
        await destination.discardImportedCopy(restored)
        let reopened = AppModel(directory: destination.directory)
        addTeardownBlock { @MainActor in
            _ = await reopened.finishPendingSave()
            try await reopened.store?.close()
        }
        await reopened.load()
        XCTAssertEqual(reopened.journals.count, 2)
        XCTAssertEqual(reopened.items.first { $0.id == draft.id }?.title, draft.title)
    }

    /// A double click, or a press before the save dialog appears, must not prepare a second archive or reach the
    /// dialog's copy with the same name. A cancelled dialog must not leave either copy behind to break the next export.
    func testRepeatedExportPressesPrepareOneArchiveAndACancelledDialogDoesNotBreakTheNext() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(directory: root.appendingPathComponent("library"))
        let dialogFolder = root.appendingPathComponent("dialog")
        addTeardownBlock { @MainActor in
            let account =
                "master-"
                + SHA256.hash(data: Data(model.directory.path.utf8)).map { String(format: "%02x", $0) }.joined()
            try? Keychain.remove(account)
            if let current = model.configuration?.keyID { try? Keychain.remove(current) }
            _ = await model.finishPendingSave()
            try await model.store?.close()
            try? FileManager.default.removeItem(at: root)
        }
        await model.start()
        model.confirmRecovery()
        // What iPhone and iPad leave behind when an earlier dialog was cancelled.
        let leftover = dialogFolder.appendingPathComponent(ArchiveFileType.filename())
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        let packages = {
            try FileManager.default.contentsOfDirectory(atPath: model.directory.path).filter {
                $0.hasPrefix("export-")
            }
        }
        let export = ArchiveExport(dialogFolder: dialogFolder)
        export.start(with: model)
        export.start(with: model)
        await export.finishPreparing()
        export.start(with: model)
        await export.finishPreparing()

        XCTAssertTrue(export.presenting)
        XCTAssertNil(export.error)
        let package = try XCTUnwrap(export.document?.staged)
        XCTAssertEqual(try packages(), [package.lastPathComponent])
        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path))

        // The dialog is cancelled without reporting back, then Export Archive… is pressed again.
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        export.presenting = false
        export.start(with: model)
        await export.finishPreparing()
        XCTAssertTrue(export.presenting)
        XCTAssertNil(export.error)
        XCTAssertEqual(try packages(), [try XCTUnwrap(export.document?.staged?.lastPathComponent)])
        XCTAssertNotEqual(export.document?.staged, package)
        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path))

        let systemFailure = CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: leftover.path])
        export.finish(.failure(systemFailure))
        export.presenting = false
        XCTAssertEqual(export.error, ArchiveExport.saveFailure)
        XCTAssertEqual(try packages(), [])
    }

    private func libraryWithAppLock(appLock: Bool) async throws -> (
        model: AppModel, owner: TestDeviceOwner, export: ArchiveExport
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(directory: root.appendingPathComponent("library"))
        addTeardownBlock { @MainActor in
            for account in [model.configuration?.keyID, model.configuration?.connectionKeyID].compactMap({ $0 }) {
                try? Keychain.remove(account)
            }
            try await model.store?.close()
            try? FileManager.default.removeItem(at: root)
        }
        await model.start(password: "this device's own password")
        model.confirmRecovery()
        let owner = TestDeviceOwner()
        model.deviceOwner = owner
        model.applicationActive = true
        if appLock {
            let result = await model.setAppLock(true)
            XCTAssertEqual(result, .saved)
        }
        return (model, owner, ArchiveExport(dialogFolder: root.appendingPathComponent("dialog")))
    }

    /// An archive needs the recovery credential, and asks for no authentication whatever App Lock says.
    func testExportingNeedsNoAuthentication() async throws {
        for appLock in [true, false] {
            let (model, owner, export) = try await libraryWithAppLock(appLock: appLock)
            let before = owner.requests
            owner.outcome = .failed
            export.start(with: model)
            await export.finishPreparing()
            XCTAssertEqual(owner.requests, before, "App Lock: \(appLock)")
            XCTAssertTrue(export.presenting, "App Lock: \(appLock)")
            XCTAssertNil(export.error)
        }
    }

    /// Launch removes the archive copies earlier builds left behind, and nothing else in the same folders.
    func testLaunchCleanupRemovesOnlyLeftoverExportCopies() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let data = root.appendingPathComponent("library")
        let temporary = root.appendingPathComponent("tmp")
        let elsewhere = root.appendingPathComponent("elsewhere")
        let manager = FileManager.default
        func folder(_ url: URL) throws -> URL {
            try manager.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("contents".utf8).write(to: url.appendingPathComponent("archive.json"))
            return url
        }
        let leftovers = [
            try folder(data.appendingPathComponent("export-\(UUID().uuidString).journalarchive")),
            try folder(temporary.appendingPathComponent("Journal Archive 2026-09-30.journalarchive")),
            try folder(data.appendingPathComponent("export-\(UUID().uuidString).journalbackup")),
            try folder(temporary.appendingPathComponent("Journal Archive 2026-09-30.journalbackup")),
            // Export as Markdown's prepared folder and the save dialog's copy of it, which hold readable journals.
            try folder(data.appendingPathComponent("markdown-\(UUID().uuidString.lowercased())")),
            try folder(temporary.appendingPathComponent("Journal Markdown 2026-10-05")),
        ]
        let kept = [
            try folder(data.appendingPathComponent("vault-\(UUID().uuidString.lowercased())")),
            try folder(data.appendingPathComponent("import-\(UUID().uuidString.lowercased())")),
            try folder(data.appendingPathComponent("export-notes.journalarchive")),
            try folder(data.appendingPathComponent("Journal Archive 2026-09-30.journalarchive")),
            try folder(data.appendingPathComponent("vault-a/export-\(UUID().uuidString).journalarchive")),
            try folder(temporary.appendingPathComponent("Journal Archive 2026-09-30 2.journalarchive")),
            try folder(temporary.appendingPathComponent("Journal Archive 2026-13-45.journalarchive")),
            try folder(temporary.appendingPathComponent("export-\(UUID().uuidString).journalarchive")),
            try folder(elsewhere.appendingPathComponent("Journal Archive 2026-09-29.journalarchive")),
            try folder(data.appendingPathComponent("markdown-notes")),
            try folder(temporary.appendingPathComponent("Journal Markdown 2026-10-05 2")),
        ]
        let configuration = data.appendingPathComponent("configuration.json")
        try Data("{}".utf8).write(to: configuration)
        // A file archive is a file: the dialog's copy of it goes like a package from an earlier build.
        let file = temporary.appendingPathComponent("Journal Archive 2026-09-28.journalarchive")
        try Data("a file archive".utf8).write(to: file)
        let link = temporary.appendingPathComponent("Journal Archive 2026-09-29.journalarchive")
        try manager.createSymbolicLink(at: link, withDestinationURL: kept[kept.count - 1])

        ArchiveExportLeftovers.remove(dataDirectory: data, temporaryDirectory: temporary)

        for leftover in leftovers + [file] { XCTAssertFalse(manager.fileExists(atPath: leftover.path), leftover.path) }
        for item in kept + [configuration] { XCTAssertTrue(manager.fileExists(atPath: item.path), item.path) }
        XCTAssertNotNil(try? manager.destinationOfSymbolicLink(atPath: link.path))
        XCTAssertTrue(manager.fileExists(atPath: kept[kept.count - 1].appendingPathComponent("archive.json").path))
    }

    /// A file archive is a file: the staged export, the save dialog's copy and the export's database copy are files and
    /// go; so does a restore's staging folder left by an app that quit, unless a library uses it. Links and anything
    /// that merely looks similar stay.
    func testLaunchCleanupRemovesStagedArchiveFilesAndRestoreStagingButNotALibrary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let data = root.appendingPathComponent("library")
        let temporary = root.appendingPathComponent("tmp")
        let manager = FileManager.default
        try manager.createDirectory(at: data, withIntermediateDirectories: true)
        try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
        func file(_ url: URL) throws -> URL {
            try Data("archive bytes".utf8).write(to: url)
            return url
        }
        func folder(_ url: URL) throws -> URL {
            try manager.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("contents".utf8).write(to: url.appendingPathComponent("journal.sqlite"))
            return url
        }
        let current = "import-\(UUID().uuidString.lowercased())"
        let earlier = "import-\(UUID().uuidString.lowercased())"
        let leftovers = [
            try file(data.appendingPathComponent("export-\(UUID().uuidString).journalbackup")),
            try file(temporary.appendingPathComponent("Journal Archive 2026-09-30.journalbackup")),
            // Files an earlier build of 1.1 staged under the extension of the 1.0 folder.
            try file(data.appendingPathComponent("export-\(UUID().uuidString).journalarchive")),
            try file(temporary.appendingPathComponent("Journal Archive 2026-09-27.journalarchive")),
            try file(temporary.appendingPathComponent("export-\(UUID().uuidString.lowercased()).sqlite")),
            try folder(data.appendingPathComponent("import-\(UUID().uuidString.lowercased())")),
        ]
        let kept = [
            try folder(data.appendingPathComponent(current)),
            try folder(data.appendingPathComponent(earlier)),
            try folder(data.appendingPathComponent("vault-\(UUID().uuidString.lowercased())")),
            try folder(data.appendingPathComponent("import-notes")),
            try file(data.appendingPathComponent("import-\(UUID().uuidString.lowercased())-file")),
            try file(data.appendingPathComponent("export-notes.journalbackup")),
            try file(data.appendingPathComponent("Journal Archive 2026-09-30.journalbackup")),
            try file(temporary.appendingPathComponent("Journal Archive 2026-09-30 2.journalbackup")),
            try file(temporary.appendingPathComponent("export-\(UUID().uuidString).journalbackup")),
            try file(data.appendingPathComponent("export-\(UUID().uuidString).journalbackup.zip")),
            try file(temporary.appendingPathComponent("export-notes.sqlite")),
        ]
        let elsewhere = try folder(root.appendingPathComponent("elsewhere"))
        let stagedLink = data.appendingPathComponent("import-\(UUID().uuidString.lowercased())")
        try manager.createSymbolicLink(at: stagedLink, withDestinationURL: elsewhere)
        let fileLink = temporary.appendingPathComponent("Journal Archive 2026-09-29.journalbackup")
        try manager.createSymbolicLink(
            at: fileLink, withDestinationURL: kept[0].appendingPathComponent("journal.sqlite"))

        // While the settings can't be read nothing can be called leftover: restore staging stays.
        ArchiveExportLeftovers.remove(dataDirectory: data, temporaryDirectory: temporary, libraryFolders: nil)
        XCTAssertTrue(manager.fileExists(atPath: leftovers[5].path))
        XCTAssertFalse(manager.fileExists(atPath: leftovers[0].path))

        ArchiveExportLeftovers.remove(
            dataDirectory: data, temporaryDirectory: temporary, libraryFolders: [current, earlier])
        for leftover in leftovers { XCTAssertFalse(manager.fileExists(atPath: leftover.path), leftover.path) }
        for item in kept + [elsewhere] { XCTAssertTrue(manager.fileExists(atPath: item.path), item.path) }
        XCTAssertNotNil(try? manager.destinationOfSymbolicLink(atPath: stagedLink.path))
        XCTAssertNotNil(try? manager.destinationOfSymbolicLink(atPath: fileLink.path))
        XCTAssertTrue(manager.fileExists(atPath: elsewhere.appendingPathComponent("journal.sqlite").path))
    }

    private func capturePreview(_ summary: ArchiveSummary) async {
        let preview = ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Import Archive").font(.title2.bold())
                ArchivePreviewSummary(summary: summary)
            }.padding(24)
        }
        if let image = await NativeTestPreview.capture(preview, name: "Archive preview") { add(image) }
        if let image = await NativeTestPreview.capture(
            preview.preferredColorScheme(.dark).environment(\.dynamicTypeSize, .accessibility5),
            name: "Archive preview dark largest text")
        {
            add(image)
        }
    }

}
