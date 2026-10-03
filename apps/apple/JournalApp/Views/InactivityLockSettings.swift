import SwiftUI

extension View {
    /// While `running`, an action the person started is in progress, so My Journal doesn't lock for inactivity; the
    /// time starts again when it ends (docs/design/mac-inactivity-lock-2026-10-03.md). Nothing on iPhone and iPad.
    func keepsUnlockedWhile(_ running: Bool) -> some View {
        modifier(InactivityHold(running: running))
    }

    /// Saves typed content before My Journal locks, which closes the sheet (LockSaving.swift).
    func savesBeforeLocking(_ save: @escaping @MainActor () async -> Void) -> some View {
        modifier(SaveBeforeLocking(save: save))
    }
}

private struct InactivityHold: ViewModifier {
    @EnvironmentObject private var model: AppModel
    let running: Bool
    @State private var holder = UUID()
    func body(content: Content) -> some View {
        #if os(macOS)
            content
                .onAppear { model.inactivityLock?.hold(running, by: holder) }
                .onValueChange(of: running) { model.inactivityLock?.hold($0, by: holder) }
                .onDisappear { model.inactivityLock?.hold(false, by: holder) }
        #else
            content
        #endif
    }
}

private struct SaveBeforeLocking: ViewModifier {
    @EnvironmentObject private var model: AppModel
    let save: @MainActor () async -> Void
    @State private var holder = UUID()
    func body(content: Content) -> some View {
        content
            .onAppear { model.savesBeforeLocking[holder] = save }
            .onDisappear { model.savesBeforeLocking[holder] = nil }
    }
}

extension AppModel {
    /// The footer's sentence about locking by itself on the Mac, with a leading space, or nothing.
    var automaticLockSentence: String {
        #if os(macOS)
            guard appLockOn else { return "" }
            return inactivityLockMinutes > 0
                ? " It also locks when you haven’t used it for the time you choose, and when your Mac sleeps or its screen locks."
                : " It also locks when your Mac sleeps or its screen locks."
        #else
            return ""
        #endif
    }
}

#if os(macOS)
    /// Settings ▸ Privacy ▸ App Lock ▸ Lock when inactive (docs/design/mac-inactivity-lock-2026-10-03.md).
    struct InactivityLockPicker: View {
        @EnvironmentObject private var model: AppModel
        /// The choice the pop-up shows while the system asks, before it's saved.
        @State private var requested: Int?
        @State private var failed = false

        var body: some View {
            Picker(
                "Lock when inactive",
                selection: Binding(get: { requested ?? model.inactivityLockMinutes }, set: { change($0) })
            ) {
                ForEach(choices, id: \.self) { minutes in
                    Text(Self.title(minutes)).tag(minutes)
                }
            }
            .disabled(requested != nil)
            .alert("Couldn’t Change Setting", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Try again.")
            }
        }

        /// The standard choices, with Never last, and a stored time that isn't one of them.
        private var choices: [Int] {
            let current = model.inactivityLockMinutes
            var times = InactivityLock.choices.filter { $0 > 0 }
            if current > 0 && !times.contains(current) { times = (times + [current]).sorted() }
            return times + [0]
        }

        /// "For 30 minutes", "For 1 hour" or "Never", as in System Settings ▸ Lock Screen.
        static func title(_ minutes: Int) -> String {
            guard minutes > 0 else { return "Never" }
            if minutes % 60 == 0 {
                let hours = minutes / 60
                return hours == 1 ? "For 1 hour" : "For \(hours) hours"
            }
            return minutes == 1 ? "For 1 minute" : "For \(minutes) minutes"
        }

        private func change(_ minutes: Int) {
            guard requested == nil, minutes != model.inactivityLockMinutes else { return }
            requested = minutes
            Task {
                let result = await model.setInactivityLock(minutes: minutes)
                requested = nil
                if result == .notSaved { failed = true }
            }
        }
    }
#endif
