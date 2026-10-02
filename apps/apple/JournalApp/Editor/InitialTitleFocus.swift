import Foundation

@MainActor
final class InitialTitleFocus {
    let itemID: UUID
    private var pending = true
    init(itemID: UUID) { self.itemID = itemID }
    func consume(when ready: () -> Bool) -> Bool {
        guard pending, ready() else { return false }
        pending = false
        return true
    }
    func cancel() { pending = false }
}
