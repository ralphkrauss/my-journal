import Foundation
import JournalCore

/// A network error in words that say what to do, chosen as sync chooses its state, so the system's own text, such as
/// “The Internet connection appears to be offline.”, never reaches the person (docs/design/build-18-fixes-2026-10-06.md
/// §1.13).
enum NetworkFailureMessage {
    static func text(for error: URLError) -> String {
        switch SyncHealth(classifying: error) {
        case .offline:
            return "You’re offline. Check your connection."
        case .certificateInvalid:
            return "Can’t connect securely to the server because its certificate isn’t valid."
        default:
            return "Couldn’t reach the server. Check your connection."
        }
    }
}
