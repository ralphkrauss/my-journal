#if os(macOS)
    import Darwin
    import Foundation
    import JournalCore

    /// A process identified by its ID, start time and program, so a later process that reuses the ID never matches.
    struct ProcessIdentity: Codable, Equatable {
        var pid: Int32
        var startSeconds: UInt64
        var startMicroseconds: UInt64
        var executable: String

        /// The identity of a running process, or nil when there is none (or it can't be inspected).
        init?(running pid: pid_t) {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
            self.pid = pid
            startSeconds = info.pbi_start_tvsec
            startMicroseconds = info.pbi_start_tvusec
            executable = String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        var isRunning: Bool { ProcessIdentity(running: pid) == self }
    }

    /// The bundled server this app started, and the app that started it. If the app ends without stopping the
    /// server (a crash or Force Quit), the next launch stops that server, but never one whose app is still running.
    struct ServerProcessRecord: Codable, Equatable {
        var server: ProcessIdentity
        var owner: ProcessIdentity

        var isOrphaned: Bool { server.isRunning && !owner.isRunning }

        static func read(from url: URL) -> ServerProcessRecord? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JournalCoding.decoder().decode(ServerProcessRecord.self, from: data)
        }
        func write(to url: URL) throws {
            try JournalCoding.encoder().encode(self).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    @MainActor
    enum ProcessStopping {
        /// Asks a process to stop, then forces it after `grace` seconds. Returns whether it ended.
        static func stop(
            _ pid: pid_t, grace: TimeInterval, isRunning: @MainActor () -> Bool
        ) async -> Bool {
            kill(pid, SIGTERM)
            if await waitForExit(seconds: grace, isRunning: isRunning) { return true }
            kill(pid, SIGKILL)
            return await waitForExit(seconds: 2, isRunning: isRunning)
        }
        private static func waitForExit(
            seconds: TimeInterval, isRunning: @MainActor () -> Bool
        ) async -> Bool {
            for _ in 0..<max(1, Int(seconds * 10)) {
                if !isRunning() { return true }
                // Cancellation must not cut short stopping a process.
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { continuation.resume() }
                }
            }
            return !isRunning()
        }
    }
#endif
