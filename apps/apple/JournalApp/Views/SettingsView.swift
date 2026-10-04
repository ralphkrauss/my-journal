import JournalCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var connect: ConnectionRequest?
    @State private var reviewingConflict: ConflictVersion?
    @StateObject private var serverAgents = ServerAgentsController()
    #if os(iOS)
        /// The pane shown, so Sync Status can open Settings at Sync.
        @State private var panes: [AppSettingsTab] = []
    #endif
    @AppStorage(MarkdownShortcuts.settingKey) private var formatAsYouType = true
    var body: some View {
        Group {
            if model.locked {
                Text("Unlock My Journal to open Settings.").foregroundStyle(.secondary).padding()
            } else {
                #if os(iOS)
                    NavigationStack(path: $panes) {
                        settings.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                            .navigationDestination(for: AppSettingsTab.self) { tab in
                                pane(tab).navigationTitle(Self.title(tab))
                            }
                    }
                    .onAppear {
                        if let tab = model.settingsRequestedTab {
                            panes = [tab]
                            model.settingsRequestedTab = nil
                        }
                    }
                #else
                    settings
                #endif
            }
        }
    }
    private var settings: some View {
        Group {
            #if os(macOS)
                // A standard Settings window: toolbar tabs, each titled by its name.
                TabView(selection: $model.settingsTab) {
                    tab(.general, "General", symbol: "gearshape")
                    tab(.sync, "Sync", symbol: "arrow.triangle.2.circlepath")
                    tab(.devices, "Devices", symbol: "laptopcomputer.and.iphone")
                    tab(.privacy, "Privacy", symbol: "hand.raised")
                    tab(.backup, "Backup", symbol: "externaldrive")
                    tab(.agents, "Agent Access", symbol: "person.badge.key")
                }
            #else
                List {
                    row(.general, "Writing", symbol: "square.and.pencil")
                    row(.sync, "Sync", symbol: "arrow.triangle.2.circlepath")
                    row(.devices, "Devices", symbol: "laptopcomputer.and.iphone")
                    row(.privacy, "Privacy", symbol: "hand.raised")
                    row(.backup, "Backup", symbol: "externaldrive")
                    row(.agents, "Agent Access", symbol: "person.badge.key")
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            #endif
        }
        .sheet(item: $connect) { _ in ConnectionView() }
        .sheet(item: $reviewingConflict) { ConflictReview(id: $0.id) }
        .onValueChange(of: model.locked) { locked in
            if locked { reviewingConflict = nil }
        }
    }
    #if os(macOS)
        private func tab(_ tab: AppSettingsTab, _ title: String, symbol: String) -> some View {
            // Each tab is as tall as its content, so the window resizes with the tab as in Apple's apps, but never
            // taller than the screen allows; longer content scrolls. Tabs that present sheets keep enough height
            // for them, so a sheet never extends past the window.
            pane(tab).modifier(BouncesOnlyWhenScrollable()).frame(width: 560)
                .frame(minHeight: tab == .general ? nil : 440, maxHeight: maxPaneHeight, alignment: .top).fixedSize()
                .tabItem { Label(title, systemImage: symbol) }.tag(tab)
        }
        /// The screen's usable height, less room for the window's title bar and tabs.
        private var maxPaneHeight: CGFloat {
            max(440, (NSScreen.main?.visibleFrame.height ?? 800) - 120)
        }
    #else
        private func row(_ tab: AppSettingsTab, _ title: String, symbol: String) -> some View {
            NavigationLink(value: tab) { Label(title, systemImage: symbol) }
        }
        private static func title(_ tab: AppSettingsTab) -> String {
            switch tab {
            case .general: return "Writing"
            case .sync: return "Sync"
            case .devices: return "Devices"
            case .privacy: return "Privacy"
            case .backup: return "Backup"
            case .agents: return "Agent Access"
            }
        }
    #endif
    @ViewBuilder private func pane(_ tab: AppSettingsTab) -> some View {
        switch tab {
        case .general: generalSettings
        case .sync: syncSettings
        case .devices: DevicesView()
        case .privacy: privacySettings
        case .backup: Form { ArchiveControls() }.formStyle(.grouped)
        case .agents: agentSettings
        }
    }
    private var generalSettings: some View {
        Form {
            if !model.journals.isEmpty { defaultJournalSection }
            Section {
                #if os(macOS)
                    Toggle("Format Markdown as you type", isOn: $formatAsYouType)
                #else
                    Toggle("Format Markdown as You Type", isOn: $formatAsYouType)
                #endif
            } footer: {
                Text(
                    "Typing “- ”, “1. ”, “# ” or “> ” at the start of a line formats it. Press Delete right after to keep what you typed."
                )
            }
        }.formStyle(.grouped)
    }
    /// Where New Entry files an entry outside a journal (docs/design/default-journal.md).
    private var defaultJournalSection: some View {
        let selection = Binding<UUID?>(
            get: { model.defaultJournal?.id },
            set: { id in if let id { model.chooseDefaultJournal(id) } })
        return Section {
            Picker(selection: selection) {
                ForEach(model.journals) { journal in
                    Text(journal.title.isEmpty ? "Untitled Journal" : journal.title).tag(UUID?.some(journal.id))
                }
            } label: {
                #if os(macOS)
                    Text("Default journal")
                #else
                    Text("Default Journal")
                #endif
            }
        } footer: {
            Text("Used for new entries you create outside a journal.")
        }
    }
    private var syncSettings: some View {
        Form {
            #if os(macOS)
                LocalServerSection(controller: model.localServer)
                if model.connection != nil && !model.localServer.isConfigured {
                    StopSyncingSection(activity: model.syncActivity)
                }
            #else
                Section {
                    if let connection = model.connection {
                        Text(connection.address).textSelection(.enabled)
                        SyncNowRows(activity: model.syncActivity) { connect = ConnectionRequest() }
                    } else {
                        Button("Connect to a Server…") { connect = ConnectionRequest() }
                    }
                } header: {
                    Text("Server")
                } footer: {
                    if model.connection != nil && model.saveFailure {
                        Text(SyncPauseNotice.saveFailed)
                    } else if let error = model.syncError {
                        Text(error)
                    } else if model.connection == nil {
                        Text("Your journals are saved on this device.")
                    } else if let footer = model.libraryFooter {
                        Text(footer)
                    }
                }
                if model.connection != nil { StopSyncingSection(activity: model.syncActivity) }
            #endif
            ConflictSettingsSection { reviewingConflict = $0 }
        }.formStyle(.grouped)
    }
    private var privacySettings: some View {
        Form {
            EncryptionSettingsSection(upgrade: model.encryption) { connect = ConnectionRequest() }
            AppLockSettingsSection { dismiss() }
        }.formStyle(.grouped)
    }
    /// Agents connect through the sync server's MCP endpoint (docs/design/agent-access-simplified.md).
    private var agentSettings: some View {
        Form {
            ServerAgentsSections(controller: serverAgents)
        }
        .formStyle(.grouped)
        .modifier(ServerAgentsPresentation(controller: serverAgents))
    }
}

struct ConflictNotice: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let id: UUID
    @State private var review = false
    var body: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout())
        layout {
            Text("This entry has changes from another device.").font(.callout)
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            Button("Review Changes") {
                Task {
                    if await model.flush() {
                        try? await model.refresh()
                        review = true
                    }
                }
            }
        }.padding().background(.quaternary, ignoresSafeAreaEdges: [])
            .sheet(isPresented: $review) { ConflictReview(id: id) }
    }
}

#if os(macOS)
    /// A pane whose content fits doesn't rubber-band when scrolled.
    private struct BouncesOnlyWhenScrollable: ViewModifier {
        func body(content: Content) -> some View {
            if #available(macOS 13.3, *) {
                content.scrollBounceBehavior(.basedOnSize)
            } else {
                content
            }
        }
    }
#endif
