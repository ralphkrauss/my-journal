import SwiftUI

extension View {
    /// Runs `action` once the sheet showing this view has finished appearing. On iOS, focus set in `onAppear` can
    /// be lost while the presentation is still under way, for example right after the Formatting popover closes.
    func onPresented(perform action: @escaping () -> Void) -> some View {
        #if os(iOS)
            background(PresentedSignal(action: action))
        #else
            onAppear(perform: action)
        #endif
    }
}

#if os(iOS)
    private struct PresentedSignal: UIViewControllerRepresentable {
        let action: () -> Void
        func makeUIViewController(context: Context) -> Controller { Controller(action: action) }
        func updateUIViewController(_ controller: Controller, context: Context) { controller.action = action }

        final class Controller: UIViewController {
            var action: () -> Void
            private var appeared = false
            init(action: @escaping () -> Void) {
                self.action = action
                super.init(nibName: nil, bundle: nil)
            }
            required init?(coder: NSCoder) { nil }
            override func viewDidLoad() {
                super.viewDidLoad()
                view.isUserInteractionEnabled = false
            }
            override func viewDidAppear(_ animated: Bool) {
                super.viewDidAppear(animated)
                guard !appeared else { return }
                appeared = true
                action()
            }
        }
    }
#endif
