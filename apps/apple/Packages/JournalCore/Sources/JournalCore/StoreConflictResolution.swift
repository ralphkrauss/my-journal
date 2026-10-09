import Foundation
import GRDB

/// When a device settles the conflicts it holds (protocol/conflicts.md, Orchestration).
public enum ConflictResolutionPoint: Sendable, Equatable {
    /// The end of a completed pull, however many pages it took: the other version of each record is final.
    case completedPull
    /// A library is opened. The one-time pass over rows an earlier version left always runs. Rows made since wait for
    /// the next completed pull, unless no server is configured, in which case there is no pull to wait for.
    case opening(serverConfigured: Bool)
    /// After a local merge or import, or after a stale save when no server is configured. The caller decides when
    /// the person has paused.
    case local
}

/// One conflict this device settled.
public struct ResolvedConflict: Sendable, Equatable {
    public enum Result: Sendable, Equatable, Hashable {
        /// The same content: the merged deletion state, or the other version as it is.
        case sameContent
        /// An entry or template that differs: this device's version stays and the other version is a separate one.
        /// `copyID` is where it is (a replaced copy keeps its identity), nil when a record with the derived identity
        /// already existed and nothing was written.
        case keptBoth(copyID: UUID?)
        /// An edit parked next to a permanent deletion; `parkedID` is where it is, nil when it was not needed.
        case deletedAndChanged(parkedID: UUID?)
        case twoDeletions
        case journalKept
        case journalDeleted
        /// A review that was already out of date: the other version went to Version History.
        case superseded
    }
    public let recordID: UUID
    public let kind: String
    public let result: Result
}

public struct ConflictResolutionReport: Sendable, Equatable {
    public var resolved: [ResolvedConflict] = []
    /// Rows left because the record is being written; the next point settles them.
    public var deferred = 0
    /// Rows left because a version can't be read yet, or can't be opened or settled; the next point tries again.
    public var held = 0
    public init() {}
    /// Whether anything was written that a synchronization should send.
    public var changedRecords: Bool { !resolved.isEmpty }
}

extension JournalStore {
    /// How long after a save a record counts as being written.
    static let writingPause: TimeInterval = 2

    /// Settles every conflict this version settles on its own at `point`, each in its own transaction. Nothing is
    /// settled while a reconciliation is in progress, for a record that is being written or that the caller `holds`
    /// (the open entry while a save of it has failed), or for a version this version can't read. A record whose
    /// versions can't be opened or whose settlement fails is counted as held and tried again at the next point; it
    /// never stops the others.
    @discardableResult public func resolveConflicts(at point: ConflictResolutionPoint, holding: Set<UUID> = []) throws
        -> ConflictResolutionReport
    {
        try Task.checkCancellation()
        var report = ConflictResolutionReport()
        guard try reconciliation() == nil else { return report }
        // The rows an earlier version left are settled first, from the other version the person last saw.
        report.resolved += try completeOpeningPass(holding: holding)
        if case .opening(let serverConfigured) = point, serverConfigured { return report }
        for recordID in try conflictedRecordIDs() {
            try Task.checkCancellation()
            if holding.contains(recordID) || (point == .completedPull && isBeingWritten(recordID)) {
                report.deferred += 1
                continue
            }
            do {
                switch try settleConflict(recordID) {
                case .resolved(let resolved): report.resolved.append(resolved)
                case .held: report.held += 1
                case .gone: break
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                report.held += 1
            }
        }
        return report
    }

    /// Whether a conflict is waiting that a later point settles on its own: not held. A row that
    /// can't be read is held, so it is not waiting.
    func hasConflictAwaitingResolution() throws -> Bool {
        for recordID in try conflictedRecordIDs() {
            let waiting = try? db.read { db -> Bool in
                guard let state = try conflictState(db, recordID: recordID) else { return false }
                if case .held = ConflictResolution.resolve(local: state.local, other: state.other, ids: copyIdentity) {
                    return false
                }
                return true
            }
            if waiting == true { return true }
        }
        return false
    }

    /// The identifiers of conflicts that are held for a version this one can't read, or whose versions can't be opened.
    public func heldConflictIDs() throws -> Set<UUID> {
        var held = Set<UUID>()
        for recordID in try conflictedRecordIDs() {
            let isHeld =
                (try? db.read { db -> Bool in
                    guard let state = try conflictState(db, recordID: recordID) else { return false }
                    return state.local.isHeld || state.other.isHeld
                }) ?? true
            if isHeld { held.insert(recordID) }
        }
        return held
    }

    /// The conflicted records that this version settles on its own at the next pull: those it can read. They keep a
    /// journal in use; reading one as "needs a newer app" would be wrong. A held row and a row that can't be opened
    /// are not among them.
    func settlingConflictIDs(_ db: Database) throws -> Set<UUID> {
        var settling = Set<UUID>()
        let rows = try String.fetchAll(
            db, sql: "SELECT record FROM conflicts WHERE record<>?", arguments: [LibraryRecord.idText])
        for recordID in rows.compactMap(UUID.init(uuidString:)) {
            guard let state = try? conflictState(db, recordID: recordID) else { continue }
            if case .held = ConflictResolution.resolve(local: state.local, other: state.other, ids: copyIdentity) {
                continue
            }
            settling.insert(recordID)
        }
        return settling
    }

    /// The entry or template that settling a conflict of `recordID` parked next to its permanent deletion, only while
    /// it is still exactly what that settlement wrote: not deleted for good, still deleted at the marker's time, not
    /// edited, and with no change queued and no conflict waiting on it. Anything else is nil, so nothing is written onto a
    /// record someone changed meanwhile.
    public func unchangedParkedEntry(_ parkedID: UUID, for recordID: UUID) throws -> JournalItem? {
        try db.read { db in
            guard let parked = try storedItem(db, uuid: parkedID), !parked.isPermanentlyDeleted,
                let marker = try storedItem(db, uuid: recordID), marker.isPermanentlyDeleted,
                parked.deletedAt != nil, parked.deletedAt == marker.permanentlyDeletedAt,
                let copy = try keptNotesStore.state(db).copies.first(where: {
                    $0.copyID == parkedID && $0.recordID == recordID
                }),
                let row = try Row.fetchOne(
                    db, sql: "SELECT kind,payload FROM records WHERE id=?", arguments: [id(parkedID)]),
                try plaintextDigest(row["payload"], id: parkedID, kind: row["kind"]) == copy.digest
            else { return nil }
            let queued = try String.fetchAll(
                db, sql: "SELECT payload FROM outbox WHERE record=?", arguments: [id(parkedID)])
            let stored: String = row["payload"]
            let reviewed = try Bool.fetchOne(
                db, sql: "SELECT EXISTS(SELECT 1 FROM conflicts WHERE record=?)", arguments: [id(parkedID)])
            guard queued.allSatisfy({ $0 == stored }), reviewed != true else { return nil }
            return parked
        }
    }
    func plaintextDigest(_ payload: String, id recordID: UUID, kind: String) throws -> String {
        KeptNotesState.digest(of: try plaintext(payload, id: recordID, kind: kind))
    }

    var copyIdentity: ConflictCopyIdentity {
        ConflictCopyIdentity(vaultKey: protection == .encrypted ? key : nil)
    }

    func isBeingWritten(_ recordID: UUID) -> Bool {
        guard let saved = lastSaves[recordID] else { return false }
        let elapsed = clock().timeIntervalSince(saved)
        return (0..<Self.writingPause).contains(elapsed)
    }
    private func conflictedRecordIDs() throws -> [UUID] {
        try db.read { db in
            try String.fetchAll(
                db, sql: "SELECT record FROM conflicts WHERE record<>? ORDER BY record",
                arguments: [LibraryRecord.idText]
            ).compactMap(UUID.init(uuidString:))
        }
    }

    // MARK: The one-time pass

    /// Settles the rows an earlier version left (3.9), before any synchronization can replace a row's other version.
    /// The rows present when the pass first runs are recorded once, in the sealed key, and only those are ever taken:
    /// a row made later, such as one a crash left in the middle of a paged catch-up, waits for a completed pull. A row
    /// that fails, or that the caller holds, stays on that list for the next call; the pass is complete when the list
    /// is empty.
    func completeOpeningPass(holding: Set<UUID>) throws -> [ResolvedConflict] {
        guard !openingPassComplete else { return [] }
        var state = try db.read { try keptNotesStore.state($0) }
        guard state.passStep < Self.passStepAllKinds else {
            openingPassComplete = true
            return []
        }
        let rows: [UUID]
        if let recorded = state.passRecords {
            rows = recorded
        } else {
            rows = try conflictedRecordIDs()
            if !rows.isEmpty {
                state.passRecords = rows
                try db.write { try keptNotesStore.save($0, state) }
            }
        }
        var resolved: [ResolvedConflict] = []
        var remaining: [UUID] = []
        for recordID in rows {
            try Task.checkCancellation()
            if holding.contains(recordID) {
                remaining.append(recordID)
                continue
            }
            do {
                if case .resolved(let result) = try settleConflict(recordID) {
                    resolved.append(result)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A failure leaves that row for the next call; it doesn't stop the others.
                remaining.append(recordID)
            }
        }
        try db.write { db in
            var latest = try keptNotesStore.state(db)
            latest.passRecords = remaining.isEmpty ? nil : remaining
            if remaining.isEmpty { latest.passStep = max(latest.passStep, Self.passStepAllKinds) }
            try keptNotesStore.save(db, latest)
        }
        openingPassComplete = remaining.isEmpty
        return resolved
    }
    /// The first version of the pass settled journals and permanent deletions (1); this one settles every kind (2).
    static let passStepAllKinds = 2

    // MARK: One conflict

    enum ConflictSettlement {
        case resolved(ResolvedConflict)
        case held, gone
    }

    /// The two versions of a conflicted record as the database holds them.
    struct ConflictState {
        let recordID: UUID
        let kind: String
        let local: ConflictSide
        let other: ConflictSide
        let localPayload: String
        let otherPayload: String
        let localRevision: Int64
        let otherRevision: Int64
        let otherDevice: UUID?
        let otherModified: Date
        /// The other version is the server's at that revision, rather than a version kept from a save on this device.
        var otherIsFromServer: Bool { otherDevice != nil && otherRevision > 0 }
    }

    func conflictState(_ db: Database, recordID: UUID) throws -> ConflictState? {
        guard
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT c.payload AS other,c.revision,c.device,c.modified,r.payload AS local,r.kind,r.revision AS localRevision
                    FROM conflicts c JOIN records r ON r.id=c.record WHERE c.record=?
                    """, arguments: [id(recordID)]),
            let modified = try? JournalCoding.date(from: row["modified"] as String)
        else { return nil }
        let kind: String = row["kind"]
        let local: String = row["local"]
        let other: String = row["other"]
        let device = UUID(uuidString: row["device"]).flatMap { $0 == UUID.zero ? nil : $0 }
        return ConflictState(
            recordID: recordID, kind: kind,
            local: ConflictSide(
                plaintext: try plaintext(local, id: recordID, kind: kind), id: recordID, kind: kind),
            other: ConflictSide(
                plaintext: try plaintext(other, id: recordID, kind: kind), id: recordID, kind: kind),
            localPayload: local, otherPayload: other, localRevision: row["localRevision"],
            otherRevision: row["revision"], otherDevice: device, otherModified: modified)
    }

    /// The authenticated plaintext of a stored payload.
    func plaintext(_ payload: String, id recordID: UUID, kind: String) throws -> Data {
        guard let data = Data(base64Encoded: payload) else { throw JournalError.invalidData }
        return try protection.decode(data, key: key, context: VaultCrypto.recordContext(id: recordID, kind: kind))
    }

    func settleConflict(_ recordID: UUID) throws -> ConflictSettlement {
        // The transaction also changes what is queued in memory; if it rolls back, the queue stays as it was.
        let queuedBefore = unsentOperations
        let settlement: ConflictSettlement
        do {
            settlement = try db.write { db -> ConflictSettlement in
                guard let state = try conflictState(db, recordID: recordID) else { return .gone }
                let outcome = ConflictResolution.resolve(local: state.local, other: state.other, ids: copyIdentity)
                // A conflict whose other version this device's record has already passed is out of date: it goes to
                // Version History and the row ends. Nothing about the record changes. A version this app can't
                // read keeps its row; a permanent deletion has no content to keep.
                guard state.localRevision <= state.otherRevision else {
                    if case .held = outcome { return .held }
                    try supersede(db, state)
                    return .resolved(ResolvedConflict(recordID: recordID, kind: state.kind, result: .superseded))
                }
                return try applyOutcome(db, outcome: outcome, to: state)
            }
        } catch {
            unsentOperations = queuedBefore
            throw error
        }
        if case .resolved = settlement { receivedChanges += 1 }
        return settlement
    }

    private func applyOutcome(_ db: Database, outcome: ConflictOutcome, to state: ConflictState) throws
        -> ConflictSettlement
    {
        if try arrivingVersionReplacesUnsentCopy(db, state: state) {
            return settled(state, .sameContent)
        }
        switch outcome {
        case .held: return .held
        case .keepBoth(let copy):
            try keepLocalVersion(db, state, record: nil)
            let copyID = try keepOtherVersionAsCopy(db, copy: copy, state: state)
            return settled(state, .keptBoth(copyID: copyID))
        case .sameContent(let record, let adoptsOther):
            if adoptsOther {
                try adoptOtherVersion(db, state)
            } else {
                try keepLocalVersion(db, state, record: record)
            }
            return settled(state, .sameContent)
        case .parked(let parked, let markerIsLocal):
            let parkedID = try park(db, parked, markerIsLocal: markerIsLocal, state: state)
            if markerIsLocal {
                try keepLocalVersion(db, state, record: nil)
            } else {
                try adoptOtherVersion(db, state)
            }
            // Either marker removes the record's earlier versions, including those a pull set aside meanwhile.
            try removeHistory(db, recordID: state.recordID)
            return settled(state, .deletedAndChanged(parkedID: parkedID))
        case .twoMarkers:
            try adoptOtherVersion(db, state)
            try removeHistory(db, recordID: state.recordID)
            return settled(state, .twoDeletions)
        case .journal(let record, let otherName):
            try keepInHistory(
                db, recordID: state.recordID, kind: state.kind, payload: state.otherPayload, saved: state.otherModified)
            try keepLocalVersion(db, state, record: record)
            if let otherName {
                try addNote(
                    db,
                    KeptNote(
                        kind: .journalRenamed, recordID: state.recordID, name: record.title, otherName: otherName,
                        created: clock()))
            }
            return settled(state, .journalKept)
        case .journalMarker(let markerIsLocal, let name):
            if markerIsLocal {
                try keepLocalVersion(db, state, record: nil)
            } else {
                try adoptOtherVersion(db, state)
            }
            try removeHistory(db, recordID: state.recordID)
            try addNote(db, KeptNote(kind: .journalDeleted, recordID: state.recordID, name: name, created: clock()))
            return settled(state, .journalDeleted)
        }
    }
    /// A parked entry this device made and has not sent is replaced, without a further copy, by a version of the same
    /// record that arrives first: two clients may write the same entry with different bytes. The arriving version wins
    /// and the local one is dropped, but only while it is still what this device wrote: one the person has edited
    /// since goes through the normal rules, which keep it. A marker is handled by parking, which drops the local entry
    /// too, under the same condition.
    private func arrivingVersionReplacesUnsentCopy(_ db: Database, state: ConflictState) throws -> Bool {
        guard state.localRevision == 0, state.otherIsFromServer, !state.other.isMarker, !state.local.isMarker,
            !state.local.isHeld, !state.other.isHeld
        else { return false }
        var notes = try keptNotesStore.state(db)
        guard notes.isUnchangedAutomaticCopy(state.recordID, plaintext: state.local.plaintext) else { return false }
        notes.copies.removeAll { $0.copyID == state.recordID }
        try keptNotesStore.save(db, notes)
        try adoptOtherVersion(db, state)
        return true
    }
    func settled(_ state: ConflictState, _ result: ResolvedConflict.Result) -> ConflictSettlement {
        .resolved(ResolvedConflict(recordID: state.recordID, kind: state.kind, result: result))
    }

    // MARK: Writing an outcome

    /// The other version becomes the record. From the server it is clean and nothing is sent; a version kept from a
    /// save on this device may never have been sent, so it is queued on its revision.
    func adoptOtherVersion(_ db: Database, _ state: ConflictState) throws {
        let recordID = id(state.recordID)
        try db.execute(
            sql: "UPDATE records SET payload=?,revision=?,dirty=? WHERE id=?",
            arguments: [state.otherPayload, state.otherRevision, state.otherIsFromServer ? 0 : 1, recordID])
        try removeQueuedChanges(db, recordID: recordID)
        try db.execute(sql: "DELETE FROM conflicts WHERE record=?", arguments: [recordID])
        if state.otherIsFromServer {
            try rememberServerVersion(
                db, recordID: recordID, revision: state.otherRevision, payload: state.otherPayload)
        } else {
            try enqueue(
                db, recordID: recordID, kind: state.kind, payload: state.otherPayload, revision: state.otherRevision)
        }
        forgetCachedPayload(state.recordID)
    }
    /// This device's version stays the record, on top of the other one: rebased on its revision and queued. `record`
    /// is the content to write when it differs from this device's version, such as with a merged deletion state.
    func keepLocalVersion(_ db: Database, _ state: ConflictState, record: JournalItem?) throws {
        let recordID = id(state.recordID)
        var payload = state.localPayload
        if let record, record != state.local.item { payload = try encode(record) }
        try db.execute(
            sql: "UPDATE records SET payload=?,revision=?,dirty=1 WHERE id=?",
            arguments: [payload, state.otherRevision, recordID])
        try removeQueuedChanges(db, recordID: recordID)
        try db.execute(sql: "DELETE FROM conflicts WHERE record=?", arguments: [recordID])
        // The other version is the server's at that revision, unless it was kept from a save on this device.
        try rememberServerVersion(
            db, recordID: recordID, revision: state.otherRevision, payload: state.otherPayload, unlessKnown: true)
        try enqueue(db, recordID: recordID, kind: state.kind, payload: payload, revision: state.otherRevision)
        forgetCachedPayload(state.recordID)
    }
    private func supersede(_ db: Database, _ state: ConflictState) throws {
        let recordID = id(state.recordID)
        if state.otherPayload != state.localPayload && !state.other.isMarker {
            try keepInHistory(
                db, recordID: state.recordID, kind: state.kind, payload: state.otherPayload, saved: state.otherModified)
        }
        try db.execute(sql: "DELETE FROM conflicts WHERE record=?", arguments: [recordID])
    }
    func removeQueuedChanges(_ db: Database, recordID: String) throws {
        let operations = try String.fetchAll(
            db, sql: "SELECT operation FROM outbox WHERE record=?", arguments: [recordID])
        try db.execute(sql: "DELETE FROM outbox WHERE record=?", arguments: [recordID])
        for operation in operations.compactMap(UUID.init(uuidString:)) { unsentOperations[operation] = nil }
    }
    func forgetCachedPayload(_ recordID: UUID) {
        editablePayloads[recordID] = nil
        decodedRecords[recordID] = nil
    }
    func keepInHistory(_ db: Database, recordID: UUID, kind: String, payload: String, saved: Date) throws {
        try db.execute(
            sql: "INSERT INTO history(record,kind,payload,saved) VALUES (?,?,?,?)",
            arguments: [id(recordID), kind, payload, JournalCoding.timestamp(saved)])
    }
    /// A permanent deletion removes the record's earlier versions on every device.
    private func removeHistory(_ db: Database, recordID: UUID) throws {
        try db.execute(sql: "DELETE FROM history WHERE record=?", arguments: [id(recordID)])
    }

    // MARK: Parking

    /// Saves the edited version of a permanently deleted entry or template as a new record in Recently Deleted and
    /// notes it. Returns its identity, or nil when the edit was an automatic copy this device had not sent and the
    /// person had not edited, which is dropped when it meets a marker because its content is in the other record. A record that already has the
    /// derived identity, in any state, is the copy: nothing is written, revived or noted.
    private func park(_ db: Database, _ parked: JournalItem, markerIsLocal: Bool, state: ConflictState) throws -> UUID?
    {
        var notes = try keptNotesStore.state(db)
        let editedID = state.recordID
        if !markerIsLocal, state.localRevision == 0,
            notes.isUnchangedAutomaticCopy(editedID, plaintext: state.local.plaintext)
        {
            notes.copies.removeAll { $0.copyID == editedID }
            try keptNotesStore.save(db, notes)
            return nil
        }
        let exists = try Bool.fetchOne(
            db, sql: "SELECT EXISTS(SELECT 1 FROM records WHERE id=?)", arguments: [id(parked.id)])
        guard exists != true else { return parked.id }
        let plaintext = try PortableRecord.encode(parked)
        let payload = try protection.encode(
            plaintext, key: key, context: VaultCrypto.recordContext(id: parked.id, kind: parked.kind)
        ).base64EncodedString()
        try db.execute(
            sql: "INSERT INTO records(id,kind,payload) VALUES (?,?,?)",
            arguments: [id(parked.id), parked.kind, payload])
        try enqueue(db, recordID: id(parked.id), kind: parked.kind, payload: payload, revision: 0)
        notes.copies = try copiesThatStillExist(db, notes.copies)
        notes.remember(
            KeptCopy(
                copyID: parked.id, recordID: editedID, originDevice: state.otherDevice,
                originRevision: state.otherRevision,
                digest: KeptNotesState.digest(of: plaintext)))
        notes.add(
            KeptNote(
                kind: .deletedAndChanged, recordID: editedID, otherID: parked.id, name: parked.displayTitle,
                created: clock()))
        try keptNotesStore.save(db, notes)
        return parked.id
    }
    /// The copies whose record is still here; a copy whose record is gone is forgotten.
    func copiesThatStillExist(_ db: Database, _ copies: [KeptCopy]) throws -> [KeptCopy] {
        var kept: [KeptCopy] = []
        for copy in copies {
            let exists = try Bool.fetchOne(
                db, sql: "SELECT EXISTS(SELECT 1 FROM records WHERE id=?)", arguments: [id(copy.copyID)])
            if exists == true { kept.append(copy) }
        }
        return kept
    }
    func addNote(_ db: Database, _ note: KeptNote) throws {
        var state = try keptNotesStore.state(db)
        state.add(note)
        try keptNotesStore.save(db, state)
    }
}

extension UUID {
    fileprivate static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}
