#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

@MainActor
enum JournalAccessibility {
    static func announce(_ text: String) {
        #if os(macOS)
            NSAccessibility.post(
                element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        #else
            UIAccessibility.post(notification: .announcement, argument: text)
        #endif
    }
    #if os(iOS)
        /// VoiceOver moves to the new screen's first element.
        static func screenChanged() {
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    #endif
}
