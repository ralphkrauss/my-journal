import Darwin
import Foundation
import JournalCore
import SwiftUI
import XCTest

@testable import Journal

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Records when the main thread is busy: from the run loop waking up until it goes back to sleep. Everything the main
/// thread does for a change (the editor, the model, SwiftUI updates, layout and drawing) falls inside these periods.
final class MainThreadActivity {
    private var observer: CFRunLoopObserver?
    private var wokeAt: UInt64 = 0
    private(set) var periods: [(start: UInt64, end: UInt64)] = []

    init() {
        let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
        observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, 0) { [weak self] _, activity in
            guard let self else { return }
            let now = Self.now()
            if activity == .afterWaiting {
                self.wokeAt = now
            } else if self.wokeAt > 0 {
                self.periods.append((self.wokeAt, now))
                self.wokeAt = 0
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    func stop() {
        if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
        observer = nil
    }

    static func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }

    /// Busy time between two instants, in milliseconds. A period still running counts until `end`.
    func busyMilliseconds(from start: UInt64, to end: UInt64) -> Double {
        var total: UInt64 = 0
        var all = periods
        if wokeAt > 0 { all.append((wokeAt, Self.now())) }
        for period in all where period.end > start && period.start < end {
            total += min(period.end, end) - max(period.start, start)
        }
        return Double(total) / 1_000_000
    }

    /// When the last busy period longer than `significant` nanoseconds ended after `start`. Shorter periods are this
    /// harness polling for the end of the work.
    func lastWork(after start: UInt64, significant: UInt64 = 2_000_000) -> UInt64? {
        periods.last { $0.end > start && $0.end - $0.start >= significant }?.end
    }
}

/// Processor time the calling thread has used, in milliseconds: on the main thread, the work it did, without the
/// time it waited. XCTest waits for an asynchronous test in a run loop mode the busy periods above don't see, so they
/// can count some of that waiting as work; this doesn't.
func threadCPUMilliseconds() -> Double {
    var info = thread_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            thread_info(pthread_mach_thread_np(pthread_self()), thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return 0 }
    let user = Double(info.user_time.seconds) * 1_000 + Double(info.user_time.microseconds) / 1_000
    let system = Double(info.system_time.seconds) * 1_000 + Double(info.system_time.microseconds) / 1_000
    return user + system
}

/// The measured values of one run, printed as one JSON line the measurement script collects.
@MainActor final class MeasurementReport {
    private var values: [String: Any] = [:]
    let platform: String

    init() {
        #if os(macOS)
            platform = "macOS"
        #else
            platform = UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS simulator" : "iOS simulator"
        #endif
    }

    subscript(key: String) -> Any? {
        get { values[key] }
        set { values[key] = newValue }
    }

    func distribution(_ key: String, _ samples: [Double]) {
        guard !samples.isEmpty else { return }
        let sorted = samples.sorted()
        func percentile(_ fraction: Double) -> Double {
            sorted[min(sorted.count - 1, Int((Double(sorted.count) * fraction).rounded(.up)) - 1)]
        }
        values[key] = [
            "p50": percentile(0.5), "p95": percentile(0.95), "max": sorted[sorted.count - 1], "count": sorted.count,
        ]
    }

    func emit() throws {
        values["platform"] = platform
        let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        print("JOURNAL-MEASUREMENT " + String(decoding: data, as: UTF8.self))
    }
}

/// The seeded library the measurement script created, opened from a copy so every run starts the same.
struct MeasurementFixture {
    struct Manifest: Decodable {
        struct Shape: Decodable {
            var entries: Int
            var cameraPhotos: Int
            var libraryPhotos: Int
        }
        var shape: Shape
        var journalID: UUID
        var normalEntryID: UUID
        var longEntryID: UUID
        var photoEntryID: UUID
        var searchTerms: [String: Int]
        var serverID: String
        var cursor: Int64
    }
    let root: URL
    let manifest: Manifest
    let key: Data

    init() throws {
        guard let path = ProcessInfo.processInfo.environment["JOURNAL_MEASURE_FIXTURE"], !path.isEmpty else {
            throw MeasurementFailure("Run scripts/measure-app.sh, which seeds the library and names it.")
        }
        root = URL(fileURLWithPath: path, isDirectory: true)
        manifest = try JournalCoding.decoder().decode(
            Manifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        key = try Data(contentsOf: root.appendingPathComponent("synthetic-key"))
    }

    var attachments: URL { root.appendingPathComponent("library/attachments", isDirectory: true) }

    /// A fresh copy of the library in a temporary folder. APFS clones it, so this is quick.
    func copyLibrary(to directory: URL) throws -> URL {
        let destination = directory.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.copyItem(at: root.appendingPathComponent("library"), to: destination)
        return destination
    }

    func log() throws -> [RemoteChange] {
        try JournalCoding.decoder().decode(
            [RemoteChange].self, from: Data(contentsOf: root.appendingPathComponent("server-log.json")))
    }
}

struct MeasurementFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// The memory the system counts against the app (what jetsam limits on iOS), in megabytes.
func physicalFootprintMegabytes() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
}

/// A window showing the app's real views for a model, as the app itself shows them.
@MainActor final class MeasuredWindow {
    let model: AppModel
    let editor = EditorActions()
    let activity = MainThreadActivity()
    #if os(macOS)
        let window: NSWindow
    #else
        let window: UIWindow
    #endif

    init(model: AppModel, size: CGSize) {
        self.model = model
        let root = RootView().environmentObject(model).environmentObject(editor)
        #if os(macOS)
            window = NSWindow(
                contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .resizable],
                backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: root)
            window.makeKeyAndOrderFront(nil)
        #else
            // The app's own scene, so the window shows as the app's windows do.
            if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                window = UIWindow(windowScene: scene)
            } else {
                window = UIWindow(frame: CGRect(origin: .zero, size: size))
            }
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = UIHostingController(rootView: root)
            window.makeKeyAndVisible()
        #endif
    }

    /// Waits until the main thread has finished all work caused by a change, and returns when it finished: the end of
    /// the last work after this call, or this call when nothing followed.
    @discardableResult func settle(after start: UInt64? = nil, timeout: Double = 30) async throws -> UInt64 {
        let called = start ?? MainThreadActivity.now()
        let deadline = called + UInt64(timeout * 1e9)
        while MainThreadActivity.now() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
            forceDisplay()
            let finished = activity.lastWork(after: called) ?? called
            if MainThreadActivity.now() - finished >= 150_000_000 { return finished }
        }
        throw MeasurementFailure("The main thread didn't become idle.")
    }

    func forceDisplay() {
        #if os(macOS)
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        #else
            window.layoutIfNeeded()
        #endif
    }

    /// The entry editor's text view, once it shows.
    func textView() -> JournalTextView? {
        #if os(macOS)
            return Self.find(in: window.contentView)
        #else
            return Self.find(in: window)
        #endif
    }

    #if os(macOS)
        private static func find(in view: NSView?) -> JournalTextView? {
            guard let view else { return nil }
            if let text = view as? JournalTextView { return text }
            for child in view.subviews {
                if let found = find(in: child) { return found }
            }
            return nil
        }
    #else
        private static func find(in view: UIView?) -> JournalTextView? {
            guard let view else { return nil }
            if let text = view as? JournalTextView { return text }
            for child in view.subviews {
                if let found = find(in: child) { return found }
            }
            return nil
        }
    #endif

    /// Types as the keyboard does, including the editor's chance to handle the key first.
    func type(_ text: String, in view: JournalTextView) {
        #if os(macOS)
            view.insertText(text, replacementRange: view.selectedRange())
        #else
            if view.delegate?.textView?(view, shouldChangeTextIn: view.selectedRange, replacementText: text) != false {
                view.insertText(text)
            }
        #endif
    }

    func placeCaretNearMiddle(of view: JournalTextView) {
        #if os(macOS)
            _ = window.makeFirstResponder(view)
            let text = view.string as NSString
        #else
            _ = view.becomeFirstResponder()
            let text = view.text as NSString? ?? ""
        #endif
        let middle = text.length / 2
        let paragraphEnd = text.range(
            of: "\n", options: [], range: NSRange(location: middle, length: text.length - middle)
        ).location
        let location = paragraphEnd == NSNotFound ? text.length : paragraphEnd
        #if os(macOS)
            view.setSelectedRange(NSRange(location: location, length: 0))
        #else
            view.selectedRange = NSRange(location: location, length: 0)
        #endif
    }

    func scroll(_ view: JournalTextView, to fraction: CGFloat) {
        #if os(macOS)
            let height = view.frame.height
            view.scroll(NSPoint(x: 0, y: max(0, height * fraction - 300)))
        #else
            let height = view.contentSize.height - view.bounds.height
            view.setContentOffset(CGPoint(x: 0, y: max(0, height * fraction)), animated: false)
        #endif
    }
}
