import SwiftUI

#if os(macOS)
    import AppKit
    private typealias TaskButton = NSButton
#else
    import UIKit
    private typealias TaskButton = UIButton
#endif

/// Checkboxes remain native controls; activating one mutates the same document and undo history as typing. Only the
/// tasks on screen have one, and the same controls move along as the text changes: making new ones for every keystroke
/// made typing lag in entries with tasks.
@MainActor final class InlineTasks {
    private weak var host: JournalTextView?
    private var buttons: [TaskButton] = []
    private let toggle: (NSRange) -> Void
    init(host: JournalTextView, toggle: @escaping (NSRange) -> Void) {
        self.host = host
        self.toggle = toggle
    }
    func synchronize(editable: Bool) {
        guard let host else { return }
        #if os(macOS)
            guard let storage = host.textStorage, let layout = host.layoutManager, let container = host.textContainer
            else { return }
            let origin = host.textContainerOrigin
            let visible = host.visibleRect
            let target: CGFloat = 22
        #else
            let storage = host.textStorage
            let layout = host.layoutManager
            let container = host.textContainer
            let origin = CGPoint(x: host.textContainerInset.left, y: host.textContainerInset.top)
            let visible = host.bounds
            let target: CGFloat = 44
        #endif
        let source = storage.string as NSString
        // Only the text on screen, with a line on either side for checkboxes taller than their line.
        let shown = layout.characterRange(
            forGlyphRange: layout.glyphRange(
                forBoundingRect: visible.insetBy(dx: 0, dy: -target).offsetBy(dx: -origin.x, dy: -origin.y),
                in: container),
            actualGlyphRange: nil)
        var used = 0
        var position = source.paragraphRange(for: NSRange(location: min(shown.location, source.length), length: 0))
            .location
        while position < storage.length, position <= NSMaxRange(shown) {
            let range = source.paragraphRange(for: NSRange(location: position, length: 0))
            position = NSMaxRange(range)
            let kind = storage.attribute(.journalKind, at: range.location, effectiveRange: nil) as? String
            guard kind == "task" || kind == "checked" else { continue }
            let marker = NSRange(location: range.location, length: 1)
            let glyph = layout.glyphRange(forCharacterRange: marker, actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyph, in: container).offsetBy(dx: origin.x, dy: origin.y)
            let frame = CGRect(x: rect.minX, y: rect.midY - target / 2, width: target, height: target)
            guard frame.intersects(visible) else { continue }
            let button = used < buttons.count ? buttons[used] : makeButton()
            used += 1
            button.tag = range.location
            button.frame = frame
            let content = source.substring(with: range).dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
            let label =
                (kind == "checked" ? "Mark as Incomplete" : "Mark as Complete")
                + (content.isEmpty ? "" : ": " + content)
            #if os(macOS)
                button.state = kind == "checked" ? .on : .off
                button.setAccessibilityLabel(label)
                button.isEnabled = editable
            #else
                button.setImage(
                    UIImage(systemName: kind == "checked" ? "checkmark.circle.fill" : "circle"), for: .normal)
                button.accessibilityLabel = label
                button.accessibilityValue = kind == "checked" ? "Checked" : "Unchecked"
                button.isEnabled = editable
            #endif
        }
        for button in buttons.dropFirst(used) { button.removeFromSuperview() }
        buttons.removeLast(buttons.count - used)
    }
    /// A checkbox for the task whose paragraph starts at the button's tag.
    private func makeButton() -> TaskButton {
        #if os(macOS)
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(activate(_:)))
        #else
            let button = UIButton(type: .system)
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
