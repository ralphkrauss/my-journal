import Foundation
import GRDB

/// Why synchronization isn't working, in the terms the person acts on (docs/design/sync-health-and-recovery.md §2).
public enum SyncHealth: Equatable, Sendable {
    /// No network connection on this device.
    case offline
    /// The server can't be reached: refused, timed out or not found.
    case unreachable
    /// The server answered, but can't serve now: a server error or too many requests.
    case unavailable
    /// The server's journals are encrypted now and this library's aren't: encryption was turned on elsewhere, or the
    /// server was replaced by an encrypted one. Reconnecting decides which.
    case signInNeeded
    /// The server was reset and waits for a setup code.
    case serverNotSetUp
    /// The server holds another identity and doesn't know this device: restored, or set up again.
    case serverReplaced
    /// The same server refuses this device: removed from Settings ▸ Sync ▸ Devices, or its credential no longer works.
    case accessRemoved
    /// The server speaks a newer protocol or recovery format than this app.
    case appUpdateNeeded
    /// The server lacks something this app needs.
    case serverUpdateNeeded
    /// The server's certificate isn't valid, or no secure connection could be made.
    case certificateInvalid
    /// The address answers, but not as a journal server.
    case notJournalServer
    /// This device's own database is damaged, so it can't be read or written.
    case localDataUnreadable
    /// This device's own database couldn't be used right now: it is busy or locked, the device is locked, or the
    /// disk is failing or full. The data is fine, and trying again can work.
    case localDataUnavailable
    case unexpected

    public enum Kind: Equatable, Sendable { case temporary, needsYou, serverChanged, noAccess, updateOrFix, unexpected }

    public var kind: Kind {
        switch self {
        case .offline, .unreachable, .unavailable, .localDataUnavailable: return .temporary
        case .signInNeeded: return .needsYou
        case .serverNotSetUp, .serverReplaced: return .serverChanged
        case .accessRemoved: return .noAccess
        case .appUpdateNeeded, .serverUpdateNeeded, .certificateInvalid, .notJournalServer: return .updateOrFix
        case .localDataUnreadable, .unexpected: return .unexpected
        }
    }

    /// Retrying by itself can't help: only the person, or updating My Journal, can.
    public var stopsAutomaticSync: Bool {
        switch kind {
        case .needsYou, .serverChanged, .noAccess: return true
        case .updateOrFix: return self == .appUpdateNeeded
        case .temporary, .unexpected: return false
        }
    }

    /// What the person sees in Settings ▸ Sync and Sync Status. `host` adds the Tailscale hint for a `.ts.net` server.
    /// `hasPassword` is false for a library without encryption, which has no password to sign in again with: the
    /// way back after a removal is a connected device or the server's recovery code.
    public func message(host: String = "", hasPassword: Bool = true) -> String {
        let saved = "Your changes are saved on this device."
        let still = "Your journals are still on this device."
        switch self {
        case .offline:
            return "You’re offline. Your changes are saved on this device and will sync when you’re back online."
        case .unreachable:
            let tailscale =
                host.lowercased().hasSuffix(".ts.net") ? " If it uses Tailscale, turn on Tailscale on this device." : ""
            return
                "Can’t reach the server right now.\(tailscale) Your changes are saved on this device and will sync automatically."
        case .unavailable:
            return
                "The server isn’t available right now. Your changes are saved on this device and will sync automatically."
        case .signInNeeded: return "The server now uses encryption or was replaced. Reconnect to keep syncing."
        case .serverNotSetUp: return "The server isn’t set up. \(still)"
        case .serverReplaced:
            return "The server was restored or replaced and doesn’t recognize this device. \(still)"
        case .accessRemoved:
            let needed = hasPassword ? "your password or a connected device" : "a connected device or a recovery code"
            return "This device no longer has access to the server. \(still) To reconnect, you need \(needed)."
        case .appUpdateNeeded: return "Update My Journal to sync with this server. \(saved)"
        case .serverUpdateNeeded: return "The server needs an update before this device can sync. \(saved)"
        case .certificateInvalid:
            return "Can’t connect securely to the server because its certificate isn’t valid. \(saved)"
        case .notJournalServer: return "The server address doesn’t lead to a My Journal server. \(saved)"
        case .localDataUnreadable:
            return
                "My Journal can’t read your journals on this device. Nothing has been removed. To keep a copy, choose Export Archive in Settings ▸ Backup."
        case .localDataUnavailable: return "Couldn’t sync right now. My Journal will try again."
        case .unexpected: return "Couldn’t sync because of an unexpected problem. \(saved)"
        }
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive,
    ]
    private static let insecure: Set<URLError.Code> = [
        .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
        .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
        .clientCertificateRequired, .appTransportSecurityRequiresSecureConnection,
    ]
    private static let garbled: Set<URLError.Code> = [.badServerResponse, .cannotParseResponse, .zeroByteResource]

    /// The state a failed synchronization is in. The engine has already told apart what needs the server's status
    /// and identity (`SyncFailure`); the rest follows from the error.
    public init(classifying error: Error) {
        switch error {
        case let failure as SyncFailure: self = failure.health
        case let error as URLError: self = Self.health(of: error)
        case is ServerRateLimited, is ServerUnavailable, is CancellationError: self = .unavailable
        case let error as DatabaseError:
            self = LocalDataFailure(classifying: error) == .damaged ? .localDataUnreadable : .localDataUnavailable
        case JournalError.unauthorized: self = .accessRemoved
        case ServerRefusal.serverNeedsUpdate: self = .serverUpdateNeeded
        case ServerRefusal.appNeedsUpdate: self = .appUpdateNeeded
        case JournalError.unsupportedFormat, JournalError.newerVersion: self = .appUpdateNeeded
        default: self = .unexpected
        }
    }
    private static func health(of error: URLError) -> SyncHealth {
        if offlineCodes.contains(error.code) { return .offline }
        if insecure.contains(error.code) { return .certificateInvalid }
        if garbled.contains(error.code) { return .unavailable }
        return .unreachable
    }
}

/// A synchronization stopped for a reason only the server's status or identity could tell.
public struct SyncFailure: Error, Equatable, LocalizedError {
    public let health: SyncHealth
    public init(_ health: SyncHealth) { self.health = health }
    public var errorDescription: String? { health.message() }
}

/// The server failed while answering (HTTP 5xx): it's running, but can't serve this request now.
public struct ServerUnavailable: Error, LocalizedError {
    public init() {}
    public var errorDescription: String? { "The server isn’t available right now. Try again in a moment." }
}
