import XCTest

@testable import JournalCore

final class SearchTests: XCTestCase {
    private func entry(_ title: String, _ text: String) -> JournalItem {
        var item = JournalItem(kind: "entry", journalID: UUID(), title: title, document: .plain(text))
        item.storedVersion = StoredVersion(digest: Data(UUID().uuidString.utf8))
        return item
    }

    /// The index finds exactly what comparing each entry's title and text with `localizedStandardContains` finds,
    /// which is how the list searched before.
    func testTheIndexFindsWhatComparingEachEntryFinds() async throws {
        let items = [
            entry("Café au lait", "Morning at the corner place."),
            entry("", "CAFE notes\nSecond line about naïve plans"),
            entry("Reise", "Die Straße war nass. Ünïcödé everywhere."),
            entry("日本", "日本語のテキストを書きました。"),
            entry("Party", "A 🎉 party with friends"),
            entry("Ligatures", "Ofﬁce hours and ﬂowers"),
            JournalItem(kind: "template", title: "Daily Reflection", document: .plain("What went well?")),
            JournalItem(kind: "journal", title: "Cafe journal"),
        ]
        let index = EntrySearchIndex(locale: Locale(identifier: "en_US"))
        await index.update(items)
        let queries = [
            "cafe", "CAFÉ", "naive", "NAÏVE", "strasse", "Straße", "unicode", "本語", "🎉", "office", "flowers",
            "went", "journal", "place.", "zzz", "e",
        ]
        for query in queries {
            let found = await index.matches(query)
            let expected = Set(
                items.filter {
                    ($0.kind == "entry" || $0.kind == "template")
                        && ($0.title.localizedStandardContains(query)
                            || $0.document.text.localizedStandardContains(query))
                }.map(\.id))
            XCTAssertEqual(found, expected, "Query “\(query)”")
        }
    }

    func testChangedAndRemovedEntriesAreFoundAsTheyAreNow() async throws {
        var first = entry("First", "about the harbor")
        let second = entry("Second", "about the mountains")
        let index = EntrySearchIndex()
        await index.update([first, second])
        var found = await index.matches("harbor")
        XCTAssertEqual(found, [first.id])

        first.document = .plain("about the lake")
        first.storedVersion = StoredVersion(digest: Data("changed".utf8))
        await index.update([first], complete: false)
        found = await index.matches("harbor")
        XCTAssertEqual(found, [])
        found = await index.matches("lake")
        XCTAssertEqual(found, [first.id])

        await index.update([first])
        found = await index.matches("mountains")
        XCTAssertEqual(found, [], "An entry no longer in the library isn't found")
    }
}
