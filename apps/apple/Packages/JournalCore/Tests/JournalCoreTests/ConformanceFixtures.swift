import Foundation
import XCTest

/// Locates the cross-client conformance fixtures (protocol/conformance). They are shared with every other client's
/// tests, so they are read from the repository and never copied.
///
/// Fixtures whose expected values come from this implementation are checked as golden files: the test computes the
/// expected values from the fixture's own inputs and compares them with the file. Setting
/// `JOURNAL_CONFORMANCE_REGENERATE=1` makes the same tests rewrite those files from the inputs in the test sources,
/// which is how a deliberate contract change produces new fixtures (protocol/conformance/README.md).
enum Conformance {
    /// The repository root, found from this file: Tests/JournalCoreTests is seven levels below it.
    static let repository: URL = {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { root.deleteLastPathComponent() }
        return root
    }()
    static let directory = repository.appendingPathComponent("protocol/conformance", isDirectory: true)
    static let regenerating = ProcessInfo.processInfo.environment["JOURNAL_CONFORMANCE_REGENERATE"] == "1"

    static func url(_ path: String) -> URL { directory.appendingPathComponent(path) }
    static func data(_ path: String) throws -> Data { try Data(contentsOf: url(path)) }
    static func decode<Value: Decodable>(_ type: Value.Type, _ path: String) throws -> Value {
        try JSONDecoder().decode(type, from: data(path))
    }
    /// The fixture as untyped JSON, for fixtures whose members are checked one by one.
    static func object(_ path: String) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: data(path))
        guard let object = value as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: path])
        }
        return object
    }

    /// The fixture's text as other clients' tools read it: sorted keys, two-space indentation, a final newline.
    static func text(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    /// The fixture at `path`; when regenerating, the file is first rewritten from `generate`.
    static func fixture(_ path: String, generate: () throws -> [String: Any]) throws -> [String: Any] {
        guard regenerating else { return try object(path) }
        let value = try generate()
        try write(value, to: path)
        return value
    }

    /// Writes `value` as the fixture at `path`. Only called when regenerating.
    static func write(_ value: Any, to path: String) throws {
        let target = url(path)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text(value).utf8).write(to: target, options: .atomic)
    }

    /// Whether two JSON values are equal, however their numbers and keys happened to be written.
    static func same(_ first: Any, _ second: Any) throws -> Bool {
        try text(first) == text(second)
    }
}
