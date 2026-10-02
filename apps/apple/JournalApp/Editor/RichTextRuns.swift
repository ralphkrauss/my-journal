import JournalCore
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

extension RichText {
    static func readRuns(_ text: NSAttributedString, range: NSRange, kind: String) -> [TextRun] {
        var runs: [TextRun] = []
        text.enumerateAttributes(in: range) { attrs, range, _ in
            if attrs[.attachment] != nil, let data = attrs[.journalInlineImage] as? Data,
                let run = try? JournalCoding.decoder().decode(TextRun.self, from: data)
            {
                runs.append(run)
                return
            }
            var value = (text.string as NSString).substring(with: range)
            if attrs[.attachment] != nil {
                // An attachment that isn't a journal image, such as one pasted from elsewhere, is never saved as
                // an object replacement character; the editor imports its image separately.
                value = value.replacingOccurrences(of: "\u{FFFC}", with: "")
                if value.isEmpty { return }
            }
            let font = attrs[.font] as? PlatformFont
            #if os(macOS)
                let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
                let bold = traits.contains(.boldFontMask), italic = traits.contains(.italicFontMask)
            #else
                let traits = font?.fontDescriptor.symbolicTraits ?? []
                let bold = traits.contains(.traitBold), italic = traits.contains(.traitItalic)
            #endif
            var run = TextRun(
                value,
                bold: bold && !RichText.boldBlockKinds.contains(kind),
                italic: italic, underline: (attrs[.underlineStyle] as? Int ?? 0) != 0,
                link: (attrs[.link] as? URL)?.absoluteString ?? attrs[.link] as? String ?? attrs[.journalInertLink]
                    as? String)
            run.strikethrough = (attrs[.strikethroughStyle] as? Int ?? 0) != 0
            run.code = (attrs[.journalCode] as? Int ?? 0) != 0
            run.linkTitle = attrs[.journalLinkTitle] as? String
            run.rawHTML = attrs[.journalRawHTML] as? Bool == true
            let parts = run.text.components(separatedBy: "\u{2028}")
            for (index, part) in parts.enumerated() {
                if index > 0 {
                    var lineBreak = run
                    lineBreak.text = "\n"
                    lineBreak.breakKind = attrs[.journalBreakKind] as? String ?? "hard"
                    runs.append(lineBreak)
                }
                if !part.isEmpty {
                    run.text = part
                    append(run, to: &runs)
                }
            }
        }
        return runs
    }
    private static func append(_ run: TextRun, to runs: inout [TextRun]) {
        if let last = runs.last, last.imageSource == nil, run.imageSource == nil, last.code == run.code,
            last.strikethrough == run.strikethrough,
            last.bold == run.bold, last.italic == run.italic, last.underline == run.underline,
            last.link == run.link, last.linkTitle == run.linkTitle, last.rawHTML == run.rawHTML, last.breakKind == nil
        {
            runs[runs.count - 1].text += run.text
        } else {
            runs.append(run)
        }
    }
}

#if os(macOS)
    extension RichText {
        private static let headings: Set<String> = [
            "heading", "subheading", "heading3", "heading4", "heading5", "heading6",
        ]
        /// Toggles bold, italic or underline per run, so each run keeps its own size and other traits.
        /// The style turns on unless every run it applies to already has it; headings are always bold.
        static func toggling(_ command: EditorCommand, in text: NSAttributedString) -> NSAttributedString {
            let result = NSMutableAttributedString(attributedString: text)
            let whole = NSRange(location: 0, length: result.length)
            var applicable = false
            var allOn = true
            result.enumerateAttributes(in: whole) { attributes, _, _ in
                guard let on = state(of: command, in: attributes) else { return }
                applicable = true
                allOn = allOn && on
            }
            guard applicable else { return result }
            result.enumerateAttributes(in: whole) { attributes, range, _ in
                guard state(of: command, in: attributes) != nil else { return }
                result.addAttributes(setting(command, on: !allOn, in: attributes, size: nil), range: range)
            }
            return result
        }
        static func toggling(_ command: EditorCommand, in typing: [NSAttributedString.Key: Any], size: CGFloat)
            -> [NSAttributedString.Key: Any]
        {
            guard let on = state(of: command, in: typing) else { return typing }
            return typing.merging(setting(command, on: !on, in: typing, size: size)) { $1 }
        }
        private static func state(of command: EditorCommand, in attributes: [NSAttributedString.Key: Any]) -> Bool? {
            let font = attributes[.font] as? NSFont
            let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
            switch command {
            case .bold:
                if headings.contains(attributes[.journalKind] as? String ?? "") { return nil }
                return traits.contains(.boldFontMask)
            case .italic: return traits.contains(.italicFontMask)
            case .underline: return (attributes[.underlineStyle] as? Int ?? 0) != 0
            default: return nil
            }
        }
        private static func setting(
            _ command: EditorCommand, on: Bool, in attributes: [NSAttributedString.Key: Any], size: CGFloat?
        ) -> [NSAttributedString.Key: Any] {
            if case .underline = command { return [.underlineStyle: on ? NSUnderlineStyle.single.rawValue : 0] }
            let trait: NSFontTraitMask = {
                if case .bold = command { return .boldFontMask }
                return .italicFontMask
            }()
            let font = attributes[.font] as? NSFont ?? RichText.font(size: size ?? NSFont.systemFontSize)
            let manager = NSFontManager.shared
            return [
                .font: on ? manager.convert(font, toHaveTrait: trait) : manager.convert(font, toNotHaveTrait: trait)
            ]
        }
    }
#endif
