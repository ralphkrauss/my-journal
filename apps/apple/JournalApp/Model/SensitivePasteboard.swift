import Foundation

#if os(macOS)
    import AppKit
#else
    import UIKit
    import UniformTypeIdentifiers
#endif

/// Copies a secret so that it stays on this device and doesn't linger: it isn't shared through Universal
/// Clipboard, clipboard managers are asked not to keep it, and it's removed after two minutes. On the Mac it's also
/// removed when My Journal quits or locks sooner, so the clipboard never keeps it longer than that.
@MainActor
enum SensitivePasteboard {
    static let lifetime: TimeInterval = 120
    #if os(macOS)
        /// The clipboard's change count right after the secret was copied, while it may still be there.
        private static var copiedChangeCount: Int?
    #endif

    static func copy(_ text: String) {
        #if os(macOS)
            let pasteboard = NSPasteboard.general
            pasteboard.prepareForNewContents(with: .currentHostOnly)
            pasteboard.setString(text, forType: .string)
            // The nspasteboard.org convention clipboard managers follow for passwords.
            pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            let copied = pasteboard.changeCount
            copiedChangeCount = copied
            DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) {
                if copiedChangeCount == copied { clear() }
            }
        #else
            UIPasteboard.general.setItems(
                [[UTType.utf8PlainText.identifier: text]],
                options: [.localOnly: true, .expirationDate: Date(timeIntervalSinceNow: lifetime)])
        #endif
    }
    /// Removes the copied secret now, unless something else was copied since. On iPhone and iPad the clipboard
    /// item expires by itself.
    static func clear() {
        #if os(macOS)
            guard let copied = copiedChangeCount else { return }
            copiedChangeCount = nil
            if NSPasteboard.general.changeCount == copied { NSPasteboard.general.clearContents() }
        #endif
    }
}
