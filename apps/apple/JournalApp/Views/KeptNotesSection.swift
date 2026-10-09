import JournalCore
import SwiftUI

/// Settings ▸ Sync ▸ Changed on Two Devices: what this device settled by keeping both versions, for 30 days
/// (docs/design/1-1-conflicts-and-reconnect.md, 4.3). Quiet: it is a list to look at, nothing to answer.
struct KeptNotesSection: View {
    @EnvironmentObject private var model: AppModel
    /// Opens what a row names. Settings closes first on the iPhone and iPad; the Mac's library window comes forward.
    let open: (KeptNoteRow) -> Void

    var body: some View {
        let rows = model.keptNoteRows
        if !model.locked, !rows.isEmpty {
            Section {
                ForEach(rows) { row in
                    if row.opens != nil {
                        Button {
                            open(row)
                        } label: {
                            KeptNoteRowLabel(row: row, opens: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(row.spokenLabel)
                        .accessibilityHint("Opens it.")
                        .accessibilityAddTraits(.isButton)
                    } else {
                        KeptNoteRowLabel(row: row, opens: false).accessibilityElement(children: .combine)
                    }
                }
                Button("Clear List") { Task { await model.clearKeptNotes() } }
            } header: {
                Text("Changed on Two Devices")
            } footer: {
                Text("Both versions are kept. This list clears after 30 days.")
            }
        }
    }
}

/// A row: the title, the sentence and the date and time, wrapping at every text size. A row that opens something has
/// the disclosure indicator on iOS; on the Mac the whole row is a button.
private struct KeptNoteRowLabel: View {
    let row: KeptNoteRow
    let opens: Bool
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title).fixedSize(horizontal: false, vertical: true)
                Text(row.sentence).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(row.date, format: .dateTime).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            #if os(iOS)
                if opens {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary).accessibilityHidden(true)
                }
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
