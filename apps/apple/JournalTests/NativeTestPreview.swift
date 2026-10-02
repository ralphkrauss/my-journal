import SwiftUI
import XCTest

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

@MainActor
enum NativeTestPreview {
    static func capture<V: View>(_ view: V, name: String, width: CGFloat = 460, height: CGFloat = 540) async
        -> XCTAttachment?
    {
        #if os(macOS)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered,
                defer: true)
            let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            window.contentView = host
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = NSImage(size: host.bounds.size)
            image.addRepresentation(bitmap)
            let attachment = XCTAttachment(image: image)
        #else
            let host = UIHostingController(rootView: view)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            await Task.yield()
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
        #endif
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }
}
