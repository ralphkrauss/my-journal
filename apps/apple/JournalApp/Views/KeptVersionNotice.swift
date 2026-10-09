import JournalCore
import SwiftUI

/// The notice above the open entry or template on the device that kept both versions of it: the other version was
/// saved as a separate entry or template (docs/design/1-1-conflicts-and-reconnect.md, 4.2). It sits where the notice
/// for changes to review sat, in the same style, and says nothing else: no alert, no sound, no announcement. A version
/// that only a newer My Journal can read shows one line with no buttons.
///
/// It never appears under a cursor that is resting in the text. Nothing is settled while the entry is being written, so
/// a notice that arrives while the person is in the title or the text waits for the next time the entry is shown, or
/// until the editor lets go of the keyboard.
struct KeptVersionNotice: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var editor: EditorActions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: JournalItem
    /// Stacked navigation (iPhone): showing the other version pushes it on the stack.
    let stacked: Bool
    /// Which notices have been shown, so one that appeared stays while the person starts writing again.
    @State private var release = NoticeRelease()

    private var writing: Bool { editor.editing || editor.editingTable }

    var body: some View {
        let notice = model.entryNotice(for: item)
        Group {
            if let notice, release.isVisible(identity(of: notice), whileWriting: writing) {
                content(notice)
            }
        }
        .onAppear { reveal(notice) }
        .onValueChange(of: writing) { _ in reveal(model.entryNotice(for: item)) }
        .onValueChange(of: notice) { reveal($0) }
    }

    private func identity(of notice: AppModel.EntryNotice) -> UUID {
        switch notice {
        case .keptBoth(let note): return note.id
        case .updateNeeded: return item.id
        }
    }

    private func reveal(_ notice: AppModel.EntryNotice?) {
        guard let notice else { return }
        release.reveal(identity(of: notice), whileWriting: writing)
    }

    @ViewBuilder private func content(_ notice: AppModel.EntryNotice) -> some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 12 : 8) {
            Text(text(for: notice)).font(.callout).fixedSize(horizontal: false, vertical: true)
            if case .keptBoth(let note) = notice { buttons(for: note) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding().background(.quaternary, ignoresSafeAreaEdges: [])
        .accessibilityIdentifier("kept-notice")
    }

    @ViewBuilder private func buttons(for note: KeptNote) -> some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 16))
        layout {
            Button("Show Other Version") {
                Task { await model.openKeptNote(note.id, revealing: stacked) }
            }
            Button("Dismiss") { Task { await model.dismissKeptNote(note.id) } }
        }
    }

    private func text(for notice: AppModel.EntryNotice) -> String {
        let template = item.kind == "template"
        switch notice {
        case .updateNeeded:
            return "This entry has a version from a newer My Journal. Update My Journal to combine them."
        case .keptBoth(let note):
            let newer = note.otherIsNewer == true
            switch (template, newer) {
            case (false, false):
                return "This entry was also changed on another device. The other version is saved as a separate entry."
            case (false, true):
                return
                    "This entry was also changed on another device, and that version is newer. It is saved as a separate entry."
            case (true, false):
                return
                    "This template was also changed on another device. The other version is saved as a separate template."
            case (true, true):
                return
                    "This template was also changed on another device, and that version is newer. It is saved as a separate template."
            }
        }
    }
}
