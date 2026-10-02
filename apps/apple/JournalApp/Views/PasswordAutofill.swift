import SwiftUI

extension View {
    @ViewBuilder func passwordAutofill(creating: Bool = false) -> some View {
        #if os(macOS)
            if #available(macOS 14, *) {
                textContentType(creating ? .newPassword : .password)
            } else {
                textContentType(.password)
            }
        #else
            textContentType(creating ? .newPassword : .password)
        #endif
    }
}
