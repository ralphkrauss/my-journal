import Foundation

/// Journal positions (docs/design/journal-order.md, "Representation"): a rank string per journal, compared byte by
/// byte. A rank is a base-62 fraction written with the digits `0-9`, `A-Z`, `a-z` in ASCII order: 1 to 64 of them,
/// never ending in `0`, so there is always room between two ranks and each fraction has one spelling.
public enum JournalRanks {
    static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8)
    static let base = 62
    /// The longest rank. A move that would need a longer one spaces every journal again instead.
    public static let longest = 64

    public static func isValid(_ rank: String) -> Bool {
        let bytes = Array(rank.utf8)
        guard (1...longest).contains(bytes.count), bytes.last != UInt8(ascii: "0") else { return false }
        return bytes.allSatisfy { digit($0) != nil }
    }
    /// Whether `first` sorts before `second`: plain byte order, the same on every device and platform.
    public static func precedes(_ first: String, _ second: String) -> Bool {
        Array(first.utf8).lexicographicallyPrecedes(Array(second.utf8))
    }
    /// A valid rank strictly between two valid ranks; nil bounds are the start and the end. Nil when `lower` doesn't
    /// precede `upper`, or when the rank would be longer than `longest`. The reference algorithm takes the midpoint
    /// of the two fractions, adding a digit only when they are adjacent; other clients may choose any rank between.
    public static func between(_ lower: String?, _ upper: String?) -> String? {
        let low = lower.map(digits) ?? []
        let high = upper.map(digits)
        if let high, !low.lexicographicallyPrecedes(high) { return nil }
        let rank = midpoint(low, high)
        guard rank.count <= longest else { return nil }
        return text(rank)
    }
    /// The rank of position `index` of `count` journals spaced evenly, for journals ranked automatically when none is
    /// ranked yet: two devices with the same journals in the same order compute the same ranks.
    public static func spaced(_ index: Int, count: Int) -> String {
        var width = 1
        var capacity = base
        // One digit more than the count needs, so the ranks leave room between them.
        while capacity / base < count + 1 {
            width += 1
            capacity *= base
        }
        var value = (index + 1) * capacity / (count + 1)
        var rank: [Int] = []
        for _ in 0..<width {
            rank.insert(value % base, at: 0)
            value /= base
        }
        while rank.last == 0 { rank.removeLast() }
        return text(rank)
    }
    /// `journals` in the order shown: those with a valid rank by rank (then by lower-case ID), then the others by
    /// name, as before journals could be moved.
    public static func arranged(_ journals: [JournalItem], ranks: [UUID: String]) -> [JournalItem] {
        var ranked: [(journal: JournalItem, rank: String)] = []
        var unranked: [JournalItem] = []
        for journal in journals {
            if let rank = ranks[journal.id], isValid(rank) {
                ranked.append((journal, rank))
            } else {
                unranked.append(journal)
            }
        }
        ranked.sort { first, second in
            first.rank == second.rank
                ? first.journal.id.uuidString.lowercased() < second.journal.id.uuidString.lowercased()
                : precedes(first.rank, second.rank)
        }
        unranked.sort { first, second in
            let order = first.title.localizedStandardCompare(second.title)
            return order == .orderedSame
                ? first.id.uuidString.lowercased() < second.id.uuidString.lowercased() : order == .orderedAscending
        }
        return ranked.map(\.journal) + unranked
    }

    private static func digit(_ byte: UInt8) -> Int? { alphabet.firstIndex(of: byte) }
    private static func digits(_ rank: String) -> [Int] { rank.utf8.compactMap(digit) }
    private static func text(_ digits: [Int]) -> String { String(decoding: digits.map { alphabet[$0] }, as: UTF8.self) }
    /// The midpoint of two fractions given as digits, `low` < `high`; a nil `high` is 1.
    private static func midpoint(_ low: [Int], _ high: [Int]?) -> [Int] {
        if let high {
            var shared = 0
            while shared < high.count, (shared < low.count ? low[shared] : 0) == high[shared] { shared += 1 }
            if shared > 0 {
                return Array(high[..<shared]) + midpoint(Array(low.dropFirst(shared)), Array(high.dropFirst(shared)))
            }
        }
        let first = low.first ?? 0
        let last = high?.first ?? base
        if last - first > 1 { return [(first + last) / 2] }
        if let high, high.count > 1 { return [high[0]] }
        return [first] + midpoint(Array(low.dropFirst()), nil)
    }
}
