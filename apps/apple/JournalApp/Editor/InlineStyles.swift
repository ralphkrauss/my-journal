import JournalCore
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// The five inline styles that share one rule (docs/design/1-1-settings-messages-editor.md §4.2).
enum InlineStyle: CaseIterable {
    case bold
    case italic
    case underline
    case strikethrough
    case code

    init?(_ command: EditorCommand) {
        switch command {
        case .bold: self = .bold
        case .italic: self = .italic
        case .underline: self = .underline
        case .strikethrough: self = .strikethrough
        case .code: self = .code
        default: return nil
        }
    }
    var command: EditorCommand {
        switch self {
        case .bold: return .bold
        case .italic: return .italic
        case .underline: return .underline
        case .strikethrough: return .strikethrough
        case .code: return .code
        }
    }
}

/// One rule for Bold, Italic, Underline, Strikethrough and Inline Code: with a selection, the style turns on for the
/// whole selection unless every character that can carry it already has it, in which case it turns off. The state
/// a control shows and the change a command makes are computed here from the same characters, through `carries`.
@MainActor
enum InlineStyles {
    /// Whether a character with these attributes can have `style` at all. Bold is not a heading's weight (its
    /// style, F-2); no style applies to a code block's text, to a picture or to the hidden character of a rule.
    static func carries(_ style: InlineStyle, _ attributes: [NSAttributedString.Key: Any]) -> Bool {
        if attributes[.attachment] != nil || attributes[.journalMarker] != nil { return false }
        if attributes[.journalStructuredBlock] != nil { return false }
        let kind = attributes[.journalKind] as? String ?? "paragraph"
        if kind == "codeBlock" { return false }
        return style != .bold || !RichText.boldBlockKinds.contains(kind)
    }
    /// Whether a character that carries `style` has it.
    static func isOn(_ style: InlineStyle, _ attributes: [NSAttributedString.Key: Any]) -> Bool {
        switch style {
        case .bold: return traits(attributes).bold
        case .italic: return traits(attributes).italic
        case .underline: return (attributes[.underlineStyle] as? Int ?? 0) != 0
        case .strikethrough: return (attributes[.strikethroughStyle] as? Int ?? 0) != 0
        case .code: return (attributes[.journalCode] as? Int ?? 0) != 0
        }
    }
    /// Whether the style is On, Off or Mixed over the characters of `range` that carry it. Line breaks never decide.
    /// Off when no character carries it.
    static func state(_ style: InlineStyle, in text: NSAttributedString, range: NSRange) -> FormattingToggle {
        toggle(samples(style, in: text, range: range))
    }
    /// The state at a caret: what the next typed character gets. `attributes` include the block's kind.
    static func state(_ style: InlineStyle, typing attributes: [NSAttributedString.Key: Any]) -> FormattingToggle {
        guard carries(style, attributes) else { return .off }
        return isOn(style, attributes) ? .on : .off
    }
    /// Whether the command would change anything: some character of the selection (or the caret) carries the style.
    static func canApply(
        _ style: InlineStyle, in text: NSAttributedString, range: NSRange, typing: [NSAttributedString.Key: Any]
    ) -> Bool {
        if range.length == 0 { return carries(style, typing) }
        guard NSMaxRange(range) <= text.length else { return false }
        return !samples(style, in: text, range: range).isEmpty
    }
    /// The values of `isOn` over the characters of `range` that carry `style`, line breaks left out.
    private static func samples(_ style: InlineStyle, in text: NSAttributedString, range: NSRange) -> [Bool] {
        guard NSMaxRange(range) <= text.length else { return [] }
        var values: [Bool] = []
        let source = text.string as NSString
        text.enumerateAttributes(in: range) { attributes, part, _ in
            guard carries(style, attributes), !source.substring(with: part).allSatisfy(\.isNewline) else { return }
            values.append(isOn(style, attributes))
        }
        return values
    }
    private static func toggle(_ values: [Bool]) -> FormattingToggle {
        if values.isEmpty { return .off }
        if values.allSatisfy({ $0 }) { return .on }
        return values.contains(true) ? .mixed : .off
    }

    /// `selected` with the style turned on unless it is On over its carrying characters, in which case it is turned
    /// off. Characters that cannot carry it, and nothing else, are left alone. Nil when none can.
    static func toggled(_ style: InlineStyle, in selected: NSAttributedString, size: CGFloat) -> NSAttributedString? {
        let whole = NSRange(location: 0, length: selected.length)
        let values = samples(style, in: selected, range: whole)
        guard !values.isEmpty else { return nil }
        let enabled = !values.allSatisfy { $0 }
        let result = NSMutableAttributedString(attributedString: selected)
        selected.enumerateAttributes(in: whole) { attributes, part, _ in
            guard carries(style, attributes) else { return }
            apply(style, enabled: enabled, to: result, range: part, attributes: attributes, size: size)
        }
        return result
    }
    /// Typing attributes with the style toggled for the next typed text: on unless the typing style has it.
    static func toggledTyping(_ style: InlineStyle, _ typing: [NSAttributedString.Key: Any], size: CGFloat)
        -> [NSAttributedString.Key: Any]?
    {
        guard carries(style, typing) else { return nil }
        let probe = NSMutableAttributedString(string: " ", attributes: typing)
        let enabled = !isOn(style, typing)
        apply(
            style, enabled: enabled, to: probe, range: NSRange(location: 0, length: 1), attributes: typing, size: size)
        var result = typing.merging(probe.attributes(at: 0, effectiveRange: nil)) { $1 }
        if style == .code, !enabled { result[.backgroundColor] = nil }
        return result
    }

    private static func apply(
        _ style: InlineStyle, enabled: Bool, to text: NSMutableAttributedString, range: NSRange,
        attributes: [NSAttributedString.Key: Any], size: CGFloat
    ) {
        switch style {
        case .bold, .italic:
            let font = attributes[.font] as? PlatformFont ?? RichText.font(size: size)
            text.addAttribute(.font, value: toggledFont(font, style: style, enabled: enabled), range: range)
        case .underline:
            text.addAttribute(
                .underlineStyle, value: enabled ? NSUnderlineStyle.single.rawValue : 0, range: range)
        case .strikethrough:
            text.addAttribute(.strikethroughStyle, value: enabled ? 1 : 0, range: range)
        case .code:
            text.addAttribute(.journalCode, value: enabled ? 1 : 0, range: range)
            let font = attributes[.font] as? PlatformFont
            text.addAttribute(.font, value: codeFont(font, enabled: enabled, size: size), range: range)
            if enabled {
                text.addAttribute(.backgroundColor, value: BlockDecorations.codeFill, range: range)
            } else {
                text.removeAttribute(.backgroundColor, range: range)
            }
        }
    }
    /// The code font keeps the run's bold and italic, and gives back the body font when code turns off.
    static func codeFont(_ original: PlatformFont?, enabled: Bool, size: CGFloat) -> PlatformFont {
        let base =
            enabled ? PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular) : RichText.font(size: size)
        guard let original else { return base }
        #if os(macOS)
            let traits = NSFontManager.shared.traits(of: original).intersection([.boldFontMask, .italicFontMask])
            return NSFontManager.shared.convert(base, toHaveTrait: traits)
        #else
            let traits = original.fontDescriptor.symbolicTraits.intersection([.traitBold, .traitItalic])
            return UIFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor, size: size)
        #endif
    }
    private static func toggledFont(_ font: PlatformFont, style: InlineStyle, enabled: Bool) -> PlatformFont {
        #if os(macOS)
            let trait: NSFontTraitMask = style == .bold ? .boldFontMask : .italicFontMask
            return enabled
                ? NSFontManager.shared.convert(font, toHaveTrait: trait)
                : NSFontManager.shared.convert(font, toNotHaveTrait: trait)
        #else
            let trait: UIFontDescriptor.SymbolicTraits = style == .bold ? .traitBold : .traitItalic
            var traits = font.fontDescriptor.symbolicTraits
            if enabled { traits.insert(trait) } else { traits.remove(trait) }
            return UIFont(
                descriptor: font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor, size: font.pointSize)
        #endif
    }
    private static func traits(_ attributes: [NSAttributedString.Key: Any]) -> (bold: Bool, italic: Bool) {
        guard let font = attributes[.font] as? PlatformFont else { return (false, false) }
        #if os(macOS)
            let traits = NSFontManager.shared.traits(of: font)
            return (traits.contains(.boldFontMask), traits.contains(.italicFontMask))
        #else
            let traits = font.fontDescriptor.symbolicTraits
            return (traits.contains(.traitBold), traits.contains(.traitItalic))
        #endif
    }
}
