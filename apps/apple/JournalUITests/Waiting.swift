import XCTest

// XCTest's waits first check their condition a second after they start, even when it already holds, and most of
// these tests' waits are for something already on screen: about a second each, over a thousand times in the iOS lane.
// These check at once and, only when that fails, wait as XCTest does, with the same timeouts and failure reports.
// Use XCTest's own waits to check that something stays absent, or before deciding where the app is just after it
// launches or unlocks, when it can still be restoring the last screen.

extension XCUIElement {
    /// waitForExistence(timeout:), returning at once when the element is already there.
    @MainActor func waitToAppear(timeout: TimeInterval) -> Bool {
        exists || waitForExistence(timeout: timeout)
    }

    /// waitForNonExistence(timeout:), returning at once when the element is already gone.
    @MainActor func waitToDisappear(timeout: TimeInterval) -> Bool {
        !exists || waitForNonExistence(timeout: timeout)
    }
}

enum Waiting {
    /// XCTWaiter.wait(for: [expectation], timeout:), completing at once when the predicate already holds.
    @MainActor static func wait(for expectation: XCTNSPredicateExpectation, timeout: TimeInterval) -> XCTWaiter.Result {
        if expectation.predicate.evaluate(with: expectation.object) {
            return .completed
        }
        return XCTWaiter.wait(for: [expectation], timeout: timeout)
    }
}

extension Waiting {
    /// Whether `condition` holds within `timeout`, checking at once first.
    @MainActor static func until(timeout: TimeInterval, _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return wait(for: expectation, timeout: timeout) == .completed
    }
}

// The app settles some states a moment after the element they belong to appears: a field's text, which field has
// the keyboard, whether a control can be used. These check such a state, allowing it `timeout` to arrive, and report
// the value last seen when it doesn't.

@MainActor func assertEventually<Value: Equatable>(
    _ actual: @escaping @autoclosure () -> Value, equals expected: Value, timeout: TimeInterval = 5,
    _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line
) {
    _ = Waiting.until(timeout: timeout) { actual() == expected }
    XCTAssertEqual(actual(), expected, message(), file: file, line: line)
}

@MainActor func assertEventually(
    _ condition: @escaping @autoclosure () -> Bool, timeout: TimeInterval = 5,
    _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertTrue(Waiting.until(timeout: timeout, condition), message(), file: file, line: line)
}
