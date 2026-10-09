import JournalCore
import XCTest

@testable import Journal

#if os(macOS)
    import AppKit
    import SwiftUI
#endif

/// The entry list is derived once per change rather than on every view update, and searched off the main thread.
/// These check that what it shows still follows the library, the query and the writing.
@MainActor
final class EntryListTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func testSearchFollowsTheQueryAndWhatIsWritten() async throws {
        let model = AppModel(directory: root)
        let journal = JournalItem(kind: "journal", title: "Daily")
        let harbor = JournalItem(kind: "entry", journalID: journal.id, title: "Walk", document: .plain("By the Harbor"))
        let hills = JournalItem(kind: "entry", journalID: journal.id, title: "Hike", document: .plain("In the hills"))
        model.items = [journal, harbor, hills]
        model.showingAllEntries = true
        model.query = "harbor"
        await model.lists.searched()
        XCTAssertEqual(model.entries.map(\.id), [harbor.id])
        model.query = "HILLS"
        await model.lists.searched()
        XCTAssertEqual(model.entries.map(\.id), [hills.id])

        var moved = hills
        moved.document = .plain("Back down by the harbor")
        model.items = [journal, harbor, moved]
        model.query = "harbor"
        await model.lists.searched()
        XCTAssertEqual(Set(model.entries.map(\.id)), [harbor.id, hills.id])
        model.query = ""
        XCTAssertEqual(model.entries.count, 2)
    }

    func testTheListShowsSavedWritingInPlace() async throws {
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        let journal = JournalItem(kind: "journal", title: "Daily")
        let older = JournalItem(
            kind: "entry", journalID: journal.id, title: "Older", date: Date(timeIntervalSince1970: 1_000))
        let newer = JournalItem(
            kind: "entry", journalID: journal.id, title: "Newer", date: Date(timeIntervalSince1970: 2_000))
        for item in [journal, older, newer] { try await store.save(item) }
        let model = AppModel(directory: root)
        model.store = store
        model.configuration = LocalConfiguration(recovery: .unprotected, recoveryConfirmed: true)
        try await model.refresh()
        model.selectedJournalID = journal.id
        XCTAssertEqual(model.entries.map(\.id), [newer.id, older.id])
        let row = model.rowKey(try XCTUnwrap(model.entries.last), accessibilitySize: false)
        let selected = await model.select(older.id)
        XCTAssertTrue(selected)

        var typed = try XCTUnwrap(model.draft)
        typed.document = .plain("Writing that the list shows")
        model.updateDraft(typed)
        let saved = await model.finishPendingSave()
        XCTAssertTrue(saved)
        XCTAssertEqual(model.entries.map(\.id), [newer.id, older.id])
        XCTAssertEqual(model.entries.last?.document.text, "Writing that the list shows")
        XCTAssertEqual(model.entryGroups.flatMap(\.1).last?.document.text, "Writing that the list shows")
        // The row is rebuilt only when its key changes, and then shows the saved writing.
        let savedRow = try XCTUnwrap(model.entries.last)
        XCTAssertNotEqual(model.rowKey(savedRow, accessibilitySize: false), row)
        XCTAssertEqual(model.listPreview(of: savedRow), "Writing that the list shows")
        try await store.close()
    }

    /// Recently Deleted is rebuilt only when its key changes: a template deleted elsewhere, the search, which filters
    /// deleted templates as it's typed, and a permanent deletion must each change it while the list stays open.
    func testRecentlyDeletedFollowsTemplatesWhileItIsShown() async throws {
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        let journal = JournalItem(kind: "journal", title: "Daily")
        let template = JournalItem(kind: "template", title: "Gratitude", document: .plain("Three good things"))
        for item in [journal, template] { try await store.save(item) }
        let model = AppModel(directory: root)
        model.store = store
        model.configuration = LocalConfiguration(recovery: .unprotected, recoveryConfirmed: true)
        try await model.refresh()
        model.showingTrash = true
        func listKey() -> EntryListKey {
            model.listKey(accessibilitySize: false, stacked: false, searchPresented: false)
        }
        var shown = listKey()
        XCTAssertTrue(model.filteredDeletedTemplates.isEmpty)

        // Deleted on another device; the next sync reads the library again.
        var deleted = template
        deleted.deletedAt = Date()
        try await store.save(deleted)
        try await model.refresh()
        XCTAssertEqual(model.filteredDeletedTemplates.map(\.id), [template.id])
        XCTAssertNotEqual(listKey(), shown)

        shown = listKey()
        model.query = "good things"
        XCTAssertNotEqual(listKey(), shown)
        XCTAssertEqual(model.filteredDeletedTemplates.map(\.id), [template.id])
        shown = listKey()
        model.query = "harbor"
        XCTAssertNotEqual(listKey(), shown)
        XCTAssertTrue(model.filteredDeletedTemplates.isEmpty)
        model.query = ""

        shown = listKey()
        let confirmation = try await model.preparePermanentDeletion(template.id)
        let refreshed = try await model.permanentlyDelete(confirmation)
        XCTAssertTrue(refreshed)
        XCTAssertTrue(model.showingTrash)
        XCTAssertTrue(model.filteredDeletedTemplates.isEmpty)
        XCTAssertNotEqual(listKey(), shown)
        try await store.close()
    }

    func testLockingForgetsTheTextKeptForSearch() async throws {
        let model = AppModel(directory: root)
        model.configuration = LocalConfiguration(
            recovery: .unprotected, recoveryConfirmed: true, appLock: true)
        let journal = JournalItem(kind: "journal", title: "Daily")
        let secret = JournalItem(kind: "entry", journalID: journal.id, document: .plain("A private thought"))
        model.items = [journal, secret]
        var found = await model.matchingEntries("private")
        XCTAssertEqual(found, [secret.id])

        XCTAssertTrue(model.lockImmediately())
        await model.lists.indexed()
        found = await model.lists.index.matches("private")
        XCTAssertTrue(found.isEmpty)
    }
    #if os(macOS)
        /// The Mac window's list column draws its rows as available, in the system's text colors. Its rows were
        /// navigation links, which AppKit's split view (outside any navigation container) can't follow, so every
        /// entry and template looked dimmed as if disabled.
        func testTheMacListDrawsItsRowsUndimmed() async throws {
            let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
            let journal = JournalItem(kind: "journal", title: "Daily")
            let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Harbor walk")
            let template = JournalItem(kind: "template", title: "Weekly review")
            for item in [journal, entry, template] { try await store.save(item) }
            let model = AppModel(directory: root)
            model.store = store
            model.configuration = LocalConfiguration(recovery: .unprotected, recoveryConfirmed: true)
            // Not asked to encrypt: the window shows the list.
            model.encryption.notNow()
            model.loaded = true
            try await model.refresh()
            model.showingAllEntries = true
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1100, height: 600), styleMask: [.titled, .resizable],
                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            let controller = NSHostingController(
                rootView: RootView().environmentObject(model).environmentObject(EditorActions()))
            controller.sizingOptions = []
            window.contentViewController = controller
            window.setContentSize(NSSize(width: 1100, height: 600))
            window.orderFront(nil)
            defer { window.close() }

            try await assertRowsUndimmed(in: window, "All Entries")
            model.showingAllEntries = false
            model.showingTemplates = true
            try await assertRowsUndimmed(in: window, "Templates")
            try await store.close()
        }

        /// Waits for the list column to draw rows, then checks that its darkest gray is near the label color's
        /// black: a dimmed row's title is mid-gray. Colored pixels, such as a selection, aren't text.
        private func assertRowsUndimmed(
            in window: NSWindow, _ collection: String, file: StaticString = #filePath, line: UInt = #line
        ) async throws {
            var darkest = 1.0
            let deadline = Date().addingTimeInterval(5)
            repeat {
                try await Task.sleep(nanoseconds: 100_000_000)
                guard let list = Self.splitController(in: window.contentView)?.listHost.view else { continue }
                list.layoutSubtreeIfNeeded()
                darkest = Self.darkestGray(in: list)
            } while darkest > 0.3 && Date() < deadline
            XCTAssertLessThan(darkest, 0.3, "\(collection) rows are drawn dimmed", file: file, line: line)
        }

        private static func darkestGray(in view: NSView) -> Double {
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 1 }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard rep.bitsPerSample == 8, rep.samplesPerPixel >= 3, !rep.isPlanar, let data = rep.bitmapData else {
                return 1
            }
            // Only opaque pixels: a transparent one reads as black.
            let alphaFirst = rep.bitmapFormat.contains(.alphaFirst)
            let first = rep.hasAlpha && alphaFirst ? 1 : 0
            let alpha = rep.hasAlpha ? (alphaFirst ? 0 : 3) : nil
            var darkest = 255
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide {
                    let pixel = data + y * rep.bytesPerRow + x * rep.bitsPerPixel / 8
                    if let alpha, pixel[alpha] < 250 { continue }
                    let channels = [Int(pixel[first]), Int(pixel[first + 1]), Int(pixel[first + 2])]
                    guard let low = channels.min(), let high = channels.max(), high - low < 20 else { continue }
                    darkest = min(darkest, high)
                }
            }
            return Double(darkest) / 255
        }

        private static func splitController(in view: NSView?) -> JournalSplitViewController? {
            guard let view else { return nil }
            if let controller = (view as? NSSplitView)?.delegate as? JournalSplitViewController { return controller }
            return view.subviews.lazy.compactMap { splitController(in: $0) }.first
        }
    #endif
}
