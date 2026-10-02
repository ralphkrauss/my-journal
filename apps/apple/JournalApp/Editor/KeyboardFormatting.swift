import SwiftUI

#if os(iOS)
    import UIKit

    @MainActor
    enum KeyboardFormatting {
        static func commands(action: Selector) -> [UIKeyCommand] {
            var commands = [UIKeyCommand]()
            for input in ["b", "i", "u", "k"] {
                commands.append(UIKeyCommand(input: input, modifierFlags: .command, action: action))
            }
            for input in ["x"] {
                commands.append(UIKeyCommand(input: input, modifierFlags: [.command, .shift], action: action))
            }
            for input in 0...6 {
                commands.append(
                    UIKeyCommand(input: String(input), modifierFlags: [.command, .alternate], action: action))
            }
            commands.append(UIKeyCommand(input: "\r", modifierFlags: [.command, .shift], action: action))
            return commands
        }
        static func command(for key: UIKeyCommand) -> EditorCommand? {
            switch key.input {
            case "\r": return .toggleTask
            case "b": return .bold
            case "i": return .italic
            case "u": return .underline
            case "k": return .linkDialog
            case "x": return .strikethrough
            case "0": return .paragraph("paragraph")
            case "1": return .paragraph("heading")
            case "2": return .paragraph("subheading")
            case "3", "4", "5", "6": return .paragraph("heading" + (key.input ?? ""))
            default: return nil
            }
        }
    }
#endif
