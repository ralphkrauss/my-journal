import Combine
import Foundation
import JournalCore

#if os(iOS)
    import UIKit
#endif

/// Encrypt Your Journals (docs/design/1-1-encryption-and-passwords.md §3.4): what the form shows and does, and where
/// a run that left it is. The work belongs to the app, not to a view, so closing a window doesn't stop it, and every
/// window shows the same state.
///
/// A library that isn't encrypted (made by an earlier version) is asked once per launch. The form is the root screen
/// until the person encrypts or chooses Not Now, which is offered only where the form can't succeed or has failed.
/// After Encrypt, the journals appear read-only with a notice that shows the progress (`EncryptionNotice`).
@MainActor
final class EncryptionUpgrade: ObservableObject {
    enum Field: Hashable { case current, password, verify }
    /// A: no server. B: a server that doesn't use encryption yet. C: it already does. D: it can't be used now.
    enum Variant: Equatable { case local, synced, signIn, unavailable }
    static let turnedOnElsewhereMessage = "Encryption was turned on from another device. Reconnect to keep syncing."
    /// How long after the check started Not Now appears, however the check ends.
    static let earlyExitSeconds: TimeInterval = 3

    private weak var model: AppModel?

    // MARK: The form

    @Published var currentPassword = "" { didSet { if currentPassword != oldValue { fieldErrors[.current] = nil } } }
    @Published var password = "" { didSet { if password != oldValue { clearPasswordErrors() } } }
    @Published var verify = "" { didSet { if verify != oldValue { clearPasswordErrors() } } }
    @Published private(set) var fieldErrors: [Field: String] = [:]
    @Published var focusRequest: Field?
    @Published private(set) var variant = Variant.local
    /// Checking the server (variants B to D).
    @Published private(set) var checking = false
    /// The check was started for the form now showing, so a library with a server doesn't flash fields before it.
    @Published private(set) var checkStarted = false
    /// Making the key, saving the open entry and checking the space, before the journals pause.
    @Published private(set) var preparing = false
    /// What went wrong on the form, and which failure it was.
    @Published private(set) var formError: String?
    @Published private(set) var formFailure: EncryptionFailure?
    /// The check hasn't finished, or it has failed, for about three seconds: Not Now is offered.
    @Published private(set) var earlyExit = false
    /// A run in this launch failed (or hit its background time limit), so the form can't promise to succeed.
    @Published private(set) var failedThisLaunch = false
    /// Not Now was chosen in this launch. Held in memory only: a cold start asks again.
    @Published private(set) var notNowChosen = false {
        didSet { if notNowChosen != oldValue { routingChanged() } }
    }
    /// The form as a sheet over the journals with Cancel, from Settings ▸ Privacy.
    @Published var formPresented = false {
        didSet { if formPresented != oldValue { routingChanged() } }
    }

    // MARK: The run, shown in the journals' notice

    @Published private(set) var phase: EncryptionPhase? {
        didSet { if (phase == nil) != (oldValue == nil) { routingChanged() } }
    }
    /// A failure after the journals paused: the notice offers what the failure allows.
    @Published private(set) var noticeError: String? {
        didSet { if (noticeError == nil) != (oldValue == nil) { routingChanged() } }
    }
    @Published private(set) var noticeFailure: EncryptionFailure?
    /// The server switched, but this device couldn't finish; the journals stay read-only.
    @Published private(set) var unfinished = false {
        didSet { if unfinished != oldValue { routingChanged() } }
    }
    /// Your Journals Are Encrypted, over the journals.
    @Published var donePresented = false
    /// A person-chosen Stop Syncing is waiting for its confirmation.
    @Published var confirmingStopSyncing = false

    // MARK: Signing in again

    /// Reconnect, from a sync message: Reconnect for this server.
    @Published var signInRequested = false
    /// This device's server was encrypted from another device; it has to sign in to keep syncing.
    @Published var turnedOnElsewhere = false
    /// How far a device signing in again has encrypted its own journals.
    @Published var rejoinProgress: Double?

    private var operation: Task<Void, Never>?
    private var checkTask: Task<Void, Never>?
    private var earlyExitTask: Task<Void, Never>?
    private var lockObservation: AnyCancellable?
    private var backgroundExpired = false
    private var pendingSignIn = false

    init(model: AppModel) {
        self.model = model
        lockObservation = model.$locked.sink { [weak self] locked in
            if locked { self?.stopForLock() }
        }
    }

    // MARK: State

    var busy: Bool { phase != nil || preparing }
    /// Cancel stops the work, until the server is being changed.
    var canCancel: Bool { busy && phase != .updatingServer }
    var synced: Bool { model?.connection != nil }
    var host: String { model?.connection.map { ServerAddress.host($0.address) } ?? "" }
    private var capitalizedHost: String { host.prefix(1).uppercased() + host.dropFirst() }
    /// A library from before libraries without encryption has an access password that only a server checks.
    var needsCurrentPassword: Bool { model?.configuration?.recovery.formatVersion == 3 && synced }
    /// Reconnect is offered while this device's journals aren't encrypted and its server's are.
    var offersSignIn: Bool {
        turnedOnElsewhere && model?.configuration?.encrypted == false && model?.connection != nil
    }
    /// Writing is paused in the journals while this is under way.
    var pausesWriting: Bool { phase != nil || unfinished }
    /// A run, a failure of one, or an unfinished switch is shown in the journals (the window shows them, read-only
    /// or not, with the notice) instead of the form.
    var inProgress: Bool { phase != nil || noticeError != nil || unfinished || model?.encryptionUnfinished == true }
    /// The journals haven't been asked about encryption yet in this launch.
    var holdsSynchronization: Bool { model?.configuration?.encrypted == false && !notNowChosen }
    /// The notice is shown above the journals.
    var showsNotice: Bool { phase != nil || noticeError != nil || unfinished }
    /// Whether the form is the window's root screen: a library that isn't encrypted, not yet decided for this launch.
    var wantsForm: Bool {
        model?.configuration?.encrypted == false && model?.store != nil && !notNowChosen && !inProgress
    }

    /// Not Now on the form: only where encryption can't succeed (the check didn't finish or failed, the server uses
    /// encryption already or can't be used) or has failed. The person's own Cancel never counts.
    var offersNotNow: Bool {
        switch variant {
        case .signIn, .unavailable: return true
        case .local, .synced: return failedThisLaunch || (checking && earlyExit)
        }
    }
    /// Stop Syncing on the form: only for states that won't pass by themselves.
    var offersStopSyncing: Bool { synced && Self.permitsStopSyncing(formFailure) }
    static func permitsStopSyncing(_ failure: EncryptionFailure?) -> Bool {
        switch failure {
        case .serverOutdated?, .accessLost?, .incorrectPassword?, .rateLimited?: return true
        default: return false
        }
    }
    /// The notice's buttons for the failure it shows.
    var noticeOffersTryAgain: Bool {
        if unfinished { return true }
        switch noticeFailure {
        case .serverOutdated?, .accessLost?, .incorrectPassword?, .rateLimited?: return false
        default: return true
        }
    }
    var noticeOffersNotNow: Bool { !unfinished }
    var noticeOffersStopSyncing: Bool { unfinished || (synced && Self.permitsStopSyncing(noticeFailure)) }

    // MARK: The form's check

    /// The form appeared: a library with a server asks it what it can do.
    func formAppeared() {
        guard !busy, !inProgress else { return }
        startCheck()
    }
    /// The form went away (Not Now, Encrypt, Cancel on the sheet): a late answer is dropped.
    func formDisappeared() {
        checkTask?.cancel()
        earlyExitTask?.cancel()
        checking = false
        checkStarted = false
    }
    /// The form shows "Checking {host}…" instead of fields.
    var showsChecking: Bool { checking || (synced && !checkStarted) }
    func startCheck() {
        guard let model, model.configuration?.encrypted == false else { return }
        checkTask?.cancel()
        earlyExitTask?.cancel()
        formError = nil
        formFailure = nil
        earlyExit = false
        checkStarted = true
        guard model.connection != nil else {
            checking = false
            variant = .local
            return
        }
        checking = true
        earlyExitTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.earlyExitSeconds * 1_000_000_000))
            if !Task.isCancelled { earlyExit = true }
        }
        checkTask = Task {
            let found = await model.checkEncryptionReadiness()
            guard !Task.isCancelled else { return }
            applyCheck(found)
        }
    }
    private func applyCheck(_ found: EncryptionCheck) {
        checking = false
        earlyExitTask?.cancel()
        switch found {
        case .local:
            variant = .local
        case .synced:
            variant = .synced
            announceForAccessibility(Self.syncedMessage(host: host))
        case .signIn:
            variant = .signIn
            turnedOnElsewhere = true
            announceForAccessibility(Self.signInMessage(host: host))
        case .failed(let failure):
            variant = .unavailable
            showOnForm(failure)
        }
    }
    /// Waits for the check, for tests.
    func finishedChecking() async { await checkTask?.value }

    // MARK: Actions

    /// Settings ▸ Privacy ▸ Turn On Encryption…: the form as a sheet with Cancel.
    func present() {
        guard !busy else { return }
        formPresented = true
    }
    /// Cancel on the sheet.
    func dismissSheet() {
        guard !busy else { return }
        formDisappeared()
        formPresented = false
    }
    /// Encrypt.
    func encrypt() {
        guard let model, !busy, !unfinished else { return }
        guard password == verify else { return fail(.verify, "The passwords don’t match.") }
        formError = nil
        formFailure = nil
        noticeError = nil
        noticeFailure = nil
        let password = password
        let current = needsCurrentPassword ? currentPassword : nil
        preparing = true
        announceForAccessibility("Encrypting your journals")
        run {
            let plan = try await model.prepareEncryption(password: password, current: current)
            try Task.checkCancellation()
            self.began()
            try await model.runEncryption(plan) { [weak self] phase in self?.update(phase) }
            self.completed()
        }
    }
    /// Try Again after the server switched but this device couldn't finish.
    func finish() {
        guard let model, !busy else { return }
        noticeError = nil
        let wasUnfinished = unfinished
        run {
            self.phase = .updatingServer
            try await model.finishInterruptedEncryption()
            self.unfinished = false
            // Finishing at launch is quiet; the person who saw the notice is told it worked.
            if wasUnfinished { self.completed() } else { self.finishedQuietly() }
        }
    }
    /// At launch: finishes a switch the server made while the app last ran; if it can't, the notice says so.
    func finishAfterLaunch() {
        guard model?.encryptionUnfinished == true, !busy else { return }
        finish()
    }
    /// Try Again on the notice or the form: the unfinished switch is finished; a failed run runs again with the
    /// password still held; a failed check checks again.
    func tryAgain() {
        if unfinished { return finish() }
        if noticeError != nil {
            noticeError = nil
            noticeFailure = nil
            return encrypt()
        }
        if variant == .unavailable { return startCheck() }
        if formFailure != nil { return encrypt() }
        startCheck()
    }
    /// Cancel on the working notice. The plain form returns; Not Now is not unlocked by it.
    func cancel() {
        guard canCancel else { return }
        operation?.cancel()
    }
    /// Not Now: the journals open as in earlier versions, and the form asks again at the next launch.
    func notNow() {
        guard !busy else { return }
        formDisappeared()
        noticeError = nil
        noticeFailure = nil
        formError = nil
        formFailure = nil
        clearPasswords()
        notNowChosen = true
        formPresented = false
        model?.syncWhenWritingPauses()
    }
    /// Reconnect (variant C): Connect to a Server opens over the form with this server. From the sheet, the sheet
    /// closes first and Settings opens it.
    func signIn() {
        if formPresented {
            pendingSignIn = true
            formPresented = false
        } else {
            signInRequested = true
        }
    }
    /// Whether the sheet closed to sign in; asked once.
    func takeSignInRequest() -> Bool {
        defer { pendingSignIn = false }
        return pendingSignIn
    }
    /// The confirmation of Stop Syncing… on the form or the unfinished notice was accepted.
    func stopSyncing() {
        guard let model, !busy else { return }
        confirmingStopSyncing = false
        if unfinished {
            run {
                self.phase = .updatingServer
                let outcome = try await model.stopSyncingAfterUnfinishedEncryption()
                self.unfinished = false
                if outcome == .adopted { self.completed() }
            }
            return
        }
        model.stopSyncing()
        failedThisLaunch = false
        variant = .local
        formError = nil
        formFailure = nil
        earlyExit = false
    }
    func dismissDone() {
        donePresented = false
    }
    /// A new library or an erased one starts with nothing decided.
    func reset() {
        operation?.cancel()
        formDisappeared()
        preparing = false
        phase = nil
        noticeError = nil
        noticeFailure = nil
        formError = nil
        formFailure = nil
        unfinished = false
        failedThisLaunch = false
        notNowChosen = false
        formPresented = false
        donePresented = false
        earlyExit = false
        variant = .local
        turnedOnElsewhere = false
        clearPasswords()
    }

    /// Waits for the work running now, for tests.
    func finishedWorking() async { await operation?.value }

    // MARK: Running

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        backgroundExpired = false
        let background = beginBackgroundTime()
        keepAwake(true)
        operation = Task {
            defer {
                phase = nil
                preparing = false
                endBackgroundTime(background)
                keepAwake(false)
            }
            do { try await work() } catch EncryptionFailure.unfinished {
                // Even when cancelled: the server may have switched, and the journals stay paused until it is known.
                explain(EncryptionFailure.unfinished)
            } catch {
                if error is CancellationError || Task.isCancelled {
                    if backgroundExpired {
                        explain(.background)
                    } else {
                        // The person's Cancel, or locking: the plain form returns, with Not Now still not offered.
                        noticeError = nil
                        noticeFailure = nil
                    }
                } else {
                    explain(error)
                }
            }
        }
    }
    /// The journals pause and appear read-only with the notice.
    private func began() {
        preparing = false
        phase = synced ? .syncing : .encrypting(0)
        formPresented = false
        showJournals()
    }
    private func update(_ next: EncryptionPhase) {
        if next == .updatingServer && phase != .updatingServer {
            announceForAccessibility("Updating \(host). You can’t stop this now.")
        }
        phase = next
    }
    private func completed() {
        clearPasswords()
        formError = nil
        formFailure = nil
        failedThisLaunch = false
        donePresented = true
        formPresented = false
        announceForAccessibility("Your journals are encrypted.")
    }
    private func finishedQuietly() {
        clearPasswords()
        failedThisLaunch = false
    }
    private func clearPasswords() {
        currentPassword = ""
        password = ""
        verify = ""
        fieldErrors = [:]
    }
    private func stopForLock() {
        // The form as a sheet closes with Settings.
        if !busy { formPresented = false }
        guard canCancel else { return }
        operation?.cancel()
    }
    private func routingChanged() { model?.objectWillChange.send() }

    /// Shows the journals the encryption is working on: Settings (a sheet on iPhone and iPad) steps aside, and the
    /// Mac's journal window comes forward.
    private func showJournals() {
        #if os(macOS)
            model?.journalWindow?.makeKeyAndOrderFront(nil)
        #else
            model?.settingsPresented = false
        #endif
    }

    #if os(iOS)
        private func beginBackgroundTime() -> UIBackgroundTaskIdentifier {
            UIApplication.shared.beginBackgroundTask(withName: "Encrypt journals") { [weak self] in
                Task { @MainActor in self?.backgroundTimeExpired() }
            }
        }
        private func endBackgroundTime(_ identifier: UIBackgroundTaskIdentifier) {
            if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier) }
        }
        private func backgroundTimeExpired() {
            guard canCancel else { return }
            backgroundExpired = true
            operation?.cancel()
        }
        /// Auto-Lock would send the app to the background in the middle of the copy.
        private func keepAwake(_ awake: Bool) { UIApplication.shared.isIdleTimerDisabled = awake }
    #else
        private func beginBackgroundTime() -> Int { 0 }
        private func endBackgroundTime(_: Int) {}
        private func keepAwake(_: Bool) {}
    #endif

    // MARK: Messages

    private func fail(_ field: Field, _ message: String) {
        fieldErrors[field] = message
        focusRequest = field
        Task {
            // After focus moves, so VoiceOver doesn't cut the announcement off.
            try? await Task.sleep(nanoseconds: 300_000_000)
            announceForAccessibility(message)
        }
    }
    private func clearPasswordErrors() {
        fieldErrors[.password] = nil
        fieldErrors[.verify] = nil
    }

    /// The failure `explain` was given, for the background limit that isn't an `EncryptionFailure`.
    private enum Stop { case background }
    private func explain(_ stop: Stop) {
        failedThisLaunch = true
        noticeFailure = nil
        noticeError = "Encryption stopped because My Journal was in the background. Keep My Journal open and try again."
        announce(noticeError)
    }

    /// A failure of the run. Before the journals paused it belongs to the form (a field, or an error above the
    /// button); after, to the notice.
    private func explain(_ failure: Error) {
        let kind = failure as? EncryptionFailure ?? .failed
        let afterPause = phase != nil
        if kind != .unfinished && kind != .turnedOnElsewhere { failedThisLaunch = true }
        switch kind {
        case .incorrectPassword where !afterPause:
            return fail(.current, "That password isn’t correct.")
        case .rateLimited where !afterPause:
            return fail(.current, "Too many password attempts on this server. Try again in a few minutes.")
        case .turnedOnElsewhere:
            // The purge or the pre-sync found the server already encrypted: the form becomes the sign-in variant.
            variant = .signIn
            turnedOnElsewhere = true
            noticeError = nil
            noticeFailure = nil
            announceForAccessibility(Self.signInMessage(host: host))
        case .unfinished:
            unfinished = true
            noticeFailure = .unfinished
            noticeError = nil
            announce(Self.unfinishedMessage(host: host))
        default:
            if afterPause {
                noticeFailure = kind
                noticeError = message(for: kind)
                announce(noticeError)
            } else {
                showOnForm(kind)
            }
        }
    }
    private func showOnForm(_ failure: EncryptionFailure) {
        formFailure = failure
        formError = message(for: failure)
        announce(formError)
    }
    private func announce(_ message: String?) {
        if let message { announceForAccessibility(message) }
    }
    /// The form's paragraphs: no server (A), a server that doesn't use encryption yet (B and D), and one that does (C).
    static let localMessage =
        "My Journal now encrypts every journal. Choose a master password to encrypt the journals on this device. Only your devices can read them."
    static func syncedMessage(host: String) -> String {
        "My Journal now encrypts every journal. Choose a master password to encrypt the journals on this device and on \(host). Only your devices can read them."
    }
    static func signInMessage(host: String) -> String {
        let name = host.prefix(1).uppercased() + host.dropFirst()
        return
            "\(name) now uses encryption. Sign in with your master password to encrypt the journals on this device. Changes that haven’t synced are kept."
    }
    static func unfinishedMessage(host: String) -> String {
        "Your journals are encrypted on \(host), but this device couldn’t finish. Free up space, then try again."
    }
    func message(for failure: EncryptionFailure) -> String {
        switch failure {
        case .incorrectPassword: return "That password isn’t correct."
        case .rateLimited: return "Too many password attempts on this server. Try again in a few minutes."
        case .unreachable: return "Couldn’t reach \(host). Check your connection and try again."
        case .serverOutdated:
            return
                "\(capitalizedHost) needs an update before it can store encrypted journals. Updating it is the way to keep syncing."
        case .notEnoughSpace(let bytes):
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            return "There isn’t enough space to encrypt your journals. Free up \(size) and try again."
        case .accessLost:
            return
                "This device no longer has access to \(host). You can stop syncing to encrypt your journals on this device."
        case .turnedOnElsewhere: return Self.turnedOnElsewhereMessage
        case .stillSyncing, .serverChanged:
            return "Your other devices are still syncing. Wait for them to finish, then try again."
        case .imagesMissing:
            return
                "Some images haven’t downloaded to this device yet. Keep My Journal open for a moment, then try again."
        case .unfinished: return Self.unfinishedMessage(host: host)
        case .failed: return "Your journals couldn’t be encrypted. They are unchanged."
        }
    }
}
