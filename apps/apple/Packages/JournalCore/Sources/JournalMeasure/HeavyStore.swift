import Foundation
import JournalCore

/// Store-level costs on the heavy synthetic library: what unlocking, autosave, search and opening a long entry cost
/// before any view is involved. Works on a copy, so the seeded library stays as it was.
enum HeavyStore {
    static func measure(_ fixture: URL) async throws -> [String: Double] {
        let library = SyntheticLibrary(directory: fixture)
        let manifest = try JournalCoding.decoder().decode(
            SyntheticLibrary.Manifest.self, from: Data(contentsOf: library.manifestURL))
        let key = try Data(contentsOf: library.keyURL)
        let work = fixture.appendingPathComponent("work-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.copyItem(at: library.libraryURL, to: work)
        defer { try? FileManager.default.removeItem(at: work) }
        var metrics: [String: Double] = [:]
        var started = ProcessInfo.processInfo.systemUptime
        let store = try JournalStore(directory: work, key: key)
        metrics["openSeconds"] = Measure.elapsed(started)
        started = ProcessInfo.processInfo.systemUptime
        let snapshot = try await store.viewSnapshot()
        metrics["firstSnapshotSeconds"] = Measure.elapsed(started)
        started = ProcessInfo.processInfo.systemUptime
        _ = try await store.viewSnapshot()
        metrics["secondSnapshotSeconds"] = Measure.elapsed(started)
        // Opening again soon after, while the system still caches the file: every record is decoded again.
        let reopened = try JournalStore(directory: work, key: key)
        started = ProcessInfo.processInfo.systemUptime
        _ = try await reopened.viewSnapshot()
        metrics["warmFileFirstSnapshotSeconds"] = Measure.elapsed(started)
        try await reopened.close()
        let entries = snapshot.items.filter { $0.kind == "entry" }
        guard entries.count == manifest.shape.entries else { throw MeasurementError.contentMismatch }
        for (term, expected) in manifest.searchTerms {
            started = ProcessInfo.processInfo.systemUptime
            let found = entries.filter {
                $0.title.localizedStandardContains(term) || $0.document.text.localizedStandardContains(term)
            }
            metrics["scanSearchSeconds." + term] = Measure.elapsed(started)
            guard found.count >= expected else { throw MeasurementError.contentMismatch }
        }
        started = ProcessInfo.processInfo.systemUptime
        let index = EntrySearchIndex()
        await index.update(snapshot.items)
        metrics["searchIndexBuildSeconds"] = Measure.elapsed(started)
        for term in manifest.searchTerms.keys {
            started = ProcessInfo.processInfo.systemUptime
            let found = await index.matches(term)
            metrics["indexSearchSeconds." + term] = Measure.elapsed(started)
            let scanned = entries.filter {
                $0.title.localizedStandardContains(term) || $0.document.text.localizedStandardContains(term)
            }
            // Templates are searched too; the scan above covers entries.
            let foundEntries = found.intersection(entries.map(\.id))
            guard foundEntries == Set(scanned.map(\.id)) else {
                print("Search differs for \(term): \(foundEntries.count) found, \(scanned.count) scanned")
                throw MeasurementError.contentMismatch
            }
        }
        guard let normal = entries.first(where: { $0.id == manifest.normalEntryID }),
            let long = entries.first(where: { $0.id == manifest.longEntryID })
        else { throw MeasurementError.contentMismatch }
        metrics["longEntryMarkdownBytes"] = Double(long.document.markdown.utf8.count)
        metrics["decodeLongEntrySeconds"] = try await median(5) { _ = try await store.item(long.id) }
        metrics["decodeNormalEntrySeconds"] = try await median(5) { _ = try await store.item(normal.id) }
        metrics["richEditLongEntrySeconds"] = try median(5) { _ = long.document.applyingRichEdit(typed(long.document)) }
        metrics["richEditNormalEntrySeconds"] = try median(5) {
            _ = normal.document.applyingRichEdit(typed(normal.document))
        }
        metrics["saveNormalEntrySeconds"] = try await saves(of: normal, in: store, count: 20)
        metrics["saveLongEntrySeconds"] = try await saves(of: long, in: store, count: 10)
        try await store.close()
        metrics["peakResidentBytes"] = try Measure.peakResidentBytes()
        return metrics
    }

    /// The document after typing one character in the middle paragraph.
    static func typed(_ document: JournalDocument) -> JournalDocument {
        var edited = document
        let middle = edited.blocks.indices.filter { edited.blocks[$0].kind == "paragraph" }
        guard let index = middle.dropFirst(middle.count / 2).first, !edited.blocks[index].runs.isEmpty else {
            return edited
        }
        edited.blocks[index].runs[edited.blocks[index].runs.count - 1].text += "e"
        return edited
    }

    /// The median time of autosaving an entry after each of `count` keystrokes, on the store actor.
    static func saves(of item: JournalItem, in store: JournalStore, count: Int) async throws -> Double {
        var current = try await store.item(item.id) ?? item
        var durations: [Double] = []
        for _ in 0..<count {
            var edited = current
            edited.document = current.document.applyingRichEdit(typed(current.document))
            edited.modifiedAt = Date()
            let started = ProcessInfo.processInfo.systemUptime
            current = try await store.save(edited)
            durations.append(Measure.elapsed(started))
        }
        return durations.sorted()[durations.count / 2]
    }

    static func median(_ count: Int, _ work: () throws -> Void) throws -> Double {
        var durations: [Double] = []
        for _ in 0..<count {
            let started = ProcessInfo.processInfo.systemUptime
            try work()
            durations.append(Measure.elapsed(started))
        }
        return durations.sorted()[count / 2]
    }

    static func median(_ count: Int, _ work: () async throws -> Void) async throws -> Double {
        var durations: [Double] = []
        for _ in 0..<count {
            let started = ProcessInfo.processInfo.systemUptime
            try await work()
            durations.append(Measure.elapsed(started))
        }
        return durations.sorted()[count / 2]
    }
}
