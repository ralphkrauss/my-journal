import XCTest

@testable import JournalCore

/// A journal server in memory with the rules merging depends on: revisions and conflicts, a change log, images that
/// can never be replaced, and failures on demand.
actor MergeServer: SyncServer {
    private(set) var identity = "server-one"
    private(set) var records: [UUID: RemoteChange] = [:]
    private var log: [RemoteChange] = []
    private var cursor: Int64 = 0
    private(set) var images: [UUID: Data] = [:]
    /// Uploads the server refused because an image with that identity already exists.
    private(set) var refusedUploads = 0
    private var failingPages = 0
    private var pushesBeforeFailure: Int?
    private var uploadsBeforeFailure: Int?
    private var refusingNextPush = false

    func status() -> ServerStatus { .healthy(serverId: identity) }
    func changes(after position: Int64, limit: Int, applied: LoggedChange?) throws -> SyncPage {
        if failingPages > 0 {
            failingPages -= 1
            throw URLError(.notConnectedToInternet)
        }
        let newer = log.filter { $0.cursor > position }
        let page = Array(newer.prefix(limit))
        return SyncPage(
            changes: page, cursor: page.last?.cursor ?? position, hasMore: newer.count > page.count,
            serverId: identity, serverIdCursor: 0)
    }
    func push(_ pending: PendingChange, serverID: String?, shortReceipt: Bool) throws -> ServerClient.PushResult {
        if let remaining = pushesBeforeFailure {
            guard remaining > 0 else { throw URLError(.notConnectedToInternet) }
            pushesBeforeFailure = remaining - 1
        }
        let current = records[pending.recordID]
        if let current, current.revision != pending.baseRevision { return .conflict(current) }
        if refusingNextPush, let current {
            refusingNextPush = false
            return .conflict(current)
        }
        cursor += 1
        let change = RemoteChange(
            cursor: cursor, recordId: pending.recordID, revision: (current?.revision ?? 0) + 1, kind: pending.kind,
            payload: pending.payload, deviceId: UUID(), modifiedAt: Date(timeIntervalSince1970: 1_800_000_000))
        records[pending.recordID] = change
        log.append(change)
        return .accepted(change)
    }
    func upload(_ bytes: Data, id: UUID) throws {
        if let remaining = uploadsBeforeFailure {
            guard remaining > 0 else { throw URLError(.notConnectedToInternet) }
            uploadsBeforeFailure = remaining - 1
        }
        if let existing = images[id] {
            guard existing == bytes else {
                refusedUploads += 1
                throw SyncRejection(reason: .invalid)
            }
            return
        }
        images[id] = bytes
    }
    func hasAttachment(_ id: UUID) -> Bool? { images[id] != nil }
    func downloadAttachment(_ id: UUID) throws -> Data {
        guard let image = images[id] else { throw JournalError.server("Image unavailable.") }
        return image
    }
    func failNextPages(_ count: Int) { failingPages = count }
    /// Refuses the next change to an existing record as stale, as when another device's change arrives just before it.
    func refuseNextPush() { refusingNextPush = true }
    func failPushes(after accepted: Int?) { pushesBeforeFailure = accepted }
    func failUploads(after accepted: Int?) { uploadsBeforeFailure = accepted }
    struct Backup {
        let records: [UUID: RemoteChange]
        let log: [RemoteChange]
        let cursor: Int64
        let images: [UUID: Data]
    }
    func backup() -> Backup { Backup(records: records, log: log, cursor: cursor, images: images) }
    /// Restores a backup as the server's --restore does: its records, change log and images, under a new identity.
    func restore(_ backup: Backup) {
        records = backup.records
        log = backup.log
        cursor = backup.cursor
        images = backup.images
        identity = "server-restored-" + UUID().uuidString
    }
}

/// Merging a device's journals into a server's library (docs/design/join-with-local-journals.md §2).
final class MergeTests: XCTestCase {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Merge-" + UUID().uuidString)
    var serverKey = Data()
    var deviceKey = Data()

    override func setUpWithError() throws {
        serverKey = try VaultCrypto.generateKey()
        deviceKey = try VaultCrypto.generateKey()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func store(_ name: String = UUID().uuidString, key: Data? = nil) throws -> JournalStore {
        try JournalStore(directory: root.appendingPathComponent(name), key: key ?? serverKey)
    }
    /// Another device already on the server, such as the Mac that set it up.
    func otherDevice(_ server: MergeServer) async throws -> (JournalStore, SyncEngine) {
        let device = try store()
        let engine = SyncEngine(store: device, server: server)
        try await engine.synchronize()
        return (device, engine)
    }
    /// The order connecting uses (§2.1): download, import, send. Returns the staged store and its engine.
    @discardableResult func merge(
        _ local: JournalStore, into server: MergeServer, readByAgents: Set<UUID>? = []
    ) async throws -> (JournalStore, SyncEngine) {
        let staged = try store()
        let engine = SyncEngine(store: staged, server: server)
        try await engine.synchronize()
        try await staged.importMerging(from: local, server: await server.identity, readByAgents: readByAgents)
        try await engine.synchronize()
        return (staged, engine)
    }
    /// What a new device would download from the server now.
    func downloaded(_ server: MergeServer) async throws -> JournalStore {
        let (device, _) = try await otherDevice(server)
        return device
    }
    func fresh(_ template: JournalItem) -> JournalItem {
        var copy = template
        copy.id = UUID()
        return copy
    }
    func live(_ items: [JournalItem], _ kind: String, _ title: String) -> [JournalItem] {
        items.filter {
            $0.kind == kind && $0.deletedAt == nil && MergePlan.nameKey($0.title) == MergePlan.nameKey(title)
        }
    }

    // MARK: Nothing written

    func testOnlyAnUntouchedNewLibraryCountsAsNothingWritten() throws {
        let journal = JournalItem(kind: "journal", title: "Default")
        let started = [journal] + BuiltInTemplates.asEarlierBuildsCreated()
        XCTAssertTrue(
            LibraryContents(items: started, conflicts: 0).nothingWritten,
            "A new library from an earlier build, with its built-in templates, joins without a Merge step.")
        XCTAssertTrue(
            LibraryContents(items: [journal], conflicts: 0).nothingWritten,
            "A new library from this build, without templates, joins without a Merge step.")
        let ownTemplate = JournalItem(kind: "template", title: "Standup", document: .plain("Yesterday, today"))
        XCTAssertFalse(LibraryContents(items: [journal, ownTemplate], conflicts: 0).nothingWritten)
        var renamed = journal
        renamed.title = "Work"
        var edited = BuiltInTemplates.asEarlierBuildsCreated()[0]
        edited.document = .plain("My own questions")
        var deletedTemplate = BuiltInTemplates.asEarlierBuildsCreated()[1]
        deletedTemplate.deletedAt = Date()
        var deletedEntry = JournalItem(kind: "entry", journalID: journal.id, title: "Tried it")
        deletedEntry.deletedAt = Date()
        let written: [String: ([JournalItem], Int)] = [
            "a renamed journal": ([renamed] + BuiltInTemplates.asEarlierBuildsCreated(), 0),
            "a second journal": (started + [JournalItem(kind: "journal", title: "Default")], 0),
            "an empty entry": (started + [JournalItem(kind: "entry", journalID: journal.id)], 0),
            "an entry in Recently Deleted": (started + [deletedEntry], 0),
            "an edited built-in template": ([journal, edited], 0),
            "a built-in template in Recently Deleted": ([journal, deletedTemplate], 0),
            "a change to review": (started, 1),
        ]
        for (reason, library) in written {
            XCTAssertFalse(LibraryContents(items: library.0, conflicts: library.1).nothingWritten, reason)
        }
        let summary = LibraryContents(items: started + [deletedEntry, edited], conflicts: 0)
        XCTAssertEqual(
            [summary.journals, summary.entries, summary.templates, summary.recentlyDeleted], [1, 0, 1, 1],
            "The Merge summary counts templates someone made or edited, and everything in Recently Deleted.")
    }

    /// After the app is opened again, a stored template is read back as Markdown rather than the blocks it was
    /// created from; an untouched library must still count as nothing written. Opening a library an earlier build
    /// made keeps its built-in templates as they are: they're the person's now (no-built-in-templates-2026-10-04.md).
    func testAReopenedNewLibraryStillCountsAsNothingWritten() async throws {
        let folder = root.appendingPathComponent("reopened")
        let created = try JournalStore(directory: folder, key: deviceKey)
        try await created.save(JournalItem(kind: "journal", title: "Default"))
        let builtIns = BuiltInTemplates.asEarlierBuildsCreated()
        for template in builtIns { try await created.save(template) }
        try await created.close()
        let reopened = try JournalStore(directory: folder, key: deviceKey)
        let items = try await reopened.items()
        XCTAssertTrue(LibraryContents(items: items, conflicts: 0).nothingWritten)
        let kept = items.filter { $0.kind == "template" && $0.deletedAt == nil }
        XCTAssertEqual(Set(kept.map(\.id)), Set(builtIns.map(\.id)), "Every built-in template stays.")
        XCTAssertTrue(kept.allSatisfy(BuiltInTemplates.isUnedited))
        var markdownForm = BuiltInTemplates.asEarlierBuildsCreated()[0]
        markdownForm.document = JournalDocument(markdown: markdownForm.document.markdown)
        XCTAssertTrue(BuiltInTemplates.isUnedited(markdownForm))
    }

    // MARK: Merge rules

    private struct Scenario {
        let local: JournalStore
        let serverDefault: JournalItem
        let serverWork: JournalItem
        let serverGratitude: JournalItem
        let localGratitude: JournalItem
        let image: Data
    }
    /// The server has "Default", "Work" (which an agent reads), built-in templates, an edited "Gratitude" and a
    /// custom "Standup". This device has "default " with entries (one archived, one in Recently Deleted, one with
    /// an image), "Work", "Travel", unedited built-ins, the same "Standup", a different "Gratitude" and "Ideas".
    private func scenario(_ server: MergeServer) async throws
        -> Scenario
    {
        let (mac, macSync) = try await otherDevice(server)
        var serverDefault = JournalItem(kind: "journal", title: "Default", date: Date(timeIntervalSince1970: 1_000))
        serverDefault.defaultTemplateID = nil
        let serverWork = JournalItem(kind: "journal", title: "Work")
        try await mac.save(serverDefault)
        try await mac.save(serverWork)
        try await mac.save(JournalItem(kind: "entry", journalID: serverDefault.id, title: "From the Mac"))
        var templates = BuiltInTemplates.asEarlierBuildsCreated()
        let gratitudeIndex = try XCTUnwrap(templates.firstIndex { $0.title == "Gratitude" })
        templates[gratitudeIndex].document = .plain("Edited on the Mac")
        for template in templates { try await mac.save(template) }
        try await mac.save(JournalItem(kind: "template", title: "Standup", document: .plain("Yesterday, today")))
        try await macSync.synchronize()

        let local = try store(key: deviceKey)
        let journal = JournalItem(kind: "journal", title: " default ")
        try await local.save(journal)
        try await local.save(JournalItem(kind: "journal", title: "Work"))
        let travel = JournalItem(kind: "journal", title: "Travel")
        try await local.save(travel)
        try await local.save(JournalItem(kind: "entry", journalID: travel.id, title: "Lisbon"))
        let image = Data(repeating: 7, count: 2048)
        let imageID = try await local.addAttachment(image)
        try await local.save(
            JournalItem(
                kind: "entry", journalID: journal.id, title: "Local thought",
                document: .init(blocks: [
                    DocumentBlock(runs: [TextRun("Written on the phone")]),
                    DocumentBlock(
                        kind: "image", attachmentID: imageID, imageDescription: "Photo", mediaType: "image/png"),
                ])))
        var archived = JournalItem(kind: "entry", journalID: journal.id, title: "Archived thought")
        archived.archivedAt = Date()
        try await local.save(archived)
        var deleted = JournalItem(kind: "entry", journalID: journal.id, title: "Deleted thought")
        deleted.deletedAt = Date()
        try await local.save(deleted)
        for template in BuiltInTemplates.asEarlierBuildsCreated() where template.title != "Gratitude" {
            try await local.save(template)
        }
        var localGratitude = try XCTUnwrap(BuiltInTemplates.asEarlierBuildsCreated().first { $0.title == "Gratitude" })
        localGratitude.document = .plain("Edited on the phone")
        try await local.save(localGratitude)
        try await local.save(JournalItem(kind: "template", title: "standup", document: .plain("Yesterday, today")))
        try await local.save(JournalItem(kind: "template", title: "Ideas", document: .plain("What if")))
        return Scenario(
            local: local, serverDefault: serverDefault, serverWork: serverWork,
            serverGratitude: templates[gratitudeIndex], localGratitude: localGratitude, image: image)
    }

    func testMergingCombinesSameNameJournalsAndKeepsBothOfDifferentTemplates() async throws {
        do {
            let server = MergeServer()
            let setup = try await scenario(server)
            // An agent reads the server's "Work", so it's never combined.
            let (staged, _) = try await merge(setup.local, into: server, readByAgents: [setup.serverWork.id])
            let result = try await downloaded(server).items()

            let defaults = live(result, "journal", "Default")
            XCTAssertEqual(defaults.map(\.id), [setup.serverDefault.id], "Same-name journals become one.")
            let inDefault = result.filter { $0.journalID == setup.serverDefault.id }.map(\.title)
            XCTAssertEqual(
                Set(inDefault), ["From the Mac", "Local thought", "Archived thought", "Deleted thought"])
            XCTAssertNotNil(result.first { $0.title == "Archived thought" }?.archivedAt)
            XCTAssertNotNil(result.first { $0.title == "Deleted thought" }?.deletedAt)
            XCTAssertEqual(
                live(result, "journal", "Work").map(\.id), [setup.serverWork.id],
                "A journal an agent reads isn't combined.")
            XCTAssertEqual(live(result, "journal", "Work 2").count, 1, "This device's is added with a number.")
            XCTAssertEqual(live(result, "journal", "Travel").count, 1)
            for title in ["Daily Reflection", "Workday Log", "Weekly Reflection", "Standup", "Ideas"] {
                XCTAssertEqual(live(result, "template", title).count, 1, "\(title) is on the server once.")
            }
            let entry = try XCTUnwrap(result.first { $0.title == "Local thought" })
            let imageID = try XCTUnwrap(entry.document.attachmentIDs.first)
            let downloadedImage = try await downloaded(server).attachment(imageID)
            XCTAssertEqual(downloadedImage, setup.image)

            // The different "Gratitude" is settled when the merge ends, like any version found on two devices: this
            // device's version is the template and the server's is kept as a template of its own.
            let reviews = try await staged.conflicts()
            XCTAssertTrue(reviews.isEmpty)
            XCTAssertEqual(live(result, "template", "Gratitude").map(\.document), [setup.localGratitude.document])
            XCTAssertEqual(
                live(result, "template", "Gratitude (other version)").map(\.document), [setup.serverGratitude.document])
            let unsent = try await staged.pending()
            XCTAssertTrue(unsent.isEmpty, "Nothing is left unsent.")
        }
    }

    func testUnknownAgentAccessNumbersEveryMatch() async throws {
        let server = MergeServer()
        let setup = try await scenario(server)
        let staged = try store()
        let engine = SyncEngine(store: staged, server: server)
        try await engine.synchronize()
        try await staged.importMerging(from: setup.local, server: await server.identity, readByAgents: nil)
        try await engine.synchronize()
        let items = try await downloaded(server).items()
        XCTAssertEqual(live(items, "journal", "Default").map(\.id), [setup.serverDefault.id])
        XCTAssertEqual(live(items, "journal", "default 2").count, 1)
        XCTAssertEqual(live(items, "journal", "Work 2").count, 1)
    }

    func testUnmatchedSameNameJournalsAreNumberedTheSameOnEveryAttempt() async throws {
        let server = MergeServer()
        let (mac, macSync) = try await otherDevice(server)
        try await mac.save(JournalItem(kind: "journal", title: "Default"))
        try await macSync.synchronize()
        let local = try store(key: deviceKey)
        try await local.insertWithoutChecks([
            JournalItem(kind: "journal", title: "Travel", date: Date(timeIntervalSince1970: 1_000)),
            JournalItem(kind: "journal", title: "travel", date: Date(timeIntervalSince1970: 2_000)),
            JournalItem(kind: "journal", title: "Default"),
        ])
        try await merge(local, into: server)
        try await merge(local, into: server)
        let items = try await downloaded(server).items()
        let titles = items.filter(JournalNames.isListed).map(\.title).sorted()
        XCTAssertEqual(titles, ["Default", "Travel", "travel 2"])
    }

    /// A join tried again after the server deleted what the first attempt sent (docs/design/journal-name-uniqueness.md
    /// §4.5, rule B): the deletion stands, and what this device wrote since goes to Recently Deleted.
    func testARetriedJoinDoesNotReviveAJournalDeletedMeanwhile() async throws {
        for permanently in [false, true] {
            let server = MergeServer()
            let (mac, macSync) = try await otherDevice(server)
            let local = try store(key: deviceKey)
            let travel = JournalItem(kind: "journal", title: "Travel")
            try await local.save(travel)
            try await local.save(JournalItem(kind: "entry", journalID: travel.id, title: "Lisbon"))
            try await merge(local, into: server)

            try await macSync.synchronize()
            let sent = MergePlan.derived(travel.id, server: await server.identity)
            _ = try await mac.deleteJournal(mac.prepareJournalDeletion(sent))
            if permanently { try await mac.permanentlyDelete(mac.preparePermanentDeletion(sent)) }
            try await macSync.synchronize()

            try await local.save(JournalItem(kind: "entry", journalID: travel.id, title: "Porto"))
            let (staged, _) = try await merge(local, into: server)
            let reviews = try await staged.conflicts()
            XCTAssertTrue(reviews.isEmpty, "Nothing becomes a change to review.")
            let unsent = try await staged.pending()
            XCTAssertTrue(unsent.isEmpty)

            let result = try await downloaded(server)
            let items = try await result.items()
            XCTAssertTrue(items.filter(JournalNames.isListed).isEmpty, "The journal stays deleted.")
            let snapshot = try await result.lifecycleSnapshot()
            let porto = try XCTUnwrap(items.first { $0.title == "Porto" }, "What this device wrote since is kept.")
            XCTAssertEqual(
                snapshot.location(of: porto), permanently ? .unavailable(.missing) : .recentlyDeleted,
                "It arrives as an entry written offline into that journal would.")
            let lisbon = items.first { $0.title == "Lisbon" }
            if permanently {
                XCTAssertNil(lisbon, "What was deleted permanently doesn't come back.")
            } else {
                XCTAssertEqual(lisbon.map { snapshot.location(of: $0) }, .recentlyDeleted)
            }
        }
    }

    // MARK: Failures and retries

    private enum Interruption: CaseIterable {
        /// Downloading fails; images fail to upload; images are sent but no record; some records are sent; all is
        /// sent but the connection isn't committed.
        case download, imageUpload, afterImages, sending, beforeCommit
    }
    func testEveryInterruptedAttemptRecoversWithoutLossOrDuplicates() async throws {
        for interruption in Interruption.allCases {
            let server = MergeServer()
            let setup = try await scenario(server)
            // The first attempt stops part way; its staged copy is discarded, as after a failure, a cancel or the
            // app quitting before the connection was committed.
            switch interruption {
            case .download: await server.failNextPages(1)
            case .imageUpload: await server.failUploads(after: 0)
            case .afterImages: await server.failPushes(after: 0)
            case .sending: await server.failPushes(after: 3)
            case .beforeCommit: break
            }
            do { try await merge(setup.local, into: server) } catch {}
            await server.failUploads(after: nil)
            await server.failPushes(after: nil)

            // Try Again, with a new device grant: a new staged copy.
            let (staged, _) = try await merge(setup.local, into: server)
            let result = try await downloaded(server).items()
            for title in ["From the Mac", "Local thought", "Archived thought", "Deleted thought", "Lisbon"] {
                XCTAssertEqual(result.filter { $0.title == title }.count, 1, "\(interruption): \(title) once")
            }
            XCTAssertEqual(live(result, "journal", "Default").count, 1, "\(interruption)")
            XCTAssertEqual(live(result, "template", "Ideas").count, 1, "\(interruption)")
            let refused = await server.refusedUploads
            XCTAssertEqual(refused, 0, "\(interruption): an image is never uploaded again under its identity")
            let images = await server.images
            XCTAssertEqual(images.count, 1, "\(interruption)")
            let unsent = try await staged.pending()
            XCTAssertTrue(unsent.isEmpty, "\(interruption): nothing waits forever")
            let unverified = try await staged.attachmentsToVerify()
            XCTAssertEqual(unverified, [], "\(interruption)")
        }
    }

    func testChangesAfterAnInterruptedAttemptAreEditsOrKeepBothVersions() async throws {
        let server = MergeServer()
        let setup = try await scenario(server)
        try await merge(setup.local, into: server)
        let firstMerge = try await downloaded(server).items()
        let mergedTravel = try XCTUnwrap(firstMerge.first { $0.title == "Lisbon" })
        let mergedThought = try XCTUnwrap(firstMerge.first { $0.title == "Local thought" })

        // Before the connection was committed, this device edited two entries, and the Mac edited one of them.
        let localItems = try await setup.local.items()
        var lisbon = try XCTUnwrap(localItems.first { $0.title == "Lisbon" })
        lisbon.document = .plain("Edited on the phone after the failure")
        try await setup.local.save(lisbon)
        var thought = try XCTUnwrap(localItems.first { $0.title == "Local thought" })
        thought.document = .plain("Phone version")
        try await setup.local.save(thought)
        let (mac, macSync) = try await otherDevice(server)
        let macCopy = try await mac.item(mergedThought.id)
        var macThought = try XCTUnwrap(macCopy)
        macThought.document = .plain("Mac version")
        try await mac.save(macThought)
        try await macSync.synchronize()

        let (staged, _) = try await merge(setup.local, into: server)
        let travelRecord = await server.records[mergedTravel.id]
        let travel = try XCTUnwrap(travelRecord)
        XCTAssertEqual(travel.revision, 2, "Only the earlier attempt had written it: an ordinary edit.")
        let travelNow = try await downloaded(server).item(mergedTravel.id)
        XCTAssertEqual(travelNow?.document, lisbon.document)
        let reviews = try await staged.conflicts()
        XCTAssertTrue(reviews.isEmpty)
        let entries = try await downloaded(server).items().filter { $0.kind == "entry" }
        let kept = try XCTUnwrap(entries.first { $0.id == mergedThought.id })
        XCTAssertEqual(kept.document, thought.document, "Another device changed it: this device's version stays")
        XCTAssertEqual(
            entries.filter { $0.title == "Local thought (other version)" }.map(\.document), [macThought.document],
            "…and the other is kept as an entry of its own: nothing lost.")
    }

    /// A phone and a new phone restored from its backup hold copies of one library. Each continues the same entry,
    /// then both merge into the same server, also after another device moved the entry to Recently Deleted in
    /// between. The second merge keeps both versions instead of replacing the first one's as if only an earlier
    /// attempt of its own had written it.
    func testCopiesOfOneLibraryMergedFromTwoDevicesKeepBothVersions() async throws {
        for deletedMeanwhile in [false, true] {
            let server = MergeServer()
            let oldPhone = try store("old-phone-\(deletedMeanwhile)", key: deviceKey)
            let journal = JournalItem(kind: "journal", title: "Diary")
            try await oldPhone.save(journal)
            let shared = try await oldPhone.save(
                JournalItem(kind: "entry", journalID: journal.id, document: .plain("Written before the backup")))
            let newPhoneFolder = root.appendingPathComponent("new-phone-\(deletedMeanwhile)")
            try await oldPhone.snapshot(to: newPhoneFolder)
            let newPhone = try JournalStore(directory: newPhoneFolder, key: deviceKey)
            for (library, text) in [(oldPhone, "Continued on the old phone"), (newPhone, "Continued on the new phone")]
            {
                let stored = try await library.item(shared.id)
                var continued = try XCTUnwrap(stored)
                continued.document = .plain(text)
                try await library.save(continued)
            }

            try await merge(oldPhone, into: server)
            if deletedMeanwhile {
                let (mac, macSync) = try await otherDevice(server)
                let onMac = try await mac.item(MergePlan.derived(shared.id, server: await server.identity))
                var deleted = try XCTUnwrap(onMac)
                deleted.deletedAt = Date()
                try await mac.save(deleted)
                try await macSync.synchronize()
            }
            let (newMerged, _) = try await merge(newPhone, into: server)
            let reviews = try await newMerged.conflicts()
            XCTAssertTrue(reviews.isEmpty, "\(deletedMeanwhile)")
            let onServer = try await downloaded(server).items().filter { $0.kind == "entry" }
            XCTAssertEqual(
                Set(onServer.map(\.document.text)), ["Continued on the old phone", "Continued on the new phone"],
                "Neither replaces the other: \(deletedMeanwhile)")
            XCTAssertEqual(onServer.count, 2, "\(deletedMeanwhile)")
            // What the other device moved to Recently Deleted stays there, and so does this device's version of it.
            XCTAssertEqual(
                onServer.filter { $0.deletedAt != nil }.count, deletedMeanwhile ? 2 : 0, "\(deletedMeanwhile)")
        }
    }

    func testEntriesMergedIntoAJournalDeletedMeanwhileCanBeRestored() async throws {
        let server = MergeServer()
        let setup = try await scenario(server)
        let staged = try store()
        let engine = SyncEngine(store: staged, server: server)
        try await engine.synchronize()
        try await staged.importMerging(
            from: setup.local, server: await server.identity, readByAgents: [])
        // Another device moves "Default" to Recently Deleted before this device sends its entries.
        let (mac, macSync) = try await otherDevice(server)
        let snapshot = try await mac.lifecycleSnapshot()
        _ = try await mac.deleteJournal(try snapshot.deletionPlan(for: setup.serverDefault.id))
        try await macSync.synchronize()
        try await engine.synchronize()

        let viewer = try await downloaded(server)
        let merged = try await viewer.items().filter { $0.title == "Local thought" }
        XCTAssertEqual(merged.count, 1)
        let whileDeleted = try await viewer.lifecycleSnapshot()
        XCTAssertEqual(whileDeleted.location(of: merged[0]), .recentlyDeleted)
        _ = try await viewer.restoreJournal(setup.serverDefault.id)
        let restored = try await viewer.item(merged[0].id)
        let afterRestore = try await viewer.lifecycleSnapshot()
        XCTAssertEqual(afterRestore.location(of: try XCTUnwrap(restored)), .journal)
    }

    /// A restore brings back the records, change log and images of a backup under a new server identity. Identities
    /// derived for the old identity no longer match: restoring a backup from before the attempt leaves everything
    /// once; one from after part of the attempt can leave a second copy, which §2.1 accepts, but never loses anything.
    func testARestoredServerBetweenAttemptsLosesNothing() async throws {
        for backupTakenAfterAttempt in [false, true] {
            let server = MergeServer()
            let setup = try await scenario(server)
            let before = await server.backup()
            await server.failPushes(after: 4)
            do { try await merge(setup.local, into: server) } catch {}
            await server.failPushes(after: nil)
            await server.restore(backupTakenAfterAttempt ? server.backup() : before)
            try await merge(setup.local, into: server)
            let titles = try await downloaded(server).items().map(\.title)
            for title in ["Local thought", "Archived thought", "Deleted thought", "Lisbon", "Ideas", "From the Mac"] {
                let copies = titles.filter { $0 == title }.count
                if backupTakenAfterAttempt {
                    XCTAssertGreaterThanOrEqual(copies, 1, "\(title) is on the server")
                } else {
                    XCTAssertEqual(copies, 1, "\(title) is on the restored server once")
                }
            }
        }
    }

    func testALargeLibraryMergesCompletely() async throws {
        let server = MergeServer()
        let local = try store(key: deviceKey)
        let journal = JournalItem(kind: "journal", title: "Notes")
        try await local.save(journal)
        for index in 0..<450 {
            try await local.save(JournalItem(kind: "entry", journalID: journal.id, title: "Note \(index)"))
        }
        await server.failPushes(after: 200)
        do { try await merge(local, into: server) } catch {}
        await server.failPushes(after: nil)
        try await merge(local, into: server)
        let entries = try await downloaded(server).items().filter { $0.kind == "entry" }
        XCTAssertEqual(entries.count, 450)
        XCTAssertEqual(Set(entries.map(\.title)).count, 450)
    }
}
