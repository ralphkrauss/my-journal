import Foundation

/// What a window shows, in order of precedence (docs/design/1-1-encryption-and-passwords.md §3.4). The form that asks
/// an unencrypted library to encrypt comes after the first-launch screen and before the journals; a saved encryption
/// marker with the server switched, or a run in progress, shows the journals (read-only, with the notice) instead of
/// the form, so a library whose server already switched is allowed to finish first.
enum WindowScreen: Equatable {
    case opening, locked, libraryProblem, welcome, encryptForm, recoveryKey, journals
}

struct WindowRouting: Equatable {
    var loaded = false
    var locked = false
    var libraryProblem = false
    var hasLibrary = false
    /// A run, a failed run, an unfinished switch, or a marker whose server switched.
    var encryptionInProgress = false
    /// The library isn't encrypted and nothing was decided for this launch.
    var needsEncryption = false
    var recoveryKey = false

    var screen: WindowScreen {
        if !loaded { return .opening }
        if locked { return .locked }
        if libraryProblem { return .libraryProblem }
        if !hasLibrary { return .welcome }
        if encryptionInProgress { return .journals }
        if needsEncryption { return .encryptForm }
        if recoveryKey { return .recoveryKey }
        return .journals
    }
}

extension AppModel {
    var windowRouting: WindowRouting {
        WindowRouting(
            loaded: loaded, locked: locked, libraryProblem: showsLibraryProblem && shownLibraryProblem != nil,
            hasLibrary: store != nil, encryptionInProgress: encryption.inProgress,
            needsEncryption: encryption.wantsForm, recoveryKey: recoveryKey != nil)
    }
    /// Writing is paused while the journals are encrypted: every control that would write is disabled, and the notice
    /// above the journals says why.
    var writingPausedForEncryption: Bool { encryption.pausesWriting }
    /// The form that asks to encrypt is the window.
    var showsEncryptionForm: Bool { windowRouting.screen == .encryptForm }
    /// No sync, publishing or waiting for changes reaches a server while the form waits for the person's decision.
    var encryptionHoldsSynchronization: Bool { encryption.holdsSynchronization }
}
