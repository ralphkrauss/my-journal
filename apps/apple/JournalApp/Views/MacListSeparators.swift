import SwiftUI

/// The Mac entries list draws lines between rows only, as Notes and Mail do: none under a section's header, none
/// after a section's last row, and none where a floating header meets the column's top edge
/// (docs/design/mac-list-separators-2026-10-04.md). iOS keeps its inset grouped style.
extension View {
    /// For a section's header.
    func entriesHeaderSeparatorHidden() -> some View {
        #if os(macOS)
            listRowSeparator(.hidden)
        #else
            self
        #endif
    }
    /// For a row: the last one of its section has no line below it.
    func entriesRowSeparator(lastInSection: Bool) -> some View {
        #if os(macOS)
            listRowSeparator(lastInSection ? .hidden : .automatic, edges: .bottom)
        #else
            self
        #endif
    }
}
