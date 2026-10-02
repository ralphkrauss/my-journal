import Foundation

public enum HistoryRecoveryError: Error, LocalizedError, Sendable {
    case unavailableVersion, destinationUnavailable, changedJournal, settingsAlreadyApplied

    public var errorDescription: String? {
        switch self {
        case .unavailableVersion: return "This version is no longer available. Reload its history."
        case .destinationUnavailable: return "Choose an available journal."
        case .changedJournal: return "This journal has changed. Review its settings again."
        case .settingsAlreadyApplied: return "These settings are already in use."
        }
    }
}
