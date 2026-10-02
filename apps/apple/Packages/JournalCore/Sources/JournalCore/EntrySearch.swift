import Foundation

/// Finds entries and templates whose title or text contains a query, ignoring case and diacritics as
/// `localizedStandardContains` does, without reading every entry again for each query. Each item's text is folded once
/// and kept in memory only; nothing of it is written anywhere, so the journals stay encrypted at rest. Clear it when the
/// journals lock.
public actor EntrySearchIndex {
    private struct Entry: Sendable {
        let version: StoredVersion?
        let text: [UInt8]
    }
    private var entries: [UUID: Entry] = [:]
    private let locale: Locale

    public init(locale: Locale = .current) { self.locale = locale }

    /// Brings the index up to date with the library. Items whose stored version is unchanged aren't read again.
    /// With `complete`, items not listed are removed.
    public func update(_ items: [JournalItem], complete: Bool = true) {
        let searchable = items.filter { $0.kind == "entry" || $0.kind == "template" }
        let changed = searchable.filter { item in
            guard let version = item.storedVersion, let known = entries[item.id] else { return true }
            return known.version != version
        }
        let locale = locale
        let folded = (try? Parallel.map(changed) { item in Self.fold(item.title + "\n" + item.document.text, locale) })
        if complete {
            let kept = Set(searchable.map(\.id))
            entries = entries.filter { kept.contains($0.key) }
        }
        for (item, text) in zip(changed, folded ?? []) {
            entries[item.id] = Entry(version: item.storedVersion, text: text)
        }
    }

    /// The identifiers of indexed items containing `query`. An empty query matches nothing.
    public func matches(_ query: String) -> Set<UUID> {
        let needle = Self.fold(query, locale)
        guard !needle.isEmpty else { return [] }
        let found = try? Parallel.map(Array(entries)) { id, entry in Self.contains(entry.text, needle) ? id : nil }
        return Set((found ?? []).compactMap { $0 })
    }

    public func clear() { entries = [:] }

    /// Text compared the way `localizedStandardContains` compares it: without case or diacritic differences, in
    /// composed form, as UTF-8.
    static func fold(_ text: String, _ locale: Locale) -> [UInt8] {
        Array(
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
                .precomposedStringWithCanonicalMapping.utf8)
    }

    static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        haystack.withUnsafeBytes { text in
            needle.withUnsafeBytes { query in
                memmem(text.baseAddress, text.count, query.baseAddress, query.count) != nil
            }
        }
    }
}
