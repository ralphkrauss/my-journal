#if os(iOS)
    import SwiftUI
    import UIKit

    struct FormattingButtonAnchor: UIViewRepresentable {
        let editor: EditorActions
        func makeUIView(context: Context) -> UIView { UIView() }
        func updateUIView(_ view: UIView, context: Context) { editor.formattingToolbarAnchor = view }
    }

    /// Shows Formatting as Notes does: on iPhone, and in compact or accessibility sizes, the Format panel in place of
    /// the keyboard, so the text keeps focus and its selection; on iPad in regular width, a popover pointing at the Aa
    /// that opened it. Both appear and disappear without animation.
    struct MobileFormattingPresenter: UIViewControllerRepresentable {
        let editor: EditorActions
        func makeCoordinator() -> Coordinator { Coordinator(editor: editor) }
        func makeUIViewController(context: Context) -> PresentingController {
            let controller = PresentingController()
            controller.sizeClassChanged = { [weak coordinator = context.coordinator] in coordinator?.sizeClassChanged()
            }
            context.coordinator.controller = controller
            context.coordinator.install()
            return controller
        }
        func updateUIViewController(_ controller: PresentingController, context: Context) {
            context.coordinator.install()
        }
        static func dismantleUIViewController(_ controller: PresentingController, coordinator: Coordinator) {
            coordinator.close(refocus: false)
        }

        /// Presents the iPad popover and reports size-class changes, which close Formatting.
        final class PresentingController: UIViewController {
            var sizeClassChanged: (() -> Void)?
            override func viewDidLoad() {
                super.viewDidLoad()
                view.isUserInteractionEnabled = false
                // Resizing a window (Stage Manager, windowed apps) changes the width class without a transition.
                if #available(iOS 17.0, *) {
                    registerForTraitChanges([UITraitHorizontalSizeClass.self]) {
                        (controller: PresentingController, previous: UITraitCollection) in
                        if controller.traitCollection.horizontalSizeClass != previous.horizontalSizeClass {
                            controller.sizeClassChanged?()
                        }
                    }
                }
            }
            override func traitCollectionDidChange(_ previous: UITraitCollection?) {
                super.traitCollectionDidChange(previous)
                if #unavailable(iOS 17.0), previous?.horizontalSizeClass != traitCollection.horizontalSizeClass {
                    sizeClassChanged?()
                }
            }
            override func willTransition(
                to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator
            ) {
                super.willTransition(to: newCollection, with: coordinator)
                if newCollection.horizontalSizeClass != traitCollection.horizontalSizeClass { sizeClassChanged?() }
            }
        }

        @MainActor final class Coordinator: NSObject, UIPopoverPresentationControllerDelegate {
            private let editor: EditorActions
            weak var controller: UIViewController?
            private lazy var panel = FormattingPanel(editor: editor) { [weak self] in self?.close(refocus: true) }
            private var popoverHost: UIHostingController<FormattingPopover>?
            /// When a tap outside last closed the popover: the same tap on Aa (in the keyboard's window, outside the
            /// popover's reach) mustn't open it again.
            private var popoverDismissedAt: Date?

            init(editor: EditorActions) {
                self.editor = editor
                super.init()
                NotificationCenter.default.addObserver(
                    self, selector: #selector(keyboardWillChangeFrame(_:)),
                    name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
                NotificationCenter.default.addObserver(
                    self, selector: #selector(keyboardDidChangeFrame(_:)),
                    name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
            }
            /// Once the entry has made room for the panel, the text being styled is scrolled into view above it.
            @objc private func keyboardDidChangeFrame(_ notification: Notification) {
                guard editor.formattingInputView != nil, let input = editor.focusedTextInput?() else { return }
                input.scrollRangeToVisible(input.selectedRange)
            }

            func install() {
                editor.toggleFormatting = { [weak self] anchor in self?.toggle(anchor: anchor) }
            }

            private var popoverShown: Bool { popoverHost?.presentingViewController != nil }

            func toggle(anchor: UIView?) {
                if editor.formatting.isPresented {
                    close(refocus: true)
                    return
                }
                if let dismissed = popoverDismissedAt, Date().timeIntervalSince(dismissed) < 0.35 { return }
                guard let controller, controller.view.window != nil else { return }
                let traits = controller.traitCollection
                if traits.horizontalSizeClass == .regular, !traits.preferredContentSizeCategory.isAccessibilityCategory,
                    let anchor = anchor ?? editor.formattingToolbarAnchor, anchor.window != nil
                {
                    presentPopover(from: anchor, in: controller)
                } else {
                    showPanel()
                }
            }

            func close(refocus: Bool) {
                if editor.formattingInputView != nil {
                    editor.formattingInputView = nil
                    editor.finishPresentation(refocus: false)
                    // The keyboard returns in place of the panel, with the selection as it is.
                    if let input = editor.focusedTextInput?() {
                        UIView.performWithoutAnimation { input.reloadInputViews() }
                    }
                } else if let host = popoverHost, popoverShown {
                    host.dismiss(animated: false)
                    editor.finishPresentation(refocus: refocus)
                } else if editor.formatting.isPresented {
                    editor.finishPresentation(refocus: false)
                }
            }

            /// Split View, Stage Manager or rotation changed the width class: close, and the keyboard returns.
            func sizeClassChanged() {
                guard editor.formatting.isPresented else { return }
                close(refocus: true)
            }

            // MARK: Panel in place of the keyboard

            private func showPanel() {
                guard let window = controller?.view.window else { return }
                editor.commitComposition?()
                editor.beginFormattingPresentation()
                editor.closeFormatting = { [weak self] refocus in self?.close(refocus: refocus) }
                panel.prepare(in: window)
                editor.formattingInputView = panel
                if let input = editor.focusedTextInput?() {
                    UIView.performWithoutAnimation { input.reloadInputViews() }
                } else {
                    // Reading: editing starts at the remembered selection, with the panel instead of the keyboard.
                    UIView.performWithoutAnimation { editor.handler?(.focus) }
                    guard editor.focusedTextInput?() != nil else {
                        close(refocus: false)
                        return
                    }
                }
                UIAccessibility.post(notification: .screenChanged, argument: panel)
            }

            /// Remembers the keyboard's height, without the accessory bar that stays above the panel.
            @objc private func keyboardWillChangeFrame(_ notification: Notification) {
                // Only while the entry's text or a table cell is edited, whose accessory bar is known.
                guard editor.formattingInputView == nil,
                    let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                    let window = controller?.view.window, let input = editor.focusedTextInput?()
                else { return }
                let local = window.convert(frame, from: window.screen.coordinateSpace)
                let covered = max(0, window.bounds.maxY - local.minY)
                let accessory = input.inputAccessoryView?.bounds.height ?? 0
                panel.rememberKeyboard(height: covered - accessory, in: window)
            }

            // MARK: iPad popover

            private func presentPopover(from anchor: UIView, in controller: UIViewController) {
                editor.beginFormattingPresentation()
                let host =
                    popoverHost
                    ?? UIHostingController(
                        rootView: FormattingPopover(
                            editor: editor, session: editor.formatting,
                            close: { [weak self] in self?.close(refocus: true) }))
                popoverHost = host
                // The popover's own margins are enough; the safe area it reports would add a band above the title.
                if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
                host.modalPresentationStyle = .popover
                // As tall as its rows, so every option shows when there's room; UIKit keeps it on screen.
                let fitted = host.sizeThatFits(in: CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
                host.preferredContentSize = CGSize(width: 300, height: fitted.height)
                if let popover = host.popoverPresentationController {
                    popover.sourceView = anchor
                    popover.sourceRect = anchor.bounds
                    popover.delegate = self
                    // A tap in the text places the caret at once; the selection change then closes the popover.
                    popover.passthroughViews = [editor.focusedTextInput?()].compactMap { $0 }
                }
                editor.closeFormatting = { [weak self] refocus in self?.close(refocus: refocus) }
                editor.formattingSelectionMoved = { [weak self] in self?.close(refocus: false) }
                controller.present(host, animated: false)
            }

            func adaptivePresentationStyle(
                for controller: UIPresentationController, traitCollection: UITraitCollection
            ) -> UIModalPresentationStyle { .none }

            func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
                popoverDismissedAt = Date()
            }

            func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
                // A tap outside: focus goes where the person tapped.
                editor.finishPresentation(refocus: false)
            }
        }
    }

    /// The Format panel shown in place of the keyboard: as tall as the keyboard it replaces, so the entry doesn't
    /// move, or as tall as its rows when there's no on-screen keyboard.
    @MainActor final class FormattingPanel: UIInputView {
        private weak var editor: EditorActions?
        private let host: UIHostingController<FormattingPopover>
        /// The on-screen keyboard's height without its accessory bar, for portrait and landscape.
        private var keyboardHeights: [Bool: CGFloat] = [:]
        private var height: CGFloat = 320
        private var laidOutSize = CGSize.zero
        private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: height)

        init(editor: EditorActions, close: @escaping () -> Void) {
            self.editor = editor
            host = UIHostingController(
                rootView: FormattingPopover(editor: editor, session: editor.formatting, close: close))
            super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 320), inputViewStyle: .keyboard)
            allowsSelfSizing = true
            host.view.backgroundColor = .clear
            host.view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
                host.view.topAnchor.constraint(equalTo: topAnchor),
                host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
                heightConstraint,
            ])
        }
        required init?(coder: NSCoder) { nil }

        /// The keyboard area sizes itself to this height.
        private func apply(height: CGFloat) {
            self.height = height
            heightConstraint.constant = height
            frame.size.height = height
        }

        func rememberKeyboard(height: CGFloat, in window: UIWindow) {
            // With a hardware keyboard only the accessory bar shows; that isn't a keyboard height.
            guard height > 120 else { return }
            keyboardHeights[Self.landscape(window)] = height
        }

        /// Sizes the panel for the app's window before it replaces the keyboard there.
        func prepare(in window: UIWindow) {
            apply(height: panelHeight(in: window))
            laidOutSize = window.bounds.size
        }

        /// Rotation or a window resize while open: the height follows, without animation.
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let input = editor?.focusedTextInput?(), let window = input.window,
                window.bounds.size != laidOutSize, laidOutSize != .zero
            else { return }
            laidOutSize = window.bounds.size
            // Once the entry has its new size, the text being styled is scrolled back into view.
            DispatchQueue.main.async { [weak input] in
                guard let input else { return }
                input.scrollRangeToVisible(input.selectedRange)
            }
            // Reloaded even at the same height, so the entry's room above the panel is measured again for the new size.
            apply(height: panelHeight(in: window))
            UIView.performWithoutAnimation { input.reloadInputViews() }
        }

        /// Exactly as tall as the keyboard it replaces (without its bar), so the entry doesn't move; the rows scroll.
        /// Without an on-screen keyboard (a hardware keyboard, or none shown yet in this orientation), as tall as the
        /// rows, up to about a keyboard's share of the window.
        private func panelHeight(in window: UIWindow) -> CGFloat {
            if let keyboard = keyboardHeights[Self.landscape(window)] { return keyboard }
            let fitted = host.sizeThatFits(in: CGSize(width: window.bounds.width, height: .greatestFiniteMagnitude))
            let share: CGFloat = Self.landscape(window) ? 0.5 : 0.4
            return min(fitted.height + window.safeAreaInsets.bottom, window.bounds.height * share)
        }

        private static func landscape(_ window: UIWindow) -> Bool { window.bounds.width > window.bounds.height }
    }

#endif
