import CryptoKit
import Foundation
import GRDB
import os

/// A record's stored columns, read before decoding so that decoding can run outside the database's queue.
struct StoredRecord: Sendable {
    let id: UUID
    let kind: String
    let payload: String
}

extension JournalStore {
    /// The item a stored payload holds. A record decoded before from the same payload is reused.
    func decode(_ payload: String, id: UUID, kind: String) throws -> JournalItem {
        let version = Self.version(of: payload)
        if let known = decodedRecords[id], known.storedVersion == version, known.kind == kind { return known }
        return try Self.decode(payload, id: id, kind: kind, version: version, key: key, protection: protection)
    }
    /// Decodes a payload stored as a record, and remembers it while the journals are open.
    func decodeRecord(_ payload: String, id: UUID, kind: String) throws -> JournalItem {
        let item = try decode(payload, id: id, kind: kind)
        if remembersDecodedRecords { decodedRecords[id] = item }
        return item
    }
    /// Decodes the records read from the database, all at once on every processor core, reusing the ones whose payload
    /// is unchanged. With `complete`, these are all records, and records no longer stored are forgotten.
    func decodeRecords(_ records: [StoredRecord], complete: Bool) throws -> [JournalItem] {
        let known = remembersDecodedRecords ? decodedRecords : [:]
        let key = key
        let protection = protection
        let items = try Parallel.map(records) { record in
            let version = Self.version(of: record.payload)
            if let item = known[record.id], item.storedVersion == version, item.kind == record.kind { return item }
            return try Self.decode(
                record.payload, id: record.id, kind: record.kind, version: version, key: key, protection: protection)
        }
        if remembersDecodedRecords {
            if complete { decodedRecords = [:] }
            for item in items { decodedRecords[item.id] = item }
        }
        return items
    }
    /// Forgets decoded records and stops keeping them, when the journals lock.
    public func forgetDecodedRecords() {
        remembersDecodedRecords = false
        decodedRecords = [:]
    }
    /// Keeps decoded records again, once the journals are unlocked.
    public func rememberDecodedRecords() { remembersDecodedRecords = true }
    /// Decrypts and decodes a stored payload.
    static func decode(
        _ payload: String, id: UUID, kind: String, version: StoredVersion, key: Data, protection: ContentProtection
    ) throws -> JournalItem {
        guard let data = Data(base64Encoded: payload) else { throw JournalError.invalidData }
        let plaintext = try protection.decode(data, key: key, context: VaultCrypto.recordContext(id: id, kind: kind))
        var item: JournalItem
        do {
            item = try PortableRecord.decode(plaintext)
            guard item.id == id, item.kind == kind else { throw JournalError.invalidData }
        } catch {
            // Authenticated content this version can't read is kept as it is instead of blocking sync.
            item = PortableRecord.unreadable(plaintext, id: id, kind: kind)
        }
        item.storedVersion = version
        return item
    }

    static func version(of payload: String) -> StoredVersion {
        var text = payload
        let digest = text.withUTF8 { SHA256.hash(data: UnsafeRawBufferPointer($0)) }
        return StoredVersion(digest: Data(digest))
    }

    /// Rows with `id`, `kind` and `payload` columns.
    func storedRecords(_ db: Database, sql: String) throws -> [StoredRecord] {
        var records: [StoredRecord] = []
        let rows = try Row.fetchCursor(db, sql: sql)
        while let row = try rows.next() {
            guard let uuid = UUID(uuidString: row["id"]) else { throw JournalError.invalidData }
            records.append(StoredRecord(id: uuid, kind: row["kind"], payload: row["payload"]))
        }
        return records
    }
}

/// Work spread over the processor's cores.
enum Parallel {
    /// `map` over `chunk` values at a time, stopping between chunks when the calling task is cancelled.
    static func map<Value: Sendable, Result: Sendable>(
        _ values: [Value], width: Int, cancellableEvery chunk: Int, _ transform: @Sendable (Value) throws -> Result
    ) throws -> [Result] {
        var results: [Result] = []
        var start = 0
        while start < values.count {
            try Task.checkCancellation()
            let end = min(values.count, start + chunk)
            results += try map(Array(values[start..<end]), width: width, transform)
            start = end
        }
        return results
    }
    /// `transform` applied to each value in parallel, in order. The first error is thrown once all work stopped.
    /// At most `width` values are transformed at once.
    static func map<Value: Sendable, Result: Sendable>(
        _ values: [Value], width: Int = ProcessInfo.processInfo.activeProcessorCount * 4,
        _ transform: @Sendable (Value) throws -> Result
    ) throws -> [Result] {
        guard values.count > 1 else { return try values.map(transform) }
        let slices = min(values.count, max(1, width))
        // Each slice's results, collected once the slice is done.
        let done = OSAllocatedUnfairLock<[Int: [Swift.Result<Result, Error>]]>(initialState: [:])
        DispatchQueue.concurrentPerform(iterations: slices) { slice in
            let range = (values.count * slice / slices)..<(values.count * (slice + 1) / slices)
            let results = range.map { index in Swift.Result { try transform(values[index]) } }
            done.withLock { $0[slice] = results }
        }
        let collected = done.withLock { $0 }
        return try (0..<slices).flatMap { slice in try (collected[slice] ?? []).map { try $0.get() } }
    }
}
