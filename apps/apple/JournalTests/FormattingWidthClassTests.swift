#if os(iOS)
    import UIKit
    import XCTest

    @testable import Journal

    @MainActor final class FormattingWidthClassTests: XCTestCase {
        /// Resizing a window (Stage Manager, iPadOS windowed apps) changes the width class without a transition, as a
        /// parent's trait override does here. Formatting must still hear of it, so it closes and the keyboard returns.
        func testWindowResizeAcrossWidthClassesClosesFormatting() throws {
            guard #available(iOS 17.0, *) else { throw XCTSkip("Trait overrides need iOS 17.") }
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
            let root = UIViewController()
            window.rootViewController = root
            root.traitOverrides.horizontalSizeClass = .compact
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            let controller = MobileFormattingPresenter.PresentingController()
            var changes = 0
            controller.sizeClassChanged = { changes += 1 }
            root.addChild(controller)
            root.view.addSubview(controller.view)
            controller.didMove(toParent: root)
            window.layoutIfNeeded()
            XCTAssertEqual(controller.traitCollection.horizontalSizeClass, .compact)
            changes = 0
            root.traitOverrides.horizontalSizeClass = .regular
            window.layoutIfNeeded()
            XCTAssertEqual(controller.traitCollection.horizontalSizeClass, .regular)
            XCTAssertGreaterThan(changes, 0, "Widening to regular width")
            changes = 0
            root.traitOverrides.horizontalSizeClass = .compact
            window.layoutIfNeeded()
            XCTAssertEqual(controller.traitCollection.horizontalSizeClass, .compact)
            XCTAssertGreaterThan(changes, 0, "Narrowing to compact width")
        }
    }
#endif
