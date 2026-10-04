import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Quote bars, horizontal rules and code block backgrounds, drawn behind the text of the visible blocks.
/// They are presentation only: the text keeps its Markdown structure and they never take clicks.
@MainActor enum BlockDecorations {
    enum Kind { case quoteBar, rule, codeBackground }
    struct Shape {
        let kind: Kind
        let rect: CGRect
    }

    static let quoteIndent: CGFloat = 18
    static let codeInset: CGFloat = 10

    static var quoteColor: PlatformColor {
        #if os(macOS)
            .tertiaryLabelColor
        #else
            .tertiaryLabel
        #endif
    }
    static var ruleColor: PlatformColor {
        #if os(macOS)
            .separatorColor
        #else
            .separator
        #endif
    }
    static var codeFill: PlatformColor {
        #if os(macOS)
            .quaternaryLabelColor
        #else
            .tertiarySystemFill
        #endif
    }

    /// `blockWidth` is the width tables and images are laid out at, so every block shares one column.
    static func shapes(
        storage: NSTextStorage, layout: NSLayoutManager, container: NSTextContainer, origin: CGPoint, visible: CGRect,
        blockWidth: CGFloat
    ) -> [Shape] {
        guard storage.length > 0 else { return [] }
        let area = visible.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = layout.glyphRange(forBoundingRect: area, in: container)
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let paragraphs = (storage.string as NSString).paragraphRange(for: characters)
        var result: [Shape] = []
        storage.enumerateAttribute(.journalBlockID, in: paragraphs) { value, range, _ in
            guard value != nil,
                let kind = storage.attribute(.journalKind, at: range.location, effectiveRange: nil)
                    as? String
            else { return }
            guard
                let used = usedRect(of: range, layout: layout, container: container, quote: kind == "quote")?.offsetBy(
                    dx: origin.x, dy: origin.y)
            else { return }
            let left = origin.x + container.lineFragmentPadding
            let width = min(blockWidth, container.size.width - 2 * container.lineFragmentPadding)
            switch kind {
            case "quote":
                result.append(
                    Shape(
                        kind: .quoteBar, rect: CGRect(x: left + 2, y: used.minY + 1, width: 3, height: used.height - 2))
                )
            case "rule":
                result.append(Shape(kind: .rule, rect: CGRect(x: left, y: used.midY, width: width, height: 0)))
            case "codeBlock", "html":
                result.append(
                    Shape(
                        kind: .codeBackground,
                        rect: CGRect(x: left, y: used.minY - 6, width: width, height: used.height + 12)))
            default:
                break
            }
        }
        return result
    }

    private static func usedRect(
        of range: NSRange, layout: NSLayoutManager, container: NSTextContainer, quote: Bool
    ) -> CGRect? {
        // Trailing line breaks (block separators, a code block's final newline) add no visible line.
        let text = layout.textStorage?.string as NSString? ?? ""
        var content = range
        while content.length > 0, text.character(at: NSMaxRange(content) - 1) == 0x0A { content.length -= 1 }
        // An empty quote line has only its line break, whose line the bar covers.
        if content.length == 0, range.length > 0, quote { content.length = 1 }
        let glyphs = layout.glyphRange(forCharacterRange: content, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        var result: CGRect?
        layout.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, _, _ in
            result = result.map { $0.union(used) } ?? used
        }
        return result
    }

    static func draw(_ shapes: [Shape], scale: CGFloat) {
        for shape in shapes {
            switch shape.kind {
            case .quoteBar:
                quoteColor.setFill()
                path(roundedRect: shape.rect, radius: 1.5).fill()
            case .rule:
                ruleColor.setFill()
                let line = 1 / max(1, scale)
                fill(
                    CGRect(
                        x: shape.rect.minX, y: (shape.rect.minY * scale).rounded() / scale, width: shape.rect.width,
                        height: line))
            case .codeBackground:
                codeFill.setFill()
                path(roundedRect: shape.rect, radius: 6).fill()
            }
        }
    }
    #if os(macOS)
        private static func path(roundedRect rect: CGRect, radius: CGFloat) -> NSBezierPath {
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        }
        private static func fill(_ rect: CGRect) { rect.fill() }
    #else
        private static func path(roundedRect rect: CGRect, radius: CGFloat) -> UIBezierPath {
            UIBezierPath(roundedRect: rect, cornerRadius: radius)
        }
        private static func fill(_ rect: CGRect) { UIRectFill(rect) }
    #endif
}

#if os(iOS)
    /// Sits below the text view's text so decorations never cover glyphs or take touches.
    final class BlockDecorationView: UIView {
        weak var host: JournalTextView?
        override init(frame: CGRect) {
            super.init(frame: frame)
            isOpaque = false
            backgroundColor = .clear
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { nil }
        override func draw(_ rect: CGRect) {
            guard let host else { return }
            let origin = CGPoint(x: host.textContainerInset.left, y: host.textContainerInset.top)
            let shapes = BlockDecorations.shapes(
                storage: host.textStorage, layout: host.layoutManager, container: host.textContainer, origin: origin,
                visible: frame, blockWidth: max(40, host.bounds.width - 20))
            guard let context = UIGraphicsGetCurrentContext() else { return }
            context.translateBy(x: -frame.minX, y: -frame.minY)
            BlockDecorations.draw(shapes, scale: traitCollection.displayScale)
        }
    }
#endif
