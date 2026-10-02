import CryptoKit
import XCTest

@testable import JournalCore

/// Quitting sends saved writing for a few seconds at most and then cancels it. A synchronization waiting for
/// another one to finish must stop waiting when cancelled, without disturbing the gate for everyone else.
final class SynchronizationGateTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
    private func openStore() throws -> JournalStore {
        let store = try JournalStore(directory: root, key: key)
        addTeardownBlock { try? await store.close() }
        return store
    }
    private func waitUntilQueued(_ count: Int, in store: JournalStore) async throws {
        for _ in 0..<10_000 where await store.synchronizationWaiters.count != count {
            await Task.yield()
        }
        let queued = await store.synchronizationWaiters.count
        XCTAssertEqual(queued, count)
    }
    private func assertCancelled(_ waiter: Task<Void, any Error>, file: StaticString = #filePath, line: UInt = #line)
        async
    {
        do {
            try await waiter.value
            XCTFail("A cancelled synchronization took the gate", file: file, line: line)
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)", file: file, line: line)
        }
    }

    func testCancelledWaiterReturnsPromptlyAndLeavesTheGateWorking() async throws {
        let store = try openStore()
        try await store.beginSynchronization()
        // Only a regression reaches this: it bounds the test instead of letting it hang.
        let fallbackRelease = Task {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            await store.endSynchronization()
        }
        let cancelled = Task { try await store.beginSynchronization() }
        try await waitUntilQueued(1, in: store)
        let start = ProcessInfo.processInfo.systemUptime
        cancelled.cancel()
        await assertCancelled(cancelled)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        fallbackRelease.cancel()
        XCTAssertLessThan(elapsed, 0.5, "A cancelled waiter returned only after \(elapsed) seconds")

        // The owner still holds the gate, no cancelled waiter is left behind, and the next one is served.
        let stillHeld = await store.synchronizing
        XCTAssertTrue(stillHeld)
        let next = Task { try await store.beginSynchronization() }
        try await waitUntilQueued(1, in: store)
        await store.endSynchronization()
        try await next.value
        await store.endSynchronization()
        let released = await store.synchronizing
        XCTAssertFalse(released)
        try await store.beginSynchronization()
        await store.endSynchronization()
    }

    func testCancelledWaiterBeforeQueueingDoesNotTakeTheGate() async throws {
        let store = try openStore()
        try await store.beginSynchronization()
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await store.beginSynchronization()
        }
        await assertCancelled(cancelled)
        let queued = await store.synchronizationWaiters.count
        XCTAssertEqual(queued, 0)
        await store.endSynchronization()
        let released = await store.synchronizing
        XCTAssertFalse(released)
    }

    /// Cancellation can reach a waiter just as the gate is handed to it; the gate then passes to the next one.
    func testGateReleasedAsWaiterIsCancelledPassesToTheNextWaiter() async throws {
        let store = try openStore()
        try await store.beginSynchronization()
        let cancelled = Task { try await store.beginSynchronization() }
        try await waitUntilQueued(1, in: store)
        let next = Task { try await store.beginSynchronization() }
        try await waitUntilQueued(2, in: store)
        cancelled.cancel()
        await store.endSynchronization()
        await assertCancelled(cancelled)
        try await next.value
        await store.endSynchronization()
        let released = await store.synchronizing
        XCTAssertFalse(released)
    }
}
