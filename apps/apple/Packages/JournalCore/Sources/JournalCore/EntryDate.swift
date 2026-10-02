import Foundation

public enum EntryDateError: Error, LocalizedError, Sendable {
    case changed, unavailable, saveRequired
    public var errorDescription: String? {
        switch self {
        case .changed: return "This entry’s date changed. Close this sheet and try again."
        case .saveRequired:
            return "Your entry has unsaved changes. Close this sheet and save your entry before changing its date."
        case .unavailable: return "This entry is no longer available for editing."
        }
    }
}
