/// How typed setup and pairing codes look while someone types them (docs/design/connection-onboarding.md).
public enum CodeEntry {
    public enum SetupCodeProblem: Equatable { case length, characters }

    /// Formats a setup code as `ABC-DEF` when the text grows at its end, by typing or pasting, or holds a whole code,
    /// for example pasted over what was there. Other edits, such as deleting or changing a character in the middle,
    /// are left as typed so the cursor stays where it is.
    public static func setupCode(_ text: String, previous: String) -> String {
        format(text, previous: previous, group: 3, separator: "-", complete: 6)
    }
    /// Formats a pairing code as `123 456 789`, in the same way.
    public static func pairingCode(_ text: String, previous: String) -> String {
        format(text, previous: previous, group: 3, separator: " ", complete: 9)
    }
    /// The code as the server compares it: ASCII upper case without separators.
    public static func normalized(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { !separators.contains($0) }.map(upper)))
    }
    public static func setupCodeProblem(_ text: String) -> SetupCodeProblem? {
        let code = normalized(text)
        if code.count != 6 { return .length }
        return code.allSatisfy { setupAlphabet.contains($0) } ? nil : .characters
    }
    public static func pairingCodeIsComplete(_ text: String) -> Bool {
        let code = normalized(text)
        return code.count == 9 && code.allSatisfy { $0.isASCII && $0.isNumber }
    }

    static let setupAlphabet = Set("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
    private static let separators = Set(" -\t\n\r\u{2010}\u{2011}\u{2012}\u{2013}\u{2014}\u{2212}".unicodeScalars)
    private static func upper(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        ("a"..."z").contains(scalar) ? Unicode.Scalar(scalar.value - 32) ?? scalar : scalar
    }
    private static func format(
        _ text: String, previous: String, group: Int, separator: Character, complete: Int
    ) -> String {
        let code = normalized(text)
        let before = normalized(previous)
        guard (code.count > before.count && code.hasPrefix(before)) || code.count == complete else { return text }
        var formatted = ""
        for (offset, character) in code.enumerated() {
            if offset > 0 && offset % group == 0 { formatted.append(separator) }
            formatted.append(character)
        }
        return formatted
    }
}
