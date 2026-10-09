import Foundation

public enum EntryDateError: Error, LocalizedError, Sendable {
    case changed, unavailable
    public var errorDescription: String? {
        switch self {
        case .changed: return "This entry’s date changed. Close this sheet and try again."
        case .unavailable: return "This entry is no longer available for editing."
        }
    }
}
