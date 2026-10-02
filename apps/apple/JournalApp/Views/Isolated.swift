import SwiftUI

/// Shows `content` again only when `key` changes, rather than whenever the view around it updates. The rows of a long
/// list would otherwise all be built again after any change the model publishes, such as a sync or a save.
struct Isolated<Key: Equatable & Sendable, Content: View>: View, Equatable {
    let key: Key
    @ViewBuilder let content: () -> Content
    var body: some View { content() }
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }
}
