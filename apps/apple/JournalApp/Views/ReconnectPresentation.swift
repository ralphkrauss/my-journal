import SwiftUI

/// Reconnect from a sync message (Sync Status, the Mac's toolbar): Connect to a Server over the window, for this
/// device's own server.
struct ReconnectPresentation: ViewModifier {
    @ObservedObject var model: AppModel
    func body(content: Content) -> some View {
        content
            .sheet(
                isPresented: Binding(
                    get: { model.reconnectRequested && !model.locked }, set: { model.reconnectRequested = $0 })
            ) {
                ConnectionView().environmentObject(model)
            }
    }
}
