import JournalCore
import SwiftUI

struct JournalSearchResults: View {
    @EnvironmentObject private var model: AppModel
    let query: String
    let openEntry: (UUID) -> Void
    /// Found off the main thread, once for each query and each change to the lists.
    @State private var results: [JournalItem] = []
    @State private var searched: SearchKey?
    private struct SearchKey: Hashable {
        let query: String
        let revision: Int
    }
    var body: some View {
        List {
            ForEach(results) { entry in
                Button {
                    openEntry(entry.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.date, format: .dateTime.day().month(.abbreviated)).font(.caption).foregroundStyle(
                            .secondary)
                        Text(entry.displayTitle).font(.headline).lineLimit(1)
                        Text(entry.document.text(prefix: 1_000)).lineLimit(1).foregroundStyle(.secondary)
                        Label(
                            model.journals.first { $0.id == entry.journalID }?.title ?? "Journal",
                            systemImage: "book.closed"
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }.foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            }
        }.overlay {
            if searched != nil && results.isEmpty { Text("No Results").foregroundStyle(.secondary) }
        }.navigationTitle("Journals")
            .task(id: SearchKey(query: query, revision: model.lists.revision)) { await search() }
    }
    private func search() async {
        let key = SearchKey(query: query, revision: model.lists.revision)
        let found = await model.matchingEntries(query)
        guard !Task.isCancelled else { return }
        let lifecycle = model.lifecycle
        results = model.items.filter {
            found.contains($0.id) && $0.kind == "entry" && lifecycle.location(of: $0) == .journal
        }.sorted { $0.date > $1.date }
        searched = key
    }
}
