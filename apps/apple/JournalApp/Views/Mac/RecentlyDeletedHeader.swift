#if os(macOS)
    import SwiftUI

    extension View {
        /// The bar at the top of Recently Deleted on the Mac, as in Finder's Trash: what the place is, and Delete All…
        /// (docs/design/ios-delete-all-and-settings-2026-10-03.md §4). The rows scroll under it. Elsewhere it takes no
        /// room, and the list keeps its identity when the collection changes.
        func recentlyDeletedHeader(shown: Bool, deleteAll: @escaping () -> Void) -> some View {
            modifier(RecentlyDeletedBar(shown: shown, deleteAll: deleteAll))
        }
    }

    private struct RecentlyDeletedBar: ViewModifier {
        let shown: Bool
        let deleteAll: () -> Void

        func body(content: Content) -> some View {
            if #available(macOS 26.0, *) {
                content.safeAreaBar(edge: .top) {
                    if shown { RecentlyDeletedHeader(deleteAll: deleteAll) }
                }
            } else {
                content.safeAreaInset(edge: .top, spacing: 0) {
                    if shown {
                        VStack(spacing: 0) {
                            RecentlyDeletedHeader(deleteAll: deleteAll)
                            Divider()
                        }.background(.bar)
                    }
                }
            }
        }
    }

    private struct RecentlyDeletedHeader: View {
        @EnvironmentObject var model: AppModel
        let deleteAll: () -> Void

        var body: some View {
            HStack(spacing: 12) {
                Text("Items stay here until you delete them permanently.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Delete All…", action: deleteAll)
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(!model.canDeleteAll)
                    // While searching, “All” could mean the results.
                    .help(
                        model.query.isEmpty
                            ? "Permanently delete all items in Recently Deleted"
                            : "Clear the search to delete all items.")
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 7)
        }
    }
#endif
