import SwiftUI

/// “Your Journals Can’t Be Opened” and “Update My Journal” (docs/design/build-18-fixes-2026-10-06.md §2.1): what the
/// window shows when the journals on this device can't be opened. It stands on its own, without authentication, and
/// shows nothing about the journals or the server. The same layout as the lock screen and the welcome screen.
struct LibraryProblemView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    let problem: LibraryProblem
    /// The last Try Again ended in a problem again, until the next attempt starts.
    @State private var stillClosed = false
    @AccessibilityFocusState private var titleFocused: Bool
    @AccessibilityFocusState private var tryAgainFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content.padding(32).frame(maxWidth: .infinity).frame(minHeight: geometry.size.height)
            }
        }
        // VoiceOver goes to the title, so the cause is read first, and hears the new screen once per problem.
        .onAppear(perform: announceScreen)
        .onValueChange(of: problem) { _ in announceScreen() }
        .onValueChange(of: stillClosed) { shown in
            if shown { JournalAccessibility.announce(Self.stillClosedLine) }
        }
    }

    static let stillClosedLine = "Still can’t be opened."

    private func announceScreen() {
        titleFocused = true
        #if os(iOS)
            JournalAccessibility.screenChanged()
        #endif
    }

    private var offersTryAgain: Bool { problem.offersTryAgain }
    /// Erase waits for one failed Try Again, and neither it nor Import is offered while the iPhone's protected data
    /// isn't available: opening fails then for a reason that ends by itself.
    private var offersErase: Bool {
        problem.allowsErase && (model.failedRetries > 0 || !problem.erasesAfterFailedRetry)
            && model.protectedDataAvailable
    }
    private var offersImport: Bool { problem.offersImport && model.protectedDataAvailable }

    private var content: some View {
        VStack(spacing: 18) {
            Image(systemName: problem == .newerVersion ? "arrow.down.app" : "exclamationmark.triangle")
                .font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title).font(.title2).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocused)
            ForEach(messages, id: \.self) { paragraph in
                Text(paragraph).fixedSize(horizontal: false, vertical: true)
            }
            if offersTryAgain && model.failedRetries > 0 {
                Text("Your journals may still be fine. Only erase them if this keeps happening.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            actions
        }.multilineTextAlignment(.center)
    }

    private var title: String {
        problem == .newerVersion ? "Update My Journal" : "Your Journals Can’t Be Opened"
    }

    private var messages: [String] {
        let device = DeviceUnlockMethod.deviceName
        switch problem {
        case .newerVersion:
            return [
                "These journals were saved by a newer version of My Journal. Update My Journal to open them."
            ]
        case .notEncrypted:
            return [
                "My Journal can’t open the journals on this device. Nothing has been removed.",
                "These journals aren’t encrypted, and this version of My Journal opens only encrypted journals.",
            ]
        case .settingsUnread:
            return [
                "My Journal can’t read the settings saved on this device. Nothing has been removed.",
                "If a newer version of My Journal saved these settings, update My Journal, then try again. If this keeps happening, restart your \(device).",
            ]
        default:
            return [
                "My Journal can’t open the journals on this device. Nothing has been removed.",
                "Try again. If this keeps happening, restart your \(device).",
            ]
        }
    }

    @ViewBuilder private var actions: some View {
        if model.retryingOpen {
            ProgressView("Opening Journal…")
        } else {
            if offersTryAgain { tryAgain }
            if offersImport {
                Button("Import Archive…") { model.archiveImportRequested = true }.buttonStyle(.bordered)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if offersErase { UnopenedEraseButton() }
        }
        learnMore
    }

    @ViewBuilder private var tryAgain: some View {
        Button {
            Task { await tryOpeningAgain() }
        } label: {
            Text("Try Again").fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
        .accessibilityFocused($tryAgainFocused)
        if stillClosed {
            Text(Self.stillClosedLine).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tryOpeningAgain() async {
        stillClosed = false
        await model.retryOpening()
        stillClosed = model.libraryProblem != nil
        tryAgainFocused = true
    }

    private var learnMore: some View {
        Button {
            if let url = AboutLink.cantOpenGuide { openURL(url) }
        } label: {
            Text("Learn More").fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain).foregroundStyle(.tint)
        .accessibilityHint("Opens the troubleshooting guide in your browser.")
        #if os(macOS)
            // The newer-version screen has no other button, so this one takes the Return key.
            .keyboardShortcut(problem == .newerVersion ? .defaultAction : nil)
        #endif
    }
}
