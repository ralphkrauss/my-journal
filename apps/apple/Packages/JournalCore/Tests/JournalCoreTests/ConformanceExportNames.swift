import Foundation

/// The inputs of protocol/conformance/markdown-export/names-v1.json. The characters are chosen from stable parts of
/// Unicode, so another platform's older or newer tables agree about them.
enum ConformanceExportNames {
    static let safe: [(input: String, fallback: String, note: String)] = [
        ("Morning pages", "Untitled", "Ordinary text is unchanged."),
        ("Work: Q4/Plans?", "Untitled", "Characters unsafe on Windows, macOS or Linux become hyphens."),
        ("#tag [draft] ^1 | a\\b", "Untitled", "Characters Obsidian rejects, and a backslash."),
        ("\"quoted\" <b> *star*", "Untitled", "Quotes, angle brackets and an asterisk."),
        ("..hidden.", "Untitled", "Leading dots and trailing dots are trimmed."),
        ("  spaced  ", "Untitled", "Surrounding spaces are trimmed."),
        ("name. . ", "Untitled", "Trailing dots and spaces are trimmed, in any mix."),
        ("  \n ", "Untitled", "Nothing left: the fallback."),
        ("", "Untitled Journal", "An empty name uses the fallback it is given."),
        ("Line one\nline two\tTabbed", "Untitled", "Line breaks and tabs become spaces."),
        ("a\u{0007}b\u{007F}c", "Untitled", "Control characters become hyphens."),
        (
            "odd\u{FFFF}\u{FFFE}\u{1FFFF}\u{0378}", "Untitled",
            "Noncharacters and unassigned code points become hyphens."
        ),
        ("gpj\u{202E}.exe", "Untitled", "A direction override could disguise the name."),
        ("a\u{2066}b\u{2069}", "Untitled", "Direction isolates too."),
        ("CON", "Untitled", "A Windows device name gets a hyphen."),
        ("nul", "Untitled", "In any letter case."),
        ("Lpt9", "Untitled", "LPT1 to LPT9."),
        ("COM¹", "Untitled", "And the superscript forms."),
        ("com1.notes", "Untitled", "The part before the first dot is what Windows reads."),
        ("CON.txt", "Untitled", "So CON.txt is a device too."),
        ("console", "Untitled", "A longer name that only starts with a device name is fine."),
        ("COM0", "Untitled", "COM0 is not reserved."),
        ("Cafe\u{0301}", "Untitled", "Names are normalized to NFC."),
        ("Straße", "Untitled", "Case is kept; only comparison folds it."),
        (String(repeating: "a", count: 99), "Untitled", "At most 60 characters."),
        (
            String(repeating: "日記", count: 80), "Untitled",
            "Sixty characters would be 180 bytes; 120 bytes is the limit."
        ),
        (
            String(repeating: "👩\u{200D}👩\u{200D}👧\u{200D}👦", count: 40), "Untitled",
            "Cut between whole characters, never inside one."
        ),
        (String(repeating: "b", count: 59) + " . ", "Untitled", "Trimmed again after the cut."),
    ]

    /// Names claimed one after another within one folder.
    static let unique: [(note: String, names: [String])] = [
        ("The same name three times.", ["Paris", "Paris", "Paris"]),
        ("Letter case is ignored.", ["Trips", "trips", "TRIPS"]),
        ("Full case folding, as APFS does.", ["Straße", "STRASSE", "strasse"]),
        ("Ligatures fold too.", ["ﬀ", "FF"]),
        ("Final sigma.", ["ς", "Σ"]),
        ("Unicode form is ignored.", ["Café", "Cafe\u{0301}"]),
        ("A number already taken is numbered again.", ["Name", "Name 2", "Name"]),
        ("A numbered name that exists first.", ["Name 2", "Name", "Name"]),
    ]

    static let yaml: [(input: String, note: String)] = [
        ("Morning pages", "Double-quoted."),
        ("A \"quote\" \\ and\nnew\tline", "Quote, backslash, line feed, tab."),
        ("cr\rhere", "Carriage return."),
        ("bell\u{0007} and \u{0000}", "Control characters as \\uXXXX."),
        ("x\u{FFFF}\u{10FFFF}", "Noncharacters: \\u above U+FFFF becomes \\U."),
        ("line\u{2028}sep\u{2029}para\u{0085}next", "U+2028, U+2029 and U+0085."),
        ("Café 🌿 日記", "Everything else is written as it is."),
        ("", "An empty string."),
    ]

    static let headings: [(input: String, note: String)] = [
        ("Morning pages", "Plain text is unchanged."),
        (
            "*Draft* #1 [x] <b> & co &amp; ![i]",
            "Formatting characters are escaped; & only before a letter or #; ! only before [."
        ),
        ("1. Not a list", "A number and a dot are not escaped inside the line."),
        ("- Not a bullet", "A hyphen is not escaped inside the line."),
        ("a_b ~c~ `d` e|f \\g", "Underscore, tilde, backtick, pipe and backslash."),
        ("Two\nlines", "Always one line."),
        ("Ends with #", "A trailing hash."),
    ]

    /// An instant, a fixed offset in minutes from UTC, then the values the export writes for them.
    static let dates: [(instant: String, offsetMinutes: Int)] = [
        ("2026-10-05T05:12:00Z", 120), ("2026-10-04T22:30:00Z", 120), ("2026-10-04T22:30:00Z", 0),
        ("2026-10-05T01:00:00Z", -300), ("2026-10-05T20:00:00Z", 330), ("2026-01-01T00:00:00Z", -570),
        ("2026-12-31T23:59:59Z", 840),
    ]
}
