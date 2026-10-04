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

    /// Places a checkbox for every checklist item in view, and just beyond it, so items scrolling in already have
    /// theirs. An item keeps its checkbox while it stays in that area; only the boxes of items that left it are used
    /// for items that arrived.
    func synchronize(editable: Bool) {
        guard let host else { return }
        #if os(macOS)
            guard let storage = host.textStorage, let layout = host.layoutManager, let container = host.textContainer
            else { return }
            observeScrolling(of: host)
            self.editable = editable
            let origin = host.textContainerOrigin
            let visible = host.visibleRect
            // A screen ahead in each direction: the scroll view draws the text there ahead of time as well.
            let area = visible.insetBy(dx: 0, dy: -max(Self.touchHeight, visible.height))
        #else
            let storage = host.textStorage
            let layout = host.layoutManager
            let container = host.textContainer
            let origin = CGPoint(x: host.textContainerInset.left, y: host.textContainerInset.top)
            // UIKit lays the text view out for every frame it scrolls.
            let area = host.bounds.insetBy(dx: 0, dy: -Self.touchHeight)
        #endif
        let items = Self.items(in: area, storage: storage, layout: layout, container: container, origin: origin)
        let locations = Set(items.map(\.location))
        var kept: [Int: TaskButton] = [:]
        var free: [TaskButton] = []
        for button in buttons {
            if locations.contains(button.tag), kept[button.tag] == nil {
                kept[button.tag] = button
            } else {
                free.append(button)
            }
        }
        var shown: [TaskButton] = []
        for index in items.indices {
            let item = items[index]
            let button = kept[item.location] ?? free.popLast() ?? makeButton()
            shown.append(button)
            button.tag = item.location
            #if os(macOS)
                place(button, for: item, editable: editable)
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
        for button in free { button.removeFromSuperview() }
        buttons = shown
        #if os(iOS)
            // VoiceOver reaches the checkboxes after the entry's text, top to bottom.
            (host.superview as? JournalWritingView)?.checkboxElements = shown
        #endif
    }

    #if os(macOS)
        /// Whether the checkboxes respond, as last synchronized.
        private var editable = true
        private weak var observedClip: NSClipView?

        /// The checkboxes follow the scroll view as it scrolls, which doesn't lay the text view out: build 14 placed
        /// them only on layout, so items scrolled into view showed no checkbox, or showed it late.
        private func observeScrolling(of host: JournalTextView) {
            guard let clip = host.enclosingScrollView?.contentView, clip !== observedClip else { return }
            if let observedClip {
                NotificationCenter.default.removeObserver(
                    self, name: NSView.boundsDidChangeNotification, object: observedClip)
            }
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(scrolled(_:)), name: NSView.boundsDidChangeNotification, object: clip)
            observedClip = clip
        }

        @objc private func scrolled(_ notification: Notification) {
            // A scroll in the middle of an edit waits for the layout that follows it.
            guard host?.textStorage?.editedMask.isEmpty != false else { return }
            synchronize(editable: editable)
        }

        /// Sets only what changed, so a checkbox that stays where it is isn't redrawn while the entry scrolls.
        private func place(_ button: NSButton, for item: Item, editable: Bool) {
            let size: NSControl.ControlSize =
                item.placement.font.pointSize < 14 ? .small : item.placement.font.pointSize > 20 ? .large : .regular
            if button.controlSize != size { button.controlSize = size }
            let height = button.cell?.cellSize.height ?? 16
            let frame = CGRect(
                x: item.placement.boxX, y: item.placement.capCenter - height / 2,
                width: max(height, item.placement.textX - item.placement.boxX), height: height)
            if button.frame != frame { button.frame = frame }
            let state: NSControl.StateValue = item.checked ? .on : .off
            if button.state != state { button.state = state }
            if button.accessibilityLabel() != item.label { button.setAccessibilityLabel(item.label) }
            if button.isEnabled != editable { button.isEnabled = editable }
        }
    #endif

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
            let content = source.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(
                Item(
                    location: range.location, checked: kind == "checked",
                    label: content.isEmpty ? "Empty checklist item" : content, placement: placement))
        }
        return result
    }

    /// The checkbox's place for the item whose paragraph starts at `location`, from the laid-out text: the box at
    /// the start of the item's list column, where bullets and numbers are drawn, the text after it.
    static func placement(
        at location: Int, storage: NSTextStorage, layout: NSLayoutManager, container: NSTextContainer,
        origin: CGPoint
    ) -> Placement? {
        // The paragraph font at the item's size, not the first word's bold or code font.
        guard location < storage.length,
            let first = storage.attribute(.font, at: location, effectiveRange: nil) as? PlatformFont
        else { return nil }
        let font = RichText.font(size: first.pointSize)
        let glyph = layout.glyphIndexForCharacter(at: location)
        guard glyph < layout.numberOfGlyphs else { return nil }
        let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let baseline = ListMarkers.baseline(ofCharacter: location, glyph: glyph, layout: layout)
        let style = storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        let column = ListMarkers.columnStart(
            style: style, size: first.pointSize, padding: container.lineFragmentPadding,
            column: storage.attribute(.journalListColumn, at: location, effectiveRange: nil) as? CGFloat)
        return Placement(
            boxX: origin.x + line.minX + column, baseline: origin.y + line.minY + baseline,
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
            // A click toggles the item and the caret stays in the text, also with Keyboard Navigation on, which
            // would otherwise give the checkbox the focus. Format ▸ Mark as Checked is the keyboard's way.
            button.refusesFirstResponder = true
        #else
            let button = ChecklistBox()
            button.addAction(
                UIAction { [weak self, weak button] _ in
                    guard let button else { return }
                    self?.toggle(NSRange(location: button.tag, length: 1))
                }, for: .touchUpInside)
        #endif
        host?.addSubview(button)
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
