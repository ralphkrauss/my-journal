import JournalCore
import LocalAuthentication
import SwiftUI

/// Settings > Devices > Add Device (docs/design/effortless-connection.md): shows a code a new iPhone or iPad scans,
/// or takes the pairing code a new device shows and compares check codes.
struct AddDeviceView: View {
    private enum Step {
        /// Asking the server whether it takes scanned codes.
        case preparing
        case showingCode
        case entry
        case waiting(PairingChallenge, scanned: Bool)
        case confirm(PairingApproval, scanned: Bool)
        /// Nothing more can be done here; only Done remains.
        case finished
    }
    /// How long a shown code lasts before a new one replaces it, how long the replaced one is still watched (a
    /// device may have scanned it just before), and how long the sheet shows codes at all.
    static let codeLifetime: TimeInterval = 120
    static let replacedCodeGrace: TimeInterval = 30
    static let sessionLifetime: TimeInterval = 600

    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var code = ""
    /// The code as last formatted, to tell typing at the end from other edits.
    @State private var formattedCode = ""
    @State private var step = Step.preparing
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    @State private var operation: Task<Void, Never>?
    @State private var current: PairingInviteHost?
    @State private var codeShownAt = Date()
    @State private var replaced: (host: PairingInviteHost, until: Date)?
    @State private var sessionStart = Date()
    @State private var expired = false
    @State private var unreachable = false

    var body: some View {
        NavigationStack {
            Form {
                if model.locked {
                    Text("Unlock My Journal to add a device.")
                } else {
                    content
                    if let error { Section { Text(error).foregroundStyle(.red).font(.callout) } }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Device")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .finished = step {
                        EmptyView()
                    } else {
                        Button(isConfirmingScan ? "Don’t Add" : "Cancel", role: .cancel) { cancel() }
                            .disabled(busy && isConfirming)
                    }
                }
                ToolbarItem(placement: .confirmationAction) { primaryAction }
            }
        }
        #if os(macOS)
            .frame(minWidth: 400, idealWidth: 460, minHeight: 440, idealHeight: 540)
            .background(ScreenCaptureExclusion())
        #endif
        .interactiveDismissDisabled(busy)
        .keepsUnlockedWhile(waitingForDevice)
        .task { await start() }
        .onDisappear {
            operation?.cancel()
            declinePending()
            #if os(iOS)
                UIApplication.shared.isIdleTimerDisabled = false
            #endif
        }
        .onValueChange(of: model.locked) { locked in
            if locked {
                cancel()
            }
        }
        .onValueChange(of: scenePhase) { phase in
            // A code isn't left behind in the background; a new one appears on return. Only leaving for the
            // background counts: Face ID and Control Center make the app inactive for a moment.
            guard case .showingCode = step, !expired else { return }
            if phase == .background {
                operation?.cancel()
                current = nil
                replaced = nil
            } else if phase == .active && current == nil {
                showNewCode()
            }
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch step {
        case .preparing:
            Section { ProgressView().frame(maxWidth: .infinity) }
        case .showingCode:
            codeSection
            if let address = model.connection?.address {
                // The new device names this server before merging its journals with it.
                Section { LabeledContent("Server", value: ServerAddress.host(address)).textSelection(.enabled) }
            }
            Section {
                Button("Enter Code Instead…") { enterCode() }
            } footer: {
                Text("For a Mac or a device that can’t scan the code.")
            }
        case .entry:
            entrySections
        case .waiting(let challenge, _):
            Section {
                if error == nil {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for \(Self.displayName(challenge.candidate.deviceName))…").foregroundStyle(
                            .secondary)
                    }.accessibilityElement(children: .combine)
                }
            }
        case .confirm(let approval, let scanned):
            Section {
                if scanned {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add “\(Self.displayName(approval.candidate.deviceName))”?").font(.headline)
                        Text("It will be able to read and sync all your journals.").foregroundStyle(.secondary)
                    }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
                } else {
                    checkCodeConfirmation(approval)
                }
            }
        case .finished:
            EmptyView()
        }
    }
    /// The Mac shows the code except in the background, so another window in front doesn't hide it from a phone
    /// held up to the screen. iPhone and iPad hide it whenever the app isn't active, since the app switcher's
    /// snapshot shows the inactive state (docs/design/build-18-fixes-2026-10-06.md §3.3).
    private var showsCodeImage: Bool {
        #if os(macOS)
            scenePhase != .background
        #else
            scenePhase == .active
        #endif
    }
    private var codeSection: some View {
        Section {
            VStack(spacing: 16) {
                if let notice { Text(notice).font(.callout).multilineTextAlignment(.center) }
                if expired {
                    if error == nil { Text("This code has expired.").font(.headline).padding(.vertical, 40) }
                } else if showsCodeImage, let current {
                    PairingCodeImage(text: current.invite.text)
                } else {
                    // Hidden in the app switcher (iPhone and iPad, where the snapshot shows the inactive state) and
                    // while the app is in the background.
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.quaternary)
                        .frame(width: 252, height: 252).accessibilityHidden(true)
                }
                Text(
                    "On your iPhone or iPad, choose Connect to a Server, then Scan Code. If it already has journals, Connect to a Server is in Settings > Sync."
                )
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                if !expired {
                    if unreachable {
                        Text("Couldn’t reach the server. Check your connection.").font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Waiting for your new device…").foregroundStyle(.secondary)
                        }.font(.callout).accessibilityElement(children: .combine)
                    }
                }
            }.frame(maxWidth: .infinity).padding(.vertical, 8)
        }
    }
    @ViewBuilder private var entrySections: some View {
        Section {
            TextField(
                "Pairing Code",
                text: $code,
                prompt: Text(verbatim: "123 456 789")
            )
            .font(.body.monospaced()).autocorrectionDisabled()
            #if os(iOS)
                .keyboardType(.numberPad)
            #endif
            .disabled(busy).onSubmit { if canLookUp { lookUp() } }
            // The field keeps its own text while editing, so the formatted code is written back here.
            .onValueChange(of: code) { typed in
                let formatted = CodeEntry.pairingCode(typed, previous: formattedCode)
                formattedCode = formatted
                if formatted != typed { code = formatted }
            }
        } footer: {
            Text("On the new device, choose Connect to a Server, then Add This Device.")
        }
        if let address = model.connection?.address {
            if PairingInvite.origin(of: address)?.hasPrefix("https://") == true {
                Section {
                    LabeledContent("Server Address", value: address).textSelection(.enabled)
                    Button("Copy Address") { copy(address) }
                }
            } else {
                // Plain HTTP is only accepted for a server on this device, such as the container on this Mac.
                Section {
                    Text(
                        "Other devices can’t connect to \(ServerAddress.host(address)). To add devices, connect this device to the server’s HTTPS address."
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
    private func checkCodeConfirmation(_ approval: PairingApproval) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Does \(Self.displayName(approval.candidate.deviceName)) show this code?").font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(PairingCheck.grouped(approval.checkCode)).font(.system(.largeTitle, design: .monospaced))
                .foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("check-code").accessibilityLabel("Check code")
                .accessibilityValue(approval.checkCode.map(String.init).joined(separator: " "))
            Text(
                "Approve only if the codes match. \(Self.displayName(approval.candidate.deviceName)) will be able to read and sync all your journals."
            ).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    @ViewBuilder private var primaryAction: some View {
        switch step {
        case .preparing:
            EmptyView()
        case .showingCode:
            if expired { Button("Show New Code") { restart() } }
        case .entry:
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Button("Continue") { lookUp() }.disabled(!canLookUp)
            }
        case .waiting(let challenge, let scanned):
            if error != nil && !scanned { Button("Try Again") { prepare(challenge, scanned: false) } }
        case .confirm(let approval, let scanned):
            if busy {
                ProgressView().controlSize(.small)
            } else {
                // Not the Return default: adding must follow reading the name or comparing the codes.
                Button(scanned ? "Add Device" : "Approve") { approve(approval) }
                    .keyboardShortcut(.return, modifiers: .command)
            }
        case .finished:
            Button("Done") { dismiss() }
        }
    }
    private var isConfirming: Bool {
        if case .confirm = step { return true }
        return false
    }
    private var isConfirmingScan: Bool {
        if case .confirm(_, true) = step { return true }
        return false
    }
    private var canLookUp: Bool { !busy && !code.isEmpty }

    // MARK: Showing a code

    /// A code is shown or a device is answering: the person is busy on the other device, not here.
    private var waitingForDevice: Bool {
        switch step {
        case .preparing, .waiting: return true
        case .showingCode: return !expired
        case .entry, .confirm, .finished: return busy
        }
    }
    private func start() async {
        guard !model.locked, let address = model.connection?.address,
            PairingInviteHost(server: address) != nil,
            (try? await model.connectedClient().status().supports(PairingInvite.feature)) == true
        else {
            step = .entry
            return
        }
        #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = true
        #endif
        restart()
    }
    private func restart() {
        error = nil
        notice = nil
        sessionStart = Date()
        expired = false
        step = .showingCode
        showNewCode()
    }
    /// A new code, watched until a device answers it. It changes every two minutes; the one it replaced is still
    /// watched for a little while, in case a device scanned it just before.
    private func showNewCode() {
        operation?.cancel()
        guard let address = model.connection?.address else { return }
        current = PairingInviteHost(server: address)
        codeShownAt = Date()
        operation = Task { await watchForNewDevice(address: address) }
    }
    private func watchForNewDevice(address: String) async {
        var failures = 0
        while !Task.isCancelled {
            let now = Date()
            if now.timeIntervalSince(sessionStart) > Self.sessionLifetime {
                expired = true
                current = nil
                replaced = nil
                #if os(iOS)
                    UIApplication.shared.isIdleTimerDisabled = false
                #endif
                return
            }
            if let shown = current, now.timeIntervalSince(codeShownAt) > Self.codeLifetime {
                replaced = (shown, now.addingTimeInterval(Self.replacedCodeGrace))
                current = PairingInviteHost(server: address)
                codeShownAt = now
            }
            if let old = replaced, old.until < now { replaced = nil }
            for host in [current, replaced?.host].compactMap({ $0 }) {
                do {
                    let candidate = try await model.connectedClient().pairingCandidate(code: host.invite.code)
                    failures = 0
                    unreachable = false
                    answer(candidate, host: host)
                    return
                } catch PairingError.codeNotFound {
                    failures = 0
                    unreachable = false
                } catch is ServerRateLimited {
                    // Only slower.
                } catch is CancellationError {
                    return
                } catch {
                    failures += 1
                    unreachable = failures >= 3
                }
            }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
        }
    }
    /// A device answered a code. Its request is shown only if it proves the device read that code; the code is
    /// used up either way.
    private func answer(_ candidate: PairingCandidate, host: PairingInviteHost) {
        current = nil
        replaced = nil
        notice = nil
        guard host.verifies(candidate) else {
            decline(candidate.id)
            expired = true
            error = "Couldn’t verify the new device. Show a new code and try again."
            return
        }
        prepare(host.challenge(candidate), scanned: true)
    }

    // MARK: Typed code

    private func enterCode() {
        operation?.cancel()
        current = nil
        replaced = nil
        error = nil
        step = .entry
    }
    private func lookUp() {
        guard CodeEntry.pairingCodeIsComplete(code) else {
            error = "Enter the 9-digit code from your new device."
            announceForAccessibility("Enter the 9-digit code from your new device.")
            return
        }
        busy = true
        error = nil
        let typed = CodeEntry.normalized(code)
        code = CodeEntry.pairingCode(typed, previous: "")
        operation = Task {
            defer { busy = false }
            do {
                let candidate = try await model.connectedClient().pairingCandidate(code: typed)
                guard !model.locked, !Task.isCancelled else { return }
                prepare(PairingChallenge(candidate), scanned: false)
            } catch { show(error, scanned: false) }
        }
    }

    // MARK: Approving

    private func prepare(_ challenge: PairingChallenge, scanned: Bool) {
        step = .waiting(challenge, scanned: scanned)
        error = nil
        operation = Task {
            do {
                let approval = try await model.connectedClient().preparePairingApproval(challenge)
                guard !model.locked, !Task.isCancelled else { return }
                step = .confirm(approval, scanned: scanned)
                // A scanned device needs no code comparison: authenticating is the confirmation, with its name on
                // screen. Without a passcode, Add stays an explicit choice.
                if scanned && Self.confirmationIsDeliberate { approve(approval) }
            } catch is CancellationError {} catch {
                if scanned {
                    stoppedConnecting(challenge.candidate, failure: error)
                } else {
                    show(error, scanned: false)
                }
            }
        }
    }
    private func approve(_ approval: PairingApproval) {
        busy = true
        error = nil
        operation = Task {
            defer { busy = false }
            guard await Self.confirmOwner(adding: Self.displayName(approval.candidate.deviceName)) else { return }
            do {
                try await model.approveDevice(approval)
                step = .finished
                dismiss()
            } catch is URLError {
                // The request may have reached the server; never suggest approving again.
                step = .finished
                error =
                    "Couldn’t confirm that \(Self.displayName(approval.candidate.deviceName)) was added. Check the device list."
            } catch {
                if case .confirm(_, true) = step {
                    stoppedConnecting(approval.candidate, failure: error)
                } else {
                    show(error, scanned: false)
                }
            }
        }
    }
    /// Face ID, Touch ID or the device passcode before another device gets the journals' key. Devices without a
    /// passcode continue.
    private static func confirmOwner(adding name: String) async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return true }
        #if os(macOS)
            let reason = "add “\(name)” to your journals"
        #else
            let reason = "Add “\(name)” to your journals"
        #endif
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) == true
    }
    /// Whether authenticating is itself a deliberate act (Touch ID, a passcode or password, Apple Watch), so it can
    /// follow a verified request without a tap first. Face ID happens by looking at the screen, before the name is
    /// read, and VoiceOver needs time to read the name: both keep the Add Device button.
    private static var confirmationIsDeliberate: Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        #if os(iOS)
            if UIAccessibility.isVoiceOverRunning { return false }
        #else
            if NSWorkspace.shared.isVoiceOverEnabled { return false }
        #endif
        return context.biometryType != .faceID
    }
    /// The new device went away while its request was open: say so and show a new code.
    private func stoppedConnecting(_ candidate: PairingCandidate, failure: Error) {
        restart()
        notice = "“\(Self.displayName(candidate.deviceName))” stopped connecting."
        if let network = failure as? URLError { error = NetworkFailureMessage.text(for: network) }
    }
    private func show(_ failure: Error, scanned: Bool) {
        if let network = failure as? URLError {
            error = NetworkFailureMessage.text(for: network)
        } else {
            error = failure.shown(.saving)
        }
        switch failure {
        case PairingError.deviceOutdated: step = .finished
        case PairingError.insecureCandidate, PairingError.expired, PairingError.noResponse:
            code = ""
            step = .entry
        default:
            // Temporary failures keep the current step and code so the person can try again.
            break
        }
    }
    private func cancel() {
        operation?.cancel()
        declinePending()
        dismiss()
    }
    /// Best effort: tells the new device it wasn't added. Otherwise its request simply expires.
    private func declinePending() {
        switch step {
        case .waiting(let challenge, _): decline(challenge.candidate.id)
        case .confirm(let approval, _): if !busy { decline(approval.candidate.id) }
        default: break
        }
    }
    private func decline(_ id: UUID) {
        guard let client = try? model.connectedClient() else { return }
        Task { try? await client.declinePairing(id) }
    }
    private func copy(_ text: String) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #else
            UIPasteboard.general.string = text
        #endif
    }
    /// A requesting device's name as shown: without control or direction-changing characters, at most 60 long.
    static func displayName(_ name: String) -> String {
        let visible = name.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && $0.properties.generalCategory != .format
        }
        let cleaned = String(String.UnicodeScalarView(visible)).trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = cleaned.isEmpty ? "New Device" : cleaned
        return shown.count > 60 ? String(shown.prefix(59)) + "…" : shown
    }
}

#if os(macOS)
    import AppKit

    /// Keeps the Add Device window out of screen sharing and recordings: its code lets a device join.
    private struct ScreenCaptureExclusion: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView { WindowWatcher() }
        func updateNSView(_ view: NSView, context: Context) {}
        private final class WindowWatcher: NSView {
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                window?.sharingType = .none
            }
        }
    }
#endif
