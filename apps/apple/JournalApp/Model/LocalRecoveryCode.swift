#if os(macOS)
    import Foundation
    import JournalCore

    enum LocalRecoveryCode {
        static func create(executable: URL, directory: URL) async throws -> String {
            try await Task.detached {
                try Task.checkCancellation()
                let process = Process()
                let output = Pipe()
                process.executableURL = executable
                process.arguments = ["--recovery-code"]
                var environment = ProcessInfo.processInfo.environment
                environment["Journal__DataDirectory"] = directory.path
                environment["DOTNET_EnableDiagnostics"] = "0"
                process.environment = environment
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                try process.run()
                defer { if process.isRunning { process.terminate() } }
                let bytes = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                try Task.checkCancellation()
                let code = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                guard process.terminationStatus == 0, code.count == 64, code.allSatisfy({ $0.isHexDigit }) else {
                    throw JournalError.server("Couldn’t reconnect to this Mac’s server. Try again.")
                }
                return code
            }.value
        }
    }
#endif
