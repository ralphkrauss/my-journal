import CryptoKit
import JournalCore
import XCTest

@testable import Journal

/// The archive as the app writes and reads it: one file in 1.1, a folder in 1.0. The format itself is checked in
/// JournalCore (container, hardening and conformance tests); these protect the routes a person takes through the app.
@MainActor
final class ArchiveFileTests: XCTestCase {
    private func library(named name: String, in root: URL) -> AppModel {
        let model = AppModel(directory: root.appendingPathComponent(name))
        addTeardownBlock { @MainActor in
            let account =
                "master-"
                + SHA256.hash(data: Data(model.directory.path.utf8)).map { String(format: "%02x", $0) }.joined()
            try? Keychain.remove(account)
            if let current = model.configuration?.keyID { try? Keychain.remove(current) }
            _ = await model.finishPendingSave()
            try? await model.store?.close()
        }
        return model
    }

    private func temporaryRoot() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    /// Export Archive writes one regular file under the archive's name, and Import Archive brings its journals,
    /// entries and images into another library as new journals.
    func testExportingAFileArchiveAndImportingItRoundTripsThroughTheAppModel() async throws {
        let root = temporaryRoot()
        let source = library(named: "source", in: root)
        let destination = library(named: "destination", in: root)
        await source.start()
        source.confirmRecovery()
        let store = try XCTUnwrap(source.store)
        let journalID = try XCTUnwrap(source.journals.first?.id)
        let image = Data((0..<3000).map { UInt8($0 % 241) })
        let imageID = try await store.addAttachment(image)
        let entry = JournalItem(
            kind: "entry", journalID: journalID, title: "Carried in one file",
            document: .init(blocks: [DocumentBlock(kind: "image", attachmentID: imageID, imageDescription: "A picture")]
            ))
        try await store.save(entry)

        let archive = try await source.prepareArchive()
        let values = try archive.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        XCTAssertEqual(values.isRegularFile, true, "A file archive is one file, not a folder")
        XCTAssertGreaterThan(values.fileSize ?? 0, image.count)
        XCTAssertEqual(try Data(contentsOf: archive).prefix(2), Data("PK".utf8), "A ZIP container")
        XCTAssertTrue(ArchiveFileType.isArchive(archive))
        let temporary = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
        XCTAssertFalse(
            temporary.contains { $0.hasPrefix("export-") && $0.hasSuffix(".sqlite") }, "The database copy is gone")

        await destination.start()
        destination.confirmRecovery()
        let restored = try await destination.inspectArchive(archive, phrase: AppModel.testPassword)
        let summary = ArchiveSummary(snapshot: try await restored.store.lifecycleSnapshot())
        XCTAssertEqual(summary.entries, 1)
        try await destination.installArchive(restored)
        await destination.discardImportedCopy(restored)

        let imported = try XCTUnwrap(destination.items.first { $0.title == "Carried in one file" })
        let importedImage = try XCTUnwrap(imported.document.attachmentIDs.first)
        XCTAssertNotEqual(importedImage, imageID, "Imported images get new identities")
        let importedBytes = try await destination.store?.attachment(importedImage)
        XCTAssertEqual(importedBytes, image)
        XCTAssertEqual(destination.journals.count, 2, "Imported journals are separate from the destination's own")
        try? FileManager.default.removeItem(at: archive)
    }

    /// An archive made by 1.0 is a folder. It still opens in 1.1, from a name that 1.1 files also use.
    func testAFolderArchiveFromVersionOneStillRestoresThroughTheAppModel() async throws {
        let root = temporaryRoot()
        let conformance = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("protocol/conformance")
        let folder = root.appendingPathComponent("Journal Archive 2026-09-30.journalarchive")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: conformance.appendingPathComponent("archive/v1/encrypted"), to: folder)
        let corpus = try JSONSerialization.jsonObject(
            with: Data(contentsOf: conformance.appendingPathComponent("crypto/encryption-v2.json")))
        let recovery = try XCTUnwrap((corpus as? [String: Any])?["recovery"] as? [String: Any])
        let password = try XCTUnwrap(recovery["password"] as? String)
        XCTAssertTrue(ArchiveFileType.isArchive(folder), "Opening one from Finder or Files is offered like a file")

        let destination = library(named: "destination", in: root)
        await destination.start()
        destination.confirmRecovery()
        let restored = try await destination.inspectArchive(folder, phrase: password)
        try await destination.installArchive(restored)
        await destination.discardImportedCopy(restored)

        let titles = destination.items.filter { $0.kind == "entry" }.map(\.title)
        XCTAssertTrue(titles.contains("Morning pages"), "\(titles)")
        XCTAssertTrue(titles.contains("Written offline"), "\(titles)")
    }

    /// The system opens an archive by its extension; the archive code never does, so a folder and a file are both
    /// offered, and nothing else is.
    func testOnlyAFileURLWithTheArchiveExtensionIsOpenedFromOutside() throws {
        let root = temporaryRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("Journal Archive 2026-10-09.journalarchive")
        try Data("PK".utf8).write(to: file)
        let folder = root.appendingPathComponent("Old.journalarchive", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertTrue(ArchiveFileType.isArchive(file))
        XCTAssertTrue(ArchiveFileType.isArchive(folder))
        XCTAssertTrue(ArchiveFileType.isArchive(root.appendingPathComponent("BACKUP.JOURNALARCHIVE")))
        XCTAssertFalse(ArchiveFileType.isArchive(root.appendingPathComponent("Backup.zip")))
        XCTAssertFalse(ArchiveFileType.isArchive(root.appendingPathComponent("journalarchive")))
        XCTAssertFalse(try XCTUnwrap(URL(string: "https://example.com/Journal.journalarchive")).isFileURL)
        XCTAssertFalse(
            ArchiveFileType.isArchive(try XCTUnwrap(URL(string: "https://example.com/Journal.journalarchive"))))
        XCTAssertEqual(ArchiveFileType.importTypes.map(\.identifier), [ArchiveFileType.identifier])
    }

    /// A full volume is said once, in the same words, whether the writer's own check caught it before anything was
    /// written or the save dialog ran out of room while copying; any other failure is not mistaken for it.
    func testAFullVolumeIsReportedAsNotEnoughSpaceWhereverItIsFound() {
        XCTAssertEqual(ArchiveExport.message(for: ArchiveError.notEnoughSpace), ArchiveExport.noSpace)
        XCTAssertEqual(ArchiveExport.message(for: CocoaError(.fileWriteOutOfSpace)), ArchiveExport.noSpace)
        XCTAssertEqual(ArchiveExport.message(for: POSIXError(.ENOSPC)), ArchiveExport.noSpace)
        XCTAssertEqual(ArchiveExport.message(for: JournalError.invalidData), "Couldn’t export the archive. Try again.")

        let export = ArchiveExport(dialogFolder: FileManager.default.temporaryDirectory)
        export.finish(.failure(CocoaError(.fileWriteOutOfSpace)))
        XCTAssertEqual(export.error, ArchiveExport.noSpace)
        export.finish(.failure(POSIXError(.ENOSPC)))
        XCTAssertEqual(export.error, ArchiveExport.noSpace)
        export.error = nil
        export.finish(.failure(CocoaError(.fileWriteNoPermission)))
        XCTAssertEqual(export.error, ArchiveExport.saveFailure)
        export.error = nil
        export.finish(.failure(CocoaError(.userCancelled)))
        XCTAssertNil(export.error, "Cancelling the dialog is not a failure")
    }
}
