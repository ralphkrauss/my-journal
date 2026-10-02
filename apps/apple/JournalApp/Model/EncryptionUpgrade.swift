import Combine
import Foundation
import JournalCore

#if os(iOS)
    import UIKit
#endif

/// Turn On Encryption (docs/design/enable-encryption.md): what the sheet shows and does. The work belongs to the app,
/// not to the sheet, so closing the sheet's window doesn't stop it, and showing the sheet again shows where it is.
@MainActor
final class EncryptionUpgrade: ObservableObject {
    enum Step: Hashable { case password, done }
    enum Field: Hashable { case current, password, verify }
    static let turnedOnElsewhereMessage = "Encryption was turned on from another device. Sign in to keep syncing."

    private weak var model: AppModel?
    @Published var path: [Step] = []
    @Published var currentPassword = "" { didSet { if currentPassword != oldValue { fieldErrors[.current] = nil } } }
    @Published var password = "" { didSet { if password != oldValue { clearPasswordErrors() } } }
    @Published var verify = "" { didSet { if verify != oldValue { clearPasswordErrors() } } }
    @Published private(set) var phase: EncryptionPhase?
    /// A failure that isn't about one field, and the step it belongs to (nil is the first step).
    @Published private(set) var error: String?
    @Published private(set) var errorStep: Step?
    /// The failure says encryption was turned on from another device; the primary button signs in.
    @Published private(set) var errorOffersSignIn = false
    @Published private(set) var fieldErrors: [Field: String] = [:]
    @Published var focusRequest: Field?
    /// The server switched, but this device couldn't finish; only Try Again is offered.
    @Published private(set) var unfinished = false
    /// The sheet, shown from Settings > Privacy.
    @Published var presented = false
    /// The sheet over the app, on iPhone and iPad, when finishing after a relaunch failed.
    @Published var presentedOverApp = false
    /// Sign In, from a sync message: Connect to a Server for this server.
    @Published var signInRequested = false
    /// This device's server was encrypted from another device; it has to sign in to keep syncing.
    @Published var turnedOnElsewhere = false
    /// How far a device signing in again has encrypted its own journals.
    @Published var rejoinProgress: Double?
    private var operation: Task<Void, Never>?
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

    var busy: Bool { phase != nil }
    /// Cancel stops the work, until the server is being changed.
    var canCancel: Bool { phase != .updatingServer && !unfinished }
    var synced: Bool { model?.connection != nil }
    /// The server this Mac runs itself, which the intro doesn't name separately.
    var ownServer: Bool {
        #if os(macOS)
            model?.localServer.isConfigured == true
        #else
            false
        #endif
    }
    var host: String {
        if ownServer { return "the server on this Mac" }
        return model?.connection.map { ServerAddress.host($0.address) } ?? ""
    }
    private var capitalizedHost: String { host.prefix(1).uppercased() + host.dropFirst() }
    var needsCurrentPassword: Bool { model?.configuration?.recovery.formatVersion == 3 }
    /// Sign In is offered while this device's journals aren't encrypted and its server's are.
    var offersSignIn: Bool {
        turnedOnElsewhere && model?.configuration?.encrypted == false && model?.connection != nil
    }
    /// Writing is paused in the journal window while this is under way.
    var pausesWriting: Bool {
        if unfinished { return true }
        switch phase {
        case .encrypting, .updatingServer: return true
        default: return false
        }
    }
    func errorMessage(on step: Step?) -> String? { errorStep == step ? error : nil }

    // MARK: Actions

    /// Shows the sheet on its first step, or where the work is when it's under way or waits for Try Again.
    func present() {
        if !busy && !unfinished { reset() }
        presented = true
    }
    private func reset() {
        path = []
        error = nil
        errorStep = nil
        errorOffersSignIn = false
        fieldErrors = [:]
        currentPassword = ""
        password = ""
        verify = ""
    }
    func continueFromAbout() {
        guard let model, !busy else { return }
        error = nil
        errorOffersSignIn = false
        run(.checking) {
            try await model.checkEncryptionReadiness()
            self.path = [.password]
            self.focusRequest = self.needsCurrentPassword ? .current : .password
        }
    }
    func turnOn() {
        guard let model, !busy else { return }
        if unfinished { return finish() }
        guard password == verify else { return fail(.verify, "The passwords don’t match.") }
        error = nil
        let password = password
        let current = needsCurrentPassword ? currentPassword : nil
        announceForAccessibility("Turning on encryption")
        run(synced ? .syncing : .encrypting(0)) {
            try await model.turnOnEncryption(password: password, current: current) { [weak self] phase in
                self?.update(phase)
            }
            self.completed()
        }
    }
    /// Try Again after the server switched but this device couldn't finish.
    func finish() {
        guard let model, !busy else { return }
        error = nil
        run(.updatingServer) {
            try await model.finishInterruptedEncryption()
            self.unfinished = false
            self.completed()
        }
    }
    /// At launch: finishes a switch the server made while the app last ran, and shows what's wrong if it can't.
    func finishAfterLaunch() {
        guard model?.encryptionUnfinished == true, !busy else { return }
        path = [.password]
        finish()
    }
    func cancel() {
        if canCancel {
            operation?.cancel()
            presented = false
            presentedOverApp = false
        }
    }
    /// Encryption was turned on from another device: the sheet closes, and Settings signs in instead.
    func signIn() {
        pendingSignIn = true
        presented = false
    }
    /// Whether the sheet closed to sign in; asked once.
    func takeSignInRequest() -> Bool {
        defer { pendingSignIn = false }
        return pendingSignIn
    }
    func done() {
        presented = false
        presentedOverApp = false
        reset()
    }
    /// Shows where the work is, from the Mac's journal window or after a relaunch.
    func showProgress() {
        #if os(macOS)
            model?.settingsTab = .privacy
            model?.settingsPresented = true
            presented = true
        #else
            presentedOverApp = true
        #endif
    }

    // MARK: Running

    private func run(_ initial: EncryptionPhase, _ work: @escaping @MainActor () async throws -> Void) {
        phase = initial
        backgroundExpired = false
        let background = beginBackgroundTime()
        operation = Task {
            defer {
                phase = nil
                endBackgroundTime(background)
            }
            do { try await work() } catch is CancellationError {
                if backgroundExpired {
                    report(
                        "Encryption stopped because My Journal was in the background. Keep My Journal open and try again."
                    )
                }
            } catch { explain(error) }
        }
    }
    private func update(_ next: EncryptionPhase) {
        if next == .updatingServer && phase != .updatingServer {
            announceForAccessibility("Updating \(host). You can’t stop this now.")
        }
        phase = next
    }
    private func completed() {
        currentPassword = ""
        password = ""
        verify = ""
        if path.last != .done { path.append(.done) }
        announceForAccessibility("Your journals are encrypted.")
    }
    private func stopForLock() {
        guard canCancel else { return }
        operation?.cancel()
        presented = false
        presentedOverApp = false
    }

    #if os(iOS)
        private func beginBackgroundTime() -> UIBackgroundTaskIdentifier {
            UIApplication.shared.beginBackgroundTask(withName: "Turn on encryption") { [weak self] in
                Task { @MainActor in self?.backgroundTimeExpired() }
            }
        }
        private func endBackgroundTime(_ identifier: UIBackgroundTaskIdentifier) {
            if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier) }
        }
        private func backgroundTimeExpired() {
            guard canCancel, busy else { return }
            backgroundExpired = true
            operation?.cancel()
        }
    #else
        private func beginBackgroundTime() -> Int { 0 }
        private func endBackgroundTime(_: Int) {}
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
    private func explain(_ failure: Error) {
        let onFirstStep = path.isEmpty
        errorOffersSignIn = false
        let message: String
        switch failure as? EncryptionFailure {
        case .incorrectPassword: return fail(.current, "That password isn’t correct.")
        case .rateLimited:
            return fail(.current, "Too many password attempts on this server. Try again in a few minutes.")
        case .unreachable:
            message =
                onFirstStep
                ? "Couldn’t reach \(host). Check your connection and try again."
                : "Couldn’t reach \(host). Encryption wasn’t turned on. Check your connection and try again."
        case .serverOutdated: message = "\(capitalizedHost) needs an update before you can turn on encryption."
        case .notEnoughSpace(let bytes):
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            message = "There isn’t enough space to encrypt your journals. Free up \(size) and try again."
        case .accessLost:
            message =
                "This device no longer has access to \(host). Connect again in Settings > Devices, then try again."
        case .turnedOnElsewhere:
            turnedOnElsewhere = true
            errorOffersSignIn = true
            message = Self.turnedOnElsewhereMessage
        case .stillSyncing, .serverChanged:
            message = "Your other devices are still syncing. Wait for them to finish, then try again."
        case .imagesMissing:
            message =
                "Some images haven’t downloaded to this device yet. Keep My Journal open for a moment, then try again."
        case .unfinished:
            unfinished = true
            if path.isEmpty { path = [.password] }
            message =
                "Your journals are encrypted on \(host), but this device couldn’t finish. Free up space, then try again."
            #if os(iOS)
                if !presented { presentedOverApp = true }
            #else
                if !presented { showProgress() }
            #endif
        case .failed, nil: message = "Encryption wasn’t turned on. Your journals are unchanged."
        }
        report(message)
    }
    private func report(_ message: String) {
        error = message
        errorStep = path.last
        announceForAccessibility(message)
    }
}
