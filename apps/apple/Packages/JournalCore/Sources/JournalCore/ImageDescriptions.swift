import Foundation

public enum ImageDescriptionError: Error, LocalizedError, Sendable {
    case changed, unavailable, entrySaveRequired
    public var errorDescription: String? {
        switch self {
        case .changed: return "This entry has changed. Review its images again."
        case .unavailable: return "This entry is no longer available for editing."
        case .entrySaveRequired:
            return "Copy your descriptions, then close this view and save your entry before trying again."
        }
    }
}

public enum ImageDescription {
    /// An image description is one line, as Markdown alt text is: each line break becomes a space, except at the
    /// start or after a space, so the text shown is the text stored.
    public static func singleLine(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let isBreak = scalar == "\n" || scalar == "\r"
            if isBreak, result.last == " " || result.last == nil { continue }
            result.append(isBreak ? " " : scalar)
        }
        return String(result)
    }
}
