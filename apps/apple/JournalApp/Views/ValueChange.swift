import SwiftUI

extension View {
    /// Runs `action` with the new value when `value` changes. macOS 14 deprecates `onChange(of:perform:)`, and its
    /// replacement needs iOS 17, while the iOS app supports iOS 16.
    func onValueChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        #if os(macOS)
            onChange(of: value) { _, newValue in action(newValue) }
        #else
            onChange(of: value, perform: action)
        #endif
    }
}
