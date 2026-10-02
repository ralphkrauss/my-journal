import JournalCore
import SwiftUI

struct WrappingMenuLabel: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Color.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(value).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.caption).accessibilityHidden(true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(value)
    }
}

/// Saved versions as the picker lists them: newest first, by when each version was made.
enum HistoryVersions {
    /// The store returns versions in the order they were recorded; resolving a conflict records an older version
    /// after a newer one. Versions with the same time keep the store's order, most recently recorded first.
    static func newestFirst(_ versions: [JournalItem]) -> [JournalItem] {
        versions.enumerated().sorted { first, second in
            first.element.modifiedAt != second.element.modifiedAt
                ? first.element.modifiedAt > second.element.modifiedAt : first.offset < second.offset
        }.map(\.element)
    }
    /// Each version's time, numbered only where versions would otherwise read the same.
    static func titles(_ versions: [JournalItem]) -> [String] {
        let times = versions.map { $0.modifiedAt.formatted(date: .abbreviated, time: .standard) }
        let counts = Dictionary(times.map { ($0, 1) }, uniquingKeysWith: +)
        var seen: [String: Int] = [:]
        return times.map { time in
            guard counts[time, default: 0] > 1 else { return time }
            seen[time, default: 0] += 1
            return "\(time) · \(seen[time, default: 1])"
        }
    }
}

struct HistoryVersionPicker: View {
    let versions: [JournalItem]
    @Binding var selected: Int
    var body: some View {
        let titles = HistoryVersions.titles(versions)
        Menu {
            Picker("Version", selection: $selected) {
                ForEach(versions.indices, id: \.self) { index in
                    Text(titles[index]).tag(index)
                }
            }.pickerStyle(.inline)
        } label: {
            WrappingMenuLabel(
                title: "Version", value: titles.indices.contains(selected) ? titles[selected] : "Choose a Version")
        }.accessibilityIdentifier("history-version")
    }
}
