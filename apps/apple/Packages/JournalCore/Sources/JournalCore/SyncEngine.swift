import Foundation

/// The server operations synchronization uses.
protocol SyncServer: Sendable {
    func status() async throws -> ServerStatus
    func changes(after: Int64, limit: Int, applied: LoggedChange?) async throws -> SyncPage
    func push(_ pending: PendingChange, serverID: String?, shortReceipt: Bool) async throws -> ServerClient.PushResult
    func upload(_ bytes: Data, id: UUID) async throws
    func hasAttachment(_ id: UUID) async throws -> Bool?
    func downloadAttachment(_ id: UUID) async throws -> Data
    /// How the server stores journals, from its recovery format; nil when it can't say.
    func contentProtection() async throws -> ContentProtection?
    /// Waits for the server's log to move past `position`. Throws only on cancellation.
    func waitForChange(_ position: QuietPosition, digest: Bool) async throws -> WaitAnswer
}
extension SyncServer {
    /// A server that can't say how it stores journals.
    func contentProtection() async throws -> ContentProtection? { nil }
    /// A server that can't hold a wait.
    func waitForChange(_ position: QuietPosition, digest: Bool) async throws -> WaitAnswer { .failed }
}
extension ServerClient: SyncServer {
    func waitForChange(_ position: QuietPosition, digest: Bool) async throws -> WaitAnswer {
        try await waitForChange(position, digest: digest, timeout: Self.waitSeconds)
    }
    func contentProtection() async throws -> ContentProtection? {
        try await recoveryParameters().contentProtection
    }
}

/// What a completed synchronization couldn't send.
public struct SyncReport: Sendable {
    /// Why a record or image isn't synchronized yet, when one can't be; everything else was synchronized.
    public let problem: String?
    /// Images still to download, which the next synchronization continues with.
    public var imagesToDownload = 0
    /// Nothing is left to send, upload, download, reconcile or rename, apart from items waiting for a retry time,
    /// and nothing is refused: the device may wait for changes instead of polling
    /// (docs/design/sync-protocol-efficiency.md §4.6).
    public var settled = false
    /// The soonest an item waiting for a retry time may be sent, from now.
    public var earliestRetry: TimeInterval?
    /// The store's state when this synchronization released it, for `JournalStore.quietPosition(since:)`.
    public var quietMark: QuietMark?
    /// Where this device is in the server's log afterwards.
    public var position: QuietPosition?
    /// Conflicts this synchronization settled on its own (protocol/conflicts.md).
    public var resolvedConflicts: [ResolvedConflict] = []
}

public actor SyncEngine {
    private let store: JournalStore
    private let server: any SyncServer
    /// Conflicts settled during the synchronization that is running, for its report.
    private var resolvedConflicts: [ResolvedConflict] = []
    /// Operations and images that failed and wait before the next attempt, so they don't hold up the rest.
    private var retries: [UUID: Retry] = [:]
    /// Operations the server didn't accept as they are, with the reason shown until their content changes.
    private var rejectedChanges: [UUID: (change: PendingChange, problem: String)] = [:]
    private var rejectedImages: [UUID: SyncRejection.Reason] = [:]
    /// Server errors in a row for one queued record while the rest of its synchronization succeeded.
    private var serverErrors: [UUID: Int] = [:]
    /// A record the server keeps failing on is refused at item level after this many attempts, so it doesn't make
    /// the whole synchronization look unavailable (docs/design/sync-health-and-recovery.md §2).
    static let serverErrorsBeforeRefusing = 3
    /// Images waiting for upload whose file is gone from this device; nothing waits for them.
    private var lostImages = Set<UUID>()
    /// Images referenced by synchronized records that aren't on this device yet.
    private var missingImages = Set<UUID>()
    private var checkedAllImages = false
    private var pageSize = 100
    /// Queued records this synchronization left only because they wait for a retry time or for images.
    private var waitingRecords = Set<UUID>()
    private let now: @Sendable () -> Date
    /// The server database changed during this synchronization; start again with its new identity.
    private struct ServerChanged: Error {}
    private struct Retry {
        var attempts: Int
        var after: Date
    }
    /// The status the last successful synchronization read, and when.
    private var statusRead: (status: ServerStatus, at: Date)?
    /// How long synchronizations that only receive reuse the server's status instead of asking for it each time.
    static let statusLifetime: TimeInterval = 60
    /// The server's limit for one encrypted record, 4 MiB.
    private let recordLimit: Int
    /// A record being written is sent once writing pauses this long, so the server keeps one revision per pause
    /// rather than one per synchronization, but at least this often while writing continues.
    public static let writingPause: TimeInterval = 2
    static let longestWritingWait: TimeInterval = 30
    /// How long one synchronization downloads images before it returns; the next one continues. Records never wait
    /// for images, so a new device shows its entries before all images arrived.
    static let imageTimePerPass: TimeInterval = 5

    public init(store: JournalStore, client: ServerClient) {
        self.init(store: store, server: client)
    }
    init(
        store: JournalStore, server: any SyncServer, now: @escaping @Sendable () -> Date = { Date() },
        recordLimit: Int = 4 * 1024 * 1024
    ) {
        self.store = store
        self.server = server
        self.now = now
        self.recordLimit = recordLimit
    }
    /// What one synchronization is asked to do.
    public struct Request: Sendable {
        /// Send records and images the server refused and ones waiting after a failure, as Sync Now and Try Again do;
        /// otherwise they wait until they change or their wait ends.
        public var retryingRefused = false
        /// Leave a record that is still being written for a later synchronization, once writing paused
        /// (`writingPause`), as automatic synchronization does. Otherwise everything saved is sent.
        public var waitingForWritingPause = false
        /// Images to download before others, such as those of the open entry.
        public var preferredImages: Set<UUID> = []
        /// Records whose conflicts are not settled in this synchronization, such as the open entry while a save of it
        /// has failed.
        public var holdingConflicts: Set<UUID> = []
        public init(
            retryingRefused: Bool = false, waitingForWritingPause: Bool = false, preferredImages: Set<UUID> = [],
            holdingConflicts: Set<UUID> = []
        ) {
            self.retryingRefused = retryingRefused
            self.waitingForWritingPause = waitingForWritingPause
            self.preferredImages = preferredImages
            self.holdingConflicts = holdingConflicts
        }
    }
    /// Runs a complete synchronization. A caller arriving while another one runs waits for it and then runs its
    /// own, so it never returns before its request was served.
    @discardableResult public func synchronize(retryingRefused: Bool = false) async throws -> SyncReport {
        try await synchronize(Request(retryingRefused: retryingRefused))
    }
    @discardableResult public func synchronize(_ request: Request) async throws -> SyncReport {
        // Throws only when cancelled before this synchronization took the gate, so it isn't released here.
        try await store.beginSynchronization()
        do {
            // Rows an earlier version left are settled before anything is read, so a pull can't replace their other
            // version first (protocol/conflicts.md, The pass over rows an earlier version left).
            resolvedConflicts = try await store.resolveConflicts(at: .opening(serverConfigured: true)).resolved
            var report = try await synchronizeAgainIfServerChanged(request)
            report.resolvedConflicts = resolvedConflicts
            report.quietMark = await store.endSynchronization()
            return report
        } catch {
            await store.endSynchronization()
            throw error
        }
    }
    private func synchronizeAgainIfServerChanged(_ request: Request) async throws -> SyncReport {
        do {
            return try await synchronizeOnce(request)
        } catch is ServerChanged {
            // The next synchronization compares everything again.
            do { return try await synchronizeOnce(request) } catch is ServerChanged {
                throw SyncFailure(.unavailable)
            }
        }
    }
    private func synchronizeOnce(_ request: Request) async throws -> SyncReport {
        let reused = try await reusableStatus(for: request)
        let status: ServerStatus
        if let reused { status = reused } else { status = try await checkedStatus() }
        let syncedID = try await store.syncedServerID()
        do {
            let report = try await synchronizeOnce(request, status: status)
            if reused == nil { statusRead = (status, now()) }
            return report
        } catch {
            statusRead = nil
            if error is CancellationError || error is ServerChanged || (error as? URLError)?.code == .cancelled {
                throw error
            }
            // A synchronization that reused the status reads it now, so a failure is explained as it would have been
            // had the status been read first (docs/design/sync-health-and-recovery.md §2).
            let current = reused == nil ? status : try await checkedStatus()
            if case JournalError.unauthorized = error { throw await lostAccess(status: current, syncedID: syncedID) }
            throw error
        }
    }
    /// The status the last successful synchronization read, while it's recent and this one only receives: nothing is
    /// queued to send and nothing is being compared again. Each page names the server's identity, so a server
    /// replaced meanwhile is still noticed; anything sent follows a status read just before.
    private func reusableStatus(for request: Request) async throws -> ServerStatus? {
        guard !request.retryingRefused, let statusRead, now().timeIntervalSince(statusRead.at) < Self.statusLifetime
        else { return nil }
        guard try await store.reconciliation() == nil, try await readyToSend(store.pending(), request).isEmpty,
            try await store.attachmentsToUpload().isEmpty, try await store.attachmentsToVerify().isEmpty
        else { return nil }
        return statusRead.status
    }
    /// Queued records this synchronization sends: all of them, or, while waiting for writing to pause, those not
    /// being written.
    private func readyToSend(_ records: [PendingChange], _ request: Request) async -> [PendingChange] {
        guard request.waitingForWritingPause else { return records }
        var ready: [PendingChange] = []
        for queued in records
        where await !store.isBeingWritten(
            queued, at: now(), pause: Self.writingPause, longest: Self.longestWritingWait)
        {
            ready.append(queued)
        }
        return ready
    }
    /// The server's status, refusing one that can't be synchronized with: not set up (reset), a newer protocol,
    /// a server below protocol revision 1, or not a journal server. The refusal is a gate and nothing else: nothing
    /// queued, no cursor, identity or credential changes, and the next status read of an updated server passes.
    private func checkedStatus() async throws -> ServerStatus {
        let status: ServerStatus
        do { status = try await server.status() } catch is DecodingError { throw SyncFailure(.notJournalServer) }
        do { try status.requireCompatible() } catch ServerRefusal.appNeedsUpdate {
            throw SyncFailure(.appUpdateNeeded)
        } catch { throw SyncFailure(.serverUpdateNeeded) }
        guard status.initialized else { throw SyncFailure(.serverNotSetUp) }
        return status
    }
    /// Why the server refused this device's credential. A server with another identity than the one this library
    /// last synchronized with was restored or replaced; the same server removed this device. A library without
    /// encryption facing an encrypted server can't tell encryption turned on elsewhere from a replaced server, and
    /// signing in decides.
    private func lostAccess(status: ServerStatus, syncedID: String?) async -> SyncFailure {
        guard let syncedID, status.serverId != syncedID else { return SyncFailure(.accessRemoved) }
        if store.protection == .plaintext, (try? await server.contentProtection()) == .encrypted {
            return SyncFailure(.signInNeeded)
        }
        return SyncFailure(.serverReplaced)
    }
    private func synchronizeOnce(_ request: Request, status: ServerStatus) async throws -> SyncReport {
        let retryingRefused = request.retryingRefused
        let serverID = status.serverId
        waitingRecords = []
        var received = Set<UUID>()
        try await confirmSameProtection(serverID: serverID)
        // Before anything is queued or read for sending: pins and journal order go to this server.
        try await store.updateLibrarySync()
        if try await store.needsReconciliation(serverID: serverID) {
            try await reconcile(serverID: serverID)
            checkedAllImages = false
        }
        // Rejected content that has been edited since is queued again as a new request.
        for (operation, rejected) in rejectedChanges where try await store.requeue(rejected.change) {
            rejectedChanges[operation] = nil
        }
        if retryingRefused {
            rejectedChanges = [:]
            rejectedImages = [:]
            retries = [:]
            serverErrors = [:]
        }
        // Read queued records first: images are added before records use them, so each one is uploaded first.
        let records = try await store.pending()
        rejectedChanges = rejectedChanges.filter { rejected in records.contains { $0.operationId == rejected.key } }
        // A record still being written waits for a later synchronization, so it needs no confirmation now.
        let sending = await readyToSend(records, request)
        if !sending.isEmpty { try await confirmSameLog(serverID: serverID) }
        let uploads = try await uploadImages()
        var pushed = try await push(sending, waitingFor: uploads.unavailable, serverID: serverID)
        received.formUnion(pushed.images)
        // Receive changes even when something couldn't be sent.
        received.formUnion(try await pull(serverID: serverID))
        // The other version of every record is final now: settle what this version settles on its own, and send the
        // result in this round (protocol/conflicts.md, Orchestration).
        let settledConflicts = try await store.resolveConflicts(at: .completedPull, holding: request.holdingConflicts)
        resolvedConflicts += settledConflicts.resolved
        if settledConflicts.changedRecords {
            let queued = await readyToSend(try await store.pending(), request)
            let settled = try await push(queued, waitingFor: uploads.unavailable, serverID: serverID)
            received.formUnion(settled.images)
            pushed.failure = pushed.failure ?? settled.failure
            pushed.serverError = pushed.serverError ?? settled.serverError
        }
        received.formUnion(try await numberDuplicateJournals(serverID: serverID))
        try await downloadImages(received, preferring: request.preferredImages)
        // Everything else succeeded, so a server error on one record counts against that record.
        if let failed = pushed.serverError { serverErrors[failed.operationId, default: 0] += 1 }
        if let failure = uploads.failure ?? pushed.failure { throw failure }
        var report = SyncReport(problem: problem())
        report.imagesToDownload = missingImages.filter { !isWaiting($0) }.count
        // The last step before the gate is released: anything written after this read breaks the quiet mark.
        let facts = try await store.settledFacts()
        report.position = facts.position
        settle(&report, facts)
        return report
    }
    /// Whether nothing is left that the next synchronization would do, except at a retry time: nothing refused,
    /// nothing queued that isn't waiting for a retry time or for images, no image to transfer that isn't waiting for
    /// a retry time or lost, no reconciliation and no automatic rename outstanding.
    private func settle(_ report: inout SyncReport, _ facts: SettledFacts) {
        let refused = !rejectedChanges.isEmpty || !rejectedImages.isEmpty
        let records = facts.queuedOperations.subtracting(waitingRecords)
        let images = facts.imagesToUpload.subtracting(lostImages).filter { !isWaiting($0) }
        report.settled =
            !refused && records.isEmpty && images.isEmpty && report.imagesToDownload == 0 && !facts.reconciling
            && !facts.renameOutstanding && !facts.conflictAwaitingResolution
        let waiting = facts.queuedOperations.union(facts.imagesToUpload).union(missingImages)
        let soonest = waiting.compactMap { retries[$0]?.after }.filter { $0 > now() }.min()
        report.earliestRetry = soonest.map { $0.timeIntervalSince(now()) }
    }
    /// Reads this many changes per page, for tests of page boundaries.
    func usePageSize(_ size: Int) { pageSize = max(1, size) }
    /// Forgets the status read last, so the next synchronization reads it again; after a failed wait, a server
    /// that fell below the protocol revision is noticed at once.
    public func forgetStatus() { statusRead = nil }
    /// Waits for the server's log to move past `position`. Throws only on cancellation.
    public func waitForChange(from position: QuietPosition) async throws -> WaitAnswer {
        try await server.waitForChange(position, digest: true)
    }
    /// A library never synchronizes with a server that stores journals another way. When another device turned on
    /// encryption, the server took a new identity and kept this device's access only if it turned encryption on; a
    /// synchronization of the unencrypted library that runs after that, such as one already running at the switch,
    /// would otherwise compare everything again and send readable journals to the encrypted server. The format can
    /// only change with the identity, so it's checked whenever the identity isn't the one this library last read.
    private func confirmSameProtection(serverID: String?) async throws {
        guard try await store.syncedServerID() != serverID else { return }
        guard let protection = try await server.contentProtection() else { return }
        // Like being signed out: the app asks to sign in once encryption was turned on from another device.
        guard protection == store.protection else { throw JournalError.unauthorized }
    }
    private func reconcile(serverID: String?) async throws {
        let existing = try await store.reconciliation()
        if existing == nil || existing?.serverID != serverID {
            try await store.beginReconciliation(serverID: serverID)
        }
        var serverIDCursor: Int64 = 0
        var more = true
        while more {
            try Task.checkCancellation()
            guard let state = try await store.reconciliation() else { throw JournalError.invalidData }
            let page = try await changes(
                after: state.cursor, applied: store.stagedChange(at: state.cursor), serverID: serverID)
            guard page.serverId == serverID else { throw ServerChanged() }
            try await store.stageReconciliation(page.changes, cursor: page.cursor)
            // Older servers can't say which changes predate a restore; treat all as possibly newer.
            serverIDCursor = serverID == nil ? 0 : page.serverIdCursor ?? 0
            more = page.hasMore
        }
        try await store.finishReconciliation(serverIDCursor: serverIDCursor)
    }
    /// Sends queued records in order. One the server rejects, or one that waits for an image, doesn't hold up the
    /// others. Returns images referenced by versions kept for review, and a failure that stopped sending.
    private func push(_ records: [PendingChange], waitingFor images: Set<UUID>, serverID: String?) async throws
        -> (images: Set<UUID>, failure: Error?, serverError: PendingChange?)
    {
        let seen = try await store.cursor()
        var received = Set<UUID>()
        for queued in records {
            try Task.checkCancellation()
            guard let pending = try await store.takeForSending(queued) else {
                // Nothing can be sent until its images are on the server.
                waitingRecords.insert(queued.operationId)
                continue
            }
            guard try await isReady(pending, waitingFor: images) else {
                if rejectedChanges[pending.operationId] == nil { waitingRecords.insert(pending.operationId) }
                continue
            }
            do {
                switch try await server.push(pending, serverID: serverID, shortReceipt: true) {
                case .accepted(let receipt):
                    // Every new change follows the ones already seen. An earlier position means the server lost
                    // changes this device saw, such as after restoring a copy of its data: compare everything.
                    guard receipt.cursor > seen || receipt.cursor <= 0 else {
                        try await store.beginReconciliation(serverID: serverID)
                        throw ServerChanged()
                    }
                    try await store.acknowledge(pending, receipt: receipt, readingOn: true)
                case .conflict(let remote):
                    if try await !store.adoptSameContent(pending, remote: remote) {
                        received.formUnion(try await store.recordConflict(remote))
                    }
                case .serverBehind:
                    // Revisions this device saw are missing, so the server was restored (older servers
                    // report no identity). Re-read everything before sending anything else.
                    try await store.beginReconciliation(serverID: serverID)
                    throw ServerChanged()
                case .serverChanged: throw ServerChanged()
                }
                retries[pending.operationId] = nil
                serverErrors[pending.operationId] = nil
            } catch let rejection as SyncRejection {
                try await reject(pending, rejection.reason)
            } catch is ServerUnavailable where refusesAfterServerError(pending) {
                try await reject(pending, .invalid)
            } catch {
                guard Self.affectsOnlyThisItem(error) else { throw error }
                wait(pending.operationId)
                return (received, error, error is ServerUnavailable ? pending : nil)
            }
        }
        return (received, nil, nil)
    }
    /// Whether this server error on `pending` is the last one allowed: earlier ones each came in a synchronization
    /// whose other requests succeeded. It's then refused like a record the server didn't accept, so the rest continues.
    private func refusesAfterServerError(_ pending: PendingChange) -> Bool {
        guard (serverErrors[pending.operationId] ?? 0) + 1 >= Self.serverErrorsBeforeRefusing else { return false }
        serverErrors[pending.operationId] = nil
        retries[pending.operationId] = nil
        return true
    }
    /// Whether to send a queued record now.
    private func isReady(_ pending: PendingChange, waitingFor images: Set<UUID>) async throws -> Bool {
        if rejectedChanges[pending.operationId] != nil || isWaiting(pending.operationId) { return false }
        if !images.isEmpty, try await store.pendingChange(pending, refersTo: images) { return false }
        guard Self.decodedLength(pending.payload) <= recordLimit else {
            try await reject(pending, .tooLarge)
            return false
        }
        return true
    }
    /// Keeps a record the server can't take as it is on this device, with an explanation, until it's edited.
    private func reject(_ pending: PendingChange, _ reason: SyncRejection.Reason) async throws {
        let title = Self.shortened(try await store.title(of: pending))
        let problem =
            switch reason {
            case .tooLarge:
                "“\(title)” is too large to sync. It’s saved on this device. Shorten it or split it into separate entries."
            case .invalid: "Your server didn’t accept “\(title)”. It’s saved on this device. Edit it to try again."
            }
        rejectedChanges[pending.operationId] = (pending, problem)
    }
    /// A title short enough for a message that may appear as a single-line menu item. An untitled entry's title is
    /// its first line, which can be very long.
    static func shortened(_ title: String) -> String {
        guard title.count > 40 else { return title }
        return title.prefix(40).trimmingCharacters(in: .whitespaces) + "…"
    }
    /// Uploads images before records that use them. Returns images the server doesn't have yet, and a failure
    /// that stopped uploading.
    private func uploadImages() async throws -> (unavailable: Set<UUID>, failure: Error?) {
        let unverified = Set(try await store.attachmentsToVerify())
        let queued = try await store.attachmentsToUpload() + unverified.sorted(by: { $0.uuidString < $1.uuidString })
        rejectedImages = rejectedImages.filter { queued.contains($0.key) }
        var unavailable = Set<UUID>()
        var failure: Error?
        for id in queued where !lostImages.contains(id) {
            try Task.checkCancellation()
            guard failure == nil, !isWaiting(id), rejectedImages[id] == nil else {
                unavailable.insert(id)
                continue
            }
            do {
                // After a server restore, an image is uploaded again only when the server lost it.
                let onServer = unverified.contains(id) ? try await server.hasAttachment(id) == true : false
                if !onServer {
                    // An image whose file is gone can never be uploaded, so records that use it aren't held back.
                    guard let bytes = try? await store.encryptedAttachment(id) else {
                        lostImages.insert(id)
                        continue
                    }
                    try await server.upload(bytes, id: id)
                }
                try await store.acknowledgeAttachment(id)
                retries[id] = nil
            } catch let rejection as SyncRejection {
                // Sending the same image again won't help until the server changes, so it waits for the next
                // start or connection instead of being uploaded over and over.
                rejectedImages[id] = rejection.reason
                unavailable.insert(id)
            } catch {
                guard Self.affectsOnlyThisItem(error, image: true) else { throw error }
                wait(id)
                unavailable.insert(id)
                failure = error
            }
        }
        return (unavailable, failure)
    }
    /// Receives changes page by page. Returns the images they refer to.
    private func pull(serverID: String?) async throws -> Set<UUID> {
        var images = Set<UUID>()
        var more = true
        while more {
            try Task.checkCancellation()
            let position = try await store.syncPosition()
            let page = try await changes(after: position.cursor, applied: position.applied, serverID: serverID)
            guard page.serverId == serverID || page.serverId == nil else { throw ServerChanged() }
            images.formUnion(try await store.apply(page.changes, cursor: page.cursor))
            more = page.hasMore
        }
        return images
    }
    /// Once everything is read, journals that share a name get numbers (docs/design/journal-name-uniqueness.md §4.6).
    /// A rename is stored only once the server accepts it, so one refused as stale, because another device renamed or
    /// changed that journal first, leaves nothing to review: the change is read and the rule runs again. Returns the
    /// images the changes read meanwhile refer to.
    private func numberDuplicateJournals(serverID: String?) async throws -> Set<UUID> {
        var images = Set<UUID>()
        for _ in 0..<Self.renameRounds {
            let renames = try await store.automaticRenames()
            guard !renames.isEmpty else { break }
            var refused = false
            let seen = try await store.cursor()
            for rename in renames {
                try Task.checkCancellation()
                let result: ServerClient.PushResult
                do {
                    result = try await server.push(rename.change, serverID: serverID, shortReceipt: true)
                } catch {
                    // A rename that can't be sent now is worked out again at the next synchronization; everything
                    // else was already sent and read.
                    if error is CancellationError || error is ServerChanged { throw error }
                    return images
                }
                switch result {
                case .accepted(let receipt):
                    guard receipt.cursor > seen || receipt.cursor <= 0 else {
                        try await store.beginReconciliation(serverID: serverID)
                        throw ServerChanged()
                    }
                    try await store.adoptAutomaticRename(rename, receipt: receipt)
                case .conflict: refused = true
                case .serverBehind:
                    try await store.beginReconciliation(serverID: serverID)
                    throw ServerChanged()
                case .serverChanged: throw ServerChanged()
                }
            }
            guard refused else { break }
            images.formUnion(try await pull(serverID: serverID))
        }
        return images
    }
    /// How often renaming is tried again in one synchronization after another device changed a journal first.
    private static let renameRounds = 3
    /// Before anything is sent, the server must still have the change this device last read. Otherwise its data was
    /// replaced by an older copy, and a write could replace a version from another device this one never saw.
    /// The newest change this device sent and the server accepted is confirmed too when it's past what was read, so
    /// a server that lost it and gave its revision to another device's version isn't written over.
    private func confirmSameLog(serverID: String?) async throws {
        let position = try await store.syncPosition()
        if position.cursor > 0, let applied = position.applied {
            _ = try await changes(after: position.cursor, applied: applied, serverID: serverID, limit: 1)
        }
        if let sent = try await store.sentChangePastPosition(serverID: serverID) {
            _ = try await changes(after: sent.cursor, applied: sent.change, serverID: serverID, limit: 1)
        }
    }
    /// One page after `cursor`, which must move forward so a faulty server can't keep this loop running. `applied`
    /// is the change read at `cursor`; a server that has another change there lost changes this device read, so
    /// everything is compared again, as after a restore.
    private func changes(after cursor: Int64, applied: LoggedChange?, serverID: String?, limit: Int? = nil)
        async throws -> SyncPage
    {
        let page: SyncPage
        do {
            page = try await server.changes(
                after: cursor, limit: limit ?? pageSize, applied: cursor > 0 ? applied : nil)
        } catch let error as ResponseTooLarge {
            guard limit == nil, pageSize > 1 else { throw error }
            // Large records can make a full page bigger than this client reads; ask for fewer at a time.
            pageSize = max(1, pageSize / 10)
            return try await changes(after: cursor, applied: applied, serverID: serverID)
        } catch is SyncLogChanged {
            try await store.beginReconciliation(serverID: serverID)
            throw ServerChanged()
        }
        let ordered = page.changes.allSatisfy { $0.cursor > cursor && $0.cursor <= page.cursor }
        guard page.cursor >= cursor, ordered, !page.hasMore || page.cursor > cursor else {
            throw JournalError.invalidData
        }
        return page
    }
    /// Downloads images that synchronized versions use. An image the server can't provide yet doesn't stop
    /// synchronization; it's tried again later.
    private func downloadImages(_ referenced: Set<UUID>, preferring preferred: Set<UUID>) async throws {
        var candidates = referenced.union(missingImages)
        if !checkedAllImages {
            candidates.formUnion(try await store.referencedAttachmentIDs())
            checkedAllImages = true
        }
        missingImages = await store.missingAttachments(candidates)
        let started = now()
        let ordered = missingImages.sorted { first, second in
            preferred.contains(first) == preferred.contains(second)
                ? first.uuidString < second.uuidString : preferred.contains(first)
        }
        for id in ordered where !isWaiting(id) {
            try Task.checkCancellation()
            guard now().timeIntervalSince(started) < Self.imageTimePerPass else { return }
            do {
                try await store.cacheAttachment(server.downloadAttachment(id), id: id)
                missingImages.remove(id)
                retries[id] = nil
            } catch {
                guard Self.affectsOnlyThisItem(error, image: true) else { throw error }
                wait(id)
                // On a connection this slow, the remaining downloads would wait as long.
                if error is URLError { return }
            }
        }
    }
    private func isWaiting(_ id: UUID) -> Bool { retries[id].map { $0.after > now() } ?? false }
    /// Waits longer after each failure, from 15 seconds up to 10 minutes.
    private func wait(_ id: UUID) {
        let attempts = (retries[id]?.attempts ?? 0) + 1
        let delay = min(15 * pow(2, Double(attempts - 1)), 600)
        retries[id] = Retry(attempts: attempts, after: now().addingTimeInterval(delay))
    }
    /// Errors that stop the whole synchronization rather than one record or image. Without a connection nothing
    /// is delayed, so everything is sent as soon as the connection returns. A record that times out ends the pass,
    /// since the next one would wait as long; an image transfer that times out may only be large, so it waits alone.
    private static func affectsOnlyThisItem(_ error: Error, image: Bool = false) -> Bool {
        if error is CancellationError || error is ServerChanged || error is ServerRateLimited || error is SyncFailure {
            return false
        }
        if case JournalError.unauthorized = error { return false }
        guard let error = error as? URLError else { return true }
        var connection: Set<URLError.Code> = [
            .cancelled, .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
            .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff,
        ]
        if !image { connection.insert(.timedOut) }
        return !connection.contains(error.code)
    }
    private func problem() -> String? {
        if let rejected = rejectedChanges.values.map(\.problem).sorted().first { return rejected }
        if rejectedImages.values.contains(.tooLarge) {
            return "An image is too large for your server. Entries that include it are saved on this device."
        }
        if !rejectedImages.isEmpty {
            return "Your server didn’t accept an image. Entries that include it are saved on this device."
        }
        return nil
    }
    /// The size of base64 text once decoded.
    static func decodedLength(_ base64: String) -> Int {
        let padding = base64.hasSuffix("==") ? 2 : base64.hasSuffix("=") ? 1 : 0
        return base64.utf8.count / 4 * 3 - padding
    }
}
