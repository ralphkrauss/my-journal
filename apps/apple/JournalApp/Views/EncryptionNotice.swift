import SwiftUI

/// The notice above the journals while they are encrypted, after a failure, and while an unfinished switch waits
/// (docs/design/1-1-encryption-and-passwords.md §3.4). The journals stay readable; writing is paused with this as the
/// reason. Device-neutral: one notice at the top of the Mac's journal window, and above the content of every
/// stacked screen and column on iPhone and iPad.
struct EncryptionNotice: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var upgrade: EncryptionUpgrade
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var confirmingStop = false

    var body: some View {
        if upgrade.showsNotice {
            VStack(alignment: .leading, spacing: 12) {
                if let phase = upgrade.phase {
                    working(phase)
                } else if upgrade.unfinished {
                    stopped(
                        message: EncryptionUpgrade.unfinishedMessage(host: upgrade.host), adopting: true)
                } else if let message = upgrade.noticeError {
                    stopped(message: message, adopting: false)
                }
            }
            .padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, ignoresSafeAreaEdges: .top)
            .accessibilityElement(children: .contain)
            .confirmationDialog(
                "Stop syncing with \(upgrade.host)?", isPresented: $confirmingStop, titleVisibility: .visible
            ) {
                Button("Stop Syncing") { upgrade.stopSyncing() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(EncryptionStopSyncing.message(model: model, host: upgrade.host, adopting: upgrade.unfinished))
            }
        }
    }

    // MARK: Working

    @ViewBuilder private func working(_ phase: EncryptionPhase) -> some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top))
        layout {
            VStack(alignment: .leading, spacing: 8) {
                Text("Writing is paused while your journals are encrypted.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                status(phase)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 12) }
            cancel
        }
    }
    @ViewBuilder private func status(_ phase: EncryptionPhase) -> some View {
        switch phase {
        case .syncing: connectionStatus("Syncing…")
        case .encrypting(let fraction): EncryptionProgressRow(fraction: fraction)
        case .updatingServer: connectionStatus("Updating \(upgrade.host)…")
        }
    }
    @ViewBuilder private var cancel: some View {
        let button = Button("Cancel") { upgrade.cancel() }
            .disabled(!upgrade.canCancel).accessibilityLabel("Cancel encryption")
        #if os(macOS)
            button.keyboardShortcut(.cancelAction)
        #else
            button
        #endif
    }

    // MARK: Failed and unfinished

    @ViewBuilder private func stopped(message: String, adopting: Bool) -> some View {
        Text(message).font(.callout).foregroundStyle(adopting ? Color.primary : Color.red)
            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 16))
        layout {
            if upgrade.noticeOffersTryAgain {
                Button("Try Again") { upgrade.tryAgain() }.disabled(upgrade.busy)
            }
            if upgrade.noticeOffersNotNow {
                Button("Not Now") { upgrade.notNow() }.disabled(upgrade.busy)
            }
            if upgrade.noticeOffersStopSyncing {
                Button("Stop Syncing…") { confirmingStop = true }.disabled(upgrade.busy)
            }
        }
    }
}
