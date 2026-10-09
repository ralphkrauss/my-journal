import XCTest

@testable import JournalCore

/// When a device settles a conflict (protocol/conflicts.md, Resolution points): a conflict a stale save made is
/// settled once writing pauses even with a server configured and unreachable, and the refusal of an action that waits
/// for a conflict says when it ends.
final class ConflictResolutionPointsTests: ConflictTestCase {
    private let mac = UUID()

    private func entryInHome(_ title: String, in store: JournalStore, home: JournalItem) async throws -> JournalItem {
        let page = entry(title, text: "first", journal: home.id)
        try await settle(page, in: store)
        return try await stored(store, page.id)
    }
    private func version(of item: JournalItem, _ text: String) -> JournalItem {
        var other = item
        other.document = .plain(text)
        other.storedVersion = nil
        return other
    }

    func testAStaleSaveIsSettledOncePausedWithoutAPullAndTheRefusalClearsWithIt() async throws {
        let store = try await openStore()
        let home = journal("Home")
        let work = journal("Work")
        try await settle(home, in: store)
        try await settle(work, in: store)
        let opened = try await entryInHome("Page", in: store, home: home)
        // The other device's version arrived after the draft was read.
        try await deliver(version(of: opened, "Written elsewhere"), revision: 2, to: store, device: mac)
        var typed = opened
        typed.document = .plain("Typed here")
        try await store.save(typed)

        do {
            _ = try await store.moveEntry(opened.id, to: work.id)
            XCTFail("An entry with changes about to be combined is not moved")
        } catch let failure as JournalLifecycleError {
            XCTAssertEqual(
                failure.errorDescription,
                "Some changes from another device will finish combining when My Journal next syncs.",
                "It says what ends the wait, which is not a moment when there is no connection")
        }

        let writing = try await store.resolveConflicts(at: .afterStaleSave)
        XCTAssertEqual(writing.deferred, 1, "The person is still writing")
        XCTAssertTrue(writing.resolved.isEmpty)
        let paused = try await settleAfterPause(store, .afterStaleSave)
        XCTAssertEqual(paused.resolved.count, 1, "…and once writing pauses no pull is needed")
        let rows = try await store.conflicts()
        XCTAssertTrue(rows.isEmpty)
        let record = try await stored(store, opened.id)
        XCTAssertEqual(record.document.text, "Typed here")
        let moved = try await store.moveEntry(opened.id, to: work.id)
        XCTAssertEqual(moved.journalID, work.id, "The refusal cleared")
        let copies = try await store.items().filter { $0.title == "Page (other version)" }
        XCTAssertEqual(copies.map(\.document.text), ["Written elsewhere"])
    }

    func testAConflictFromAPullStillWaitsForACompletedPull() async throws {
        let store = try await openStore()
        let home = journal("Home")
        try await settle(home, in: store)
        let page = try await entryInHome("Page", in: store, home: home)
        var typed = page
        typed.document = .plain("Typed here")
        try await store.save(typed)
        try await deliver(version(of: page, "Written elsewhere"), revision: 2, to: store, device: mac)

        let stale = try await settleAfterPause(store, .afterStaleSave)
        XCTAssertTrue(stale.resolved.isEmpty, "Its other version may be an intermediate one until the pull is complete")
        let rows = try await store.conflicts()
        XCTAssertEqual(rows.count, 1)
        let pulled = try await store.resolveConflicts(at: .completedPull)
        XCTAssertEqual(pulled.resolved.count, 1)
    }

    func testAStaleSaveDoesNotSettleDuringAReconciliation() async throws {
        let store = try await openStore()
        let home = journal("Home")
        try await settle(home, in: store)
        let opened = try await entryInHome("Page", in: store, home: home)
        try await deliver(version(of: opened, "Written elsewhere"), revision: 2, to: store, device: mac)
        var typed = opened
        typed.document = .plain("Typed here")
        try await store.save(typed)
        try await store.beginReconciliation(serverID: "restored")
        let reconciling = try await settleAfterPause(store, .afterStaleSave)
        XCTAssertTrue(reconciling.resolved.isEmpty)
        try await store.setSetting("reconcile", value: nil)
        let after = try await settleAfterPause(store, .afterStaleSave)
        XCTAssertEqual(after.resolved.count, 1)
    }

    // MARK: The pass over rows an earlier version left

    func testAnOpeningWithoutRowsRecordsThePassSoALaterRowIsNotTakenForAnEarlierOne() async throws {
        let store = try await openStore(runPass: false)
        let home = journal("Home")
        try await settle(home, in: store)
        _ = try await store.resolveConflicts(at: .opening(serverConfigured: true))
        let page = try await entryInHome("Page", in: store, home: home)
        var typed = page
        typed.document = .plain("Typed here")
        try await store.save(typed)
        try await deliver(version(of: page, "Written elsewhere"), revision: 2, to: store, device: mac)
        let later = try await settleAfterPause(store, .opening(serverConfigured: true))
        XCTAssertTrue(later.resolved.isEmpty, "A row made after the first opening waits for a completed pull")
        let state = try await store.keptNotesState()
        XCTAssertEqual(state.passStep, JournalStore.passStepAllKinds)
    }

    func testTheSecondStepOfThePassTakesOnlyRowsThatExistedAtItsFirstOpening() async throws {
        let store = try await openStore("upgrade", runPass: false)
        let home = journal("Home")
        try await settle(home, in: store)
        let old = try await entryInHome("Old", in: store, home: home)
        var typed = old
        typed.document = .plain("Typed here")
        try await store.save(typed)
        try await deliver(version(of: old, "Left by 1.0"), revision: 2, to: store, device: mac)
        try await store.forgetThatThePassRan(throughStep: 1)

        let first = try await store.resolveConflicts(at: .opening(serverConfigured: true))
        XCTAssertEqual(first.resolved.count, 1, "The row the earlier version left")
        // A row made by this version in the middle of a paged catch-up, then a crash.
        let newer = try await entryInHome("Newer", in: store, home: home)
        var typedAgain = newer
        typedAgain.document = .plain("Typed here too")
        try await store.save(typedAgain)
        try await deliver(version(of: newer, "Intermediate page"), revision: 2, to: store, device: mac)
        let reopened = try await store.resolveConflicts(at: .opening(serverConfigured: true))
        XCTAssertTrue(reopened.resolved.isEmpty)
    }
}

extension JournalStore {
    /// Makes this library one that an earlier version left conflicts in: the pass has run through `step` only.
    func forgetThatThePassRan(throughStep step: Int = 0) throws {
        let notes = keptNotesStore
        try db.write { db in
            var state = try notes.state(db)
            state.passStep = step
            state.passRecords = nil
            try notes.save(db, state)
        }
        openingPassComplete = false
    }
}
