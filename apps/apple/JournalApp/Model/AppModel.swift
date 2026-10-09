import Combine
import CryptoKit
import JournalCore
import LocalAuthentication
import SwiftUI
import os

enum AppSettingsTab: Hashable { case general, sync, privacy, backup, agents }

/// Why writing is paused for a server connection: it is being set up, or a failed one waits for Try Again.
enum ServerConnectionPause: Equatable { case connecting, waitingForRetry }

@MainActor
final class AppModel: ObservableObject {
    @Published var loaded = false
    private var starting = false
    /// Why the journals on this device can't be opened, if they can't (LibraryProblem.swift). While it is set the
    /// model has no live library, never locks, and refuses every change of the configuration.
    @Published var libraryProblem: LibraryProblem?
    /// The last problem set, so the screen keeps describing it while Try Again runs.
    var lastLibraryProblem: LibraryProblem?
    /// Try Again is running (the screen shows progress in place of its buttons).
    @Published var retryingOpen = false
    /// How many taps of Try Again ended in a problem again, in memory: Erase is offered after one.
    @Published var failedRetries = 0
    /// The library opened, and its first read hasn't succeeded yet: a failed read then is a failed open.
    var firstReadPending = false
    /// A library closed after a failed open or first read, which the next open waits for.
    var libraryClosing: Task<Void, Never>?
    /// iPhone and iPad: files and Keychain items aren't readable before the first unlock or while the device is
    /// locked, so a failed open then ends by itself and offers nothing that removes anything.
    @Published var protectedDataAvailable = true
    /// Erase lists the app's Keychain items to remove what the configuration doesn't name, for the app's own data
    /// folder only (never under test, so erasing there can't remove a real library's keys).
    var sweepsKeychain = false
    /// The preferences Erase removes its own keys from; tests use a suite of their own.
    var preferences = UserDefaults.standard
    /// Lists the Keychain's accounts for Erase; replaced by tests.
    var keychainListing: () throws -> [String] = { try Keychain.accounts() }
    /// How long the encryption form's check and the unfinished state's questions to the server may take; tests set it
    /// shorter.
    var serverQuestionSeconds: TimeInterval = 10
    /// The bytes free for important use on the volume that holds `directory`; tests replace it.
    var availableStorage: (URL) -> Int64? = {
        (try? $0.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }
    /// The library is being replaced (connecting, pairing or importing); this starts a new vault session.
    /// Set while connecting (ServerJoining.swift) or importing replaces the library.
    @Published var vaultReplacement = false {
        didSet {
            if vaultReplacement {
                vaultSessionID = UUID()
                imageInsertionGeneration = UUID()
                initialInsertion = nil
                titleFocus = nil
                entryCreationID = nil
                // The journals list leaves edit mode (journal-order.md). Committing a change, such as deleting a
                // journal in edit mode, keeps it.
                editingJournals = false
            }
            updateImageLoading()
        }
    }
    /// An entry action (Move, Change Date, Restore) is being committed to the open library.
    @Published private(set) var committingMutation = false
    /// A library copy staged for joining a server, kept for Try Again with the same access. `merges` and `key` are
    /// how it joins (ServerJoining.swift, `joinPlan`).
    @Published var stagedVault: (deviceID: UUID, folder: String, store: JournalStore, merges: Bool, key: Data)?
    /// Nothing may change the open library: it is being replaced, an entry action is being committed, or a copy
    /// of it waits for Try Again, which must not miss writing done in the meantime.
    var replacingVault: Bool { vaultReplacement || committingMutation || stagedVault != nil }
    /// A server connection is being set up; unlike an archive import, it can take a while.
    @Published var connectingToServer = false
    /// What joining a server is doing while it merges this library's journals (docs/design/join-with-local-journals.md).
    @Published var joinPhase: JoinPhase?
    /// Access a join received and kept for Try Again, as a one-time recovery code can't be used twice; given up when
    /// the connection flow is left (`giveUpRetry`).
    var retryGrant: (address: String, key: Data, grant: DeviceGrant)?
    /// Merging has started sending this device's journals, so some may already be on the server.
    var mergeSending = false
    /// The server the person agreed, on Merge Journals, to merge this library with in the open connection flow.
    var agreedMergeHost: String?
    /// Writing is paused for a server connection. The Mac says so in its window, where the connection sheet sits
    /// on the Settings window; on iPhone and iPad the sheet covers the app.
    var serverConnectionPause: ServerConnectionPause? {
        if stagedVault != nil && !vaultReplacement { return .waitingForRetry }
        return vaultReplacement && connectingToServer ? .connecting : nil
    }
    var items: [JournalItem] {
        get { storedItems }
        set {
            objectWillChange.send()
            storedItems = newValue
            itemsChanged()
        }
    }
    /// The items, changed in place by `replaceQuietly` when only an entry's writing changed.
    private var storedItems: [JournalItem] = []
    func replaceQuietly(at index: Int, with item: JournalItem) { storedItems[index] = item }
    /// Lists derived from `items`, kept until what they depend on changes.
    let lists = DerivedLists()
    @Published var selectedJournalID: UUID? {
        didSet { journalReplacedAutomatically = false }
    }
    /// The selected journal was chosen in place of one that left the list (deleted here or by a sync), not by the
    /// person or an action that shows a journal, such as Merge Into…. On iPhone, the journal's page goes back to
    /// Journals then.
    private(set) var journalReplacedAutomatically = false
    /// Set when launching or unlocking restores an entry, so the iPhone shows it rather than the list.
    @Published var revealsSelection = false
    @Published var selectedID: UUID? {
        didSet {
            guard oldValue != selectedID else { return }
            imageInsertionGeneration = UUID()
            // Choosing an entry is use, also with VoiceOver or Voice Control, which send no key or click.
            noteUse()
        }
    }
    var draft: JournalItem? {
        willSet { if !lists.quietDraft { objectWillChange.send() } }
        didSet {
            // An image being added belongs to the open entry, wherever its text changed meanwhile (typing, a sync).
            if oldValue?.id != draft?.id {
                imageInsertionGeneration = UUID()
                if oldValue != nil { sendWritingAfterLeaving() }
            }
            if draft?.id != initialInsertion?.itemID { initialInsertion = nil }
            if draft?.id != titleFocus?.itemID { titleFocus = nil }
            // Opening a stored version makes it the base of later edits; editing keeps the base.
            if !keepsDraftBase { draftBase = draft }
            if !lists.textOnlyDraft { updateImageLoading() }
        }
    }
    private(set) var vaultSessionID = UUID()
    private(set) var imageInsertionGeneration = UUID()
    var titleFocus: InitialTitleFocus? {
        didSet { if oldValue !== titleFocus { oldValue?.cancel() } }
    }
    var initialInsertion: InitialEditorInsertion?
    private var entryCreationID: UUID?
    var creatingEntry: Bool { entryCreationID != nil }
    /// The search. Typing in the search field updates the list once the results are ready; views update at once only
    /// where a search starts or ends, or in Recently Deleted, which filters its journals by name as it's typed.
    var query: String {
        get { storedQuery }
        set {
            let changed = newValue != storedQuery
            if newValue.isEmpty != storedQuery.isEmpty || showingTrash { objectWillChange.send() }
            storedQuery = newValue
            if changed { searchQuery() }
        }
    }
    private var storedQuery = ""
    @Published var showingTrash = false
    @Published var showingTemplates = false
    @Published var showingUnavailable = false
    @Published var showingAllEntries = false
    /// Where Delete All in Recently Deleted is, for every window and the menu bar (PermanentDeletionOperations.swift).
    @Published var deleteAllPhase = DeleteAllPhase.idle
    @Published var error: String? {
        didSet { if error != nil { reviewRequests.noteProblem() } }
    }
    @Published var saveFailure = false {
        didSet {
            if saveFailure {
                reviewRequests.noteProblem()
            } else {
                saveRequiredAlert = nil
            }
        }
    }
    /// An operation shown in the app's alert needed the open entry saved first (`report(_:_:)`).
    @Published var saveRequiredAlert: JournalError?
    @Published var locked = false {
        didSet {
            if locked {
                reviewRequests.noteLocked()
                vaultSessionID = UUID()
                imageInsertionGeneration = UUID()
                initialInsertion = nil
                titleFocus = nil
                entryCreationID = nil
                // The journals list leaves edit mode (journal-order.md). Committing a change, such as deleting a
                // journal in edit mode, keeps it.
                editingJournals = false
            }
            updateImageLoading()
        }
    }
    /// Unlocked, and the journals are still being read (AppLockOperations.swift).
    @Published var openingJournals = false
    /// Erase Journals and Settings is moving the library aside (EraseOperations.swift); windows close what they show.
    @Published var erasingLibrary = false
    @Published var recoveryKey: String?
    @Published var configuration: LocalConfiguration?
    let imageLoader = DocumentImageLoader()
    var imageData: [UUID: Data] { imageLoader.images }
    private var imageSubscription: AnyCancellable?
    /// The changes the person can still review: entries and templates changed on two devices, and those a newer
    /// version of the app must open. Journal and deletion conflicts have no review; this version settles them itself
    /// (ConflictNotes.swift).
    @Published var conflicts: [ConflictVersion] = [] {
        didSet {
            lists.invalidate()
            if !conflicts.isEmpty { reviewRequests.noteProblem() }
        }
    }
    /// Every record that has a conflict, reviewable or not; the lifecycle of journals and entries follows it.
    var conflictedIDs: Set<UUID> = []
    /// The conflicted journals and deletions that settle at the next pull, which don't keep a journal out of use.
    var settlingConflictIDs: Set<UUID> = []
    /// The conflicts that wait for a version of this app that can read them.
    var heldConflictIDs: Set<UUID> = []
    /// A journal or deletion conflict waits for a newer version (Settings ▸ Sync says so).
    @Published var heldChangesNeedUpdate = false {
        didSet { if heldChangesNeedUpdate { reviewRequests.noteProblem() } }
    }
    /// What this device settled by keeping both versions (Settings ▸ Sync ▸ Changed on Two Devices).
    @Published var keptNotes: [KeptNote] = []
    @Published var pendingSync = false
    /// Pins and journal ranks (LibraryOperations.swift), and what Settings ▸ Sync says about them.
    @Published var library = LibraryArrangement.empty {
        didSet { if library != oldValue { lists.invalidate() } }
    }
    @Published var librarySync = LibrarySyncState()
    /// The Journals list's edit mode on iPhone and iPad (journal-order.md).
    @Published var editingJournals = false
    /// The front window's undo manager, for menu bar commands that can be undone.
    weak var windowUndoManager: UndoManager?
    @Published var syncError: String?
    /// The last synchronization failed as a whole, for example without a connection, and `syncError` says why.
    /// Otherwise `syncError` describes a record or image that can't sync while everything else did.
    @Published var syncFailed = false
    /// Why the last synchronization failed, as one of the states in docs/design/sync-health-and-recovery.md; nil
    /// once it succeeds.
    @Published var syncHealth: SyncHealth?
    /// Changes have waited more than a day while sync fails (`updateSyncLongWait`): Sync Status asks for attention.
    @Published var syncLongWait = false
    @Published var connection: SyncConnection? {
        didSet { syncActivity.connectionChanged(connection) }
    }
    /// The last complete synchronization and Sync Now's progress (SyncSchedule.swift).
    lazy var syncActivity = SyncActivity(directory: directory)
    static let defaultTextSize: Double = 16
    @Published var textSize: Double = defaultTextSize
    /// Menu requests the window's views answer: New Journal, Import Archive…, Export Archive….
    @Published var newJournalRequested = false
    @Published var archiveImportRequested = false
    @Published var archiveExportPresented = false
    /// File ▸ Export Journals as Markdown…'s sheet.
    @Published var markdownExportPresented = false
    @Published var settingsPresented = false
    @Published var templateChooserPresented = false
    @Published var settingsTab: AppSettingsTab = .general
    /// The pane Settings opens at on iPhone and iPad, once (Sync Settings… in Sync Status).
    var settingsRequestedTab: AppSettingsTab?
    /// When the device owner last authenticated to set a new password without the current one.
    var passwordResetAuthorizedAt: Date?
    /// App Lock's authentication: the device's own (AppLockOperations.swift, DeviceAuthentication.swift).
    var deviceOwner: DeviceOwnerAuthenticating
    @Published var unlockState = DeviceUnlockState()
    /// Saves of typed content in open sheets, run before locking (LockSaving.swift).
    var savesBeforeLocking: [UUID: @MainActor () async -> Void] = [:]
    /// Image descriptions a lock closed before they were saved (LockSaving.swift).
    var unsavedImageDescriptions: UnsavedImageDescriptions?
    /// Whether the app is active, kept current from the system; a success is applied only while it is.
    var applicationActive = false
    private var activitySubscriptions: [AnyCancellable] = []
    /// Turn On Encryption, which outlasts the sheet that shows it (EncryptionUpgrade.swift).
    lazy var encryption = EncryptionUpgrade(model: self)
    /// The system's rating request at a pause in writing (ReviewRequestTiming.swift).
    lazy var reviewRequests: ReviewRequests = {
        let requests = ReviewRequests.forApp(hostsTests: Self.hostsTests)
        requests.momentIsClear = { [weak self] in self?.reviewMomentIsClear ?? false }
        return requests
    }()

    #if os(macOS)
        /// Locks after a time without use (InactivityLock.swift); started once the app has launched.
        var inactivityLock: InactivityLock?
        /// The journal window; menu commands that need it open it again after it was closed.
        weak var journalWindow: NSWindow?
        var hasJournalWindow: Bool { journalWindow.map { $0.isVisible || $0.isMiniaturized } ?? false }
    #endif
    var store: JournalStore? {
        didSet {
            if oldValue !== store {
                vaultSessionID = UUID()
                imageInsertionGeneration = UUID()
                initialInsertion = nil
                titleFocus = nil
                entryCreationID = nil
                // A library opened at launch sets it again, after assigning the store (LibraryOpening.swift).
                firstReadPending = false
                // The journals list leaves edit mode (journal-order.md). Committing a change, such as deleting a
                // journal in edit mode, keeps it.
                editingJournals = false
            }
            updateImageLoading()
        }
    }
    /// Replaced when the library is (connecting in ServerJoining.swift, importing, turning on encryption).
    var masterKey: Data?
    private var saveTask: Task<Void, Never>?
    /// Settles the conflicts a library without a server holds once writing pauses (ConflictNotes.swift).
    var localResolution: Task<Void, Never>?
    /// Speaks a change the person may not see, such as where Restore put an entry; tests replace it.
    var announce: @MainActor (String) -> Void = { JournalAccessibility.announce($0) }
    private var mutationTask: Task<Void, Error>?
    var journalEditTask: Task<Void, Never>?
    private var saveGeneration = 0
    /// The stored version the open draft was read or last saved as. Writing differs from it until it's saved.
    var draftBase: JournalItem?
    var keepsDraftBase = false
    /// The save of the open draft in progress. Saves run one at a time, each based on what the previous one stored.
    var draftWrite: (id: UUID, task: Task<Error?, Never>)?
    var draftWrites = 0
    /// The store's received-change count when the view was last read from it.
    private var refreshedChanges: Int?
    var syncEngine: SyncEngine?
    /// Keeps the copies agents read through the sync server current (docs/design/agent-access-server.md).
    private(set) var agentCopies: AgentCopyPublisher?
    /// Sends the declines of agent requests for as long as the app runs, so they outlive the Settings window.
    let agentDeclines = AgentRequestDeclines()
    var supersededRemoval: Task<Void, Never>?
    let syncTiming = SyncTiming()
    let directory: URL

    init(directory explicitDirectory: URL? = nil) {
        if let explicitDirectory {
            directory = explicitDirectory
        } else if let path = ProcessInfo.processInfo.environment["JOURNAL_DATA_DIR"] {
            directory = URL(fileURLWithPath: path)
        } else if let testID = ProcessInfo.processInfo.environment["JOURNAL_UI_TEST_ID"] {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("JournalUITest-" + testID, isDirectory: true)
        } else if Self.hostsTests {
            // The app hosting unit tests never opens the journals of the person running them.
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "JournalTestHost-" + UUID().uuidString, isDirectory: true)
        } else {
            directory = Self.defaultDirectory
        }
        sweepsKeychain =
            explicitDirectory == nil && !Self.hostsTests
            && ProcessInfo.processInfo.environment["JOURNAL_DATA_DIR"] == nil
            && ProcessInfo.processInfo.environment["JOURNAL_UI_TEST_ID"] == nil
        deviceOwner = SystemDeviceOwner.make()
        imageSubscription = imageLoader.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        observeApplicationActivity()
    }
    private func observeApplicationActivity() {
        #if os(macOS)
            let became = NSApplication.didBecomeActiveNotification
            let resigned = NSApplication.didResignActiveNotification
        #else
            let became = UIApplication.didBecomeActiveNotification
            let resigned = UIApplication.willResignActiveNotification
        #endif
        let center = NotificationCenter.default
        activitySubscriptions = [
            center.publisher(for: became).receive(on: RunLoop.main).sink { [weak self] _ in
                Task { @MainActor in await self?.applicationBecameActive() }
            },
            center.publisher(for: resigned).receive(on: RunLoop.main).sink { [weak self] _ in
                Task { @MainActor in self?.applicationResignedActive() }
            },
        ]
        #if os(iOS)
            observeProtectedData(center)
        #endif
    }
    #if os(iOS)
        /// A launch before the first unlock, or while the device is locked, can't open the library; it opens by
        /// itself once protected data is available (LibraryProblem.swift).
        private func observeProtectedData(_ center: NotificationCenter) {
            protectedDataAvailable = UIApplication.shared.isProtectedDataAvailable
            activitySubscriptions += [
                center.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)
                    .receive(on: RunLoop.main).sink { [weak self] _ in
                        Task { @MainActor in await self?.protectedDataBecameAvailable() }
                    },
                center.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)
                    .receive(on: RunLoop.main).sink { [weak self] _ in
                        Task { @MainActor in self?.protectedDataAvailable = false }
                    },
            ]
        }
    #endif
    /// Application Support inside the app's container when the app is sandboxed.
    private static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrivateJournal", isDirectory: true)
    }
    /// Whether this process hosts unit tests, which load into the app itself (the same check `Keychain` uses).
    static let hostsTests =
        NSClassFromString("XCTestCase") != nil
        || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    var keyAccount: String {
        "master-" + SHA256.hash(data: Data(directory.path.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    var configURL: URL { directory.appendingPathComponent("configuration.json") }
    func start(password: String) async {
        // Starting a journal overwrites the configuration; not while the one there couldn't be read or opened.
        guard configuration == nil, !starting, libraryProblem == nil else { return }
        starting = true
        defer { starting = false }
        var staged: NewVault?
        do {
            let created = try await NewVault.prepare(in: directory, password: password)
            staged = created
            // The key's name is saved with the library, never derived from where the library is stored: an iOS
            // app's container path can change with an update.
            let account = "master-" + UUID().uuidString.lowercased()
            try Keychain.write(created.key, account: account)
            // The connection's name too, so the library never finds an older library's connection by the
            // path-derived name (docs/design/erase-device-2026-10-04.md §5).
            configuration = LocalConfiguration(
                recovery: created.recovery, recoveryConfirmed: true, storageFolder: created.folder, keyID: account,
                connectionKeyID: account + "-connection")
            do { try persistConfiguration() } catch {
                configuration = nil
                try? Keychain.remove(account)
                throw error
            }
            masterKey = created.key
            store = created.store
            selectedJournalID = created.journalID
            try await refresh()
        } catch {
            if configuration == nil { await staged?.discard() }
            self.error = error.shown(.saving)
        }
    }
    func replaceUnconfirmedRecoveryKey() async throws {
        guard let key = masterKey else { throw JournalError.locked }
        let phrase = try VaultCrypto.recoveryPhrase()
        let envelope = try await Task.detached { try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0 }.value
        configuration?.recovery = envelope
        try persistConfiguration()
        recoveryKey = phrase
    }
    func confirmRecovery() {
        do {
            configuration?.recoveryConfirmed = true
            try persistConfiguration()
            recoveryKey = nil
        } catch {
            self.error = error.shown(.saving)
        }
    }
    /// Saves the configuration. Every overwrite of the file goes through here, so while the journals can't be opened
    /// (or the settings read) it refuses: nothing replaces a file the app couldn't read, or abandons a library it
    /// couldn't open (docs/design/build-18-fixes-2026-10-06.md §2.1, rule 1).
    func persistConfiguration() throws {
        guard libraryProblem == nil else { throw LibraryNotOpenError() }
        try writeConfiguration()
    }
    /// The archive install's own save, which is the one change allowed over a library that can't be opened or whose
    /// key is missing: it was verified first, and the person chose it.
    func persistRestoredConfiguration() throws {
        if let problem = libraryProblem, !problem.offersImport { throw LibraryNotOpenError() }
        try writeConfiguration()
    }
    private func writeConfiguration() throws {
        guard let configuration else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JournalCoding.encoder().encode(configuration).write(to: configURL, options: .atomic)
    }
    func refresh(forSession expectedSession: UUID? = nil) async throws {
        guard let store, !locked else { return }
        let session = expectedSession ?? vaultSessionID
        let replacementPhase = replacingVault
        func isCurrent() -> Bool {
            self.store === store && vaultSessionID == session && !locked
                && replacingVault == replacementPhase && (expectedSession == nil || !Task.isCancelled)
        }
        guard isCurrent() else { return }
        let base = draftBase
        let writes = draftWrites
        let received = await store.receivedChangeCount()
        await store.rememberDecodedRecords()
        let snapshot: JournalViewSnapshot
        do { snapshot = try await store.viewSnapshot() } catch {
            // Damage inside the records is found here, not when the store opens: until the first read succeeds, a
            // failed read is a failed open (LibraryProblem.swift).
            guard firstReadPending, isCurrent() else { throw error }
            await failOpening(error)
            throw LibraryOpenHandled()
        }
        let libraryState = try? await store.librarySyncState()
        let held = snapshot.conflicts.isEmpty ? [] : ((try? await store.heldConflictIDs()) ?? [])
        let notes = (try? await store.keptNotes()) ?? []
        guard isCurrent() else { return }
        firstReadPending = false
        failedRetries = 0
        items = snapshot.items
        adoptConflicts(snapshot.conflicts, held: held)
        if notes != keptNotes { keptNotes = notes }
        pendingSync = snapshot.pending
        if library != snapshot.library { library = snapshot.library }
        if let libraryState, libraryState != librarySync { librarySync = libraryState }
        refreshedChanges = received
        followStoredDraft(from: base, writes: writes)
        reconcileDraftLocation()
        if selectedJournalID == nil || !journals.contains(where: { $0.id == selectedJournalID }) {
            selectedJournalID = journals.first { $0.id == configuration?.lastJournalID }?.id ?? journals.first?.id
            journalReplacedAutomatically = true
        }
        guard isCurrent() else { return }
        updateImageLoading(retry: true)
        removeSupersededLibraries(synchronized: false)
        await imageLoader.task?.value
    }

    /// Whether the visible entry or collection can change without first writing the current draft.
    /// Whether the open entry has writing that isn't stored yet; a sync may change other fields meanwhile.
    var draftHasUnsavedEdits: Bool {
        guard let draft, draft.kind != "journal" else { return false }
        if saveFailure || mutationTask != nil { return true }
        if let base = draftBase, base.id == draft.id, base.title != draft.title || base.document != draft.document {
            return true
        }
        guard let stored = items.first(where: { $0.id == draft.id }) else { return false }
        return stored.title != draft.title || stored.document != draft.document
    }
    var draftIsSaved: Bool {
        guard !replacingVault, !saveFailure, mutationTask == nil else { return false }
        guard let draft, draft.kind != "journal" else { return true }
        return draft == draftBase
    }
    /// Abandons a pending “new entry” so its completion doesn't replace a navigation the person chose.
    func endEntryCreation() { entryCreationID = nil }
    func updateDraft(_ item: JournalItem) {
        // Text typed into an editable entry keeps it editable; anything else is checked.
        let textOnly = draft.map { item.document.changesOnlyText(from: $0.document) } ?? false
        guard canEdit, draft?.id == item.id, textOnly || item.document.isEditable else { return }
        // Only the editor's edits arrive here, including Dictation's, which sends no key presses.
        noteUse()
        reviewRequests.noteEdit(entry: item.id)
        var item = item
        item.modifiedAt = Date()
        item.storedVersion = draft?.storedVersion
        changeDraftQuietly(item, textOnly: textOnly)
        saveGeneration += 1
        // Persist each editing event locally. Network sync is independently coalesced.
        if saveTask == nil {
            saveTask = Task {
                _ = await flush()
                saveTask = nil
            }
        }
    }
    func finishPendingSave() async -> Bool {
        await saveTask?.value
        return await flush()
    }
    func entryAutosaveSettled() async -> Bool {
        await saveTask?.value
        guard !saveFailure, let draft else { return false }
        // Field-only patches must not flush an old full record over newer store content.
        return draft == draftBase
    }
    func awaitEntryAutosave() async throws {
        guard await entryAutosaveSettled() else { throw JournalError.saveRequired }
    }
    /// How a failed write is announced in the alert. Writing again after each keystroke would otherwise repeat it.
    enum SaveFailureAnnouncement {
        /// The first failure only; the Not Saved notice carries the rest.
        case firstFailure
        /// Every failure: the person asked to try again.
        case always
        /// None, because the caller shows its own message.
        case never
    }
    @discardableResult func flush(
        whileEditing entryID: UUID? = nil, announcing announcement: SaveFailureAnnouncement = .firstFailure
    ) async -> Bool {
        let session = vaultSessionID
        let destination = store
        func canContinue() -> Bool {
            guard let entryID else { return true }
            return !Task.isCancelled && !locked && !replacingVault
                && vaultSessionID == session && store === destination && draft?.id == entryID
        }
        guard canContinue() else { return false }
        // A committed move must update the retained draft before any lifecycle save.
        _ = try? await mutationTask?.value
        guard canContinue() else { return false }
        while let write = draftWrite {
            _ = await write.task.value
            guard canContinue() else { return false }
        }
        guard let store, let item = draft else { return !saveFailure }
        // Journal selections are read-only metadata previews, and read-only entries can't have edits.
        guard item.kind != "journal", item.document.isEditable else { return !saveFailure }
        if !saveFailure, item == draftBase { return true }
        let generation = saveGeneration
        let failure = await writeDraft(item, to: store)
        guard canContinue() else { return false }
        guard failure == nil else {
            let firstFailure = !saveFailure
            saveFailure = true
            if announcement == .always || (announcement == .firstFailure && firstFailure) {
                // The lock screen can show this message, so it doesn't name the entry there.
                self.error =
                    locked
                    ? "Couldn’t save your changes. Unlock My Journal to try again."
                    : "Couldn’t save “\(item.displayTitle)”. Keep it open and try again."
            }
            return false
        }
        if generation == saveGeneration, saveFailure { saveFailure = false }
        reviewRequests.noteSaved(entry: item.id)
        if !pendingSync { pendingSync = true }
        syncWhenWritingPauses()
        resolveConflictsWhenWritingPauses()
        rememberSelection()
        if generation != saveGeneration { return await flush(whileEditing: entryID, announcing: announcement) }
        return true
    }
    /// A new, empty entry where New Entry puts it: in the journal shown, otherwise in the Default Journal. A template
    /// is used from inside the entry (`useTemplate`).
    func newEntry() async {
        guard !locked, !replacingVault, !Task.isCancelled, let store, let journal = newEntryJournal else { return }
        let creationID = UUID()
        reviewRequests.interrupt()
        var selection = selectedID
        var context = selectedJournalID
        let allEntries = showingAllEntries
        entryCreationID = creationID
        defer {
            if entryCreationID == creationID { entryCreationID = nil }
        }
        // Once the entry is saved it opens, even if the control that asked for it went away as the list changed.
        func isCurrent(cancellable: Bool = true) -> Bool {
            entryCreationID == creationID && self.store === store && !locked && !replacingVault
                && !(cancellable && Task.isCancelled) && selectedJournalID == context
                && showingAllEntries == allEntries && selectedID == selection
        }
        guard await flush(), isCurrent() else { return }
        // The list shows the journal the entry goes to, such as when it was started from Templates or Recently
        // Deleted. What was open there closes first, as choosing the journal does, so nothing closes it later.
        if destination != (allEntries ? .all : .journal(journal.id)) {
            showingTrash = false
            showingTemplates = false
            showingUnavailable = false
            selectedJournalID = journal.id
            context = journal.id
            selectedID = nil
            draft = nil
            selection = nil
        }
        do {
            let item = JournalItem(kind: "entry", journalID: journal.id)
            let stored = try await store.save(item)
            guard isCurrent(cancellable: false) else { return }
            query = ""
            try await refresh()
            guard isCurrent(cancellable: false) else { return }
            titleFocus = InitialTitleFocus(itemID: item.id)
            selectedID = item.id
            draft = stored
            rememberSelection()
        } catch {
            if isCurrent(cancellable: false) { self.error = error.shown(.saving) }
        }
    }
    func saveTemplate(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !locked, !replacingVault, await flush(), let draft, let store else { return }
        guard draft.kind != "journal" else { return }
        do {
            let template = JournalItem(kind: "template", title: trimmed, document: draft.document)
            try await store.save(template)
            try await refresh()
        } catch { self.error = error.shown(.saving) }
    }
    /// Synchronizes the current library with its connection and keeps agents' copies current from it. Every step that
    /// opens a library or commits a connection calls this, so a library that just joined publishes like one opened at
    /// launch. `engine` keeps the synchronization that already ran for this library and connection, as joining does.
    func configureSync(keeping engine: SyncEngine? = nil) {
        // The previous library's publisher never uploads from a library that was replaced.
        if let previous = agentCopies { Task { await previous.stop() } }
        // A new library or connection starts from a clean sync state; what was wrong with the previous one no
        // longer applies (docs/design/sync-health-and-recovery.md §2).
        resetSyncHealth()
        resetWatcher()
        guard let store, let connection,
            let client = try? ServerClient(address: connection.address, token: connection.token)
        else {
            syncEngine = nil
            agentCopies = nil
            return
        }
        syncEngine = engine ?? SyncEngine(store: store, client: client)
        agentCopies = AgentCopyPublisher(store: store, client: client)
    }
    /// Synchronizes once. Returns false when synchronization failed, for example without a connection; a record
    /// or image that can't sync as it is sets `syncError` while everything else synchronizes.
    /// `retryingRefused` also sends records and images the server refused before, as Sync Now and Try Again do.
    /// `waitingForWritingPause` leaves an entry being written until writing pauses, as automatic sync does.
    @discardableResult func sync(retryingRefused: Bool = false, waitingForWritingPause: Bool = false) async -> Bool {
        // The change watcher learns how every synchronization ended (docs/design/sync-protocol-efficiency.md §4.6).
        if syncTiming.watcher.waiting { handleWatcher(.quietBroken()) }
        var finished = ChangeWatcher.Finished(outcome: .declined, startedAt: .now, finishedAt: .now)
        defer {
            finished.finishedAt = .now
            handleWatcher(.syncFinished(finished))
            // Any synchronization that ran does what one the watcher asked for would.
            if finished.outcome != .declined { syncTiming.watcherSyncDue = false }
        }
        // Nothing reaches a server while an unencrypted library waits for the person's decision to encrypt.
        guard !locked, !replacingVault, !saveFailure, !encryptionHoldsSynchronization, let store, let syncEngine
        else { return false }
        // The floor between requests counts from every synchronization, not only the loop's.
        handleWatcher(.syncStarted)
        var report: SyncReport?
        var failure: Error?
        let request = SyncEngine.Request(
            retryingRefused: retryingRefused, waitingForWritingPause: waitingForWritingPause,
            preferredImages: Set(draft?.document.attachmentIDs ?? []), holdingConflicts: conflictsToHold)
        do { report = try await syncEngine.synchronize(request) } catch { failure = error }
        // Cancelled, for example on leaving the foreground: nothing was learned about the server.
        if failure is CancellationError || (failure as? URLError)?.code == .cancelled { return false }
        syncTiming.imagesToDownload = report?.imagesToDownload ?? 0
        guard self.store === store, !locked, !replacingVault else { return failure == nil }
        do {
            // Conflicts this synchronization settled by itself may have parked the open entry's edit elsewhere.
            let settled = report?.resolvedConflicts ?? []
            if !settled.isEmpty { await followParkedEntry(settled) }
            // Records may have arrived even when a later step failed. Without new ones, the list stays as it is.
            let received = await store.receivedChangeCount()
            if !settled.isEmpty || received != refreshedChanges {
                try await refresh()
            } else {
                let pending = try await store.hasPendingChanges()
                if pending != pendingSync { pendingSync = pending }
                // The server may have gained or lost the library record (Settings ▸ Sync's footer).
                if let state = try? await store.librarySyncState(), state != librarySync { librarySync = state }
            }
        } catch {
            failure = failure ?? error
        }
        // Views update only when what they show changes; most synchronizations change nothing.
        let health = failure.map(SyncHealth.init(classifying:))
        recordSyncHealth(health, failure: failure)
        let problem = health.map(syncMessage(of:)) ?? report?.problem
        if syncError != problem { syncError = problem }
        if syncFailed != (failure != nil) { syncFailed = failure != nil }
        updateSyncLongWait()
        await refreshPendingItems()
        if failure == nil {
            syncActivity.synced()
            removeSupersededLibraries(synchronized: true)
        }
        // Agents read what has synced, so their copies follow each successful sync.
        if failure == nil, let agentCopies { await agentCopies.requestPublishing() }
        finished.outcome = failure != nil ? .failed : report?.settled == true ? .settled : .unsettled
        finished.mark = report?.quietMark
        finished.position = report?.position
        finished.earliestRetry = report?.earliestRetry.map { .milliseconds(Int64($0 * 1000)) }
        finished.waitingSupported = report?.waitingSupported == true
        return failure == nil
    }
    /// Locks at once when App Lock is on, before anything else can be shown, and returns whether it did. Writing is
    /// saved afterwards by `saveWhileLocked()`.
    /// `prompting` asks the system without a tap once the app is active again, as after the background on iOS.
    @discardableResult func lockImmediately(prompting: Bool = false) -> Bool {
        // A library that can't be opened has no store to unlock: locking would put up a screen that leads nowhere.
        guard appLockOn, libraryProblem == nil, !retryingOpen else { return false }
        // A request still showing belongs to the earlier lock; its answer is ignored.
        deviceOwner.cancel()
        unlockState.lockCount += 1
        unlockState.pendingSuccess = nil
        unlockState.problem = false
        unlockState.promptPending = prompting
        unlockState.inactiveForRequest = false
        locked = true
        openingJournals = false
        // The journals list leaves edit mode (journal-order.md); its view is gone before it could see the lock.
        editingJournals = false
        SensitivePasteboard.clear()
        mutationTask?.cancel()
        if let agentCopies { Task { await agentCopies.stop() } }
        items = []
        adoptConflicts([], held: [])
        keptNotes = []
        localResolution?.cancel()
        localResolution = nil
        imageLoader.clear()
        query = ""
        lists.clear()
        if let store { Task { await store.forgetDecodedRecords() } }
        // A sync problem can name an entry. A health message names none, so the state keeps its own sentence.
        if syncHealth == nil { syncError = nil }
        return true
    }
    func unlockWithRecovery(_ phrase: String) async {
        guard let envelope = configuration?.recovery else { return }
        let result: (Data, RecoveryEnvelope)
        do { result = try await recoverKey(envelope, phrase: phrase) } catch {
            self.error = error.shown(.reading)
            return
        }
        do {
            let account = configuration?.keyID ?? keyAccount
            try Keychain.write(result.0, account: account)
            configuration?.keyID = account
            configuration?.recovery = result.1
            masterKey = result.0
        } catch {
            self.error = error.shown(.saving)
            return
        }
        if store == nil {
            do { try await openLibrary(key: result.0, protection: envelope.contentProtection) } catch {
                await failOpening(error)
                return
            }
            await numberDuplicateJournalsWithoutServer()
        }
        // The key is back: the missing key is no longer a problem, and the configuration can be saved.
        if libraryProblem == .needsKey { setLibraryProblem(nil) }
        do {
            // App Lock stays on: the device's authentication can't be forgotten the way a PIN could.
            configuration?.pinRetiredNotice = nil
            unlockState.problem = false
            try persistConfiguration()
            locked = false
            error = nil
            try await readJournalsAfterUnlocking()
            if draft == nil { selectInitialEntry(reveal: true) }
        } catch { report(error, .reading) }
    }

}

extension AppModel {
    /// Pauses writing while another operation replaces the library, as connecting does (turning on encryption).
    func pauseWriting(_ paused: Bool) {
        if vaultReplacement != paused { vaultReplacement = paused }
    }
    /// Opens `destination` with `key` in place of the current library once the configuration names it. Used by
    /// turning on encryption (EncryptionOperations.swift); the journals keep their identities.
    func openReplacedLibrary(_ destination: JournalStore, key: Data) async {
        masterKey = key
        let previous = store
        store = destination
        configureSync()
        selectedID = nil
        draft = nil
        selectedJournalID = nil
        items = []
        imageLoader.clear()
        do {
            try await refresh()
            selectInitialEntry()
        } catch {
            self.error = "Encryption is on, but your journals couldn’t be displayed. Reopen My Journal to try again."
        }
        try? await previous?.close()
    }
}

extension AppModel {
    /// Forgets the erased library, as if the app had just been installed (EraseOperations.swift): nothing of it stays
    /// in memory, nothing keeps running for it, and the window shows the first-launch screen.
    func clearErasedLibrary() {
        deviceOwner.cancel()
        unlockState.lockCount += 1
        unlockState.authenticating = false
        unlockState.promptPending = false
        unlockState.problem = false
        SensitivePasteboard.clear()
        saveTask?.cancel()
        saveTask = nil
        mutationTask?.cancel()
        mutationTask = nil
        journalEditTask?.cancel()
        journalEditTask = nil
        supersededRemoval?.cancel()
        supersededRemoval = nil
        syncTiming.afterWriting?.cancel()
        windowUndoManager?.removeAllActions()
        // The connection first: its Last Synced time is forgotten with it.
        connection = nil
        agentDeclines.cancelAll()
        store = nil
        configureSync()
        configuration = nil
        masterKey = nil
        recoveryKey = nil
        draftWrite = nil
        draft = nil
        draftBase = nil
        selectedID = nil
        selectedJournalID = nil
        items = []
        adoptConflicts([], held: [])
        keptNotes = []
        localResolution?.cancel()
        localResolution = nil
        library = .empty
        librarySync = LibrarySyncState()
        pendingSync = false
        refreshedChanges = nil
        query = ""
        showingTrash = false
        showingTemplates = false
        showingUnavailable = false
        showingAllEntries = false
        revealsSelection = false
        editingJournals = false
        openingJournals = false
        error = nil
        // The problem screen doesn't follow the welcome screen (docs/design/build-18-fixes-2026-10-06.md §2.1).
        setLibraryProblem(nil)
        failedRetries = 0
        firstReadPending = false
        saveFailure = false
        syncActivity.pendingItems = 0
        encryption.reset()
        retryGrant = nil
        agreedMergeHost = nil
        mergeSending = false
        joinPhase = nil
        passwordResetAuthorizedAt = nil
        savesBeforeLocking = [:]
        unsavedImageDescriptions = nil
        imageLoader.clear()
        lists.clear()
        locked = false
        vaultReplacement = false
        reviewRequests.reset()
    }
}

extension AppModel {
    // Complete reconciliation before a lock/quit flush can save the retained draft.
    /// With `settle`, the library is read again only once a list's removal animation has finished
    /// (`waitForListRemovals`): the update would otherwise land in the middle of it.
    func commitMutation<Outcome: Sendable>(
        settle: Duration = .zero,
        _ operation: @escaping @Sendable () async throws -> Outcome,
        reconcile: @escaping @MainActor (Outcome) -> Void
    ) async throws -> Bool {
        guard !locked, !replacingVault else { throw JournalError.locked }
        // The same library stays open: images, pending focus and other session work continue.
        committingMutation = true
        let task = Task {
            try Task.checkCancellation()
            let outcome = try await operation()
            pendingSync = true
            reconcile(outcome)
        }
        mutationTask = task
        do {
            defer {
                mutationTask = nil
                committingMutation = false
            }
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        }
        await waitForListRemovals(settle)
        do {
            try await refresh()
            return true
        } catch { return false }
    }
}
