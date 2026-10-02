import JournalCore
import SwiftUI

/// A quiet explanation shown under the title when the entry can't be edited normally.
struct EntryEditingNote: View {
    let document: JournalDocument

    var body: some View {
        if !document.isEditable {
            Text("Update My Journal to edit this entry.").foregroundStyle(.secondary)
        } else if document.requiresMarkdownSource {
            Text("This entry uses Markdown that can’t be previewed.").foregroundStyle(.secondary)
        }
    }
}
