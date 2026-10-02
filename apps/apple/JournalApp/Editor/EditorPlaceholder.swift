import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// The empty body's placeholder as real text, laid out with the body's font, paragraph style and line height, so it
/// wraps as typed body text would: “Start writing…”, or “Start writing or ” and the link “[template symbol] use a
/// template” (docs/design/new-entry-template-suggestion.md).
@MainActor
enum PlaceholderText {
    static let plain = "Start writing…"
    static let prefix = "Start writing or "
    static let link = "use a template"
    static let symbol = "doc.on.doc"

    /// The text and the range of the link. The link is kept on one line, and breaks between its words only when it
    /// is wider than `width` on its own.
    static func make(
        size: CGFloat, offersTemplate: Bool, width: CGFloat, placeholder: PlatformColor, link: PlatformColor
    ) -> (text: NSAttributedString, link: NSRange?) {
        var body = RichText.attributes(kind: "paragraph", size: size)
        body[.foregroundColor] = placeholder
        // Lines exactly as tall as typed body text's: the symbol reaches a little above the font's ascender, which
        // would otherwise make its line taller and move the baseline down.
        if let font = body[.font] as? PlatformFont, let style = body[.paragraphStyle] as? NSParagraphStyle,
            let fixed = style.mutableCopy() as? NSMutableParagraphStyle
        {
            fixed.minimumLineHeight = lineHeight(of: font)
            fixed.maximumLineHeight = lineHeight(of: font)
            body[.paragraphStyle] = fixed
        }
        guard offersTemplate else { return (NSAttributedString(string: plain, attributes: body), nil) }
        let together = linkRun(body: body, color: link, separator: "\u{00A0}")
        let run = together.size().width <= width ? together : linkRun(body: body, color: link, separator: " ")
        let text = NSMutableAttributedString(string: prefix, attributes: body)
        let range = NSRange(location: text.length, length: run.length)
        text.append(run)
        return (text, range)
    }

    /// The symbol, sized with the body font and centred on its capitals, then the underlined words.
    private static func linkRun(
        body: [NSAttributedString.Key: Any], color: PlatformColor, separator: String
    ) -> NSAttributedString {
        var attributes = body
        attributes[.foregroundColor] = color
        let run = NSMutableAttributedString()
        if let font = body[.font] as? PlatformFont, let image = symbolImage(font: font, color: color) {
            // A symbol image carries its own baseline, which text layout honours: set with the body font it sits on
            // the baseline and centres on the capitals as in Notes and Mail, without offsets of its own.
            let attachment = attachment(for: image)
            run.append(NSAttributedString(attachment: attachment))
            run.addAttributes(attributes, range: NSRange(location: 0, length: run.length))
            run.append(NSAttributedString(string: "\u{00A0}", attributes: attributes))
        }
        var words = attributes
        words[.underlineStyle] = NSUnderlineStyle.single.rawValue
        run.append(NSAttributedString(string: link.replacingOccurrences(of: " ", with: separator), attributes: words))
        return run
    }

    /// The line height typed text in this font gets.
    private static func lineHeight(of font: PlatformFont) -> CGFloat {
        #if os(macOS)
            NSLayoutManager().defaultLineHeight(for: font)
        #else
            font.lineHeight
        #endif
    }

    private static func attachment(for symbol: PlatformImage) -> NSTextAttachment {
        #if os(macOS)
            // AppKit places an attachment's bottom on the baseline; the symbol's alignment rectangle says where its
            // own baseline is.
            let attachment = NSTextAttachment()
            attachment.image = symbol
            attachment.bounds = CGRect(
                x: 0, y: -symbol.alignmentRect.minY, width: symbol.size.width, height: symbol.size.height)
            return attachment
        #else
            return NSTextAttachment(image: symbol)
        #endif
    }

    private static func symbolImage(font: PlatformFont, color: PlatformColor) -> PlatformImage? {
        #if os(macOS)
            let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular, scale: .small)
                .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
            return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        #else
            let configuration = UIImage.SymbolConfiguration(font: font, scale: .small)
            return UIImage(systemName: symbol, withConfiguration: configuration)?
                .withTintColor(color, renderingMode: .alwaysOriginal)
        #endif
    }
}

#if os(macOS)
    /// Draws the placeholder text; never the target of a click or of VoiceOver, which reach the link's button.
    final class PlaceholderTextView: NSTextView {
        convenience init() {
            self.init(frame: .zero)
            isEditable = false
            isSelectable = false
            drawsBackground = false
            textContainerInset = .zero
            setAccessibilityElement(false)
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// The link's glyphs, in this view's coordinates.
        func rect(of range: NSRange) -> NSRect? {
            guard let layout = layoutManager, let container = textContainer else { return nil }
            layout.ensureLayout(for: container)
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            return layout.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(
                dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        }
    }

    extension NativeEditor.Coordinator {
        /// Shows the placeholder while the body is empty, laid out exactly where body text would be; the link's
        /// transparent button covers only the link's glyphs.
        func showSuggestion(_ content: AnyView?) {
            guard let view else { return }
            if placeholder.superview !== view { view.addSubview(placeholder) }
            let empty = view.string.isEmpty && parent.document.imageBlocks.isEmpty
            placeholder.isHidden = !empty
            if let content, empty {
                if let suggestionHost {
                    suggestionHost.rootView = content
                } else {
                    let host = NSHostingView(rootView: content)
                    host.sceneBridgingOptions = []
                    view.addSubview(host)
                    view.accessoryViews = [host]
                    suggestionHost = host
                }
                suggestionHost?.isHidden = false
            } else {
                suggestionHost?.isHidden = true
            }
            placeSuggestion()
            orderKeyViews()
        }
        func placeSuggestion() {
            guard let view, !placeholder.isHidden, let container = view.textContainer else { return }
            let origin = view.textContainerOrigin
            let width = max(0, view.bounds.width - 2 * origin.x)
            placeholder.textContainer?.lineFragmentPadding = container.lineFragmentPadding
            let offered = suggestionHost.map { !$0.isHidden } ?? false
            let (text, link) = PlaceholderText.make(
                size: parent.fontSize, offersTemplate: offered, width: width - 2 * container.lineFragmentPadding,
                placeholder: .placeholderTextColor, link: .secondaryLabelColor)
            placeholder.textStorage?.setAttributedString(text)
            placeholder.frame = NSRect(x: origin.x, y: origin.y, width: width, height: 0)
            placeholder.sizeToFit()
            placeholder.frame.size.width = width
            guard let host = suggestionHost, offered, let link, let glyphs = placeholder.rect(of: link) else { return }
            host.frame = glyphs.offsetBy(dx: placeholder.frame.minX, dy: placeholder.frame.minY)
        }
        /// With Keyboard Navigation on, Tab goes title → link → body, and Shift-Tab back.
        func orderKeyViews() {
            guard let view, let title = Self.titleField(in: view.window?.contentView) else { return }
            if let host = suggestionHost, !host.isHidden, let link = Self.button(in: host) {
                title.nextKeyView = link
                link.nextKeyView = view
            } else if title.nextKeyView !== view {
                title.nextKeyView = view
            }
        }
        private static func titleField(in root: NSView?) -> NSView? {
            guard let root else { return nil }
            if root is TitleTextField { return root }
            for child in root.subviews {
                if let found = titleField(in: child) { return found }
            }
            return nil
        }
        private static func button(in root: NSView) -> NSButton? {
            if let button = root as? NSButton { return button }
            for child in root.subviews {
                if let found = button(in: child) { return found }
            }
            return nil
        }
    }
#else
    /// Draws the placeholder text with TextKit 1, as the body editor does; never touched or read by VoiceOver, which
    /// reaches the link's button.
    final class PlaceholderTextView: UITextView {
        /// A text view made with its own TextKit 1 objects doesn't keep the text storage alive.
        private var ownedStorage: NSTextStorage?

        convenience init() {
            let storage = NSTextStorage()
            let layout = NSLayoutManager()
            storage.addLayoutManager(layout)
            let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
            container.widthTracksTextView = true
            layout.addTextContainer(container)
            self.init(frame: .zero, textContainer: container)
            ownedStorage = storage
            isEditable = false
            isSelectable = false
            isScrollEnabled = false
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            backgroundColor = .clear
            textContainerInset = .zero
        }

        /// The link's glyphs, in this view's coordinates.
        func rect(of range: NSRange) -> CGRect {
            layoutManager.ensureLayout(for: textContainer)
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            return layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        }
    }
#endif
