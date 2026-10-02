#if os(iOS)
    import UIKit

    /// Time iOS grants to finish work, such as saving and locking, after the app leaves the screen.
    @MainActor
    final class BackgroundActivity {
        private var identifier = UIBackgroundTaskIdentifier.invalid

        /// Runs `work`, asking iOS not to suspend the app until it finishes or the granted time runs out.
        static func run(_ name: String, _ work: @escaping @MainActor () async -> Void) {
            let activity = BackgroundActivity()
            activity.identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak activity] in
                activity?.end()
            }
            Task {
                await work()
                activity.end()
            }
        }

        private func end() {
            guard identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
    }
#endif
