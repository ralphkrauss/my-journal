import JournalCore
import SwiftUI

@main
struct JournalApp: App {
    /// The journal window. Menu commands open it again after it was closed.
    static let windowID = "journal"
    #if os(macOS)
        @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var appDelegate
    #else
        @UIApplicationDelegateAdaptor(JournalAppDelegate.self) private var appDelegate
    #endif
    @StateObject private var model = AppModel()
    @StateObject private var editor = EditorActions()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup(id: Self.windowID) {
            RootView()
                .environmentObject(model)
                .environmentObject(editor)
                .modifier(EncryptionPresentation(model: model, upgrade: model.encryption))
                .modifier(AppLockTurnedOffAlert(model: model))
                .modifier(ReviewRequestPresenter(model: model))
                .overlay {
                    // Not while App Lock's own request is showing, which makes the app briefly inactive, nor while
                    // its panel closes after the answer.
                    if scenePhase != .active && model.appLockOn && !model.unlockState.requestInFront {
                        LockedCover(model: model)
                    }
                }
                .task {
                    // The app hosting unit tests stays idle; tests drive their own models.
                    guard !AppModel.hostsTests else { return }
                    #if os(iOS)
                        PrivacyCover.shared.watch(model)
                    #endif
                    await model.load()
                    await ArchiveExportLeftovers.removeAtLaunch(
                        dataDirectory: model.directory, libraryFolders: model.libraryFolderNames)
                    #if os(macOS)
                        model.startInactivityLock()
                        LocalAgentCleanup.run(dataDirectory: model.directory)
                    #endif
                }
                // Restarted when the app returns from the background, which syncs at once.
                .task(id: scenePhase == .background) {
                    guard !AppModel.hostsTests, scenePhase != .background else { return }
                    await model.synchronizeAutomatically()
                }
                .onValueChange(of: scenePhase) { phase in
                    if phase == .background {
                        model.syncActivity.persist()
                        saveAndLock()
                    }
                }
                #if os(macOS)
                    // The entries and editor column minimums (JournalSplitViewController); a narrower window hides the
                    // sidebar, as in Notes.
                    .frame(minWidth: 801, minHeight: 420)
                    .background(WindowCloseGuard(model: model))
                    .onAppear { appDelegate.model = model }
                #endif
        }
        #if os(macOS)
            .defaultSize(width: 1100, height: 720)
            // Set here, so SwiftUI keeps the journal window's AppKit toolbar in this style on every update.
            .windowToolbarStyle(.unified(showsTitle: true))
        #endif
        .commands { JournalCommands(model: model, editor: editor) }
        #if os(macOS)
            Settings {
                SettingsView().environmentObject(model)
            }
        #endif
    }

    private func saveAndLock() {
        #if os(iOS)
            // Lock before anything else, so no journal content is shown again. iOS may suspend the app soon after
            // it leaves the screen; ask for time to save first.
            model.applicationEnteredBackground()
            BackgroundActivity.run("Save and lock") { await model.saveWhileLocked() }
        #else
            Task {
                _ = await model.flush()
                await model.sendWriting()
            }
        #endif
    }
}
