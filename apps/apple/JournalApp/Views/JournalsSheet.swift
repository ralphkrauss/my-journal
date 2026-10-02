import Foundation
import SwiftUI

struct JournalsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var journalID: UUID?
    var body: some View {
        NavigationStack {
            JournalSettingsView(journalID: journalID).navigationTitle(journalID == nil ? "Journals" : "Journal")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
            .frame(width: 520, height: 500)
        #endif
    }
}
