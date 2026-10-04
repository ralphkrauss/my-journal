import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// List items and quotes hold only their text (docs/design/list-markers-2026-10-03.md). Assistive technologies learn
/// what they are from accessibility text attributes on that text, never from characters in it. The attributes are
/// part of the paragraph's own attributes, so the text views hand them on to VoiceOver with the text: on the Mac the
/// list item attributes AppKit defines for this, the item's prefix and its nesting level; on iPhone and iPad a custom
/// text attribute. Quotes carry a custom text attribute on both.
enum ListAccessibility {
    /// The attributes that tell assistive technologies what a paragraph is; they belong to the whole paragraph.
    static var keys: [NSAttributedString.Key] {
        #if os(macOS)
            [.accessibilityListItemPrefix, .accessibilityListItemLevel, .accessibilityCustomText]
        #else
            [.accessibilityTextCustom]
        #endif
    }

    /// What VoiceOver is told a paragraph of `kind` is, in words; nil for other paragraphs.
    static func announcement(kind: String, number: Int?) -> String? {
        switch kind {
        case "bullet": return "Bullet"
        case "numbered": return "\(number ?? 1)."
        case "task": return "Checkbox, unchecked"
        case "checked": return "Checkbox, checked"
        case "quote": return "Quote"
        default: return nil
        }
    }

    /// Gives the numbered item in `range` its number for assistive technologies too.
    static func renumber(_ text: NSMutableAttributedString, range: NSRange, number: Int) {
        let announcement = "\(number)."
        #if os(macOS)
            text.addAttribute(
                .accessibilityListItemPrefix, value: NSAttributedString(string: announcement), range: range)
        #else
            text.addAttribute(.accessibilityTextCustom, value: [announcement], range: range)
        #endif
    }

    /// The accessibility attributes of a paragraph of `kind`, `level` lists deep.
    static func attributes(kind: String, number: Int? = nil, level: Int = 0) -> [NSAttributedString.Key: Any] {
        guard let announcement = announcement(kind: kind, number: number) else { return [:] }
        #if os(macOS)
            if kind == "quote" { return [.accessibilityCustomText: [announcement]] }
            // A bullet as the character itself, as AppKit asks; a number as written; a checkbox in words.
            return [
                .accessibilityListItemPrefix: NSAttributedString(string: kind == "bullet" ? "•" : announcement),
                .accessibilityListItemLevel: level,
            ]
        #else
            return [.accessibilityTextCustom: [announcement]]
        #endif
    }
}
