#if os(iOS)
    import JournalCore
    import SwiftUI

    struct EntryHeaderView: View {
        @EnvironmentObject private var model: AppModel
        @EnvironmentObject private var editor: EditorActions
        let item: JournalItem
        @Binding var title: String

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if model.saveFailure {
                    SaveFailureNotice(entryID: item.id).padding().id("save-failure")
                }
                if item.kind == "entry"
                    ? !model.lifecycle.location(of: item).isInLiveJournal
                    : model.isRecentlyDeleted(item)
                {
                    EntryRecoveryNotice(entry: item).padding().background(.quaternary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    if model.canEdit {
                        EntryTitleEditor(
                            text: $title, initialFocus: model.titleFocus?.itemID == item.id ? model.titleFocus : nil,
                            submit: { editor.perform(.focus) }
                        )
                        .id(item.id)
                    } else {
                        Text(title.isEmpty ? "Title" : title)
                            .font(.title.bold()).textSelection(.enabled)
                            .foregroundStyle(title.isEmpty ? .tertiary : .primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Title").accessibilityValue(title)
                            .accessibilityIdentifier("Entry title")
                    }
                    EntryEditingNote(document: item.document)
                }.padding(.horizontal, 4).padding(.top, 28).padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("Entry header")
        }
    }
#endif
