import Foundation

/// What a window shows, in order of precedence: opening progress, the lock screen, the library problem screen, the
/// first-launch screen, the recovery key of a new library, and the journals.
enum WindowScreen: Equatable {
    case opening, locked, libraryProblem, welcome, recoveryKey, journals
}

struct WindowRouting: Equatable {
    var loaded = false
    var locked = false
    var libraryProblem = false
    var hasLibrary = false
    var recoveryKey = false

    var screen: WindowScreen {
        if !loaded { return .opening }
        if locked { return .locked }
        if libraryProblem { return .libraryProblem }
        if !hasLibrary { return .welcome }
        if recoveryKey { return .recoveryKey }
        return .journals
    }
}

extension AppModel {
    var windowRouting: WindowRouting {
        WindowRouting(
            loaded: loaded, locked: locked, libraryProblem: showsLibraryProblem && shownLibraryProblem != nil,
            hasLibrary: store != nil, recoveryKey: recoveryKey != nil)
    }
}
