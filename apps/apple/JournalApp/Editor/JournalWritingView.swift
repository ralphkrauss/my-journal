#if os(iOS)
    import SwiftUI
    import UIKit

    final class JournalWritingView: UIView {
        let editor = JournalTextView()
        private var header: (UIView & UIContentView)?
        /// “Start writing…”, or “Start writing or [symbol] use a template”, laid out as body text (PlaceholderText).
        private let placeholder = PlaceholderTextView()
        private var placeholderSize: CGFloat = 17
        private struct PlaceholderKey: Equatable {
            var size: CGFloat
            var offered: Bool
            var width: CGFloat
        }
        private var placeholderKey: PlaceholderKey?
        /// The link's button: transparent, over the link's glyphs, and what VoiceOver reads as “Use a Template”.
        private var suggestion: (UIView & UIContentView)?
        private var entryID: UUID?
        private var headerHeight: CGFloat = 0
        private var headerWidth: CGFloat = 0
        private var viewportHeight: CGFloat = 0
        private var viewportInsets = UIEdgeInsets.zero
        private var failurePinned = false
        private var showingFailure = false
        private var revealFailure = false
        private var layingOutHeader = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            isAccessibilityElement = false
            clipsToBounds = true
            addSubview(editor)
            // UIKit sizes the text's content and drawing area from the part of the text laid out so far. With
            // non-contiguous layout, rotating after writing left only the start of the text laid out, so the end
            // of the entry wasn't drawn. Lay out contiguously, as the Mac's text view does.
            editor.layoutManager.allowsNonContiguousLayout = false
            editor.containerLayoutChanged = { [weak self] in self?.layoutHeader() }
            editor.containerInteractionBegan = { [weak self] in
                self?.failurePinned = false
                self?.revealFailure = false
            }
            editor.addSubview(placeholder)
        }

        required init?(coder: NSCoder) { nil }

        /// Hides "Start writing…" with the first keystroke, before the document catches up.
        func editorTextChanged() {
            guard editor.textStorage.length > 0 else { return }
            placeholder.isHidden = true
            if suggestion?.isHidden == false {
                suggestion?.isHidden = true
                updateAccessibility()
            }
        }

        func configure(
            header content: AnyView?, suggestion offered: AnyView?, entryID: UUID, failure: Bool,
            placeholderSize: CGFloat?
        ) {
            if self.entryID != entryID {
                self.entryID = entryID
                showingFailure = false
                revealFailure = false
                failurePinned = false
                headerHeight = 0
                headerWidth = 0
            }
            revealFailure = revealFailure || (failure && !showingFailure)
            showingFailure = failure
            if !failure {
                failurePinned = false
                revealFailure = false
            }
            if let content {
                let configuration = UIHostingConfiguration { content.id(entryID) }.margins(.all, 0)
                if let header {
                    header.configuration = configuration
                } else {
                    let hosted = configuration.makeContentView()
                    editor.addSubview(hosted)
                    header = hosted
                }
            } else {
                header?.removeFromSuperview()
                header = nil
            }
            if let offered {
                let configuration = UIHostingConfiguration { offered }.margins(.all, 0)
                if let suggestion {
                    suggestion.configuration = configuration
                } else {
                    let hosted = configuration.makeContentView()
                    // Below the header, so its target never takes a tap meant for the title.
                    if let header {
                        editor.insertSubview(hosted, belowSubview: header)
                    } else {
                        editor.addSubview(hosted)
                    }
                    suggestion = hosted
                }
            }
            // Typed text may not have reached the document yet.
            placeholder.isHidden = placeholderSize == nil || editor.textStorage.length > 0
            suggestion?.isHidden = offered == nil || placeholder.isHidden
            editor.gestureExclusions = suggestion.map { [$0] } ?? []
            updateAccessibility()
            if let placeholderSize { self.placeholderSize = placeholderSize }
            setNeedsLayout()
        }

        func updateAccessibility() {
            let tables = subviews.compactMap { $0 as? InlineTableGrid }.sorted { $0.frame.minY < $1.frame.minY }
            let offered = suggestion.flatMap { $0.isHidden ? nil : $0 }
            accessibilityElements = [header, offered].compactMap { $0 } + [editor] + tables
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            editor.frame = bounds
            layoutHeader()
        }

        private func layoutHeader() {
            guard !layingOutHeader, editor.bounds.width > 0 else { return }
            layingOutHeader = true
            defer { layingOutHeader = false }
            let width = editor.bounds.width
            let height = header?.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height ?? 0
            guard height.isFinite, height >= 0 else { return }
            let previousHeight = headerHeight
            let changed =
                abs(height - headerHeight) > 0.5 || abs(width - headerWidth) > 0.5
                || abs(editor.bounds.height - viewportHeight) > 0.5 || editor.adjustedContentInset != viewportInsets
            let userScrolling = editor.isTracking || editor.isDragging || editor.isDecelerating
            if userScrolling { failurePinned = false }
            viewportHeight = editor.bounds.height
            viewportInsets = editor.adjustedContentInset
            let offset = editor.contentOffset
            headerHeight = height
            headerWidth = width
            header?.frame = CGRect(x: 0, y: 0, width: width, height: height)
            if abs(editor.textContainerInset.top - height - 8) > 0.5 {
                editor.textContainerInset.top = height + 8
            }
            if !placeholder.isHidden { layoutPlaceholder(width: width, top: height + 8) }
            if revealFailure, header != nil {
                revealFailure = false
                failurePinned = true
                editor.setContentOffset(CGPoint(x: 0, y: -editor.adjustedContentInset.top), animated: false)
            } else if changed, !userScrolling, !failurePinned {
                if let title = firstResponder(in: header) as? UITextView, let range = title.selectedTextRange {
                    let caret = title.convert(title.caretRect(for: range.end), to: editor)
                    editor.scrollRectToVisible(caret.insetBy(dx: 0, dy: -8), animated: false)
                } else if editor.isFirstResponder, let range = editor.selectedTextRange {
                    editor.scrollRectToVisible(editor.caretRect(for: range.end).insetBy(dx: 0, dy: -8), animated: false)
                } else if previousHeight > 0, offset.y >= previousHeight {
                    editor.layoutIfNeeded()
                    let minimum = -editor.adjustedContentInset.top
                    let maximum = max(
                        minimum, editor.contentSize.height - editor.bounds.height + editor.adjustedContentInset.bottom)
                    let position = min(maximum, max(minimum, offset.y + height - previousHeight))
                    editor.setContentOffset(CGPoint(x: offset.x, y: position), animated: false)
                }
            }
        }

        /// The placeholder in the body's own text container, so its lines are where typed text's would be; the link's
        /// 44-point target covers the link's glyphs, reaching into empty space.
        private func layoutPlaceholder(width: CGFloat, top: CGFloat) {
            let inset = editor.textContainerInset
            let padding = editor.textContainer.lineFragmentPadding
            let containerWidth = max(0, width - inset.left - inset.right)
            placeholder.textContainer.lineFragmentPadding = padding
            let offered = suggestion.map { !$0.isHidden } ?? false
            let (text, link) = PlaceholderText.make(
                size: placeholderSize, offersTemplate: offered, width: containerWidth - 2 * padding,
                placeholder: .tertiaryLabel, link: .secondaryLabel)
            let key = PlaceholderKey(size: placeholderSize, offered: offered, width: containerWidth)
            if placeholderKey != key {
                placeholderKey = key
                placeholder.attributedText = text
            }
            let fitting = placeholder.sizeThatFits(CGSize(width: containerWidth, height: .greatestFiniteMagnitude))
            placeholder.frame = CGRect(x: inset.left, y: top, width: containerWidth, height: fitting.height)
            guard let suggestion, offered, let link else { return }
            let glyphs = placeholder.rect(of: link).offsetBy(dx: placeholder.frame.minX, dy: placeholder.frame.minY)
            let height = max(44, glyphs.height)
            suggestion.frame = CGRect(
                x: glyphs.minX, y: glyphs.midY - height / 2, width: glyphs.width, height: height)
        }

        private func firstResponder(in view: UIView?) -> UIView? {
            guard let view else { return nil }
            if view.isFirstResponder { return view }
            for child in view.subviews {
                if let responder = firstResponder(in: child) { return responder }
            }
            return nil
        }
    }
#endif
