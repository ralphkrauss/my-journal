import CJournalArchive
import XCTest
import os

@testable import JournalCore

/// Smaller defences of the archive reader: the inflater's length guard, a named pipe where a file should be, and the
/// folder a restore may remove.
final class ArchiveReaderHardeningTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func setUp() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    /// zlib counts in `unsigned int`. A length above that must be refused, not cut to its low 32 bits: 5 GiB would
    /// have become 1 GiB. The stream here is a complete empty stored block, which zlib would accept from 5 bytes.
    func testTheInflaterRefusesLengthsThatDoNotFitZlib() throws {
        let inflater = try XCTUnwrap(journal_inflater_create())
        defer { journal_inflater_destroy(inflater) }
        let stream: [UInt8] = [0x01, 0x00, 0x00, 0xFF, 0xFF]
        var output = [UInt8](repeating: 0, count: 8)
        var consumed = 99
        var produced = 99
        let tooLong = stream.withUnsafeBufferPointer { input in
            output.withUnsafeMutableBufferPointer { out in
                journal_inflater_step(
                    inflater, input.baseAddress, 5 << 30, out.baseAddress, out.count, &consumed, &produced)
            }
        }
        XCTAssertEqual(tooLong, -1)
        XCTAssertEqual(consumed, 0)
        XCTAssertEqual(produced, 0)
        let fine = stream.withUnsafeBufferPointer { input in
            output.withUnsafeMutableBufferPointer { out in
                journal_inflater_step(
                    inflater, input.baseAddress, input.count, out.baseAddress, out.count, &consumed, &produced)
            }
        }
        XCTAssertEqual(fine, 1)
        XCTAssertEqual(consumed, stream.count)
    }

    /// Opening a named pipe for reading waits until something writes to it. A reader that checks the type after the open
    /// would hang on a pipe put where the archive was; it must refuse the pipe without waiting.
    func testANamedPipeInPlaceOfTheArchiveIsRefusedWithoutWaiting() {
        let pipe = root.appendingPathComponent("pipe.journalarchive")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        let finished = expectation(description: "the pipe is refused")
        let outcome = OSAllocatedUnfairLock(initialState: "still waiting")
        DispatchQueue.global().async {
            do {
                _ = try ArchiveInput(path: pipe.path)
                outcome.withLock { $0 = "opened" }
            } catch {
                outcome.withLock { $0 = ConformanceContainerTests.outcome(of: error) }
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 10)
        // If the reader is still waiting for a writer, let it go so the thread ends.
        let writer = open(pipe.path, O_WRONLY | O_NONBLOCK)
        if writer >= 0 { close(writer) }
        XCTAssertEqual(outcome.withLock { $0 }, "damaged")
    }

    /// A folder that is there already is an error, and a failed restore never removes it: it was not the restore's.
    func testARestoreNeverRemovesAFolderItDidNotCreate() async throws {
        let existing = root.appendingPathComponent("import-existing")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
        let marker = existing.appendingPathComponent("keep")
        try Data("mine".utf8).write(to: marker)
        XCTAssertThrowsError(try StagingFolder.create(at: existing)) {
            XCTAssertEqual(ConformanceContainerTests.outcome(of: $0), "damaged")
        }
        XCTAssertEqual(try Data(contentsOf: marker), Data("mine".utf8))

        let source = Conformance.url("archive/v2/encrypted.zip")
        let archives = try XCTUnwrap(Conformance.object("archive/v2/expected.json")["archives"] as? [String: Any])
        let encrypted = try XCTUnwrap(archives["encrypted"] as? [String: Any])
        let password = try XCTUnwrap(encrypted["password"] as? String)
        for phrase in [password, "a wrong password"] {
            do {
                _ = try await VaultArchive.restore(from: source, to: existing, phrase: phrase)
                XCTFail("an existing folder must be refused")
            } catch {}
            XCTAssertEqual(try Data(contentsOf: marker), Data("mine".utf8))
        }
    }

    /// The parent of the staging folder is not made for the restore: a missing one is an error, not a tree to create.
    func testTheStagingFolderIsCreatedWithoutItsParent() async throws {
        let parent = root.appendingPathComponent("missing")
        XCTAssertThrowsError(try StagingFolder.create(at: parent.appendingPathComponent("import-x")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.path))
    }
}
