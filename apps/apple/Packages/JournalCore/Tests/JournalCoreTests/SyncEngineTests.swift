import CryptoKit
import XCTest
import os

@testable import JournalCore

/// A server in memory with the protocol's revision, cursor and image rules.
actor MemoryServer: SyncServer {
    struct State {
        var records: [UUID: RemoteChange] = [:]
        var log: [RemoteChange] = []
        var nextCursor: Int64 = 1
        var images: [UUID: Data] = [:]
        /// Every operation applied, as the server keeps them to answer a repeated request the same way.
        var operations: [UUID: (payload: String, change: RemoteChange)] = [:]
    }
    var state = State()
    /// Images larger than this are refused, like a proxy with a small upload limit.
    var uploadLimit = Int.max
    var pageRequests = 0
    /// Changes sent to devices in pages.
    var changesSent = 0
    /// Record changes received, including repeated ones, and images sent to devices.
    var pushes: [PendingChange] = []
    var downloads = 0
    /// Applies the next change but loses the answer, as a dropped connection would.
    private var losesNextAnswer = false
    /// Whether each push asked for a short receipt; one that asks gets it, read back by the real decoder.
    var shortReceiptRequests: [Bool] = []
    /// Waits answer from `waitAnswers` in order, then `unchanged`.
    /// The identity pages and the status report, and the newest cursor that existed when it was assigned.
    var serverID = "memory-server"
    var identityCursor: Int64 = 0
    var waitAnswers: [WaitAnswer] = []
    var waitPositions: [QuietPosition] = []
    private var pushesBeforeFailure: Int?
    private var stallsPages = false
    private var failsNextPage = false
    private var failsPageAfterNextPush = false
    /// Runs while the next change is being sent, before the server applies it.
    private var whileSendingNext: (@Sendable () async -> Void)?
    private var holdsNextPage = false
    private var heldPage: CheckedContinuation<Void, Never>?
    private var pageHeld: CheckedContinuation<Void, Never>?

    /// What the status says instead of a healthy server's, such as a server below protocol revision 1.
    var statusOverride: ServerStatus?
    func status() -> ServerStatus { statusOverride ?? .healthy(serverId: serverID) }
    func report(_ status: ServerStatus?) { statusOverride = status }
    func changes(after cursor: Int64, limit: Int, applied: LoggedChange?) async throws -> SyncPage {
        pageRequests += 1
        if let applied, cursor > 0,
            !state.log.contains(where: {
                $0.cursor == cursor && $0.recordId == applied.recordId && $0.revision == applied.revision
                    && (applied.digest == nil || JournalStore.payloadDigest($0.payload) == applied.digest)
            })
        {
            throw SyncLogChanged()
        }
        if failsNextPage {
            failsNextPage = false
            throw URLError(.networkConnectionLost)
        }
        if holdsNextPage {
            holdsNextPage = false
            await withCheckedContinuation { continuation in
                heldPage = continuation
                pageHeld?.resume()
                pageHeld = nil
            }
        }
        if stallsPages {
            return SyncPage(
                changes: [], cursor: cursor, hasMore: true, serverId: serverID, serverIdCursor: identityCursor)
        }
        let newer = state.log.filter { $0.cursor > cursor }
        let page = Array(newer.prefix(limit))
        changesSent += page.count
        return SyncPage(
            changes: page, cursor: page.last?.cursor ?? cursor, hasMore: newer.count > page.count,
            serverId: serverID, serverIdCursor: identityCursor)
    }
    func push(_ pending: PendingChange, serverID: String?, shortReceipt: Bool) async throws -> ServerClient.PushResult {
        try await push(pending, from: nil, shortReceipt: shortReceipt)
    }
    /// A push from the device `device`, whose identity the change carries as a real server records it.
    func push(_ pending: PendingChange, from device: UUID?, shortReceipt: Bool) async throws
        -> ServerClient.PushResult
    {
        shortReceiptRequests.append(shortReceipt)
        if let remaining = pushesBeforeFailure {
            pushesBeforeFailure = remaining > 1 ? remaining - 1 : nil
            if remaining == 1 { throw ServerUnavailable() }
        }
        let result = try await apply(pending, from: device)
        guard shortReceipt, case .accepted(let change) = result else { return result }
        return .accepted(try ServerClient.receipt(Self.shortReceipt(change), for: pending))
    }
    /// The short receipt a server sends for `change` to a push that asks for one.
    static func shortReceipt(_ change: RemoteChange) throws -> Data {
        struct Short: Encodable {
            var cursor: Int64
            var recordId: UUID
            var revision: Int64
            var kind: String
            var deviceId: UUID
            var modifiedAt: Date
            var payloadDigest: String
        }
        return try JournalCoding.encoder().encode(
            Short(
                cursor: change.cursor, recordId: change.recordId, revision: change.revision, kind: change.kind,
                deviceId: change.deviceId, modifiedAt: change.modifiedAt,
                payloadDigest: JournalStore.payloadDigest(change.payload)))
    }
    func waitForChange(_ position: QuietPosition, digest: Bool) -> WaitAnswer {
        waitPositions.append(position)
        return waitAnswers.isEmpty ? .unchanged(early: false) : waitAnswers.removeFirst()
    }
    /// The `count`th push from now fails with a server error before anything is applied.
    func failPush(number count: Int) { pushesBeforeFailure = count }
    func holdWaits(answering answers: [WaitAnswer] = []) { waitAnswers = answers }
    private func apply(_ pending: PendingChange, from device: UUID?) async throws -> ServerClient.PushResult {
        if let action = whileSendingNext {
            whileSendingNext = nil
            await action()
        }
        pushes.append(pending)
        if failsPageAfterNextPush {
            failsPageAfterNextPush = false
            failsNextPage = true
        }
        if let applied = state.operations[pending.operationId] {
            // The same request is answered as before; another one with this identifier is refused.
            guard applied.payload == pending.payload else { throw SyncRejection(reason: .invalid) }
            return .accepted(applied.change)
        }
        let current = state.records[pending.recordID]
        let revision = current?.revision ?? 0
        if let current, revision != pending.baseRevision {
            return pending.baseRevision > revision ? .serverBehind : .conflict(current)
        }
        guard revision == pending.baseRevision else { return .serverBehind }
        let change = RemoteChange(
            cursor: state.nextCursor, recordId: pending.recordID, revision: revision + 1, kind: pending.kind,
            payload: pending.payload, deviceId: device ?? UUID(),
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000))
        state.nextCursor += 1
        state.log.append(change)
        state.records[pending.recordID] = change
        state.operations[pending.operationId] = (pending.payload, change)
        if losesNextAnswer {
            losesNextAnswer = false
            throw URLError(.networkConnectionLost)
        }
        return .accepted(change)
    }
    func loseNextAnswer() { losesNextAnswer = true }
    func upload(_ bytes: Data, id: UUID) throws {
        guard bytes.count <= uploadLimit else { throw SyncRejection(reason: .tooLarge) }
        state.images[id] = bytes
    }
    func hasAttachment(_ id: UUID) -> Bool? { state.images[id] != nil }
    func downloadAttachment(_ id: UUID) throws -> Data {
        guard let image = state.images[id] else { throw JournalError.server("Image unavailable.") }
        downloads += 1
        return image
    }
    func record(_ id: UUID) -> RemoteChange? { state.records[id] }
    func loseImage(_ id: UUID) -> Data? { state.images.removeValue(forKey: id) }
    func receiveImage(_ image: Data, id: UUID) { state.images[id] = image }
    func limitUploads(to bytes: Int) { uploadLimit = bytes }
    func stallPages() { stallsPages = true }
    /// Fails the page request after the next change sent, as when the connection drops right after it was accepted.
    func failPageAfterNextPush() { failsPageAfterNextPush = true }
    func whileSendingNext(_ action: @escaping @Sendable () async -> Void) { whileSendingNext = action }
    /// Restores a copy of the server's data without a new identity, as copying its data folder back would.
    func rollBack(to earlier: State) { state = earlier }
    /// Restores a backup with `--restore`: the server takes a new identity, and changes up to the backup's newest
    /// cursor predate it.
    func restore(_ backup: State, identity: String) {
        state = backup
        serverID = identity
        identityCursor = backup.nextCursor - 1
    }
    /// The library record's values as the server holds them, opened with `store`'s key.
    func libraryValues(openedBy store: JournalStore) async -> [String: JSONValue]? {
        guard let record = state.records[LibraryRecord.id] else { return nil }
        return await store.libraryValues(inPayload: record.payload)
    }
    /// Holds the next page request until `releasePage()`.
    func holdNextPage() { holdsNextPage = true }
    /// Returns once a page request is held.
    func pageIsHeld() async {
        guard heldPage == nil else { return }
        await withCheckedContinuation { pageHeld = $0 }
    }
    func releasePage() {
        heldPage?.resume()
        heldPage = nil
    }
}

final class SyncEngineTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
    private func device(_ name: String) throws -> JournalStore {
        let store = try JournalStore(directory: root.appendingPathComponent(name), key: key)
        addTeardownBlock { try? await store.close() }
        return store
    }
    private func text(_ store: JournalStore, _ id: UUID) async throws -> String? {
        try await store.item(id)?.document.text
    }
    private func item(_ store: JournalStore, _ id: UUID) async throws -> JournalItem {
        let stored = try await store.item(id)
        return try XCTUnwrap(stored)
    }

    func testImagesUsedOnlyByAVersionAwaitingReviewAreDownloadedSoExportWorks() async throws {
        let server = MemoryServer()
        let mac = try device("mac")
        let phone = try device("phone")
        let macSync = SyncEngine(store: mac, server: server)
        let phoneSync = SyncEngine(store: phone, server: server)
        var entry = JournalItem(kind: "entry", journalID: UUID(), document: .plain("Shared"))
        try await phone.save(entry)
        try await phoneSync.synchronize()
        try await macSync.synchronize()

        var fromMac = try await item(mac, entry.id)
        fromMac.document = .plain("Edited offline on the Mac")
        try await mac.save(fromMac)
        let photo = Data("photo from the phone".utf8)
        let photoID = try await phone.addAttachment(photo)
        entry = try await item(phone, entry.id)
        entry.document = .init(blocks: [DocumentBlock(kind: "image", attachmentID: photoID, imageDescription: "")])
        try await phone.save(entry)
        try await phoneSync.synchronize()
        try await macSync.synchronize()

        let conflicts = try await mac.conflicts()
        XCTAssertEqual(conflicts.first?.remote.document.attachmentIDs, [photoID])
        let downloaded = try await mac.attachment(photoID)
        XCTAssertEqual(downloaded, photo)
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: VaultCrypto.recoveryPhrase()).0
        try await VaultArchive.export(
            store: mac, recovery: recovery, key: key, to: root.appendingPathComponent("backup.journalarchive"))
    }

    func testARecordOrImageTheServerCantTakeStaysOnThisDeviceWithoutStoppingOthers() async throws {
        let server = MemoryServer()
        let mac = try device("mac")
        let phone = try device("phone")
        let macSync = SyncEngine(store: mac, server: server, recordLimit: 4096)
        let fromPhone = JournalItem(kind: "entry", journalID: UUID(), document: .plain("Written on the phone"))
        try await phone.save(fromPhone)
        try await SyncEngine(store: phone, server: server).synchronize()

        var long = JournalItem(kind: "entry", journalID: UUID(), title: "Server log")
        long.document = .plain(String(repeating: "A long pasted log line. ", count: 200))
        let short = JournalItem(kind: "entry", journalID: UUID(), document: .plain("A short note"))
        await server.limitUploads(to: 1000)
        let photoID = try await mac.addAttachment(Data(repeating: 7, count: 5000))
        let withPhoto = JournalItem(
            kind: "entry", journalID: UUID(),
            document: .init(blocks: [DocumentBlock(kind: "image", attachmentID: photoID, imageDescription: "")]))
        for item in [long, short, withPhoto] { try await mac.save(item) }
        let report = try await macSync.synchronize()

        XCTAssertEqual(
            report.problem,
            "“Server log” is too large to sync. It’s saved on this device. Shorten it or split it into separate entries."
        )
        let sent = await server.record(short.id)
        XCTAssertNotNil(sent)
        let received = try await text(mac, fromPhone.id)
        XCTAssertEqual(received, "Written on the phone")
        let heldBack = await (server.record(long.id), server.record(withPhoto.id))
        XCTAssertNil(heldBack.0)
        XCTAssertNil(heldBack.1, "A record isn't sent before the image it uses")

        long.document = .plain("Shortened")
        try await mac.save(long)
        await server.limitUploads(to: .max)
        let later = try await macSync.synchronize()
        XCTAssertNotNil(later.problem, "An automatic sync doesn't send a refused image again")
        let shortened = await server.record(long.id)
        XCTAssertNotNil(shortened)
        let retried = try await macSync.synchronize(retryingRefused: true)
        XCTAssertNil(retried.problem, "Try Again sends the refused image once more")
        let sentWithPhoto = await server.record(withPhoto.id)
        XCTAssertNotNil(sentWithPhoto)
    }

    func testAnImageTheServerCantProvideDoesNotStopSyncAndIsTriedAgain() async throws {
        let server = MemoryServer()
        let mac = try device("mac")
        let phone = try device("phone")
        let clock = OSAllocatedUnfairLock(initialState: Date())
        let macSync = SyncEngine(store: mac, server: server, now: { clock.withLock { $0 } })
        let photoID = try await phone.addAttachment(Data("photo".utf8))
        let entry = JournalItem(
            kind: "entry", journalID: UUID(),
            document: .init(blocks: [DocumentBlock(kind: "image", attachmentID: photoID, imageDescription: "")]))
        try await phone.save(entry)
        try await SyncEngine(store: phone, server: server).synchronize()
        let lostImage = await server.loseImage(photoID)
        let image = try XCTUnwrap(lostImage)
        let before = await mac.receivedChangeCount()

        try await macSync.synchronize()
        let arrived = try await mac.item(entry.id)
        XCTAssertNotNil(arrived, "The entry arrives without its image")
        let missing = await mac.missingAttachments([photoID])
        XCTAssertEqual(missing, [photoID])
        let afterEntry = await mac.receivedChangeCount()
        XCTAssertGreaterThan(afterEntry, before)
        try await macSync.synchronize()
        let unchanged = await mac.receivedChangeCount()
        XCTAssertEqual(unchanged, afterEntry, "Nothing new arrived, so nothing needs to be shown again")

        await server.receiveImage(image, id: photoID)
        clock.withLock { $0 = $0.addingTimeInterval(20) }
        try await macSync.synchronize()
        let downloaded = try await mac.attachment(photoID)
        XCTAssertEqual(downloaded, Data("photo".utf8))
    }

    func testASyncRequestedDuringAnotherOneRunsAfterIt() async throws {
        let server = MemoryServer()
        let mac = try device("mac")
        let engine = SyncEngine(store: mac, server: server)
        await server.holdNextPage()
        let first = Task { try await engine.synchronize() }
        await server.pageIsHeld()
        let written = JournalItem(kind: "entry", journalID: UUID(), document: .plain("Written during a sync"))
        try await mac.save(written)
        let release = Task {
            try await Task.sleep(nanoseconds: 100_000_000)
            await server.releasePage()
        }
        try await engine.synchronize()
        let sent = await server.record(written.id)
        XCTAssertNotNil(sent, "The requested sync ran after the earlier one, not merely beside it")
        _ = try await first.value
        try await release.value
    }

    func testAServerThatDoesNotMoveForwardStopsTheSync() async throws {
        let server = MemoryServer()
        await server.stallPages()
        do {
            try await SyncEngine(store: try device("mac"), server: server).synchronize()
            XCTFail("A page that claims more without moving forward must not be followed")
        } catch JournalError.invalidData {}
        let requests = await server.pageRequests
        XCTAssertEqual(requests, 1)
    }

    func testAServerRestoredFromACopyOfItsDataIsReadAgain() async throws {
        let server = MemoryServer()
        let mac = try device("mac")
        let phone = try device("phone")
        let phoneSync = SyncEngine(store: phone, server: server)
        let first = JournalItem(kind: "entry", journalID: UUID(), document: .plain("First"))
        try await phone.save(first)
        try await phoneSync.synchronize()
        let copy = await server.state
        let lost = JournalItem(kind: "entry", journalID: UUID(), document: .plain("Lost by the server"))
        try await phone.save(lost)
        try await phone.save(JournalItem(kind: "entry", journalID: UUID(), document: .plain("Also lost")))
        try await phoneSync.synchronize()
        let macSync = SyncEngine(store: mac, server: server)
        try await macSync.synchronize()

        await server.rollBack(to: copy)
        let tablet = JournalItem(kind: "entry", journalID: UUID(), document: .plain("Written after the restore"))
        let tabletStore = try device("tablet")
        try await tabletStore.save(tablet)
        try await SyncEngine(store: tabletStore, server: server).synchronize()
        var edited = try await item(mac, first.id)
        edited.document = .plain("First, edited on the Mac")
        try await mac.save(edited)
        try await macSync.synchronize()

        let received = try await text(mac, tablet.id)
        XCTAssertEqual(received, "Written after the restore", "Changes reusing positions this device saw arrive")
        let restoredToServer = await server.record(lost.id)
        XCTAssertNotNil(restoredToServer, "Records the server lost are sent again")
    }

    /// A device that only receives keeps reading after its cursor. When the server's data folder is replaced by an
    /// older copy, new changes reuse positions this device already read, so they are found only by confirming the
    /// change it read last.
    func testADeviceThatOnlyReceivesNoticesAServerRestoredFromACopy() async throws {
        let server = MemoryServer()
        let phone = try device("phone")
        let mac = try device("mac")
        let phoneSync = SyncEngine(store: phone, server: server)
        let first = JournalItem(kind: "entry", journalID: UUID(), document: .plain("First"))
        try await phone.save(first)
        try await phoneSync.synchronize()
        let copy = await server.state
        let lost = JournalItem(kind: "entry", journalID: UUID(), document: .plain("Lost by the server"))
        try await phone.save(lost)
        try await phone.save(JournalItem(kind: "entry", journalID: UUID(), document: .plain("Also lost")))
        try await phoneSync.synchronize()
        let macSync = SyncEngine(store: mac, server: server)
        try await macSync.synchronize()

        await server.rollBack(to: copy)
        let tabletStore = try device("tablet")
        let written = [
            JournalItem(kind: "entry", journalID: UUID(), document: .plain("Written after the restore")),
            JournalItem(kind: "entry", journalID: UUID(), document: .plain("Also written after it")),
        ]
        for item in written { try await tabletStore.save(item) }
        try await SyncEngine(store: tabletStore, server: server).synchronize()
        try await macSync.synchronize()

        for item in written {
            let received = try await text(mac, item.id)
            XCTAssertEqual(received, item.document.text, "Changes at positions this device read before arrive")
        }
        let restoredToServer = await server.record(lost.id)
        XCTAssertNotNil(restoredToServer, "Records the server lost are sent again")
    }

    /// Before sending, a device confirms the server still has the change it read last. Otherwise an edit based on a
    /// revision number the restored server reused would replace another device's version unseen.
    func testAnEditIsNotSentOverAVersionWrittenAfterTheServerWasRestoredFromACopy() async throws {
        let server = MemoryServer()
        let phone = try device("phone")
        let mac = try device("mac")
        let phoneSync = SyncEngine(store: phone, server: server)
        let macSync = SyncEngine(store: mac, server: server)
        var entry = JournalItem(kind: "entry", journalID: UUID(), document: .plain("Shared"))
        try await phone.save(entry)
        try await phoneSync.synchronize()
        let copy = await server.state
        entry = try await item(phone, entry.id)
        entry.document = .plain("Edited on the phone")
        try await phone.save(entry)
        try await phoneSync.synchronize()
        try await macSync.synchronize()

        await server.rollBack(to: copy)
        let tablet = try device("tablet")
        let tabletSync = SyncEngine(store: tablet, server: server)
        try await tablet.save(JournalItem(kind: "entry", journalID: UUID(), document: .plain("A new entry")))
        try await tabletSync.synchronize()
        var fromTablet = try await item(tablet, entry.id)
        fromTablet.document = .plain("Edited on the tablet after the restore")
        try await tablet.save(fromTablet)
        try await tabletSync.synchronize()
        var fromMac = try await item(mac, entry.id)
        fromMac.document = .plain("Edited on the Mac")
        try await mac.save(fromMac)
        try await macSync.synchronize()

        let conflicts = try await mac.conflicts()
        XCTAssertEqual(conflicts.first?.remote.document.text, "Edited on the tablet after the restore")
        XCTAssertEqual(conflicts.first?.local.document.text, "Edited on the Mac")
        try await tabletSync.synchronize()
        let kept = try await text(tablet, entry.id)
        XCTAssertEqual(kept, "Edited on the tablet after the restore", "The tablet's version wasn't replaced unseen")
    }

    /// The server accepts the phone's edit, but the connection drops before the phone reads on, and then the server's
    /// data folder is replaced by an older copy without that edit. The Mac's edit of the same entry then gets the same
    /// revision number: the phone keeps both for review instead of ignoring the Mac's.
    func testAnAcceptedEditTheServerLostBecomesAReviewWithTheVersionWrittenInstead() async throws {
        let server = MemoryServer()
        let phone = try device("phone")
        let mac = try device("mac")
        let phoneSync = SyncEngine(store: phone, server: server)
        let macSync = SyncEngine(store: mac, server: server)
        var entry = try await phone.save(JournalItem(kind: "entry", journalID: UUID(), document: .plain("Shared")))
        try await phoneSync.synchronize()
        try await macSync.synchronize()
        let copy = await server.state
        entry = try await item(phone, entry.id)
        entry.document = .plain("Written on the phone")
        try await phone.save(entry)
        await server.failPageAfterNextPush()
        do {
            try await phoneSync.synchronize()
            XCTFail("The connection dropped")
        } catch is URLError {}

        await server.rollBack(to: copy)
        var fromMac = try await item(mac, entry.id)
        fromMac.document = .plain("Written on the Mac")
        try await mac.save(fromMac)
        try await macSync.synchronize()
        try await phoneSync.synchronize()

        let reviews = try await phone.conflicts()
        XCTAssertEqual(reviews.map(\.local.document.text), ["Written on the phone"])
        XCTAssertEqual(reviews.map(\.remote.document.text), ["Written on the Mac"])
        let review = try XCTUnwrap(reviews.first)
        try await phone.resolve(review, choice: .local)
        try await phoneSync.synchronize()
        try await macSync.synchronize()
        let onMac = try await text(mac, entry.id)
        XCTAssertEqual(onMac, "Written on the phone", "The version chosen in the review reaches the other device")
    }

    /// While the phone sends an edit, a window holding an older copy of the entry saves it, and the person keeps that
    /// version in the review before the edit is accepted. That version and later edits still reach other devices.
    func testAVersionChosenInAReviewWhileTheEntryWasBeingSentIsSent() async throws {
        let server = MemoryServer()
        let phone = try device("phone")
        let phoneSync = SyncEngine(store: phone, server: server)
        let entry = try await phone.save(JournalItem(kind: "entry", journalID: UUID(), document: .plain("First")))
        try await phoneSync.synchronize()
        let olderCopy = try await item(phone, entry.id)
        var edited = olderCopy
        edited.document = .plain("Edited")
        try await phone.save(edited)
        await server.whileSendingNext {
            var stale = olderCopy
            stale.document = .plain("Saved from another window")
            _ = try? await phone.save(stale)
            guard let review = try? await phone.conflicts().first else { return }
            _ = try? await phone.resolve(review, choice: .local)
        }
        try await phoneSync.synchronize()
        try await phoneSync.synchronize()
        let mac = try device("mac")
        let macSync = SyncEngine(store: mac, server: server)
        try await macSync.synchronize()
        let chosen = try await text(mac, entry.id)
        XCTAssertEqual(chosen, "Saved from another window")

        var later = try await item(phone, entry.id)
        later.document = .plain("Edited later")
        try await phone.save(later)
        try await phoneSync.synchronize()
        try await macSync.synchronize()
        let received = try await text(mac, entry.id)
        XCTAssertEqual(received, "Edited later")
        let pending = try await phone.hasPendingChanges()
        XCTAssertFalse(pending)
    }

    /// An earlier version could leave a change queued on a revision older than the one this device has, which the
    /// server then refused on every synchronization. It's sent on the current revision instead.
    func testAChangeQueuedOnAnOlderRevisionThanThisDeviceHasIsSent() async throws {
        let server = MemoryServer()
        let phone = try device("phone")
        let phoneSync = SyncEngine(store: phone, server: server)
        var entry = try await phone.save(JournalItem(kind: "entry", journalID: UUID(), document: .plain("First")))
        try await phoneSync.synchronize()
        entry = try await item(phone, entry.id)
        entry.document = .plain("Second")
        try await phone.save(entry)
        try await phoneSync.synchronize()
        entry = try await item(phone, entry.id)
        entry.document = .plain("Third")
        try await phone.save(entry)
        try await phone.db.write { try $0.execute(sql: "UPDATE outbox SET base=1") }

        try await phoneSync.synchronize()
        try await phoneSync.synchronize()
        let mac = try device("mac")
        try await SyncEngine(store: mac, server: server).synchronize()
        let received = try await text(mac, entry.id)
        XCTAssertEqual(received, "Third")
    }

    /// Setting the clock back, by hand or when a fast clock is corrected, doesn't hold what was written out of
    /// automatic synchronization until the clock catches up.
    func testWritingIsSentAfterTheClockWasSetBack() async throws {
        let server = MemoryServer()
        let phone = try device("phone")
        let entry = try await phone.save(
            JournalItem(kind: "entry", journalID: UUID(), document: .plain("Written before the clock changed")))
        let anHourEarlier = SyncEngine(store: phone, server: server, now: { Date().addingTimeInterval(-3600) })
        try await anHourEarlier.synchronize(.init(waitingForWritingPause: true))
        let sent = await server.record(entry.id)
        XCTAssertNotNil(sent)
    }

    func testWritingThatContinuesIsSentOnceItPausesAsOneRevisionOfItsLatestContent() async throws {
        let server = MemoryServer()
        let phone = try device("phone")
        var entry = try await phone.save(JournalItem(kind: "entry", journalID: UUID(), document: .plain("One")))
        for text in ["One two", "One two three"] {
            entry.document = .plain(text)
            entry = try await phone.save(entry)
        }
        try await SyncEngine(store: phone, server: server).synchronize(.init(waitingForWritingPause: true))
        let whileWriting = await server.record(entry.id)
        XCTAssertNil(whileWriting, "Automatic sync waits until writing pauses")

        let paused = SyncEngine(store: phone, server: server, now: { Date().addingTimeInterval(3) })
        try await paused.synchronize(.init(waitingForWritingPause: true))
        let pushes = await server.pushes.filter { $0.recordID == entry.id }
        XCTAssertEqual(pushes.count, 1, "The writing reaches the server as one revision")
        let mac = try device("mac")
        try await SyncEngine(store: mac, server: server).synchronize()
        let received = try await text(mac, entry.id)
        XCTAssertEqual(received, "One two three")
        let pending = try await phone.hasPendingChanges()
        XCTAssertFalse(pending)
    }

    /// While an entry is being written, an automatic synchronization only asks for new changes: nothing is sent, so
    /// there's nothing to confirm before sending.
    func testAutomaticSyncWhileWritingOnlyAsksForNewChanges() async throws {
        let server = MemoryServer()
        let phone = try device("phone")
        let sync = SyncEngine(store: phone, server: server)
        var entry = try await phone.save(JournalItem(kind: "entry", journalID: UUID(), document: .plain("One")))
        try await sync.synchronize()
        entry = try await item(phone, entry.id)
        entry.document = .plain("One two")
        try await phone.save(entry)
        let before = await server.pageRequests
        try await sync.synchronize(.init(waitingForWritingPause: true))
        let pages = await server.pageRequests
        XCTAssertEqual(pages - before, 1)
        let sent = await server.pushes.count
        XCTAssertEqual(sent, 1, "The entry being written waits")
    }

    func testARepeatedSendAfterALostAnswerCarriesTheSameContent() async throws {
        let server = MemoryServer()
        let phone = try device("phone")
        let sync = SyncEngine(store: phone, server: server)
        var entry = try await phone.save(JournalItem(kind: "entry", journalID: UUID(), document: .plain("Draft")))
        await server.loseNextAnswer()
        do {
            try await sync.synchronize()
            XCTFail("The answer was lost")
        } catch is URLError {}
        entry.document = .plain("Draft, continued while the connection was down")
        try await phone.save(entry)

        let report = try await sync.synchronize()
        XCTAssertNil(report.problem, "The server doesn't refuse the repeated request as a different one")
        try await sync.synchronize()
        let mac = try device("mac")
        try await SyncEngine(store: mac, server: server).synchronize()
        let received = try await text(mac, entry.id)
        XCTAssertEqual(received, "Draft, continued while the connection was down")
    }

    func testContentIsNeverSentBeforeAnImageItUsesIsOnTheServer() async throws {
        let server = MemoryServer()
        let phone = try device("phone")
        var entry = try await phone.save(JournalItem(kind: "entry", journalID: UUID(), document: .plain("Text")))
        await server.limitUploads(to: 10)
        let photoID = try await phone.addAttachment(Data(repeating: 1, count: 100))
        entry.document.blocks.append(DocumentBlock(kind: "image", attachmentID: photoID, imageDescription: ""))
        try await phone.save(entry)
        try await SyncEngine(store: phone, server: server).synchronize()

        let mac = try device("mac")
        try await SyncEngine(store: mac, server: server).synchronize()
        let received = try await item(mac, entry.id)
        XCTAssertEqual(received.document.text, "Text", "The earlier version went; the one with the image waits")
        let pending = try await phone.hasPendingChanges()
        XCTAssertTrue(pending)
    }

    func testAnImageRemovedAgainBeforeItSyncedIsNotUploadedUnlessUsedAgain() async throws {
        let server = MemoryServer()
        let phone = try device("phone")
        let removed = try await phone.addAttachment(Data("pasted by mistake".utf8))
        let kept = try await phone.addAttachment(Data("kept".utf8))
        var entry = JournalItem(
            kind: "entry", journalID: UUID(),
            document: .init(blocks: [DocumentBlock(kind: "image", attachmentID: removed, imageDescription: "")]))
        entry = try await phone.save(entry)
        entry.document = .init(blocks: [DocumentBlock(kind: "image", attachmentID: kept, imageDescription: "")])
        entry = try await phone.save(entry)
        let sync = SyncEngine(store: phone, server: server)
        try await sync.synchronize()
        var onServer = await (server.hasAttachment(removed), server.hasAttachment(kept))
        XCTAssertEqual(onServer.0, false)
        XCTAssertEqual(onServer.1, true)

        entry.document.blocks.append(DocumentBlock(kind: "image", attachmentID: removed, imageDescription: ""))
        try await phone.save(entry)
        try await sync.synchronize()
        onServer = await (server.hasAttachment(removed), server.hasAttachment(kept))
        XCTAssertEqual(onServer.0, true, "Used again, it is uploaded")
    }

    /// What this device sent isn't downloaded again when nothing came before it on the server; another device's change
    /// that did is received, with this device's own, and reading on from the change it sent stays confirmed.
    func testASentChangeIsNotDownloadedAgain() async throws {
        let server = MemoryServer()
        let mac = try device("mac")
        let phone = try device("phone")
        let macSync = SyncEngine(store: mac, server: server)
        var entry = try await mac.save(JournalItem(kind: "entry", journalID: UUID(), document: .plain("Mac")))
        try await macSync.synchronize()
        var sent = await server.changesSent
        XCTAssertEqual(sent, 0, "The Mac doesn't download the entry it just sent")

        let phoneSync = SyncEngine(store: phone, server: server)
        try await phoneSync.synchronize()
        let fromPhone = JournalItem(kind: "entry", journalID: UUID(), document: .plain("Phone"))
        try await phone.save(fromPhone)
        try await phoneSync.synchronize()
        entry.document = .plain("Mac, edited")
        entry = try await mac.save(entry)
        try await macSync.synchronize()
        let received = try await text(mac, fromPhone.id)
        XCTAssertEqual(received, "Phone", "A change that came between is received")
        let afterBetween = await server.changesSent

        entry.document = .plain("Mac, edited again")
        try await mac.save(entry)
        try await macSync.synchronize()
        try await macSync.synchronize()
        sent = await server.changesSent
        XCTAssertEqual(sent, afterBetween, "Nothing is downloaded again, and reading on is still confirmed")
        let cursor = try await mac.cursor()
        let last = await server.state.log.last?.cursor
        XCTAssertEqual(cursor, last)
        try await phoneSync.synchronize()
        let onPhone = try await text(phone, entry.id)
        XCTAssertEqual(onPhone, "Mac, edited again")
    }

    func testANewDeviceReceivesEveryEntryAtOnceAndImagesOverSeveralSynchronizations() async throws {
        let server = MemoryServer()
        let phone = try device("phone")
        var entries: [JournalItem] = []
        for index in 0..<3 {
            let photo = try await phone.addAttachment(Data("photo \(index)".utf8))
            let entry = JournalItem(
                kind: "entry", journalID: UUID(),
                document: .init(blocks: [DocumentBlock(kind: "image", attachmentID: photo, imageDescription: "")]))
            entries.append(try await phone.save(entry))
        }
        try await SyncEngine(store: phone, server: server).synchronize()

        // Each reading of the clock is three seconds later, so one synchronization has time for one image.
        let clock = OSAllocatedUnfairLock(initialState: Date())
        let tablet = try device("tablet")
        let sync = SyncEngine(
            store: tablet, server: server,
            now: {
                clock.withLock { time in
                    time = time.addingTimeInterval(3)
                    return time
                }
            })
        let first = try await sync.synchronize()
        let arrived = try await tablet.items().filter { $0.kind == "entry" }
        XCTAssertEqual(arrived.count, 3, "Every entry is there before its images")
        XCTAssertEqual(first.imagesToDownload, 2)
        var downloads = await server.downloads
        XCTAssertEqual(downloads, 1)
        let second = try await sync.synchronize()
        let third = try await sync.synchronize()
        XCTAssertEqual([second.imagesToDownload, third.imagesToDownload], [1, 0])
        downloads = await server.downloads
        XCTAssertEqual(downloads, 3)
    }

}
