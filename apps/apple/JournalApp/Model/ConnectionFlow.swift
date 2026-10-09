import CryptoKit
import JournalCore
import SwiftUI

/// What Connect to a Server knows and does (docs/design/connection-onboarding.md). Each step is a screen on a
/// navigation stack; work and its failures stay on the step where the person started it, and the next step appears
/// only once it succeeds.
@MainActor
final class ConnectionFlow: ObservableObject {
    enum Step: Hashable {
        case setUpServer, choosePassword, enterPassword, serverReady, signIn, addThisDevice, recoveryCode
        /// Merge Journals and, after a scanned code, Finish on Your Other Device
        /// (docs/design/join-with-local-journals.md).
        case merge, finish
    }
    enum Field: Hashable { case setupCode, newPassword, verifyPassword, phrase }

    let model: AppModel
    init(model: AppModel) { self.model = model }

    @Published var path: [Step] = [] { didSet { pathChanged(from: oldValue) } }
    @Published var address = ""
    @Published var chosenServer: String?
    @Published private(set) var status: ServerStatus?
    /// What the server published about its recovery envelope, which decided what this flow asks for; connecting
    /// requires the same.
    @Published private(set) var envelope: RecoveryParameters?
    @Published private(set) var passwordless = false
    @Published var setupCode = "" { didSet { if setupCode != oldValue { fieldErrors[.setupCode] = nil } } }
    /// A master password chosen for a journal created while setting up the server. Kept while the sheet is open, so
    /// Try Again never asks for it twice.
    @Published var newPassword = "" { didSet { if newPassword != oldValue { clearPasswordErrors() } } }
    @Published var verifyPassword = "" { didSet { if verifyPassword != oldValue { clearPasswordErrors() } } }
    @Published var phrase = "" {
        didSet {
            if phrase != oldValue {
                fieldErrors[.phrase] = nil
                codeUsedNotice = nil
            }
        }
    }
    /// Shown above the recovery code field after Back from Merge Journals spent the code it was entered with, until
    /// a new one is typed (docs/design/build-18-fixes-2026-10-06.md §3.2).
    @Published private(set) var codeUsedNotice: String?
    /// The journal this flow created before setting up the server. Its encryption and password can't change now.
    @Published private(set) var createdJournalHere = false
    @Published private(set) var fieldErrors: [Field: String] = [:]
    /// A field that should take focus, for example because its error just appeared.
    @Published var focusRequest: Field?
    @Published private(set) var busy = false
    @Published private(set) var installing = false
    /// What the busy row says.
    @Published private(set) var activity = ""
    /// A failure that isn't about one field, shown on the step where it happened.
    @Published var error: String? { didSet { errorStep = path.last } }
    @Published private(set) var errorStep: Step?
    /// Everything is done and the sheet should close.
    @Published private(set) var finished = false
    /// The server was set up or joined; nothing is undone when the sheet closes.
    private(set) var completed = false

    // Pairing
    @Published private(set) var ticket: PairingTicket?
    @Published private(set) var received: PairingContents?
    /// The check code shown here and the approving key it came from; the grant must come from the same key.
    @Published private(set) var reveal: PairingReveal?
    /// The person chose Connect after comparing the check codes. Nothing from the other device is used before.
    @Published private(set) var confirmed = false
    /// A code scanned from a connected device. It names the server and the connected device's key, so no check code
    /// is compared; a scanned code never falls back to the typed code.
    @Published private(set) var invite: PairingInvite?
    /// A scanned code can be tried again when only the connection failed; otherwise a new code is needed.
    @Published private(set) var canRetryScannedCode = false
    /// The server the person agreed to merge this device's journals with in this sheet, so a new code for it doesn't
    /// ask again.
    @Published private(set) var agreedHost: String?
    /// Merging stopped part way, so the step's button tries again.
    @Published private(set) var mergeInterrupted = false
    /// Scan Again was chosen on a pushed step; the first screen opens the scanner.
    @Published var scanRequested = false
    /// Joining stopped before sending anything because the server holds another library; Merge continues it
    /// (docs/design/sync-health-and-recovery.md §3.2).
    private var resumeAfterMerge: (() -> Void)?
    private var pairingKey: Curve25519.KeyAgreement.PrivateKey?
    private var receivedDeviceID: UUID?
    private var operation: Task<Void, Never>?
    /// The withdrawal of a pairing request, which a new request waits for so the other device can't answer the old
    /// one's grant.
    private var withdrawal: Task<Void, Never>?
    /// The next code shown replaces one that was withdrawn, so VoiceOver says it is new.
    private var announcesNewCode = false

    var host: String { ServerAddress.host(address) }
    /// What the busy row says, including what merging is doing.
    var activityLabel: String { model.joinPhase?.label ?? activity }
    /// The Merge Journals step comes first: this device has journals to merge and the person hasn't agreed yet.
    private var asksToMerge: Bool { model.joinsByMerging && agreedHost != host }

    // MARK: Choosing a server

    func check() {
        busy = true
        error = nil
        operation = Task {
            defer { busy = false }
            do {
                let client = try ServerClient(address: address)
                let server = try await client.statusOnFirstContact()
                var shown: RecoveryParameters?
                if server.initialized {
                    let current = try await client.recoveryParameters()
                    // Say at once when this server can't take this device's journals, before any pairing.
                    try model.checkServerEnvelope(current, shown: nil)
                    shown = current
                }
                try Task.checkCancellation()
                guard server.protocolVersion == 1 else {
                    throw JournalError.server("Update My Journal to connect to this server.")
                }
                envelope = shown
                passwordless = shown.map { !$0.requiresPassword } ?? false
                status = server
                if !server.initialized {
                    path = [.setUpServer]
                    focusRequest = .setupCode
                } else if asksToMerge {
                    path = [.merge]
                } else if passwordless {
                    path = [.addThisDevice]
                } else {
                    path = [.signIn]
                    focusRequest = .phrase
                }
            } catch is CancellationError {} catch { show(error) }
        }
    }

    // MARK: Setting up a new server

    /// The step after the setup code, or nil when Set Up follows directly.
    var stepAfterSetupCode: Step? {
        if createdJournalHere { return nil }
        if model.store == nil { return .choosePassword }
        return needsExistingPassword ? .enterPassword : nil
    }
    /// Setting up from a library protected by a password needs it: the server's recovery secret derives from it.
    var needsExistingPassword: Bool {
        model.store != nil && model.configuration?.requiresPassword != false && model.recoveryKey == nil
    }
    var existingCredentialName: String { model.configuration?.credentialName ?? "Master Password" }

    func continueFromSetupCode() {
        error = nil
        let checksCode = status?.supports(ServerClient.setupCheckFeature) == true
        switch CodeEntry.setupCodeProblem(setupCode) {
        case .length where !checksCode && CodeEntry.isOlderSetupCode(setupCode):
            // A server from before six-character codes still shows its eight-character one until it's updated.
            setupCode = CodeEntry.normalized(setupCode)
        case .length: return fail(.setupCode, "Enter the 6-character setup code from your server.")
        case .characters: return fail(.setupCode, "Setup codes use letters and the digits 2–9, without I or O.")
        case nil: setupCode = CodeEntry.setupCode(CodeEntry.normalized(setupCode), previous: "")
        }
        guard let next = stepAfterSetupCode else { return setUp() }
        guard checksCode else { return advance(to: next) }
        busy = true
        activity = "Checking…"
        operation = Task {
            defer { busy = false }
            do {
                try await ServerClient(address: address).checkSetupCode(setupCode)
                try Task.checkCancellation()
                advance(to: next)
            } catch is CancellationError {} catch { showSetupFailure(error) }
        }
    }
    private func advance(to step: Step) {
        path.append(step)
        switch step {
        case .choosePassword: focusRequest = .newPassword
        case .enterPassword: focusRequest = .phrase
        default: break
        }
    }
    func setUpWithNewPassword() {
        if !createdJournalHere && newPassword != verifyPassword {
            return fail(.verifyPassword, "The passwords don’t match.")
        }
        setUp()
    }
    /// Sets up a new server. Without a journal on this device, first creates one as chosen.
    func setUp() {
        busy = true
        installing = true
        activity = "Setting Up…"
        error = nil
        operation = Task {
            defer {
                busy = false
                installing = false
            }
            if model.store == nil {
                model.error = nil
                await model.start(password: newPassword)
                guard model.store != nil else {
                    error = model.error ?? "Couldn’t create your journal. Try again."
                    return
                }
                createdJournalHere = true
            }
            do {
                try await model.initializeServer(
                    address: address, code: setupCode, phrase: createdJournalHere ? newPassword : phrase,
                    uploadLocal: true)
                newPassword = ""
                verifyPassword = ""
                phrase = ""
                completed = true
                path.append(.serverReady)
            } catch JournalError.invalidRecoveryKey where !createdJournalHere {
                fail(.phrase, Self.incorrectMessage(existingCredentialName))
            } catch {
                showSetupFailure(error)
            }
        }
    }
    private func showSetupFailure(_ failure: Error) {
        switch failure {
        case JournalError.invalidSetupCode:
            returnToSetupCode("That setup code isn’t correct. Check the code on your server.")
        case is ServerRateLimited:
            returnToSetupCode("Too many incorrect codes. Try again in a few minutes.")
        case ServerConnectionError.serverChanged:
            path = []
            show(failure)
        default:
            show(failure)
            if createdJournalHere, let message = error {
                error = "Your journal is saved on this device, but the server couldn’t be set up. " + message
            }
            returnIfSetUpElsewhere()
        }
    }
    /// Someone else set the server up meanwhile: this device can only sign in now, which starts from the server.
    private func returnIfSetUpElsewhere() {
        let address = address
        Task {
            guard let server = try? await ServerClient(address: address).status(), server.initialized,
                address == self.address, !completed
            else { return }
            path = []
            status = nil
            error = "This server has just been set up. Choose it again to sign in."
        }
    }
    private func returnToSetupCode(_ message: String) {
        path = [.setUpServer]
        fail(.setupCode, message)
    }

    // MARK: Joining a server that's set up

    /// The name of what opens this server's library, as Settings names it.
    var credentialName: String {
        switch envelope?.formatVersion {
        case 1: return "Recovery Key"
        case 3: return "Access Password"
        default: return "Master Password"
        }
    }
    /// How an error names a typed credential: a recovery key or code by its name, any kind of password as a password.
    private static func typedName(_ credentialName: String) -> String {
        credentialName.hasPrefix("Recovery") ? credentialName.lowercased() : "password"
    }
    private static func incorrectMessage(_ credentialName: String) -> String {
        "That \(typedName(credentialName)) isn’t correct."
    }
    /// A device with nothing written receives the server's journals; one with journals agreed to merge them first.
    var downloadFooter: String? { model.nothingWritten ? "Your journals will download to this device." : nil }

    /// Merge Journals: the person agreed to merge with this server. Nothing was sent to it yet.
    func confirmMerge() {
        agreedHost = host
        model.agreedMergeHost = host
        error = nil
        if let resume = resumeAfterMerge {
            resumeAfterMerge = nil
            path.removeLast()
            resume()
            return
        }
        if let invite {
            path = [.finish]
            requestScannedPairing(invite)
        } else if passwordless {
            path.append(.addThisDevice)
        } else {
            path.append(.signIn)
            focusRequest = .phrase
        }
    }
    func signIn() {
        guard agreedToMerge() else { return }
        busy = true
        installing = true
        activity = "Signing In…"
        error = nil
        let recovering = path.last == .recoveryCode
        operation = Task {
            defer {
                busy = false
                installing = false
            }
            do {
                let empty = model.nothingWritten
                try await model.recoverServer(
                    address: address, phrase: phrase, uploadLocal: !empty, shown: envelope,
                    replacingEmptyLibrary: empty)
                completed = true
                finished = true
            } catch JournalError.invalidRecoveryKey where !recovering {
                fail(.phrase, Self.incorrectMessage(credentialName))
            } catch ServerConnectionError.invalidRecoveryCode {
                fail(.phrase, "That recovery code isn’t correct or has already been used.")
            } catch is ServerRateLimited where !recovering {
                fail(
                    .phrase,
                    "Too many \(Self.typedName(credentialName)) attempts on this server. Try again in a few minutes, or use a connected device."
                )
            } catch is MergeConsentNeeded {
                askToMerge { [weak self] in self?.signIn() }
            } catch {
                if error as? ServerConnectionError == .serverChanged { path = [] }
                show(error)
            }
        }
    }

    // MARK: Adding this device with a code

    func beginPairing() {
        abandon()
        busy = true
        activity = "Waiting for approval…"
        error = nil
        operation = Task {
            defer { busy = false }
            await withdrawal?.value
            withdrawal = nil
            do {
                let client = try ServerClient(address: address)
                guard try await client.status().supports(PairingCheck.feature) else {
                    throw PairingError.serverOutdated
                }
                let key = Curve25519.KeyAgreement.PrivateKey()
                let request = try await client.beginPairing(
                    deviceName: model.deviceName, publicKey: key.publicKey.rawRepresentation)
                if Task.isCancelled {
                    try? await client.cancelPairing(request)
                    return
                }
                ticket = request
                pairingKey = key
                if announcesNewCode {
                    announcesNewCode = false
                    announceForAccessibility("New code.")
                }
                try await awaitApproval(client, ticket: request, key: key)
            } catch is CancellationError {} catch { show(error) }
        }
    }
    /// Starts joining the server a scanned code names: it's checked first, and a device with journals asks to merge
    /// before anything is sent.
    func join(_ scanned: PairingInvite) {
        abandon()
        path = []
        invite = scanned
        address = scanned.server
        confirmed = true
        busy = true
        activity = "Checking…"
        error = nil
        operation = Task {
            defer { busy = false }
            do {
                let client = try ServerClient(address: scanned.server)
                let server = try await client.statusOnFirstContact()
                guard server.protocolVersion == 1 else {
                    throw JournalError.server("Update My Journal to connect to this server.")
                }
                guard server.initialized, server.supports(PairingInvite.feature) else {
                    throw JournalError.server("This server needs an update before you can add devices this way.")
                }
                let current = try await client.recoveryParameters()
                try model.checkServerEnvelope(current, shown: nil)
                envelope = current
                passwordless = !current.requiresPassword
                try Task.checkCancellation()
                if asksToMerge {
                    path = [.merge]
                } else {
                    path = [.finish]
                    try await pairScanned(scanned, client: client)
                }
            } catch is CancellationError {} catch { show(error) }
        }
    }
    /// Asks the connected device that showed the code to approve this one.
    private func requestScannedPairing(_ scanned: PairingInvite) {
        busy = true
        activity = "Waiting for approval…"
        error = nil
        operation = Task {
            defer { busy = false }
            do {
                try await pairScanned(scanned, client: ServerClient(address: scanned.server))
            } catch is CancellationError {} catch { show(error) }
        }
    }
    private func pairScanned(_ scanned: PairingInvite, client: ServerClient) async throws {
        activity = "Waiting for approval…"
        let key = Curve25519.KeyAgreement.PrivateKey()
        let request = try await client.beginPairing(
            deviceName: model.deviceName, publicKey: key.publicKey.rawRepresentation, invite: scanned)
        if Task.isCancelled {
            try? await client.cancelPairing(request)
            return
        }
        ticket = request
        pairingKey = key
        try await awaitApproval(client, ticket: request, key: key)
    }
    func retryScannedCode() {
        if let invite { join(invite) }
    }
    /// Leaves a scanned code for choosing a server again.
    func forgetScannedCode() {
        abandon()
        invite = nil
        error = nil
        path = []
    }
    /// Scan Again: a new code from the connected device.
    func scanAgain() {
        forgetScannedCode()
        scanRequested = true
    }
    /// Polls until approved, revealing this device's key (and showing the check code) once the approving
    /// device's key is known. Rate-limited responses only lengthen the interval.
    private func awaitApproval(
        _ client: ServerClient, ticket request: PairingTicket, key: PairingPrivateKey
    ) async throws {
        var delay: UInt64 = 1_000_000_000
        while !Task.isCancelled {
            guard request.pollingDeadline > Date() else { throw PairingError.expired }
            do {
                let poll = try await client.pollPairing(request)
                try Task.checkCancellation()
                if poll.declined == true { throw PairingError.declined }
                if poll.approved {
                    // A grant can only follow this device's reveal; otherwise no check code was ever shown.
                    guard let reveal else { throw PairingError.insecureGrant }
                    guard let id = poll.deviceId else { throw JournalError.invalidData }
                    received = try ServerClient.openPairing(poll, reveal: reveal, ticket: request, privateKey: key)
                    receivedDeviceID = id
                    pairingKey = nil
                    // Accepted only once the person confirmed that the codes match, or when the key came from a
                    // scanned code; Connect continues from here.
                    if confirmed { await finishImport() }
                    return
                }
                if reveal == nil, poll.approverKey != nil {
                    // A scanned code named the connected device's key: any other key is the server's.
                    if let invite, !invite.names(approverKey: poll.approverKey) { throw PairingError.insecureGrant }
                    let shown = try await client.revealPairing(request, poll: poll, privateKey: key)
                    try Task.checkCancellation()
                    reveal = shown
                    if invite == nil {
                        announceForAccessibility(
                            "Check code \(shown.checkCode.map(String.init).joined(separator: " ")). Connect only if your other device shows the same code."
                        )
                    }
                }
                delay = 1_000_000_000
            } catch is ServerRateLimited {
                delay = min(delay * 2, 16_000_000_000)
            }
            try await Task.sleep(nanoseconds: delay)
        }
    }
    /// The check code is on screen and the person hasn't compared it yet.
    var awaitingConfirmation: Bool { invite == nil && reveal != nil && !confirmed && error == nil }
    func confirm() {
        confirmed = true
        // The other device may have approved already; nothing was installed until now.
        if received != nil { resumeImport() }
    }
    func resumeImport() { operation = Task { await finishImport() } }
    private func finishImport() async {
        // Nothing from the other device is installed before the codes were compared, or without a scanned code.
        guard confirmed || invite != nil, let received, let id = receivedDeviceID, !model.locked else { return }
        guard agreedToMerge() else { return }
        busy = true
        installing = true
        activity = "Connecting…"
        error = nil
        defer {
            busy = false
            installing = false
        }
        do {
            try Task.checkCancellation()
            // A library with nothing written is replaced; any other was merged with the server's, as the person agreed.
            let replacing = model.nothingWritten
            try await model.installPairedVault(
                address: address, key: received.masterKey, token: received.token, deviceID: id,
                uploadLocal: !replacing, recoveryVersion: received.recoveryVersion ?? 1, shown: envelope,
                replacingEmptyLibrary: replacing)
            completed = true
            ticket = nil
            self.received = nil
            finished = true
        } catch is CancellationError {} catch is MergeConsentNeeded {
            askToMerge { [weak self] in self?.resumeImport() }
        } catch {
            if let refusal = error as? ServerConnectionError {
                // This pairing can't be used with the server as it is now: start again from the address, where
                // Continue checks the server again.
                if refusal == .serverChanged {
                    abandon()
                    path = []
                }
                self.error = refusal.shown(.saving)
            } else if let interrupted = error as? MergeInterrupted {
                self.error = mergeFailure(sent: interrupted.sent)
            } else if (error as? JournalError)?.refusesMerge == true {
                self.error = error.shown(.saving)
            } else if model.store == nil {
                self.error = "Couldn’t finish connecting."
            } else if model.replacingVault {
                // A copy of the library waits for Try Again, and writing is paused until it's used or discarded.
                self.error =
                    "Couldn’t finish connecting. Your local journals remain on this device. Try again, or cancel to keep writing."
            } else {
                self.error = "Couldn’t finish connecting. Your local journals remain on this device."
            }
            canRetryScannedCode = false
            if let message = self.error { announceForAccessibility(message) }
        }
    }

    // MARK: Leaving

    /// Stops what's running. A pairing request is withdrawn, and access that was granted but never used is given up.
    func abandon() {
        operation?.cancel()
        operation = nil
        busy = false
        if let ticket, let client = try? ServerClient(address: address) {
            withdrawal = Task { try? await client.cancelPairing(ticket) }
        }
        // Approved but never connected, for example because the codes didn't match: the new access this device
        // received is given up, so it doesn't stay in the Devices list. If this fails, the other device can revoke it.
        // The library may already use this access while installing finishes; it's revoked only if it doesn't.
        if !completed, let received, let id = receivedDeviceID, model.connection?.deviceID != id,
            let client = try? ServerClient(address: address, token: received.token)
        {
            Task { try? await client.revoke(id) }
        }
        confirmed = false
        // Access kept for Try Again is given up with its staged copy, so editing continues.
        if !completed { Task { await model.giveUpRetry() } }
        ticket = nil
        pairingKey = nil
        received = nil
        receivedDeviceID = nil
        reveal = nil
    }
    /// The failure to show on a step; nil is the first screen.
    func errorMessage(on step: Step?) -> String? { errorStep == step ? error : nil }
    /// Leaving Add This Device, by Back or otherwise, withdraws its request. Back from Merge Journals forgets a
    /// scanned code; nothing was sent for it. Back from a Merge Journals step that was pushed after access was
    /// received gives that access up, as the merge was not agreed to (docs/design/sync-health-and-recovery.md §3.2).
    private func pathChanged(from old: [Step]) {
        if old.contains(.addThisDevice) && !path.contains(.addThisDevice) { abandon() }
        if old == [.merge], path.isEmpty, invite != nil {
            invite = nil
            error = nil
        }
        if old.last == .merge, path.count < old.count, resumeAfterMerge != nil { leaveMergeWithoutAgreeing() }
    }
    /// The step Back lands on starts as a new visit: the access it obtained is given up, so what it asks for again
    /// is asked from the server again.
    private func leaveMergeWithoutAgreeing() {
        resumeAfterMerge = nil
        abandon()
        error = nil
        switch path.last {
        case .signIn:
            phrase = ""
            focusRequest = .phrase
        case .recoveryCode:
            phrase = ""
            codeUsedNotice = "That code was used. Enter a new one."
            focusRequest = .phrase
            if let notice = codeUsedNotice {
                // After focus moves, so VoiceOver doesn't cut the announcement off.
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    announceForAccessibility(notice)
                }
            }
        case .addThisDevice:
            // The old code was withdrawn; its screen shows “Getting a code…” until a new one arrives.
            announcesNewCode = true
            beginPairing()
        default:
            break
        }
    }
    func cancel() {
        abandon()
        model.agreedMergeHost = nil
        finished = true
    }
    func close() {
        if !completed { abandon() }
        model.agreedMergeHost = nil
    }
    /// The server holds another library: Merge Journals asks first, and Merge continues with `resume`.
    private func askToMerge(_ resume: @escaping () -> Void) {
        resumeAfterMerge = resume
        path.append(.merge)
    }

    // MARK: Messages

    private func fail(_ field: Field, _ message: String) {
        fieldErrors[field] = message
        focusRequest = field
        // After focus moves, so VoiceOver doesn't cut the announcement off.
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            announceForAccessibility(message)
        }
    }
    private func clearPasswordErrors() {
        fieldErrors[.newPassword] = nil
        fieldErrors[.verifyPassword] = nil
    }
    /// Some journals may be on the server only once sending started (docs/design/join-with-local-journals.md §2.7).
    private func mergeFailure(sent: Bool) -> String {
        sent
            ? "Couldn’t finish connecting. Your journals are still on this device, and some may already be on \(host). Try again, or cancel to keep writing."
            : "Couldn’t finish connecting. Your journals are still on this device. Try again, or cancel to keep writing."
    }
    /// Consent is checked again when installing: the library may have gained writing since the server was checked,
    /// for example in another window. Merge Journals then comes first, and nothing is installed.
    private func agreedToMerge() -> Bool {
        guard asksToMerge else { return true }
        abandon()
        error = nil
        path = [.merge]
        return false
    }
    /// Shows a failure in words that say what to do next.
    private func show(_ failure: Error) {
        canRetryScannedCode = false
        mergeInterrupted = failure is MergeInterrupted
        let message: String
        switch failure {
        case let interrupted as MergeInterrupted:
            message = mergeFailure(sent: interrupted.sent)
        case ServerConnectionError.encryptionOff:
            message =
                ServerConnectionError.encryptionOffMessage(host: host)
        case is URLError:
            canRetryScannedCode = invite != nil
            message =
                host.hasSuffix(".ts.net")
                ? "Couldn’t connect to the server. If it uses Tailscale, turn on Tailscale on this device and try again."
                : "Couldn’t connect to the server. Check your connection and try again."
        case let refusal as SyncFailure where refusal.health == .notJournalServer:
            message = "This address doesn’t lead to a My Journal server. Check it and try again."
        case is ServerUnavailable:
            message = "The server isn’t available right now. Try again in a moment."
        case PairingError.declined where invite != nil:
            message = "Your connected device didn’t add this one."
        case PairingError.expired where invite != nil:
            message = "This code has expired. Show a new code on your connected device."
        case PairingError.insecureGrant where invite != nil:
            message = "Couldn’t add this device securely. Show a new code on your connected device and try again."
        default:
            message = failure.shown(.saving)
        }
        error = message
        announceForAccessibility(message)
    }
}
