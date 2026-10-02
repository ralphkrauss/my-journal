import SwiftUI

#if os(iOS)
    extension RootView {
        /// Shows the model's collection and entry after the layout changes to stacked navigation, not stale routes.
        func rebuildNavigationPath() {
            var path: [CompactJournalRoute] = []
            if let destination = model.destination {
                path.append(.collection(destination))
                if let id = model.draft?.id { path.append(.entry(id)) }
            }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { navigationPath = path }
        }
        /// The stack shows the model's collection. When the model moves to another one (New Entry from Templates or
        /// Recently Deleted, Restore Journal, Merge Into…, Restore from an entry's notice), the stack is rebuilt on it,
        /// keeping the open entry, so Back returns to where the entry is now. A journal that left the list without
        /// another chosen in its place (deleted here or by a sync) goes back to Journals rather than leaving a page
        /// whose title and actions belong elsewhere.
        func followModelDestination(to destination: JournalDestination?) {
            guard usesStackedNavigation, case .collection(let shown)? = navigationPath.first, shown != destination
            else { return }
            var path: [CompactJournalRoute] = []
            if let destination, !(journalLeftList(shown) && model.journalReplacedAutomatically) {
                path.append(.collection(destination))
                if navigationPath.count > 1, case .entry(let id) = navigationPath[1], id == model.draft?.id {
                    path.append(.entry(id))
                }
            }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { navigationPath = path }
        }
        private func journalLeftList(_ shown: JournalDestination) -> Bool {
            guard case .journal(let id) = shown else { return false }
            return !model.journals.contains { $0.id == id }
        }
    }

    /// Searches the listed entries. On iOS 17 and later, Search Entries (⌥⌘F) opens the search field.
    struct EntrySearch: ViewModifier {
        @Binding var text: String
        @Binding var isPresented: Bool
        let prompt: String
        func body(content: Content) -> some View {
            if #available(iOS 17, *) {
                content.searchable(text: $text, isPresented: $isPresented, prompt: prompt)
            } else {
                content.searchable(text: $text, prompt: prompt)
            }
        }
    }
#endif
