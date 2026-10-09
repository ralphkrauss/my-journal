import Foundation

public enum HistoryRecoveryError: Error, LocalizedError, Sendable {
    case unavailableVersion, destinationUnavailable

    public var errorDescription: String? {
        switch self {
        case .unavailableVersion: return "This version is no longer available. Reload its history."
        case .destinationUnavailable: return "Choose an available journal."
        }
    }
}
