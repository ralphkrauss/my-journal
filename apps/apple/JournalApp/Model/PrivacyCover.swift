import SwiftUI

/// What App Lock shows instead of journals while the app isn't active. It says the journal is locked only when it
/// is: an app that is merely inactive, for example behind Control Center or a permission alert, needs no unlocking.
struct LockedCover: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Rectangle().fill(.background).overlay {
            if model.locked { Label("My Journal Is Locked", systemImage: "lock").foregroundStyle(.secondary) }
        }.ignoresSafeArea()
    }
}

#if os(iOS)
    import UIKit

    /// While App Lock is on, covers every window whenever the app isn't active, including sheets, popovers and
    /// alerts, which appear above the root view. The app switcher and its snapshot then never show journal content.
    @MainActor
    final class PrivacyCover: NSObject {
        static let shared = PrivacyCover()
        private weak var model: AppModel?
        private var windows: [UIWindow] = []

        func watch(_ model: AppModel) {
            let first = self.model == nil
            self.model = model
            guard first else { return }
            let center = NotificationCenter.default
            center.addObserver(
                self, selector: #selector(coverUnlessAuthenticating), name: UIScene.willDeactivateNotification,
                object: nil)
            center.addObserver(
                self, selector: #selector(cover), name: UIScene.didEnterBackgroundNotification, object: nil)
            center.addObserver(self, selector: #selector(uncover), name: UIScene.didActivateNotification, object: nil)
        }

        /// App Lock's own request makes the app inactive while it shows; covering then would hide the lock screen
        /// behind the cover. Entering the background still covers.
        @objc private func coverUnlessAuthenticating() {
            guard model?.unlockState.requestInFront != true else { return }
            cover()
        }

        @objc private func cover() {
            guard windows.isEmpty, let model, model.appLockOn else { return }
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                let window = UIWindow(windowScene: scene)
                window.windowLevel = .alert + 1
                window.rootViewController = UIHostingController(rootView: LockedCover(model: model))
                window.isHidden = false
                windows.append(window)
            }
        }

        @objc private func uncover() {
            for window in windows { window.isHidden = true }
            windows = []
        }
    }
#endif
