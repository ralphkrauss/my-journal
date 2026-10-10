import CryptoKit
import Foundation

@testable import JournalCore

/// A directory archive as My Journal 1.0 wrote it (protocol/archive.md, Directory archive). The app no longer writes
/// one, but it still reads those of encrypted libraries, so tests build them here: a snapshot of the library, its
/// images, and a header that holds the recovery envelope and the sealed manifest. The header of a library 1.0 made
/// without encryption (plain manifest) is built only to show that it is refused.
enum DirectoryArchiveFixture {
    static func write(store: JournalStore, recovery: RecoveryEnvelope, key: Data, to destination: URL) async throws {
        try await store.snapshot(to: destination, requireComplete: true)
        do {
            let manifest = try manifestJSON(of: destination)
            let sealed = try VaultCrypto.seal(manifest, key: key, context: "journal:v1:archive")
            let header: [String: Any] = [
                "version": 1,
                "recovery": [
                    "salt": recovery.salt, "wrappedKey": recovery.wrappedKey, "iterations": recovery.iterations,
                    "formatVersion": recovery.formatVersion,
                ] as [String: Any],
                "manifest": sealed.base64EncodedString(),
            ]
            try JSONSerialization.data(withJSONObject: header, options: .sortedKeys).write(
                to: destination.appendingPathComponent("archive.json"))
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static func manifestJSON(of directory: URL) throws -> Data {
        let images = directory.appendingPathComponent("attachments", isDirectory: true)
        var hashes: [String: String] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: images.path) where !name.hasPrefix(".") {
            hashes[name] = try digest(images.appendingPathComponent(name))
        }
        let manifest: [String: Any] = [
            "database": try digest(directory.appendingPathComponent("journal.sqlite")), "attachments": hashes,
        ]
        return try JSONSerialization.data(withJSONObject: manifest, options: .sortedKeys)
    }

    private static func digest(_ file: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
    }

    /// Only the header 1.0 wrote for a library without encryption: version 2, recovery format 3 or 4, a plain manifest.
    static func writeUnencryptedHeader(formatVersion: Int, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let manifest = try JSONSerialization.data(withJSONObject: ["database": "", "attachments": [:]])
        let header: [String: Any] = [
            "version": 2,
            "recovery": [
                "salt": "", "wrappedKey": "", "iterations": 0, "formatVersion": formatVersion,
            ] as [String: Any],
            "manifest": manifest.base64EncodedString(),
        ]
        try JSONSerialization.data(withJSONObject: header, options: .sortedKeys).write(
            to: destination.appendingPathComponent("archive.json"))
    }
}
