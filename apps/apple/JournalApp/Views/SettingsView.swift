import JournalCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var connect: ConnectionRequest?
    /// Changes when a Connect or Reconnect sheet opened from Sync closes, so Devices reads its list again.
    @State private var devicesReload = 0
    @State private var reviewingConflict: ConflictVersion?
    @StateObject private var serverAgents = ServerAgentsController()
    #if os(iOS)
        /// The pane shown, so Sync Status can open Settings at Sync.
        @State private var panes: [AppSettingsTab] = []
    #endif
    @AppStorage(MarkdownShortcuts.settingKey) private var formatAsYouType = true
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif
    var body: some View {
        Group {
            if model.locked {
                Text("Unlock My Journal to open Settings.").foregroundStyle(.secondary).padding()
            } else if model.showsLibraryProblem {
                // Settings need a library, and Erase is on the problem screen, so no controls are shown greyed out.
                Text("Settings are available once your journals open.").foregroundStyle(.secondary).padding()
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
                    tab(.privacy, "Privacy", symbol: "hand.raised")
                    tab(.backup, "Backup", symbol: "externaldrive")
                    tab(.agents, "Agent Access", symbol: "person.badge.key")
                }
            #else
                List {
                    Section {
                        row(.general, "General", symbol: "gearshape")
                        row(.sync, "Sync", symbol: "arrow.triangle.2.circlepath")
                        row(.privacy, "Privacy", symbol: "hand.raised")
                        row(.backup, "Backup", symbol: "externaldrive")
                        row(.agents, "Agent Access", symbol: "person.badge.key")
                    }
                    // The privacy policy and the project's pages (docs/design/about-and-ratings-2026-10-05.md §1).
                    AboutSection()
                    // A standalone function, in a last section of its own, as iOS Settings ends General with Transfer
                    // or Reset iPhone (docs/design/erase-device-2026-10-04.md §1).
                    EraseSection { closeAfterErasing() }
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            #endif
        }
        .sheet(item: $connect, onDismiss: { devicesReload += 1 }) { _ in ConnectionView() }
        .sheet(item: $reviewingConflict) { ConflictReview(id: $0.id) }
        .onValueChange(of: model.locked) { locked in
            if locked { reviewingConflict = nil }
        }
    }
    #if os(macOS)
        private func tab(_ tab: AppSettingsTab, _ title: String, symbol: String) -> some View {
            // Each tab is as tall as its content, so the window resizes with the tab as in Apple's apps, but never
            // taller than the screen allows; longer content scrolls. Tabs that present sheets keep enough height
            // for them, so a sheet never extends past the window. Sync gains and loses sections as the connection
            // changes and the device list arrives, so it has one height and scrolls inside it.
            paneContent(tab).tabItem { Label(title, systemImage: symbol) }.tag(tab)
        }
        @ViewBuilder private func paneContent(_ tab: AppSettingsTab) -> some View {
            let content = pane(tab).modifier(BouncesOnlyWhenScrollable()).frame(width: 560)
            if tab == .sync {
                content.frame(height: min(Self.syncPaneHeight, maxPaneHeight), alignment: .top)
            } else {
                content.frame(minHeight: tab == .general ? nil : 440, maxHeight: maxPaneHeight, alignment: .top)
                    .fixedSize()
            }
        }
        private static let syncPaneHeight: CGFloat = 640
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
            case .general: return "General"
            case .sync: return "Sync"
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
        case .privacy: privacySettings
        case .backup:
            Form {
                ArchiveControls()
                MarkdownExportSection()
            }.formStyle(.grouped)
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
            #if os(macOS)
                // At the end of General in a group of its own, as System Settings ends General with Transfer or
                // Reset (docs/design/erase-device-2026-10-04.md §1).
                EraseSection { closeAfterErasing() }
            #endif
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
                    notConnectedFooter
                } else if let footer = model.libraryFooter {
                    Text(footer)
                }
            }
            ConflictSettingsSection { reviewingConflict = $0 }
            if model.connection != nil {
                // Absent when the server doesn't accept this device: the Server section says why.
                if !model.serverRefusesThisDevice { DevicesSection(reload: devicesReload) }
                StopSyncingSection(activity: model.syncActivity)
            }
        }.formStyle(.grouped)
    }
    /// Where a server comes from, or why this Mac stopped syncing with the server it once ran
    /// (docs/design/client-only-mac-lists-markdown-2026-10-05.md §1.1–1.2).
    private var notConnectedFooter: Text {
        #if os(macOS)
            if model.configuration?.stoppedSyncingWithFormerMacServer == true {
                return Text(
                    "My Journal no longer runs a server on this Mac, so this Mac stopped syncing. Your journals are saved on this Mac. To sync again, connect to a server.\n"
                ) + AboutLink.link("Learn More", to: AboutLink.formerMacServerGuide)
            }
        #endif
        return Text(
            "Your journals are saved on this device. To sync them with your other devices, connect to a server.\n")
            + AboutLink.link("How to Set Up a Server", to: AboutLink.syncGuide)
    }
    private var privacySettings: some View {
        Form {
            // Without a library (just erased, while Settings closes) there is no protection to describe.
            if model.configuration != nil {
                EncryptionSettingsSection(upgrade: model.encryption) { connect = ConnectionRequest() }
                AppLockSettingsSection { dismiss() }
            }
        }.formStyle(.grouped)
    }
    /// After Erase Journals and Settings, the window shows the first-launch screen; Settings has nothing to show.
    private func closeAfterErasing() {
        #if os(macOS)
            if !model.hasJournalWindow { openWindow(id: JournalApp.windowID) }
        #else
            Task {
                // Once the sheet has gone, VoiceOver moves to the first-launch screen.
                try? await Task.sleep(for: .milliseconds(600))
                JournalAccessibility.screenChanged()
            }
        #endif
        dismiss()
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
