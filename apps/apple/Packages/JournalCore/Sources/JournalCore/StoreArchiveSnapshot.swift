import Foundation
import GRDB

// What a file archive takes from a library: a consistent copy of the database, and the images the library keeps.
extension JournalStore {
    /// Checks the library as an export needs (`validateSnapshot`), then copies the database to `file`, which must not
    /// exist, as one self-contained rollback-journal file with no `-wal` or `-shm`. Returns the identifiers in the
    /// copy's `attachments` table, which are the images to archive: images never change once written, so reading
    /// them from the library while the copy is archived is safe. Removes `file` again if anything fails.
    func exportDatabase(to file: URL) async throws -> [String] {
        try Task.checkCancellation()
        try await validateSnapshot()
        return try copyDatabase(to: file)
    }

    private func copyDatabase(to file: URL) throws -> [String] {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: file.path) else { throw CocoaError(.fileWriteFileExists) }
        var target: DatabaseQueue?
        do {
            let snapshot = try DatabaseQueue(path: file.path)
            target = snapshot
            try db.backup(to: snapshot)
            try snapshot.writeWithoutTransaction { _ = try String.fetchOne($0, sql: "PRAGMA journal_mode = DELETE") }
            let stored = try snapshot.read { try String.fetchAll($0, sql: "SELECT id FROM attachments") }
            let identifiers = try stored.map { text -> String in
                guard let uuid = UUID(uuidString: text) else { throw JournalError.invalidData }
                return id(uuid)
            }
            try Task.checkCancellation()
            try snapshot.close()
            for suffix in ["-wal", "-shm"] {
                let leftover = URL(fileURLWithPath: file.path + suffix)
                if manager.fileExists(atPath: leftover.path) { try manager.removeItem(at: leftover) }
            }
            return identifiers
        } catch {
            try? target?.close()
            try? manager.removeItem(at: file)
            throw error
        }
    }

    /// The most an export writes: the database (with its write-ahead log, which the copy folds in) and every image
    /// file the library holds. The copy of the database is deleted once archived, so this is conservative.
    func archiveBytesEstimate() throws -> UInt64 {
        let manager = FileManager.default
        var total: UInt64 = 0
        for suffix in ["", "-wal"] {
            let file = directory.appendingPathComponent("journal.sqlite" + suffix)
            if let size = try? manager.attributesOfItem(atPath: file.path)[.size] as? UInt64 { total += size }
        }
        let identifiers = try db.read { try String.fetchAll($0, sql: "SELECT id FROM attachments") }
        for text in identifiers {
            guard let uuid = UUID(uuidString: text) else { throw JournalError.invalidData }
            let size = try manager.attributesOfItem(atPath: attachmentURL(uuid).path)[.size] as? UInt64
            total += size ?? 0
        }
        return total
    }
}
