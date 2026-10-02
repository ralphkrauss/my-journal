import JournalCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Settings > Agent Access: agents that connect to the sync server's MCP endpoint and read the journals the owner
/// allowed (docs/design/agent-access-simplified.md, section 10).
struct ServerAgentsSections: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var controller: ServerAgentsController
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if model.connection != nil, controller.phase == .ready, !controller.requests.isEmpty {
            Section("Requests") { requestRows }
        }
        if model.connection != nil, controller.loaded, !controller.agents.isEmpty {
            Section("Agents") { agentRows }
        }
        connectSection
    }

    private var connectSection: some View {
        Section {
            connect
        } header: {
            Text("Connect an Agent")
        } footer: {
            if model.connection != nil, controller.phase == .ready {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        "Add this address to your agent as an MCP server or custom connector. When the agent asks for access, the request appears here."
                    )
                    if let exposure { Text(verbatim: exposure) }
                    if let guide = ServerAgentText.guide { Link("How to Connect an Agent", destination: guide) }
                }
            }
        }
    }

    private var host: String { ServerAgentText.host(model.connection?.address) }
    private var leadingHost: String { ServerAgentText.leadingHost(model.connection?.address) }
    /// With encryption, whoever runs a server other than this Mac's could read what agents read.
    private var exposure: String? {
        guard model.configuration?.encrypted != false,
            let server = model.connection.flatMap({ URL(string: $0.address)?.host }),
            !ServerAgentText.isLoopback(host: server)
        else { return nil }
        return "While an agent has access, anyone who controls \(host) could read the journals it reads."
    }

    @ViewBuilder private var connect: some View {
        if model.connection == nil {
            #if os(macOS)
                Text("To let agents read your journals, use this Mac as your server or connect to one.")
                Button("Set Up Sync…") { model.settingsTab = .sync }
            #else
                Text("To let agents read your journals, connect to a sync server.")
                Button("Set Up Sync…") { controller.connecting = true }
            #endif
        } else {
            switch controller.phase {
            case .loading where !controller.loaded:
                connectionStatus("Loading…")
            case .needsUpdate:
                Text(verbatim: "\(leadingHost) needs an update before agents can connect.")
            case .noAccess:
                Text(verbatim: "This device no longer has access to \(host).")
                Button("Connect Again…") { controller.connecting = true }
            case .addressUnavailable(let reason):
                Text(
                    reason == "public-url-required"
                        ? "Set your server’s public address before agents can connect."
                        : "\(leadingHost) doesn’t know its HTTPS address. Set its public address before agents can connect."
                )
                if let guide = ServerAgentText.guide { Link("How to Connect an Agent", destination: guide) }
            case .unreachable:
                Text(verbatim: "Couldn’t reach \(host).")
                Button("Try Again") { Task { await controller.load(model) } }
            default:
                if let address = controller.mcpURL {
                    MCPAddressRow(address: address)
                    if let reachability = ServerAgentText.reachability(address) {
                        Text(reachability).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var requestRows: some View {
        ForEach(controller.requests) { request in
            Button {
                controller.reviewing = request
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        // One line each, except at accessibility sizes, where nothing is cut off.
                        Text(verbatim: ServerAgentText.displayName(request.clientName))
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        Text(verbatim: "\(request.redirectHost) · \(ServerAgentText.asked(request.requestedAt))")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The button stays the accessibility element, so VoiceOver and the Mac's accessibility actions press it.
            .accessibilityLabel(
                Text(
                    verbatim:
                        "\(ServerAgentText.displayName(request.clientName)), returns to \(request.redirectHost), \(ServerAgentText.asked(request.requestedAt))"
                )
            )
            .accessibilityHint("Reviews the request.")
        }
    }

    @ViewBuilder private var agentRows: some View {
        ForEach(controller.agents) { agent in
            #if os(macOS)
                Button {
                    controller.selected = agent
                } label: {
                    HStack {
                        ServerAgentRow(agent: agent)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityHint("Shows details.")
            #else
                NavigationLink {
                    ServerAgentDetailView(controller: controller, agentID: agent.id)
                } label: {
                    ServerAgentRow(agent: agent)
                }.accessibilityHint("Shows details.")
            #endif
        }
    }
}

/// Presents the pane's sheets from its form, loads the list for the connected server and, while the pane is visible
/// and My Journal is active, looks for new requests every few seconds.
struct ServerAgentsPresentation: ViewModifier {
    @EnvironmentObject var model: AppModel
    @ObservedObject var controller: ServerAgentsController
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task(id: model.connection?.address) {
                await controller.load(model)
                // At once when the pane appears, then every few seconds while My Journal is active.
                await controller.refreshRequests(model)
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if isActive { await controller.refreshRequests(model) }
                }
            }
            .onValueChange(of: scenePhase) { phase in
                if phase == .active { Task { await controller.refreshRequests(model) } }
            }
            #if os(macOS)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) {
                    _ in Task { await controller.refreshRequests(model) }
                }
            #endif
            .sheet(item: $controller.reviewing, onDismiss: { Task { await controller.refreshRequests(model) } }) {
                AllowAgentView(controller: controller, summary: $0)
            }
            .sheet(isPresented: $controller.connecting) { ConnectionView() }
            #if os(macOS)
                .sheet(item: $controller.selected) { agent in
                    NavigationStack {
                        ServerAgentDetailView(controller: controller, agentID: agent.id)
                    }
                    .frame(minWidth: 440, idealWidth: 480, minHeight: 420, idealHeight: 560)
                }
            #endif
            .onValueChange(of: model.locked) { locked in
                if locked { controller.clear() }
            }
    }

    private var isActive: Bool {
        #if os(macOS)
            NSApp.isActive
        #else
            scenePhase == .active
        #endif
    }
}

/// The MCP server address with Copy (and Share on iPhone and iPad, since it's usually needed on a computer).
struct MCPAddressRow: View {
    let address: String
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var copied = false
    @State private var feedback: Task<Void, Never>?
    var body: some View {
        LabeledContent("MCP Server Address") {
            Text(verbatim: address).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                // Accessibility sizes stack the address below its label.
                .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
        }
        HStack {
            Button(copied ? "Copied" : "Copy") {
                PlainPasteboard.copy(address)
                copied = true
                announceForAccessibility("Copied.")
                feedback?.cancel()
                feedback = Task {
                    do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
                    copied = false
                }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(copied ? "Copied" : "Copy MCP Server Address")
            #if os(iOS)
                Spacer()
                ShareLink(item: address) { Text("Share…") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Share MCP Server Address")
            #endif
        }
        .onDisappear { feedback?.cancel() }
    }
}

/// One agent in the list: its name, journals and status.
struct ServerAgentRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let agent: LibraryAgent
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: agent.name).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            Group {
                Text(verbatim: ServerAgentText.journalNames(agent, journals: model.journals)).lineLimit(2)
                if agent.settings != nil {
                    if agent.needsReconnect && !agent.hasExpired() {
                        Label(ServerAgentText.status(agent), systemImage: "exclamationmark.circle")
                    } else {
                        Text(ServerAgentText.status(agent))
                    }
                }
            }.font(.subheadline).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Journals

/// All journals, including ones created later, or the chosen ones.
enum AgentJournalScope: Hashable {
    case all, selected
}

/// The Journals choice of the approval sheet and the agent detail: All Journals or Selected Journals, and the
/// journals themselves.
struct AgentJournalsSection: View {
    @EnvironmentObject var model: AppModel
    @Binding var scope: AgentJournalScope?
    @Binding var selection: Set<UUID>
    /// The agent's name, for the footer.
    let name: String
    /// In the detail, the last chosen journal can't be turned off (revoking stops all access).
    var keepsOne = false

    var body: some View {
        Section {
            Picker("Journals", selection: $scope) {
                Text("All Journals").tag(AgentJournalScope?.some(.all))
                Text("Selected Journals").tag(AgentJournalScope?.some(.selected))
            }
            #if os(macOS)
                .pickerStyle(.radioGroup)
            #else
                .pickerStyle(.inline)
            #endif
            .labelsHidden()
        } header: {
            Text("Journals")
        } footer: {
            if scope == nil { footer }
        }
        if let scope {
            Section {
                ForEach(model.journals) { journal in
                    if scope == .all {
                        // What All Journals includes now, as a reminder; nothing to change here.
                        Toggle(isOn: .constant(true)) { Text(verbatim: journal.title) }.disabled(true)
                    } else {
                        Toggle(isOn: binding(journal.id)) { Text(verbatim: journal.title) }
                            .disabled(keepsOne && isLastChosen(journal.id))
                            .accessibilityHint(
                                keepsOne && isLastChosen(journal.id) ? "To stop all access, revoke it." : "")
                    }
                }
                if scope == .selected, unknownCount > 0 {
                    Text(
                        unknownCount == 1
                            ? "1 journal that isn’t on this device"
                            : "\(unknownCount) journals that aren’t on this device"
                    ).foregroundStyle(.secondary)
                }
            } footer: {
                footer
            }
        }
    }

    private var footer: some View {
        Text(
            verbatim: (scope == .all ? "Includes journals you create later. " : "")
                + ServerAgentText.readOnly(name) + " It may send what it reads to its AI provider.")
    }
    private var unknownCount: Int { selection.subtracting(model.journals.map(\.id)).count }
    private func isLastChosen(_ id: UUID) -> Bool { selection == [id] }
    private func binding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { selection.contains(id) },
            set: { value in
                if value {
                    selection.insert(id)
                } else {
                    selection.remove(id)
                }
            })
    }
}

// MARK: - Allow

/// Allow Access: who is asking and where access goes, the number the page shows, and the journals.
struct AllowAgentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @ObservedObject var controller: ServerAgentsController
    let summary: AgentRequest
    @State private var request: AgentRequest?
    @State private var number = ""
    @State private var scope: AgentJournalScope?
    @State private var selection: Set<UUID> = []
    @State private var busy = false
    @State private var error: String?
    @State private var ending: (title: String, message: String)?
    @State private var operation: Task<Void, Never>?
    @FocusState private var numberFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                #if os(macOS)
                    if #unavailable(macOS 26) { Section { Text("Allow Access").font(.headline) } }
                #endif
                if let request {
                    details(request)
                } else if let error {
                    Section { Text(error).foregroundStyle(.red) }
                } else {
                    Section { connectionStatus("Loading…") }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Allow Access")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Don’t Allow") { decline() }.disabled(busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Allow") { allow() }.disabled(!canAllow)
                    }
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 440, idealWidth: 480, minHeight: 420, idealHeight: 540)
        #endif
        // One way out: Don't Allow or Allow (Escape is Don't Allow on the Mac).
        .interactiveDismissDisabled(true)
        .task { await open() }
        .onDisappear { operation?.cancel() }
        .onValueChange(of: model.locked) { locked in
            if locked {
                operation?.cancel()
                dismiss()
            }
        }
        .alert(
            ending?.title ?? "", isPresented: Binding(get: { ending != nil }, set: { if !$0 { ending = nil } }),
            presenting: ending
        ) { _ in
            Button("OK") { dismiss() }
        } message: {
            Text($0.message)
        }
    }

    private var host: String { ServerAgentText.host(model.connection?.address) }
    private var target: LibraryAgent? { request.flatMap(controller.reconnectTarget) }
    private var clientName: String { ServerAgentText.displayName(summary.clientName) }
    private var atLimit: Bool { target == nil && controller.agents.count >= AgentCopyPublisher.maximumAgents }
    private var canAllow: Bool {
        guard request != nil, !busy, number.count == 2, !atLimit else { return false }
        if target != nil { return true }
        return scope == .all || (scope == .selected && !selection.intersection(model.journals.map(\.id)).isEmpty)
    }

    private var numberPrompt: Text? {
        #if os(macOS)
            nil
        #else
            Text("Number Shown on the Page")
        #endif
    }

    @ViewBuilder private func details(_ request: AgentRequest) -> some View {
        Section {
            // One row: who is asking, where access goes, and when to allow it.
            VStack(alignment: .leading, spacing: 6) {
                if let target {
                    Text(verbatim: "\(target.name) wants to reconnect.").font(.headline)
                } else {
                    Text(verbatim: "\(clientName) wants to read your journals.").font(.headline)
                }
                Text(verbatim: ServerAgentText.returns(request))
                Group {
                    if let identified = request.identifiedAs, !request.returnsToLoopback {
                        Text(verbatim: "Identified as \(identified)")
                    }
                    if request.identifiedAs != nil && request.returnsToLoopback {
                        Text("My Journal can’t confirm which app this is.")
                    }
                    if atLimit {
                        Text("You can have up to 20 agents. Revoke one to allow another.")
                    } else {
                        Text("Only allow access if you just connected from your agent.")
                    }
                }.foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }
        Section {
            // The Mac shows the label beside the field; iOS shows it as the prompt.
            TextField("Number Shown on the Page", text: $number, prompt: numberPrompt)
                .autocorrectionDisabled()
                #if os(iOS)
                    .keyboardType(.numberPad)
                #endif
                .focused($numberFocused)
                .onValueChange(of: number) { typed in
                    let digits = String(typed.filter { $0.isASCII && $0.isNumber }.prefix(2))
                    if digits != typed { number = digits }
                    // Both digits entered: the keyboard makes way for the journals.
                    if digits.count == 2 { numberFocused = false }
                }
                .onSubmit { if canAllow { allow() } }
                .accessibilityLabel("Number Shown on the Page")
        } header: {
            Text("Number")
        }
        if let target {
            Section {
                Text(verbatim: ServerAgentText.journalNames(target, journals: model.journals))
            } header: {
                Text("Journals")
            } footer: {
                Text(verbatim: ServerAgentText.readOnly(target.name))
            }
        } else {
            AgentJournalsSection(scope: $scope, selection: $selection, name: clientName)
        }
        if let error {
            Section { Text(error).foregroundStyle(.red) }
        }
    }

    private func open() async {
        do {
            request = try await controller.request(model, id: summary.id)
            numberFocused = true
        } catch AgentCopyError.requestNotFound {
            ending = ("Request Ended", "Start again from your agent if you still want to connect it.")
        } catch {
            self.error = "Couldn’t reach \(host). Check your connection and try again."
        }
    }

    private func allow() {
        guard canAllow, let request, let value = Int(number) else { return }
        busy = true
        error = nil
        let target = target
        let all = scope == .all
        let journals = selection
        operation = Task {
            defer { busy = false }
            do {
                if let target {
                    try await controller.reconnect(model, request: request, number: value, agent: target)
                } else {
                    try await controller.approve(
                        model, request: request, number: value, allJournals: all, journalIDs: all ? [] : journals)
                }
                announceForAccessibility("Access allowed.")
                dismiss()
            } catch AgentCopyError.numberMismatch {
                controller.forget(request)
                announceForAccessibility("Request declined.")
                ending = (
                    "Numbers Don’t Match", "The request was declined. If you started it, connect again from your agent."
                )
            } catch AgentCopyError.requestNotFound {
                controller.forget(request)
                ending = ("Request Ended", "Start again from your agent if you still want to connect it.")
            } catch AgentCopyError.limit {
                error = "You can have up to 20 agents. Revoke one to allow another."
            } catch is ServerRateLimited {
                error = "Too many attempts. Try again in a minute."
            } catch let failure as URLError where failure.code != .cancelled {
                error = "Couldn’t reach \(host). Check your connection and try again."
            } catch is CancellationError {
                return
            } catch {
                self.error = "Couldn’t allow access. Try again."
            }
            if let error { announceForAccessibility(error) }
        }
    }

    private func decline() {
        operation?.cancel()
        let request = request ?? summary
        Task { try? await controller.decline(model, request: request) }
        announceForAccessibility("Request declined.")
        dismiss()
    }
}

// MARK: - Detail

/// One agent: its name, journals, end, when it was used, recent activity and Revoke Access. Changes apply at once.
struct ServerAgentDetailView: View {
    enum Ending: Hashable {
        case never, current, thirtyDays, ninetyDays
    }
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @ObservedObject var controller: ServerAgentsController
    let agentID: UUID
    @State private var shown: LibraryAgent?
    @State private var name = ""
    @State private var scope: AgentJournalScope?
    @State private var selection: Set<UUID> = []
    @State private var ending = Ending.never
    @State private var confirming = false
    @State private var working = false
    @State private var error: String?
    @State private var saving: Task<Void, Never>?
    @State private var applied = false
    @FocusState private var nameFocused: Bool

    private var agent: LibraryAgent? { controller.agent(agentID) ?? shown }
    private var revoked: Bool { controller.loaded && controller.agent(agentID) == nil }
    private var host: String { ServerAgentText.host(model.connection?.address) }

    var body: some View {
        Form {
            #if os(macOS)
                if #unavailable(macOS 26) { Section { Text(verbatim: agent?.name ?? "").font(.headline) } }
            #endif
            if revoked || agent == nil {
                Section { Text("This agent’s access was revoked.") }
            } else if let agent {
                details(agent)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text(verbatim: agent?.name ?? ""))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #else
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(working) }
            }
        #endif
        .onAppear { if !applied, let agent { apply(agent) } }
        .onDisappear { saving?.cancel() }
        .onValueChange(of: model.locked) { if $0 { dismiss() } }
    }

    private var expired: Bool { agent?.hasExpired() ?? false }

    @ViewBuilder private func details(_ agent: LibraryAgent) -> some View {
        if let status = status(agent) {
            Section { Text(verbatim: status) }
        }
        if agent.settings == nil {
            Section { Text("Details aren’t available on this device.").foregroundStyle(.secondary) }
        } else {
            Section {
                TextField("Name", text: $name)
                    .focused($nameFocused)
                    .onSubmit { save() }
                    .disabled(expired)
            } header: {
                // The Mac labels the field itself.
                #if os(iOS)
                    Text("Name")
                #endif
            }
            AgentJournalsSection(scope: $scope, selection: $selection, name: agent.name, keepsOne: true)
                .disabled(expired)
            Section {
                Picker("Access Ends", selection: $ending) {
                    Text("Never").tag(Ending.never)
                    if let ends = agent.settings?.expiresAt {
                        Text(ends.formatted(date: .abbreviated, time: .omitted)).tag(Ending.current)
                    }
                    Text("In 30 Days").tag(Ending.thirtyDays)
                    Text("In 90 Days").tag(Ending.ninetyDays)
                }.pickerStyle(.menu).disabled(expired)
            }
        }
        Section {
            LabeledContent(
                "Last Used",
                value: agent.server.lastUsedAt.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
            LabeledContent("Added", value: agent.server.createdAt.formatted(date: .abbreviated, time: .omitted))
            NavigationLink("Recent Activity") { AgentActivityView(controller: controller, agent: agent) }
        }
        Section {
            Button(expired ? "Remove" : "Revoke Access", role: .destructive) {
                if expired { revoke() } else { confirming = true }
            }
            .disabled(working)
            // Attached to the button, so on iPad the popover points at it rather than at the top of the form.
            .confirmationDialog(
                Text(verbatim: "Revoke access for \(agent.name)?"), isPresented: $confirming, titleVisibility: .visible
            ) {
                Button("Revoke Access", role: .destructive) { revoke() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    verbatim:
                        "\(agent.name) won’t be able to read your journals anymore. It keeps anything it already read.")
            }
            if working { connectionStatus(expired ? "Removing…" : "Revoking…") }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .onValueChange(of: nameFocused) { focused in if !focused { save() } }
        .onValueChange(of: scope) { _ in scheduleSave() }
        .onValueChange(of: selection) { _ in scheduleSave() }
        .onValueChange(of: ending) { _ in scheduleSave() }
    }

    private func status(_ agent: LibraryAgent) -> String? {
        let client = ServerAgentText.displayName(agent.server.clientName)
        if let ends = agent.expiresAt, ends <= Date() {
            return "Access ended \(ends.formatted(date: .abbreviated, time: .omitted))."
        }
        if agent.server.state == .pending { return "Waiting for \(client) to finish connecting." }
        if agent.needsReconnect { return "Connect again from \(client) to reconnect it." }
        return nil
    }

    /// Shows the agent's saved settings in the controls.
    private func apply(_ agent: LibraryAgent) {
        shown = agent
        applied = true
        guard let settings = agent.settings else { return }
        name = settings.name
        scope = settings.allJournals ? .all : .selected
        selection = settings.journalIDs
        ending = settings.expiresAt == nil ? .never : .current
    }

    private func scheduleSave() {
        guard applied else { return }
        saving?.cancel()
        saving = Task {
            do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
            await commit()
        }
    }
    private func save() {
        saving?.cancel()
        saving = Task { await commit() }
    }

    /// Saves what the controls show, if it differs from the agent's settings. A failure shows the saved settings
    /// again.
    private func commit() async {
        guard let agent, let settings = agent.settings, !expired else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = (1...80).contains(trimmed.count) ? trimmed : settings.name
        let all = scope == .all
        let journals = all ? Set<UUID>() : selection
        let expiresAt: Date? =
            switch ending {
            case .never: nil
            case .current: settings.expiresAt
            case .thirtyDays: Calendar.current.date(byAdding: .day, value: 30, to: Date())
            case .ninetyDays: Calendar.current.date(byAdding: .day, value: 90, to: Date())
            }
        guard all || !journals.isEmpty else { return }
        guard
            cleanName != settings.name || all != settings.allJournals
                || (!all && journals != settings.journalIDs) || expiresAt != settings.expiresAt
        else {
            if cleanName != name { name = cleanName }
            return
        }
        error = nil
        do {
            let changed = try await controller.change(
                model, agent: agent, name: cleanName, allJournals: all, journalIDs: journals, expiresAt: expiresAt)
            apply(changed)
        } catch is CancellationError {
            return
        } catch AgentCopyError.settingsChanged {
            await controller.load(model)
            if let latest = controller.agent(agentID) { apply(latest) }
            error = "This agent was changed on another device. Showing the latest settings."
        } catch {
            apply(agent)
            self.error = "Couldn’t save this change. Check your connection and try again."
        }
        if let error { announceForAccessibility(error) }
    }

    private func revoke() {
        guard let agent else { return }
        saving?.cancel()
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                try await controller.revoke(model, agent: agent)
                announceForAccessibility("Access revoked.")
                dismiss()
            } catch {
                self.error =
                    expired
                    ? "Couldn’t remove the agent. Check your connection and try again."
                    : "Couldn’t revoke access. Check your connection and try again."
                if let message = self.error { announceForAccessibility(message) }
            }
        }
    }
}

/// The tools an agent used recently.
struct AgentActivityView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var controller: ServerAgentsController
    let agent: LibraryAgent
    @State private var activity: [AgentActivityEvent]?
    @State private var failed = false

    var body: some View {
        Form {
            Section {
                if let activity, !activity.isEmpty {
                    ForEach(activity, id: \.self) { event in
                        LabeledContent(ServerAgentText.activity(event.tool)) {
                            Text(event.at.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                } else if activity != nil {
                    Text("No activity yet.").foregroundStyle(.secondary)
                } else if failed {
                    Text("Couldn’t load activity.").foregroundStyle(.secondary)
                } else {
                    connectionStatus("Loading…")
                }
            } footer: {
                Text("My Journal records which tools the agent used, not what it searched for or read.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Recent Activity")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            do { activity = try await controller.activity(model, agent: agent) } catch { failed = true }
        }
    }
}
