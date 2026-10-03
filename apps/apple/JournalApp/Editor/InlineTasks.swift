import SwiftUI

#if os(macOS)
    import AppKit
    private typealias TaskButton = NSButton
#else
    import UIKit
    private typealias TaskButton = ChecklistBox
#endif

/// Checkboxes remain native controls; activating one mutates the same document and undo history as typing. Only the
/// checklist items on screen have one, and the same controls move along as the text changes: making new ones for every
/// keystroke made typing lag in entries with checklists (docs/design/checklists-2026-10-03.md).
@MainActor final class InlineTasks {
    private weak var host: JournalTextView?
    private var buttons: [TaskButton] = []
    private let toggle: (NSRange) -> Void
    init(host: JournalTextView, toggle: @escaping (NSRange) -> Void) {
        self.host = host
        self.toggle = toggle
    }

    /// Where one item's checkbox goes, in the text view's coordinates.
    struct Placement {
        /// The start of the item's list column, where the box is drawn.
        var boxX: CGFloat
        /// The first line's baseline.
        var baseline: CGFloat
        /// Where the item's text, and its wrapped lines, start.
        var textX: CGFloat
        /// The item's paragraph font at its size.
        var font: PlatformFont
        /// The middle of the first line's capital letters, which the box is centred on.
        var capCenter: CGFloat { baseline - font.capHeight / 2 }
    }

    /// The height of a checkbox's touch area on iPhone and iPad, centred on the box: 44 points, and more at large
    /// text sizes, where the box itself is taller.
    static let touchHeight: CGFloat = 44
    static func touchHeight(for font: PlatformFont) -> CGFloat { max(touchHeight, (font.pointSize * 1.3).rounded(.up)) }

    func synchronize(editable: Bool) {
        guard let host else { return }
        #if os(macOS)
            guard let storage = host.textStorage, let layout = host.layoutManager, let container = host.textContainer
            else { return }
            let origin = host.textContainerOrigin
            let visible = host.visibleRect
        #else
            let storage = host.textStorage
            let layout = host.layoutManager
            let container = host.textContainer
            let origin = CGPoint(x: host.textContainerInset.left, y: host.textContainerInset.top)
            let visible = host.bounds
        #endif
        let items = Self.items(
            in: visible.insetBy(dx: 0, dy: -Self.touchHeight), storage: storage, layout: layout, container: container,
            origin: origin)
        for (index, item) in items.enumerated() {
            let button = index < buttons.count ? buttons[index] : makeButton()
            button.tag = item.location
            #if os(macOS)
                button.controlSize =
                    item.placement.font.pointSize < 14 ? .small : item.placement.font.pointSize > 20 ? .large : .regular
                let height = button.cell?.cellSize.height ?? 16
                button.frame = CGRect(
                    x: item.placement.boxX, y: item.placement.capCenter - height / 2,
                    width: max(height, item.placement.textX - item.placement.boxX), height: height)
                button.state = item.checked ? .on : .off
                button.setAccessibilityLabel(item.label)
                button.isEnabled = editable
            #else
                let previous = index > 0 ? items[index - 1].placement.capCenter : nil
                let next = index + 1 < items.count ? items[index + 1].placement.capCenter : nil
                button.show(
                    item,
                    touch: Self.touchRange(
                        around: item.placement.capCenter, height: Self.touchHeight(for: item.placement.font),
                        previous: previous, next: next),
                    editable: editable)
            #endif
        }
        for button in buttons.dropFirst(items.count) { button.removeFromSuperview() }
        buttons.removeLast(max(0, buttons.count - items.count))
        #if os(iOS)
            // VoiceOver reaches the checkboxes after the entry's text, top to bottom.
            (host.superview as? JournalWritingView)?.checkboxElements = Array(buttons.prefix(items.count))
        #endif
    }

    struct Item {
        /// Where the item's paragraph starts.
        var location: Int
        var checked: Bool
        /// The item's text, for VoiceOver.
        var label: String
        var placement: Placement
    }

    /// The checklist items laid out within `area`, top to bottom.
    static func items(
        in area: CGRect, storage: NSTextStorage, layout: NSLayoutManager, container: NSTextContainer, origin: CGPoint
    ) -> [Item] {
        let source = storage.string as NSString
        let shown = layout.characterRange(
            forGlyphRange: layout.glyphRange(
                forBoundingRect: area.offsetBy(dx: -origin.x, dy: -origin.y), in: container),
            actualGlyphRange: nil)
        var result: [Item] = []
        var position = source.paragraphRange(for: NSRange(location: min(shown.location, source.length), length: 0))
            .location
        while position < storage.length, position <= NSMaxRange(shown) {
            let range = source.paragraphRange(for: NSRange(location: position, length: 0))
            position = NSMaxRange(range)
            let kind = storage.attribute(.journalKind, at: range.location, effectiveRange: nil) as? String
            guard kind == "task" || kind == "checked",
                let placement = placement(
                    at: range.location, storage: storage, layout: layout, container: container, origin: origin),
                area.minY...area.maxY ~= placement.capCenter
            else { continue }
            let content = source.substring(with: range).dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(
                Item(
                    location: range.location, checked: kind == "checked",
                    label: content.isEmpty ? "Empty checklist item" : content, placement: placement))
        }
        return result
    }

    /// The checkbox's place for the item whose paragraph starts at `location`, from the laid-out text: the box at
    /// the start of the item's list column, the text after it.
    static func placement(
        at location: Int, storage: NSTextStorage, layout: NSLayoutManager, container: NSTextContainer,
        origin: CGPoint
    ) -> Placement? {
        // The paragraph font at the item's size: the hidden ☐ marker itself may be drawn in a fallback font.
        guard location < storage.length,
            let marker = storage.attribute(.font, at: location, effectiveRange: nil) as? PlatformFont
        else { return nil }
        let font = RichText.font(size: marker.pointSize)
        let glyph = layout.glyphIndexForCharacter(at: location)
        guard glyph < layout.numberOfGlyphs else { return nil }
        let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let point = layout.location(forGlyphAt: glyph)
        let style = storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        return Placement(
            boxX: origin.x + line.minX + point.x, baseline: origin.y + line.minY + point.y,
            textX: origin.x + container.lineFragmentPadding + (style?.headIndent ?? 0), font: font)
    }

    /// A touch area `height` tall around `center`, split halfway towards a neighbouring item's box where the two
    /// would overlap, so a tap always toggles the nearer item.
    static func touchRange(around center: CGFloat, height: CGFloat, previous: CGFloat?, next: CGFloat?)
        -> ClosedRange<CGFloat>
    {
        var top = center - height / 2
        var bottom = center + height / 2
        if let previous { top = max(top, (previous + center) / 2) }
        if let next { bottom = min(bottom, (center + next) / 2) }
        return top...bottom
    }

    /// A checkbox for the item whose paragraph starts at the button's tag.
    private func makeButton() -> TaskButton {
        #if os(macOS)
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(activate(_:)))
        #else
            let button = ChecklistBox()
            button.addAction(
                UIAction { [weak self, weak button] _ in
                    guard let button else { return }
                    self?.toggle(NSRange(location: button.tag, length: 1))
                }, for: .touchUpInside)
        #endif
        host?.addSubview(button)
        buttons.append(button)
        return button
    }
    #if os(macOS)
        @objc private func activate(_ sender: NSButton) { toggle(NSRange(location: sender.tag, length: 0)) }
    #endif
}

#if os(iOS)
    /// A checklist item's checkbox on iPhone and iPad: `square`, or `checkmark.square.fill` in the accent colour with
    /// a white checkmark, sized by the item's font and sitting on its first line's baseline. The touch area reaches
    /// from the left of the box to the item's text, never over it.
    final class ChecklistBox: UIButton {
        let box = UIImageView()
        private var checked = false
        private var font = UIFont.preferredFont(forTextStyle: .body)

        override init(frame: CGRect) {
            super.init(frame: frame)
            box.isUserInteractionEnabled = false
            addSubview(box)
            isPointerInteractionEnabled = true
        }
        required init?(coder: NSCoder) { nil }

        func show(_ item: InlineTasks.Item, touch: ClosedRange<CGFloat>, editable: Bool) {
            checked = item.checked
            font = item.placement.font
            isEnabled = editable
            render()
            let size = box.image?.size ?? CGSize(width: font.pointSize, height: font.pointSize)
            let right = max(item.placement.textX, item.placement.boxX + size.width)
            let left = min(item.placement.boxX, max(0, right - InlineTasks.touchHeight))
            frame = CGRect(
                x: left, y: touch.lowerBound, width: right - left, height: touch.upperBound - touch.lowerBound)
            // Symbols are drawn to sit on the baseline of text in the same font.
            let top =
                box.image?.baselineOffsetFromBottom.map { item.placement.baseline - size.height + $0 }
                ?? item.placement.capCenter - size.height / 2
            box.frame = CGRect(
                x: item.placement.boxX - left, y: top - touch.lowerBound, width: size.width, height: size.height)
            accessibilityLabel = item.label
            accessibilityValue = item.checked ? "Checked" : "Unchecked"
        }

        override func tintColorDidChange() {
            super.tintColorDidChange()
            render()
        }

        private func render() {
            // A disabled checkbox, in a read-only entry, turns grey as a disabled control does.
            let fill: UIColor = isEnabled ? tintColor : .systemGray
            let colors: [UIColor] = checked ? [.white, fill] : [isEnabled ? .secondaryLabel : .tertiaryLabel]
            let configuration = UIImage.SymbolConfiguration(font: font, scale: .medium)
                .applying(UIImage.SymbolConfiguration(paletteColors: colors))
            box.image = UIImage(
                systemName: checked ? "checkmark.square.fill" : "square", withConfiguration: configuration)
        }
    }
#endif
