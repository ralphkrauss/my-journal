import Foundation

/// What the rating request decides with, kept only on this device in the app's own preferences
/// (docs/design/about-and-ratings-2026-10-05.md §3). No journal content; nothing is synced or sent.
struct ReviewUsage: Codable, Equatable {
    /// When this device first used the app.
    var firstUse: Date
    /// Calendar days on which the person's own edits to an entry were saved.
    var writingDays = 0
    /// The last of those days, so a day is counted once.
    var lastWritingDay: String?
    /// The app version during which the system was last asked for a rating, and when.
    var lastRequestVersion: String?
    var lastRequest: Date?

    /// Counts the day of `date` as a writing day, once.
    mutating func recordWriting(at date: Date, calendar: Calendar) {
        let day = Self.dayKey(date, calendar: calendar)
        guard day != lastWritingDay else { return }
        lastWritingDay = day
        writingDays += 1
    }

    /// The local calendar day, such as "2026-10-5".
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

/// When the system may be asked for a rating, apart from the moment itself (ReviewRequests).
enum ReviewRequestRules {
    static let minimumAge: TimeInterval = 7 * 24 * 60 * 60
    static let minimumWritingDays = 4
    static let minimumInterval: TimeInterval = 120 * 24 * 60 * 60

    /// After a week of use and writing on four days, in a session without problems, never twice in one version and
    /// not within 120 days of the last request.
    static func allow(_ usage: ReviewUsage?, version: String, problemThisSession: Bool, now: Date) -> Bool {
        guard let usage, !problemThisSession else { return false }
        guard now.timeIntervalSince(usage.firstUse) >= minimumAge, usage.writingDays >= minimumWritingDays else {
            return false
        }
        guard usage.lastRequestVersion != version else { return false }
        if let last = usage.lastRequest, now.timeIntervalSince(last) < minimumInterval { return false }
        return true
    }
}

/// Where the usage is kept: the app's preferences, or memory for tests and debug runs.
@MainActor final class ReviewUsageStore {
    static let defaultsKey = "ReviewRequestUsage"
    private let read: () -> Data?
    private let write: (Data) -> Void

    private init(read: @escaping () -> Data?, write: @escaping (Data) -> Void) {
        self.read = read
        self.write = write
    }

    static func preferences(_ defaults: UserDefaults = .standard) -> ReviewUsageStore {
        ReviewUsageStore(
            read: { defaults.data(forKey: defaultsKey) },
            write: { defaults.set($0, forKey: defaultsKey) })
    }

    static func memory(_ initial: ReviewUsage? = nil) -> ReviewUsageStore {
        final class Box {
            var data: Data?
        }
        let box = Box()
        box.data = initial.flatMap { try? JSONEncoder().encode($0) }
        return ReviewUsageStore(read: { box.data }, write: { box.data = $0 })
    }

    var usage: ReviewUsage? {
        get { read().flatMap { try? JSONDecoder().decode(ReviewUsage.self, from: $0) } }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else { return }
            write(data)
        }
    }

    /// The usage, started now if this device has none yet.
    func current(now: Date) -> ReviewUsage {
        if let usage { return usage }
        let started = ReviewUsage(firstUse: now)
        usage = started
        return started
    }
}
