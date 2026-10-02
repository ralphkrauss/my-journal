import Foundation
import Network
import os

/// A minimal HTTP server on the loopback address, for tests that must control exactly what a journal server
/// answers. It records every request, so a test can prove that something was never sent.
final class FakeJournalServer {
    struct Request: Sendable {
        let method: String
        let path: String
        let body: Data
    }
    typealias Responder = @Sendable (Request) -> (status: Int, body: Data)

    private let listener: NWListener
    private let log = OSAllocatedUnfairLock<[Request]>(initialState: [])
    private(set) var address = ""

    init(respond: @escaping Responder) async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "FakeJournalServer")
        let log = log
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            Self.receive(on: connection, buffer: Data()) { request in
                log.withLock { $0.append(request) }
                return respond(request)
            }
        }
        let listener = listener
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            listener.stateUpdateHandler = { state in
                let value: Result<UInt16, Error>?
                switch state {
                case .ready: value = listener.port.map { .success($0.rawValue) } ?? .failure(URLError(.badURL))
                case .failed(let error): value = .failure(error)
                default: value = nil
                }
                guard let value else { return }
                let first = resumed.withLock { done -> Bool in
                    let first = !done
                    done = true
                    return first
                }
                if first { continuation.resume(with: value) }
            }
            listener.start(queue: queue)
        }
        address = "http://127.0.0.1:\(port)"
    }

    deinit { listener.cancel() }

    var requests: [Request] { log.withLock { $0 } }

    /// Reads one request (headers and a Content-Length body), answers it and closes the connection.
    private static func receive(
        on connection: NWConnection, buffer: Data, handle: @escaping @Sendable (Request) -> (status: Int, body: Data)
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, complete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            guard error == nil else {
                connection.cancel()
                return
            }
            guard let request = parse(buffer) else {
                if complete {
                    connection.cancel()
                } else {
                    receive(on: connection, buffer: buffer, handle: handle)
                }
                return
            }
            let answer = handle(request)
            var response = Data(
                ("HTTP/1.1 \(answer.status) Test\r\nContent-Type: application/json\r\n"
                    + "Content-Length: \(answer.body.count)\r\nConnection: close\r\n\r\n").utf8)
            response.append(answer.body)
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private static func parse(_ buffer: Data) -> Request? {
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let lines = String(decoding: buffer[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let start = lines.first?.split(separator: " ") ?? []
        guard start.count >= 2 else { return nil }
        let length =
            lines.dropFirst().compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, parts[0].lowercased() == "content-length" else { return nil }
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }.first ?? 0
        let body = buffer[end.upperBound...]
        guard body.count >= length else { return nil }
        return Request(method: String(start[0]), path: String(start[1]), body: Data(body.prefix(length)))
    }
}
